import 'package:cloud_firestore/cloud_firestore.dart';

enum FinancialFeeMode {
  free,
  subscription,
  booking,
  subscriptionAndBooking,
}

enum BillingCycle { monthly, annual, oneTime }

enum FeeOverrideType { defaultFee, exempt, custom }

enum ChargeType { subscription, booking, event, other }

enum ChargeStatus {
  unpaid,
  partial,
  pendingReview,
  paid,
  waived,
  overdue,
  rejected,
  cancelled,
  refundRequired,
}

class ReceiptUploadArguments {
  const ReceiptUploadArguments({
    this.paymentId,
    this.periodLabel = 'إيصال دفع',
    this.organizationId,
    this.membershipId,
    this.userId,
    this.amountDeclaredBaisa,
  });

  final String? paymentId;
  final String periodLabel;
  final String? organizationId;
  final String? membershipId;
  final String? userId;
  final int? amountDeclaredBaisa;
}

int baisaFrom(dynamic value, {dynamic legacyRialValue}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (legacyRialValue is num) return (legacyRialValue * 1000).round();
  return 0;
}

DateTime? financialDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String formatBaisa(int value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  return '$sign${absolute ~/ 1000}.${(absolute % 1000).toString().padLeft(3, '0')} ر.ع';
}

int? parseOmaniRialsToBaisa(String input) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var normalized = input.trim().replaceAll(',', '.').replaceAll('٫', '.');
  for (var index = 0; index < arabicDigits.length; index += 1) {
    normalized = normalized.replaceAll(arabicDigits[index], '$index');
  }
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final rials = int.tryParse(parts.first);
  if (rials == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  return rials * 1000 + int.parse(fraction.padRight(3, '0').ifEmpty('0'));
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class FinancialSettings {
  const FinancialSettings({
    required this.organizationId,
    this.currency = 'OMR',
    this.feeMode = FinancialFeeMode.free,
    this.receiptPaymentsEnabled = true,
    this.onlinePaymentsEnabled = false,
    this.onlinePaymentProvider,
    this.allowMonthlyPlans = true,
    this.allowAnnualPlans = true,
    this.memberBookingFeeBaisa = 0,
    this.nonMemberBookingFeeBaisa = 0,
    this.eventBookingFeeBaisa = 0,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
  });

  final String organizationId;
  final String currency;
  final FinancialFeeMode feeMode;
  final bool receiptPaymentsEnabled;
  final bool onlinePaymentsEnabled;
  final String? onlinePaymentProvider;
  final bool allowMonthlyPlans;
  final bool allowAnnualPlans;
  final int memberBookingFeeBaisa;
  final int nonMemberBookingFeeBaisa;
  final int eventBookingFeeBaisa;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get isFree => feeMode == FinancialFeeMode.free;
  bool get supportsSubscriptions =>
      feeMode == FinancialFeeMode.subscription ||
      feeMode == FinancialFeeMode.subscriptionAndBooking;

  factory FinancialSettings.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    return FinancialSettings(
      organizationId: data['organizationId'] as String? ??
          doc.reference.parent.parent?.id ??
          '',
      currency: data['currency'] as String? ?? 'OMR',
      feeMode: FinancialFeeMode.values.firstWhere(
        (item) => item.name == data['feeMode'],
        orElse: () => FinancialFeeMode.free,
      ),
      receiptPaymentsEnabled: data['receiptPaymentsEnabled'] != false,
      onlinePaymentsEnabled: data['onlinePaymentsEnabled'] == true,
      onlinePaymentProvider: data['onlinePaymentProvider'] as String?,
      allowMonthlyPlans: data['allowMonthlyPlans'] != false,
      allowAnnualPlans: data['allowAnnualPlans'] != false,
      memberBookingFeeBaisa: baisaFrom(data['memberBookingFeeBaisa'],
          legacyRialValue: data['memberBookingFee']),
      nonMemberBookingFeeBaisa: baisaFrom(data['nonMemberBookingFeeBaisa'],
          legacyRialValue: data['nonMemberBookingFee']),
      eventBookingFeeBaisa: baisaFrom(data['eventBookingFeeBaisa'],
          legacyRialValue: data['eventBookingFee']),
      createdAt: financialDate(data['createdAt']),
      updatedAt: financialDate(data['updatedAt']),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore(String actorId) => {
        'organizationId': organizationId,
        'currency': 'OMR',
        'feeMode': feeMode.name,
        'receiptPaymentsEnabled': receiptPaymentsEnabled,
        'onlinePaymentsEnabled': false,
        'onlinePaymentProvider': null,
        'allowMonthlyPlans': allowMonthlyPlans,
        'allowAnnualPlans': allowAnnualPlans,
        'memberBookingFeeBaisa': memberBookingFeeBaisa,
        'nonMemberBookingFeeBaisa': nonMemberBookingFeeBaisa,
        'eventBookingFeeBaisa': eventBookingFeeBaisa,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': actorId,
      };
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.organizationId,
    required this.nameArabic,
    required this.descriptionArabic,
    required this.billingCycle,
    required this.amountBaisa,
    required this.active,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String organizationId;
  final String nameArabic;
  final String descriptionArabic;
  final BillingCycle billingCycle;
  final int amountBaisa;
  final bool active;
  final DateTime? startDate;
  final DateTime? endDate;

  factory SubscriptionPlan.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionPlan(
      id: data['planId'] as String? ?? doc.id,
      organizationId: data['organizationId'] as String? ?? '',
      nameArabic: data['nameArabic'] as String? ?? '',
      descriptionArabic: data['descriptionArabic'] as String? ?? '',
      billingCycle: BillingCycle.values.firstWhere(
        (item) => item.name == data['billingCycle'],
        orElse: () => BillingCycle.monthly,
      ),
      amountBaisa:
          baisaFrom(data['amountBaisa'], legacyRialValue: data['amount']),
      active: data['active'] != false,
      startDate: financialDate(data['startDate']),
      endDate: financialDate(data['endDate']),
    );
  }
}

class MemberAccount {
  const MemberAccount({
    required this.organizationId,
    required this.membershipId,
    required this.userId,
    this.planId,
    this.planNameArabic,
    this.subscriptionStatus = 'inactive',
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.feeOverrideType = FeeOverrideType.defaultFee,
    this.customAmountBaisa,
    this.exemptionReason,
  });

  final String organizationId;
  final String membershipId;
  final String userId;
  final String? planId;
  final String? planNameArabic;
  final String subscriptionStatus;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final FeeOverrideType feeOverrideType;
  final int? customAmountBaisa;
  final String? exemptionReason;

  bool get isExempt => feeOverrideType == FeeOverrideType.exempt;

  factory MemberAccount.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MemberAccount(
      organizationId: data['organizationId'] as String? ?? '',
      membershipId: data['membershipId'] as String? ?? doc.id,
      userId: data['userId'] as String? ?? '',
      planId: data['planId'] as String?,
      planNameArabic: data['planNameArabic'] as String?,
      subscriptionStatus: data['subscriptionStatus'] as String? ?? 'inactive',
      subscriptionStartDate: financialDate(data['subscriptionStartDate']),
      subscriptionEndDate: financialDate(data['subscriptionEndDate']),
      feeOverrideType: FeeOverrideType.values.firstWhere(
        (item) =>
            (item == FeeOverrideType.defaultFee ? 'default' : item.name) ==
            data['feeOverrideType'],
        orElse: () => FeeOverrideType.defaultFee,
      ),
      customAmountBaisa: data['customAmountBaisa'] == null
          ? null
          : baisaFrom(data['customAmountBaisa']),
      exemptionReason: data['exemptionReason'] as String?,
    );
  }
}

class FinancialCharge {
  const FinancialCharge({
    required this.id,
    required this.organizationId,
    required this.membershipId,
    required this.userId,
    required this.chargeType,
    required this.titleArabic,
    required this.amountDueBaisa,
    required this.amountPaidBaisa,
    required this.balanceBaisa,
    required this.status,
    this.sourceId,
    this.periodKey,
    this.idempotencyKey,
    this.descriptionArabic,
    this.dueDate,
    this.lastTransactionId,
    this.lastPayerName,
  });

  final String id;
  final String organizationId;
  final String membershipId;
  final String userId;
  final ChargeType chargeType;
  final String? sourceId;
  final String? periodKey;
  final String? idempotencyKey;
  final String titleArabic;
  final String? descriptionArabic;
  final int amountDueBaisa;
  final int amountPaidBaisa;
  final int balanceBaisa;
  final DateTime? dueDate;
  final ChargeStatus status;
  final String? lastTransactionId;
  final String? lastPayerName;

  bool get isPayable =>
      balanceBaisa > 0 &&
      const {
        ChargeStatus.unpaid,
        ChargeStatus.partial,
        ChargeStatus.rejected,
        ChargeStatus.overdue,
      }.contains(status);

  factory FinancialCharge.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FinancialCharge.fromMap(data, fallbackId: doc.id);
  }

  factory FinancialCharge.fromMap(
    Map<String, dynamic> data, {
    String? fallbackId,
  }) {
    final due = baisaFrom(data['amountDueBaisa'],
        legacyRialValue: data['amountDue'] ?? data['amount']);
    final paid =
        baisaFrom(data['amountPaidBaisa'], legacyRialValue: data['amountPaid']);
    return FinancialCharge(
      id: data['chargeId'] as String? ?? fallbackId ?? '',
      organizationId: data['organizationId'] as String? ?? '',
      membershipId:
          data['membershipId'] as String? ?? data['memberId'] as String? ?? '',
      userId: data['userId'] as String? ?? data['memberId'] as String? ?? '',
      chargeType: ChargeType.values.firstWhere(
        (item) => item.name == data['chargeType'],
        orElse: () => ChargeType.other,
      ),
      sourceId: data['sourceId'] as String?,
      periodKey: data['periodKey'] as String?,
      idempotencyKey: data['idempotencyKey'] as String?,
      titleArabic:
          data['titleArabic'] as String? ?? data['title'] as String? ?? 'رسم',
      descriptionArabic: data['descriptionArabic'] as String?,
      amountDueBaisa: due,
      amountPaidBaisa: paid,
      balanceBaisa: data['balanceBaisa'] == null
          ? (due - paid).clamp(0, due).toInt()
          : baisaFrom(data['balanceBaisa']),
      dueDate: financialDate(data['dueDate']),
      status: ChargeStatus.values.firstWhere(
        (item) =>
            item.name == data['status'] ||
            (item == ChargeStatus.pendingReview && data['status'] == 'pending'),
        orElse: () => ChargeStatus.unpaid,
      ),
      lastTransactionId: data['lastTransactionId'] as String? ??
          data['transactionId'] as String?,
      lastPayerName: data['lastPayerName'] as String?,
    );
  }
}

class MemberDirectoryEntry {
  const MemberDirectoryEntry({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    required this.memberNumber,
    this.photoUrl,
  });

  final String membershipId;
  final String userId;
  final String fullName;
  final String memberNumber;
  final String? photoUrl;

  factory MemberDirectoryEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MemberDirectoryEntry.fromMap(data, fallbackMembershipId: doc.id);
  }

  factory MemberDirectoryEntry.fromMap(
    Map<String, dynamic> data, {
    String? fallbackMembershipId,
  }) {
    return MemberDirectoryEntry(
      membershipId:
          data['membershipId'] as String? ?? fallbackMembershipId ?? '',
      userId: data['userId'] as String? ?? '',
      fullName: data['fullName'] as String? ?? '',
      memberNumber: data['memberNumber'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
    );
  }
}

String normalizeArabicSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
    .replaceAll('ـ', '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
