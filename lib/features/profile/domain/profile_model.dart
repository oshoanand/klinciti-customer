class CustomerProfileModel {
  final String id;
  final String? email;
  final String? mobile;
  final String? emailVerified;
  final String? mobileVerified;
  final String? image;
  final String? firstName;
  final String? lastName;
  final String? middleName;
  final String? city;
  final String? address;
  final String? description;
  final String? gender;
  final String? dateOfBirth;

  CustomerProfileModel({
    required this.id,
    this.email,
    this.mobile,
    this.emailVerified,
    this.mobileVerified,
    this.image,
    this.firstName,
    this.lastName,
    this.middleName,
    this.city,
    this.address,
    this.description,
    this.gender,
    this.dateOfBirth,
  });

  factory CustomerProfileModel.fromJson(Map<String, dynamic> json) {
    return CustomerProfileModel(
      id: json['id'],
      email: json['email'],
      mobile: json['mobile'],
      emailVerified: json['email_verified'],
      mobileVerified: json['mobile_verified'],
      image: json['image'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      middleName: json['middle_name'],
      city: json['city'],
      address: json['address'],
      description: json['description'],
      gender: json['gender'],
      dateOfBirth: json['date_of_birth'],
    );
  }
}
