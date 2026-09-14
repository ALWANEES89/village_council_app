import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/admin_access.dart';
import '../../../core/notifications/notification_deeplink.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/financial_models.dart';
import '../../../data/models/membership_model.dart';
import '../../../domain/dashboard/council_dashboard_metrics.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_bell.dart';
import '../member/council_booking_screen.dart';

class CouncilDashboardScreen extends ConsumerStatefulWidget {
  const CouncilDashboardScreen({super.key});

  @override
  ConsumerState<CouncilDashboardScreen> createState() =>
      _CouncilDashboardScreenState();
}

class _CouncilDashboardScreenState
    extends ConsumerState<CouncilDashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _dailyKey = GlobalKey();
  final _financeKey = GlobalKey();
  final _managementKey = GlobalKey();
  bool _switchingCouncil = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final councilContext = ref.watch(organizationContextProvider);
    final organization = councilContext.currentOrganization;
    if (!councilContext.hasOrganization || organization == null) {
      return _NoCouncilView(strings: strings);
    }

    final organizationId = organization['organizationId'] as String;
    final selectedMembership = councilContext.currentMembership;
    final membership = selectedMembership == null
        ? null
        : ref
                .watch(membershipDocumentProvider((
                  organizationId: organizationId,
                  membershipId: selectedMembership.id,
                )))
                .asData
                ?.value ??
            selectedMembership;
    final adminAccess = ref.watch(adminAccessProvider).asData?.value;
    final access = adminAccess ?? const AdminAccess();
    final canManageFinancialSettings =
        adminAccess?.canManageFinancialSettings == true;
    final capabilities = _CouncilCapabilities(
      access: access,
      membership: membership,
      isPlatformAdmin: councilContext.isPlatformAdmin,
      canManageFinancialSettings: canManageFinancialSettings,
    );
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final profile = authUser == null
        ? null
        : ref.watch(userProfileProvider(authUser.uid)).asData?.value;
    final legacyMember = ref.watch(currentMemberProvider).asData?.value;
    final memberName = profile?.fullName ??
        legacyMember?.fullName ??
        authUser?.displayName ??
        strings.member;
    final languageCode = Localizations.localeOf(context).languageCode;
    final organizationName = _organizationName(organization, languageCode);
    final activeMemberships = authUser == null
        ? null
        : ref.watch(activeUserMembershipsProvider(authUser.uid)).valueOrNull;
    final availableOrganizations =
        ref.watch(organizationsProvider).valueOrNull ?? const [];
    final canSwitchCouncil = access.isPlatformOwner
        ? availableOrganizations.length > 1
        : (activeMemberships?.memberships.length ?? 0) > 1;

    final dashboardMetrics =
        ref.watch(councilDashboardMetricsProvider(organizationId));
    final bookings = capabilities.canReviewBookings
        ? ref.watch(organizationBookingsProvider(organizationId))
        : const AsyncValue<List<BookingModel>>.data([]);
    final AsyncValue<List<dynamic>>? receipts = capabilities.canReviewReceipts
        ? ref.watch(pendingFinancialReceiptsProvider(organizationId))
        : membership == null
            ? null
            : ref.watch(payerFinancialTransactionsProvider((
                organizationId: organizationId,
                membershipId: membership.id,
              )));
    final charges = capabilities.canManageFinance
        ? ref.watch(organizationChargesProvider(organizationId))
        : membership == null
            ? null
            : ref.watch(memberChargesProvider((
                organizationId: organizationId,
                membershipId: membership.id,
              )));
    final notifications = authUser == null
        ? const AsyncValue<List<AppNotificationModel>>.data([])
        : ref.watch(userNotificationsProvider(authUser.uid));

    final sections = _buildSections(
      strings: strings,
      organization: organization,
      organizationId: organizationId,
      membership: membership,
      userId: authUser?.uid,
      capabilities: capabilities,
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF6F8FB),
      drawer: _DashboardDrawer(
        organizationName: organizationName,
        logoUrl: organization['logoUrl'] as String?,
        onHome: () => _closeDrawerAndScroll(null),
        onDaily: () => _closeDrawerAndScroll(_dailyKey),
        onFinance: () => _closeDrawerAndScroll(_financeKey),
        onManagement: () => _closeDrawerAndScroll(_managementKey),
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.councilDashboard,
                style: const TextStyle(fontSize: 17)),
            Text(
              organizationName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (access.isPlatformOwner)
            IconButton(
              tooltip: strings.backToSystemAdministration,
              onPressed: () => context.goNamed('adminDashboard'),
              icon: const Icon(Icons.public),
            ),
          const NotificationBell(color: Colors.white),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(councilDashboardMetricsProvider(organizationId));
          ref.invalidate(organizationBookingsProvider(organizationId));
          ref.invalidate(pendingFinancialReceiptsProvider(organizationId));
          ref.invalidate(organizationChargesProvider(organizationId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _DashboardHeader(
              organization: organization,
              organizationName: organizationName,
              memberName: memberName,
              roleName: _roleName(
                councilContext.currentRole,
                membership?.roleId ?? 'system_owner',
                languageCode,
                strings,
              ),
              memberNumber: membership?.memberNumber,
              switching: _switchingCouncil,
              onSwitchCouncil: canSwitchCouncil
                  ? () => _showCouncilSwitcher(
                        currentOrganizationId: organizationId,
                        isPlatformOwner: access.isPlatformOwner,
                      )
                  : null,
            ),
            const SizedBox(height: 18),
            _SummaryGrid(
              members: dashboardMetrics.when(
                data: (value) => '${value['members'] ?? 0}',
                loading: () => null,
                error: (_, __) => null,
              ),
              upcomingBookings: dashboardMetrics.when(
                data: (value) => '${value['upcomingBookings'] ?? 0}',
                loading: () => null,
                error: (_, __) => null,
              ),
              metricsUnavailable: dashboardMetrics.hasError,
              pendingReceipts: receipts?.when(
                    data: (items) =>
                        '${items.where((item) => item.reviewStatus == 'pending').length}',
                    loading: () => null,
                    error: (_, __) => '—',
                  ) ??
                  '—',
              outstandingSubscriptions: charges?.when(
                    data: (items) => '${countOutstandingSubscriptions(items)}',
                    loading: () => null,
                    error: (_, __) => '—',
                  ) ??
                  '—',
              onMembersTap: capabilities.canManageMembers
                  ? () => context.pushNamed('memberManagement')
                  : null,
              onBookingsTap: capabilities.canReviewBookings
                  ? () => context.pushNamed('councilBookings')
                  : null,
              onReceiptsTap: capabilities.canReviewReceipts
                  ? () => context.pushNamed('financialReview')
                  : null,
              onSubscriptionsTap: capabilities.canViewReports
                  ? () => context.pushNamed('financialManagement')
                  : null,
            ),
            const SizedBox(height: 20),
            KeyedSubtree(
              key: _dailyKey,
              child: _FeatureSection(
                title: strings.dailyOperations,
                subtitle: strings.dailyOperationsDescription,
                icon: Icons.today_outlined,
                color: const Color(0xFF0A8F63),
                actions: sections.daily,
              ),
            ),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: _financeKey,
              child: _FeatureSection(
                title: strings.finance,
                subtitle: strings.financeDescription,
                icon: Icons.savings_outlined,
                color: const Color(0xFF1769E0),
                actions: sections.finance,
              ),
            ),
            const SizedBox(height: 14),
            KeyedSubtree(
              key: _managementKey,
              child: _FeatureSection(
                title: strings.councilManagement,
                subtitle: strings.councilManagementDescription,
                icon: Icons.manage_accounts_outlined,
                color: const Color(0xFF7243D6),
                actions: sections.management,
              ),
            ),
            if (sections.quick.isNotEmpty) ...[
              const SizedBox(height: 20),
              _QuickActions(actions: sections.quick),
            ],
            const SizedBox(height: 20),
            _ImportantAlerts(
              bookings: bookings,
              receipts: capabilities.canReviewReceipts ? receipts : null,
              charges: capabilities.canManageFinance ? charges : null,
              canReviewBookings: capabilities.canReviewBookings,
              canReviewReceipts: capabilities.canReviewReceipts,
              canManageFinance: capabilities.canManageFinance,
            ),
            const SizedBox(height: 14),
            _RecentActivity(
              notifications: notifications,
              organizationId: organizationId,
              userId: authUser?.uid,
            ),
          ],
        ),
      ),
    );
  }

  _DashboardSections _buildSections({
    required AppLocalizations strings,
    required Map<String, dynamic> organization,
    required String organizationId,
    required MembershipModel? membership,
    required String? userId,
    required _CouncilCapabilities capabilities,
  }) {
    void openBooking() => context.pushNamed(
          'rentalPlaceholder',
          extra: CouncilBookingArguments(
            organizationId: organizationId,
            membershipId: membership?.id,
          ),
        );

    final daily = <_DashboardAction>[
      _DashboardAction(
          Icons.event_available_outlined,
          strings.bookings,
          capabilities.canReviewBookings
              ? () => context.pushNamed('councilBookings')
              : openBooking),
      if (capabilities.canManageMembers)
        _DashboardAction(Icons.groups_outlined, strings.membersManagement,
            () => context.pushNamed('memberManagement')),
      _DashboardAction(
        Icons.card_membership_outlined,
        strings.subscriptions,
        capabilities.canManageFinance
            ? () => context.pushNamed('financialManagement')
            : () => _showMembership(context, membership),
      ),
      _DashboardAction(Icons.notifications_outlined, strings.notifications,
          () => context.pushNamed('notifications')),
    ];
    final finance = <_DashboardAction>[
      if (capabilities.canManageFinance)
        _DashboardAction(
            Icons.account_balance_wallet_outlined,
            strings.feesAndSubscriptions,
            () => context.pushNamed('financialManagement')),
      _DashboardAction(Icons.receipt_long_outlined, strings.receipts,
          () => context.pushNamed('receiptHistory')),
      if (capabilities.canReviewReceipts)
        _DashboardAction(Icons.fact_check_outlined, strings.paymentReview,
            () => context.pushNamed('financialReview')),
      if (capabilities.canViewReports)
        _DashboardAction(Icons.analytics_outlined, strings.financialReports,
            () => context.pushNamed('financialReport')),
      if (capabilities.canViewReports)
        _DashboardAction(Icons.payments_outlined, strings.expenses,
            () => context.pushNamed('expenses')),
    ];
    final management = <_DashboardAction>[
      _DashboardAction(
          Icons.account_balance_outlined,
          strings.councilInformation,
          () => _showOrganization(context, organization)),
      if (capabilities.canChangeRoles)
        _DashboardAction(Icons.admin_panel_settings_outlined,
            strings.permissions, () => context.pushNamed('rolesManagement')),
      if (capabilities.canManageSettings)
        _DashboardAction(Icons.settings_outlined, strings.councilSettings,
            () => _comingSoon(context)),
      if (capabilities.canReadAudit)
        _DashboardAction(Icons.history_edu_outlined, strings.activityLog,
            () => context.pushNamed('auditLogs')),
    ];
    final quick = <_DashboardAction>[
      _DashboardAction(
          Icons.add_circle_outline, strings.newBooking, openBooking),
      if (membership != null && userId != null)
        _DashboardAction(
          Icons.upload_file_outlined,
          strings.uploadReceipt,
          () => context.pushNamed(
            'uploadReceipt',
            extra: ReceiptUploadArguments(
              organizationId: organizationId,
              membershipId: membership.id,
              userId: userId,
              periodLabel: strings.generalPaymentReceipt,
            ),
          ),
        ),
      if (capabilities.canReviewReceipts)
        _DashboardAction(Icons.verified_outlined, strings.reviewReceipt,
            () => context.pushNamed('financialReview')),
      if (capabilities.canManageMembers)
        _DashboardAction(Icons.group_add_outlined, strings.manageMembers,
            () => context.pushNamed('memberManagement')),
      if (capabilities.canSendNotifications)
        _DashboardAction(Icons.campaign_outlined, strings.sendNotification,
            () => context.pushNamed('sendCouncilNotification')),
    ];
    return _DashboardSections(daily, finance, management, quick);
  }

  Future<void> _closeDrawerAndScroll(GlobalKey? key) async {
    _scaffoldKey.currentState?.closeDrawer();
    if (key == null) {
      PrimaryScrollController.maybeOf(context)?.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final target = key.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> _showCouncilSwitcher({
    required String currentOrganizationId,
    required bool isPlatformOwner,
  }) async {
    final strings = AppLocalizations.of(context);
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || _switchingCouncil) return;
    final organizations =
        ref.read(organizationsProvider).valueOrNull ?? const [];
    final memberships = ref
            .read(activeUserMembershipsProvider(user.uid))
            .valueOrNull
            ?.memberships ??
        const <MembershipModel>[];
    final membershipByOrganization = {
      for (final membership in memberships)
        membership.organizationId: membership,
    };
    final allowed = organizations.where((organization) {
      final id = organization['organizationId'] as String?;
      return id != null &&
          (isPlatformOwner || membershipByOrganization.containsKey(id));
    }).toList();
    if (allowed.length < 2) return;

    var query = '';
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final language = Localizations.localeOf(context).languageCode;
          final filtered = allowed
              .where((organization) => _organizationSearchText(organization)
                  .contains(query.trim().toLowerCase()))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(strings.chooseCouncil,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: strings.searchCouncils,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final organization = filtered[index];
                        final id = organization['organizationId'] as String;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFEAF3FF),
                            child: Icon(
                              id == currentOrganizationId
                                  ? Icons.check
                                  : Icons.account_balance_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          title:
                              Text(_organizationName(organization, language)),
                          selected: id == currentOrganizationId,
                          onTap: () => Navigator.pop(sheetContext, id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selectedId == null || selectedId == currentOrganizationId || !mounted) {
      return;
    }
    setState(() => _switchingCouncil = true);
    try {
      if (isPlatformOwner) {
        await ref
            .read(organizationContextProvider.notifier)
            .selectOrganizationAsSuperAdmin(selectedId);
      } else {
        final membership = membershipByOrganization[selectedId];
        if (membership == null) throw StateError('Membership is required.');
        await ref.read(organizationContextProvider.notifier).selectOrganization(
              organizationId: selectedId,
              userId: user.uid,
              membershipId: membership.id,
            );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSwitchCouncil)),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingCouncil = false);
    }
  }
}

class _NoCouncilView extends StatelessWidget {
  const _NoCouncilView({required this.strings});
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.account_balance_outlined,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: 14),
              Text(strings.noCouncilSelected),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.goNamed('memberHome'),
                child: Text(strings.returnHome),
              ),
            ]),
          ),
        ),
      );
}

class _CouncilCapabilities {
  const _CouncilCapabilities({
    required this.access,
    required this.membership,
    required this.isPlatformAdmin,
    required this.canManageFinancialSettings,
  });
  final AdminAccess access;
  final MembershipModel? membership;
  final bool isPlatformAdmin;
  final bool canManageFinancialSettings;
  Set<String> get permissions => (isPlatformAdmin
          ? const ['fullAccess']
          : membership?.permissionsSnapshot ?? const <String>[])
      .toSet();
  bool get fullAccess =>
      access.isPlatformOwner ||
      isPlatformAdmin ||
      access.isOrgOwner ||
      access.isChairman;
  bool can(String value, [String? alias]) =>
      fullAccess ||
      permissions.contains(value) ||
      (alias != null && permissions.contains(alias));
  bool get canManageMembers => access.canManageMembers;
  bool get canChangeRoles => access.canChangeRoles;
  bool get canReviewReceipts => access.canReviewReceipts;
  bool get canManageFinance => canManageFinancialSettings;
  bool get canReadAudit => access.canReadAudit;
  bool get canReviewBookings =>
      access.isPlatformOwner ||
      const {'chairman', 'adminManager'}.contains(membership?.roleId) ||
      can('bookings.manage') ||
      can('bookings.approve');
  bool get canViewReports => access.canViewFinancialReports;
  bool get canSendNotifications => access.canSendCouncilNotifications;
  bool get canManageSettings =>
      can('organization.manage') || can('settings.manage');
}

class _DashboardSections {
  const _DashboardSections(
      this.daily, this.finance, this.management, this.quick);
  final List<_DashboardAction> daily;
  final List<_DashboardAction> finance;
  final List<_DashboardAction> management;
  final List<_DashboardAction> quick;
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.organization,
    required this.organizationName,
    required this.memberName,
    required this.roleName,
    required this.memberNumber,
    required this.switching,
    required this.onSwitchCouncil,
  });
  final Map<String, dynamic> organization;
  final String organizationName;
  final String memberName;
  final String roleName;
  final String? memberNumber;
  final bool switching;
  final VoidCallback? onSwitchCouncil;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final logoUrl = organization['logoUrl'] as String?;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E6F56), Color(0xFF16A278)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x220E6F56), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            foregroundImage: logoUrl == null || logoUrl.isEmpty
                ? null
                : NetworkImage(logoUrl),
            child: logoUrl == null || logoUrl.isEmpty
                ? const Icon(Icons.account_balance, color: Color(0xFF0E6F56))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(strings.welcomeBack,
                  style: const TextStyle(color: Colors.white70)),
              Text(organizationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.person_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      [
                        roleName,
                        if (memberNumber?.isNotEmpty == true)
                          '${strings.memberNumber}: $memberNumber',
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ]),
            ),
          ]),
        ),
        if (onSwitchCouncil != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: switching ? null : onSwitchCouncil,
            icon: switching
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.swap_horiz),
            label: Text(strings.switchCouncil),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54)),
          ),
        ],
      ]),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.members,
    required this.upcomingBookings,
    required this.pendingReceipts,
    required this.outstandingSubscriptions,
    required this.metricsUnavailable,
    this.onMembersTap,
    this.onBookingsTap,
    this.onReceiptsTap,
    this.onSubscriptionsTap,
  });
  final String? members;
  final String? upcomingBookings;
  final String? pendingReceipts;
  final String? outstandingSubscriptions;
  final bool metricsUnavailable;
  final VoidCallback? onMembersTap;
  final VoidCallback? onBookingsTap;
  final VoidCallback? onReceiptsTap;
  final VoidCallback? onSubscriptionsTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final cards = [
      _StatData(strings.members, members, Icons.groups_outlined,
          const Color(0xFF0A8F63), const Color(0xFFE7F8F2),
          unavailable: metricsUnavailable, onTap: onMembersTap),
      _StatData(
          strings.upcomingBookings,
          upcomingBookings,
          Icons.event_available_outlined,
          const Color(0xFF1769E0),
          const Color(0xFFEAF3FF),
          unavailable: metricsUnavailable,
          onTap: onBookingsTap),
      _StatData(
          strings.receiptsPendingReview,
          pendingReceipts,
          Icons.receipt_long_outlined,
          const Color(0xFFE06B17),
          const Color(0xFFFFF3E3),
          onTap: onReceiptsTap),
      _StatData(
          strings.outstandingSubscriptions,
          outstandingSubscriptions,
          Icons.credit_card_outlined,
          const Color(0xFF7243D6),
          const Color(0xFFF1EBFF),
          onTap: onSubscriptionsTap),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 142,
      ),
      itemBuilder: (context, index) => _SummaryStatCard(data: cards[index]),
    );
  }
}

class _StatData {
  const _StatData(
      this.label, this.value, this.icon, this.color, this.background,
      {this.unavailable = false, this.onTap});
  final String label;
  final String? value;
  final IconData icon;
  final Color color;
  final Color background;
  final bool unavailable;
  final VoidCallback? onTap;
}

class _SummaryStatCard extends StatelessWidget {
  const _SummaryStatCard({required this.data});
  final _StatData data;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8EDF3)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 12,
                    offset: Offset(0, 4)),
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                  radius: 20,
                  backgroundColor: data.background,
                  child: Icon(data.icon, color: data.color, size: 22)),
              const Spacer(),
              if (data.unavailable)
                Text(
                  AppLocalizations.of(context).unavailable,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC45117),
                  ),
                )
              else if (data.value == null)
                const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text(data.value!,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
              Text(data.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF667085))),
            ]),
          ),
        ),
      );
}

class _DashboardAction {
  const _DashboardAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.actions,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_DashboardAction> actions;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE8EDF3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                backgroundColor: color.withValues(alpha: .1),
                child: Icon(icon, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF667085))),
                  ]),
            ),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final action in actions)
                SizedBox(
                    width: width,
                    child: _FeatureActionTile(action: action, color: color)),
            ]);
          }),
        ]),
      );
}

class _FeatureActionTile extends StatelessWidget {
  const _FeatureActionTile({required this.action, required this.color});
  final _DashboardAction action;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 82),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, color: color),
                    const SizedBox(height: 7),
                    Text(action.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
            ),
          ),
        ),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});
  final List<_DashboardAction> actions;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(title: strings.quickActions, icon: Icons.bolt_outlined),
      const SizedBox(height: 10),
      SizedBox(
        height: 98,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: actions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final action = actions[index];
            return SizedBox(
              width: 126,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: action.onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(action.icon, color: AppColors.primary),
                          const SizedBox(height: 7),
                          Text(action.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                        ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _ImportantAlerts extends StatelessWidget {
  const _ImportantAlerts({
    required this.bookings,
    required this.receipts,
    required this.charges,
    required this.canReviewBookings,
    required this.canReviewReceipts,
    required this.canManageFinance,
  });
  final AsyncValue<List<BookingModel>> bookings;
  final AsyncValue<List<dynamic>>? receipts;
  final AsyncValue<List<FinancialCharge>>? charges;
  final bool canReviewBookings;
  final bool canReviewReceipts;
  final bool canManageFinance;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final alerts = <({
      IconData icon,
      Color color,
      String text,
      int count,
      VoidCallback action,
    })>[];
    final isLoading = (canReviewBookings && bookings.isLoading) ||
        (receipts?.isLoading ?? false) ||
        (charges?.isLoading ?? false);
    final hasError = (canReviewBookings && bookings.hasError) ||
        (receipts?.hasError ?? false) ||
        (charges?.hasError ?? false);
    final bookingItems = bookings.valueOrNull;
    if (canReviewBookings && bookingItems != null) {
      final count =
          bookingItems.where((item) => item.status == 'pending').length;
      if (count > 0) {
        alerts.add((
          icon: Icons.event_busy_outlined,
          color: Colors.orange,
          text: strings.pendingBookingsAlert,
          count: count,
          action: () => context.pushNamed('bookingRequestsReview'),
        ));
      }
    }
    final receiptItems = receipts?.valueOrNull;
    if (receiptItems != null) {
      final count =
          receiptItems.where((item) => item.reviewStatus == 'pending').length;
      if (count > 0) {
        alerts.add((
          icon: Icons.receipt_long_outlined,
          color: Colors.red,
          text: strings.pendingReceiptsAlert,
          count: count,
          action: () => context.pushNamed('financialReview'),
        ));
      }
    }
    final chargeItems = charges?.valueOrNull;
    if (chargeItems != null) {
      final count = chargeItems
          .where((item) =>
              item.chargeType == ChargeType.subscription &&
              item.status == ChargeStatus.overdue &&
              item.balanceBaisa > 0)
          .length;
      if (count > 0) {
        alerts.add((
          icon: Icons.warning_amber_rounded,
          color: Colors.deepOrange,
          text: strings.overdueSubscriptionsAlert,
          count: count,
          action: () => context.pushNamed('financialManagement'),
        ));
      }
    }
    return InkWell(
      onTap: () => context.pushNamed('importantAlerts'),
      borderRadius: BorderRadius.circular(20),
      child: _Panel(
        title: strings.importantAlerts,
        icon: Icons.notification_important_outlined,
        child: alerts.isEmpty && isLoading
            ? const Center(child: CircularProgressIndicator())
            : alerts.isEmpty && hasError
                ? _EmptyLine(
                    icon: Icons.cloud_off_outlined, text: strings.couldNotLoad)
                : alerts.isEmpty
                    ? _EmptyLine(
                        icon: Icons.check_circle_outline,
                        text: strings.noImportantAlerts)
                    : Column(children: [
                        for (var index = 0; index < alerts.length; index++) ...[
                          if (index > 0) const Divider(height: 20),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: alerts[index].action,
                            leading: Icon(alerts[index].icon,
                                color: alerts[index].color),
                            title: Text(alerts[index].text),
                            trailing:
                                Badge(label: Text('${alerts[index].count}')),
                          ),
                        ],
                      ]),
      ),
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity(
      {required this.notifications, required this.organizationId, this.userId});
  final AsyncValue<List<AppNotificationModel>> notifications;
  final String organizationId;
  final String? userId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return _Panel(
      title: strings.recentActivity,
      icon: Icons.history_outlined,
      child: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _EmptyLine(
            icon: Icons.cloud_off_outlined, text: strings.couldNotLoad),
        data: (items) {
          final scoped = items
              .where((item) => item.organizationId == organizationId)
              .take(4)
              .toList();
          if (scoped.isEmpty) {
            return _EmptyLine(
                icon: Icons.inbox_outlined, text: strings.noRecentActivity);
          }
          return Column(children: [
            for (var index = 0; index < scoped.length; index++) ...[
              if (index > 0) const Divider(height: 20),
              _ActivityRow(
                notification: scoped[index],
                onTap: userId == null ||
                        !NotificationDeepLink.hasDestination(
                          type: scoped[index].type,
                          relatedEntityType: scoped[index].relatedEntityType,
                        )
                    ? null
                    : () => _openNotification(context, ref, scoped[index]),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.pushNamed('notifications'),
                child: Text(strings.viewAllNotifications),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    AppNotificationModel notification,
  ) async {
    final userId = this.userId;
    if (userId == null) return;
    if (notification.isUnread) {
      try {
        await ref.read(notificationRepositoryProvider).markAsRead(
              userId,
              notification.notificationId,
            );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(AppLocalizations.of(context).couldNotUpdateNotification),
            ),
          );
        }
        return;
      }
    }
    if (!context.mounted) return;
    await NotificationDeepLink.open(
      context,
      ref,
      type: notification.type,
      relatedEntityType: notification.relatedEntityType,
      relatedEntityId: notification.relatedEntityId,
      organizationId: notification.organizationId,
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.notification, this.onTap});
  final AppNotificationModel notification;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFEAF3FF),
            child: Icon(Icons.notifications_none,
                size: 19, color: Color(0xFF1769E0)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(notification.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(notification.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF667085))),
              const SizedBox(height: 3),
              Text(
                  DateFormat.yMd(locale)
                      .add_jm()
                      .format(notification.createdAt),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF98A2B3))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8EDF3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(title: title, icon: icon),
          const SizedBox(height: 14),
          child,
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold))),
      ]);
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: const Color(0xFF98A2B3)),
          const SizedBox(width: 8),
          Flexible(
              child:
                  Text(text, style: const TextStyle(color: Color(0xFF667085)))),
        ]),
      );
}

class _DashboardDrawer extends StatelessWidget {
  const _DashboardDrawer({
    required this.organizationName,
    required this.logoUrl,
    required this.onHome,
    required this.onDaily,
    required this.onFinance,
    required this.onManagement,
  });
  final String organizationName;
  final String? logoUrl;
  final VoidCallback onHome;
  final VoidCallback onDaily;
  final VoidCallback onFinance;
  final VoidCallback onManagement;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return NavigationDrawer(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
        child: Row(children: [
          CircleAvatar(
            radius: 26,
            foregroundImage:
                logoUrl?.isNotEmpty == true ? NetworkImage(logoUrl!) : null,
            child: logoUrl?.isNotEmpty == true
                ? null
                : const Icon(Icons.account_balance_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(organizationName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
      const Divider(),
      ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(strings.home),
          onTap: onHome),
      ListTile(
          leading: const Icon(Icons.today_outlined),
          title: Text(strings.dailyOperations),
          onTap: onDaily),
      ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: Text(strings.finance),
          onTap: onFinance),
      ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: Text(strings.councilManagement),
          onTap: onManagement),
    ]);
  }
}

String _organizationName(Map<String, dynamic> organization, String locale) {
  final preferred = locale == 'en'
      ? organization['officialNameEnglish']
      : organization['officialNameArabic'];
  if (preferred is String && preferred.trim().isNotEmpty) return preferred;
  final fallback = locale == 'en'
      ? organization['officialNameArabic']
      : organization['officialNameEnglish'];
  if (fallback is String && fallback.trim().isNotEmpty) return fallback;
  return organization['shortName'] as String? ??
      organization['organizationId'] as String? ??
      '-';
}

String _organizationSearchText(Map<String, dynamic> organization) => [
      organization['officialNameArabic'],
      organization['officialNameEnglish'],
      organization['shortName'],
    ].whereType<String>().join(' ').toLowerCase();

String _roleName(Map<String, dynamic>? role, String fallback, String locale,
    AppLocalizations strings) {
  final value = role?['roleName'];
  if (value is Map && value[locale] is String) return value[locale] as String;
  if (fallback == 'system_owner' || fallback == 'superAdmin') {
    return strings.platformAdministrator;
  }
  return switch (fallback) {
    'owner' || 'council_owner' => strings.councilOwnerRole,
    'chairman' => strings.chairmanRole,
    'adminManager' => strings.administrativeManagerRole,
    'financialManager' => strings.financialManagerRole,
    'financialReviewer' => strings.financialReviewerRole,
    'member' => strings.memberRole,
    _ => fallback,
  };
}

String _statusName(MembershipStatus status, AppLocalizations strings) =>
    switch (status) {
      MembershipStatus.active => strings.active,
      MembershipStatus.pending => strings.pending,
      MembershipStatus.suspended => strings.suspended,
      MembershipStatus.rejected => strings.rejected,
      MembershipStatus.resigned => strings.resigned,
      MembershipStatus.removed => strings.removed,
      MembershipStatus.cancelled => strings.cancelled,
    };

void _showOrganization(
    BuildContext context, Map<String, dynamic> organization) {
  final strings = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  final rawDescription = organization['description'];
  final description = rawDescription is Map
      ? rawDescription[locale]?.toString()
      : rawDescription?.toString();
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(_organizationName(organization, locale)),
      content: Text(description?.trim().isNotEmpty == true
          ? description!
          : strings.noAdditionalInformation),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.close)),
      ],
    ),
  );
}

void _showMembership(BuildContext context, MembershipModel? membership) {
  final strings = AppLocalizations.of(context);
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(strings.membershipStatus),
      content: Text(membership == null
          ? strings.fullPlatformAccess
          : '${_statusName(membership.status, strings)}\n${strings.memberNumber}: ${membership.memberNumber}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.close)),
      ],
    ),
  );
}

void _comingSoon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).serviceComingSoon)));
}
