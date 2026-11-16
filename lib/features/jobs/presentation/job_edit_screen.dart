import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/job_provider.dart';
import 'widgets/job_form_widget.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/global_error_widget.dart';

class JobEditScreen extends ConsumerWidget {
  final String jobId;

  const JobEditScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobDetailsProvider(jobId));
    final isSubmitting = ref.watch(jobMutationStateProvider);

    return Scaffold(
      body: jobAsync.when(
        data: (job) {
          // Strict Guard: Only PENDING jobs can be edited
          if (job.status != 'PENDING') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Эту заявку нельзя редактировать'),
                  backgroundColor: Colors.red,
                ),
              );
              context.pop();
            });
            return const SizedBox.shrink();
          }

          return JobFormWidget(
            title: 'Редактировать заявку',
            initialValues: JobFormValues(
              categoryId: job.categoryId, // NEW: Relational ID
              subcategoryIds: job.subcategoryIds, // NEW: List of UUIDs
              description: job.description,
              address: job.pickupAddress,
              budget: job.budget > 0 ? job.budget.toInt().toString() : '',
              timing: job.timing ?? 'today',
            ),
            initialPhotos: job.photos,
            isSubmitting: isSubmitting,
            onSubmit: (data, existingPhotos, newPhotos) async {
              if (existingPhotos.isEmpty && newPhotos.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Нужно хотя бы одно фото.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                // Pass the structured IDs to your updated mutation provider
                await ref
                    .read(jobMutationStateProvider.notifier)
                    .updateJob(
                      jobId: jobId,
                      categoryId: data.categoryId, // MATCHES NEW BACKEND
                      subcategoryIds:
                          data.subcategoryIds, // MATCHES NEW BACKEND
                      description: data.description,
                      address: data.address,
                      timing: data.timing,
                      budget: data.budget,
                      existingPhotos: existingPhotos,
                      newPhotos: newPhotos,
                    );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Заявка обновлена.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  context.pop();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final apiError = ApiException.fromDioException(error);
          return GlobalErrorWidget(
            message: apiError.message,
            onRetry: () => ref.refresh(jobDetailsProvider(jobId)),
          );
        },
      ),
    );
  }
}
