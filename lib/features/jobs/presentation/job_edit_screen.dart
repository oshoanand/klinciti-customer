import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../providers/job_provider.dart';
import 'widgets/job_form_widget.dart';

class JobEditScreen extends ConsumerStatefulWidget {
  final String jobId;

  const JobEditScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobEditScreen> createState() => _JobEditScreenState();
}

class _JobEditScreenState extends ConsumerState<JobEditScreen> {
  // Prevents triggering multiple SnackBars / pops if build() runs more than once
  bool _hasHandledNonPendingGuard = false;

  void _handleNonPendingRedirect() {
    if (_hasHandledNonPendingGuard) return;
    _hasHandledNonPendingGuard = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Редактирование недоступно: заявка уже в работе, завершена или отменена.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      if (context.canPop()) {
        context.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(customerJobDetailProvider(widget.jobId));
    final isSubmitting = ref.watch(customerJobMutationProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          tooltip: 'Назад',
          onPressed: isSubmitting ? null : () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Редактирование заявки',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Заказ #${widget.jobId.substring(0, widget.jobId.length >= 6 ? 6 : widget.jobId.length)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        actions: [
          // Subtle live status pill indicating editable state
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.pencil,
                      size: 12,
                      color: Color(0xFF2563EB),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Поиск',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: jobAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0F172A)),
              const SizedBox(height: 14),
              Text(
                'Загружаем данные заявки...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        error: (error, _) {
          final apiError = ApiException.fromDioException(error);
          return GlobalErrorWidget(
            message: apiError.message,
            onRetry: () =>
                ref.invalidate(customerJobDetailProvider(widget.jobId)),
          );
        },
        data: (job) {
          // Strict guard: only PENDING jobs can be edited
          if (job.status != 'PENDING') {
            _handleNonPendingRedirect();
            return _buildLockedState(context);
          }

          return Column(
            children: [
              // Modern contextual notice banner
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        LucideIcons.info,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Вы можете изменить детали, фото или бюджет, пока на заявку не назначен исполнитель.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main reusable job form
              Expanded(
                child: JobFormWidget(
                  title: 'Сохранить изменения',
                  initialValues: JobFormValues(
                    categoryId: job.categoryId ?? '',
                    subcategoryIds: job.subcategoryIds,
                    description: job.description,
                    address: job.pickupAddress,
                    budget: job.budget > 0 ? job.budget.toInt().toString() : '',
                    timing: job.timing.isNotEmpty ? job.timing : 'today',
                  ),
                  initialPhotos: job.photos,
                  isSubmitting: isSubmitting,
                  onSubmit: (data, existingPhotos, newPhotos) async {
                    if (existingPhotos.isEmpty && newPhotos.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Добавьте хотя бы одно фото.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    try {
                      await ref
                          .read(customerJobMutationProvider.notifier)
                          .updateJob(
                            jobId: widget.jobId,
                            categoryId: data.categoryId,
                            subcategoryIds: data.subcategoryIds,
                            description: data.description,
                            address: data.address,
                            timing: data.timing,
                            budget: data.budget,
                            city: job.city != 'Не указан' ? job.city : null,
                            existingPhotos: existingPhotos,
                            newPhotos: newPhotos,
                          );

                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Заявка успешно обновлена'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      context.pop(true);
                    } on ApiException catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Ошибка обновления заявки: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Fallback UI shown briefly if the job status changed before popping
  Widget _buildLockedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.lock, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Редактирование недоступно',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Изменять можно только заявки в статусе поиска мастера.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
