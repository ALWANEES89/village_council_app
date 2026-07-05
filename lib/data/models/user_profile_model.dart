import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  const UserProfileModel({
    required this.userId,
    this.fullName = '',
    this.civilId = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.photoUrl,
  });

  final String userId;
  final String fullName;
  final String civilId;
  final String phone;
  final String email;
  final String address;
  final String? photoUrl;

  factory UserProfileModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return UserProfileModel(
      userId: data['userId'] as String? ?? document.id,
      fullName: data['fullName'] as String? ?? '',
      civilId: data['civilId'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      email: data['email'] as String? ?? '',
      address: data['address'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'fullName': fullName,
      'civilId': civilId,
      'phone': phone,
      'email': email,
      'address': address,
      'photoUrl': photoUrl,
    };
  }
}
