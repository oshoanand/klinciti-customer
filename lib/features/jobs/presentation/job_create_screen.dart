import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../providers/job_provider.dart';
import 'widgets/job_form_widget.dart';

class JobCreateScreen extends ConsumerWidget {
  /// Optional pre-selected parent Category ID (UUID) passed from the router
  final String? initialCategory;

  const JobCreateScreen({super.key, this.initialCategory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSubmitting = ref.watch(customerJobMutationProvider);
    final canPop = context.canPop();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: canPop
            ? IconButton(
                icon: const Icon(
                  LucideIcons.arrow_left,
                  color: Color(0xFF0F172A),
                ),
                tooltip: 'Назад',
                onPressed: isSubmitting ? null : () => context.pop(),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Новая заявка',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Опишите задачу и добавьте фото',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: Column(
        children: [
          // Subtle onboarding tip banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF16A34A).withValues(alpha: 0.25),
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
                    color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.sparkles,
                    size: 18,
                    color: Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Добавьте четкие фото и подробности — так мы быстрее подберем проверенного мастера.',
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
              title: 'Опубликовать заявку',
              initialCategory: initialCategory,
              isSubmitting: isSubmitting,
              onSubmit: (data, existingPhotos, newPhotos) async {
                if (data.categoryId.trim().isEmpty ||
                    data.subcategoryIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Выберите категорию и хотя бы одну подкатегорию.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (newPhotos.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Добавьте хотя бы одно фото.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  // Upload photos to MinIO and POST /api/jobs/create
                  final createdJob = await ref
                      .read(customerJobMutationProvider.notifier)
                      .createJob(
                        categoryId: data.categoryId,
                        subcategoryIds: data.subcategoryIds,
                        description: data.description,
                        address: data.address,
                        timing: data.timing,
                        budget: data.budget,
                        localPhotos: newPhotos,
                      );

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Заявка создана! Ожидайте назначения мастера.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );

                  // Open the newly created job detail screen cleanly
                  if (context.canPop()) {
                    context.pushReplacement(
                      '${AppRoutes.jobDetail}/${createdJob.id}',
                    );
                  } else {
                    context.go('${AppRoutes.jobList}?status=PENDING');
                  }
                } on ApiException catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка создания заявки: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
