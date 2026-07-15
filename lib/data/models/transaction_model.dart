import 'package:cloud_firestore/cloud_firestore.dart';

import 'financial_models.dart';

enum TransactionStatus { submitted, underReview, approved, rejected }

enum PaymentScope { self, others, mixed }

class TransactionEvent {
  const TransactionEvent({
    required this.status,
    required this.timestamp,
    this.adminName,
    this.note,
  });

  final TransactionStatus status;
  final DateTime timestamp;
  final String? adminName;
  final String? note;

  factory TransactionEvent.fromMap(Map<String, dynamic> map) =>
      TransactionEvent(
        status: TransactionStatus.values.firstWhere(
          (item) => item.name == map['status'],
          orElse: () => TransactionStatus.submitted,
        ),
        timestamp: financialDate(map['timestamp']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        adminName: map['adminName'] as String?,
        note: map['note'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'status': status.name,
        'timestamp': Timestamp.fromDate(timestamp),
        'adminName': adminName,
        'note': note,
      };
}

class ReceiptAllocation {
  const ReceiptAllocation({
    required this.beneficiaryUserId,
    required this.beneficiaryMembershipId,
    required this.beneficiaryName,
    required this.chargeId,
    required this.chargeTitle,
    required this.amountAllocatedBaisa,
    required this.balanceBeforeBaisa,
  });

  final String beneficiaryUserId;
  final String beneficiaryMembershipId;
  final String beneficiaryName;
  final String chargeId;
  final String chargeTitle;
  final int amountAllocatedBaisa;
  final int balanceBeforeBaisa;

  factory ReceiptAllocation.fromMap(Map<String, dynamic> map) =>
      ReceiptAllocation(
        beneficiaryUserId: map['beneficiaryUserId'] as String? ?? '',
        beneficiaryMembershipId:
            map['beneficiaryMembershipId'] as String? ?? '',
        beneficiaryName: map['beneficiaryName'] as String? ?? '',
        chargeId: map['chargeId'] as String? ?? '',
        chargeTitle: map['chargeTitle'] as String? ?? '',
        amountAllocatedBaisa: baisaFrom(map['amountAllocatedBaisa'],
            legacyRialValue: map['amountAllocated']),
        balanceBeforeBaisa: baisaFrom(map['balanceBeforeBaisa'],
            legacyRialValue: map['balanceBefore']),
      );

  Map<String, dynamic> toMap() => {
        'beneficiaryUserId': beneficiaryUserId,
        'beneficiaryMembershipId': beneficiaryMembershipId,
        'beneficiaryName': beneficiaryName,
        'chargeId': chargeId,
        'chargeTitle': chargeTitle,
        'amountAllocatedBaisa': amountAllocatedBaisa,
        'balanceBeforeBaisa': balanceBeforeBaisa,
      };
}

class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.organizationId,
    required this.payerUserId,
    required this.payerMembershipId,
    required this.payerName,
    required this.paymentScope,
    required this.amountDeclaredBaisa,
    required this.allocationTotalBaisa,
    required this.differenceBaisa,
    required this.receiptUrl,
    required this.currentStatus,
    required this.submittedAt,
    this.receiptStoragePath,
    this.fileName,
    this.fileType,
    this.reviewStatus = 'pending',
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.allocations = const [],
    this.timeline = const [],
    this.memberNumber,
    this.paymentPeriod,
    this.legacyPaymentId,
  });

  final String id;
  final String organizationId;
  final String payerUserId;
  final String payerMembershipId;
  final String payerName;
  final PaymentScope paymentScope;
  final int amountDeclaredBaisa;
  final int allocationTotalBaisa;
  final int differenceBaisa;
  final String receiptUrl;
  final String? receiptStoragePath;
  final String? fileName;
  final String? fileType;
  final String reviewStatus;
  final TransactionStatus currentStatus;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  final List<ReceiptAllocation> allocations;
  final List<TransactionEvent> timeline;
  final String? memberNumber;
  final String? paymentPeriod;
  final String? legacyPaymentId;

  // Legacy aliases retained while old screens and production receipts migrate.
  String get memberId => payerUserId;
  String get userId => payerUserId;
  String get membershipId => payerMembershipId;
  String get memberName => payerName;
  String? get paymentId => legacyPaymentId;
  String? get memberPhone => null;
  double get amountDeclared => amountDeclaredBaisa / 1000;

  bool get amountsMatch =>
      differenceBaisa == 0 && amountDeclaredBaisa == allocationTotalBaisa;
  bool get paysForOthers => allocations
      .any((item) => item.beneficiaryMembershipId != payerMembershipId);

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    final declared = baisaFrom(data['amountDeclaredBaisa'],
        legacyRialValue: data['amountDeclared']);
    final allocations = (data['allocations'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReceiptAllocation.fromMap)
        .toList(growable: false);
    final allocationTotal = data['allocationTotalBaisa'] == null
        ? allocations.fold<int>(
            0, (total, item) => total + item.amountAllocatedBaisa)
        : baisaFrom(data['allocationTotalBaisa']);
    final statusName = data['currentStatus'] as String? ??
        switch (data['reviewStatus']) {
          'approved' => 'approved',
          'rejected' => 'rejected',
          _ => 'submitted',
        };
    final payerUserId = data['payerUserId'] as String? ??
        data['userId'] as String? ??
        data['memberId'] as String? ??
        '';
    final payerMembershipId = data['payerMembershipId'] as String? ??
        data['membershipId'] as String? ??
        payerUserId;
    return TransactionModel(
      id: data['transactionId'] as String? ?? doc.id,
      organizationId: data['organizationId'] as String? ??
          doc.reference.parent.parent?.id ??
          '',
      payerUserId: payerUserId,
      payerMembershipId: payerMembershipId,
      payerName:
          data['payerName'] as String? ?? data['memberName'] as String? ?? '',
      paymentScope: PaymentScope.values.firstWhere(
        (item) => item.name == data['paymentScope'],
        orElse: () => PaymentScope.self,
      ),
      amountDeclaredBaisa: declared,
      allocationTotalBaisa: allocationTotal,
      differenceBaisa: data['differenceBaisa'] == null
          ? declared - allocationTotal
          : baisaFrom(data['differenceBaisa']),
      receiptUrl: data['receiptUrl'] as String? ?? '',
      receiptStoragePath: data['receiptStoragePath'] as String?,
      fileName: data['fileName'] as String?,
      fileType: data['fileType'] as String?,
      reviewStatus: data['reviewStatus'] as String? ?? 'pending',
      currentStatus: TransactionStatus.values.firstWhere(
        (item) => item.name == statusName,
        orElse: () => TransactionStatus.submitted,
      ),
      submittedAt: financialDate(data['submittedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reviewedAt: financialDate(data['reviewedAt']),
      reviewedBy: data['reviewedBy'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      allocations: allocations,
      timeline: (data['timeline'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TransactionEvent.fromMap)
          .toList(growable: false),
      memberNumber: data['payerMemberNumber'] as String? ??
          data['memberNumber'] as String?,
      paymentPeriod: data['paymentPeriod'] as String?,
      legacyPaymentId: data['paymentId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'transactionId': id,
        'organizationId': organizationId,
        'payerUserId': payerUserId,
        'payerMembershipId': payerMembershipId,
        'payerName': payerName,
        'userId': payerUserId,
        'memberId': payerUserId,
        'membershipId': payerMembershipId,
        'memberName': payerName,
        'paymentScope': paymentScope.name,
        'amountDeclaredBaisa': amountDeclaredBaisa,
        'allocationTotalBaisa': allocationTotalBaisa,
        'differenceBaisa': differenceBaisa,
        'receiptUrl': receiptUrl,
        'receiptStoragePath': receiptStoragePath,
        'fileName': fileName,
        'fileType': fileType,
        'reviewStatus': reviewStatus,
        'status': reviewStatus == 'pending' ? 'pendingReview' : reviewStatus,
        'currentStatus': currentStatus.name,
        'submittedAt': Timestamp.fromDate(submittedAt),
        'reviewedAt':
            reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
        'reviewedBy': reviewedBy,
        'rejectionReason': rejectionReason,
        'allocations':
            allocations.map((item) => item.toMap()).toList(growable: false),
        'beneficiaryMembershipIds': allocations
            .map((item) => item.beneficiaryMembershipId)
            .toSet()
            .toList(),
        'timeline':
            timeline.map((item) => item.toMap()).toList(growable: false),
        'memberNumber': memberNumber,
        'paymentPeriod': paymentPeriod,
        'paymentId': legacyPaymentId,
      };
}
