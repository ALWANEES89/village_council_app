import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/transaction_model.dart';
import '../../../data/repositories/financial_repository.dart';
import '../../../providers/app_providers.dart';

class AdminReviewScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String? organizationId;
  const AdminReviewScreen({
    super.key,
    required this.transactionId,
    this.organizationId,
  });

  @override
  ConsumerState<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends ConsumerState<AdminReviewScreen> {
  bool _isProcessing = false;
  bool _isOpening = false;
  bool _completed = false;
  final _rejectionController = TextEditingController();
  final Set<String> _temporaryReceiptPaths = {};

  @override
  void dispose() {
    unawaited(_deleteTemporaryReceipts());
    _rejectionController.dispose();
    super.dispose();
  }

  Future<void> _deleteTemporaryReceipts() async {
    for (final path in _temporaryReceiptPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The external viewer may still hold the file; cache cleanup is best effort.
      }
    }
  }

  Future<void> _openReceipt(TransactionModel tx) async {
    if (_isOpening || _isProcessing) return;
    setState(() => _isOpening = true);
    try {
      final access =
          await ref.read(financialRepositoryProvider).getFinancialReceiptAccess(
                organizationId: tx.organizationId,
                transactionId: tx.id,
              );
      switch (access) {
        case FinancialReceiptUrlAccess(:final url):
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            throw StateError('تعذر فتح رابط الإيصال.');
          }
        case FinancialReceiptBytesAccess(
            :final fileName,
            :final contentType,
            :final bytes,
          ):
          final directory = Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}financial_receipts',
          );
          await directory.create(recursive: true);
          final safeTransactionId =
              tx.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
          final file = File(
            '${directory.path}${Platform.pathSeparator}${safeTransactionId}_$fileName',
          );
          await file.writeAsBytes(bytes, flush: true);
          _temporaryReceiptPaths.add(file.path);
          final result = await OpenFilex.open(file.path, type: contentType);
          if (result.type != ResultType.done) {
            throw StateError(result.message);
          }
      }
    } catch (error) {
      debugPrint('[Receipts] secure open failed type=${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح الإيصال. تحقق من الصلاحية والملف.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  Future<void> _approve(TransactionModel tx) async {
    if (_isProcessing || _completed) return;
    setState(() => _isProcessing = true);
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    try {
      await ref.read(financialReceiptRepositoryProvider).approve(
            transactionId: tx.id,
            organizationId: tx.organizationId,
            reviewedBy: user.uid,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showFriendlyError();
      return;
    }
    if (!mounted) return;
    _completed = true;
    _closeSafely(
      organizationId: tx.organizationId,
      message: 'تم اعتماد الإيصال بنجاح',
      color: Colors.green.shade600,
    );
  }

  Future<void> _reject(TransactionModel tx) async {
    if (_isProcessing || _completed || !mounted) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectionDialog(controller: _rejectionController),
    );
    if (!mounted || reason == null || reason.isEmpty) return;

    setState(() => _isProcessing = true);
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    try {
      await ref.read(financialReceiptRepositoryProvider).reject(
            transactionId: tx.id,
            organizationId: tx.organizationId,
            reviewedBy: user.uid,
            rejectionReason: reason,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showFriendlyError();
      return;
    }
    if (!mounted) return;
    _completed = true;
    _closeSafely(
      organizationId: tx.organizationId,
      message: 'تم رفض الإيصال',
      color: Colors.red,
    );
  }

  void _closeSafely({
    required String? organizationId,
    required String message,
    required Color color,
  }) {
    if (!mounted) return;
    if (organizationId?.isNotEmpty == true) {
      ref.invalidate(pendingFinancialReceiptsProvider(organizationId!));
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(true);
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _showFriendlyError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر تنفيذ العملية. قد يكون الإيصال قد تمت مراجعته.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(firestoreServiceProvider);
    final txStream = widget.organizationId?.isNotEmpty == true
        ? service.organizationTransactionStream(
            organizationId: widget.organizationId!,
            transactionId: widget.transactionId,
          )
        : service.transactionStream(widget.transactionId);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            'مراجعة الإيصال',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: AppColors.primaryDark,
          centerTitle: true,
        ),
        body: StreamBuilder<TransactionModel?>(
          stream: txStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل بيانات الإيصال'));
            }
            final tx = snapshot.data;
            if (tx == null) {
              return const Center(child: Text('لم يتم العثور على المعاملة'));
            }
            return _ReviewContent(
              tx: tx,
              isProcessing: _isProcessing,
              isOpening: _isOpening,
              onOpen: () => _openReceipt(tx),
              onApprove: () => _approve(tx),
              onReject: () => _reject(tx),
            );
          },
        ),
      ),
    );
  }
}

class _ReviewContent extends StatelessWidget {
  final TransactionModel tx;
  final bool isProcessing;
  final bool isOpening;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ReviewContent({
    required this.tx,
    required this.isProcessing,
    required this.isOpening,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'اسم العضو:', value: tx.memberName),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'تاريخ الإرسال:',
            value: DateFormat('yyyy/MM/dd - HH:mm').format(tx.submittedAt),
          ),
          const SizedBox(height: 20),
          const Text('صورة الإيصال:',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textDark)),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: isProcessing || isOpening ? null : onOpen,
              icon: isOpening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new),
              label:
                  Text(isOpening ? 'جارٍ فتح الإيصال...' : 'فتح الإيصال بأمان'),
            ),
          ),
          const SizedBox(height: 32),
          if (isProcessing)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text('رفض',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('قبول واعتماد',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textDark)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: TextStyle(color: Colors.grey.shade700)),
        ),
      ],
    );
  }
}

class _RejectionDialog extends StatelessWidget {
  final TextEditingController controller;
  const _RejectionDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: const Text('سبب الرفض', textAlign: TextAlign.right),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'اكتب سبب الرفض هنا...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('تأكيد الرفض',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
