import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/membership_request/data/membership_request_model.dart';
import '../../../features/membership_request/providers/membership_request_providers.dart';
import '../../../features/member_management/providers/member_management_providers.dart';
import '../../../providers/app_providers.dart';

class MembershipRequestsReviewScreen extends ConsumerStatefulWidget {
  const MembershipRequestsReviewScreen({super.key});

  @override
  ConsumerState<MembershipRequestsReviewScreen> createState() =>
      _MembershipRequestsReviewScreenState();
}

class _MembershipRequestsReviewScreenState
    extends ConsumerState<MembershipRequestsReviewScreen> {
  String? _processingRequestId;

  Future<void> _approve({
    required MembershipRequestModel request,
    required String reviewedBy,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اعتماد طلب الانضمام'),
        content: Text('هل تريد اعتماد طلب ${request.fullName}؟'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _processingRequestId = request.requestId);
    try {
      await ref.read(membershipRequestRepositoryProvider).approve(
            organizationId: request.organizationId,
            requestId: request.requestId,
            reviewedBy: reviewedBy,
          );
      ref.invalidate(
        pendingMembershipRequestsProvider(request.organizationId),
      );
      ref.invalidate(memberListProvider(request.organizationId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم اعتماد العضو بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _processingRequestId = null);
    }
  }

  Future<void> _reject({
    required MembershipRequestModel request,
    required String reviewedBy,
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectionReasonDialog(),
    );
    if (reason == null || !mounted) return;

    setState(() => _processingRequestId = request.requestId);
    try {
      await ref.read(membershipRequestRepositoryProvider).reject(
            organizationId: request.organizationId,
            requestId: request.requestId,
            reviewedBy: reviewedBy,
            rejectionReason: reason,
          );
      ref.invalidate(
        pendingMembershipRequestsProvider(request.organizationId),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض طلب الانضمام')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _processingRequestId = null);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تعذر تنفيذ العملية: $error'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organization = organizationContext.currentOrganization;
    final organizationId = organization?['organizationId'] as String?;
    final reviewedBy = ref.watch(authStateProvider).value?.uid;
    final access = ref.watch(adminAccessProvider).asData?.value;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('طلبات الانضمام'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: organizationId == null ||
                reviewedBy == null ||
                access?.canReviewRequests != true
            ? const _OrganizationRequired()
            : _buildRequests(
                organizationId: organizationId,
                organizationName: _organizationName(organization!),
                reviewedBy: reviewedBy,
              ),
      ),
    );
  }

  Widget _buildRequests({
    required String organizationId,
    required String organizationName,
    required String reviewedBy,
  }) {
    final requests =
        ref.watch(pendingMembershipRequestsProvider(organizationId));

    return requests.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذر تحميل الطلبات: $error'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) return const _EmptyRequests();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final request = items[index];
            return _MembershipRequestCard(
              request: request,
              organizationName: organizationName,
              isProcessing: _processingRequestId == request.requestId,
              actionsEnabled: _processingRequestId == null,
              onApprove: () => _approve(
                request: request,
                reviewedBy: reviewedBy,
              ),
              onReject: () => _reject(
                request: request,
                reviewedBy: reviewedBy,
              ),
            );
          },
        );
      },
    );
  }
}

class _MembershipRequestCard extends StatelessWidget {
  const _MembershipRequestCard({
    required this.request,
    required this.organizationName,
    required this.isProcessing,
    required this.actionsEnabled,
    required this.onApprove,
    required this.onReject,
  });

  final MembershipRequestModel request;
  final String organizationName;
  final bool isProcessing;
  final bool actionsEnabled;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final submittedDate =
        DateFormat('yyyy/MM/dd - HH:mm').format(request.submittedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.fullName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const Divider(height: 24),
            _RequestField(label: 'الرقم المدني', value: request.civilId),
            _RequestField(label: 'الهاتف', value: request.phone),
            _RequestField(label: 'المجلس', value: organizationName),
            const _RequestField(label: 'الحالة', value: 'قيد المراجعة'),
            _RequestField(label: 'البريد الإلكتروني', value: request.email),
            _RequestField(label: 'العنوان', value: request.address),
            _RequestField(
              label: 'الدور المطلوب',
              value: request.requestedRole,
            ),
            _RequestField(label: 'تاريخ التقديم', value: submittedDate),
            _RequestField(
              label: 'ملاحظات',
              value: request.notes?.trim().isNotEmpty == true
                  ? request.notes!
                  : '-',
            ),
            const SizedBox(height: 14),
            if (isProcessing)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: actionsEnabled ? onReject : null,
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: actionsEnabled ? onApprove : null,
                      icon: const Icon(Icons.check),
                      label: const Text('اعتماد'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
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

class _RequestField extends StatelessWidget {
  const _RequestField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

String _organizationName(Map<String, dynamic> organization) {
  final arabicName = organization['officialNameArabic'];
  if (arabicName is String && arabicName.trim().isNotEmpty) return arabicName;
  final shortName = organization['shortName'];
  if (shortName is String && shortName.trim().isNotEmpty) return shortName;
  return organization['organizationId'] as String? ?? '-';
}

class _RejectionReasonDialog extends StatefulWidget {
  const _RejectionReasonDialog();

  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سبب رفض الطلب'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'اكتب سبب الرفض',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'سبب الرفض مطلوب' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              context.pop(_controller.text.trim());
            }
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('رفض الطلب'),
        ),
      ],
    );
  }
}

class _OrganizationRequired extends StatelessWidget {
  const _OrganizationRequired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_outlined, size: 56),
            const SizedBox(height: 16),
            const Text(
              'يجب اختيار مجلس قبل مراجعة طلبات الانضمام',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.pushNamed('organizationSelector'),
              child: const Text('اختيار المجلس'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.how_to_reg_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('لا توجد طلبات انضمام قيد المراجعة'),
        ],
      ),
    );
  }
}
