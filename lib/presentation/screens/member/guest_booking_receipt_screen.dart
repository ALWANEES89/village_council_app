import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/financial_models.dart';
import '../../../providers/app_providers.dart';

class GuestBookingReceiptArguments {
  const GuestBookingReceiptArguments({
    required this.organizationId,
    required this.bookingId,
  });

  final String organizationId;
  final String bookingId;
}

class GuestBookingReceiptScreen extends ConsumerStatefulWidget {
  const GuestBookingReceiptScreen({super.key, required this.arguments});

  final GuestBookingReceiptArguments arguments;

  @override
  ConsumerState<GuestBookingReceiptScreen> createState() =>
      _GuestBookingReceiptScreenState();
}

class _GuestBookingReceiptScreenState
    extends ConsumerState<GuestBookingReceiptScreen> {
  late Future<Map<String, dynamic>?> _charge;
  final _amountController = TextEditingController();
  File? _file;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _charge = ref.read(bookingRepositoryProvider).getGuestBookingCharge(
          organizationId: widget.arguments.organizationId,
          bookingId: widget.arguments.bookingId,
        );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _file = File(path));
  }

  Future<void> _submit(Map<String, dynamic> charge) async {
    final amount = parseOmaniRialsToBaisa(_amountController.text);
    final balance = charge['balanceBaisa'] as int? ?? 0;
    if (_file == null || amount == null || amount <= 0 || amount > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('اختر الإيصال وأدخل مبلغًا صحيحًا لا يتجاوز الرصيد.')),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _submitting = true);
    String? uploadedPath;
    try {
      final receiptId = const Uuid().v4();
      final upload = await ref.read(storageServiceProvider).uploadReceipt(
            file: _file!,
            memberId: user.uid,
            organizationId: widget.arguments.organizationId,
            receiptId: receiptId,
            onProgress: (_) {},
          );
      uploadedPath = upload.fullPath;
      await ref.read(bookingRepositoryProvider).submitGuestBookingReceipt(
            organizationId: widget.arguments.organizationId,
            bookingId: widget.arguments.bookingId,
            chargeId: charge['chargeId'] as String,
            receiptId: receiptId,
            amountDeclaredBaisa: amount,
            balanceBeforeBaisa: balance,
            receiptUrl: upload.url,
            receiptStoragePath: upload.fullPath,
            fileName: upload.fileName,
            fileType: upload.fileType,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال إيصال الحجز للمراجعة.')),
        );
        context.pop();
      }
    } catch (error) {
      if (uploadedPath != null) {
        await ref
            .read(financialRepositoryProvider)
            .cleanupOrphanReceipt(receiptStoragePath: uploadedPath)
            .catchError((_) {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الإيصال: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إيصال رسوم الحجز'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _charge,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل رسم الحجز.'));
            }
            final charge = snapshot.data;
            if (charge == null) {
              return const Center(child: Text('لا يوجد رسم حجز مستحق.'));
            }
            final balance = charge['balanceBaisa'] as int? ?? 0;
            if (_amountController.text.isEmpty && balance > 0) {
              _amountController.text =
                  '${balance ~/ 1000}.${(balance % 1000).toString().padLeft(3, '0')}';
            }
            final transactionId = charge['lastTransactionId'] as String?;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: Text(charge['titleArabic'] as String? ?? 'رسم حجز'),
                    subtitle: Text('الحالة: ${charge['status']}'),
                    trailing: Text(formatBaisa(balance)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المدفوع فعليًا في التحويل',
                    hintText: '0.000',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_file == null
                      ? 'اختر صورة أو PDF'
                      : _file!.path.split(Platform.pathSeparator).last),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submitting || balance <= 0
                      ? null
                      : () => _submit(charge),
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: const Text('رفع الإيصال'),
                ),
                if (transactionId?.isNotEmpty == true)
                  TextButton.icon(
                    onPressed: () => context.pushNamed(
                      'transactionTimeline',
                      pathParameters: {'id': transactionId!},
                      queryParameters: {
                        'organizationId': widget.arguments.organizationId,
                      },
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('سجل المعاملة'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
