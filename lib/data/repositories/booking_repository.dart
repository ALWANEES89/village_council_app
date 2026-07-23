import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/booking_model.dart';

List<BookingModel> parseBookingAvailability(
  Map<String, dynamic> data, {
  required String organizationId,
}) {
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

class BookingRepository {
  BookingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

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
    return parseBookingAvailability(data, organizationId: organizationId);
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
    final day = '${bookingDate.year.toString().padLeft(4, '0')}-'
        '${bookingDate.month.toString().padLeft(2, '0')}-'
        '${bookingDate.day.toString().padLeft(2, '0')}';
    await _functions.httpsCallable('createBooking').call({
      'bookingId': reference.id,
      'organizationId': organizationId,
      if (membershipId.isNotEmpty) 'membershipId': membershipId,
      'requesterName': requesterName,
      'requesterPhone': requesterPhone,
      'bookingDate': day,
      if (startTime?.trim().isNotEmpty == true) 'startTime': startTime!.trim(),
      if (endTime?.trim().isNotEmpty == true) 'endTime': endTime!.trim(),
      'occasionType': occasionType.trim(),
      'notes': notes.trim(),
    });
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
    await _functions.httpsCallable('reviewBooking').call({
      'organizationId': organizationId,
      'bookingId': bookingId,
      'decision': 'approve',
    });
  }

  Future<void> reject({
    required String organizationId,
    required String bookingId,
    required String reviewedBy,
    required String rejectionReason,
  }) async {
    await _functions.httpsCallable('reviewBooking').call({
      'organizationId': organizationId,
      'bookingId': bookingId,
      'decision': 'reject',
      'reason': rejectionReason.trim(),
    });
  }
}
