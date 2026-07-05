import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class RolesManagementScreen extends ConsumerStatefulWidget {
  const RolesManagementScreen({super.key});

  @override
  ConsumerState<RolesManagementScreen> createState() =>
      _RolesManagementScreenState();
}

class _RolesManagementScreenState extends ConsumerState<RolesManagementScreen> {
  String? _organizationId;

  Future<void> _editRole(Map<String, dynamic> role) async {
    final organizationId = _organizationId;
    if (organizationId == null) return;
    final controller = TextEditingController(
      text: List<String>.from(role['permissions'] as List? ?? const [])
          .join(', '),
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('صلاحيات ${_roleName(role)}'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          textDirection: ui.TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'الصلاحيات مفصولة بفاصلة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (save != true) {
      controller.dispose();
      return;
    }
    final permissions = controller.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    controller.dispose();
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
    final organizations = ref.watch(organizationsProvider);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إدارة الصلاحيات'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: organizations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('تعذر تحميل المجالس')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('لا توجد مجالس متاحة'));
            }
            _organizationId ??= items.first['organizationId'] as String;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: _organizationId,
                    decoration: const InputDecoration(labelText: 'المجلس'),
                    items: items
                        .map(
                          (organization) => DropdownMenuItem(
                            value: organization['organizationId'] as String,
                            child: Text(
                              organization['officialNameArabic'] as String? ??
                                  organization['organizationId'] as String,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _organizationId = value),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ref
                        .read(roleRepositoryProvider)
                        .streamAll(_organizationId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
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
            );
          },
        ),
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
