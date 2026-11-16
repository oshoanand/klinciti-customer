class JobModel {
  final String id;
  final String description;
  final String categoryId;
  final List<String> subcategoryIds; // ✅ CHANGED to List<String>
  final String status;
  final List<String> photos;
  final double budget;
  final String pickupAddress;
  final String? timing;
  final DateTime createdAt;

  JobModel({
    required this.id,
    required this.description,
    required this.categoryId,
    required this.subcategoryIds,
    required this.status,
    required this.photos,
    required this.budget,
    required this.pickupAddress,
    this.timing,
    required this.createdAt,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      id: json['id'],
      description: json['description'] ?? '',
      categoryId: json['category_id'] ?? '',

      subcategoryIds:
          (json['subcategory_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      status: json['status'] ?? 'PENDING',
      photos:
          (json['photos'] as List?)?.map((e) => e.toString()).toList() ?? [],
      budget: (json['budget'] != null)
          ? double.tryParse(json['budget'].toString()) ?? 0.0
          : 0.0,
      pickupAddress: json['pickup_address'] ?? '',
      timing: json['timing'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
