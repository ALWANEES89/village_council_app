import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../presentation/widgets/omr_amount.dart';
import '../data/audit_log_model.dart';
import '../data/audit_log_repository.dart';
import '../providers/audit_providers.dart';

typedef _OrgOption = ({String id, String name});

class AuditLogsScreen extends ConsumerStatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> {
  String? _organizationId;
  DateTime? _from;
  DateTime? _to;
  String? _actionFilter;
  String? _roleFilter;
  String? _targetTypeFilter;
  String _nameQuery = '';

  @override
  Widget build(BuildContext context) {
    final accessAsync = ref.watch(adminAccessProvider);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('سجل الأحداث'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: accessAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const _Message('تعذر التحقق من الصلاحيات'),
          data: (access) {
            if (!access.canReadAudit) {
              return const _Message('لا تملك صلاحية عرض سجل الأحداث');
            }
            final seeAll = access.isSuperAdmin || access.isLegacyAdmin;
            return _buildOrganizationScope(seeAll: seeAll);
          },
        ),
      ),
    );
  }

  Widget _buildOrganizationScope({required bool seeAll}) {
    final orgsAsync = ref.watch(organizationsProvider);
    return orgsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _Message('تعذر تحميل المجالس'),
      data: (organizations) {
        final names = <String, String>{
          for (final organization in organizations)
            organization['organizationId'] as String:
                _organizationName(organization),
        };

        if (seeAll) {
          final options = organizations
              .map<_OrgOption>((organization) => (
                    id: organization['organizationId'] as String,
                    name: _organizationName(organization),
                  ))
              .toList();
          return _buildScopedBody(options);
        }

        final uid = ref.watch(authStateProvider).valueOrNull?.uid;
        if (uid == null) {
          return const _Message('يجب تسجيل الدخول');
        }
        final membershipsAsync = ref.watch(activeUserMembershipsProvider(uid));
        return membershipsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const _Message('تعذر تحميل العضويات'),
          data: (result) {
            final ids = result.memberships
                .where(membershipCanReadAudit)
                .map((membership) => membership.organizationId)
                .toSet();
            final options = ids
                .map<_OrgOption>((id) => (id: id, name: names[id] ?? id))
                .toList();
            return _buildScopedBody(options);
          },
        );
      },
    );
  }

  Widget _buildScopedBody(List<_OrgOption> options) {
    if (options.isEmpty) {
      return const _Message('لا توجد مجالس متاحة لعرض سجلها');
    }
    final selectedId = options.any((option) => option.id == _organizationId)
        ? _organizationId!
        : options.first.id;

    final query = AuditLogQuery(
      organizationId: selectedId,
      from: _from,
      to: _to == null
          ? null
          : DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59),
    );
    final logsAsync = ref.watch(auditLogsProvider(query));

    return Column(
      children: [
        if (options.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(
                labelText: 'المجلس',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: options
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.id,
                      child: Text(option.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _organizationId = value),
            ),
          ),
        Expanded(
          child: logsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _Message(
              'تعذر تحميل سجل هذا المجلس (قد لا تملك صلاحية القراءة).\n$error',
            ),
            data: (entries) => _buildList(entries),
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<AuditLogEntry> allEntries) {
    final actions = _distinct(allEntries.map((entry) => entry.action));
    final roles = _distinct(
        allEntries.map((entry) => entry.actorRole).whereType<String>());
    final targetTypes = _distinct(
        allEntries.map((entry) => entry.targetType).whereType<String>());

    final search = _nameQuery.trim().toLowerCase();
    final entries = allEntries.where((entry) {
      if (_actionFilter != null && entry.action != _actionFilter) return false;
      if (_roleFilter != null && entry.actorRole != _roleFilter) return false;
      if (_targetTypeFilter != null && entry.targetType != _targetTypeFilter) {
        return false;
      }
      if (search.isNotEmpty) {
        final haystack = [
          entry.actorName ?? '',
          entry.actorUserId ?? '',
          entry.targetId ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(search)) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        _FilterBar(
          actions: actions,
          roles: roles,
          targetTypes: targetTypes,
          actionFilter: _actionFilter,
          roleFilter: _roleFilter,
          targetTypeFilter: _targetTypeFilter,
          from: _from,
          to: _to,
          onAction: (value) => setState(() => _actionFilter = value),
          onRole: (value) => setState(() => _roleFilter = value),
          onTargetType: (value) => setState(() => _targetTypeFilter = value),
          onName: (value) => setState(() => _nameQuery = value),
          onPickFrom: () => _pickDate(isFrom: true),
          onPickTo: () => _pickDate(isFrom: false),
          onClear: _clearFilters,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'عدد السجلات: ${entries.length}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const Spacer(),
              const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'للقراءة فقط',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const _Message('لا توجد سجلات مطابقة')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _AuditCard(entry: entries[index]),
                ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _from = null;
      _to = null;
      _actionFilter = null;
      _roleFilter = null;
      _targetTypeFilter = null;
      _nameQuery = '';
    });
  }

  static List<String> _distinct(Iterable<String> values) {
    final set = values
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return set;
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.actions,
    required this.roles,
    required this.targetTypes,
    required this.actionFilter,
    required this.roleFilter,
    required this.targetTypeFilter,
    required this.from,
    required this.to,
    required this.onAction,
    required this.onRole,
    required this.onTargetType,
    required this.onName,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClear,
  });

  final List<String> actions;
  final List<String> roles;
  final List<String> targetTypes;
  final String? actionFilter;
  final String? roleFilter;
  final String? targetTypeFilter;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String?> onAction;
  final ValueChanged<String?> onRole;
  final ValueChanged<String?> onTargetType;
  final ValueChanged<String> onName;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'بحث بالاسم / المعرّف',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onName,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterDropdown(
                label: 'العملية',
                value: actionFilter,
                items: actions,
                display: actionLabel,
                onChanged: onAction,
              ),
              _FilterDropdown(
                label: 'الدور',
                value: roleFilter,
                items: roles,
                display: roleLabel,
                onChanged: onRole,
              ),
              _FilterDropdown(
                label: 'نوع الهدف',
                value: targetTypeFilter,
                items: targetTypes,
                display: targetTypeLabel,
                onChanged: onTargetType,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    from == null ? 'من تاريخ' : dateFormat.format(from!),
                  ),
                  onPressed: onPickFrom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    to == null ? 'إلى تاريخ' : dateFormat.format(to!),
                  ),
                  onPressed: onPickTo,
                ),
              ),
              IconButton(
                tooltip: 'مسح الفلاتر',
                icon: const Icon(Icons.filter_alt_off_outlined),
                onPressed: onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> items;
  final String Function(String) display;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
          ...items.map(
            (item) => DropdownMenuItem<String?>(
              value: item,
              child: Text(display(item), overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final date = entry.createdAt == null
        ? '—'
        : DateFormat('yyyy/MM/dd - HH:mm').format(entry.createdAt!);
    final actor = entry.actorName?.trim().isNotEmpty == true
        ? entry.actorName!
        : (entry.actorUserId ?? 'غير معروف');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _actionColor(entry.action).withValues(alpha: 0.15),
          child: Icon(_actionIcon(entry.targetType),
              color: _actionColor(entry.action), size: 20),
        ),
        title: Text(
          actionLabel(entry.action),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('$actor — ${roleLabel(entry.actorRole ?? 'unknown')}'),
            Text(date,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _kv('نوع الهدف', targetTypeLabel(entry.targetType ?? '—')),
          if (entry.targetId != null) _kv('معرّف الهدف', entry.targetId!),
          if (entry.actorUserId != null)
            _kv('معرّف الفاعل', entry.actorUserId!),
          _kv('المصدر', entry.source ?? '—'),
          if (entry.platform != null) _kv('المنصّة', entry.platform!),
          const Divider(),
          _ValueBlock(title: 'القيمة السابقة', value: entry.oldValue),
          const SizedBox(height: 8),
          _ValueBlock(title: 'القيمة الجديدة', value: entry.newValue),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text('$key:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _ValueBlock extends StatelessWidget {
  const _ValueBlock({required this.title, required this.value});

  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
          const SizedBox(height: 6),
          _renderValue(value),
        ],
      ),
    );
  }

  Widget _renderValue(Object? value, {String? fieldName}) {
    if (value == null) {
      return Text('—', style: TextStyle(color: Colors.grey.shade500));
    }
    if (_isBaisaField(fieldName) && value is num) {
      return OmrAmount(amountBaisa: value.toInt());
    }
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_auditFieldLabel(entry.key.toString())}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(
                      child: _renderValue(
                        entry.value,
                        fieldName: entry.key.toString(),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: _renderValue(item, fieldName: fieldName),
                ))
            .toList(),
      );
    }
    return SelectableText(_stringify(value));
  }

  String _stringify(Object? value) {
    if (value == null) return '—';
    return value.toString();
  }

  bool _isBaisaField(String? fieldName) =>
      fieldName?.toLowerCase().endsWith('baisa') == true;

  String _auditFieldLabel(String fieldName) {
    const labels = {
      'amountBaisa': 'المبلغ',
      'amountDueBaisa': 'المبلغ المستحق',
      'amountPaidBaisa': 'المبلغ المدفوع',
      'amountDeclaredBaisa': 'المبلغ المصرح',
      'amountAllocatedBaisa': 'المبلغ الموزع',
      'allocationTotalBaisa': 'إجمالي التوزيع',
      'balanceBaisa': 'الرصيد',
      'balanceBeforeBaisa': 'الرصيد السابق',
      'balanceAfterBaisa': 'الرصيد اللاحق',
      'memberBookingFeeBaisa': 'رسم حجز العضو',
      'nonMemberBookingFeeBaisa': 'رسم حجز الضيف',
      'eventBookingFeeBaisa': 'رسم المناسبة',
    };
    if (labels.containsKey(fieldName)) return labels[fieldName]!;
    if (_isBaisaField(fieldName)) {
      return fieldName.substring(0, fieldName.length - 'Baisa'.length);
    }
    return fieldName;
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
        ),
      ),
    );
  }
}

// ── تسميات عربية ────────────────────────────────────────────────────────────

String actionLabel(String action) {
  const labels = {
    'membership.created': 'إنشاء عضوية',
    'membership.deleted': 'حذف عضوية',
    'membership.role_changed': 'تغيير دور عضو',
    'membership.status_changed': 'تغيير حالة عضوية',
    'membership.updated': 'تعديل عضوية',
    'role.created': 'إنشاء دور',
    'role.deleted': 'حذف دور',
    'role.permissions_changed': 'تغيير صلاحيات دور',
    'membership_request.submitted': 'تقديم طلب عضوية',
    'membership_request.approved': 'اعتماد طلب عضوية',
    'membership_request.rejected': 'رفض طلب عضوية',
    'membership_request.cancelled': 'إلغاء طلب عضوية',
    'membership_request.reopened': 'إعادة فتح طلب عضوية',
    'receipt.submitted': 'رفع إيصال',
    'receipt.approved': 'اعتماد إيصال',
    'receipt.rejected': 'رفض إيصال',
    'receipt.reviewed': 'مراجعة إيصال',
    'booking.created': 'إنشاء حجز',
    'booking.approved': 'اعتماد حجز',
    'booking.rejected': 'رفض حجز',
    'booking.cancelled': 'إلغاء حجز',
    'settings.created': 'إنشاء إعدادات',
    'settings.updated': 'تعديل إعدادات المجلس',
    'financial_profile.created': 'إنشاء ملف مالي',
    'financial_profile.updated': 'تعديل بيانات البنك',
    'organization.created': 'إنشاء مجلس',
    'organization.updated': 'تعديل بيانات المجلس',
    'organization.status_changed': 'تغيير حالة المجلس',
    'organization.deleted': 'حذف مجلس',
  };
  return labels[action] ?? action;
}

String roleLabel(String role) {
  const labels = {
    'chairman': 'رئيس المجلس',
    'adminManager': 'مدير إداري',
    'financialManager': 'المدير المالي',
    'financialReviewer': 'المراجع المالي',
    'secretary': 'أمين السر',
    'member': 'عضو',
    'superAdmin': 'مشرف المنصّة',
    'legacyAdmin': 'أدمن',
    'unknown': 'غير معروف',
  };
  return labels[role] ?? role;
}

String targetTypeLabel(String targetType) {
  const labels = {
    'membership': 'عضوية',
    'role': 'دور',
    'membership_request': 'طلب عضوية',
    'transaction': 'إيصال/معاملة',
    'booking': 'حجز',
    'settings': 'إعدادات',
    'financial_profile': 'ملف مالي',
    'organization': 'مجلس',
  };
  return labels[targetType] ?? targetType;
}

IconData _actionIcon(String? targetType) {
  switch (targetType) {
    case 'membership':
      return Icons.badge_outlined;
    case 'role':
      return Icons.admin_panel_settings_outlined;
    case 'membership_request':
      return Icons.how_to_reg_outlined;
    case 'transaction':
      return Icons.receipt_long_outlined;
    case 'booking':
      return Icons.event_note_outlined;
    case 'settings':
      return Icons.settings_outlined;
    case 'financial_profile':
      return Icons.account_balance_outlined;
    case 'organization':
      return Icons.account_balance;
    default:
      return Icons.history;
  }
}

Color _actionColor(String action) {
  if (action.contains('reject') || action.contains('deleted')) {
    return Colors.red;
  }
  if (action.contains('approved') || action.contains('created')) {
    return Colors.green;
  }
  if (action.contains('role') || action.contains('permissions')) {
    return Colors.deepPurple;
  }
  return AppColors.primary;
}

String _organizationName(Map<String, dynamic> organization) {
  final arabic = organization['officialNameArabic'];
  if (arabic is String && arabic.trim().isNotEmpty) return arabic;
  final shortName = organization['shortName'];
  if (shortName is String && shortName.trim().isNotEmpty) return shortName;
  return organization['organizationId'] as String? ?? '';
}
