import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking_model.dart';
import 'notification_repository.dart';

class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  late final NotificationRepository _notifications =
      NotificationRepository(firestore: _firestore);

  CollectionReference<Map<String, dynamic>> _bookings(String organizationId) =>
      _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('bookings');

  Stream<List<BookingModel>> streamForOrganization(String organizationId) {
    return _bookings(organizationId).orderBy('bookingDate').snapshots().map(
        (snapshot) => snapshot.docs.map(BookingModel.fromFirestore).toList());
  }

  Future<void> create({
    required String organizationId,
    required String userId,
    required String membershipId,
    required String requesterName,
    required String requesterPhone,
    required DateTime bookingDate,
    required String occasionType,
    required String notes,
    String? startTime,
    String? endTime,
  }) async {
    final reference = _bookings(organizationId).doc();
    final now = FieldValue.serverTimestamp();
    await reference.set({
      'bookingId': reference.id,
      'organizationId': organizationId,
      'userId': userId,
      'membershipId': membershipId,
      'requesterName': requesterName,
      'requesterPhone': requesterPhone,
      'bookingDate': Timestamp.fromDate(DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
      )),
      if (startTime?.trim().isNotEmpty == true) 'startTime': startTime!.trim(),
      if (endTime?.trim().isNotEmpty == true) 'endTime': endTime!.trim(),
      'occasionType': occasionType.trim(),
      'notes': notes.trim(),
      'status': 'pending',
      'createdAt': now,
      'updatedAt': now,
    });
    // Notification delivery is secondary to the authoritative booking write.
    await _notifications.notifyOrganizationReviewers(
      organizationId: organizationId,
      permissions: const ['bookings.approve', 'bookings.manage'],
      title: 'طلب حجز جديد',
      body: 'يوجد طلب جديد لحجز المجلس.',
      type: 'bookingSubmitted',
      relatedEntityType: 'booking',
      relatedEntityId: reference.id,
      createdByUserId: userId,
    );
    await _notifications.createForUser(
      userId: userId,
      organizationId: organizationId,
      title: 'تم إرسال طلب الحجز',
      body: 'طلب حجز المجلس قيد المراجعة.',
      type: 'bookingReceived',
      relatedEntityType: 'booking',
      relatedEntityId: reference.id,
      createdByUserId: userId,
    );
  }

  Future<void> approve({
    required String organizationId,
    required String bookingId,
    required String reviewedBy,
  }) async {
    final reference = _bookings(organizationId).doc(bookingId);
    final snapshot = await reference.get();
    final requesterId = snapshot.data()?['userId'] as String?;
    final now = FieldValue.serverTimestamp();
    await reference.update({
      'status': 'approved',
      'approvedBy': reviewedBy,
      'approvedAt': now,
      'rejectionReason': null,
      'updatedAt': now,
    });
    if (requesterId?.isNotEmpty == true) {
      await _notifications.createForUser(
        userId: requesterId!,
        organizationId: organizationId,
        title: 'تم قبول طلب الحجز',
        body: 'تمت الموافقة على حجز المجلس.',
        type: 'bookingApproved',
        relatedEntityType: 'booking',
        relatedEntityId: bookingId,
        createdByUserId: reviewedBy,
      );
    }
  }

  Future<void> reject({
    required String organizationId,
    required String bookingId,
    required String reviewedBy,
    required String rejectionReason,
  }) async {
    final reference = _bookings(organizationId).doc(bookingId);
    final snapshot = await reference.get();
    final requesterId = snapshot.data()?['userId'] as String?;
    final reason = rejectionReason.trim();
    final now = FieldValue.serverTimestamp();
    await reference.update({
      'status': 'rejected',
      'rejectedBy': reviewedBy,
      'rejectedAt': now,
      'rejectionReason': reason,
      'updatedAt': now,
    });
    if (requesterId?.isNotEmpty == true) {
      await _notifications.createForUser(
        userId: requesterId!,
        organizationId: organizationId,
        title: 'تم رفض طلب الحجز',
        body: reason.isEmpty ? 'تم رفض طلب الحجز.' : reason,
        type: 'bookingRejected',
        relatedEntityType: 'booking',
        relatedEntityId: bookingId,
        createdByUserId: reviewedBy,
      );
    }
  }
}
