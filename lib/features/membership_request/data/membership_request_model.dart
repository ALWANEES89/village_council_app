import 'package:cloud_firestore/cloud_firestore.dart';

enum MembershipRequestStatus {
  pending,
  approved,
  rejected,
  cancelled,
}

class MembershipRequestModel {
  final String requestId;
  final String organizationId;
  final String userId;
  final String fullName;
  final String civilId;
  final String phone;
  final String email;
  final String address;
  final String requestedRole;
  final MembershipRequestStatus status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  final String? notes;

  const MembershipRequestModel({
    required this.requestId,
    required this.organizationId,
    required this.userId,
    required this.fullName,
    required this.civilId,
    required this.phone,
    required this.email,
    required this.address,
    required this.requestedRole,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.notes,
  });

  factory MembershipRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MembershipRequestModel(
      requestId: data['requestId'] ?? doc.id,
      organizationId: data['organizationId'] ?? '',
      userId: data['userId'] ?? '',
      fullName: data['fullName'] ?? '',
      civilId: data['civilId'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      address: data['address'] ?? '',
      requestedRole: data['requestedRole'] ?? 'member',
      status: MembershipRequestStatus.values.firstWhere(
        (status) => status.name == (data['status'] ?? 'pending'),
        orElse: () => MembershipRequestStatus.pending,
      ),
      submittedAt: _requiredDateTime(
        data['submittedAt'],
        'submittedAt',
        doc.id,
      ),
      reviewedAt: _optionalDateTime(data['reviewedAt']),
      reviewedBy: data['reviewedBy'],
      rejectionReason: data['rejectionReason'],
      notes: data['notes'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'requestId': requestId,
      'organizationId': organizationId,
      'userId': userId,
      'fullName': fullName,
      'civilId': civilId,
      'phone': phone,
      'email': email,
      'address': address,
      'requestedRole': requestedRole,
      'status': status.name,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'reviewedAt': reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
      'reviewedBy': reviewedBy,
      'rejectionReason': rejectionReason,
      'notes': notes,
    };
  }
}

DateTime _requiredDateTime(dynamic value, String field, String documentId) {
  final dateTime = _optionalDateTime(value);
  if (dateTime != null) return dateTime;
  throw StateError(
    'Membership request $documentId is missing $field.',
  );
}

DateTime? _optionalDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
