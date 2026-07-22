import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/data/models/financial_models.dart';
import 'package:village_council_app/data/models/transaction_model.dart';
import 'package:village_council_app/domain/financial/financial_logic.dart';

void main() {
  ReceiptAllocation allocation({
    String user = 'u1',
    String membership = 'm1',
    String charge = 'c1',
    int amount = 1000,
    int balance = 1000,
  }) =>
      ReceiptAllocation(
        beneficiaryUserId: user,
        beneficiaryMembershipId: membership,
        beneficiaryName: 'عضو',
        chargeId: charge,
        chargeTitle: 'اشتراك',
        amountAllocatedBaisa: amount,
        balanceBeforeBaisa: balance,
      );

  FinancialCharge charge({
    String organization = 'org1',
    String membership = 'm1',
    String id = 'c1',
    int due = 1000,
    int paid = 0,
    int balance = 1000,
    ChargeStatus status = ChargeStatus.unpaid,
    ChargeType type = ChargeType.subscription,
  }) =>
      FinancialCharge(
        id: id,
        organizationId: organization,
        membershipId: membership,
        userId: membership,
        chargeType: type,
        titleArabic: 'رسم',
        amountDueBaisa: due,
        amountPaidBaisa: paid,
        balanceBaisa: balance,
        status: status,
      );

  group('OMR money', () {
    test('uses integer baisa and three decimal formatting', () {
      expect(parseOmaniRialsToBaisa('12.500'), 12500);
      expect(parseOmaniRialsToBaisa('1.2'), 1200);
      expect(parseOmaniRialsToBaisa('1.2345'), isNull);
      expect(parseOmaniRialsToBaisa('٥'), 5000);
      expect(parseOmaniRialsToBaisa('١٢٫٥٠٠'), 12500);
      expect(parseOmaniRialsToBaisa('١٫٢٣٤٥'), isNull);
      expect(formatBaisa(12500), '12.500 ر.ع.');
      expect(baisaFrom(null, legacyRialValue: 12.5), 12500);
    });
  });

  group('plans, overrides and fee modes', () {
    const monthly = SubscriptionPlan(
      id: 'monthly',
      organizationId: 'org1',
      nameArabic: 'شهري',
      descriptionArabic: '',
      billingCycle: BillingCycle.monthly,
      amountBaisa: 5000,
      active: true,
    );
    test('free council has no synthetic fee mode', () {
      const settings = FinancialSettings(organizationId: 'org1');
      expect(settings.isFree, isTrue);
      expect(settings.supportsSubscriptions, isFalse);
    });
    test('monthly and annual periods have stable idempotency keys', () {
      final month = subscriptionIdempotencyKey(
          organizationId: 'org1',
          membershipId: 'm1',
          planId: 'monthly',
          periodKey: '2026-07');
      final year = subscriptionIdempotencyKey(
          organizationId: 'org1',
          membershipId: 'm1',
          planId: 'annual',
          periodKey: '2026');
      expect(month, isNot(year));
      expect(
          month,
          subscriptionIdempotencyKey(
              organizationId: 'org1',
              membershipId: 'm1',
              planId: 'monthly',
              periodKey: '2026-07'));
    });
    test('custom amount and exemption override the plan', () {
      const custom = MemberAccount(
          organizationId: 'org1',
          membershipId: 'm1',
          userId: 'u1',
          feeOverrideType: FeeOverrideType.custom,
          customAmountBaisa: 2750);
      const exempt = MemberAccount(
          organizationId: 'org1',
          membershipId: 'm2',
          userId: 'u2',
          feeOverrideType: FeeOverrideType.exempt,
          exemptionReason: 'قرار موثق');
      expect(effectiveSubscriptionAmount(plan: monthly, account: custom), 2750);
      expect(effectiveSubscriptionAmount(plan: monthly, account: exempt), 0);
    });
    test('booking and event charge types remain distinct', () {
      expect(charge(type: ChargeType.booking).chargeType, ChargeType.booking);
      expect(charge(type: ChargeType.event).chargeType, ChargeType.event);
    });
  });

  group('multi-tenant isolation and Arabic search', () {
    test('same membership in two councils remains a different account key', () {
      const first = (organizationId: 'org1', membershipId: 'm1');
      const second = (organizationId: 'org2', membershipId: 'm1');
      expect(first, isNot(second));
    });
    test('normalization ignores hamza, diacritics and tatweel', () {
      expect(normalizeArabicSearch('إِبْــرَاهِيم'),
          normalizeArabicSearch('ابراهيم'));
      expect(normalizeArabicSearch('أحمد علي'), 'احمد علي');
    });
    test('same names are distinguished by membership number and id', () {
      const first = MemberDirectoryEntry(
          membershipId: 'm1',
          userId: 'u1',
          fullName: 'محمد علي',
          memberNumber: '101');
      const second = MemberDirectoryEntry(
          membershipId: 'm2',
          userId: 'u2',
          fullName: 'محمد علي',
          memberNumber: '202');
      expect(first.fullName, second.fullName);
      expect(first.memberNumber, isNot(second.memberNumber));
      expect({first.membershipId, second.membershipId}.length, 2);
    });
  });

  group('collective receipt allocations', () {
    test('self, others and mixed scopes are derived correctly', () {
      expect(
          derivePaymentScope(
              payerMembershipId: 'm1', allocations: [allocation()]),
          PaymentScope.self);
      expect(
          derivePaymentScope(
              payerMembershipId: 'm1',
              allocations: [allocation(membership: 'm2')]),
          PaymentScope.others);
      expect(
          derivePaymentScope(payerMembershipId: 'm1', allocations: [
            allocation(),
            allocation(membership: 'm2', charge: 'c2')
          ]),
          PaymentScope.mixed);
    });
    test('one receipt can cover several members and charges', () {
      final items = [
        allocation(),
        allocation(
            user: 'u2',
            membership: 'm2',
            charge: 'c2',
            amount: 2500,
            balance: 3000)
      ];
      final result =
          validateReceiptDraft(declaredBaisa: 3500, allocations: items);
      expect(result.isValid, isTrue);
      expect(uniqueBeneficiaryMemberships(items), {'m1', 'm2'});
      expect(
          notificationRecipientUserIds(
              payerUserId: 'payer', allocations: items),
          {'payer', 'u1', 'u2'});
    });
    test('duplicate charge is rejected', () {
      final result = validateReceiptDraft(
          declaredBaisa: 2000, allocations: [allocation(), allocation()]);
      expect(result.errors, contains('duplicateCharge'));
    });
    test('partial payment is allowed but overpayment is rejected', () {
      expect(
          validateReceiptDraft(
              declaredBaisa: 500,
              allocations: [allocation(amount: 500)]).isValid,
          isTrue);
      expect(
          validateReceiptDraft(
              declaredBaisa: 1500,
              allocations: [allocation(amount: 1500)]).errors,
          contains('overpayment'));
      expect(
          statusAfterApprovedAllocation(
              balanceBeforeBaisa: 1000, allocationBaisa: 500),
          ChargeStatus.partial);
      expect(
          statusAfterApprovedAllocation(
              balanceBeforeBaisa: 1000, allocationBaisa: 1000),
          ChargeStatus.paid);
    });
    test('entered amount becomes a partial allocation for one charge', () {
      expect(
        suggestedAllocationAmount(
          balanceBaisa: 12500,
          alreadyAllocatedBaisa: 0,
          declaredBaisa: 5000,
        ),
        5000,
      );
      expect(
        suggestedAllocationAmount(
          balanceBaisa: 12500,
          alreadyAllocatedBaisa: 0,
        ),
        12500,
      );
    });
    test('amount mismatch blocks submission', () {
      final result =
          validateReceiptDraft(declaredBaisa: 900, allocations: [allocation()]);
      expect(result.isValid, isFalse);
      expect(result.errors, contains('amountMismatch'));
      expect(result.differenceFrom(900), -100);
    });
    test('approval can happen only once while pending and matching', () {
      expect(
          canApproveReceipt(
              reviewStatus: 'pending',
              amountDeclaredBaisa: 1000,
              allocationTotalBaisa: 1000,
              differenceBaisa: 0),
          isTrue);
      expect(
          canApproveReceipt(
              reviewStatus: 'approved',
              amountDeclaredBaisa: 1000,
              allocationTotalBaisa: 1000,
              differenceBaisa: 0),
          isFalse);
    });
  });

  group('dashboard states', () {
    test('covers loading, error, empty and free', () {
      expect(
          deriveDashboardState(
              loading: true,
              hasError: false,
              isFree: false,
              account: null,
              charges: const [],
              pendingReceiptBaisa: 0),
          FinancialDashboardState.loading);
      expect(
          deriveDashboardState(
              loading: false,
              hasError: true,
              isFree: false,
              account: null,
              charges: const [],
              pendingReceiptBaisa: 0),
          FinancialDashboardState.error);
      expect(
          deriveDashboardState(
              loading: false,
              hasError: false,
              isFree: true,
              account: null,
              charges: const [],
              pendingReceiptBaisa: 0),
          FinancialDashboardState.free);
      expect(
          deriveDashboardState(
              loading: false,
              hasError: false,
              isFree: false,
              account: null,
              charges: const [],
              pendingReceiptBaisa: 0),
          FinancialDashboardState.empty);
    });
    test('covers due, partial, pending, paid, overdue and exempt', () {
      FinancialDashboardState state(FinancialCharge item,
              {MemberAccount? account, int pending = 0}) =>
          deriveDashboardState(
              loading: false,
              hasError: false,
              isFree: false,
              account: account,
              charges: [item],
              pendingReceiptBaisa: pending);
      expect(state(charge()), FinancialDashboardState.due);
      expect(
          state(charge(paid: 500, balance: 500, status: ChargeStatus.partial)),
          FinancialDashboardState.partial);
      expect(state(charge(status: ChargeStatus.pendingReview), pending: 1000),
          FinancialDashboardState.pendingReview);
      expect(state(charge(paid: 1000, balance: 0, status: ChargeStatus.paid)),
          FinancialDashboardState.paid);
      expect(state(charge(status: ChargeStatus.overdue)),
          FinancialDashboardState.overdue);
      const exempt = MemberAccount(
          organizationId: 'org1',
          membershipId: 'm1',
          userId: 'u1',
          feeOverrideType: FeeOverrideType.exempt);
      expect(state(charge(), account: exempt), FinancialDashboardState.exempt);
    });
  });
}
