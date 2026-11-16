import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/job_model.dart';
import '../data/job_repository.dart';

// ==========================================
// 1. FETCH PROVIDERS (READ)
// ==========================================

/// Fetches the list of all jobs for the current logged-in customer.
final customerJobsProvider = FutureProvider.autoDispose<List<JobModel>>((ref) {
  final repository = ref.watch(jobRepositoryProvider);
  return repository.fetchCustomerJobs();
});

/// Fetches a single job by its ID (useful for the Edit Screen).
final jobDetailsProvider = FutureProvider.family.autoDispose<JobModel, String>((
  ref,
  jobId,
) {
  final repository = ref.watch(jobRepositoryProvider);
  return repository.fetchJobDetails(jobId);
});

// ==========================================
// 2. MUTATION PROVIDER (CREATE, UPDATE, DELETE)
// ==========================================

/// Provides the loading state (true/false) while a job is being submitted/deleted
final jobMutationStateProvider =
    StateNotifierProvider.autoDispose<JobMutationNotifier, bool>((ref) {
      return JobMutationNotifier(ref.watch(jobRepositoryProvider), ref);
    });

class JobMutationNotifier extends StateNotifier<bool> {
  final JobRepository _repository;
  final Ref _ref;

  JobMutationNotifier(this._repository, this._ref) : super(false);
  // Inside JobMutationNotifier...

  Future<void> createJob({
    required String categoryId,
    required List<String> subcategoryIds, // ✅ CHANGED to List
    required String description,
    required String address,
    required String timing,
    required String? budget,
    required List<File> localPhotos,
  }) async {
    state = true;
    try {
      await _repository.createJob(
        categoryId: categoryId,
        subcategoryIds: subcategoryIds, // ✅ Forward array
        description: description,
        address: address,
        timing: timing,
        budget: budget,
        localPhotos: localPhotos,
      );
      _ref.invalidate(customerJobsProvider);
      state = false;
    } catch (e) {
      state = false;
      rethrow;
    }
  }

  Future<void> updateJob({
    required String jobId,
    required String categoryId,
    required List<String> subcategoryIds, // ✅ CHANGED to List
    required String description,
    required String address,
    required String timing,
    required String? budget,
    required List<String> existingPhotos,
    required List<File> newPhotos,
  }) async {
    state = true;
    try {
      await _repository.updateJob(
        jobId: jobId,
        categoryId: categoryId,
        subcategoryIds: subcategoryIds, // ✅ Forward array
        description: description,
        address: address,
        timing: timing,
        budget: budget,
        existingPhotos: existingPhotos,
        newPhotos: newPhotos,
      );

      _ref.invalidate(customerJobsProvider);
      _ref.invalidate(jobDetailsProvider(jobId));
      state = false;
    } catch (e) {
      state = false;
      rethrow;
    }
  }

  Future<void> deleteJob(String jobId) async {
    state = true;
    try {
      await _repository.deleteJob(jobId);

      _ref.invalidate(customerJobsProvider);
      state = false;
    } catch (e) {
      state = false;
      rethrow;
    }
  }
}
