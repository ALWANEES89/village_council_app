import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../data/models/payment_model.dart';
import '../../../providers/app_providers.dart';

class ReceiptUploadScreen extends ConsumerStatefulWidget {
  final String? paymentId;
  final String periodLabel;
  final String? organizationId;
  final String? membershipId;
  final String? userId;
  final double? amountDeclared;

  const ReceiptUploadScreen({
    super.key,
    required this.paymentId,
    required this.periodLabel,
    this.organizationId,
    this.membershipId,
    this.userId,
    this.amountDeclared,
  });

  @override
  ConsumerState<ReceiptUploadScreen> createState() =>
      _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends ConsumerState<ReceiptUploadScreen> {
  File? _selectedFile;
  String? _fileName;
  bool _isPdf = false;

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedFile = File(image.path);
        _fileName = image.name;
        _isPdf = false;
      });
    }
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedFile = File(image.path);
        _fileName = image.name;
        _isPdf = false;
      });
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _fileName = result.files.single.name;
        _isPdf = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار ملف أولاً')),
      );
      return;
    }

    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      _showFriendlyError();
      return;
    }
    UserProfileModel? profile;
    try {
      profile = await ref.read(userProfileProvider(user.uid).future);
    } catch (_) {
      // The membership snapshot still allows receipt submission.
    }
    MemberModel? legacyMember;
    try {
      legacyMember = await ref.read(currentMemberProvider.future);
    } catch (_) {
      // Organization memberships do not require a legacy member document.
    }
    final organizationContext = ref.read(organizationContextProvider);
    PaymentModel? selectedPayment;
    if (widget.paymentId?.isNotEmpty == true) {
      try {
        selectedPayment = await ref
            .read(firestoreServiceProvider)
            .getPayment(widget.paymentId!);
      } catch (_) {
        // The receipt can still be submitted without payment enrichment.
      }
    }
    final organizationId = widget.organizationId ??
        selectedPayment?.organizationId ??
        organizationContext.currentOrganization?['organizationId'] as String?;
    final membershipId =
        widget.membershipId ?? organizationContext.currentMembership?.id;
    final membership = organizationContext.currentMembership;

    final success = await ref.read(uploadProvider.notifier).uploadReceipt(
          file: _selectedFile!,
          memberId: widget.userId ?? user.uid,
          memberName: profile?.fullName ?? legacyMember?.fullName ?? '',
          paymentId: widget.paymentId ?? '',
          periodLabel: widget.periodLabel,
          organizationId: organizationId,
          membershipId: membershipId,
          amountDeclared: widget.amountDeclared ?? selectedPayment?.amount,
          paymentPeriod: widget.periodLabel,
          memberNumber: membership?.memberNumber,
          memberPhone: profile?.phone ?? legacyMember?.phone,
        );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم إرسال الإيصال للمراجعة'),
          backgroundColor: Colors.green.shade600,
        ),
      );
      context.pop();
    } else {
      final error = ref.read(uploadProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_uploadErrorMessage(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _uploadErrorMessage(String? error) {
    if (error == null || error.trim().isEmpty) {
      return 'تعذر رفع الإيصال. حاول مرة أخرى.';
    }
    final normalized = error.toLowerCase();
    if (normalized.contains('unauthorized') ||
        normalized.contains('permission-denied')) {
      return 'لا تملك صلاحية رفع الإيصال لهذا المجلس. ($error)';
    }
    if (normalized.contains('unsupported receipt file type')) {
      return 'نوع الملف غير مدعوم. استخدم صورة JPG/PNG/WEBP أو PDF. ($error)';
    }
    if (normalized.contains('invalid receipt file size')) {
      return 'حجم الملف غير صالح أو يتجاوز 10 ميجابايت. ($error)';
    }
    return 'تعذر رفع الإيصال: $error';
  }

  void _showFriendlyError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر رفع الإيصال. تحقق من الاتصال وحاول مرة أخرى.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('رفع إيصال الدفع',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: AppColors.primary,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'تأكيد دفع: ${widget.periodLabel}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text('اختر طريقة رفع الإيصال:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textDark)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.camera_alt,
                      label: 'التقاط صورة',
                      color: Colors.blue,
                      onTap: _pickFromCamera,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.photo_library,
                      label: 'من المعرض',
                      color: Colors.green,
                      onTap: _pickFromGallery,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.picture_as_pdf,
                      label: 'ملف PDF',
                      color: Colors.red,
                      onTap: _pickPdf,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_selectedFile != null) ...[
                const Text('المعاينة:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        fontSize: 15)),
                const SizedBox(height: 12),
                Container(
                  height: _isPdf ? 100 : 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.white,
                  ),
                  child: _isPdf
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.picture_as_pdf,
                                  color: Colors.red, size: 48),
                              const SizedBox(height: 8),
                              Text(_fileName ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(_selectedFile!, fit: BoxFit.cover),
                        ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedFile = null),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('إزالة الملف',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
              const SizedBox(height: 20),
              if (uploadState.isUploading) ...[
                LinearPercentIndicator(
                  lineHeight: 12,
                  percent: uploadState.progress,
                  backgroundColor: Colors.grey.shade200,
                  progressColor: AppColors.primary,
                  barRadius: const Radius.circular(6),
                  center: Text(
                    '${(uploadState.progress * 100).toInt()}%',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                    child: Text('جاري رفع الإيصال...',
                        style: TextStyle(color: AppColors.primary))),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _selectedFile != null
                          ? AppColors.primaryGradient
                          : const LinearGradient(
                              colors: [Colors.grey, Colors.grey]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _selectedFile != null ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.send, color: Colors.white),
                      label: const Text('إرسال للمراجعة',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
