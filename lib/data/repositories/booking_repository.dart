import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/booking_model.dart';
import 'notification_repository.dart';

class BookingRepository {
  BookingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
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

  Stream<List<BookingModel>> streamForUser(
      String organizationId, String userId) {
    return _bookings(organizationId)
        .where('userId', isEqualTo: userId)
        .orderBy('bookingDate', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(BookingModel.fromFirestore).toList());
  }

  Future<List<BookingModel>> getAvailability({
    required String organizationId,
    required DateTime month,
  }) async {
    final result =
        await _functions.httpsCallable('getBookingAvailability').call({
      'organizationId': organizationId,
      'year': month.year,
      'month': month.month,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['days'] as List? ?? const []).map((item) {
      final day = Map<String, dynamic>.from(item as Map);
      return BookingModel(
        bookingId: '',
        organizationId: organizationId,
        userId: '',
        membershipId: '',
        requesterName: '',
        requesterPhone: '',
        bookingDate: DateTime.parse(day['date'] as String).toLocal(),
        occasionType: '',
        notes: '',
        status: day['status'] as String? ?? 'pending',
      );
    }).toList();
  }

  Future<Map<String, dynamic>?> getGuestBookingCharge({
    required String organizationId,
    required String bookingId,
  }) async {
    final result =
        await _functions.httpsCallable('getGuestBookingCharge').call({
      'organizationId': organizationId,
      'bookingId': bookingId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final charge = data['charge'];
    return charge is Map ? Map<String, dynamic>.from(charge) : null;
  }

  Future<String> submitGuestBookingReceipt({
    required String organizationId,
    required String bookingId,
    required String chargeId,
    required String receiptId,
    required int amountDeclaredBaisa,
    required int balanceBeforeBaisa,
    required String receiptUrl,
    required String receiptStoragePath,
    required String fileName,
    required String fileType,
  }) async {
    final result =
        await _functions.httpsCallable('submitGuestBookingReceipt').call({
      'organizationId': organizationId,
      'bookingId': bookingId,
      'chargeId': chargeId,
      'receiptId': receiptId,
      'amountDeclaredBaisa': amountDeclaredBaisa,
      'balanceBeforeBaisa': balanceBeforeBaisa,
      'receiptUrl': receiptUrl,
      'receiptStoragePath': receiptStoragePath,
      'fileName': fileName,
      'fileType': fileType,
    });
    return Map<String, dynamic>.from(result.data as Map)['transactionId']
        as String;
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
      if (membershipId.isNotEmpty) 'membershipId': membershipId,
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

  Future<String> requestCancellation({
    required String organizationId,
    required String bookingId,
    String reason = '',
  }) async {
    final result =
        await _functions.httpsCallable('requestBookingCancellation').call({
      'organizationId': organizationId,
      'bookingId': bookingId,
      'reason': reason.trim(),
    });
    return Map<String, dynamic>.from(result.data as Map)['status'] as String;
  }

  Future<void> reviewCancellation({
    required String organizationId,
    required String bookingId,
    required bool approve,
    String reason = '',
  }) async {
    await _functions.httpsCallable('reviewBookingCancellation').call({
      'organizationId': organizationId,
      'bookingId': bookingId,
      'decision': approve ? 'approve' : 'reject',
      'reason': reason.trim(),
    });
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
