import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../providers/member_management_providers.dart';

/// خيار دور معروض في المحرّر → roleId المستخدم فعليًّا في النظام.
const _roleOptions = <String, String>{
  'member': 'عضو',
  'adminManager': 'مدير إداري',
  'chairman': 'رئيس المجلس',
};

/// الصلاحيات المعروضة = المفاتيح التي تفرضها Firestore Rules فعليًّا (dotted)،
/// حتى يكون منح الصلاحية فعّالاً وليس مجرد عرض.
const _permissionCatalog = <String, String>{
  'members.read': 'قراءة الأعضاء',
  'members.manage': 'إدارة الأعضاء',
  'membershipRequests.review': 'مراجعة طلبات العضوية',
  'roles.manage': 'تغيير الأدوار والصلاحيات',
  'receipts.review': 'مراجعة الإيصالات',
  'payments.approve': 'اعتماد المدفوعات',
  'payments.reject': 'رفض المدفوعات',
  'bookings.approve': 'اعتماد الحجوزات',
  'bookings.manage': 'إدارة الحجوزات',
  'settings.manage': 'إدارة إعدادات المجلس',
  'organization.manage': 'إدارة المجلس',
  'audit.read': 'عرض سجل الأحداث',
  'notifications.send': 'إرسال الإشعارات',
};

class MemberPermissionsScreen extends ConsumerStatefulWidget {
  const MemberPermissionsScreen({
    super.key,
    required this.organizationId,
    required this.userId,
  });

  final String organizationId;
  final String userId;

  @override
  ConsumerState<MemberPermissionsScreen> createState() =>
      _MemberPermissionsScreenState();
}

class _MemberPermissionsScreenState
    extends ConsumerState<MemberPermissionsScreen> {
  String? _roleId;
  final Set<String> _permissions = {};
  bool _initialized = false;
  bool _saving = false;

  MemberLookup get _lookup =>
      (organizationId: widget.organizationId, userId: widget.userId);

  Future<void> _save() async {
    final actor = ref.read(authServiceProvider).currentUser?.uid;
    final roleId = _roleId;
    if (actor == null || roleId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(memberManagementRepositoryProvider).updateMemberPermissions(
            organizationId: widget.organizationId,
            userId: widget.userId,
            newRoleId: roleId,
            permissions: _permissions.toList(),
            actorUserId: actor,
          );
      ref.invalidate(managedMemberProvider(_lookup));
      ref.invalidate(memberListProvider(widget.organizationId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الصلاحيات')),
      );
      context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(managedMemberProvider(_lookup));
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('تعديل صلاحيات العضو'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: member.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(_friendlyError(error))),
          data: (value) {
            if (value == null) {
              return const Center(child: Text('العضوية غير موجودة'));
            }
            if (value.membership.isOwnerMembership) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'هذا هو المالك الأساسي للنظام ولا يمكن تعديل صلاحياته من التطبيق.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!_initialized) {
              _initialized = true;
              final currentRole = value.membership.roleId;
              _roleId = _roleOptions.containsKey(currentRole)
                  ? currentRole
                  : 'member';
              _permissions
                ..clear()
                ..addAll(value.membership.permissionsSnapshot
                    .where(_permissionCatalog.containsKey));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  value.fullName.isEmpty ? value.userId : value.fullName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text('الدور',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _roleId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _roleOptions.entries
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _roleId = value),
                ),
                const SizedBox(height: 20),
                const Text('الصلاحيات المخصّصة',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'صلاحية system_owner لا تُمنح من التطبيق (Console فقط).',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: _permissionCatalog.entries.map((entry) {
                      return CheckboxListTile(
                        dense: true,
                        title: Text(entry.value),
                        subtitle: Text(entry.key,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11)),
                        value: _permissions.contains(entry.key),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _permissions.add(entry.key);
                          } else {
                            _permissions.remove(entry.key);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: const Text('حفظ الصلاحيات'),
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

String _friendlyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('permission-denied') || text.contains('unauthorized')) {
    return 'ليست لديك صلاحية لتنفيذ هذا الإجراء.';
  }
  if (text.contains('primary owner')) {
    return 'لا يمكن تعديل المالك الأساسي للنظام.';
  }
  if (text.contains('system_owner')) {
    return 'لا يمكن إسناد دور المالك الأعلى من التطبيق.';
  }
  return 'تعذر تنفيذ العملية. حاول مرة أخرى.';
}
