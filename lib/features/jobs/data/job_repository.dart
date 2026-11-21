import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/uploader_service.dart';
import 'job_model.dart';

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return JobRepository(
    ref.watch(apiClientProvider),
    ref.watch(uploaderServiceProvider),
  );
});

class JobRepository {
  final ApiClient _api;
  final UploaderService _uploader;

  JobRepository(this._api, this._uploader);

  /// Fetches aggregated job counts per status
  /// GET /api/jobs/for-customer/by-stats
  Future<CustomerJobStats> fetchJobStats() async {
    try {
      final response = await _api.dio.get('/jobs/for-customer/by-stats');
      final map = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};
      return CustomerJobStats.fromJson(map);
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Fetches paginated jobs for a specific status tab
  /// GET /api/jobs/for-customer/by-status
  Future<PaginatedJobsState> fetchJobsByStatus({
    required String status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _api.dio.get(
        '/jobs/for-customer/by-status',
        queryParameters: {
          'status': status,
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      final body = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};

      final rawList = (body['data'] as List<dynamic>?) ?? const [];
      final jobs = rawList
          .whereType()
          .map((e) => CustomerJobModel.fromJson(JsonMap.from(e)))
          .toList();

      final meta = body['meta'] is Map
          ? JsonMap.from(body['meta'] as Map)
          : <String, dynamic>{};

      final total =
          int.tryParse((meta['total'] ?? jobs.length).toString()) ?? 0;
      final hasMore = meta['hasMore'] == true || (page * limit) < total;

      return PaginatedJobsState(
        items: jobs,
        page: page,
        total: total,
        hasMore: hasMore,
        isLoadingMore: false,
      );
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Fetches full details of a single job
  /// GET /api/jobs/:jobId
  Future<CustomerJobModel> fetchJobDetail(String jobId) async {
    try {
      final response = await _api.dio.get('/jobs/$jobId');
      final map = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};
      return CustomerJobModel.fromJson(map);
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Cancels a PENDING job
  /// DELETE /api/jobs/:jobId
  Future<String> cancelJob(String jobId) async {
    try {
      final response = await _api.dio.delete('/jobs/$jobId');
      final data = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};
      return data['message']?.toString() ?? 'Заявка отменена';
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Opens an arbitration dispute for a COMPLETED or ONGOING job
  /// POST /api/jobs/:jobId/dispute
  Future<String> disputeJob({
    required String jobId,
    required String reason,
  }) async {
    try {
      final response = await _api.dio.post(
        '/jobs/$jobId/dispute',
        data: {'reason': reason.trim()},
      );
      final data = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};
      return data['message']?.toString() ??
          'Спор успешно открыт. Администратор свяжется с вами.';
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Initiates a T-Bank Safe Deal payment session and returns the checkout URL
  /// POST /api/payments/tinkoff/init
  Future<String> initiateSafeDealPayment(String jobId) async {
    try {
      final response = await _api.dio.post(
        '/payments/tinkoff/init',
        data: {'jobId': jobId},
      );

      final data = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};

      final paymentUrl =
          (data['paymentUrl'] ??
                  data['PaymentURL'] ??
                  data['url'] ??
                  (data['data'] is Map ? data['data']['paymentUrl'] : null))
              ?.toString();

      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw ApiException('Не удалось получить ссылку на оплату');
      }

      return paymentUrl;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }

  /// Uploads local photos to MinIO and creates a new PENDING job
  /// POST /api/jobs/create
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
    try {
      // 1. Upload all local photos in parallel using presigned URLs
      final List<String> uploadedUrls = await Future.wait(
        localPhotos.map(
          (file) => _uploader.uploadFileDirectly(
            file: file,
            endpoint: '/jobs/presigned-url',
            payloadData: const {},
            compress: true,
            imageContext: 'jobs',
            isGetRequest: false,
          ),
        ),
      );

      // 2. Parse optional budget string safely
      final cleanBudget = budget?.replaceAll(RegExp(r'[^\d.]'), '').trim();
      final double? parsedBudget =
          (cleanBudget != null && cleanBudget.isNotEmpty)
          ? double.tryParse(cleanBudget)
          : null;

      // 3. Submit job payload matching backend CreateJobSchema
      final response = await _api.dio.post(
        '/jobs/create',
        data: {
          'categoryId': categoryId,
          'subcategoryIds': subcategoryIds,
          'description': description.trim(),
          'pickup_address': address.trim(),
          'timing': timing,
          'photos': uploadedUrls,
          if (parsedBudget != null && parsedBudget > 0) 'budget': parsedBudget,
          if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        },
      );

      final map = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};
      return CustomerJobModel.fromJson(map);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }

  /// Uploads any newly selected photos and updates a PENDING job
  /// PATCH /api/jobs/:jobId
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
    try {
      // 1. Upload any newly added local photos to MinIO in parallel
      final List<String> uploadedUrls = newPhotos.isEmpty
          ? const []
          : await Future.wait(
              newPhotos.map(
                (file) => _uploader.uploadFileDirectly(
                  file: file,
                  endpoint: '/jobs/presigned-url',
                  payloadData: const {},
                  compress: true,
                  imageContext: 'jobs',
                  isGetRequest: false,
                ),
              ),
            );

      final allPhotos = [...existingPhotos, ...uploadedUrls];

      // 2. Parse optional budget string safely
      final cleanBudget = budget?.replaceAll(RegExp(r'[^\d.]'), '').trim();
      final double? parsedBudget =
          (cleanBudget != null && cleanBudget.isNotEmpty)
          ? double.tryParse(cleanBudget)
          : null;

      // 3. Send PATCH request matching backend UpdateJobSchema
      final response = await _api.dio.patch(
        '/jobs/$jobId',
        data: {
          'categoryId': categoryId,
          'subcategoryIds': subcategoryIds,
          'description': description.trim(),
          'pickup_address': address.trim(),
          'timing': timing,
          'photos': allPhotos,
          'budget': (parsedBudget != null && parsedBudget > 0)
              ? parsedBudget
              : null,
          if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        },
      );

      final map = response.data is Map
          ? JsonMap.from(response.data as Map)
          : <String, dynamic>{};
      return CustomerJobModel.fromJson(map);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }
}
