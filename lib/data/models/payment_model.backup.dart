import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { paid, unpaid, pending, rejected }
enum PaymentType { monthly, annual }

class PaymentModel {
  final String id;
  final String memberId;
  final PaymentType type;
  final int year;
  final int? month;
  final double amount;
  final PaymentStatus status;
  final DateTime? paidDate;
  final String? receiptUrl;
  final String? transactionId;

  PaymentModel({
    required this.id,
    required this.memberId,
    required this.type,
    required this.year,
    this.month,
    required this.amount,
    required this.status,
    this.paidDate,
    this.receiptUrl,
    this.transactionId,
  });

  factory PaymentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentModel(
      id: doc.id,
      memberId: data['memberId'] ?? '',
      type: PaymentType.values.firstWhere(
        (e) => e.name == (data['type'] ?? 'monthly'),
        orElse: () => PaymentType.monthly,
      ),
      year: data['year'] ?? DateTime.now().year,
      month: data['month'],
      amount: (data['amount'] ?? 0.0).toDouble(),
      status: PaymentStatus.values.firstWhere(
        (e) => e.name == (data['status'] ?? 'unpaid'),
        orElse: () => PaymentStatus.unpaid,
      ),
      paidDate: data['paidDate'] != null
          ? (data['paidDate'] as Timestamp).toDate()
          : null,
      receiptUrl: data['receiptUrl'],
      transactionId: data['transactionId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'memberId': memberId,
      'type': type.name,
      'year': year,
      'month': month,
      'amount': amount,
      'status': status.name,
      'paidDate': paidDate != null ? Timestamp.fromDate(paidDate!) : null,
      'receiptUrl': receiptUrl,
      'transactionId': transactionId,
    };
  }

  String get periodLabel {
    if (type == PaymentType.annual) return 'الاشتراك السنوي $year';
    final months = [
      '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${months[month ?? 1]} $year';
  }

  String get statusLabel {
    switch (status) {
      case PaymentStatus.paid:
        return 'مدفوع';
      case PaymentStatus.unpaid:
        return 'غير مدفوع';
      case PaymentStatus.pending:
        return 'قيد المراجعة';
      case PaymentStatus.rejected:
        return 'مرفوض';
    }
  }
}
