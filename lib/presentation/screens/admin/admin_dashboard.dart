import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/transaction_model.dart';
import '../../../data/models/organization_model.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/omr_amount.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(adminAccessProvider);
    if (accessAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final access = accessAsync.asData?.value;
    // سجلّات تطوير مؤقتة (debug فقط) لتشخيص ظهور اللوحة الذهبية.
    assert(() {
      debugPrint('[Access] goldenPanel org='
          '${ref.read(organizationContextProvider).currentOrganization?['organizationId']} '
          'isSuperAdmin=${access?.isSuperAdmin} isSystemOwner=${access?.isSystemOwner} '
          'roleId=${access?.roleId} role=${access?.role} status=${access?.status} '
          'canAccessGoldenAdminPanel=${access?.canAccessGoldenAdminPanel} '
          'canManageMembers=${access?.canManageMembers} '
          'canChangeRoles=${access?.canChangeRoles}');
      return true;
    }());
    if (access?.canOpenAdmin != true) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لا تملك صلاحية دخول لوحة التحكم')),
      );
    }
    final currentOrganization =
        ref.watch(organizationContextProvider).currentOrganization;
    final organizationContext = ref.watch(organizationContextProvider);
    final organizationId = currentOrganization?['organizationId'] as String?;
    final roleId = organizationContext.currentRole?['roleId'] as String? ??
        organizationContext.currentMembership?.roleId;
    final canReviewReceipts = access?.isSuperAdmin == true ||
        access?.canReviewReceipts == true ||
        const ['chairman', 'financialManager', 'financialReviewer']
            .contains(roleId);
    final membershipPermissions =
        organizationContext.currentMembership?.permissionsSnapshot ?? const [];
    final canReviewBookings = access?.isSuperAdmin == true ||
        roleId == 'chairman' ||
        membershipPermissions.contains('bookings.manage') ||
        membershipPermissions.contains('bookings.approve');
    final pendingReceipts = organizationId == null
        ? null
        : ref.watch(pendingFinancialReceiptsProvider(organizationId));
    final organizationName = _organizationName(currentOrganization);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 90,
              floating: true,
              pinned: true,
              backgroundColor: AppColors.primaryDark,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(organizationName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                background: Container(
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight))),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              actions: [
                const NotificationBell(color: Colors.white),
                if (access?.isSuperAdmin == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.workspace_premium, color: Colors.amber),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () {
                    if (organizationId != null) {
                      ref.invalidate(
                        pendingFinancialReceiptsProvider(organizationId),
                      );
                    }
                  },
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المجلس الحالي: $organizationName',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (access?.isSuperAdmin == true) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber.shade700),
                        ),
                        child: Text(
                          'Super Admin',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (access?.canReviewRequests == true)
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.how_to_reg),
                          ),
                          title: const Text(
                            'طلبات الانضمام',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('مراجعة واعتماد طلبات العضوية'),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 18),
                          onTap: () =>
                              context.pushNamed('membershipRequestsReview'),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (access?.canManageMembers == true)
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.groups),
                          ),
                          title: const Text(
                            'إدارة الأعضاء',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle:
                              const Text('البحث والتصفية وإدارة العضويات'),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 18),
                          onTap: () => context.pushNamed('memberManagement'),
                        ),
                      ),
                    if (canReviewBookings && organizationId != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.event_note_outlined),
                          ),
                          title: const Text(
                            'طلبات حجز المجلس',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('مراجعة واعتماد طلبات الحجز'),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 18),
                          onTap: () =>
                              context.pushNamed('bookingRequestsReview'),
                        ),
                      ),
                    ],
                    if (canReviewReceipts && organizationId != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.receipt_long_outlined),
                          ),
                          title: const Text(
                            'مراجعة الإيصالات',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('الإيصالات قيد الاعتماد'),
                          trailing: pendingReceipts?.when(
                            data: (items) => Badge(
                              label: Text('${items.length}'),
                              child: const Icon(Icons.arrow_forward_ios),
                            ),
                            loading: () => const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            error: (_, __) =>
                                const Icon(Icons.arrow_forward_ios),
                          ),
                          onTap: () => context.pushNamed('financialReview'),
                        ),
                      ),
                    ],
                    if (access?.canManageFinance == true &&
                        organizationId != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.account_balance_wallet_outlined),
                          ),
                          title: const Text(
                            'إدارة الرسوم والاشتراكات',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'إعدادات الرسوم والباقات وحسابات الأعضاء',
                          ),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 18),
                          onTap: () => context.pushNamed('financialManagement'),
                        ),
                      ),
                    ],
                    if (access?.isSuperAdmin == true) ...[
                      const SizedBox(height: 10),
                      _AdminActionCard(
                        icon: Icons.add_business_outlined,
                        title: 'إضافة مجلس',
                        subtitle: 'إنشاء مجلس جديد وإعداد صلاحياته',
                        onTap: () => context.pushNamed('createOrganization'),
                        gold: true,
                      ),
                      const SizedBox(height: 10),
                      _AdminActionCard(
                        icon: Icons.account_balance_outlined,
                        title: 'إدارة المجالس',
                        subtitle: 'تعديل المجالس وتفعيلها أو تعليقها',
                        onTap: () =>
                            context.pushNamed('organizationsManagement'),
                        gold: true,
                      ),
                    ],
                    if (access?.canManageRoles == true) ...[
                      const SizedBox(height: 10),
                      _AdminActionCard(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'إدارة الصلاحيات',
                        subtitle: 'إدارة أدوار وصلاحيات المجلس',
                        onTap: () => context.pushNamed('rolesManagement'),
                        gold: access?.isSuperAdmin == true,
                      ),
                    ],
                    if (access?.canReadAudit == true) ...[
                      const SizedBox(height: 10),
                      _AdminActionCard(
                        icon: Icons.history,
                        title: 'سجل الأحداث',
                        subtitle: 'عرض سجل العمليات الحساسة (للقراءة فقط)',
                        onTap: () => context.pushNamed('auditLogs'),
                        gold: access?.isSuperAdmin == true,
                      ),
                    ],
                    if (access?.isSuperAdmin == true) ...[
                      const SizedBox(height: 10),
                      _AdminActionCard(
                        icon: Icons.settings_outlined,
                        title: 'الإعدادات',
                        subtitle: 'إعدادات المجلس والمنصة',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('قسم الإعدادات قيد التجهيز')),
                        ),
                        gold: true,
                      ),
                      const SizedBox(height: 10),
                      _AdminActionCard(
                        icon: Icons.analytics_outlined,
                        title: 'التقارير',
                        subtitle: 'عرض لوحات المؤشرات والتقارير',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('قسم التقارير قيد التجهيز')),
                        ),
                        gold: true,
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCards extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsCards({required this.stats});

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM', 'ar').format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('إحصائيات $monthName',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'المبالغ المحصلة',
                amountBaisa: stats['totalCollectedBaisa'] as int? ?? 0,
                icon: Icons.monetization_on,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'الأعضاء الملتزمون',
                value: '${stats['committedCount']}/${stats['totalMembers']}',
                icon: Icons.check_circle,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _StatCard(
          label: 'الأعضاء المتأخرون هذا الشهر',
          value: '${stats['lateCount']} عضو',
          icon: Icons.warning_amber,
          color: Colors.red,
          fullWidth: true,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String? value;
  final int? amountBaisa;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  const _StatCard({
    required this.label,
    this.value,
    this.amountBaisa,
    required this.icon,
    required this.color,
    this.fullWidth = false,
  }) : assert(value != null || amountBaisa != null);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 4),
                if (amountBaisa != null)
                  OmrAmount(
                    amountBaisa: amountBaisa!,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  )
                else
                  Text(value!,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final TransactionModel tx;
  const _PendingCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.pushNamed(
          'adminReview',
          pathParameters: {'id': tx.id},
          queryParameters: {
            if (tx.organizationId.isNotEmpty)
              'organizationId': tx.organizationId,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long,
                    color: Colors.orange, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.memberName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      'تاريخ الإرسال: ${DateFormat('yyyy/MM/dd - HH:mm').format(tx.submittedAt)}',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('مراجعة',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPending extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('لا توجد طلبات قيد المراجعة',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

String _organizationName(Map<String, dynamic>? organization) {
  final name = organization?['officialNameArabic'];
  if (name is String && name.trim().isNotEmpty) return name;
  return OrganizationModel.production.officialNameArabic;
}

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) {
    return const Center(
        child: CircularProgressIndicator(color: AppColors.primary));
  }
}

class _AdminActionCard extends StatelessWidget {
  const _AdminActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.gold = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final color = gold ? Colors.amber.shade800 : AppColors.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
        onTap: onTap,
      ),
    );
  }
}
