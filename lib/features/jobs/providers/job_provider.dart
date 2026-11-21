import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/job_model.dart';
import '../data/job_repository.dart';

export '../data/job_model.dart';

// ==========================================
// 1. READ PROVIDERS
// ==========================================

/// Aggregated customer job counts per status
final customerJobStatsProvider = FutureProvider.autoDispose<CustomerJobStats>((
  ref,
) {
  return ref.watch(jobRepositoryProvider).fetchJobStats();
});

/// Paginated list provider per status tab
final customerJobsListProvider = AsyncNotifierProvider.family
    .autoDispose<CustomerJobsListNotifier, PaginatedJobsState, String>(() {
      return CustomerJobsListNotifier();
    });

class CustomerJobsListNotifier
    extends AutoDisposeFamilyAsyncNotifier<PaginatedJobsState, String> {
  static const int _pageSize = 20;

  @override
  Future<PaginatedJobsState> build(String arg) {
    return ref
        .read(jobRepositoryProvider)
        .fetchJobsByStatus(status: arg, page: 1, limit: _pageSize);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(jobRepositoryProvider)
          .fetchJobsByStatus(status: arg, page: 1, limit: _pageSize),
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final nextPage = current.page + 1;
      final nextResult = await ref
          .read(jobRepositoryProvider)
          .fetchJobsByStatus(status: arg, page: nextPage, limit: _pageSize);

      // Deduplicate by job ID when appending pages
      final existingIds = current.items.map((j) => j.id).toSet();
      final uniqueNew = nextResult.items
          .where((j) => !existingIds.contains(j.id))
          .toList();

      state = AsyncValue.data(
        current.copyWith(
          items: [...current.items, ...uniqueNew],
          page: nextPage,
          total: nextResult.total,
          hasMore: nextResult.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncValue.data(current.copyWith(isLoadingMore: false));
    }
  }
}

/// Full details of a single job
final customerJobDetailProvider = FutureProvider.family
    .autoDispose<CustomerJobModel, String>((ref, jobId) {
      return ref.watch(jobRepositoryProvider).fetchJobDetail(jobId);
    });

// ==========================================
// 2. MUTATION NOTIFIER (Cancel, Dispute, Safe Deal Payment)
// ==========================================

final customerJobMutationProvider =
    StateNotifierProvider.autoDispose<CustomerJobMutationNotifier, bool>((ref) {
      return CustomerJobMutationNotifier(ref);
    });

class CustomerJobMutationNotifier extends StateNotifier<bool> {
  final Ref _ref;

  CustomerJobMutationNotifier(this._ref) : super(false);

  void _invalidateJobProviders(String jobId) {
    _ref.invalidate(customerJobStatsProvider);
    _ref.invalidate(customerJobDetailProvider(jobId));

    for (final status in const [
      'PENDING',
      'ACCEPTED',
      'ONGOING',
      'PAYMENT_PENDING',
      'PAID',
      'COMPLETED',
      'DISPUTED',
      'CANCELLED',
    ]) {
      _ref.invalidate(customerJobsListProvider(status));
    }
  }

  Future<String> cancelJob(String jobId) async {
    state = true;
    try {
      final message = await _ref.read(jobRepositoryProvider).cancelJob(jobId);
      _invalidateJobProviders(jobId);
      return message;
    } finally {
      if (mounted) state = false;
    }
  }

  Future<String> disputeJob({
    required String jobId,
    required String reason,
  }) async {
    state = true;
    try {
      final message = await _ref
          .read(jobRepositoryProvider)
          .disputeJob(jobId: jobId, reason: reason);
      _invalidateJobProviders(jobId);
      return message;
    } finally {
      if (mounted) state = false;
    }
  }

  Future<String> initiateSafeDealPayment(String jobId) async {
    state = true;
    try {
      return await _ref
          .read(jobRepositoryProvider)
          .initiateSafeDealPayment(jobId);
    } finally {
      if (mounted) state = false;
    }
  }

  /// Creates a new job and refreshes dashboard stats and PENDING job lists
  Future<CustomerJobModel> createJob({
    required String categoryId,
    required List<String> subcategoryIds,
    required String description,
    required String address,
    required String timing,
    String? budget,
    String? city,
    required List<File> localPhotos,
  }) async {
    state = true;
    try {
      final created = await _ref
          .read(jobRepositoryProvider)
          .createJob(
            categoryId: categoryId,
            subcategoryIds: subcategoryIds,
            description: description,
            address: address,
            timing: timing,
            budget: budget,
            city: city,
            localPhotos: localPhotos,
          );

      _ref.invalidate(customerJobStatsProvider);
      _ref.invalidate(customerJobsListProvider('PENDING'));
      _ref.invalidate(customerJobsListProvider('ALL'));

      return created;
    } finally {
      if (mounted) state = false;
    }
  }

  /// Updates a PENDING job and invalidates detail, list, and stats caches
  Future<CustomerJobModel> updateJob({
    required String jobId,
    required String categoryId,
    required List<String> subcategoryIds,
    required String description,
    required String address,
    required String timing,
    String? budget,
    String? city,
    required List<String> existingPhotos,
    required List<File> newPhotos,
  }) async {
    state = true;
    try {
      final updated = await _ref
          .read(jobRepositoryProvider)
          .updateJob(
            jobId: jobId,
            categoryId: categoryId,
            subcategoryIds: subcategoryIds,
            description: description,
            address: address,
            timing: timing,
            budget: budget,
            city: city,
            existingPhotos: existingPhotos,
            newPhotos: newPhotos,
          );
      _invalidateJobProviders(jobId);
      return updated;
    } finally {
      if (mounted) state = false;
    }
  }
}
