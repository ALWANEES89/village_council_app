import 'package:cloud_firestore/cloud_firestore.dart';

class BookingModel {
  const BookingModel({
    required this.bookingId,
    required this.organizationId,
    required this.userId,
    required this.membershipId,
    required this.requesterName,
    required this.requesterPhone,
    required this.bookingDate,
    required this.occasionType,
    required this.notes,
    required this.status,
    this.startTime,
    this.endTime,
    this.rejectionReason,
  });

  final String bookingId;
  final String organizationId;
  final String userId;
  final String membershipId;
  final String requesterName;
  final String requesterPhone;
  final DateTime bookingDate;
  final String? startTime;
  final String? endTime;
  final String occasionType;
  final String notes;
  final String status;
  final String? rejectionReason;

  factory BookingModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawDate = data['bookingDate'];
    return BookingModel(
      bookingId: data['bookingId'] as String? ?? document.id,
      organizationId: data['organizationId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      membershipId: data['membershipId'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? '',
      requesterPhone: data['requesterPhone'] as String? ?? '',
      bookingDate: rawDate is Timestamp
          ? rawDate.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      startTime: data['startTime'] as String?,
      endTime: data['endTime'] as String?,
      occasionType: data['occasionType'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}
