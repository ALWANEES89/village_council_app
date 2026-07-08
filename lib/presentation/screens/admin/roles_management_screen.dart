import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

/// كتالوج كل الصلاحيات القابلة للمنح مع أسمائها العربية — تُعرض كقائمة اختيار
/// عند تعديل صلاحيات دور. المفاتيح هي نفسها التي تفرضها Firestore Rules.
const _permissionsCatalog = <String, String>{
  'fullAccess': 'صلاحية كاملة (كل شيء)',
  'members.read': 'قراءة الأعضاء',
  'members.manage': 'إدارة الأعضاء',
  'members.approve': 'اعتماد الأعضاء',
  'membershipRequests.review': 'مراجعة طلبات الانضمام',
  'roles.manage': 'إدارة الأدوار والصلاحيات',
  'organization.manage': 'إدارة المجلس',
  'settings.manage': 'إدارة إعدادات المجلس',
  'receipts.review': 'مراجعة الإيصالات',
  'payments.read': 'قراءة المدفوعات',
  'payments.manage': 'إدارة المدفوعات',
  'payments.approve': 'اعتماد المدفوعات',
  'payments.reject': 'رفض المدفوعات',
  'transactions.review': 'مراجعة المعاملات',
  'reports.view': 'عرض التقارير المالية',
  'bookings.read': 'قراءة الحجوزات',
  'bookings.create': 'إنشاء حجز',
  'bookings.approve': 'اعتماد الحجوزات',
  'bookings.reject': 'رفض الحجوزات',
  'bookings.manage': 'إدارة الحجوزات',
  'announcements.manage': 'إدارة الإعلانات',
  'notifications.send': 'إرسال الإشعارات',
  'audit.read': 'عرض سجل الأحداث',
  'profile.read': 'قراءة الملف الشخصي',
  'rentals.create': 'إنشاء طلب إيجار',
};

class RolesManagementScreen extends ConsumerStatefulWidget {
  const RolesManagementScreen({super.key});

  @override
  ConsumerState<RolesManagementScreen> createState() =>
      _RolesManagementScreenState();
}

class _RolesManagementScreenState extends ConsumerState<RolesManagementScreen> {
  /// المجلس الحالي المعروض (يُحسب كل build ويستخدمه _editRole عند الحفظ).
  String? _organizationId;

  Future<void> _editRole(Map<String, dynamic> role) async {
    final organizationId = _organizationId;
    if (organizationId == null) return;
    // قائمة اختيار بكل الصلاحيات؛ المحدَّد منها = صلاحيات هذا الدور.
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _RolePermissionsDialog(
        roleName: _roleName(role),
        initialPermissions:
            List<String>.from(role['permissions'] as List? ?? const []),
      ),
    );
    if (result == null) return;
    final permissions = result;
    try {
      await ref.read(roleRepositoryProvider).update(
        organizationId: organizationId,
        roleId: role['roleId'] as String,
        data: {'permissions': permissions},
        actorUserId: ref.read(authServiceProvider).currentUser?.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث الصلاحيات')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('غير مصرح بتعديل هذه الصلاحيات')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // لا قائمة منسدلة: الشاشة تعرض أدوار المجلس الحالي فقط الذي دخل منه المستخدم.
    final currentOrganization =
        ref.watch(organizationContextProvider).currentOrganization;
    final organizationId = currentOrganization?['organizationId'] as String?;
    final organizationName =
        currentOrganization?['officialNameArabic'] as String?;
    _organizationId = organizationId;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إدارة الصلاحيات'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: organizationId == null
            ? const Center(child: Text('لم يتم اختيار مجلس'))
            : Column(
                children: [
                  // اسم المجلس الحالي (عرض فقط بدل القائمة المنسدلة).
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_outlined,
                            color: AppColors.primary),
                        title: const Text('المجلس'),
                        subtitle: Text(
                          organizationName ?? organizationId,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: ref
                          .read(roleRepositoryProvider)
                          .streamAll(organizationId),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final role = snapshot.data![index];
                            final permissions = List<String>.from(
                              role['permissions'] as List? ?? const [],
                            );
                            return Card(
                              child: ListTile(
                                title: Text(_roleName(role)),
                                subtitle: Text(
                                  permissions.isEmpty
                                      ? 'لا توجد صلاحيات'
                                      : permissions.join(' • '),
                                ),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => _editRole(role),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// نافذة تعديل صلاحيات دور — قائمة اختيار (Checkbox) بكل الصلاحيات، المحدَّد
/// منها هو صلاحيات الدور. تُرجِع قائمة المفاتيح المحدَّدة عند الحفظ.
class _RolePermissionsDialog extends StatefulWidget {
  const _RolePermissionsDialog({
    required this.roleName,
    required this.initialPermissions,
  });

  final String roleName;
  final List<String> initialPermissions;

  @override
  State<_RolePermissionsDialog> createState() => _RolePermissionsDialogState();
}

class _RolePermissionsDialogState extends State<_RolePermissionsDialog> {
  late final Set<String> _selected = {...widget.initialPermissions};

  @override
  Widget build(BuildContext context) {
    // كل صلاحيات الكتالوج + أي صلاحية موجودة في الدور وغير مُدرَجة (تحسبًا).
    final keys = <String>{
      ..._permissionsCatalog.keys,
      ...widget.initialPermissions,
    }.toList();
    final fullAccess = _selected.contains('fullAccess');
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Text('صلاحيات ${widget.roleName}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: keys.map((key) {
              // «صلاحية كاملة» تُلغي الحاجة لبقية الصلاحيات (تعطيلها بصريًّا).
              final isFull = key == 'fullAccess';
              final disabled = fullAccess && !isFull;
              return CheckboxListTile(
                dense: true,
                value: _selected.contains(key),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_permissionsCatalog[key] ?? key),
                subtitle: Text(
                  key,
                  textDirection: ui.TextDirection.ltr,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
                onChanged: disabled
                    ? null
                    : (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(key);
                          } else {
                            _selected.remove(key);
                          }
                        }),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected.toList()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

String _roleName(Map<String, dynamic> role) {
  final arabic = role['arabicName'];
  if (arabic is String && arabic.isNotEmpty) return arabic;
  final name = role['roleName'];
  if (name is Map && name['ar'] is String) return name['ar'] as String;
  return role['roleId'] as String? ?? '';
}
