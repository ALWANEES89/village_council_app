import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/membership_model.dart';
import '../../../providers/app_providers.dart';
import '../member/council_booking_screen.dart';
import '../../widgets/notification_bell.dart';

class CouncilDashboardScreen extends ConsumerWidget {
  const CouncilDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final councilContext = ref.watch(organizationContextProvider);
    final organization = councilContext.currentOrganization;
    if (!councilContext.hasOrganization || organization == null) {
      return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_outlined,
                    size: 64, color: AppColors.primary),
                const SizedBox(height: 14),
                const Text('لم يتم اختيار مجلس'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.goNamed('memberHome'),
                  child: const Text('العودة للرئيسية'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedMembership = councilContext.currentMembership;
    final membership = selectedMembership == null
        ? null
        : ref
                .watch(membershipDocumentProvider((
                  organizationId: organization['organizationId'] as String,
                  membershipId: selectedMembership.id,
                )))
                .asData
                ?.value ??
            selectedMembership;
    final roleId = membership?.roleId ??
        (councilContext.isPlatformAdmin ? 'superAdmin' : 'member');
    final permissions = (councilContext.isPlatformAdmin
            ? const ['fullAccess']
            : membership?.permissionsSnapshot ?? const <String>[])
        .toSet();
    final fullAccess = councilContext.isPlatformAdmin ||
        permissions.contains('fullAccess') ||
        roleId == 'chairman' ||
        roleId == 'superAdmin';
    bool can(String permission, [String? legacyAlias]) =>
        fullAccess ||
        permissions.contains(permission) ||
        (legacyAlias != null && permissions.contains(legacyAlias));

    final organizationId = organization['organizationId'] as String;
    final authUser = ref.watch(authStateProvider).value;
    final profile = authUser == null
        ? null
        : ref.watch(userProfileProvider(authUser.uid)).asData?.value;
    final legacyMember = ref.watch(currentMemberProvider).asData?.value;
    final memberName = profile?.fullName ??
        legacyMember?.fullName ??
        authUser?.displayName ??
        '-';

    final actions = <_CouncilAction>[
      _CouncilAction(
        Icons.account_balance_outlined,
        'بيانات المجلس',
        () => _showOrganization(context, organization),
      ),
      _CouncilAction(
        Icons.card_membership_outlined,
        'حالة الاشتراك',
        () => _showMembership(context, membership),
      ),
      _CouncilAction(
        Icons.upload_file_outlined,
        'رفع إيصال',
        () => context.pushNamed(
          'uploadReceipt',
          extra: {
            'organizationId': organizationId,
            'membershipId': membership?.id,
            'userId': authUser?.uid,
            'paymentId': null,
            'periodLabel': 'إيصال دفع عام',
          },
        ),
      ),
      _CouncilAction(
        Icons.history_outlined,
        'سجل المدفوعات',
        () => context.pushNamed('receiptHistory'),
      ),
      _CouncilAction(
        Icons.campaign_outlined,
        'الإعلانات',
        () => _comingSoon(context),
      ),
      _CouncilAction(
        Icons.event_available_outlined,
        'حجز مجلس',
        () => context.pushNamed(
          'rentalPlaceholder',
          extra: CouncilBookingArguments(
            organizationId: organizationId,
            membershipId: membership?.id,
          ),
        ),
      ),
      _CouncilAction(
        Icons.support_agent_outlined,
        'تواصل معنا',
        () => _comingSoon(context),
      ),
      if (can('receipts.review'))
        _CouncilAction(
          Icons.receipt_long_outlined,
          'مراجعة الإيصالات',
          () => context.pushNamed('financialReview'),
          administrative: true,
        ),
      if (councilContext.isPlatformAdmin ||
          roleId == 'chairman' ||
          roleId == 'adminManager' ||
          permissions.contains('bookings.manage') ||
          permissions.contains('bookings.approve'))
        _CouncilAction(
          Icons.event_note_outlined,
          'طلبات حجز المجلس',
          () => context.pushNamed('bookingRequestsReview'),
          administrative: true,
        ),
      if (can('payments.approve') || can('payments.reject'))
        _CouncilAction(
          Icons.payments_outlined,
          'اعتماد المدفوعات',
          () => context.pushNamed('financialReview'),
          administrative: true,
        ),
      if (can('reports.view'))
        _CouncilAction(
          Icons.analytics_outlined,
          'التقارير المالية',
          () => _comingSoon(context),
          administrative: true,
        ),
      if (can('members.read', 'members.manage'))
        _CouncilAction(
          Icons.groups_outlined,
          'إدارة الأعضاء',
          () => context.pushNamed('memberManagement'),
          administrative: true,
        ),
      if (can('members.approve', 'membershipRequests.review'))
        _CouncilAction(
          Icons.how_to_reg_outlined,
          'طلبات الانضمام',
          () => context.pushNamed('membershipRequestsReview'),
          administrative: true,
        ),
      if (can('roles.manage'))
        _CouncilAction(
          Icons.admin_panel_settings_outlined,
          'إدارة الصلاحيات',
          () => context.pushNamed('rolesManagement'),
          administrative: true,
        ),
      if (can('notifications.send'))
        _CouncilAction(
          Icons.notifications_active_outlined,
          'إرسال إشعار',
          () => _comingSoon(context),
          administrative: true,
        ),
      if (can('organization.manage') || can('settings.manage'))
        _CouncilAction(
          Icons.settings_outlined,
          'إعدادات المجلس',
          () => _comingSoon(context),
          administrative: true,
        ),
      if (can('audit.read'))
        _CouncilAction(
          Icons.history_edu_outlined,
          'سجل العمليات',
          () => _comingSoon(context),
          administrative: true,
        ),
    ];

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_organizationName(organization)),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          actions: const [NotificationBell(color: Colors.white)],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_organizationName(organization),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _HeaderLine('العضو', memberName),
                  _HeaderLine('رقم العضو', membership?.memberNumber ?? '-'),
                  _HeaderLine(
                      'الدور', _roleName(councilContext.currentRole, roleId)),
                  _HeaderLine(
                      'الحالة',
                      membership == null
                          ? 'نشط'
                          : _statusName(membership.status)),
                  _HeaderLine(
                      'اليوم', DateFormat('yyyy/MM/dd').format(DateTime.now())),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (_, index) => _ActionCard(action: actions[index]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderLine extends StatelessWidget {
  const _HeaderLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child:
            Text('$label: $value', style: const TextStyle(color: Colors.white)),
      );
}

class _CouncilAction {
  const _CouncilAction(this.icon, this.label, this.onTap,
      {this.administrative = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool administrative;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});
  final _CouncilAction action;

  @override
  Widget build(BuildContext context) {
    final color =
        action.administrative ? AppColors.primaryDark : AppColors.primary;
    return Card(
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(action.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

void _showOrganization(
    BuildContext context, Map<String, dynamic> organization) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(_organizationName(organization)),
      content: Text((organization['description'] is Map
                  ? organization['description']['ar']
                  : organization['description'])
              ?.toString() ??
          'لا توجد بيانات إضافية'),
    ),
  );
}

void _showMembership(BuildContext context, MembershipModel? membership) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('حالة الاشتراك'),
      content: Text(membership == null
          ? 'دخول كامل للمشرف العام'
          : '${_statusName(membership.status)}\nرقم العضو: ${membership.memberNumber}'),
    ),
  );
}

void _comingSoon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('سيتم تفعيل هذه الخدمة قريبًا')),
  );
}

String _organizationName(Map<String, dynamic> organization) =>
    organization['officialNameArabic'] as String? ??
    organization['shortName'] as String? ??
    organization['organizationId'] as String? ??
    '-';

String _roleName(Map<String, dynamic>? role, String fallback) {
  if (role?['roleId'] != fallback) return fallback;
  final value = role?['roleName'];
  if (value is Map && value['ar'] is String) return value['ar'] as String;
  return fallback;
}

String _statusName(MembershipStatus status) => switch (status) {
      MembershipStatus.active => 'نشط',
      MembershipStatus.pending => 'قيد المراجعة',
      MembershipStatus.suspended => 'معلق',
      MembershipStatus.rejected => 'مرفوض',
      MembershipStatus.resigned => 'ملغى',
      MembershipStatus.removed => 'تمت الإزالة',
      MembershipStatus.cancelled => 'ملغى',
    };
