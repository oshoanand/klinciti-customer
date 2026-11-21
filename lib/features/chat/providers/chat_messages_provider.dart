import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/socket/socket_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message_model.dart';
import 'chat_sessions_provider.dart';

final chatMessagesProvider = AsyncNotifierProvider.family
    .autoDispose<ChatMessagesNotifier, List<ChatMessageModel>, String>(() {
      return ChatMessagesNotifier();
    });

class ChatMessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<ChatMessageModel>, String> {
  late SocketService _socket;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final int _limit = 50;

  @override
  Future<List<ChatMessageModel>> build(String arg) async {
    _socket = ref.watch(socketServiceProvider);
    _hasMore = true;
    _isLoadingMore = false;

    _socket.listen('receive_message', _onReceiveMessage);
    _socket.listen('message_confirmed', _onMessageConfirmed);
    _socket.listen('messages_read_by_recipient', _onMessagesReadByRecipient);
    _socket.listen('read_status_synced', _onReadStatusSynced);

    ref.onDispose(() {
      _socket.stopListening('receive_message', _onReceiveMessage);
      _socket.stopListening('message_confirmed', _onMessageConfirmed);
      _socket.stopListening(
        'messages_read_by_recipient',
        _onMessagesReadByRecipient,
      );
      _socket.stopListening('read_status_synced', _onReadStatusSynced);
    });

    return _fetchMessages(offset: 0);
  }

  Future<List<ChatMessageModel>> _fetchMessages({required int offset}) async {
    final messages = await ref
        .read(chatRepositoryProvider)
        .fetchMessages(arg, limit: _limit, offset: offset);

    if (messages.length < _limit) {
      _hasMore = false;
    }
    return messages;
  }

  // ==========================================================
  // PAGINATION (LOAD OLDER MESSAGES)
  // ==========================================================
  Future<void> loadMore() async {
    if (!_hasMore ||
        _isLoadingMore ||
        !state.hasValue ||
        arg.startsWith('new_')) {
      return;
    }

    _isLoadingMore = true;

    try {
      final currentList = state.value!;
      final confirmedCount = currentList
          .where((m) => !m.id.startsWith('temp_'))
          .length;

      final olderMessages = await _fetchMessages(offset: confirmedCount);

      if (olderMessages.isNotEmpty && state.hasValue) {
        final existingIds = state.value!.map((m) => m.id).toSet();
        final uniqueOlder = olderMessages
            .where((m) => !existingIds.contains(m.id))
            .toList();

        state = AsyncValue.data([...state.value!, ...uniqueOlder]);
      }
    } catch (e) {
      log('LoadMore Messages Error: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  // ==========================================================
  // SEND MESSAGE (OPTIMISTIC UI + HTTP POST)
  // ==========================================================
  Future<String?> sendMessage({
    required String text,
    required String receiverId,
    String? imageUrl,
  }) async {
    final trimmedText = text.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    if (trimmedText.isEmpty && !hasImage) {
      return null;
    }

    final currentUserId =
        ref.read(currentUserProvider)?['id']?.toString() ?? '';
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    final tempMessage = ChatMessageModel(
      id: tempId,
      chatSessionId: arg,
      senderId: currentUserId,
      text: trimmedText.isNotEmpty ? trimmedText : null,
      imageUrl: imageUrl,
      isRead: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      isSending: true,
      isFailed: false,
    );

    if (state.hasValue) {
      state = AsyncValue.data([tempMessage, ...state.value!]);
    }

    try {
      final result = await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            sessionId: arg,
            partnerId: receiverId,
            text: trimmedText,
            imageUrl: imageUrl,
          );

      final realSessionId = result.sessionId;
      final newMessage = result.message;

      // If this was a placeholder session ('new_<adminUuid>'), upgrade it in the inbox provider
      if (arg.startsWith('new_') && !realSessionId.startsWith('new_')) {
        ref
            .read(chatSessionsProvider.notifier)
            .upgradePlaceholderSession(
              partnerId: receiverId,
              realSessionId: realSessionId,
              lastMessage: trimmedText.isNotEmpty ? trimmedText : '📷 Фото',
            );
      }

      if (state.hasValue) {
        final currentMessages = state.value!;
        final alreadyConfirmedBySocket = currentMessages.any(
          (m) => m.id == newMessage.id,
        );

        if (alreadyConfirmedBySocket) {
          final cleanedList = currentMessages
              .where((m) => m.id != tempId)
              .toList();
          state = AsyncValue.data(cleanedList);
        } else {
          final updatedList = currentMessages.map((msg) {
            return msg.id == tempId ? newMessage : msg;
          }).toList();
          state = AsyncValue.data(updatedList);
        }
      }

      return realSessionId;
    } catch (e) {
      log('Failed to send message: $e');

      if (state.hasValue) {
        final updatedList = state.value!.map((msg) {
          if (msg.id == tempId) {
            return msg.copyWith(isFailed: true, isSending: false);
          }
          return msg;
        }).toList();
        state = AsyncValue.data(updatedList);
      }
      return null;
    }
  }

  // ==========================================================
  // MARK INCOMING MESSAGES AS READ
  // ==========================================================
  void markAsRead(String senderId) {
    if (arg.startsWith('new_') || senderId.isEmpty) return;

    try {
      _socket.emit('mark_messages_read', {
        'chatSessionId': arg,
        'senderId': senderId,
      });

      // Immediately clear unread badge in the Inbox list
      ref.read(chatSessionsProvider.notifier).clearUnreadLocally(arg, senderId);

      if (state.hasValue) {
        final currentMessages = state.value!;
        final hasUnreadFromPartner = currentMessages.any(
          (msg) => msg.senderId == senderId && !msg.isRead,
        );

        if (!hasUnreadFromPartner) return;

        final updatedList = currentMessages.map((msg) {
          if (msg.senderId == senderId && !msg.isRead) {
            return msg.copyWith(isRead: true);
          }
          return msg;
        }).toList();

        state = AsyncValue.data(updatedList);
      }
    } catch (_) {}
  }

  // ==========================================================
  // SOCKET: RECEIVE MESSAGE (DEDUPLICATED & RACE-SAFE)
  // ==========================================================
  void _onReceiveMessage(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final msg = ChatMessageModel.fromJson(
        Map<String, dynamic>.from(payload as Map),
      );

      if (msg.chatSessionId != arg && !arg.startsWith('new_')) return;

      final currentMessages = state.value!;
      if (currentMessages.any((m) => m.id == msg.id)) return;

      final tempMessageIndex = currentMessages.indexWhere(
        (m) =>
            (m.isSending == true || m.id.startsWith('temp_')) &&
            m.senderId == msg.senderId &&
            (m.text ?? '').trim() == (msg.text ?? '').trim() &&
            (m.imageUrl ?? '') == (msg.imageUrl ?? ''),
      );

      if (tempMessageIndex != -1) {
        final updatedList = List<ChatMessageModel>.from(currentMessages);
        updatedList[tempMessageIndex] = msg;
        state = AsyncValue.data(updatedList);
      } else {
        state = AsyncValue.data([msg, ...currentMessages]);
      }
    } catch (_) {}
  }

  void _onMessageConfirmed(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final rawMsg = data['message'] ?? data;
      final msg = ChatMessageModel.fromJson(
        Map<String, dynamic>.from(rawMsg as Map),
      );

      if (msg.chatSessionId == arg) {
        final currentMessages = state.value!;
        if (!currentMessages.any((m) => m.id == msg.id)) {
          state = AsyncValue.data([msg, ...currentMessages]);
        }
      }
    } catch (_) {}
  }

  // ==========================================================
  // SOCKET: READ RECEIPTS
  // ==========================================================
  void _onMessagesReadByRecipient(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final sessionId =
          data['chatSessionId']?.toString() ??
          data['chat_session_id']?.toString();

      if (sessionId != null && sessionId != arg) return;

      final currentUserId =
          ref.read(currentUserProvider)?['id']?.toString() ?? '';

      final updatedList = state.value!.map((m) {
        if (m.senderId == currentUserId && !m.isRead) {
          return m.copyWith(isRead: true);
        }
        return m;
      }).toList();

      state = AsyncValue.data(updatedList);
    } catch (_) {}
  }

  void _onReadStatusSynced(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final partnerId = data['partnerId']?.toString();

      final updatedList = state.value!.map((m) {
        if ((partnerId == null || m.senderId == partnerId) && !m.isRead) {
          return m.copyWith(isRead: true);
        }
        return m;
      }).toList();

      state = AsyncValue.data(updatedList);
    } catch (_) {}
  }
}
