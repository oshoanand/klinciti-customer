import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exceptions.dart';
import '../../../../core/router/route_names.dart';
import '../../chat/providers/chat_sessions_provider.dart';
import '../providers/job_provider.dart';

class JobDetailScreen extends ConsumerStatefulWidget {
  final String jobId;

  const JobDetailScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  // ==========================================
  // HARDWARE & NAVIGATION ACTIONS
  // ==========================================

  Future<void> _callWorker(String? mobile) async {
    if (mobile == null || mobile.trim().isEmpty) return;
    final clean = mobile.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть звонилку')),
        );
      }
    }
  }

  Future<void> _chatWithWorker(CustomerJobModel job) async {
    if (job.workerId == null || job.workerId!.isEmpty) return;
    try {
      final session = await ref
          .read(chatSessionsProvider.notifier)
          .resolveOrInitiateSession(
            partnerId: job.workerId!,
            fallbackName: job.workerName,
            fallbackAvatar: job.workerImage,
          );
      if (!mounted) return;
      context.push(
        '${AppRoutes.chatDetail}/${session.id}/${session.partnerId}',
        extra: {
          'partnerName': session.partnerName ?? job.workerName,
          'partnerAvatar': session.partnerAvatar ?? job.workerImage,
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка открытия чата: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openPhotoViewer(String title, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenPhotoViewer(title: title, url: imageUrl),
      ),
    );
  }

  // ==========================================
  // MUTATION ACTIONS (Pay, Dispute, Cancel)
  // ==========================================

  Future<void> _handleSafeDealPayment(CustomerJobModel job) async {
    try {
      final paymentUrl = await ref
          .read(customerJobMutationProvider.notifier)
          .initiateSafeDealPayment(job.id);

      final uri = Uri.tryParse(paymentUrl);
      if (uri == null) {
        throw ApiException('Некорректная ссылка на оплату');
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка инициализации оплаты: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDisputeDialog(CustomerJobModel job) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Открыть спор по заказу'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Опишите проблему с выполненной работой. Администратор свяжется с вами для урегулирования:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Например: Работа выполнена не полностью...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'Укажите причину (минимум 5 символов)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final reason = controller.text.trim();
              Navigator.pop(dialogCtx);

              try {
                final msg = await ref
                    .read(customerJobMutationProvider.notifier)
                    .disputeJob(jobId: job.id, reason: reason);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } on ApiException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Открыть спор'),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(CustomerJobModel job) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Отменить заявку?'),
        content: const Text(
          'Вы уверены, что хотите отменить эту заявку? Мастера больше не смогут откликаться на нее.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                final msg = await ref
                    .read(customerJobMutationProvider.notifier)
                    .cancelJob(job.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.green),
                  );
                  if (context.canPop()) context.pop();
                }
              } on ApiException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Отменить заявку'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(customerJobDetailProvider(widget.jobId));
    final isMutating = ref.watch(customerJobMutationProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Детали заказа',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          if (jobAsync.valueOrNull?.status == 'PENDING')
            IconButton(
              icon: const Icon(
                LucideIcons.pencil,
                size: 19,
                color: Color(0xFF0F172A),
              ),
              tooltip: 'Редактировать заявку',
              onPressed: isMutating
                  ? null
                  : () async {
                      final updated = await context.push<bool>(
                        '${AppRoutes.jobEdit}/${widget.jobId}',
                      );
                      if (updated == true && mounted) {
                        ref.invalidate(customerJobDetailProvider(widget.jobId));
                      }
                    },
            ),
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 18,
              color: Color(0xFF0F172A),
            ),
            onPressed: () =>
                ref.invalidate(customerJobDetailProvider(widget.jobId)),
          ),
        ],
      ),
      body: jobAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circle_alert,
                  color: Colors.red,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ошибка загрузки заказа: $err',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(customerJobDetailProvider(widget.jobId)),
                  icon: const Icon(LucideIcons.refresh_cw, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (job) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF0F172A),
                onRefresh: () async {
                  ref.invalidate(customerJobDetailProvider(widget.jobId));
                  await ref.read(
                    customerJobDetailProvider(widget.jobId).future,
                  );
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 1. Status & Budget Banner
                    _buildStatusBanner(job),
                    const SizedBox(height: 16),

                    // 2. Service Details Card
                    _buildServiceDetailsCard(job),

                    // 3. Assigned Worker Card
                    if (job.workerId != null && job.workerId!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildWorkerCard(job),
                    ],

                    // 4. Customer Uploaded Photos
                    if (job.photos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildPhotosCard(
                        title: 'Фотографии заказа',
                        photos: job.photos,
                      ),
                    ],

                    // 5. Worker Completion Proof (shown when worker completes job)
                    if (job.completionPhotos.isNotEmpty ||
                        (job.completionComment != null &&
                            job.completionComment!.isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      _buildCompletionReportCard(job),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Contextual Bottom Action Bar
            _buildBottomActionBar(job, isMutating),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SECTION BUILDERS
  // ==========================================

  Widget _buildStatusBanner(CustomerJobModel job) {
    Color color;
    IconData icon;
    String title;
    String subtitle;

    if (job.isPaymentPending) {
      color = Colors.indigo;
      icon = LucideIcons.credit_card;
      title = 'Работа выполнена — ожидает оплаты';
      subtitle = 'Проверьте фотоотчет мастера и оплатите заказ через Безопасную сделку или откройте спор.';
    } else if (job.isPaid) {
      color = Colors.teal;
      icon = LucideIcons.shield_check;
      title = 'Заказ оплачен';
      subtitle =
          'Оплата успешно подтверждена. Спасибо, что пользуетесь Klinciti!';
    } else {
      switch (job.status) {
        case 'PENDING':
          color = const Color(0xFF3B82F6);
          icon = LucideIcons.search;
          title = 'Поиск исполнителя';
          subtitle = 'Мы подбираем подходящего мастера для вашего заказа.';
          break;
        case 'ACCEPTED':
          color = Colors.purple;
          icon = LucideIcons.user_check;
          title = 'Мастер назначен';
          subtitle = 'Ожидайте подтверждения начала работ от исполнителя.';
          break;
        case 'ONGOING':
          color = Colors.orange;
          icon = LucideIcons.hammer;
          title = 'Заказ в работе';
          subtitle = 'Исполнитель приступил к выполнению вашего заказа.';
          break;
        case 'DISPUTED':
          color = Colors.deepOrange;
          icon = LucideIcons.triangle_alert;
          title = 'Открыт спор';
          subtitle =
              'Администратор разбирается в ситуации и скоро свяжется с вами.';
          break;
        case 'CANCELLED':
          color = Colors.red;
          icon = LucideIcons.circle_x;
          title = 'Заказ отменен';
          subtitle = 'Эта заявка была отменена.';
          break;
        default:
          color = Colors.green;
          icon = LucideIcons.circle_check;
          title = 'Заказ завершен';
          subtitle = 'Работа по заказу выполнена.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceDetailsCard(CustomerJobModel job) {
    final createdStr = job.createdAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(job.createdAt!.toLocal())
        : '—';
    final budgetStr = job.budget > 0
        ? '${job.budget.toStringAsFixed(0)} ₽'
        : 'Договорная';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  job.categoryName ?? 'Услуга',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                budgetStr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          if (job.subcategoryName != null &&
              job.subcategoryName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              job.subcategoryName!,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
          ],
          const Divider(height: 24),
          _buildInfoRow(LucideIcons.map_pin, 'Адрес', job.pickupAddress),
          const SizedBox(height: 10),
          _buildInfoRow(LucideIcons.clock, 'Сроки', job.timingLabel),
          const SizedBox(height: 10),
          _buildInfoRow(LucideIcons.calendar, 'Создан', createdStr),
          const Divider(height: 24),
          const Text(
            'Описание задачи',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            job.description,
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF0F172A),
              height: 1.45,
            ),
          ),
          if (job.workerComment != null && job.workerComment!.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Комментарий мастера при принятии',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              job.workerComment!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkerCard(CustomerJobModel job) {
    final hasAvatar =
        job.workerImage != null && job.workerImage!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Назначенный исполнитель',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey.shade100,
                backgroundImage: hasAvatar
                    ? NetworkImage(job.workerImage!)
                    : null,
                child: !hasAvatar
                    ? const Icon(LucideIcons.user, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.workerName ?? 'Мастер Klinciti',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (job.workerRating != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.star,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            job.workerRating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (job.workerMobile != null && job.workerMobile!.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callWorker(job.workerMobile),
                    icon: const Icon(LucideIcons.phone, size: 16),
                    label: const Text('Позвонить'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (job.workerMobile != null && job.workerMobile!.isNotEmpty)
                const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _chatWithWorker(job),
                  icon: const Icon(LucideIcons.message_circle, size: 16),
                  label: const Text('Написать'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosCard({
    required String title,
    required List<String> photos,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final url = photos[index];
                return GestureDetector(
                  onTap: () => _openPhotoViewer('$title (${index + 1})', url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: 104,
                      height: 104,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 104,
                        height: 104,
                        color: Colors.grey.shade200,
                        child: const Icon(
                          LucideIcons.image_off,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionReportCard(CustomerJobModel job) {
    final completedStr = job.completedAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(job.completedAt!.toLocal())
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.circle_check,
                size: 18,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Отчет о выполнении',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (completedStr != null)
                Text(
                  completedStr,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          if (job.completionComment != null &&
              job.completionComment!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              job.completionComment!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF334155),
                height: 1.4,
              ),
            ),
          ],
          if (job.completionPhotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: job.completionPhotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final url = job.completionPhotos[index];
                  return GestureDetector(
                    onTap: () =>
                        _openPhotoViewer('Фото результата (${index + 1})', url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 104,
                          height: 104,
                          color: Colors.grey.shade200,
                          child: const Icon(
                            LucideIcons.image_off,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(CustomerJobModel job, bool isMutating) {
    // 1. COMPLETED + PAYMENT PENDING -> Show Safe Deal Pay + Open Dispute
    if (job.isPaymentPending) {
      return _bottomBarWrapper(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: isMutating
                    ? null
                    : () => _handleSafeDealPayment(job),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: isMutating
                    ? const SizedBox.shrink()
                    : const Icon(LucideIcons.shield_check, size: 20),
                label: isMutating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Оплатить ${job.budget.toStringAsFixed(0)} ₽ (Безопасная сделка)',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: isMutating ? null : () => _showDisputeDialog(job),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepOrange,
                  side: const BorderSide(color: Colors.deepOrange),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(LucideIcons.triangle_alert, size: 18),
                label: const Text(
                  'Есть претензия — открыть спор',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. ONGOING -> Allow customer to open a dispute if needed
    if (job.status == 'ONGOING') {
      return _bottomBarWrapper(
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: isMutating ? null : () => _showDisputeDialog(job),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepOrange,
              side: const BorderSide(color: Colors.deepOrange),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(LucideIcons.triangle_alert, size: 18),
            label: const Text(
              'Открыть спор',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    // 3. PENDING -> Allow customer to edit or cancel the job
    if (job.status == 'PENDING') {
      return _bottomBarWrapper(
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: isMutating
                      ? null
                      : () async {
                          final updated = await context.push<bool>(
                            '${AppRoutes.jobEdit}/${job.id}',
                          );
                          if (updated == true && mounted) {
                            ref.invalidate(
                              customerJobDetailProvider(widget.jobId),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(LucideIcons.pencil, size: 17),
                  label: const Text(
                    'Редактировать',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: isMutating ? null : () => _showCancelDialog(job),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Icon(LucideIcons.trash, size: 19),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _bottomBarWrapper({required Widget child}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.paddingOf(context).bottom + 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// FULL-SCREEN ZOOMABLE PHOTO VIEWER
// ==========================================
class _FullScreenPhotoViewer extends StatelessWidget {
  final String title;
  final String url;

  const _FullScreenPhotoViewer({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator(color: Colors.white);
            },
            errorBuilder: (_, __, ___) => const Icon(
              LucideIcons.image_off,
              color: Colors.white54,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
