typedef JsonMap = Map<String, dynamic>;

class CustomerJobStats {
  final int pending;
  final int accepted;
  final int ongoing;
  final int paymentPending;
  final int paid;
  final int completed;
  final int disputed;
  final int cancelled;
  final int refused;

  const CustomerJobStats({
    this.pending = 0,
    this.accepted = 0,
    this.ongoing = 0,
    this.paymentPending = 0,
    this.paid = 0,
    this.completed = 0,
    this.disputed = 0,
    this.cancelled = 0,
    this.refused = 0,
  });

  factory CustomerJobStats.fromJson(JsonMap rawJson) {
    final JsonMap json = rawJson['data'] is Map
        ? JsonMap.from(rawJson['data'] as Map)
        : rawJson;

    int parseCount(String key) =>
        int.tryParse((json[key] ?? 0).toString()) ?? 0;

    return CustomerJobStats(
      pending: parseCount('PENDING'),
      accepted: parseCount('ACCEPTED'),
      ongoing: parseCount('ONGOING'),
      paymentPending: parseCount('PAYMENT_PENDING'),
      paid: parseCount('PAID'),
      completed: parseCount('COMPLETED'),
      disputed: parseCount('DISPUTED'),
      cancelled: parseCount('CANCELLED'),
      refused: parseCount('REFUSED'),
    );
  }
}

class CustomerJobModel {
  final String id;
  final String? categoryId;
  final List<String> subcategoryIds;
  final String description;
  final double budget;
  final String city;
  final String pickupAddress;
  final String status;
  final String? paymentStatus;
  final String? paymentMethod;
  final String timing;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final List<String> photos;
  final List<String> completionPhotos;
  final String? workerComment;
  final String? completionComment;

  // Assigned worker details
  final String? workerId;
  final String? workerName;
  final String? workerImage;
  final String? workerMobile;
  final double? workerRating;

  // Category metadata
  final String? categoryName;
  final String? subcategoryName;

  const CustomerJobModel({
    required this.id,
    this.categoryId,
    this.subcategoryIds = const [],
    required this.description,
    required this.budget,
    required this.city,
    required this.pickupAddress,
    required this.status,
    this.paymentStatus,
    this.paymentMethod,
    required this.timing,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.photos = const [],
    this.completionPhotos = const [],
    this.workerComment,
    this.completionComment,
    this.workerId,
    this.workerName,
    this.workerImage,
    this.workerMobile,
    this.workerRating,
    this.categoryName,
    this.subcategoryName,
  });

  /// Matches backend PAYMENT_PENDING logic:
  /// COMPLETED job where payment is NULL, PENDING, FAILED, or CANCELED
  bool get isPaymentPending {
    if (status != 'COMPLETED') return false;
    final p = paymentStatus?.toUpperCase();
    return p == null ||
        p.isEmpty ||
        p == 'PENDING' ||
        p == 'FAILED' ||
        p == 'CANCELED';
  }

  /// Matches backend PAID logic:
  /// COMPLETED job where payment is PAID, CAPTURED, or AUTHORIZED
  bool get isPaid {
    if (status != 'COMPLETED') return false;
    final p = paymentStatus?.toUpperCase();
    return p == 'PAID' || p == 'CAPTURED' || p == 'AUTHORIZED';
  }

  String get timingLabel {
    switch (timing.toLowerCase()) {
      case 'asap':
        return 'Как можно скорее';
      case 'today':
        return 'Сегодня';
      case 'week':
        return 'На этой неделе';
      case 'flexible':
        return 'Гибкий график';
      default:
        return timing;
    }
  }

  factory CustomerJobModel.fromJson(JsonMap rawJson) {
    final JsonMap json = rawJson['data'] is Map
        ? JsonMap.from(rawJson['data'] as Map)
        : rawJson;

    List<String> parseStringList(dynamic value) {
      if (value is List) {
        return value
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return const [];
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return CustomerJobModel(
      id: (json['id'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),

      categoryId: (json['category_id'] ?? json['categoryId'])?.toString(),
      subcategoryIds: parseStringList(
        json['subcategory_ids'] ?? json['subcategoryIds'],
      ),
      budget: double.tryParse((json['budget'] ?? '0').toString()) ?? 0.0,
      city: (json['city'] ?? 'Не указан').toString(),
      pickupAddress: (json['pickup_address'] ?? json['pickupAddress'] ?? '')
          .toString(),
      status: (json['status'] ?? 'PENDING').toString().toUpperCase(),
      paymentStatus: (json['payment_status'] ?? json['paymentStatus'])
          ?.toString()
          .toUpperCase(),
      paymentMethod: (json['payment_method'] ?? json['paymentMethod'])
          ?.toString(),
      timing: (json['timing'] ?? 'flexible').toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
      completedAt: parseDate(json['completed_at'] ?? json['completedAt']),
      photos: parseStringList(json['photos'] ?? json['jobs_photos']),
      completionPhotos: parseStringList(
        json['completion_photos'] ?? json['completionPhotos'],
      ),
      workerComment: (json['worker_comment'] ?? json['workerComment'])
          ?.toString(),
      completionComment:
          (json['completion_comment'] ?? json['completionComment'])?.toString(),
      workerId: (json['worker_id'] ?? json['workerId'])?.toString(),
      workerName: (json['worker_name'] ?? json['workerName'])?.toString(),
      workerImage: (json['worker_image'] ?? json['workerImage'])?.toString(),
      workerMobile: (json['worker_mobile'] ?? json['workerMobile'])?.toString(),
      workerRating: json['worker_rating'] != null
          ? double.tryParse(json['worker_rating'].toString())
          : null,
      categoryName: (json['category_name'] ?? json['categoryName'])?.toString(),
      subcategoryName: (json['subcategory_name'] ?? json['subcategoryName'])
          ?.toString(),
    );
  }
}

class PaginatedJobsState {
  final List<CustomerJobModel> items;
  final int page;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;

  const PaginatedJobsState({
    this.items = const [],
    this.page = 1,
    this.total = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  PaginatedJobsState copyWith({
    List<CustomerJobModel>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return PaginatedJobsState(
      items: items ?? this.items,
      page: page ?? this.page,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}
