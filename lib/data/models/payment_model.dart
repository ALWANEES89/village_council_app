import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { paid, unpaid, pending, rejected }

enum PaymentType { monthly, annual }

class PaymentModel {
  final String id;
  final String memberId;
  final String? organizationId;
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
    this.organizationId,
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
      organizationId: data['organizationId'] as String?,
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
      if (organizationId != null) 'organizationId': organizationId,
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
    if (type == PaymentType.annual) {
      return 'Ø§Ù„Ø§Ø´ØªØ±Ø§Ùƒ Ø§Ù„Ø³Ù†ÙˆÙŠ $year';
    }
    final months = [
      '',
      'ÙŠÙ†Ø§ÙŠØ±',
      'ÙØ¨Ø±Ø§ÙŠØ±',
      'Ù…Ø§Ø±Ø³',
      'Ø£Ø¨Ø±ÙŠÙ„',
      'Ù…Ø§ÙŠÙˆ',
      'ÙŠÙˆÙ†ÙŠÙˆ',
      'ÙŠÙˆÙ„ÙŠÙˆ',
      'Ø£ØºØ³Ø·Ø³',
      'Ø³Ø¨ØªÙ…Ø¨Ø±',
      'Ø£ÙƒØªÙˆØ¨Ø±',
      'Ù†ÙˆÙÙ…Ø¨Ø±',
      'Ø¯ÙŠØ³Ù…Ø¨Ø±'
    ];
    return '${months[month ?? 1]} $year';
  }

  String get statusLabel {
    switch (status) {
      case PaymentStatus.paid:
        return 'Ù…Ø¯ÙÙˆØ¹';
      case PaymentStatus.unpaid:
        return 'ØºÙŠØ± Ù…Ø¯ÙÙˆØ¹';
      case PaymentStatus.pending:
        return 'Ù‚ÙŠØ¯ Ø§Ù„Ù…Ø±Ø§Ø¬Ø¹Ø©';
      case PaymentStatus.rejected:
        return 'Ù…Ø±ÙÙˆØ¶';
    }
  }
}
