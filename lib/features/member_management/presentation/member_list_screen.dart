import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/role_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/membership_model.dart';
import '../../../providers/app_providers.dart';
import '../data/member_management_models.dart';
import '../providers/member_management_providers.dart';

class MemberListScreen extends ConsumerStatefulWidget {
  const MemberListScreen({super.key});

  @override
  ConsumerState<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends ConsumerState<MemberListScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organizationId =
        organizationContext.currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).asData?.value;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إدارة الأعضاء'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: organizationId == null || access?.canManageMembers != true
            ? const _OrganizationRequired()
            : _buildMemberList(organizationId),
      ),
    );
  }

  Widget _buildMemberList(String organizationId) {
    final state = ref.watch(memberListProvider(organizationId));
    final controller = ref.read(memberListProvider(organizationId).notifier);
    final roles = ref.watch(organizationRolesProvider(organizationId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'بحث بالاسم أو الرقم المدني أو الهاتف',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 350),
                    () => controller.setSearch(value),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  DropdownButton<MembershipStatus?>(
                    value: state.filter.status,
                    hint: const Text('كل الحالات'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل الحالات'),
                      ),
                      for (final status in MembershipStatus.values)
                        DropdownMenuItem(
                          value: status,
                          child: Text(_statusLabel(status)),
                        ),
                    ],
                    onChanged: controller.setStatus,
                  ),
                  roles.when(
                    loading: () => const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (_, __) => const SizedBox(),
                    data: (items) => DropdownButton<String?>(
                      value: state.filter.roleId,
                      hint: const Text('كل الأدوار'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('كل الأدوار'),
                        ),
                        for (final role in items)
                          DropdownMenuItem(
                            value: role['roleId'] as String,
                            child: Text(_roleName(role)),
                          ),
                      ],
                      onChanged: controller.setRole,
                    ),
                  ),
                  PopupMenuButton<(MemberSortField, bool)>(
                    tooltip: 'ترتيب',
                    icon: const Icon(Icons.sort),
                    onSelected: (value) => controller.setSort(
                      value.$1,
                      descending: value.$2,
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: (MemberSortField.joinedAt, true),
                        child: Text('الأحدث انضماماً'),
                      ),
                      PopupMenuItem(
                        value: (MemberSortField.joinedAt, false),
                        child: Text('الأقدم انضماماً'),
                      ),
                      PopupMenuItem(
                        value: (MemberSortField.memberNumber, false),
                        child: Text('رقم العضو'),
                      ),
                      PopupMenuItem(
                        value: (MemberSortField.status, false),
                        child: Text('الحالة'),
                      ),
                      PopupMenuItem(
                        value: (MemberSortField.role, false),
                        child: Text('الدور'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: controller.load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _MemberResults(
            state: state,
            organizationId: organizationId,
            onLoadMore: controller.loadMore,
            onRetry: controller.load,
          ),
        ),
      ],
    );
  }
}

class _MemberResults extends StatelessWidget {
  const _MemberResults({
    required this.state,
    required this.organizationId,
    required this.onLoadMore,
    required this.onRetry,
  });

  final MemberListState state;
  final String organizationId;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (state.error != null && state.members.isEmpty) {
      return _ErrorView(message: state.error!, onRetry: onRetry);
    }
    if (state.members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد نتائج في الصفحة الحالية'),
            if (state.hasMore) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: state.isLoadingMore ? null : onLoadMore,
                child: state.isLoadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('متابعة البحث'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: state.members.length + 1,
      itemBuilder: (context, index) {
        if (index == state.members.length) {
          if (!state.hasMore) return const SizedBox(height: 16);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OutlinedButton(
              onPressed: state.isLoadingMore ? null : onLoadMore,
              child: state.isLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تحميل المزيد'),
            ),
          );
        }

        final member = state.members[index];
        final isOwner = member.membership.isOwnerMembership;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isOwner ? Colors.cyan.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  (isOwner ? Colors.cyan : AppColors.primary)
                      .withValues(alpha: 0.12),
              child: Icon(
                isOwner ? Icons.verified_user : Icons.person,
                color: isOwner ? Colors.cyan.shade700 : AppColors.primary,
              ),
            ),
            title: Text(
              member.fullName.isEmpty ? member.userId : member.fullName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isOwner ? Colors.cyan.shade900 : null,
              ),
            ),
            subtitle: Text(
              '${member.membership.memberNumber} • '
              '${effectiveRoleLabelArabic(
                member.membership.roleId,
                role: member.membership.role,
                fallback: member.roleName,
                permissions: member.membership.permissionsSnapshot,
              )}',
            ),
            trailing: _StatusBadge(status: member.membership.status),
            onTap: () => context.pushNamed(
              'memberDetails',
              pathParameters: {'userId': member.userId},
              queryParameters: {'organizationId': organizationId},
            ),
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MembershipStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MembershipStatus.active => Colors.green,
      MembershipStatus.pending => Colors.orange,
      MembershipStatus.suspended => Colors.red,
      MembershipStatus.rejected => Colors.red,
      MembershipStatus.resigned => Colors.grey,
      MembershipStatus.removed => Colors.grey,
      MembershipStatus.cancelled => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(_statusLabel(status), style: TextStyle(color: color)),
    );
  }
}

class _OrganizationRequired extends StatelessWidget {
  const _OrganizationRequired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        onPressed: () => context.pushNamed('organizationSelector'),
        child: const Text('اختيار المجلس'),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
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
