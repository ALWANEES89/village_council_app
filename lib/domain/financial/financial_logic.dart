import '../../data/models/financial_models.dart';
import '../../data/models/transaction_model.dart';

enum FinancialDashboardState {
  loading,
  empty,
  free,
  regular,
  due,
  partial,
  pendingReview,
  paid,
  overdue,
  exempt,
  error,
}

/// حالات التصفية في دليل الحسابات المالية للإدارة.
///
/// تبقى [regular] حالة مجمعة للعضو الذي لا يملك التزامًا مفتوحًا، بينما تمثل
/// بقية القيم حالات الرسوم الفعلية المخزنة. قد يظهر العضو في أكثر من تصفية
/// تفصيلية عندما يملك عدة رسوم بحالات مختلفة.
enum FinancialMemberFilter {
  all,
  regular,
  unpaid,
  partial,
  overdue,
  pendingReview,
  paid,
  exempt,
  rejected,
  cancelled,
  refundRequired,
}

bool memberMatchesFinancialFilter({
  required FinancialMemberFilter filter,
  required Iterable<FinancialCharge> charges,
}) {
  final items = charges.toList(growable: false);
  return switch (filter) {
    FinancialMemberFilter.all => true,
    FinancialMemberFilter.regular => items.every(_isSettledFinancialCharge),
    FinancialMemberFilter.unpaid =>
      items.any((item) => item.status == ChargeStatus.unpaid),
    FinancialMemberFilter.partial =>
      items.any((item) => item.status == ChargeStatus.partial),
    FinancialMemberFilter.overdue =>
      items.any((item) => item.status == ChargeStatus.overdue),
    FinancialMemberFilter.pendingReview => items.any((item) =>
        item.status == ChargeStatus.pendingReview || item.hasPendingReceipt),
    FinancialMemberFilter.paid =>
      items.any((item) => item.status == ChargeStatus.paid),
    FinancialMemberFilter.exempt =>
      items.any((item) => item.status == ChargeStatus.waived),
    FinancialMemberFilter.rejected =>
      items.any((item) => item.status == ChargeStatus.rejected),
    FinancialMemberFilter.cancelled =>
      items.any((item) => item.status == ChargeStatus.cancelled),
    FinancialMemberFilter.refundRequired =>
      items.any((item) => item.status == ChargeStatus.refundRequired),
  };
}

bool _isSettledFinancialCharge(FinancialCharge charge) {
  if (charge.hasPendingReceipt) return false;
  return switch (charge.status) {
    ChargeStatus.paid || ChargeStatus.waived || ChargeStatus.cancelled => true,
    ChargeStatus.unpaid ||
    ChargeStatus.partial ||
    ChargeStatus.pendingReview ||
    ChargeStatus.overdue ||
    ChargeStatus.rejected ||
    ChargeStatus.refundRequired =>
      false,
  };
}

class FinancialChargeSummary {
  const FinancialChargeSummary({
    required this.dueInvoiceCount,
    required this.paidInvoiceCount,
    required this.totalPaidBaisa,
    required this.totalBalanceBaisa,
  });

  final int dueInvoiceCount;
  final int paidInvoiceCount;
  final int totalPaidBaisa;
  final int totalBalanceBaisa;
}

FinancialChargeSummary summarizeFinancialCharges(
  Iterable<FinancialCharge> charges,
) {
  var dueInvoiceCount = 0;
  var paidInvoiceCount = 0;
  var totalPaidBaisa = 0;
  var totalBalanceBaisa = 0;
  const nonPayableStatuses = {
    ChargeStatus.waived,
    ChargeStatus.cancelled,
    ChargeStatus.refundRequired,
  };

  for (final charge in charges) {
    totalPaidBaisa += charge.amountPaidBaisa;
    if (charge.status == ChargeStatus.paid) {
      paidInvoiceCount += 1;
    }
    if (charge.balanceBaisa > 0 &&
        !nonPayableStatuses.contains(charge.status)) {
      dueInvoiceCount += 1;
      totalBalanceBaisa += charge.balanceBaisa;
    }
  }

  return FinancialChargeSummary(
    dueInvoiceCount: dueInvoiceCount,
    paidInvoiceCount: paidInvoiceCount,
    totalPaidBaisa: totalPaidBaisa,
    totalBalanceBaisa: totalBalanceBaisa,
  );
}

class ReceiptDraftValidation {
  const ReceiptDraftValidation(
      {required this.allocationTotalBaisa, required this.errors});
  final int allocationTotalBaisa;
  final List<String> errors;
  bool get isValid => errors.isEmpty;
  int differenceFrom(int declaredBaisa) => declaredBaisa - allocationTotalBaisa;
}

ReceiptDraftValidation validateReceiptDraft({
  required int declaredBaisa,
  required List<ReceiptAllocation> allocations,
}) {
  final errors = <String>[];
  final seenCharges = <String>{};
  var total = 0;
  if (declaredBaisa <= 0) errors.add('invalidDeclaredAmount');
  if (allocations.isEmpty) errors.add('missingAllocations');
  for (final allocation in allocations) {
    total += allocation.amountAllocatedBaisa;
    if (!seenCharges.add(allocation.chargeId)) {
      errors.add('duplicateCharge');
    }
    if (allocation.amountAllocatedBaisa <= 0) {
      errors.add('invalidAllocation');
    }
    if (allocation.amountAllocatedBaisa > allocation.balanceBeforeBaisa) {
      errors.add('overpayment');
    }
  }
  if (declaredBaisa != total) errors.add('amountMismatch');
  return ReceiptDraftValidation(
      allocationTotalBaisa: total, errors: List.unmodifiable(errors.toSet()));
}

int suggestedAllocationAmount({
  required int balanceBaisa,
  required int alreadyAllocatedBaisa,
  int? declaredBaisa,
}) {
  if (balanceBaisa <= 0 || alreadyAllocatedBaisa < 0) {
    throw ArgumentError('Balances and allocations must be valid.');
  }
  final remaining = (declaredBaisa ?? 0) - alreadyAllocatedBaisa;
  if (remaining > 0 && remaining <= balanceBaisa) return remaining;
  return balanceBaisa;
}

PaymentScope derivePaymentScope({
  required String payerMembershipId,
  required Iterable<ReceiptAllocation> allocations,
}) {
  final hasSelf = allocations
      .any((item) => item.beneficiaryMembershipId == payerMembershipId);
  final hasOthers = allocations
      .any((item) => item.beneficiaryMembershipId != payerMembershipId);
  if (hasSelf && hasOthers) return PaymentScope.mixed;
  if (hasOthers) return PaymentScope.others;
  return PaymentScope.self;
}

Set<String> uniqueBeneficiaryMemberships(
        Iterable<ReceiptAllocation> allocations) =>
    allocations.map((item) => item.beneficiaryMembershipId).toSet();

Set<String> notificationRecipientUserIds({
  required String payerUserId,
  required Iterable<ReceiptAllocation> allocations,
}) =>
    {payerUserId, ...allocations.map((item) => item.beneficiaryUserId)};

int effectiveSubscriptionAmount({
  required SubscriptionPlan plan,
  required MemberAccount account,
}) {
  if (account.feeOverrideType == FeeOverrideType.exempt) {
    return 0;
  }
  if (account.feeOverrideType == FeeOverrideType.custom) {
    return account.customAmountBaisa ?? 0;
  }
  return plan.amountBaisa;
}

String subscriptionIdempotencyKey({
  required String organizationId,
  required String membershipId,
  required String planId,
  required String periodKey,
}) =>
    'subscription_${organizationId}_${membershipId}_${planId}_$periodKey';

ChargeStatus statusAfterApprovedAllocation({
  required int balanceBeforeBaisa,
  required int allocationBaisa,
}) {
  if (allocationBaisa <= 0 || allocationBaisa > balanceBeforeBaisa) {
    throw ArgumentError(
        'Allocation must be positive and cannot exceed the charge balance.');
  }
  return allocationBaisa == balanceBeforeBaisa
      ? ChargeStatus.paid
      : ChargeStatus.partial;
}

bool canApproveReceipt({
  required String reviewStatus,
  required int amountDeclaredBaisa,
  required int allocationTotalBaisa,
  required int differenceBaisa,
}) =>
    reviewStatus == 'pending' &&
    amountDeclaredBaisa > 0 &&
    amountDeclaredBaisa == allocationTotalBaisa &&
    differenceBaisa == 0;

FinancialDashboardState deriveDashboardState({
  required bool loading,
  required bool hasError,
  required bool isFree,
  required MemberAccount? account,
  required List<FinancialCharge> charges,
  required int pendingReceiptBaisa,
}) {
  if (loading) return FinancialDashboardState.loading;
  if (hasError) return FinancialDashboardState.error;
  if (isFree) return FinancialDashboardState.free;
  if (account?.isExempt == true ||
      charges.any((item) => item.status == ChargeStatus.waived)) {
    return FinancialDashboardState.exempt;
  }
  if (charges.isEmpty) {
    return FinancialDashboardState.empty;
  }
  if (charges.any((item) => item.status == ChargeStatus.overdue)) {
    return FinancialDashboardState.overdue;
  }
  if (pendingReceiptBaisa > 0 ||
      charges.any((item) => item.status == ChargeStatus.pendingReview)) {
    return FinancialDashboardState.pendingReview;
  }
  if (charges.any((item) => item.status == ChargeStatus.partial)) {
    return FinancialDashboardState.partial;
  }
  if (charges.every(
      (item) => item.status == ChargeStatus.paid || item.balanceBaisa == 0)) {
    return FinancialDashboardState.paid;
  }
  if (charges.any((item) => item.balanceBaisa > 0)) {
    return FinancialDashboardState.due;
  }
  return FinancialDashboardState.regular;
}
