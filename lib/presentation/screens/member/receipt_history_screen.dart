import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/transaction_model.dart';
import '../../../providers/app_providers.dart';

class ReceiptHistoryScreen extends ConsumerWidget {
  const ReceiptHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final receipts =
        user == null ? null : ref.watch(memberTransactionsProvider(user.uid));
    // إيصالات المجلس الحالي فقط — لا تُدمج إيصالات المجالس الأخرى للعضو.
    final currentOrgId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('سجل الإيصالات'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: receipts == null
            ? const Center(child: Text('تعذر تحميل الحساب'))
            : receipts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('تعذر تحميل سجل الإيصالات'),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(
                          memberTransactionsProvider(user!.uid),
                        ),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
                data: (items) {
                  if (currentOrgId == null) {
                    return const Center(
                      child: Text('افتح المجلس لعرض إيصالاته'),
                    );
                  }
                  // تصفية على المجلس الحالي + إزالة التكرار (قد يُطابق
                  // collectionGroup نسخة المجلس والنسخة الجذرية بنفس المعرّف).
                  final seen = <String>{};
                  final scoped = <TransactionModel>[];
                  for (final receipt in items) {
                    if (receipt.organizationId != currentOrgId) continue;
                    if (seen.add(receipt.id)) scoped.add(receipt);
                  }
                  return scoped.isEmpty
                      ? const Center(
                          child: Text('لا توجد إيصالات في هذا المجلس'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: scoped.length,
                          itemBuilder: (_, index) =>
                              _ReceiptHistoryCard(receipt: scoped[index]),
                        );
                },
              ),
      ),
    );
  }
}

class _ReceiptHistoryCard extends StatelessWidget {
  const _ReceiptHistoryCard({required this.receipt});

  final TransactionModel receipt;

  @override
  Widget build(BuildContext context) {
    final status = switch (receipt.reviewStatus) {
      'approved' => ('معتمد', Colors.green),
      'rejected' => ('مرفوض', Colors.red),
      _ => ('قيد المراجعة', Colors.orange),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.receipt_long, color: status.$2),
        title: Text(receipt.paymentPeriod ?? 'إيصال دفع'),
        subtitle: Text(
          '${DateFormat('yyyy/MM/dd').format(receipt.submittedAt)}\n${status.$1}'
          '${receipt.rejectionReason?.isNotEmpty == true ? '\n${receipt.rejectionReason}' : ''}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () async {
            final uri = Uri.tryParse(receipt.receiptUrl);
            if (uri != null) await launchUrl(uri);
          },
        ),
      ),
    );
  }
}
