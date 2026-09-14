import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _bookingDateFromData(Map<String, dynamic> data) {
  final rawDate = data['bookingDate'];
  if (rawDate is Timestamp) return rawDate.toDate();
  if (rawDate is DateTime) return rawDate;
  if (rawDate is String) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) return parsed;
  }

  // الحجوزات التي سبقت المخطط الحديث قد تحفظ اليوم فقط. نستخدمه للعرض
  // والترتيب بدلاً من إسقاط المستند من استعلام Firestore المرتب.
  final bookingDay = data['bookingDay'];
  if (bookingDay is String) {
    final parsed = DateTime.tryParse(bookingDay);
    if (parsed != null) return parsed;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

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
    this.bookingCategory = 'regular',
    this.startTime,
    this.endTime,
    this.rejectionReason,
    this.cancellationReason,
    this.financialChargeId,
    this.financialFeeWaived = false,
    this.financialWaiverReason,
    this.financialFeeStatus,
    this.financialAccountType,
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
  final String bookingCategory;
  final String? rejectionReason;
  final String? cancellationReason;
  final String? financialChargeId;
  final bool financialFeeWaived;
  final String? financialWaiverReason;
  final String? financialFeeStatus;
  final String? financialAccountType;

  factory BookingModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return BookingModel(
      bookingId: data['bookingId'] as String? ?? document.id,
      organizationId: data['organizationId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      membershipId: data['membershipId'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? '',
      requesterPhone: data['requesterPhone'] as String? ?? '',
      bookingDate: _bookingDateFromData(data),
      startTime: data['startTime'] as String?,
      endTime: data['endTime'] as String?,
      occasionType: data['occasionType'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      bookingCategory: data['bookingCategory'] is String &&
              ['regular', 'event'].contains(data['bookingCategory'])
          ? data['bookingCategory'] as String
          : 'regular',
      rejectionReason: data['rejectionReason'] as String?,
      cancellationReason: data['cancellationReason'] as String?,
      financialChargeId: data['financialChargeId'] as String?,
      financialFeeWaived: data['financialFeeWaived'] == true,
      financialWaiverReason: data['financialWaiverReason'] as String?,
      financialFeeStatus: data['financialFeeStatus'] as String?,
      financialAccountType: data['financialAccountType'] as String?,
    );
  }
}
