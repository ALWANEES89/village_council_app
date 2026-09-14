import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/financial_models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';

class ImportantAlertsScreen extends ConsumerWidget {
  const ImportantAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).valueOrNull;
    if (organizationId == null || access == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.importantAlerts)),
        body: Center(child: Text(strings.couldNotLoad)),
      );
    }
    final canReviewBookings = access.isPlatformOwner ||
        access.isOrgOwner ||
        access.isChairman ||
        access.has('bookings.manage') ||
        access.has('bookings.approve');
    final bookingState = canReviewBookings
        ? ref.watch(organizationBookingsProvider(organizationId))
        : null;
    final receiptState = access.canReviewReceipts
        ? ref.watch(pendingFinancialReceiptsProvider(organizationId))
        : null;
    final chargeState = access.canViewFinancialReports
        ? ref.watch(organizationChargesProvider(organizationId))
        : null;
    final states = [bookingState, receiptState, chargeState]
        .whereType<AsyncValue<Object?>>();
    final isLoading = states.any((state) => state.isLoading);
    final hasError = states.any((state) => state.hasError);
    final bookings = bookingState?.valueOrNull;
    final receipts = receiptState?.valueOrNull;
    final charges = chargeState?.valueOrNull;
    final rows = <Widget>[];
    final pendingBookings =
        bookings?.where((item) => item.status == 'pending').length ?? 0;
    if (pendingBookings > 0) {
      rows.add(_AlertTile(
        icon: Icons.event_busy_outlined,
        title: strings.pendingBookingsAlert,
        count: pendingBookings,
        onTap: () => context.pushNamed('bookingRequestsReview'),
      ));
    }
    final pendingReceipts =
        receipts?.where((item) => item.reviewStatus == 'pending').length ?? 0;
    if (pendingReceipts > 0) {
      rows.add(_AlertTile(
        icon: Icons.receipt_long_outlined,
        title: strings.pendingReceiptsAlert,
        count: pendingReceipts,
        onTap: () => context.pushNamed('financialReview'),
      ));
    }
    final overdue = charges
            ?.where((item) =>
                item.chargeType == ChargeType.subscription &&
                item.status == ChargeStatus.overdue &&
                item.balanceBaisa > 0)
            .length ??
        0;
    if (overdue > 0) {
      rows.add(_AlertTile(
        icon: Icons.warning_amber_rounded,
        title: strings.overdueSubscriptionsAlert,
        count: overdue,
        onTap: () => context.pushNamed('financialManagement'),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: Text(strings.importantAlerts)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : hasError
              ? Center(child: Text(strings.couldNotLoad))
              : rows.isEmpty
                  ? Center(child: Text(strings.noImportantAlerts))
                  : ListView(padding: const EdgeInsets.all(16), children: rows),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon),
          title: Text(title),
          trailing: Badge(label: Text('$count')),
        ),
      );
}
