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
import '../../widgets/omr_amount.dart';

class TransactionTimelineScreen extends ConsumerStatefulWidget {
  const TransactionTimelineScreen(
      {super.key, required this.transactionId, this.organizationId});
  final String transactionId;
  final String? organizationId;

  @override
  ConsumerState<TransactionTimelineScreen> createState() =>
      _TransactionTimelineScreenState();
}

class _TransactionTimelineScreenState
    extends ConsumerState<TransactionTimelineScreen> {
  bool _opening = false;
  final Set<String> _temporaryReceiptPaths = {};

  @override
  void dispose() {
    unawaited(_deleteTemporaryReceipts());
    super.dispose();
  }

  Future<void> _deleteTemporaryReceipts() async {
    for (final path in _temporaryReceiptPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // External viewers may retain the cache file briefly.
      }
    }
  }

  Future<void> _openReceipt(TransactionModel transaction) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final access =
          await ref.read(financialRepositoryProvider).getFinancialReceiptAccess(
                organizationId: transaction.organizationId,
                transactionId: transaction.id,
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
          final safeId =
              transaction.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
          final file = File(
            '${directory.path}${Platform.pathSeparator}${safeId}_$fileName',
          );
          await file.writeAsBytes(bytes, flush: true);
          _temporaryReceiptPaths.add(file.path);
          final result = await OpenFilex.open(file.path, type: contentType);
          if (result.type != ResultType.done) throw StateError(result.message);
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
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgId = widget.organizationId ??
        ref
            .watch(organizationContextProvider)
            .currentOrganization?['organizationId'] as String?;
    final transaction = orgId == null
        ? null
        : ref.watch(financialTransactionProvider(
            (organizationId: orgId, transactionId: widget.transactionId)));
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: const Text('تفاصيل المعاملة'),
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white),
        body: transaction == null
            ? const Center(child: Text('لا يوجد مجلس حالي.'))
            : transaction.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('تعذر تحميل المعاملة.')),
                data: (item) => item == null
                    ? const Center(child: Text('لم يتم العثور على المعاملة.'))
                    : _TransactionDetails(
                        transaction: item,
                        opening: _opening,
                        onOpenReceipt: () => _openReceipt(item),
                      ),
              ),
      ),
    );
  }
}

class _TransactionDetails extends StatelessWidget {
  const _TransactionDetails({
    required this.transaction,
    required this.opening,
    required this.onOpenReceipt,
  });
  final TransactionModel transaction;
  final bool opening;
  final VoidCallback onOpenReceipt;

  @override
  Widget build(BuildContext context) {
    final color = switch (transaction.reviewStatus) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _ => Colors.orange,
    };
    final label = switch (transaction.reviewStatus) {
      'approved' => 'تم الاعتماد',
      'rejected' => 'تم الرفض',
      _ => 'قيد المراجعة',
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Icon(
                transaction.reviewStatus == 'approved'
                    ? Icons.check_circle
                    : transaction.reviewStatus == 'rejected'
                        ? Icons.cancel
                        : Icons.hourglass_top,
                color: color,
                size: 44),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            OmrAmount(
              amountBaisa: transaction.amountDeclaredBaisa,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(DateFormat('yyyy/MM/dd - HH:mm')
                .format(transaction.submittedAt)),
          ]),
        ),
        if (transaction.rejectionReason?.isNotEmpty == true)
          Card(
              color: Colors.red.shade50,
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('سبب الرفض: ${transaction.rejectionReason}'))),
        const SizedBox(height: 16),
        const Text('توزيع الإيصال',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        for (final allocation in transaction.allocations)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(allocation.beneficiaryName),
              subtitle: Text(allocation.chargeTitle),
              trailing: OmrAmount(
                amountBaisa: allocation.amountAllocatedBaisa,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: opening ? null : onOpenReceipt,
          icon: opening
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new),
          label: Text(opening ? 'جارٍ فتح الإيصال...' : 'عرض ملف الإيصال'),
        ),
        const SizedBox(height: 16),
        const Text('مسار المعاملة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        _Step(
            icon: Icons.send_outlined,
            title: 'تم إرسال الإيصال',
            date: transaction.submittedAt,
            completed: true),
        _Step(
            icon: Icons.fact_check_outlined,
            title: 'مراجعة المبلغ والتوزيع',
            date: transaction.reviewedAt,
            completed: transaction.reviewStatus != 'pending'),
        _Step(
          icon: transaction.reviewStatus == 'rejected'
              ? Icons.cancel_outlined
              : Icons.verified_outlined,
          title: transaction.reviewStatus == 'rejected'
              ? 'تم الرفض'
              : 'تم اعتماد التوزيع',
          date: transaction.reviewedAt,
          completed: transaction.reviewStatus != 'pending',
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.icon,
      required this.title,
      required this.date,
      required this.completed});
  final IconData icon;
  final String title;
  final DateTime? date;
  final bool completed;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(
          backgroundColor: completed ? Colors.green : Colors.grey.shade300,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title),
        subtitle: Text(date == null
            ? 'بانتظار الإجراء'
            : DateFormat('yyyy/MM/dd - HH:mm').format(date!)),
      );
}
