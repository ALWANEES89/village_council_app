import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/financial_models.dart';
import '../../../data/models/transaction_model.dart';
import '../../../providers/app_providers.dart';

class TransactionTimelineScreen extends ConsumerWidget {
  const TransactionTimelineScreen(
      {super.key, required this.transactionId, this.organizationId});
  final String transactionId;
  final String? organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = organizationId ??
        ref
            .watch(organizationContextProvider)
            .currentOrganization?['organizationId'] as String?;
    final transaction = orgId == null
        ? null
        : ref.watch(financialTransactionProvider(
            (organizationId: orgId, transactionId: transactionId)));
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
                    : _TransactionDetails(transaction: item),
              ),
      ),
    );
  }
}

class _TransactionDetails extends StatelessWidget {
  const _TransactionDetails({required this.transaction});
  final TransactionModel transaction;

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
            Text(formatBaisa(transaction.amountDeclaredBaisa),
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
              trailing: Text(formatBaisa(allocation.amountAllocatedBaisa),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final uri = Uri.tryParse(transaction.receiptUrl);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('عرض ملف الإيصال'),
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
