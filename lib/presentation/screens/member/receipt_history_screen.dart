import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/omr_amount.dart';

class ReceiptHistoryScreen extends ConsumerWidget {
  const ReceiptHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organizationId =
        organizationContext.currentOrganization?['organizationId'] as String?;
    final membershipId = organizationContext.currentMembership?.id;
    final key = organizationId == null || membershipId == null
        ? null
        : (organizationId: organizationId, membershipId: membershipId);
    final receipts =
        key == null ? null : ref.watch(payerFinancialTransactionsProvider(key));
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: const Text('سجل المعاملات'),
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white),
        body: receipts == null
            ? const Center(child: Text('افتح المجلس لعرض سجل معاملاته.'))
            : receipts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .invalidate(payerFinancialTransactionsProvider(key!)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('تعذر التحميل - إعادة المحاولة'),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Center(
                        child: Text('لا توجد معاملات في هذا المجلس.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final receipt = items[index];
                          final color = switch (receipt.reviewStatus) {
                            'approved' => Colors.green,
                            'rejected' => Colors.red,
                            _ => Colors.orange,
                          };
                          final label = switch (receipt.reviewStatus) {
                            'approved' => 'معتمد',
                            'rejected' => 'مرفوض',
                            _ => 'قيد المراجعة',
                          };
                          final beneficiaries = receipt.allocations
                              .map((item) => item.beneficiaryName)
                              .toSet()
                              .join('، ');
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: .12),
                                  child:
                                      Icon(Icons.receipt_long, color: color)),
                              title: OmrAmount(
                                amountBaisa: receipt.amountDeclaredBaisa,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                  '${DateFormat('yyyy/MM/dd - HH:mm').format(receipt.submittedAt)}\n$label${beneficiaries.isEmpty ? '' : '\nعن: $beneficiaries'}'),
                              isThreeLine: beneficiaries.isNotEmpty,
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () => context.pushNamed(
                                'transactionTimeline',
                                pathParameters: {'id': receipt.id},
                                queryParameters: {
                                  'organizationId': organizationId
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
