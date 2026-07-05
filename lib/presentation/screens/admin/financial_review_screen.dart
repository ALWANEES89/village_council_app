import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/transaction_model.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/reason_input_dialog.dart';

class FinancialReviewScreen extends ConsumerStatefulWidget {
  const FinancialReviewScreen({super.key});

  @override
  ConsumerState<FinancialReviewScreen> createState() =>
      _FinancialReviewScreenState();
}

class _FinancialReviewScreenState extends ConsumerState<FinancialReviewScreen> {
  /// معرّفات الإيصالات قيد المعالجة (اعتماد/رفض). حالة لكل إيصال على حدة —
  /// لا loading عام — حتى لا يتعطّل غير الإيصال المستهدف، ولمنع الضغط المتكرر
  /// أو فتح الإيصال أثناء رفضه/اعتماده (سبب crash `_dependents.isEmpty`).
  final Set<String> _processingIds = {};

  bool _isProcessing(String id) => _processingIds.contains(id);

  Future<void> _approve(TransactionModel receipt) async {
    final id = receipt.id;
    final organizationId = receipt.organizationId;
    if (_processingIds.contains(id) || organizationId == null) return;
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;
    setState(() => _processingIds.add(id));
    try {
      await ref.read(financialReceiptRepositoryProvider).approve(
            transactionId: id,
            organizationId: organizationId,
            reviewedBy: user.uid,
          );
      if (!mounted) return;
      // لا نستدعي ref.invalidate: تدفّق Firestore (snapshots) يُحدّث القائمة
      // تلقائيًّا فيخرج الإيصال من pending. الإبطال هنا كان يعيد كامل القائمة
      // إلى حالة loading فيهدم الشجرة أثناء أي تفاعل جارٍ (سبب crash).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم اعتماد الإيصال بنجاح')),
      );
    } catch (error, stackTrace) {
      debugPrint('[FinancialReview] approve failed id=$id: $error\n$stackTrace');
      _showError();
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  Future<void> _reject(TransactionModel receipt) async {
    final id = receipt.id;
    final organizationId = receipt.organizationId;
    if (_processingIds.contains(id) || organizationId == null) return;

    final reason = await showReasonDialog(
      context: context,
      title: 'سبب رفض الإيصال',
      hint: 'اكتب سبب الرفض',
      actionLabel: 'رفض',
      confirmColor: Colors.red,
    );
    if (!mounted || reason == null) return;
    // تحقّق مجددًا بعد await الحوار (قد يكون الإيصال دخل المعالجة أثناءه).
    if (_processingIds.contains(id)) return;
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;
    setState(() => _processingIds.add(id));
    try {
      await ref.read(financialReceiptRepositoryProvider).reject(
            transactionId: id,
            organizationId: organizationId,
            reviewedBy: user.uid,
            rejectionReason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الإيصال')),
      );
    } catch (error, stackTrace) {
      debugPrint('[FinancialReview] reject failed id=$id: $error\n$stackTrace');
      _showError();
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  /// فتح الإيصال (رابط خارجي) بأمان: يستخدم context الخاص بالـ State مع فحص
  /// mounted بعد await — لا يعتمد على context البطاقة التي قد تُحذف من القائمة.
  Future<void> _openReceipt(TransactionModel receipt) async {
    // لا نفتح الإيصال إذا كان قيد الرفض/الاعتماد (منع سباق التفكيك).
    if (_processingIds.contains(receipt.id)) return;
    try {
      final uri = Uri.tryParse(receipt.receiptUrl);
      final opened = uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الإيصال')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[FinancialReview] open receipt failed '
          'id=${receipt.id}: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الإيصال')),
      );
    }
  }

  void _showError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر تنفيذ العملية. حاول مرة أخرى.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organizationId =
        organizationContext.currentOrganization?['organizationId'] as String?;
    final roleId = organizationContext.currentRole?['roleId'] as String? ??
        organizationContext.currentMembership?.roleId;
    final access = ref.watch(adminAccessProvider).asData?.value;
    final allowed = access?.isSuperAdmin == true ||
        access?.canReviewReceipts == true ||
        const ['chairman', 'financialManager', 'financialReviewer']
            .contains(roleId);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('مراجعة الإيصالات'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: organizationId == null || !allowed
            ? const Center(child: Text('لا تملك صلاحية مراجعة الإيصالات'))
            : _buildReceipts(organizationId),
      ),
    );
  }

  Widget _buildReceipts(String organizationId) {
    final receipts =
        ref.watch(pendingFinancialReceiptsProvider(organizationId));
    return receipts.when(
      // لا نمسح قائمة معروضة عند إعادة التحميل: نُبقيها ونعرض الجديد فور وصوله.
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        // نُظهر الخطأ الحقيقي في السجل (فهرس/صلاحية/شبكة) بدل ابتلاعه.
        debugPrint('[FinancialReview] pending stream error '
            'org=$organizationId: $error\n$stackTrace');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تعذر تحميل الإيصالات قيد المراجعة'),
                const SizedBox(height: 6),
                Text(
                  _streamErrorHint(error),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(
                    pendingFinancialReceiptsProvider(organizationId),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        );
      },
      data: (items) => items.isEmpty
          ? const Center(child: Text('لا توجد إيصالات قيد الاعتماد'))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(
                pendingFinancialReceiptsProvider(organizationId),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final receipt = items[index];
                  final processing = _isProcessing(receipt.id);
                  return _ReceiptCard(
                    key: ValueKey(receipt.id),
                    receipt: receipt,
                    processing: processing,
                    onView: processing ? null : () => _openReceipt(receipt),
                    onApprove: processing ? null : () => _approve(receipt),
                    onReject: processing ? null : () => _reject(receipt),
                  );
                },
              ),
            ),
    );
  }

  String _streamErrorHint(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed-precondition') || text.contains('index')) {
      return 'الفهرس المطلوب غير مُهيّأ بعد. يرجى المحاولة بعد قليل.';
    }
    if (text.contains('permission-denied') || text.contains('unauthorized')) {
      return 'ليست لديك صلاحية عرض هذه الإيصالات.';
    }
    return 'تحقّق من الاتصال ثم أعد المحاولة.';
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    super.key,
    required this.receipt,
    required this.processing,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final TransactionModel receipt;
  final bool processing;

  /// كل الإجراءات nullable: قيمتها null تعني معطّلة (أثناء المعالجة).
  final VoidCallback? onView;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(receipt.memberName,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('رقم العضو: ${receipt.memberNumber ?? '-'}'),
            Text('الهاتف: ${receipt.memberPhone ?? '-'}'),
            Text(
                'المبلغ: ${receipt.amountDeclared?.toStringAsFixed(3) ?? '-'}'),
            Text('فترة الدفع: ${receipt.paymentPeriod ?? '-'}'),
            Text(
                'التاريخ: ${DateFormat('yyyy/MM/dd - HH:mm').format(receipt.submittedAt)}'),
            const Text('الحالة: قيد المراجعة'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              // معطّل أثناء المعالجة: لا يُفتح الإيصال لحظة رفضه/اعتماده.
              onPressed: onView,
              icon: const Icon(Icons.open_in_new),
              label: const Text('عرض الإيصال'),
            ),
            const SizedBox(height: 8),
            if (processing)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('رفض'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text('اعتماد'),
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
