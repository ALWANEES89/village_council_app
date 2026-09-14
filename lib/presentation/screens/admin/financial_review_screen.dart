import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/errors/firebase_function_error_message.dart';
import '../../../data/models/transaction_model.dart';
import '../../../data/repositories/financial_repository.dart';
import '../../../domain/financial/financial_logic.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/reason_input_dialog.dart';
import '../../widgets/omr_amount.dart';

class FinancialReviewScreen extends ConsumerStatefulWidget {
  const FinancialReviewScreen({super.key});
  @override
  ConsumerState<FinancialReviewScreen> createState() =>
      _FinancialReviewScreenState();
}

class _FinancialReviewScreenState extends ConsumerState<FinancialReviewScreen> {
  final Set<String> _processing = {};
  final Set<String> _opening = {};
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
        // The external viewer may still hold the file; the OS cache can remove it later.
      }
    }
  }

  Future<void> _approve(TransactionModel receipt) async {
    final strings = AppLocalizations.of(context);
    final approvalAllowed = canApproveReceipt(
      reviewStatus: receipt.reviewStatus,
      amountDeclaredBaisa: receipt.amountDeclaredBaisa,
      allocationTotalBaisa: receipt.allocationTotalBaisa,
      differenceBaisa: receipt.differenceBaisa,
    );
    if (!approvalAllowed ||
        receipt.allocations.isEmpty ||
        _processing.contains(receipt.id)) {
      return;
    }
    setState(() => _processing.add(receipt.id));
    try {
      await ref.read(financialReceiptRepositoryProvider).approve(
            transactionId: receipt.id,
            organizationId: receipt.organizationId,
            reviewedBy: ref.read(authServiceProvider).currentUser!.uid,
          );
      _message(strings.receiptApprovedAndAllocated);
    } catch (error) {
      debugPrint('[Receipts] approve failed type=${error.runtimeType}');
      _message(
        firebaseFunctionErrorMessage(
          error,
          fallback: strings.receiptApprovalFailed,
          unavailableMessage: strings.receiptApprovalUnavailable,
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _processing.remove(receipt.id));
    }
  }

  Future<void> _reject(TransactionModel receipt) async {
    final strings = AppLocalizations.of(context);
    if (_processing.contains(receipt.id)) return;
    final reason = await showReasonDialog(
      context: context,
      title: strings.receiptRejectionReason,
      hint: strings.receiptRejectionReasonHint,
      actionLabel: strings.rejectReceipt,
      confirmColor: Colors.red,
    );
    if (!mounted || reason == null || reason.trim().isEmpty) return;
    setState(() => _processing.add(receipt.id));
    try {
      await ref.read(financialReceiptRepositoryProvider).reject(
            transactionId: receipt.id,
            organizationId: receipt.organizationId,
            reviewedBy: ref.read(authServiceProvider).currentUser!.uid,
            rejectionReason: reason,
          );
      _message(strings.receiptRejectedWithoutPayment);
    } catch (error) {
      debugPrint('[Receipts] reject failed type=${error.runtimeType}');
      _message(
        firebaseFunctionErrorMessage(
          error,
          fallback: strings.receiptRejectionFailed,
          unavailableMessage: strings.receiptReviewUnavailable,
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _processing.remove(receipt.id));
    }
  }

  Future<void> _openReceipt(TransactionModel receipt) async {
    final strings = AppLocalizations.of(context);
    if (_opening.contains(receipt.id)) return;
    setState(() => _opening.add(receipt.id));
    try {
      final access =
          await ref.read(financialRepositoryProvider).getFinancialReceiptAccess(
                organizationId: receipt.organizationId,
                transactionId: receipt.id,
              );
      switch (access) {
        case FinancialReceiptUrlAccess(:final url):
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            throw StateError(strings.receiptOpenFailed);
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
          final safeTransactionId = receipt.id.replaceAll(
            RegExp(r'[^A-Za-z0-9_-]'),
            '_',
          );
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
      _message(
        firebaseFunctionErrorMessage(
          error,
          fallback: strings.receiptOpenFailed,
          unavailableMessage: strings.receiptOpenUnavailable,
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _opening.remove(receipt.id));
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).value;
    final allowed =
        access?.canReviewReceipts == true || access?.isPlatformOwner == true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          title: Text(strings.receiptReviewTitle),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white),
      body: organizationId == null || !allowed
          ? Center(child: Text(strings.noReceiptReviewPermission))
          : ref.watch(pendingFinancialReceiptsProvider(organizationId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: OutlinedButton.icon(
                    onPressed: () => ref.invalidate(
                        pendingFinancialReceiptsProvider(organizationId)),
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.receiptsLoadRetry),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? Center(child: Text(strings.noPendingReceipts))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (_, index) {
                          final receipt = items[index];
                          return _ReceiptReviewCard(
                            receipt: receipt,
                            processing: _processing.contains(receipt.id),
                            opening: _opening.contains(receipt.id),
                            onApprove: () => _approve(receipt),
                            onReject: () => _reject(receipt),
                            onOpen: () => _openReceipt(receipt),
                          );
                        },
                      ),
              ),
    );
  }
}

class _ReceiptReviewCard extends StatelessWidget {
  const _ReceiptReviewCard(
      {required this.receipt,
      required this.processing,
      required this.opening,
      required this.onApprove,
      required this.onReject,
      required this.onOpen});
  final TransactionModel receipt;
  final bool processing;
  final bool opening;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final canApprove = canApproveReceipt(
          reviewStatus: receipt.reviewStatus,
          amountDeclaredBaisa: receipt.amountDeclaredBaisa,
          allocationTotalBaisa: receipt.allocationTotalBaisa,
          differenceBaisa: receipt.differenceBaisa,
        ) &&
        receipt.allocations.isNotEmpty;
    final matchColor = canApprove ? Colors.green : Colors.deepOrange;
    final beneficiaries =
        receipt.allocations.map((item) => item.beneficiaryName).toSet();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                child: Text(receipt.payerName.isEmpty
                    ? '?'
                    : receipt.payerName.characters.first)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(receipt.payerName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(strings
                      .membershipNumberValue(receipt.memberNumber ?? '-')),
                  Text(strings.submittedAtValue(DateFormat('yyyy/MM/dd - HH:mm')
                      .format(receipt.submittedAt))),
                ])),
          ]),
          const Divider(height: 26),
          Text(strings.payerEnteredAmount),
          OmrAmount(
            amountBaisa: receipt.amountDeclaredBaisa,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          LabeledOmrAmount(
            label: strings.allocationTotal,
            amountBaisa: receipt.allocationTotalBaisa,
          ),
          LabeledOmrAmount(
            label: strings.amountDifference,
            amountBaisa: receipt.differenceBaisa,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: matchColor.withValues(alpha: .08),
                border: Border.all(color: matchColor),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(canApprove ? Icons.check_circle : Icons.warning_amber,
                  color: matchColor),
              const SizedBox(width: 8),
              Text(
                  canApprove
                      ? strings.amountMatchesAllocation
                      : receipt.amountDeclaredBaisa <= 0 ||
                              receipt.allocations.isEmpty
                          ? strings.incompleteReceiptApprovalDisabled
                          : strings.differenceApprovalDisabled,
                  style: TextStyle(
                      color: matchColor, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 14),
          Text(strings.paidBeneficiariesCount(beneficiaries.length),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final allocation in receipt.allocations)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(allocation.beneficiaryName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(allocation.chargeTitle),
                  LabeledOmrAmount(
                    label: strings.balanceAtSubmission,
                    amountBaisa: allocation.balanceBeforeBaisa,
                  ),
                ],
              ),
              trailing: OmrAmount(
                amountBaisa: allocation.amountAllocatedBaisa,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          OutlinedButton.icon(
            onPressed: opening ? null : onOpen,
            icon: opening
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new),
            label: Text(receipt.fileType == 'application/pdf'
                ? strings.openPdfFile
                : strings.viewReceiptImage),
          ),
          const SizedBox(height: 10),
          if (processing)
            const Center(child: CircularProgressIndicator())
          else
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: Text(strings.reject))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton.icon(
                      onPressed: canApprove ? onApprove : null,
                      icon: const Icon(Icons.check),
                      label: Text(strings.approve))),
            ]),
        ]),
      ),
    );
  }
}
