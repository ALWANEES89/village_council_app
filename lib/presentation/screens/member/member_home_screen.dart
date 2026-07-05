import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/role_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/membership_model.dart';
import '../../../data/models/payment_model.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../data/repositories/membership_repository.dart';
import '../../../features/membership_request/data/membership_request_model.dart';
import '../../../features/membership_request/providers/membership_request_providers.dart';
import '../../../providers/app_providers.dart';
import 'council_booking_screen.dart';
import '../../widgets/notification_bell.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen> {
  String? _cachedMembershipUserId;
  List<MembershipModel> _cachedMemberships = const [];
  bool _membershipLoadFailed = false;

  Future<void> _refresh(String userId) async {
    ref.invalidate(currentMemberProvider);
    ref.invalidate(userProfileProvider(userId));
    ref.invalidate(userMembershipsProvider(userId));
    ref.invalidate(activeUserMembershipsProvider(userId));
    ref.invalidate(userMembershipRequestsProvider(userId));
    ref.invalidate(memberPaymentsProvider(userId));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _retryMembershipLoading(String userId) async {
    ref.invalidate(activeUserMembershipsProvider(userId));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  List<MembershipModel> _visibleMemberships(
    String userId,
    AsyncValue<ActiveMembershipsResult> membershipsAsync,
  ) {
    if (_cachedMembershipUserId != userId) {
      _cachedMembershipUserId = userId;
      _cachedMemberships = const [];
      _membershipLoadFailed = false;
    }

    final result = membershipsAsync.asData?.value;
    if (result != null) {
      if (result.memberships.isNotEmpty) {
        _cachedMemberships = List.unmodifiable(result.memberships);
      } else if (!result.loadFailed) {
        _cachedMemberships = const [];
      }
      _membershipLoadFailed = result.loadFailed;
    } else if (membershipsAsync.hasError) {
      _membershipLoadFailed = true;
    }
    return _cachedMemberships;
  }

  Future<void> _signOut() async {
    ref.read(organizationContextProvider.notifier).clearOrganization();
    await ref.read(authServiceProvider).signOut();
    if (mounted) context.goNamed('login');
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('هذه الخدمة ستتوفر قريبًا')),
    );
  }

  Future<bool> _selectMembership(MembershipModel membership) async {
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
          const SnackBar(content: Text('تعذر فتح المجلس. حاول مرة أخرى.')),
        );
      }
      return false;
    }
  }

  Future<void> _enterCouncil(MembershipModel membership) async {
    if (await _selectMembership(membership) && mounted) {
      context.pushNamed('councilDashboard');
    }
  }

  Future<void> _openPaymentHistory(List<MembershipModel> active) async {
    if (active.isEmpty) {
      _showComingSoon();
      return;
    }
    if (await _selectMembership(active.first) && mounted) {
      context.pushNamed('dashboard');
    }
  }

  Future<void> _uploadReceipt(
    List<MembershipModel> active,
    List<PaymentModel> payments,
  ) async {
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد عضوية نشطة لرفع إيصال')),
      );
      return;
    }
    final membership = await _chooseMembership(active);
    if (membership == null || !mounted) return;
    final matchingPayments = payments
        .where((item) => item.status != PaymentStatus.paid)
        .where(
          (item) =>
              item.organizationId == membership.organizationId ||
              (active.length == 1 && item.organizationId == null),
        )
        .toList();
    final payment = matchingPayments.isEmpty ? null : matchingPayments.first;
    if (await _selectMembership(membership) && mounted) {
      context.pushNamed(
        'uploadReceipt',
        extra: {
          'organizationId': membership.organizationId,
          'membershipId': membership.id,
          'userId': membership.userId,
          'paymentId': payment?.id,
          'periodLabel': payment?.periodLabel ?? 'إيصال دفع عام',
          'amountDeclared': payment?.amount,
        },
      );
    }
  }

  Future<void> _openCouncilBooking(
    List<MembershipModel> activeMemberships,
  ) async {
    if (activeMemberships.isEmpty) {
      context.pushNamed('rentalPlaceholder');
      return;
    }
    final membership = await _chooseMembership(activeMemberships);
    if (membership == null || !mounted) return;
    context.pushNamed(
      'rentalPlaceholder',
      extra: CouncilBookingArguments(
        organizationId: membership.organizationId,
        membershipId: membership.id,
      ),
    );
  }

  Future<MembershipModel?> _chooseMembership(
    List<MembershipModel> memberships,
  ) async {
    if (memberships.length == 1) return memberships.single;
    final organizations = await Future.wait(
      memberships.map(
        (membership) => ref
            .read(organizationRepositoryProvider)
            .getById(membership.organizationId),
      ),
    );
    if (!mounted) return null;
    return showDialog<MembershipModel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('اختر المجلس'),
        children: [
          for (var index = 0; index < memberships.length; index++)
            SimpleDialogOption(
              onPressed: () => context.pop(memberships[index]),
              child: ListTile(
                leading: const Icon(
                  Icons.account_balance_outlined,
                  color: AppColors.primary,
                ),
                title: Text(_organizationName(organizations[index])),
                subtitle: Text(
                  'رقم العضو: ${memberships[index].memberNumber}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);
    final user =
        authAsync.asData?.value ?? ref.read(authServiceProvider).currentUser;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F5FA),
        body: user == null
            ? authAsync.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _SignedOutView(onSignOut: _signOut)
            : _buildDashboard(user),
      ),
    );
  }

  Widget _buildDashboard(User user) {
    final memberAsync = ref.watch(currentMemberProvider);
    final profileAsync = ref.watch(userProfileProvider(user.uid));
    final membershipsAsync = ref.watch(activeUserMembershipsProvider(user.uid));
    final requestsAsync = ref.watch(userMembershipRequestsProvider(user.uid));
    final paymentsAsync = ref.watch(memberPaymentsProvider(user.uid));
    final adminAccessAsync = ref.watch(adminAccessProvider);

    final member = memberAsync.asData?.value;
    final profile = profileAsync.asData?.value;
    final memberships = _visibleMemberships(user.uid, membershipsAsync);
    final requests = requestsAsync.asData?.value ?? const [];
    final payments = paymentsAsync.asData?.value ?? const [];
    final active = memberships
        .where((item) => item.status == MembershipStatus.active)
        .toList();
    final pending = requests
        .where((item) => item.status == MembershipRequestStatus.pending)
        .toList();
    final profileData = _ProfileData.resolve(
      user: user,
      profile: profile,
      member: member,
      memberNumber: active.isEmpty ? null : active.first.memberNumber,
    );

    return RefreshIndicator(
      onRefresh: () => _refresh(user.uid),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _HeaderAndProfile(
            profile: profileData,
            onEditProfile: () => context.pushNamed('profileEdit'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (profileAsync.hasError || memberAsync.hasError)
                  const _WarningCard(
                    message:
                        'تعذر تحميل بعض بيانات الملف الشخصي، ويمكنك متابعة استخدام التطبيق.',
                  ),
                if (_membershipLoadFailed || membershipsAsync.hasError)
                  _WarningCard(
                    message: 'تعذر تحميل العضويات. حاول مرة أخرى.',
                    onRetry: () => _retryMembershipLoading(user.uid),
                  ),
                if (requestsAsync.hasError &&
                    active.isEmpty &&
                    requests.isEmpty)
                  const _WarningCard(
                    message: 'تعذر تحديث طلبات العضوية حاليًا.',
                  ),
                if (adminAccessAsync.asData?.value.isSuperAdmin == true) ...[
                  _SuperAdminCard(
                    onTap: () => context.pushNamed('adminDashboard'),
                  ),
                  const SizedBox(height: 18),
                ],
                _MembershipSection(
                  activeMemberships: active,
                  pendingRequests: pending,
                  isSuperAdmin:
                      adminAccessAsync.asData?.value.isSuperAdmin == true,
                  unavailable: membershipsAsync.hasError && active.isEmpty,
                  loading: (membershipsAsync.isLoading && active.isEmpty) ||
                      requestsAsync.isLoading,
                  onEnterCouncil: _enterCouncil,
                ),
                const SizedBox(height: 18),
                _MainActions(
                  onJoinRequest: () => context.pushNamed('joinRequest'),
                  onRentCouncil: () => _openCouncilBooking(active),
                ),
                const SizedBox(height: 18),
                _AccountSummaryCard(
                  payments: payments,
                  loading: paymentsAsync.isLoading,
                  unavailable: paymentsAsync.hasError,
                  onOpenHistory: () => _openPaymentHistory(active),
                ),
                const SizedBox(height: 18),
                const _SectionTitle(title: 'الخدمات السريعة'),
                const SizedBox(height: 10),
                _QuickServices(
                  onUploadReceipt: () => _uploadReceipt(active, payments),
                  onRentCouncil: () => _openCouncilBooking(active),
                  onReceiptHistory: () => context.pushNamed('receiptHistory'),
                  onComingSoon: _showComingSoon,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل الخروج'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      backgroundColor: Colors.red.shade50,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuperAdminCard extends StatelessWidget {
  const _SuperAdminCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade700, Colors.amber.shade400],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF9A6700),
          child: Icon(Icons.admin_panel_settings_outlined),
        ),
        title: const Text(
          'لوحة التحكم',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: const Text(
          'إدارة المجالس والمستخدمين والصلاحيات',
          style: TextStyle(color: Colors.white),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white),
        onTap: onTap,
      ),
    );
  }
}

class _HeaderAndProfile extends StatelessWidget {
  const _HeaderAndProfile({
    required this.profile,
    required this.onEditProfile,
  });

  final _ProfileData profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 490,
      child: Stack(
        children: [
          Container(
            height: 230,
            padding: const EdgeInsets.fromLTRB(18, 48, 18, 60),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(34),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'مجلس القرية',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const NotificationBell(color: Colors.white),
              ],
            ),
          ),
          Positioned(
            top: 145,
            left: 16,
            right: 16,
            child: _ProfileCard(
              profile: profile,
              onEditProfile: onEditProfile,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onEditProfile});

  final _ProfileData profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ProfileAvatar(photoUrl: profile.photoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرحبًا، ${profile.fullName}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      profile.phone.isEmpty
                          ? 'رقم الهاتف غير متاح'
                          : profile.phone,
                      textDirection: ui.TextDirection.ltr,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            runSpacing: 8,
            children: [
              if (profile.civilId.isNotEmpty)
                _ProfileLine(icon: Icons.badge_outlined, text: profile.civilId),
              if (profile.memberNumber.isNotEmpty)
                _ProfileLine(
                  icon: Icons.confirmation_number_outlined,
                  text: 'رقم العضو: ${profile.memberNumber}',
                ),
              if (profile.email.isNotEmpty)
                _ProfileLine(icon: Icons.email_outlined, text: profile.email),
              if (profile.address.isNotEmpty)
                _ProfileLine(
                  icon: Icons.location_on_outlined,
                  text: profile.address,
                ),
              _ProfileLine(
                icon: Icons.calendar_today_outlined,
                text: DateFormat('EEEE، d MMMM yyyy', 'ar')
                    .format(DateTime.now()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEditProfile,
              icon: const Icon(Icons.edit_outlined, size: 19),
              label: const Text('تعديل الملف الشخصي'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.1),
      ),
      child: url == null || url.isEmpty
          ? const Icon(Icons.person, size: 42, color: AppColors.primary)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.person,
                size: 42,
                color: AppColors.primary,
              ),
            ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _MembershipSection extends StatelessWidget {
  const _MembershipSection({
    required this.activeMemberships,
    required this.pendingRequests,
    required this.isSuperAdmin,
    required this.unavailable,
    required this.loading,
    required this.onEnterCouncil,
  });

  final List<MembershipModel> activeMemberships;
  final List<MembershipRequestModel> pendingRequests;
  final bool isSuperAdmin;
  final bool unavailable;
  final bool loading;
  final ValueChanged<MembershipModel> onEnterCouncil;

  @override
  Widget build(BuildContext context) {
    if (loading && activeMemberships.isEmpty && pendingRequests.isEmpty) {
      return const _SoftCard(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (activeMemberships.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'عضوياتك'),
          const SizedBox(height: 10),
          for (final membership in activeMemberships)
            _MembershipCard(
              membership: membership,
              onEnter: () => onEnterCouncil(membership),
            ),
          if (pendingRequests.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'طلباتك قيد المراجعة',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final request in pendingRequests)
              _PendingOrganizationName(request: request),
          ],
        ],
      );
    }
    if (pendingRequests.isNotEmpty) {
      return _SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'طلباتك قيد المراجعة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('لديك ${pendingRequests.length} طلب قيد مراجعة الإدارة.'),
            const SizedBox(height: 12),
            for (final request in pendingRequests)
              _PendingOrganizationName(request: request),
          ],
        ),
      );
    }
    if (isSuperAdmin) {
      return const _SoftCard(
        child: Text(
          'يمكنك إدارة جميع المجالس من لوحة التحكم دون الحاجة إلى عضوية.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    if (unavailable) return const SizedBox.shrink();
    return const _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حالة عضويتك',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('لا توجد عضوية مرتبطة بحسابك حاليًا'),
          SizedBox(height: 5),
          Text(
            'يمكنك طلب الانضمام إلى أحد المجالس',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _MembershipCard extends ConsumerStatefulWidget {
  const _MembershipCard({required this.membership, required this.onEnter});

  final MembershipModel membership;
  final VoidCallback onEnter;

  @override
  ConsumerState<_MembershipCard> createState() => _MembershipCardState();
}

class _MembershipCardState extends ConsumerState<_MembershipCard> {
  late Future<_OrganizationMeta> _meta;

  @override
  void initState() {
    super.initState();
    _meta = _load();
  }

  @override
  void didUpdateWidget(covariant _MembershipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membership.organizationId !=
            widget.membership.organizationId ||
        oldWidget.membership.roleId != widget.membership.roleId) {
      _meta = _load();
    }
  }

  Future<_OrganizationMeta> _load() async {
    final organization = await ref
        .read(organizationRepositoryProvider)
        .getById(widget.membership.organizationId);
    final role = await ref.read(roleRepositoryProvider).getById(
          organizationId: widget.membership.organizationId,
          roleId: widget.membership.roleId,
        );
    return _OrganizationMeta(organization: organization, role: role);
  }

  @override
  Widget build(BuildContext context) {
    final liveMembership = ref
            .watch(membershipDocumentProvider((
              organizationId: widget.membership.organizationId,
              membershipId: widget.membership.id,
            )))
            .asData
            ?.value ??
        widget.membership;
    if (liveMembership.status != MembershipStatus.active) {
      return const SizedBox.shrink();
    }
    // الصلاحية العالمية (المالك الأعلى) مصدرها platform_admins وتتغلّب على الدور
    // المحلي داخل أي مجلس. نعرضها بوضوح حتى لا تبدو الصلاحية مختلفة بين المجالس.
    final isPlatformOwner =
        ref.watch(adminAccessProvider).asData?.value.isPlatformOwner == true;
    return FutureBuilder<_OrganizationMeta>(
      future: _meta,
      builder: (context, snapshot) {
        final name = _organizationName(snapshot.data?.organization);
        final role = roleLabelArabic(
          liveMembership.roleId,
          role: liveMembership.role,
          fallback: _roleName(snapshot.data?.role, liveMembership.roleId),
        );
        return GestureDetector(
          onTap: widget.onEnter,
          child: _SoftCard(
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0x146200EE),
                      child:
                          Icon(Icons.account_balance, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const _StatusBadge(label: 'نشط', color: Colors.green),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                    'رقم العضو: ${liveMembership.memberNumber.isEmpty ? '-' : liveMembership.memberNumber}'),
                if (isPlatformOwner) ...[
                  Row(
                    children: [
                      Icon(Icons.verified_user,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 4),
                      const Text(
                        'الصلاحية: المالك الأعلى',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    'الدور داخل هذا المجلس: $role',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ] else
                  Text('الدور: $role'),
                Text(
                  'تاريخ الانضمام: ${DateFormat('yyyy/MM/dd').format(widget.membership.joinedAt)}',
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: widget.onEnter,
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('دخول المجلس'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PendingOrganizationName extends ConsumerStatefulWidget {
  const _PendingOrganizationName({required this.request});

  final MembershipRequestModel request;

  @override
  ConsumerState<_PendingOrganizationName> createState() =>
      _PendingOrganizationNameState();
}

class _PendingOrganizationNameState
    extends ConsumerState<_PendingOrganizationName> {
  late Future<Map<String, dynamic>?> _organization;

  @override
  void initState() {
    super.initState();
    _organization = ref
        .read(organizationRepositoryProvider)
        .getById(widget.request.organizationId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _organization,
      builder: (context, snapshot) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.hourglass_top, color: Colors.orange),
        title: Text(
          _organizationName(snapshot.data),
        ),
      ),
    );
  }
}

class _MainActions extends StatelessWidget {
  const _MainActions({
    required this.onJoinRequest,
    required this.onRentCouncil,
  });

  final VoidCallback onJoinRequest;
  final VoidCallback onRentCouncil;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LargeActionCard(
            icon: Icons.group_add_outlined,
            title: 'طلب الانضمام إلى مجلس',
            subtitle: 'انضم إلى أحد المجالس المتاحة',
            onTap: onJoinRequest,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LargeActionCard(
            icon: Icons.home_work_outlined,
            title: 'استئجار مجلس',
            subtitle: 'استأجر مجلس لإقامة مناسبة',
            onTap: onRentCouncil,
          ),
        ),
      ],
    );
  }
}

class _LargeActionCard extends StatelessWidget {
  const _LargeActionCard({
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 158,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Color(0x0E000000), blurRadius: 18),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.payments,
    required this.loading,
    required this.unavailable,
    required this.onOpenHistory,
  });

  final List<PaymentModel> payments;
  final bool loading;
  final bool unavailable;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final paid = payments.where((item) => item.status == PaymentStatus.paid);
    final due = payments.where((item) => item.status != PaymentStatus.paid);
    final paidAmount = paid.fold<double>(0, (sum, item) => sum + item.amount);
    final remaining = due.fold<double>(0, (sum, item) => sum + item.amount);
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'ملخص الحساب'),
          if (loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _SummaryItem(
                    label: 'الفواتير المستحقة', value: '${due.length}'),
                _SummaryItem(
                    label: 'الفواتير المدفوعة', value: '${paid.length}'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _SummaryItem(
                  label: 'المبلغ المدفوع',
                  value: paidAmount.toStringAsFixed(3),
                ),
                _SummaryItem(
                  label: 'المبلغ المتبقي',
                  value: remaining.toStringAsFixed(3),
                ),
              ],
            ),
          ],
          if (unavailable) ...[
            const SizedBox(height: 10),
            const Text(
              'تعذر تحديث بيانات المدفوعات حاليًا، وتظهر القيم الافتراضية.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenHistory,
              child: const Text('عرض سجل المدفوعات'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _QuickServices extends StatelessWidget {
  const _QuickServices({
    required this.onUploadReceipt,
    required this.onRentCouncil,
    required this.onReceiptHistory,
    required this.onComingSoon,
  });

  final VoidCallback onUploadReceipt;
  final VoidCallback onRentCouncil;
  final VoidCallback onReceiptHistory;
  final VoidCallback onComingSoon;

  @override
  Widget build(BuildContext context) {
    final services = [
      (Icons.upload_file_outlined, 'رفع إيصال', onUploadReceipt),
      (Icons.event_available_outlined, 'حجز مجلس', onRentCouncil),
      (Icons.history_outlined, 'سجل الإيصالات', onReceiptHistory),
      (Icons.campaign_outlined, 'الإعلانات', onComingSoon),
      (Icons.help_outline, 'الأسئلة الشائعة', onComingSoon),
      (Icons.support_agent_outlined, 'تواصل معنا', onComingSoon),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, index) {
        final service = services[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: service.$3,
            borderRadius: BorderRadius.circular(17),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(service.$1, color: AppColors.primary, size: 29),
                  const SizedBox(height: 8),
                  Text(
                    service.$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D000000), blurRadius: 18, offset: Offset(0, 7)),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textDark,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  const _SignedOutView({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('تعذر تحميل بيانات حسابك'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onSignOut,
              child: const Text('العودة إلى تسجيل الدخول'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.fullName,
    required this.phone,
    required this.civilId,
    required this.memberNumber,
    required this.email,
    required this.address,
    this.photoUrl,
  });

  final String fullName;
  final String phone;
  final String civilId;
  final String memberNumber;
  final String email;
  final String address;
  final String? photoUrl;

  factory _ProfileData.resolve({
    required User user,
    required UserProfileModel? profile,
    required MemberModel? member,
    required String? memberNumber,
  }) {
    return _ProfileData(
      fullName: _firstValue([profile?.fullName, member?.fullName], 'عضو'),
      phone: _firstValue(
        [
          profile?.phone,
          member?.phone,
          user.phoneNumber,
          _phoneFromEmail(user.email)
        ],
        '',
      ),
      civilId: _firstValue([profile?.civilId, member?.civilId], ''),
      memberNumber: memberNumber?.trim() ?? '',
      email: profile?.email.trim() ?? '',
      address: profile?.address.trim() ?? '',
      photoUrl: profile?.photoUrl,
    );
  }
}

class _OrganizationMeta {
  const _OrganizationMeta({required this.organization, required this.role});

  final Map<String, dynamic>? organization;
  final Map<String, dynamic>? role;
}

String _firstValue(List<String?> values, String fallback) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return fallback;
}

String? _phoneFromEmail(String? email) {
  if (email == null || !email.endsWith('@alrahmat.local')) return null;
  final digits = email.split('@').first;
  return digits.isEmpty ? null : '+$digits';
}

String _organizationName(Map<String, dynamic>? data) {
  if (data == null) return 'اسم المجلس غير متاح';
  final arabic = data['officialNameArabic'];
  if (arabic is String && arabic.trim().isNotEmpty) return arabic;
  final shortName = data['shortName'];
  if (shortName is String && shortName.trim().isNotEmpty) return shortName;
  return 'اسم المجلس غير متاح';
}

String _roleName(Map<String, dynamic>? data, String fallback) {
  if (data?['roleId'] != fallback) return fallback;
  if (data == null) return fallback;
  final name = data['roleName'];
  if (name is String && name.trim().isNotEmpty) return name;
  if (name is Map && name['ar'] is String) return name['ar'] as String;
  return fallback;
}
