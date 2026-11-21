import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/socket/socket_service.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/chat_repository.dart';
import '../../data/models/chat_session_model.dart';
import '../../providers/active_chat_provider.dart';
import '../../providers/chat_messages_provider.dart';
import '../../providers/chat_sessions_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String partnerId;
  final String? partnerName;
  final String? partnerAvatar;

  const ChatDetailScreen({
    super.key,
    required this.sessionId,
    required this.partnerId,
    this.partnerName,
    this.partnerAvatar,
  });

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  late String _currentSessionId;
  late final SocketService _socket;
  late final StateController<String?> _activeChatController;

  bool _isUploading = false;
  bool _partnerIsTyping = false;
  bool _partnerIsOnline = false;
  DateTime? _partnerLastSeen;
  Timer? _typingStopTimer;

  @override
  void initState() {
    super.initState();
    _currentSessionId = widget.sessionId;
    _socket = ref.read(socketServiceProvider);
    _activeChatController = ref.read(activeChatSessionProvider.notifier);

    // Seed initial presence from ChatSessionsNotifier if already loaded
    final existingSessions = ref.read(chatSessionsProvider).valueOrNull;
    if (existingSessions != null) {
      for (final s in existingSessions) {
        if (s.partnerId == widget.partnerId || s.id == _currentSessionId) {
          _partnerIsOnline = s.isOnline;
          if (s.lastSeen != null) {
            _partnerLastSeen = DateTime.tryParse(s.lastSeen!);
          }
          break;
        }
      }
    }

    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeChatController.state = _currentSessionId;
      ref
          .read(chatMessagesProvider(_currentSessionId).notifier)
          .markAsRead(widget.partnerId);

      _socket.listen('user_typing', _onPartnerTyping);
      _socket.listen('user_stopped_typing', _onPartnerStoppedTyping);
      _socket.listen('user_status_changed', _onUserStatusChanged);
      _socket.listen('user_presence', _onUserStatusChanged);

      _socket.emit('check_presence', {'userId': widget.partnerId});
    });
  }

  // ==========================================
  // REAL-TIME SOCKET HANDLERS
  // ==========================================
  void _onPartnerTyping(dynamic payload) {
    if (!mounted || payload is! Map) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      if (data['userId']?.toString() == widget.partnerId) {
        setState(() => _partnerIsTyping = true);
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _onPartnerStoppedTyping(dynamic payload) {
    if (!mounted || payload is! Map) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      if (data['userId']?.toString() == widget.partnerId) {
        setState(() => _partnerIsTyping = false);
      }
    } catch (_) {}
  }

  void _onUserStatusChanged(dynamic payload) {
    if (!mounted || payload is! Map) return;
    try {
      final data = Map<String, dynamic>.from(payload);
      if (data['userId']?.toString() == widget.partnerId) {
        setState(() {
          _partnerIsOnline = data['isOnline'] == true;
          final lastSeenStr = data['lastSeen']?.toString();
          if (lastSeenStr != null && lastSeenStr.isNotEmpty) {
            _partnerLastSeen = DateTime.tryParse(lastSeenStr);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _socket.emit('check_presence', {'userId': widget.partnerId});
      ref
          .read(chatMessagesProvider(_currentSessionId).notifier)
          .markAsRead(widget.partnerId);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(chatMessagesProvider(_currentSessionId).notifier).loadMore();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleLocalUserTyping() {
    _socket.emit('typing', {'receiverId': widget.partnerId});
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      _socket.emit('stop_typing', {'receiverId': widget.partnerId});
    });
  }

  // ==========================================
  // IMAGE UPLOAD & SENDING
  // ==========================================
  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final repo = ref.read(chatRepositoryProvider);
      final imageUrl = await repo.uploadChatImage(
        File(image.path),
        sessionId: _currentSessionId,
      );

      final newSessionId = await ref
          .read(chatMessagesProvider(_currentSessionId).notifier)
          .sendMessage(
            text: '',
            receiverId: widget.partnerId,
            imageUrl: imageUrl,
          );

      _handleSessionUpgrade(newSessionId);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки фото: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// Upgrades any `new_<UUID>` or `new_admin` placeholder to the real DB session UUID
  void _handleSessionUpgrade(String? returnedSessionId) {
    if (_currentSessionId.startsWith('new_') &&
        returnedSessionId != null &&
        !returnedSessionId.startsWith('new_')) {
      setState(() {
        _currentSessionId = returnedSessionId;
      });

      _activeChatController.state = _currentSessionId;

      context.replace(
        '/chat/$_currentSessionId/${widget.partnerId}',
        extra: {
          'partnerName': widget.partnerName,
          'partnerAvatar': widget.partnerAvatar,
        },
      );
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // UI BUILDERS
  // ==========================================
  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    String dateText;
    if (msgDay == today) {
      dateText = 'Сегодня';
    } else if (msgDay == yesterday) {
      dateText = 'Вчера';
    } else {
      dateText = DateFormat('d MMMM', 'ru').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        dateText,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAppBarTitle(ChatSessionModel? matchedSession) {
    final displayName =
        widget.partnerName ??
        matchedSession?.partnerName ??
        'Администратор Klinciti';
    final displayAvatar = widget.partnerAvatar ?? matchedSession?.partnerAvatar;
    final isAdmin =
        matchedSession?.isAdmin ??
        displayName.toLowerCase().contains('админ') ||
            displayName.toLowerCase().contains('поддержк');

    String statusText = _partnerIsTyping ? 'Печатает...' : 'Не в сети';
    Color dotColor = _partnerIsTyping
        ? Colors.blueAccent
        : (_partnerIsOnline
              ? Colors.greenAccent.shade400
              : Colors.grey.shade400);

    if (!_partnerIsTyping) {
      if (_partnerIsOnline) {
        statusText = 'В сети';
      } else if (_partnerLastSeen != null) {
        final lastSeen = _partnerLastSeen!.toLocal();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final msgDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);

        if (msgDay == today) {
          statusText =
              'Был(а) сегодня в ${DateFormat('HH:mm').format(lastSeen)}';
        } else if (msgDay == yesterday) {
          statusText = 'Был(а) вчера в ${DateFormat('HH:mm').format(lastSeen)}';
        } else {
          statusText =
              'Был(а) ${DateFormat('d MMM', 'ru').format(lastSeen)} в ${DateFormat('HH:mm').format(lastSeen)}';
        }
      }
    }

    final hasAvatar = displayAvatar != null && displayAvatar.trim().isNotEmpty;

    return Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: isAdmin
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                  : Colors.grey.shade200,
              backgroundImage: hasAvatar ? NetworkImage(displayAvatar) : null,
              child: !hasAvatar
                  ? Icon(
                      isAdmin ? LucideIcons.shield_check : Icons.person,
                      color: isAdmin ? const Color(0xFF3B82F6) : Colors.grey,
                      size: 20,
                    )
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.badge_check,
                      size: 15,
                      color: Color(0xFF3B82F6),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: (_partnerIsTyping || _partnerIsOnline)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: _partnerIsTyping
                      ? Colors.blueAccent.shade700
                      : (_partnerIsOnline
                            ? Colors.green.shade700
                            : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _activeChatController.state = null;
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    _socket.stopListening('user_typing', _onPartnerTyping);
    _socket.stopListening('user_stopped_typing', _onPartnerStoppedTyping);
    _socket.stopListening('user_status_changed', _onUserStatusChanged);
    _socket.stopListening('user_presence', _onUserStatusChanged);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(chatMessagesProvider(_currentSessionId));
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = currentUser?['id']?.toString() ?? '';

    final allSessions = ref.watch(chatSessionsProvider).valueOrNull ?? const [];
    ChatSessionModel? matchedSession;
    for (final s in allSessions) {
      if (s.id == _currentSessionId || s.partnerId == widget.partnerId) {
        matchedSession = s;
        break;
      }
    }

    ref.listen(chatMessagesProvider(_currentSessionId), (previous, next) {
      final currentMessages = next.value;
      final previousMessages = previous?.value;

      if (currentMessages != null && previousMessages != null) {
        if (currentMessages.length > previousMessages.length) {
          if (_scrollController.hasClients && _scrollController.offset < 100) {
            _scrollToBottom();
          }
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: _buildAppBarTitle(matchedSession),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Ошибка загрузки: $error')),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.messages_square,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Напишите первое сообщение',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Since messages are ordered NEWEST-FIRST, index 0 is the latest message
                if (messages.isNotEmpty &&
                    messages.first.senderId == widget.partnerId &&
                    !messages.first.isRead) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      ref
                          .read(
                            chatMessagesProvider(_currentSessionId).notifier,
                          )
                          .markAsRead(widget.partnerId);
                    }
                  });
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length + (_partnerIsTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_partnerIsTyping) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            bottom: 8,
                            top: 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Печатает...',
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      index -= 1;
                    }

                    final msg = messages[index];
                    final msgDate =
                        DateTime.tryParse(msg.createdAt)?.toLocal() ??
                        DateTime.now();

                    bool showDateSeparator = false;

                    if (index == messages.length - 1) {
                      showDateSeparator = true;
                    } else {
                      final nextOlderMsg = messages[index + 1];
                      final nextOlderDate =
                          DateTime.tryParse(nextOlderMsg.createdAt)
                              ?.toLocal() ??
                          msgDate;

                      if (msgDate.year != nextOlderDate.year ||
                          msgDate.month != nextOlderDate.month ||
                          msgDate.day != nextOlderDate.day) {
                        showDateSeparator = true;
                      }
                    }

                    final bubble = ChatBubble(
                      message: msg,
                      isMe: msg.senderId == currentUserId,
                    );

                    if (showDateSeparator) {
                      return Column(
                        children: [_buildDateSeparator(msgDate), bubble],
                      );
                    }

                    return bubble;
                  },
                );
              },
            ),
          ),
          ChatInput(
            isUploading: _isUploading,
            onSend: (text) async {
              _typingStopTimer?.cancel();
              _socket.emit('stop_typing', {'receiverId': widget.partnerId});

              final newSessionId = await ref
                  .read(chatMessagesProvider(_currentSessionId).notifier)
                  .sendMessage(text: text, receiverId: widget.partnerId);

              _handleSessionUpgrade(newSessionId);
              _scrollToBottom();
            },
            onTyping: _handleLocalUserTyping,
            onAttachmentPressed: _showAttachmentOptions,
          ),
        ],
      ),
    );
  }
}
