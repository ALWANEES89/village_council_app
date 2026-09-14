import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/council_management_models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/omr_amount.dart';

enum _ReportPeriod { thisMonth, previousMonth, thisYear, custom }

class FinancialReportScreen extends ConsumerStatefulWidget {
  const FinancialReportScreen({super.key});

  @override
  ConsumerState<FinancialReportScreen> createState() =>
      _FinancialReportScreenState();
}

class _FinancialReportScreenState extends ConsumerState<FinancialReportScreen> {
  _ReportPeriod _period = _ReportPeriod.thisMonth;
  DateTimeRange? _customRange;
  Future<CouncilFinancialReport>? _report;
  String? _loadedOrganizationId;

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    return switch (_period) {
      _ReportPeriod.thisMonth => (
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1, 0)
        ),
      _ReportPeriod.previousMonth => (
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month, 0)
        ),
      _ReportPeriod.thisYear => (
          DateTime(now.year),
          DateTime(now.year, 12, 31)
        ),
      _ReportPeriod.custom => (
          _customRange?.start ?? DateTime(now.year, now.month),
          _customRange?.end ?? DateTime(now.year, now.month + 1, 0)
        ),
    };
  }

  void _load(String organizationId) {
    final range = _range();
    setState(() {
      _loadedOrganizationId = organizationId;
      _report =
          ref.read(councilManagementRepositoryProvider).getFinancialReport(
                organizationId: organizationId,
                startDate: range.$1,
                endDate: range.$2,
              );
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).valueOrNull;
    if (organizationId == null || access?.canViewFinancialReports != true) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.financialReports)),
        body: Center(child: Text(strings.accessDenied)),
      );
    }
    if (_loadedOrganizationId != organizationId) {
      _loadedOrganizationId = organizationId;
      _report =
          ref.read(councilManagementRepositoryProvider).getFinancialReport(
                organizationId: organizationId,
                startDate: _range().$1,
                endDate: _range().$2,
              );
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.financialReports)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_ReportPeriod>(
              segments: [
                ButtonSegment(
                    value: _ReportPeriod.thisMonth,
                    label: Text(strings.thisMonth)),
                ButtonSegment(
                    value: _ReportPeriod.previousMonth,
                    label: Text(strings.previousMonth)),
                ButtonSegment(
                    value: _ReportPeriod.thisYear,
                    label: Text(strings.thisYear)),
                ButtonSegment(
                    value: _ReportPeriod.custom,
                    label: Text(strings.customPeriod)),
              ],
              selected: {_period},
              onSelectionChanged: (value) async {
                final selected = value.single;
                if (selected == _ReportPeriod.custom) {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (range == null) return;
                  _customRange = range;
                }
                _period = selected;
                _load(organizationId);
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<CouncilFinancialReport>(
              future: _report,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(child: Text(strings.couldNotLoad));
                }
                return _ReportBody(report: snapshot.data!);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});
  final CouncilFinancialReport report;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final regular = report.revenueByCategory['bookingRegular'] ?? 0;
    final event = report.revenueByCategory['bookingEvent'] ?? 0;
    final packageAddOn = report.revenueByCategory['packageAddOn'] ?? 0;
    final cards = <(String, int, IconData)>[
      (
        strings.totalCollected,
        report.totalCollectedBaisa,
        Icons.savings_outlined
      ),
      (strings.totalOutstanding, report.totalOutstandingBaisa, Icons.schedule),
      (strings.bookingRevenue, regular + event, Icons.event_available_outlined),
      (strings.packageRevenue, packageAddOn, Icons.inventory_2_outlined),
      (
        strings.totalExpenses,
        report.totalExpensesBaisa,
        Icons.payments_outlined
      ),
      (
        strings.netPosition,
        report.netBalanceBaisa,
        Icons.account_balance_outlined
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 125,
          ),
          itemBuilder: (_, index) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(cards[index].$3),
                  const Spacer(),
                  OmrAmount(amountBaisa: cards[index].$2),
                  Text(cards[index].$1,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
                title: Text(strings.membersPaid),
                trailing: Text('${report.membersPaidCount}')),
            ListTile(
                title: Text(strings.membersUnpaid),
                trailing: Text('${report.membersUnpaidCount}')),
            ListTile(
              title: Text(strings.membershipRevenue),
              trailing: OmrAmount(
                  amountBaisa: report.revenueByCategory['subscription'] ?? 0),
            ),
            ListTile(
              title: Text(strings.bookingRevenue),
              trailing: OmrAmount(amountBaisa: regular + event),
            ),
          ]),
        ),
        if (report.expenseByCategory.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(strings.expenseBreakdown,
              style: Theme.of(context).textTheme.titleMedium),
          for (final entry in report.expenseByCategory.entries)
            ListTile(
              title: Text(_expenseCategoryLabel(strings, entry.key)),
              trailing: OmrAmount(amountBaisa: entry.value),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          DateFormat.yMd(Localizations.localeOf(context).toString())
              .format(DateTime.now()),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _expenseCategoryLabel(AppLocalizations strings, String category) {
    return switch (category) {
      'bills' => strings.expenseBills,
      'electricity' => strings.expenseElectricity,
      'water' => strings.expenseWater,
      'communications' => strings.expenseCommunications,
      'supplies' => strings.expenseSupplies,
      'maintenance' => strings.expenseMaintenance,
      'cleaning' => strings.expenseCleaning,
      'equipment' => strings.expenseEquipment,
      'hospitality' => strings.expenseHospitality,
      _ => strings.expenseOther,
    };
  }
}
