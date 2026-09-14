import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/admin_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/financial_models.dart';
import '../../../data/models/membership_model.dart';
import '../../../domain/membership/join_council_routing.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/main_bottom_navigation.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/omr_amount.dart';
import 'council_booking_screen.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen> {
  Future<bool> _selectMembership(MembershipModel membership) async {
    final current = ref.read(organizationContextProvider).currentMembership;
    if (current?.organizationId == membership.organizationId &&
        current?.id == membership.id) {
      return true;
    }
    try {
      await ref.read(organizationContextProvider.notifier).selectOrganization(
            organizationId: membership.organizationId,
            userId: membership.userId,
            membershipId: membership.id,
          );
      return mounted;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotOpenCouncil),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _openBooking(MembershipModel? membership) async {
    if (membership != null && !await _selectMembership(membership)) return;
    if (!mounted) return;
    context.pushNamed(
      'rentalPlaceholder',
      extra: CouncilBookingArguments(
        organizationId: membership?.organizationId,
        membershipId: membership?.id,
      ),
    );
  }

  Future<void> _openPayments(MembershipModel? membership) async {
    if (membership == null) return _showNoMembership();
    if (await _selectMembership(membership) && mounted) {
      context.pushNamed('dashboard');
    }
  }

  Future<void> _openCouncilDashboard(MembershipModel membership) async {
    if (await _selectMembership(membership) && mounted) {
      context.pushNamed('councilDashboard');
    }
  }

  Future<void> _uploadReceipt(MembershipModel? membership) async {
    if (membership == null) return _showNoMembership();
    if (!await _selectMembership(membership) || !mounted) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    context.pushNamed(
      'uploadReceipt',
      extra: ReceiptUploadArguments(
        organizationId: membership.organizationId,
        membershipId: membership.id,
        userId: user.uid,
        periodLabel: AppLocalizations.of(context).generalPaymentReceipt,
      ),
    );
  }

  void _showNoMembership() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).noActiveMembership)),
    );
  }

  Future<void> _onBottomNavigation(
    int index,
    MembershipModel? membership,
  ) async {
    switch (index) {
      case 0:
        return;
      case 1:
        return _openBooking(membership);
      case 2:
        return _openPayments(membership);
      case 3:
        if (mounted) context.pushNamed('notifications');
        return;
      case 4:
        if (mounted) context.pushNamed('myAccount');
        return;
    }
  }

  Future<void> _refresh(User user, MembershipModel? membership) async {
    ref.invalidate(userProfileProvider(user.uid));
    ref.invalidate(activeUserMembershipsProvider(user.uid));
    ref.invalidate(userNotificationsProvider(user.uid));
    if (membership != null) {
      ref.invalidate(userBookingsProvider((
        organizationId: membership.organizationId,
        userId: user.uid,
      )));
      ref.invalidate(memberChargesProvider((
        organizationId: membership.organizationId,
        membershipId: membership.id,
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final auth = ref.watch(authStateProvider);
    final user = auth.valueOrNull ?? ref.read(authServiceProvider).currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: auth.isLoading
              ? const CircularProgressIndicator()
              : FilledButton(
                  onPressed: () => context.goNamed('login'),
                  child: Text(strings.returnHome),
                ),
        ),
      );
    }

    final membershipsState = ref.watch(activeUserMembershipsProvider(user.uid));
    final systemOwnerState = ref.watch(systemOwnerAccessProvider);
    if (membershipsState.isLoading || systemOwnerState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final membershipsResult = membershipsState.valueOrNull;
    final memberships = membershipsState.valueOrNull?.memberships
            .where((item) => item.status == MembershipStatus.active)
            .toList() ??
        const <MembershipModel>[];
    final membershipsLoadFailed = membershipsState.hasError ||
        membershipsResult == null ||
        membershipsResult.loadFailed;
    if (membershipsLoadFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(strings.couldNotLoadAccount),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(activeUserMembershipsProvider(user.uid)),
                  child: Text(strings.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isSystemOwner = systemOwnerState.valueOrNull == true;
    if (shouldOpenJoinCouncil(
      activeMembershipCount: memberships.length,
      membershipsLoadFailed: membershipsLoadFailed,
      isSystemOwner: isSystemOwner,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.goNamed('joinRequest');
      });
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(strings.findAndJoinCouncil),
            ],
          ),
        ),
      );
    }
    final contextState = ref.watch(organizationContextProvider);
    final selected = _selectedMembership(
      memberships,
      contextState.currentMembership,
    );
    final organizations =
        ref.watch(organizationsProvider).valueOrNull ?? const [];
    final organization =
        _organizationFor(organizations, selected?.organizationId);
    final locale = Localizations.localeOf(context).languageCode;
    final councilName =
        organization == null ? null : _organizationName(organization, locale);
    final profile = ref.watch(userProfileProvider(user.uid)).valueOrNull;
    final displayName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : strings.member;
    final access = selected == null
        ? const AdminAccess()
        : AdminAccess(
            isSuperAdmin: isSystemOwner,
            permissions: selected.permissionsSnapshot,
            roleId: selected.roleId,
            role: selected.role,
            isPrimaryOwner: selected.isPrimaryOwner,
            status: selected.status.name,
          );
    final bookings = selected == null
        ? null
        : ref.watch(userBookingsProvider((
            organizationId: selected.organizationId,
            userId: user.uid,
          )));
    final charges = selected == null
        ? null
        : ref.watch(memberChargesProvider((
            organizationId: selected.organizationId,
            membershipId: selected.id,
          )));
    final notifications = ref.watch(userNotificationsProvider(user.uid));

    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      bottomNavigationBar: MainBottomNavigation(
        selectedIndex: 0,
        onSelected: (index) => _onBottomNavigation(index, selected),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(user, selected),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _HomeHeader(
                name: displayName,
                councilName: councilName,
                photoUrl: profile?.photoUrl,
                onProfile: () => context.pushNamed('myAccount'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList.list(children: [
                if (memberships.length > 1) ...[
                  _CouncilSelector(
                    memberships: memberships,
                    organizations: organizations,
                    selected: selected,
                    onChanged: (membership) async {
                      if (membership != null) {
                        await _selectMembership(membership);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _UpcomingBookingCard(
                  state: bookings,
                  onBook: () => _openBooking(selected),
                  onDetails: () => _openBooking(selected),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionHeader(title: strings.services),
                const SizedBox(height: AppSpacing.sm),
                _ServicesGrid(
                  onBookings: () => _openBooking(selected),
                  onPayments: () => _openPayments(selected),
                  onReceipts: () => context.pushNamed('receiptHistory'),
                  onNotifications: () => context.pushNamed('notifications'),
                  onUpload: () => _uploadReceipt(selected),
                ),
                const SizedBox(height: AppSpacing.lg),
                _FinancialSummary(state: charges),
                const SizedBox(height: AppSpacing.md),
                _LatestNotification(
                  state: notifications,
                  organizationId: selected?.organizationId,
                ),
                if (selected != null && access.canAccessGoldenAdminPanel) ...[
                  const SizedBox(height: AppSpacing.md),
                  _AccessCard(
                    icon: Icons.dashboard_customize_outlined,
                    title: strings.councilDashboard,
                    subtitle: strings.councilDashboardDescription,
                    onTap: () => _openCouncilDashboard(selected),
                  ),
                ],
                if (isSystemOwner) ...[
                  const SizedBox(height: AppSpacing.md),
                  _AccessCard(
                    icon: Icons.public,
                    title: strings.systemAdministration,
                    subtitle: strings.systemAdministrationDescription,
                    onTap: () => context.pushNamed('adminDashboard'),
                  ),
                ],
                if (memberships.isEmpty && !membershipsState.isLoading) ...[
                  const SizedBox(height: AppSpacing.md),
                  _AccessCard(
                    icon: Icons.group_add_outlined,
                    title: strings.joinCouncil,
                    subtitle: strings.noActiveMembership,
                    onTap: () => context.pushNamed('joinRequest'),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.name,
    required this.councilName,
    required this.photoUrl,
    required this.onProfile,
  });
  final String name;
  final String? councilName;
  final String? photoUrl;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 10,
        16,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(children: [
        InkWell(
          onTap: onProfile,
          borderRadius: BorderRadius.circular(30),
          child: CircleAvatar(
            radius: 27,
            foregroundImage: photoUrl?.trim().isNotEmpty == true
                ? NetworkImage(photoUrl!)
                : null,
            child: photoUrl?.trim().isNotEmpty == true
                ? null
                : const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.welcomeUser(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (councilName != null)
                Text(
                  councilName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
        const NotificationBell(color: Colors.white),
      ]),
    );
  }
}

class _UpcomingBookingCard extends StatelessWidget {
  const _UpcomingBookingCard({
    required this.state,
    required this.onBook,
    required this.onDetails,
  });
  final AsyncValue<List<BookingModel>>? state;
  final VoidCallback onBook;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (state == null) {
      return _HomeCard(child: _EmptyBooking(onBook: onBook));
    }
    return state!.when(
      loading: () => const _HomeCard(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _HomeCard(
        child: _StateLine(
          icon: Icons.cloud_off_outlined,
          text: strings.couldNotLoad,
        ),
      ),
      data: (items) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final upcoming = items
            .where((item) =>
                !item.bookingDate.isBefore(today) &&
                const {'pending', 'approved', 'confirmed'}
                    .contains(item.status))
            .toList()
          ..sort((a, b) => a.bookingDate.compareTo(b.bookingDate));
        if (upcoming.isEmpty) {
          return _HomeCard(child: _EmptyBooking(onBook: onBook));
        }
        final booking = upcoming.first;
        final locale = Localizations.localeOf(context).languageCode;
        return _HomeCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeader(
              title: strings.upcomingBooking,
              icon: Icons.event_available_outlined,
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              text: DateFormat.yMMMMd(locale).format(booking.bookingDate),
            ),
            if (booking.occasionType.trim().isNotEmpty)
              _InfoRow(
                icon: Icons.celebration_outlined,
                text: booking.occasionType,
              ),
            _InfoRow(
              icon: Icons.info_outline,
              text: _bookingStatus(booking.status, strings),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onDetails,
                child: Text(strings.viewDetails),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _EmptyBooking extends StatelessWidget {
  const _EmptyBooking({required this.onBook});
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Row(children: [
      const CircleAvatar(
        radius: 25,
        backgroundColor: Color(0xFFFFEEE8),
        child: Icon(Icons.event_available_outlined, color: AppColors.primary),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(strings.noUpcomingBooking,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          TextButton(onPressed: onBook, child: Text(strings.bookNow)),
        ]),
      ),
    ]);
  }
}

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({
    required this.onBookings,
    required this.onPayments,
    required this.onReceipts,
    required this.onNotifications,
    required this.onUpload,
  });
  final VoidCallback onBookings;
  final VoidCallback onPayments;
  final VoidCallback onReceipts;
  final VoidCallback onNotifications;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final items = [
      (Icons.event_outlined, strings.bookings, onBookings),
      (Icons.credit_card_outlined, strings.subscriptions, onPayments),
      (Icons.receipt_long_outlined, strings.receipts, onReceipts),
      (Icons.notifications_outlined, strings.notifications, onNotifications),
      (Icons.upload_file_outlined, strings.uploadReceipt, onUpload),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 106,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          child: InkWell(
            onTap: item.$3,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$1, color: AppColors.primary),
                    const SizedBox(height: 6),
                    Text(
                      item.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ]),
            ),
          ),
        );
      },
    );
  }
}

class _FinancialSummary extends StatelessWidget {
  const _FinancialSummary({required this.state});
  final AsyncValue<List<FinancialCharge>>? state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return _HomeCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader(
          title: strings.outstandingAmount,
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        if (state == null)
          Text(strings.noActiveMembership)
        else
          state!.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _StateLine(
              icon: Icons.cloud_off_outlined,
              text: strings.couldNotLoad,
            ),
            data: (items) => OmrAmount(
              amountBaisa: items.fold<int>(
                0,
                (sum, item) => sum + item.balanceBaisa,
              ),
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ]),
    );
  }
}

class _LatestNotification extends StatelessWidget {
  const _LatestNotification({required this.state, this.organizationId});
  final AsyncValue<List<AppNotificationModel>> state;
  final String? organizationId;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return _HomeCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader(
          title: strings.latestNotification,
          icon: Icons.notifications_active_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        state.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => Text(strings.couldNotLoad),
          data: (items) {
            final scoped = organizationId == null
                ? items
                : items
                    .where((item) => item.organizationId == organizationId)
                    .toList();
            return scoped.isEmpty
                ? Text(strings.noNotifications)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(scoped.first.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          scoped.first.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ]);
          },
        ),
      ]),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _HomeCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          minTileHeight: 78,
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFFFEEE8),
            child: Icon(icon, color: AppColors.primary),
          ),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: onTap,
        ),
      );
}

class _CouncilSelector extends StatelessWidget {
  const _CouncilSelector({
    required this.memberships,
    required this.organizations,
    required this.selected,
    required this.onChanged,
  });
  final List<MembershipModel> memberships;
  final List<Map<String, dynamic>> organizations;
  final MembershipModel? selected;
  final ValueChanged<MembershipModel?> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return DropdownButtonFormField<MembershipModel>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).currentCouncil,
        prefixIcon: const Icon(Icons.account_balance_outlined),
        filled: true,
        fillColor: AppColors.surface,
      ),
      items: memberships.map((membership) {
        final organization =
            _organizationFor(organizations, membership.organizationId) ??
                {'organizationId': membership.organizationId};
        return DropdownMenuItem(
          value: membership,
          child: Text(
            _organizationName(organization, locale),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        elevation: 1,
        shadowColor: const Color(0x0A000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ]);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ]),
      );
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: AppColors.warning),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ]);
}

MembershipModel? _selectedMembership(
  List<MembershipModel> memberships,
  MembershipModel? current,
) {
  if (memberships.isEmpty) return null;
  if (current == null) return memberships.first;
  for (final membership in memberships) {
    if (membership.id == current.id &&
        membership.organizationId == current.organizationId) {
      return membership;
    }
  }
  return memberships.first;
}

Map<String, dynamic>? _organizationFor(
  List<Map<String, dynamic>> organizations,
  String? organizationId,
) {
  if (organizationId == null) return null;
  for (final organization in organizations) {
    if (organization['organizationId'] == organizationId) return organization;
  }
  return null;
}

String _organizationName(Map<String, dynamic> organization, String locale) {
  final preferred = locale == 'en'
      ? organization['officialNameEnglish']
      : organization['officialNameArabic'];
  final fallback = locale == 'en'
      ? organization['officialNameArabic']
      : organization['officialNameEnglish'];
  for (final value in [preferred, fallback, organization['shortName']]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return organization['organizationId'] as String? ?? '-';
}

String _bookingStatus(String status, AppLocalizations strings) =>
    switch (status) {
      'approved' || 'confirmed' => strings.approved,
      'pending' => strings.pending,
      'cancelled' => strings.cancelled,
      'rejected' => strings.rejected,
      _ => status,
    };
