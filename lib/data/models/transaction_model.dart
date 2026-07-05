import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus { submitted, underReview, approved, rejected }

class TransactionEvent {
  final TransactionStatus status;
  final DateTime timestamp;
  final String? adminName;
  final String? note;

  TransactionEvent({
    required this.status,
    required this.timestamp,
    this.adminName,
    this.note,
  });

  factory TransactionEvent.fromMap(Map<String, dynamic> map) {
    return TransactionEvent(
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'submitted'),
        orElse: () => TransactionStatus.submitted,
      ),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      adminName: map['adminName'],
      note: map['note'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'adminName': adminName,
      'note': note,
    };
  }

  String get label {
    switch (status) {
      case TransactionStatus.submitted:
        return 'تم إرسال الإيصال';
      case TransactionStatus.underReview:
        return 'قيد المراجعة';
      case TransactionStatus.approved:
        return 'تم الاعتماد';
      case TransactionStatus.rejected:
        return 'تم الرفض';
    }
  }
}

class TransactionModel {
  final String id;
  final String memberId;
  final String? userId;
  final String? organizationId;
  final String? membershipId;
  final String? receiptStoragePath;
  final String? reviewStatus;
  final String? uploadedByUserId;
  final double? amountDeclared;
  final String? paymentPeriod;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? memberNumber;
  final String? memberPhone;
  final String memberName;
  final String paymentId;
  final String receiptUrl;
  final TransactionStatus currentStatus;
  final List<TransactionEvent> timeline;
  final DateTime submittedAt;
  final String? rejectionReason;

  TransactionModel({
    required this.id,
    required this.memberId,
    this.userId,
    this.organizationId,
    this.membershipId,
    this.receiptStoragePath,
    this.reviewStatus,
    this.uploadedByUserId,
    this.amountDeclared,
    this.paymentPeriod,
    this.reviewedBy,
    this.reviewedAt,
    this.memberNumber,
    this.memberPhone,
    required this.memberName,
    required this.paymentId,
    required this.receiptUrl,
    required this.currentStatus,
    required this.timeline,
    required this.submittedAt,
    this.rejectionReason,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final timelineData = (data['timeline'] as List<dynamic>?) ?? [];
    return TransactionModel(
      id: doc.id,
      memberId: data['memberId'] ?? '',
      userId: data['userId'] as String?,
      organizationId: data['organizationId'] as String?,
      membershipId: data['membershipId'] as String?,
      receiptStoragePath: data['receiptStoragePath'] as String?,
      reviewStatus: data['reviewStatus'] as String?,
      uploadedByUserId: data['uploadedByUserId'] as String?,
      amountDeclared: (data['amountDeclared'] as num?)?.toDouble(),
      paymentPeriod: data['paymentPeriod'] as String?,
      reviewedBy: data['reviewedBy'] as String?,
      reviewedAt: data['reviewedAt'] == null
          ? null
          : (data['reviewedAt'] as Timestamp).toDate(),
      memberNumber: data['memberNumber'] as String?,
      memberPhone: data['memberPhone'] as String?,
      memberName: data['memberName'] ?? '',
      paymentId: data['paymentId'] ?? '',
      receiptUrl: data['receiptUrl'] ?? '',
      currentStatus: TransactionStatus.values.firstWhere(
        (e) => e.name == (data['currentStatus'] ?? 'submitted'),
        orElse: () => TransactionStatus.submitted,
      ),
      timeline: timelineData
          .map((e) => TransactionEvent.fromMap(e as Map<String, dynamic>))
          .toList(),
      submittedAt: (data['submittedAt'] as Timestamp).toDate(),
      rejectionReason: data['rejectionReason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'memberId': memberId,
      'userId': userId ?? memberId,
      if (organizationId != null) 'organizationId': organizationId,
      if (membershipId != null) 'membershipId': membershipId,
      if (receiptStoragePath != null) 'receiptStoragePath': receiptStoragePath,
      'reviewStatus': reviewStatus ?? 'pending',
      'uploadedByUserId': uploadedByUserId ?? userId ?? memberId,
      if (amountDeclared != null) 'amountDeclared': amountDeclared,
      if (paymentPeriod != null) 'paymentPeriod': paymentPeriod,
      if (reviewedBy != null) 'reviewedBy': reviewedBy,
      if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
      if (memberNumber != null) 'memberNumber': memberNumber,
      if (memberPhone != null) 'memberPhone': memberPhone,
      'memberName': memberName,
      'paymentId': paymentId,
      'receiptUrl': receiptUrl,
      'currentStatus': currentStatus.name,
      'status': 'pendingReview',
      'timeline': timeline.map((e) => e.toMap()).toList(),
      'submittedAt': Timestamp.fromDate(submittedAt),
      'rejectionReason': rejectionReason,
    };
  }
}
