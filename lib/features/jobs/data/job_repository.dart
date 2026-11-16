import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../domain/job_model.dart';

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return JobRepository(ref.watch(apiClientProvider));
});

class JobRepository {
  final ApiClient _api;

  JobRepository(this._api);

  Future<List<JobModel>> fetchCustomerJobs() async {
    try {
      final res = await _api.dio.get('/jobs/customer/list');
      final List data = res.data;
      return data.map((e) => JobModel.fromJson(e)).toList();
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<JobModel> fetchJobDetails(String jobId) async {
    try {
      final res = await _api.dio.get('/jobs/$jobId');
      return JobModel.fromJson(res.data);
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> createJob({
    required String categoryId,
    required List<String> subcategoryIds,
    required String description,
    required String address,
    required String timing,
    required String? budget,
    required List<File> localPhotos,
  }) async {
    try {
      final List<String> uploadedPhotoUrls = await _uploadPhotos(localPhotos);

      await _api.dio.post(
        '/jobs/create',
        data: {
          'description': description,
          'categoryId': categoryId,
          'subcategoryIds': subcategoryIds,
          'timing': timing,
          'photos': uploadedPhotoUrls,
          'budget': budget != null && budget.isNotEmpty
              ? double.parse(budget)
              : null,
          'pickup_address': address,
        },
      );
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> updateJob({
    required String jobId,
    required String categoryId,
    required List<String> subcategoryIds,
    required String description,
    required String address,
    required String timing,
    required String? budget,
    required List<String> existingPhotos,
    required List<File> newPhotos,
  }) async {
    try {
      final List<String> newlyUploadedUrls = await _uploadPhotos(newPhotos);
      final List<String> allPhotos = [...existingPhotos, ...newlyUploadedUrls];

      if (allPhotos.isEmpty) throw ApiException('Добавьте хотя бы одно фото');

      await _api.dio.patch(
        '/jobs/$jobId',
        data: {
          'description': description,
          'categoryId': categoryId,
          'subcategoryIds': subcategoryIds,
          'timing': timing,
          'photos': allPhotos,
          'budget': budget != null && budget.isNotEmpty
              ? double.parse(budget)
              : null,
          'pickup_address': address,
        },
      );
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteJob(String jobId) async {
    try {
      await _api.dio.delete('/jobs/$jobId');
    } catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- INTERNAL HELPER: MinIO Upload ---
  Future<List<String>> _uploadPhotos(List<File> files) async {
    final List<String> finalUrls = [];

    for (var file in files) {
      final fileName = p.basename(file.path);

      // 1. Get the presigned URL from the backend
      final presignedRes = await _api.dio.post(
        '/jobs/presigned-url',
        data: {'fileName': fileName},
      );

      // Fallback support depending on exact backend response naming
      // No IP replacements here - we use the exact signed URL from the backend!
      final String uploadUrl =
          presignedRes.data['presignedUrl'] ?? presignedRes.data['url'];
      final String finalImageUrl =
          presignedRes.data['publicUrl'] ?? presignedRes.data['fileUrl'];

      // 2. Determine mimeType
      String contentType = presignedRes.data['mimeType'] ?? 'image/jpeg';
      if (presignedRes.data['mimeType'] == null) {
        if (fileName.toLowerCase().endsWith('.png')) {
          contentType = 'image/png';
        } else if (fileName.toLowerCase().endsWith('.webp')) {
          contentType = 'image/webp';
        } else if (fileName.toLowerCase().endsWith('.avif')) {
          contentType = 'image/avif';
        } else if (fileName.toLowerCase().endsWith('.heic')) {
          contentType = 'image/heic';
        }
      }

      // 3. Setup raw Dio with timeouts
      final rawDio = Dio(
        BaseOptions(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final fileLength = await file.length();

      // 4. PUT the file to MinIO
      await rawDio.put(
        uploadUrl,
        data: file.openRead(), // Streaming instantly
        options: Options(
          headers: {
            Headers.contentLengthHeader: fileLength,
            Headers.contentTypeHeader: contentType,
          },
        ),
      );

      finalUrls.add(finalImageUrl);
    }

    return finalUrls;
  }
}
