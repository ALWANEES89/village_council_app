import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/role_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/membership_model.dart';
import '../../../presentation/widgets/reason_input_dialog.dart';
import '../../../providers/app_providers.dart';
import '../data/member_management_models.dart';
import '../providers/member_management_providers.dart';

class MemberDetailsScreen extends ConsumerStatefulWidget {
  const MemberDetailsScreen({
    super.key,
    required this.organizationId,
    required this.userId,
  });

  final String organizationId;
  final String userId;

  @override
  ConsumerState<MemberDetailsScreen> createState() =>
      _MemberDetailsScreenState();
}

class _MemberDetailsScreenState extends ConsumerState<MemberDetailsScreen> {
  bool _isProcessing = false;

  MemberLookup get _lookup => (
        organizationId: widget.organizationId,
        userId: widget.userId,
      );

  String? get _actorUserId => ref.read(authServiceProvider).currentUser?.uid;

  Future<bool> _run(Future<void> Function(String actorUserId) action) async {
    final actorUserId = _actorUserId;
    if (actorUserId == null || _isProcessing) return false;
    setState(() => _isProcessing = true);
    try {
      await action(actorUserId);
      ref.invalidate(managedMemberProvider(_lookup));
      ref.invalidate(memberListProvider(widget.organizationId));
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تنفيذ العملية بنجاح')),
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _activate() async {
    await _run(
      (actor) => ref.read(memberManagementRepositoryProvider).activate(
            organizationId: widget.organizationId,
            userId: widget.userId,
            actorUserId: actor,
          ),
    );
  }

  Future<void> _suspend() async {
    final reason = await _textDialog(
      title: 'تعليق العضوية',
      hint: 'سبب التعليق (اختياري)',
      actionLabel: 'تعليق',
    );
    if (reason == null) return;
    await _run(
      (actor) => ref.read(memberManagementRepositoryProvider).suspend(
            organizationId: widget.organizationId,
            userId: widget.userId,
            actorUserId: actor,
            reason: reason.isEmpty ? null : reason,
          ),
    );
  }

  Future<void> _changeRole() async {
    _logRoleChangeDiagnostics();
    final roles = await ref.read(
      organizationRolesProvider(widget.organizationId).future,
    );
    if (!mounted) return;
    final roleId = await _selectionDialog(
      title: 'تغيير الصلاحية',
      items: {
        for (final role in roles) role['roleId'] as String: _roleName(role),
      },
    );
    if (roleId == null) return;
    await _run(
      (actor) => ref.read(memberManagementRepositoryProvider).changeRole(
            organizationId: widget.organizationId,
            userId: widget.userId,
            newRoleId: roleId,
            actorUserId: actor,
          ),
    );
  }

  /// سجلّات تشخيص [RoleChange] عند بدء تغيير الصلاحية: تُظهر حالة المالك الأعلى
  /// العالمي (platform_admins) مقابل الدور المحلي، لتشخيص أي رفض صلاحية.
  void _logRoleChangeDiagnostics() {
    final access = ref.read(adminAccessProvider).valueOrNull;
    final membership =
        ref.read(managedMemberProvider(_lookup)).valueOrNull?.membership;
    final platformAdmin = ref.read(currentPlatformAdminProvider).valueOrNull;
    final writePath =
        'organizations/${widget.organizationId}/memberships/${widget.userId}';
    debugPrint('[RoleChange]\n'
        'uid=$_actorUserId\n'
        'organizationId=${widget.organizationId}\n'
        'targetMemberUid=${widget.userId}\n'
        'localRole=${membership?.role}\n'
        'localRoleId=${membership?.roleId}\n'
        'permissionsSnapshot=${access?.permissions}\n'
        'platformAdmin.exists=${platformAdmin != null}\n'
        'platformAdmin.role=${platformAdmin?['role']}\n'
        'platformAdmin.status=${platformAdmin?['status']}\n'
        'platformAdmin.fullAccess=${platformAdmin?['fullAccess']}\n'
        'isSystemOwner=${access?.isSystemOwner}\n'
        'isPlatformOwner=${access?.isPlatformOwner}\n'
        'canChangeRoles=${access?.canChangeRoles}\n'
        'writePath=$writePath');
  }

  Future<void> _transfer() async {
    final organizations = await ref.read(organizationsProvider.future);
    if (!mounted) return;
    final available = organizations.where(
      (organization) => organization['organizationId'] != widget.organizationId,
    );
    final targetId = await _selectionDialog(
      title: 'نقل العضو إلى مجلس',
      items: {
        for (final organization in available)
          organization['organizationId'] as String:
              _organizationName(organization),
      },
    );
    if (targetId == null) return;
    final transferred = await _run(
      (actor) =>
          ref.read(memberManagementRepositoryProvider).transferOrganization(
                sourceOrganizationId: widget.organizationId,
                targetOrganizationId: targetId,
                userId: widget.userId,
                actorUserId: actor,
              ),
    );
    if (transferred && mounted) context.pop();
  }

  void _editPermissions() {
    context.pushNamed(
      'memberPermissions',
      pathParameters: {'userId': widget.userId},
      queryParameters: {'organizationId': widget.organizationId},
    );
  }

  Future<void> _transferPresident() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعيين رئيساً للمجلس'),
        content: const Text(
          'سيتم تعيين هذا العضو رئيساً للمجلس، وتخفيض الرئيس الحالي إلى عضو. '
          'المالك الأساسي للنظام لا يتأثّر. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('تعيين رئيساً'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      (actor) =>
          ref.read(memberManagementRepositoryProvider).transferCouncilPresident(
                organizationId: widget.organizationId,
                newPresidentUserId: widget.userId,
                actorUserId: actor,
              ),
    );
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء العضوية'),
        content: const Text('هل أنت متأكد من إلغاء عضوية هذا العضو؟'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إلغاء العضوية'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await _run(
      (actor) => ref.read(memberManagementRepositoryProvider).remove(
            organizationId: widget.organizationId,
            userId: widget.userId,
            actorUserId: actor,
          ),
    );
    if (removed && mounted) context.pop();
  }

  Future<String?> _textDialog({
    required String title,
    required String hint,
    required String actionLabel,
  }) {
    // حوار آمن يملك الـ controller في State خاص به (يمنع crash
    // "TextEditingController used after disposed" / `_dependents.isEmpty`).
    return showReasonDialog(
      context: context,
      title: title,
      hint: hint,
      actionLabel: actionLabel,
    );
  }

  Future<String?> _selectionDialog({
    required String title,
    required Map<String, String> items,
  }) {
    if (items.isEmpty) return Future.value(null);
    String? selected;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: items.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) => setDialogState(() => selected = value),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: selected == null ? null : () => context.pop(selected),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(managedMemberProvider(_lookup));
    final history = ref.watch(memberHistoryProvider(widget.userId));
    // تغيير الدور عملية إسناد صلاحيات: تُعرض فقط لمن يملك roles.manage
    // (أو fullAccess/المالك). Firestore Rules تفرض القيد نفسه.
    final access = ref.watch(adminAccessProvider).valueOrNull;
    final canManageRoles = access?.canManageRoles ?? false;
    // سجلّات تطوير مؤقتة (debug فقط) لتشخيص ظهور أزرار الإدارة.
    assert(() {
      final m = member.valueOrNull?.membership;
      debugPrint('[Access] uid=${ref.read(authServiceProvider).currentUser?.uid} '
          'org=${widget.organizationId} target=${widget.userId}');
      debugPrint('[Access] role=${m?.role} roleId=${m?.roleId} '
          'status=${m?.status.name} isPrimaryOwner=${m?.isPrimaryOwner} '
          'perms=${m?.permissionsSnapshot}');
      debugPrint('[Access] isSuperAdmin=${access?.isSuperAdmin} '
          'isSystemOwner=${access?.isSystemOwner} '
          'canManageMembers=${access?.canManageMembers} '
          'canChangeRoles=${access?.canChangeRoles} '
          'canTransferCouncilManager=${access?.canTransferCouncilManager} '
          'goldenPanel=${access?.canAccessGoldenAdminPanel}');
      return true;
    }());

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('تفاصيل العضو'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: member.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (value) {
            if (value == null) {
              return const Center(child: Text('العضوية غير موجودة'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (value.membership.isOwnerMembership) const _OwnerBanner(),
                _DetailsSection(
                  title: 'المعلومات الشخصية',
                  rows: {
                    'الاسم': value.fullName,
                    'الرقم المدني': value.civilId,
                    'الهاتف': value.phone,
                    'البريد الإلكتروني': value.email,
                    'العنوان': value.address,
                  },
                ),
                _DetailsSection(
                  title: 'معلومات العضوية',
                  rows: {
                    'رقم العضو': value.membership.memberNumber,
                    'الدور': effectiveRoleLabelArabic(
                      value.membership.roleId,
                      role: value.membership.role,
                      fallback: value.roleName,
                      permissions: value.membership.permissionsSnapshot,
                    ),
                    'الحالة': _statusLabel(value.membership.status),
                    'تاريخ الانضمام': DateFormat('yyyy/MM/dd')
                        .format(value.membership.joinedAt),
                  },
                ),
                _AdminActions(
                  status: value.membership.status,
                  isProcessing: _isProcessing,
                  canManageRoles: canManageRoles,
                  onActivate: _activate,
                  onSuspend: _suspend,
                  onChangeRole: _changeRole,
                  onEditPermissions: _editPermissions,
                  onTransfer: _transfer,
                  onTransferPresident: _transferPresident,
                  onRemove: _remove,
                ),
                const SizedBox(height: 16),
                const Text(
                  'سجل العضو',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                history.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعذر تحميل سجل العضو، قد تحتاج البيانات إلى تجهيز',
                        style: TextStyle(color: Colors.orange),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(
                          memberHistoryProvider(widget.userId),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                  data: (events) => events.isEmpty
                      ? const Text('لا يوجد سجل حتى الآن')
                      : Column(
                          children: events
                              .map((event) => _HistoryTile(event: event))
                              .toList(),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            for (final row in rows.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${row.key}:',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(child: SelectableText(row.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminActions extends StatelessWidget {
  const _AdminActions({
    required this.status,
    required this.isProcessing,
    required this.canManageRoles,
    required this.onActivate,
    required this.onSuspend,
    required this.onChangeRole,
    required this.onEditPermissions,
    required this.onTransfer,
    required this.onTransferPresident,
    required this.onRemove,
  });

  final MembershipStatus status;
  final bool isProcessing;
  final bool canManageRoles;
  final VoidCallback onActivate;
  final VoidCallback onSuspend;
  final VoidCallback onChangeRole;
  final VoidCallback onEditPermissions;
  final VoidCallback onTransfer;
  final VoidCallback onTransferPresident;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إجراءات الإدارة',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (isProcessing)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status != MembershipStatus.active)
                    FilledButton.icon(
                      onPressed: onActivate,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('تفعيل'),
                    ),
                  if (status != MembershipStatus.suspended)
                    OutlinedButton.icon(
                      onPressed: onSuspend,
                      icon: const Icon(Icons.block),
                      label: const Text('تعليق العضوية'),
                    ),
                  if (canManageRoles)
                    OutlinedButton.icon(
                      onPressed: onChangeRole,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('تغيير الصلاحية'),
                    ),
                  if (canManageRoles)
                    OutlinedButton.icon(
                      onPressed: onEditPermissions,
                      icon: const Icon(Icons.tune),
                      label: const Text('تعديل الصلاحيات المخصّصة'),
                    ),
                  if (canManageRoles && status == MembershipStatus.active)
                    OutlinedButton.icon(
                      onPressed: onTransferPresident,
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('تعيين رئيساً للمجلس'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onTransfer,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('نقل المجلس'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.person_remove),
                    label: const Text('إلغاء العضوية'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.event});

  final MemberHistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final date = event.createdAt == null
        ? '-'
        : DateFormat('yyyy/MM/dd - HH:mm').format(event.createdAt!);
    return Card(
      child: ListTile(
        leading: Icon(_historyIcon(event.type), color: AppColors.primary),
        title: Text(_historyTitle(event)),
        subtitle: Text(
          [date, if (event.reason?.isNotEmpty == true) event.reason!]
              .join('\n'),
        ),
      ),
    );
  }
}

String _historyTitle(MemberHistoryEvent event) {
  return switch (event.type) {
    MemberHistoryType.status =>
      'تغيير الحالة: ${event.previousStatus ?? '-'} ← ${event.newStatus ?? '-'}',
    MemberHistoryType.role =>
      'تغيير الدور: ${event.previousRoleId ?? '-'} ← ${event.newRoleId ?? '-'}',
    MemberHistoryType.organization =>
      'نقل المجلس: ${event.organizationId ?? '-'} ← ${event.targetOrganizationId ?? '-'}',
    MemberHistoryType.removed => 'إزالة العضو من المجلس',
  };
}

IconData _historyIcon(MemberHistoryType type) {
  return switch (type) {
    MemberHistoryType.status => Icons.toggle_on_outlined,
    MemberHistoryType.role => Icons.admin_panel_settings_outlined,
    MemberHistoryType.organization => Icons.swap_horiz,
    MemberHistoryType.removed => Icons.person_remove_outlined,
  };
}

class _OwnerBanner extends StatelessWidget {
  const _OwnerBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: Colors.cyan.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.cyan.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.verified_user, color: Colors.cyan.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'المالك الأعلى للنظام — محميّ ولا يمكن تعديله أو حذفه.',
                style: TextStyle(
                  color: Colors.cyan.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('permission-denied') || text.contains('unauthorized')) {
    return 'ليست لديك صلاحية لتنفيذ هذا الإجراء.';
  }
  if (text.contains('primary owner')) {
    return 'لا يمكن تعديل المالك الأساسي للنظام.';
  }
  if (text.contains('active member')) {
    return 'يجب أن يكون العضو نشطاً لتعيينه رئيساً.';
  }
  if (text.contains('does not exist')) {
    return 'العنصر المطلوب غير موجود.';
  }
  return 'تعذر تنفيذ العملية. حاول مرة أخرى.';
}

String _statusLabel(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.active => 'نشط',
    MembershipStatus.pending => 'قيد المراجعة',
    MembershipStatus.suspended => 'موقوف',
    MembershipStatus.rejected => 'مرفوض',
    MembershipStatus.resigned => 'منسحب',
    MembershipStatus.removed => 'تمت الإزالة',
    MembershipStatus.cancelled => 'ملغى',
  };
}

String _roleName(Map<String, dynamic> role) {
  final value = role['roleName'];
  if (value is Map && value['ar'] is String) return value['ar'] as String;
  if (value is String) return value;
  return role['roleId'] as String? ?? '';
}

String _organizationName(Map<String, dynamic> organization) {
  final arabic = organization['officialNameArabic'];
  if (arabic is String && arabic.isNotEmpty) return arabic;
  final shortName = organization['shortName'];
  if (shortName is String && shortName.isNotEmpty) return shortName;
  return organization['organizationId'] as String? ?? '';
}
