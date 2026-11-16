import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/job_provider.dart';
import '../../categories/providers/category_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';

// ==========================================
// 1. STATUS CONFIGURATION
// ==========================================
class StatusConfig {
  final String label;
  final Color textColor;
  final Color bgColor;
  final IconData icon;

  StatusConfig(this.label, this.textColor, this.bgColor, this.icon);
}

final Map<String, StatusConfig> _statusMap = {
  'PENDING': StatusConfig(
    'Поиск исполнителя',
    Colors.amber.shade700,
    Colors.amber.shade100,
    LucideIcons.clock,
  ),
  'ACCEPTED': StatusConfig(
    'В работе',
    Colors.blue.shade700,
    Colors.blue.shade100,
    LucideIcons.package_open,
  ),
  'COMPLETED': StatusConfig(
    'Завершена',
    Colors.green.shade700,
    Colors.green.shade100,
    LucideIcons.circle_check,
  ),
  'REFUSED': StatusConfig(
    'Отклонена',
    Colors.red.shade700,
    Colors.red.shade100,
    LucideIcons.circle_x,
  ),
  'CANCELLED': StatusConfig(
    'Отменена',
    Colors.grey.shade700,
    Colors.grey.shade200,
    LucideIcons.circle_x,
  ),
};

// ==========================================
// 2. MAIN SCREEN
// ==========================================
class JobListScreen extends ConsumerStatefulWidget {
  const JobListScreen({super.key});

  @override
  ConsumerState<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends ConsumerState<JobListScreen> {
  String? _jobToDelete;
  bool _isDeleting = false;

  Future<void> _handleDeleteConfirm() async {
    if (_jobToDelete == null) return;

    setState(() => _isDeleting = true);
    try {
      await ref
          .read(jobMutationStateProvider.notifier)
          .deleteJob(_jobToDelete!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Заявка была успешно отменена и удалена.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _jobToDelete = null;
        });
      }
    }
  }

  void _showDeleteDialog(String jobId) {
    setState(() => _jobToDelete = jobId);

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.circle_alert,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Удалить заявку?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вы уверены, что хотите удалить эту заявку? Это действие нельзя отменить.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isDeleting
                              ? null
                              : () {
                                  setState(() => _jobToDelete = null);
                                  Navigator.pop(context);
                                },
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isDeleting
                              ? null
                              : () async {
                                  setDialogState(() => _isDeleting = true);
                                  await _handleDeleteConfirm();
                                  if (context.mounted) Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: _isDeleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Удалить',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      if (mounted && !_isDeleting) setState(() => _jobToDelete = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(customerJobsProvider);
    // Fetch cached categories to resolve the category names from IDs
    final categoriesAsync = ref.watch(publicCategoriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Colors.black),
          onPressed: () => context.go('/home'),
        ),
        title: const Text(
          'Мои заявки',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: jobsAsync.when(
        data: (jobs) {
          if (jobs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Icon(
                        LucideIcons.package_open,
                        size: 40,
                        color: Colors.grey.shade300,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Заявок пока нет',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'У вас еще нет активных или завершенных заявок.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () => context.push('/create-job'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Создать заявку',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(customerJobsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16).copyWith(bottom: 100),
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                final statusConfig =
                    _statusMap[job.status] ?? _statusMap['PENDING']!;
                final canDelete = job.status == 'PENDING';

                // ==========================================
                // RESOLVE CATEGORY NAME DYNAMICALLY
                // ==========================================
                String displayTitle = 'Загрузка...';

                categoriesAsync.whenData((categories) {
                  try {
                    final parent = categories.firstWhere(
                      (c) => c.id == job.categoryId,
                    );
                    displayTitle = parent.name;

                    // Optionally append subcategory names if you want them in the title
                    if (job.subcategoryIds.isNotEmpty) {
                      final subNames = parent.subcategories
                          .where((sub) => job.subcategoryIds.contains(sub.id))
                          .map((sub) => sub.name)
                          .toList();
                      if (subNames.isNotEmpty) {
                        displayTitle =
                            '${parent.name} (${subNames.join(', ')})';
                      }
                    }
                  } catch (_) {
                    displayTitle =
                        'Услуга (ID: ${job.categoryId.substring(0, 4)}...)';
                  }
                });

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Title & Status
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayTitle, // FIXED: Dynamic human-readable name
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.calendar_days,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormat(
                                        'd MMMM yyyy, HH:mm',
                                        'ru_RU',
                                      ).format(job.createdAt.toLocal()),

                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusConfig.bgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  statusConfig.icon,
                                  size: 14,
                                  color: statusConfig.textColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusConfig.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusConfig.textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      // Description
                      Text(
                        job.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 20),
                      // Meta Info (Address & Budget)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.map_pin,
                                    size: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      job.pickupAddress,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.wallet,
                                    size: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      job.budget > 0
                                          ? '${job.budget.toInt()} ₽'
                                          : 'Договорная',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Actions (Edit/Delete)
                      if (canDelete) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            InkWell(
                              onTap: () => context.push('/edit-job/${job.id}'),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.pencil,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Редактировать',
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => _showDeleteDialog(job.id),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.trash,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Удалить',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF0F172A)),
        ),
        error: (error, _) {
          final apiError = ApiException.fromDioException(error);
          return GlobalErrorWidget(
            message: apiError.message,
            onRetry: () => ref.refresh(customerJobsProvider.future),
          );
        },
      ),
    );
  }
}
