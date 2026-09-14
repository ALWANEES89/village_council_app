import 'package:cloud_firestore/cloud_firestore.dart';

int _integer(dynamic value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return 0;
}

DateTime? _date(dynamic value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
        ? value
        : null;

class CouncilAnnouncement {
  const CouncilAnnouncement({
    required this.id,
    required this.organizationId,
    required this.title,
    required this.content,
    required this.createdAt,
    this.createdBy,
  });

  final String id;
  final String organizationId;
  final String title;
  final String content;
  final DateTime? createdAt;
  final String? createdBy;

  factory CouncilAnnouncement.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CouncilAnnouncement(
      id: data['announcementId'] as String? ?? document.id,
      organizationId: data['organizationId'] as String? ??
          document.reference.parent.parent?.id ??
          '',
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      createdAt: _date(data['createdAt']),
      createdBy: data['createdBy'] as String?,
    );
  }
}

class CouncilExpense {
  const CouncilExpense({
    required this.id,
    required this.organizationId,
    required this.title,
    required this.category,
    required this.amountBaisa,
    required this.expenseDate,
    required this.createdAt,
    this.status = 'posted',
    this.note,
    this.supplier,
    this.invoiceNumber,
    this.attachmentStoragePath,
    this.createdBy,
  });

  final String id;
  final String organizationId;
  final String title;
  final String category;
  final int amountBaisa;
  final DateTime? expenseDate;
  final DateTime? createdAt;
  final String status;
  final String? note;
  final String? supplier;
  final String? invoiceNumber;
  final String? attachmentStoragePath;
  final String? createdBy;

  factory CouncilExpense.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CouncilExpense(
      id: data['expenseId'] as String? ?? document.id,
      organizationId: data['organizationId'] as String? ??
          document.reference.parent.parent?.id ??
          '',
      title: data['title'] as String? ?? '',
      category: data['category'] as String? ?? 'other',
      amountBaisa: _integer(data['amountBaisa']),
      expenseDate: _date(data['expenseDate']),
      createdAt: _date(data['createdAt']),
      status: data['status'] as String? ?? 'posted',
      note: data['note'] as String?,
      supplier: data['supplier'] as String?,
      invoiceNumber: data['invoiceNumber'] as String?,
      attachmentStoragePath: data['attachmentStoragePath'] as String?,
      createdBy: data['createdBy'] as String?,
    );
  }
}

class CouncilStaffPerformance {
  const CouncilStaffPerformance({
    required this.userId,
    required this.displayName,
    required this.receiptsApproved,
    required this.receiptsRejected,
    required this.bookingsApproved,
    required this.bookingsRejected,
  });

  final String userId;
  final String displayName;
  final int receiptsApproved;
  final int receiptsRejected;
  final int bookingsApproved;
  final int bookingsRejected;

  int get totalActions =>
      receiptsApproved + receiptsRejected + bookingsApproved + bookingsRejected;

  factory CouncilStaffPerformance.fromMap(Map<String, dynamic> data) =>
      CouncilStaffPerformance(
        userId: data['userId'] as String? ?? '',
        displayName: data['displayName'] as String? ?? 'مستخدم إداري',
        receiptsApproved: _integer(data['receiptsApproved']),
        receiptsRejected: _integer(data['receiptsRejected']),
        bookingsApproved: _integer(data['bookingsApproved']),
        bookingsRejected: _integer(data['bookingsRejected']),
      );
}

class CouncilFinancialReport {
  const CouncilFinancialReport({
    required this.organizationId,
    required this.totalCollectedBaisa,
    required this.totalExpensesBaisa,
    required this.netBalanceBaisa,
    required this.totalDueBaisa,
    required this.totalPaidBaisa,
    required this.totalOutstandingBaisa,
    required this.transactionCount,
    required this.chargeCount,
    required this.paidChargeCount,
    required this.openChargeCount,
    required this.membersPaidCount,
    required this.membersUnpaidCount,
    required this.expenseCount,
    required this.revenueByCategory,
    required this.expenseByCategory,
    required this.bookingCounts,
    required this.staffPerformance,
  });

  final String organizationId;
  final int totalCollectedBaisa;
  final int totalExpensesBaisa;
  final int netBalanceBaisa;
  final int totalDueBaisa;
  final int totalPaidBaisa;
  final int totalOutstandingBaisa;
  final int transactionCount;
  final int chargeCount;
  final int paidChargeCount;
  final int openChargeCount;
  final int membersPaidCount;
  final int membersUnpaidCount;
  final int expenseCount;
  final Map<String, int> revenueByCategory;
  final Map<String, int> expenseByCategory;
  final Map<String, int> bookingCounts;
  final List<CouncilStaffPerformance> staffPerformance;

  factory CouncilFinancialReport.fromMap(Map<String, dynamic> data) {
    Map<String, int> intMap(dynamic value) {
      if (value is! Map) return const <String, int>{};
      return Map<String, int>.unmodifiable({
        for (final entry in value.entries)
          entry.key.toString(): _integer(entry.value),
      });
    }

    final staff = (data['staffPerformance'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => CouncilStaffPerformance.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
    return CouncilFinancialReport(
      organizationId: data['organizationId'] as String? ?? '',
      totalCollectedBaisa: _integer(data['totalCollectedBaisa']),
      totalExpensesBaisa: _integer(data['totalExpensesBaisa']),
      netBalanceBaisa: _integer(data['netBalanceBaisa']),
      totalDueBaisa: _integer(data['totalDueBaisa']),
      totalPaidBaisa: _integer(data['totalPaidBaisa']),
      totalOutstandingBaisa: _integer(data['totalOutstandingBaisa']),
      transactionCount: _integer(data['transactionCount']),
      chargeCount: _integer(data['chargeCount']),
      paidChargeCount: _integer(data['paidChargeCount']),
      openChargeCount: _integer(data['openChargeCount']),
      membersPaidCount: _integer(data['membersPaidCount']),
      membersUnpaidCount: _integer(data['membersUnpaidCount']),
      expenseCount: _integer(data['expenseCount']),
      revenueByCategory: intMap(data['revenueByCategory']),
      expenseByCategory: intMap(data['expenseByCategory']),
      bookingCounts: intMap(data['bookingCounts']),
      staffPerformance: staff,
    );
  }
}

class CouncilActivityDetail {
  const CouncilActivityDetail({
    required this.entityType,
    required this.entityId,
    required this.organizationId,
    required this.title,
    required this.status,
    required this.amountBaisa,
    required this.submittedByName,
    required this.reviewedByName,
    required this.createdAt,
    required this.reviewedAt,
    required this.rejectionReason,
    required this.content,
  });

  final String entityType;
  final String entityId;
  final String organizationId;
  final String title;
  final String status;
  final int amountBaisa;
  final String submittedByName;
  final String reviewedByName;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String rejectionReason;
  final String content;

  factory CouncilActivityDetail.fromMap(Map<String, dynamic> data) =>
      CouncilActivityDetail(
        entityType: data['entityType'] as String? ?? '',
        entityId: data['entityId'] as String? ?? '',
        organizationId: data['organizationId'] as String? ?? '',
        title: data['title'] as String? ?? '',
        status: data['status'] as String? ?? '',
        amountBaisa: _integer(data['amountBaisa']),
        submittedByName: data['submittedByName'] as String? ?? '',
        reviewedByName: data['reviewedByName'] as String? ?? '',
        createdAt: data['createdAtMillis'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                data['createdAtMillis'] as int)
            : null,
        reviewedAt: data['reviewedAtMillis'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                data['reviewedAtMillis'] as int)
            : null,
        rejectionReason: data['rejectionReason'] as String? ?? '',
        content: data['content'] as String? ?? '',
      );
}
