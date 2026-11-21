import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_names.dart';
import '../../data/models/chat_session_model.dart';
import '../../providers/chat_sessions_provider.dart';

class ChatInboxScreen extends ConsumerWidget {
  const ChatInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsState = ref.watch(chatSessionsProvider);
    final totalUnread = ref.watch(totalUnreadChatCountProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: context.canPop()
              ? IconButton(
                  icon: const Icon(
                    LucideIcons.arrow_left,
                    color: Color(0xFF0F172A),
                  ),
                  onPressed: () => context.pop(),
                )
              : const Padding(
                  padding: EdgeInsets.only(left: 16.0),
                  child: Icon(
                    LucideIcons.message_circle_more,
                    color: Color(0xFF0F172A),
                  ),
                ),
          title: Row(
            children: [
              const Text(
                'Сообщения',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                  fontSize: 22,
                ),
              ),
              if (totalUnread > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    totalUnread > 99 ? '99+' : totalUnread.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                LucideIcons.refresh_cw,
                size: 18,
                color: Color(0xFF0F172A),
              ),
              tooltip: 'Обновить',
              onPressed: () =>
                  ref.read(chatSessionsProvider.notifier).refresh(),
            ),
          ],
          centerTitle: false,
        ),
        body: RefreshIndicator(
          color: const Color(0xFF0F172A),
          backgroundColor: Colors.white,
          onRefresh: () => ref.read(chatSessionsProvider.notifier).refresh(),
          child: sessionsState.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFF0F172A)),
            ),
            error: (err, _) => Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.circle_alert,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ошибка загрузки чатов\n$err',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () =>
                          ref.read(chatSessionsProvider.notifier).refresh(),
                      icon: const Icon(LucideIcons.refresh_cw, size: 16),
                      label: const Text('Повторить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            data: (sessions) {
              if (sessions.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(top: 8, bottom: 32),
                itemCount: sessions.length,
                separatorBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(left: 88, right: 24),
                  child: Divider(height: 1, color: Colors.grey.shade200),
                ),
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return _buildSessionTile(context, session);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSessionTile(BuildContext context, ChatSessionModel session) {
    final date =
        DateTime.tryParse(session.updatedAt)?.toLocal() ?? DateTime.now();
    final isUnread = session.unreadCount > 0;
    final isAdmin = session.isAdmin;
    final hasAvatar =
        session.partnerAvatar != null &&
        session.partnerAvatar!.trim().isNotEmpty;

    final String presenceText = _formatPresence(
      isOnline: session.isOnline,
      lastSeenRaw: session.lastSeen,
      isAdmin: isAdmin,
    );

    return Material(
      color: isAdmin
          ? Colors.blue.shade50.withValues(alpha: 0.35)
          : Colors.white,
      child: InkWell(
        onTap: () {
          context.push(
            '${AppRoutes.chatDetail}/${session.id}/${session.partnerId}',
            extra: {
              'partnerName': session.partnerName,
              'partnerAvatar': session.partnerAvatar,
              'isOnline': session.isOnline,
              'lastSeen': session.lastSeen,
              'isAdmin': session.isAdmin,
            },
          );
        },
        highlightColor: Colors.grey.shade100,
        splashColor: Colors.grey.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with Online / Offline Presence Dot
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isAdmin
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                        : const Color(0xFF0F172A).withValues(alpha: 0.06),
                    backgroundImage: hasAvatar
                        ? NetworkImage(session.partnerAvatar!)
                        : null,
                    child: !hasAvatar
                        ? Icon(
                            isAdmin
                                ? LucideIcons.shield_check
                                : LucideIcons.user,
                            color: isAdmin
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF64748B),
                            size: 24,
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: session.isOnline
                            ? Colors.green
                            : Colors.grey.shade400,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Middle Content: Name, Admin Badge, Presence/Last Seen, and Message Preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Name + Admin Role Pill + Timestamp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  session.partnerName ??
                                      (isAdmin
                                          ? 'Администратор Klinciti'
                                          : 'Пользователь'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isUnread
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                    fontSize: 16,
                                    color: isAdmin
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (isAdmin) ...[
                                const SizedBox(width: 5),
                                const Icon(
                                  LucideIcons.badge_check,
                                  size: 16,
                                  color: Color(0xFF3B82F6),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Админ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!session.id.startsWith('new_'))
                          Text(
                            _formatLastMessageDate(date),
                            style: TextStyle(
                              fontSize: 12,
                              color: isUnread
                                  ? const Color(0xFF3B82F6)
                                  : Colors.grey.shade500,
                              fontWeight: isUnread
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Row 2: Online / Last Seen Status
                    Text(
                      presenceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: session.isOnline
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: session.isOnline
                            ? Colors.green.shade700
                            : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Row 3: Typing indicator or Last Message + Unread Count Badge
                    Row(
                      children: [
                        Expanded(
                          child: session.isTyping
                              ? const Text(
                                  'Печатает...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF3B82F6),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Text(
                                  session.lastMessage ??
                                      (isAdmin
                                          ? 'Напишите администратору по любому вопросу'
                                          : '📷 Фото'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isUnread
                                        ? const Color(0xFF0F172A)
                                        : Colors.grey.shade600,
                                    fontWeight: isUnread
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontSize: 13.5,
                                  ),
                                ),
                        ),
                        if (isUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              session.unreadCount > 99
                                  ? '99+'
                                  : session.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPresence({
    required bool isOnline,
    required String? lastSeenRaw,
    required bool isAdmin,
  }) {
    if (isOnline) {
      return 'В сети';
    }
    if (lastSeenRaw != null && lastSeenRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(lastSeenRaw)?.toLocal();
      if (parsed != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final seenDay = DateTime(parsed.year, parsed.month, parsed.day);
        final timeStr = DateFormat('HH:mm').format(parsed);

        if (seenDay == today) {
          return 'Был(а) в сети сегодня в $timeStr';
        } else if (seenDay == yesterday) {
          return 'Был(а) в сети вчера в $timeStr';
        } else {
          return 'Был(а) в сети ${DateFormat('dd.MM.yy').format(parsed)} в $timeStr';
        }
      }
    }
    return isAdmin ? 'Служба поддержки Klinciti' : 'Не в сети';
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  LucideIcons.message_square,
                  size: 40,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Нет активных чатов',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь появятся ваши переписки\nс администраторами и мастерами.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLastMessageDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    if (msgDay == today) {
      return DateFormat('HH:mm').format(date);
    } else if (msgDay == yesterday) {
      return 'Вчера';
    } else {
      return DateFormat('dd.MM.yy').format(date);
    }
  }
}
