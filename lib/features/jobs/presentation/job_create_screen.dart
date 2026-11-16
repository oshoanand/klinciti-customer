import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/job_provider.dart';
import 'widgets/job_form_widget.dart';

class JobCreateScreen extends ConsumerWidget {
  // This now expects the parent Category ID (UUID) from the router
  final String? initialCategory;

  const JobCreateScreen({super.key, this.initialCategory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the loading state of the mutation provider
    final isSubmitting = ref.watch(jobMutationStateProvider);

    return JobFormWidget(
      title: 'Создать заявку',
      initialCategory: initialCategory,
      isSubmitting: isSubmitting,
      onSubmit: (data, existingPhotos, newPhotos) async {
        // Validation: Ensure at least one photo is provided for a new job
        if (newPhotos.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нужно хотя бы одно фото.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        try {
          // The mutation provider handles the 2-step process (Upload to MinIO -> POST to backend)
          await ref
              .read(jobMutationStateProvider.notifier)
              .createJob(
                categoryId: data.categoryId,
                subcategoryIds: data.subcategoryIds,
                description: data.description,
                address: data.address,
                timing: data.timing,
                budget: data.budget,
                localPhotos: newPhotos,
              );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Заявка создана! Ожидайте предложений.'),
                backgroundColor: Colors.green,
              ),
            );
            // Navigate to the orders list upon success
            context.go('/orders');
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
  }
}
