import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overlay_support/overlay_support.dart';

import '../../../core/socket/socket_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_session_model.dart';
import 'active_chat_provider.dart';

final chatSessionsProvider =
    AsyncNotifierProvider<ChatSessionsNotifier, List<ChatSessionModel>>(() {
      return ChatSessionsNotifier();
    });

/// Total unread messages count across all chat sessions
final totalUnreadChatCountProvider = Provider<int>((ref) {
  final sessions = ref.watch(chatSessionsProvider).valueOrNull ?? const [];
  return sessions.fold<int>(0, (sum, s) => sum + s.unreadCount);
});

class ChatSessionsNotifier extends AsyncNotifier<List<ChatSessionModel>> {
  late SocketService _socket;

  @override
  Future<List<ChatSessionModel>> build() async {
    _socket = ref.watch(socketServiceProvider);

    _socket.listen('receive_message', _onMessageReceived);
    _socket.listen('messages_read_by_recipient', _onMessagesRead);
    _socket.listen('read_status_synced', _onReadStatusSynced);
    _socket.listen('user_status_changed', _onUserStatusChanged);
    _socket.listen('user_presence', _onUserStatusChanged);
    _socket.listen('user_typing', _onUserTyping);
    _socket.listen('user_stopped_typing', _onUserStoppedTyping);

    ref.onDispose(() {
      _socket.stopListening('receive_message', _onMessageReceived);
      _socket.stopListening('messages_read_by_recipient', _onMessagesRead);
      _socket.stopListening('read_status_synced', _onReadStatusSynced);
      _socket.stopListening('user_status_changed', _onUserStatusChanged);
      _socket.stopListening('user_presence', _onUserStatusChanged);
      _socket.stopListening('user_typing', _onUserTyping);
      _socket.stopListening('user_stopped_typing', _onUserStoppedTyping);
    });

    return _fetchInitialSessions();
  }

  Future<List<ChatSessionModel>> _fetchInitialSessions() async {
    final sessions = await ref.read(chatRepositoryProvider).fetchSessions();
    return _sortSessions(sessions);
  }

  List<ChatSessionModel> _sortSessions(List<ChatSessionModel> list) {
    final copy = List<ChatSessionModel>.from(list);
    copy.sort((a, b) {
      // 1. Always keep Administrators pinned at the top
      if (a.isAdmin && !b.isAdmin) return -1;
      if (!a.isAdmin && b.isAdmin) return 1;

      // 2. Among admins, keep active conversations above uninitiated placeholders
      final aIsVirtual = a.id.startsWith('new_');
      final bIsVirtual = b.id.startsWith('new_');
      if (aIsVirtual && !bIsVirtual) return 1;
      if (!aIsVirtual && bIsVirtual) return -1;

      // 3. Sort by most recent activity
      final aDate =
          DateTime.tryParse(a.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse(b.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return copy;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchInitialSessions());
  }

  /// Immediately clears unread count locally when the user opens a session
  void clearUnreadLocally(String sessionId, String partnerId) {
    final currentSessions = state.valueOrNull;
    if (currentSessions == null) return;

    final index = currentSessions.indexWhere(
      (s) => s.id == sessionId || s.partnerId == partnerId,
    );
    if (index != -1 && currentSessions[index].unreadCount > 0) {
      final newList = List<ChatSessionModel>.from(currentSessions);
      newList[index] = newList[index].copyWith(unreadCount: 0);
      state = AsyncValue.data(newList);
    }
  }

  /// Replaces a `new_<partnerId>` placeholder session ID with the newly created DB UUID
  void upgradePlaceholderSession({
    required String partnerId,
    required String realSessionId,
    String? lastMessage,
  }) {
    final currentSessions = state.valueOrNull;
    if (currentSessions == null) return;

    final index = currentSessions.indexWhere((s) => s.partnerId == partnerId);
    if (index != -1) {
      final existing = currentSessions[index];
      final updated = existing.copyWith(
        id: realSessionId,
        lastMessage: lastMessage ?? existing.lastMessage,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      final newList = List<ChatSessionModel>.from(currentSessions);
      newList[index] = updated;
      state = AsyncValue.data(_sortSessions(newList));
    }
  }

  Future<ChatSessionModel> resolveOrInitiateSession({
    required String partnerId,
    String? fallbackName,
    String? fallbackAvatar,
  }) async {
    final currentSessions = state.valueOrNull;
    if (currentSessions != null && partnerId != 'admin') {
      final existingIndex = currentSessions.indexWhere(
        (s) => s.partnerId == partnerId && !s.id.startsWith('new_'),
      );
      if (existingIndex != -1) {
        final existing = currentSessions[existingIndex];
        return existing.copyWith(
          partnerName: existing.partnerName ?? fallbackName,
          partnerAvatar: existing.partnerAvatar ?? fallbackAvatar,
        );
      }
    }

    final session = await ref
        .read(chatRepositoryProvider)
        .initiateChat(partnerId);

    final enrichedSession = session.copyWith(
      partnerName: session.partnerName ?? fallbackName,
      partnerAvatar: session.partnerAvatar ?? fallbackAvatar,
    );

    if (state.hasValue) {
      final list = [...state.value!];
      final idx = list.indexWhere(
        (s) =>
            s.id == enrichedSession.id ||
            s.partnerId == enrichedSession.partnerId,
      );
      if (idx != -1) {
        list[idx] = enrichedSession;
      } else {
        list.insert(0, enrichedSession);
      }
      state = AsyncValue.data(_sortSessions(list));
    } else {
      await refresh();
    }

    return enrichedSession;
  }

  // ==========================================
  // INCOMING MESSAGES
  // ==========================================
  void _onMessageReceived(dynamic payload) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final sessionId =
          data['chat_session_id']?.toString() ??
          data['chatSessionId']?.toString();
      final text = data['text']?.toString();
      final senderId =
          data['sender_id']?.toString() ?? data['senderId']?.toString();

      final currentUser = ref.read(currentUserProvider);
      final currentUserId = currentUser?['id']?.toString();
      final isMe = senderId == currentUserId;

      final currentlyActiveSessionId = ref.read(activeChatSessionProvider);
      final isCurrentlyOpen =
          currentlyActiveSessionId != null &&
          (currentlyActiveSessionId == sessionId ||
              (senderId != null &&
                  currentlyActiveSessionId == 'new_$senderId'));

      if (!isMe && !isCurrentlyOpen) {
        FlutterRingtonePlayer().playNotification();

        showOverlayNotification((context) {
          return SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF3B82F6)
                        .withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.message_rounded,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                  title: const Text(
                    'Новое сообщение',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    (text != null && text.isNotEmpty) ? text : '📷 Фото',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  onTap: () {
                    OverlaySupportEntry.of(context)?.dismiss();
                  },
                ),
              ),
            ),
          );
        }, duration: const Duration(seconds: 4));
      }

      final currentSessions = state.value!;
      // Match either by exact sessionId OR by virtual placeholder partnerId
      int index = currentSessions.indexWhere((s) => s.id == sessionId);
      if (index == -1 && !isMe && senderId != null) {
        index = currentSessions.indexWhere((s) => s.partnerId == senderId);
      }

      if (index != -1) {
        final session = currentSessions[index];

        final updatedSession = session.copyWith(
          id: sessionId ?? session.id,
          lastMessage: (text != null && text.isNotEmpty) ? text : '📷 Фото',
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          unreadCount: (isMe || isCurrentlyOpen)
              ? session.unreadCount
              : session.unreadCount + 1,
          isTyping: false,
        );

        final newList = [...currentSessions];
        newList[index] = updatedSession;

        state = AsyncValue.data(_sortSessions(newList));
      } else {
        refresh();
      }
    } catch (_) {}
  }

  void _onMessagesRead(dynamic payload) {}

  void _onReadStatusSynced(dynamic payload) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final partnerId = data['partnerId']?.toString();
      final sessionId =
          data['chatSessionId']?.toString() ??
          data['chat_session_id']?.toString();

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere(
        (s) =>
            (partnerId != null && s.partnerId == partnerId) ||
            (sessionId != null && s.id == sessionId),
      );

      if (index != -1) {
        final session = currentSessions[index];
        if (session.unreadCount == 0) return;

        final newList = [...currentSessions];
        newList[index] = session.copyWith(unreadCount: 0);
        state = AsyncValue.data(newList);
      }
    } catch (_) {}
  }

  // ==========================================
  // REAL-TIME PRESENCE (Online / Offline / Last Seen)
  // ==========================================
  void _onUserStatusChanged(dynamic payload) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final userId = data['userId']?.toString();
      final isOnline = data['isOnline'] == true;
      final lastSeen = data['lastSeen']?.toString();
      if (userId == null) return;

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == userId);

      if (index != -1) {
        final session = currentSessions[index];
        if (session.isOnline == isOnline && session.lastSeen == lastSeen) {
          return;
        }

        final updatedSession = session.copyWith(
          isOnline: isOnline,
          lastSeen: isOnline ? null : (lastSeen ?? session.lastSeen),
        );

        final newList = [...currentSessions];
        newList[index] = updatedSession;
        state = AsyncValue.data(newList);
      }
    } catch (_) {}
  }

  // ==========================================
  // TYPING INDICATORS
  // ==========================================
  void _onUserTyping(dynamic payload) => _updateTypingState(payload, true);
  void _onUserStoppedTyping(dynamic payload) =>
      _updateTypingState(payload, false);

  void _updateTypingState(dynamic payload, bool isTyping) {
    if (!state.hasValue) return;

    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final userId = data['userId']?.toString();
      if (userId == null) return;

      final currentSessions = state.value!;
      final index = currentSessions.indexWhere((s) => s.partnerId == userId);

      if (index != -1) {
        final session = currentSessions[index];
        if (session.isTyping == isTyping) return;

        final newList = [...currentSessions];
        newList[index] = session.copyWith(isTyping: isTyping);
        state = AsyncValue.data(newList);
      }
    } catch (_) {}
  }
}
