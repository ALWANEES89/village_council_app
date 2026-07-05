import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class OrganizationsManagementScreen extends ConsumerStatefulWidget {
  const OrganizationsManagementScreen({super.key});

  @override
  ConsumerState<OrganizationsManagementScreen> createState() =>
      _OrganizationsManagementScreenState();
}

class _OrganizationsManagementScreenState
    extends ConsumerState<OrganizationsManagementScreen> {
  bool _repairing = false;

  Future<void> _repairOrganizations() async {
    if (_repairing) return;
    setState(() => _repairing = true);
    try {
      final result = await ref
          .read(organizationRepositoryProvider)
          .repairAllOrganizationStructures();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? 'تم إصلاح هيكل المجلس'
                : 'تم إصلاح جزء من الهيكل، راجع السجل',
          ),
        ),
      );
    } on FirebaseException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إصلاح جزء من الهيكل، راجع السجل')),
      );
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(adminAccessProvider);
    if (accessAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (accessAsync.asData?.value.isSuperAdmin != true) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('هذا القسم متاح للمشرف العام فقط'),
        ),
      );
    }
    final adminData = ref.watch(currentPlatformAdminProvider).asData?.value;
    final rawPreferences = adminData?['notificationPreferences'];
    final preferences = rawPreferences is Map ? rawPreferences : const {};
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إدارة المجالس'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              onPressed: () => context.pushNamed('createOrganization'),
              icon: const Icon(Icons.add_business_outlined),
            ),
          ],
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: ref
              .read(organizationRepositoryProvider)
              .streamAllIncludingInactive(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل بيانات المجالس'));
            }
            final organizations = snapshot.data ?? const [];
            if (organizations.isEmpty) {
              return const Center(child: Text('لا توجد مجالس حتى الآن'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: _repairing ? null : _repairOrganizations,
                  icon: _repairing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.build_circle_outlined),
                  label: const Text('إصلاح هيكل المجالس'),
                ),
                const SizedBox(height: 16),
                for (final organization in organizations)
                  _OrganizationAdminCard(
                    organization: organization,
                    notificationsEnabled:
                        preferences[organization['organizationId']] != false,
                  ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.pushNamed('createOrganization'),
          icon: const Icon(Icons.add),
          label: const Text('إضافة مجلس'),
        ),
      ),
    );
  }
}

class _OrganizationAdminCard extends ConsumerWidget {
  const _OrganizationAdminCard({
    required this.organization,
    required this.notificationsEnabled,
  });

  final Map<String, dynamic> organization;
  final bool notificationsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizationId = organization['organizationId'] as String;
    final active = organization['status'] == 'active';
    final createdAt = organization['createdAt'];
    final createdLabel = createdAt is Timestamp
        ? DateFormat('yyyy/MM/dd').format(createdAt.toDate())
        : '-';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.account_balance)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    organization['officialNameArabic'] as String? ??
                        organizationId,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(active ? 'نشط' : 'مؤرشف'),
                  backgroundColor:
                      active ? Colors.green.shade50 : Colors.orange.shade50,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('تاريخ الإنشاء: $createdLabel'),
            FutureBuilder<Map<String, int>>(
              future: ref
                  .read(organizationRepositoryProvider)
                  .getOrganizationCounts(organizationId),
              builder: (context, snapshot) {
                final counts = snapshot.data ?? const {};
                return Text(
                  'الأعضاء: ${counts['members'] ?? 0}  •  الطلبات: ${counts['requests'] ?? 0}',
                );
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('استلام إشعارات هذا المجلس'),
              value: notificationsEnabled,
              onChanged: (value) async {
                final user = ref.read(authServiceProvider).currentUser;
                if (user == null) return;
                await ref
                    .read(platformAdminRepositoryProvider)
                    .setOrganizationNotifications(
                      userId: user.uid,
                      organizationId: organizationId,
                      enabled: value,
                    );
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.pushNamed(
                    'createOrganization',
                    extra: organization,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(organizationRepositoryProvider)
                      .setArchived(
                        organizationId,
                        archived: active,
                        actorUserId:
                            ref.read(authServiceProvider).currentUser?.uid,
                      ),
                  icon: Icon(active ? Icons.archive_outlined : Icons.unarchive),
                  label: Text(active ? 'أرشفة' : 'إعادة التفعيل'),
                ),
                OutlinedButton.icon(
                  onPressed: active
                      ? () async {
                          await ref
                              .read(organizationContextProvider.notifier)
                              .selectOrganizationAsSuperAdmin(organizationId);
                          if (context.mounted) {
                            context.pushNamed('councilDashboard');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح لوحة المجلس'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
