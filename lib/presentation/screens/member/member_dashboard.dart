import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/financial_models.dart';
import '../../../data/models/transaction_model.dart';
import '../../../domain/financial/financial_logic.dart';
import '../../../providers/app_providers.dart';

class MemberDashboard extends ConsumerStatefulWidget {
  const MemberDashboard({super.key});

  @override
  ConsumerState<MemberDashboard> createState() => _MemberDashboardState();
}

class _MemberDashboardState extends ConsumerState<MemberDashboard> {
  ChargeStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organization = organizationContext.currentOrganization;
    final membership = organizationContext.currentMembership;
    final user = ref.watch(authStateProvider).value;
    if (organization == null || membership == null || user == null) {
      return const Scaffold(
          body: Center(child: Text('افتح مجلسًا لعرض ملخص الحساب.')));
    }
    final organizationId = organization['organizationId'] as String? ?? '';
    final key = (organizationId: organizationId, membershipId: membership.id);
    final settings = ref.watch(financialSettingsProvider(organizationId));
    final account = ref.watch(memberAccountProvider(key));
    final charges = ref.watch(memberChargesProvider(key));
    final transactions = ref.watch(payerFinancialTransactionsProvider(key));
    final profile = ref.watch(userProfileProvider(user.uid)).value;
    final legacyMember = ref.watch(currentMemberProvider).value;
    final memberName =
        profile?.fullName ?? legacyMember?.fullName ?? 'عضو المجلس';
    final organizationName = organization['officialNameArabic'] as String? ??
        organization['nameArabic'] as String? ??
        organization['name'] as String? ??
        'المجلس الحالي';

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('ملخص الحساب'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'سجل المعاملات',
              onPressed: () => context.pushNamed('receiptHistory'),
              icon: const Icon(Icons.receipt_long_outlined),
            ),
          ],
        ),
        body: settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _ErrorState(
              onRetry: () =>
                  ref.invalidate(financialSettingsProvider(organizationId))),
          data: (financialSettings) {
            if (financialSettings.isFree) {
              return _FreeCouncilState(
                organizationName: organizationName,
                memberName: memberName,
                memberNumber: membership.memberNumber,
              );
            }
            return charges.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ErrorState(
                  onRetry: () => ref.invalidate(memberChargesProvider(key))),
              data: (items) => _buildFinancialContent(
                organizationName: organizationName,
                memberName: memberName,
                memberNumber: membership.memberNumber,
                organizationId: organizationId,
                membershipId: membership.id,
                account: account.value,
                charges: items,
                transactions: transactions.value ?? const [],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFinancialContent({
    required String organizationName,
    required String memberName,
    required String memberNumber,
    required String organizationId,
    required String membershipId,
    required MemberAccount? account,
    required List<FinancialCharge> charges,
    required List<TransactionModel> transactions,
  }) {
    final totalDue =
        charges.fold<int>(0, (sum, item) => sum + item.amountDueBaisa);
    final totalPaid =
        charges.fold<int>(0, (sum, item) => sum + item.amountPaidBaisa);
    final totalBalance =
        charges.fold<int>(0, (sum, item) => sum + item.balanceBaisa);
    final pending = transactions
        .where((item) => item.reviewStatus == 'pending')
        .fold<int>(0, (sum, item) => sum + item.amountDeclaredBaisa);
    final payable = charges.where((item) => item.isPayable).toList();
    final nextDue = payable
        .map((item) => item.dueDate)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (current, item) =>
              current == null || item.isBefore(current) ? item : current,
        );
    final progress =
        totalDue == 0 ? 0.0 : (totalPaid / totalDue).clamp(0.0, 1.0);
    final accountState = _accountStateLabel(deriveDashboardState(
      loading: false,
      hasError: false,
      isFree: false,
      account: account,
      charges: charges,
      pendingReceiptBaisa: pending,
    ));
    final filtered = _filter == null
        ? charges
        : charges.where((item) => item.status == _filter).toList();
    final paidForOthers =
        transactions.where((item) => item.paysForOthers).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(memberChargesProvider(
            (organizationId: organizationId, membershipId: membershipId)));
        ref.invalidate(payerFinancialTransactionsProvider(
            (organizationId: organizationId, membershipId: membershipId)));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AccountHeader(
            organizationName: organizationName,
            memberName: memberName,
            memberNumber: memberNumber,
            planName: account?.planNameArabic ??
                (account?.planId == null ? 'لم تُعيّن باقة' : account!.planId!),
            subscriptionStatus: account?.subscriptionStatus ?? 'غير مفعّل',
            accountState: accountState,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryCard(
                  label: 'إجمالي الرسوم',
                  value: formatBaisa(totalDue),
                  icon: Icons.request_quote_outlined),
              _SummaryCard(
                  label: 'إجمالي المدفوع',
                  value: formatBaisa(totalPaid),
                  icon: Icons.check_circle_outline,
                  color: Colors.green),
              _SummaryCard(
                  label: 'المتبقي',
                  value: formatBaisa(totalBalance),
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.red),
              _SummaryCard(
                  label: 'قيد المراجعة',
                  value: formatBaisa(pending),
                  icon: Icons.hourglass_top,
                  color: Colors.orange),
              _SummaryCard(
                label: 'الاستحقاق القادم',
                value: nextDue == null
                    ? 'لا يوجد'
                    : DateFormat('yyyy/MM/dd').format(nextDue),
                icon: Icons.event_outlined,
                color: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('نسبة السداد',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${(progress * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                        value: progress, minHeight: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: payable.isEmpty
                      ? null
                      : () => context.pushNamed(
                            'uploadReceipt',
                            extra: ReceiptUploadArguments(
                              organizationId: organizationId,
                              membershipId: membershipId,
                            ),
                          ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('رفع إيصال'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.pushNamed('receiptHistory'),
                  icon: const Icon(Icons.history),
                  label: const Text('سجل المعاملات'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('الرسوم',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                    label: 'الكل',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null)),
                for (final status in ChargeStatus.values)
                  _FilterChip(
                    label: _chargeStatusLabel(status),
                    selected: _filter == status,
                    onTap: () => setState(() => _filter = status),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const _EmptyCard(text: 'لا توجد رسوم ضمن هذا التصنيف.')
          else
            for (final charge in filtered)
              _ChargeCard(
                charge: charge,
                onOpen: () {
                  if (charge.isPayable) {
                    context.pushNamed(
                      'uploadReceipt',
                      extra: ReceiptUploadArguments(
                        paymentId: charge.id,
                        periodLabel: charge.titleArabic,
                        organizationId: organizationId,
                        membershipId: membershipId,
                      ),
                    );
                  } else if (charge.lastTransactionId != null) {
                    context.pushNamed(
                      'transactionTimeline',
                      pathParameters: {'id': charge.lastTransactionId!},
                      queryParameters: {'organizationId': organizationId},
                    );
                  }
                },
              ),
          const SizedBox(height: 20),
          const Text('مدفوعات قمت بها عن أعضاء آخرين',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (paidForOthers.isEmpty)
            const _EmptyCard(text: 'لا توجد مدفوعات عن أعضاء آخرين حتى الآن.')
          else
            for (final transaction in paidForOthers)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group_outlined,
                      color: AppColors.primary),
                  title: Text(formatBaisa(transaction.amountDeclaredBaisa)),
                  subtitle: Text(
                    transaction.allocations
                        .where((item) =>
                            item.beneficiaryMembershipId != membershipId)
                        .map((item) => item.beneficiaryName)
                        .toSet()
                        .join('، '),
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.pushNamed(
                    'transactionTimeline',
                    pathParameters: {'id': transaction.id},
                    queryParameters: {'organizationId': organizationId},
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

String _accountStateLabel(FinancialDashboardState state) => switch (state) {
      FinancialDashboardState.exempt => 'معفى',
      FinancialDashboardState.overdue => 'متأخر',
      FinancialDashboardState.pendingReview => 'قيد المراجعة',
      FinancialDashboardState.due || FinancialDashboardState.partial => 'مستحق',
      FinancialDashboardState.free => 'مجلس مجاني',
      _ => 'منتظم',
    };

String _chargeStatusLabel(ChargeStatus status) => switch (status) {
      ChargeStatus.unpaid => 'غير مدفوع',
      ChargeStatus.partial => 'جزئي',
      ChargeStatus.pendingReview => 'قيد المراجعة',
      ChargeStatus.paid => 'مدفوع',
      ChargeStatus.waived => 'معفى',
      ChargeStatus.overdue => 'متأخر',
      ChargeStatus.rejected => 'مرفوض',
      ChargeStatus.cancelled => 'ملغى',
      ChargeStatus.refundRequired => 'يتطلب استردادًا',
    };

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.organizationName,
    required this.memberName,
    required this.memberNumber,
    required this.planName,
    required this.subscriptionStatus,
    required this.accountState,
  });
  final String organizationName;
  final String memberName;
  final String memberNumber;
  final String planName;
  final String subscriptionStatus;
  final String accountState;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(organizationName,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(memberName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            Text('رقم العضوية: $memberNumber',
                style: const TextStyle(color: Colors.white70)),
            const Divider(color: Colors.white24, height: 26),
            Row(
              children: [
                Expanded(
                    child: Text(
                        'الباقة: $planName\nالحالة: $subscriptionStatus',
                        style: const TextStyle(color: Colors.white))),
                Chip(
                    label: Text(accountState),
                    avatar: const Icon(Icons.verified_user_outlined, size: 18)),
              ],
            ),
          ],
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.color = AppColors.primary});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 42) / 2,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.grey)),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _ChargeCard extends StatelessWidget {
  const _ChargeCard({required this.charge, required this.onOpen});
  final FinancialCharge charge;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(charge.titleArabic,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                Chip(label: Text(_chargeStatusLabel(charge.status))),
              ]),
              Text(
                  '${charge.chargeType.name} • ${charge.periodKey ?? 'بدون فترة'}'),
              const SizedBox(height: 8),
              Text(
                  'المبلغ: ${formatBaisa(charge.amountDueBaisa)}  •  المدفوع: ${formatBaisa(charge.amountPaidBaisa)}'),
              Text(
                  'المتبقي: ${formatBaisa(charge.balanceBaisa)}  •  الاستحقاق: ${charge.dueDate == null ? '-' : DateFormat('yyyy/MM/dd').format(charge.dueDate!)}'),
              if (charge.lastPayerName?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('تم الدفع عنك بواسطة: ${charge.lastPayerName}',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                ),
              if (charge.isPayable)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('اضغط لاختيار الرسم ورفع إيصال',
                      style: TextStyle(color: AppColors.primary)),
                ),
            ]),
          ),
        ),
      );
}

class _FreeCouncilState extends StatelessWidget {
  const _FreeCouncilState(
      {required this.organizationName,
      required this.memberName,
      required this.memberNumber});
  final String organizationName;
  final String memberName;
  final String memberNumber;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.volunteer_activism_outlined,
                size: 84, color: Colors.green),
            const SizedBox(height: 16),
            Text(organizationName,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('$memberName • $memberNumber'),
            const SizedBox(height: 18),
            const Text('هذا المجلس مجاني ولا يفرض رسومًا على أعضائه.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('لن يتم إنشاء أي رسوم وهمية في حسابك.',
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(24), child: Center(child: Text(text))));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 52, color: Colors.red),
          const SizedBox(height: 10),
          const Text('تعذر تحميل الحساب المالي.'),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ]),
      );
}
