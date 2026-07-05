import 'package:cloud_firestore/cloud_firestore.dart';

enum MemberStatus { active, suspended, pending }

class MemberModel {
  final String id;
  final String fullName;
  final String civilId;
  final String phone;

  // Legacy single-organization fields. Keep these until services and screens
  // read organization-specific values from MembershipModel.
  final String memberNumber;
  final MemberStatus status;
  final bool isAdmin;
  final DateTime joinDate;
  final String? fcmToken;

  MemberModel({
    required this.id,
    required this.fullName,
    required this.civilId,
    required this.phone,
    required this.memberNumber,
    required this.status,
    required this.isAdmin,
    required this.joinDate,
    this.fcmToken,
  });

  factory MemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MemberModel(
      id: doc.id,
      fullName: data['fullName'] ?? '',
      civilId: data['civilId'] ?? '',
      phone: data['phone'] ?? '',
      memberNumber: data['memberNumber'] ?? '',
      status: MemberStatus.values.firstWhere(
        (e) => e.name == (data['status'] ?? 'active'),
        orElse: () => MemberStatus.active,
      ),
      isAdmin: data['isAdmin'] ?? false,
      joinDate: (data['joinDate'] as Timestamp).toDate(),
      fcmToken: data['fcmToken'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fullName': fullName,
      'civilId': civilId,
      'phone': phone,
      'memberNumber': memberNumber,
      'status': status.name,
      'isAdmin': isAdmin,
      'joinDate': Timestamp.fromDate(joinDate),
      'fcmToken': fcmToken,
    };
  }

  // During the migration, the legacy member document ID remains the stable
  // user identifier used by authentication and existing screens.
  String get userId => id;

  String get statusLabel {
    switch (status) {
      case MemberStatus.active:
        return 'نشط';
      case MemberStatus.suspended:
        return 'موقوف';
      case MemberStatus.pending:
        return 'قيد المراجعة';
    }
  }
}
