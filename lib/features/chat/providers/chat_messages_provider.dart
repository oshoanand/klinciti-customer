import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/models/chat_message_model.dart';
import '../data/chat_repository.dart';
import '../../auth/providers/auth_provider.dart';

final chatMessagesProvider = AsyncNotifierProvider.family
    .autoDispose<ChatMessagesNotifier, List<ChatMessageModel>, String>(() {
      return ChatMessagesNotifier();
    });

class ChatMessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<ChatMessageModel>, String> {
  late SocketService _socket;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 50;

  @override
  Future<List<ChatMessageModel>> build(String arg) async {
    _socket = ref.watch(socketServiceProvider);

    // Setup socket listeners for real-time events
    _socket.listen('receive_message', _onReceiveMessage);
    _socket.listen('message_confirmed', _onMessageConfirmed);
    _socket.listen('read_status_synced', _onReadStatusSynced);

    ref.onDispose(() {
      _socket.stopListening('receive_message');
      _socket.stopListening('message_confirmed');
      _socket.stopListening('read_status_synced');
    });

    return _fetchMessages(offset: 0);
  }

  Future<List<ChatMessageModel>> _fetchMessages({required int offset}) async {
    try {
      final messages = await ref
          .read(chatRepositoryProvider)
          .fetchMessages(
            arg, // sessionId passed as 'arg'
            limit: _limit,
            offset: offset,
          );

      if (messages.length < _limit) {
        _hasMore = false;
      }
      return messages;
    } catch (e, st) {
      throw AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || !state.hasValue) return;

    _isLoadingMore = true;
    _offset += _limit;

    try {
      final olderMessages = await _fetchMessages(offset: _offset);
      state = AsyncValue.data([...state.value!, ...olderMessages]);
    } catch (e) {
      _offset -= _limit; // Revert offset on error
    } finally {
      _isLoadingMore = false;
    }
  }

  // ✅ UPDATED: Now handles true Optimistic UI & returns the new session ID
  Future<String?> sendMessage({
    required String text,
    required String receiverId,
    String? imageUrl,
  }) async {
    if (text.trim().isEmpty && (imageUrl == null || imageUrl.isEmpty))
      return null;

    final currentUserId =
        ref.read(currentUserProvider)?['id']?.toString() ?? '';
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Create a temporary optimistic message
    final tempMessage = ChatMessageModel(
      id: tempId,
      chatSessionId: arg,
      senderId: currentUserId,
      text: text,
      imageUrl: imageUrl,
      isRead: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      // Make sure ChatMessageModel has these optional fields, or omit them if you handle UI differently
      isSending: true,
    );

    // 2. Instantly update the UI
    if (state.hasValue) {
      state = AsyncValue.data([tempMessage, ...state.value!]);
    }

    try {
      final api = ref.read(apiClientProvider);

      // 3. Send HTTP Request
      final response = await api.dio.post(
        '/chats/messages',
        data: {
          'sessionId': arg,
          'partnerId': receiverId, // Crucial for 'new_admin' backend logic
          'text': text.trim(),
          if (imageUrl != null) 'imageUrl': imageUrl,
        },
      );

      final responseData = response.data;
      final realSessionId = responseData['sessionId'] as String?;
      final newMessage = ChatMessageModel.fromJson(
        responseData['message'] ?? responseData,
      );

      // 4. Confirm the message in local state (Swap temp ID with real UUID)
      if (state.hasValue) {
        final currentMessages = state.value!;

        // Did Socket already confirm this while HTTP was still loading?
        final alreadyConfirmedBySocket = currentMessages.any(
          (m) => m.id == newMessage.id,
        );

        if (!alreadyConfirmedBySocket) {
          final updatedList = currentMessages.map((msg) {
            return msg.id == tempId ? newMessage : msg;
          }).toList();

          state = AsyncValue.data(updatedList);
        }
      }

      // 5. Broadcast via socket for instant delivery
      _socket.emit('send_message', {
        'receiverId': receiverId,
        'chatSessionId': realSessionId ?? arg,
        'text': text,
        'imageUrl': imageUrl,
        'messageId': newMessage.id,
      });

      return realSessionId;
    } catch (e) {
      print("❌ Failed to send message: $e");

      // Mark as failed in UI if request crashes
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

  void markAsRead(String senderId) {
    try {
      _socket.emit('mark_messages_read', {
        'chatSessionId': arg,
        'senderId': senderId,
      });

      if (state.hasValue) {
        final updatedList = state.value!.map((msg) {
          if (msg.senderId == senderId && !msg.isRead) {
            return msg.copyWith(isRead: true);
          }
          return msg;
        }).toList();
        state = AsyncValue.data(updatedList);
      }
    } catch (_) {}
  }

  // ✅ UPDATED: Robust deduplication & race-condition handling
  void _onReceiveMessage(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final msg = ChatMessageModel.fromJson(Map<String, dynamic>.from(payload));

      // Ensure the message belongs to this specific chat room
      // Handle edge case where 'arg' is 'new_admin' but the socket brings the real session ID
      if (msg.chatSessionId == arg || arg == 'new_admin') {
        final currentMessages = state.value!;

        // 1. Check if the message is already fully confirmed
        if (currentMessages.any((m) => m.id == msg.id)) return;

        // 2. Race Condition Check: Did Socket beat HTTP?
        // Look for an optimistic message currently "sending" with the same text
        final tempMessageIndex = currentMessages.indexWhere(
          (m) =>
              m.isSending == true &&
              m.senderId == msg.senderId &&
              m.text == msg.text,
        );

        if (tempMessageIndex != -1) {
          // Swap the temporary message with the real one from the socket
          final updatedList = List<ChatMessageModel>.from(currentMessages);
          updatedList[tempMessageIndex] = msg;
          state = AsyncValue.data(updatedList);
        } else {
          // Brand new message from partner
          state = AsyncValue.data([msg, ...currentMessages]);
        }
      }
    } catch (_) {}
  }

  void _onMessageConfirmed(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      final msg = ChatMessageModel.fromJson(
        Map<String, dynamic>.from(data['message']),
      );
      if (msg.chatSessionId == arg) {
        final currentMessages = state.value!;
        if (!currentMessages.any((m) => m.id == msg.id)) {
          state = AsyncValue.data([msg, ...currentMessages]);
        }
      }
    } catch (_) {}
  }

  void _onReadStatusSynced(dynamic payload) {
    if (!state.hasValue) return;
    try {
      final updatedList = state.value!
          .map((m) => m.copyWith(isRead: true))
          .toList();
      state = AsyncValue.data(updatedList);
    } catch (_) {}
  }
}
