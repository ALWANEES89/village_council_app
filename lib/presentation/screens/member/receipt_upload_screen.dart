import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/financial_models.dart';
import '../../../data/models/transaction_model.dart';
import '../../../domain/financial/financial_logic.dart';
import '../../../providers/app_providers.dart';

class ReceiptUploadScreen extends ConsumerStatefulWidget {
  const ReceiptUploadScreen({
    super.key,
    this.paymentId,
    this.periodLabel = 'إيصال دفع',
    this.organizationId,
    this.membershipId,
    this.userId,
    this.amountDeclaredBaisa,
  });

  final String? paymentId;
  final String periodLabel;
  final String? organizationId;
  final String? membershipId;
  final String? userId;
  final int? amountDeclaredBaisa;

  @override
  ConsumerState<ReceiptUploadScreen> createState() =>
      _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends ConsumerState<ReceiptUploadScreen> {
  final _amountController = TextEditingController();
  final _searchController = TextEditingController();
  final Map<String, MemberDirectoryEntry> _beneficiaries = {};
  final Map<String, List<FinancialCharge>> _chargesByMember = {};
  final Map<String, int> _allocations = {};
  Timer? _debounce;
  PaymentScope _scope = PaymentScope.self;
  List<MemberDirectoryEntry> _searchResults = const [];
  bool _searching = false;
  bool _loadingCharges = false;
  File? _selectedFile;
  String? _fileName;
  bool _isPdf = false;

  String get _organizationId =>
      widget.organizationId ??
      ref
          .read(organizationContextProvider)
          .currentOrganization?['organizationId'] as String? ??
      '';
  String get _payerMembershipId =>
      widget.membershipId ??
      ref.read(organizationContextProvider).currentMembership?.id ??
      '';

  @override
  void initState() {
    super.initState();
    if (widget.amountDeclaredBaisa != null) {
      final baisa = widget.amountDeclaredBaisa!;
      _amountController.text =
          '${baisa ~/ 1000}.${(baisa % 1000).toString().padLeft(3, '0')}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeSelf());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeSelf() async {
    final context = ref.read(organizationContextProvider);
    final membership = context.currentMembership;
    final user = ref.read(authStateProvider).value;
    if (membership == null || user == null || _organizationId.isEmpty) return;
    final profile = ref.read(userProfileProvider(user.uid)).value;
    final legacy = ref.read(currentMemberProvider).value;
    final self = MemberDirectoryEntry(
      membershipId: membership.id,
      userId: user.uid,
      fullName: profile?.fullName ?? legacy?.fullName ?? 'أنا',
      memberNumber: membership.memberNumber,
    );
    _beneficiaries[self.membershipId] = self;
    await _loadCharges(self.membershipId, initialChargeId: widget.paymentId);
  }

  Future<void> _loadCharges(String membershipId,
      {String? initialChargeId}) async {
    if (_chargesByMember.containsKey(membershipId)) return;
    setState(() => _loadingCharges = true);
    try {
      final charges =
          await ref.read(financialRepositoryProvider).getPayableCharges(
        organizationId: _organizationId,
        membershipIds: [membershipId],
      );
      if (!mounted) return;
      setState(() {
        _chargesByMember[membershipId] = charges;
        if (initialChargeId?.isNotEmpty == true) {
          for (final charge
              in charges.where((item) => item.id == initialChargeId)) {
            _allocations[charge.id] = charge.balanceBaisa;
          }
        }
      });
    } catch (error) {
      _showMessage('تعذر تحميل الرسوم المتاحة: $error', error: true);
    } finally {
      if (mounted) setState(() => _loadingCharges = false);
    }
  }

  void _changeScope(PaymentScope scope) {
    final selfId = _payerMembershipId;
    setState(() {
      _scope = scope;
      if (scope == PaymentScope.self) {
        final others = _beneficiaries.keys.where((id) => id != selfId).toList();
        for (final id in others) {
          _removeBeneficiary(id);
        }
      } else if (scope == PaymentScope.others) {
        _allocations.removeWhere((chargeId, _) =>
            (_chargesByMember[selfId] ?? const [])
                .any((charge) => charge.id == chargeId));
      }
    });
    if (scope == PaymentScope.mixed && !_beneficiaries.containsKey(selfId)) {
      _initializeSelf();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final normalized = normalizeArabicSearch(value);
    if (normalized.length < 3) {
      setState(() => _searchResults = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() => _searching = true);
    try {
      final results = await ref.read(financialRepositoryProvider).searchMembers(
            organizationId: _organizationId,
            query: value,
          );
      if (!mounted) return;
      setState(() => _searchResults = results
          .where((item) => item.membershipId != _payerMembershipId)
          .toList());
    } catch (error) {
      _showMessage('تعذر البحث عن الأعضاء: $error', error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addBeneficiary(MemberDirectoryEntry entry) async {
    if (_beneficiaries.containsKey(entry.membershipId)) {
      _showMessage('تم اختيار هذا العضو مسبقًا.');
      return;
    }
    setState(() {
      _beneficiaries[entry.membershipId] = entry;
      _searchResults = const [];
      _searchController.clear();
    });
    await _loadCharges(entry.membershipId);
  }

  void _removeBeneficiary(String membershipId) {
    final chargeIds = (_chargesByMember[membershipId] ?? const [])
        .map((item) => item.id)
        .toSet();
    _allocations.removeWhere((id, _) => chargeIds.contains(id));
    _chargesByMember.remove(membershipId);
    _beneficiaries.remove(membershipId);
  }

  Future<void> _editAllocation(FinancialCharge charge) async {
    final controller = TextEditingController(
      text: ((_allocations[charge.id] ?? charge.balanceBaisa) / 1000)
          .toStringAsFixed(3),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(charge.titleArabic),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'المبلغ المخصص',
              helperText: 'الحد الأقصى ${formatBaisa(charge.balanceBaisa)}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final baisa = parseOmaniRialsToBaisa(controller.text);
              if (baisa == null || baisa <= 0 || baisa > charge.balanceBaisa) {
                return;
              }
              Navigator.pop(context, baisa);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      setState(() => _allocations[charge.id] = value);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(source: source);
    if (image == null) return;
    setState(() {
      _selectedFile = File(image.path);
      _fileName = image.name;
      _isPdf = false;
    });
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _selectedFile = File(path);
      _fileName = result!.files.single.name;
      _isPdf = true;
    });
  }

  int get _allocationTotal =>
      _allocations.values.fold(0, (sum, value) => sum + value);
  int? get _declared => parseOmaniRialsToBaisa(_amountController.text);

  List<ReceiptAllocation> _buildAllocations() {
    final result = <ReceiptAllocation>[];
    for (final entry in _chargesByMember.entries) {
      final beneficiary = _beneficiaries[entry.key];
      if (beneficiary == null) continue;
      for (final charge in entry.value) {
        final amount = _allocations[charge.id];
        if (amount == null) continue;
        result.add(ReceiptAllocation(
          beneficiaryUserId: beneficiary.userId,
          beneficiaryMembershipId: beneficiary.membershipId,
          beneficiaryName: beneficiary.fullName,
          chargeId: charge.id,
          chargeTitle: charge.titleArabic,
          amountAllocatedBaisa: amount,
          balanceBeforeBaisa: charge.balanceBaisa,
        ));
      }
    }
    return result;
  }

  Future<void> _submit() async {
    final declared = _declared;
    final allocations = _buildAllocations();
    if (_selectedFile == null) {
      return _showMessage('اختر صورة الإيصال أو ملف PDF.', error: true);
    }
    if (allocations.isEmpty) {
      return _showMessage('اختر رسمًا واحدًا على الأقل.', error: true);
    }
    if (declared == null || declared <= 0) {
      return _showMessage('أدخل المبلغ المدفوع بثلاث خانات عشرية.',
          error: true);
    }
    final validation = validateReceiptDraft(
      declaredBaisa: declared,
      allocations: allocations,
    );
    if (!validation.isValid) {
      return _showMessage('لا يمكن الإرسال قبل تطابق المبلغ مع مجموع التوزيع.',
          error: true);
    }
    final verifiedScope = derivePaymentScope(
      payerMembershipId: _payerMembershipId,
      allocations: allocations,
    );
    final success = await ref.read(uploadProvider.notifier).uploadReceipt(
          file: _selectedFile!,
          organizationId: _organizationId,
          membershipId: _payerMembershipId,
          paymentScope: verifiedScope,
          amountDeclaredBaisa: declared,
          allocations: allocations,
        );
    if (!mounted) return;
    if (success) {
      _showMessage('تم إرسال الإيصال للمراجعة.');
      context.pop();
    } else {
      _showMessage(ref.read(uploadProvider).error ?? 'تعذر إرسال الإيصال.',
          error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    final upload = ref.watch(uploadProvider);
    final declared = _declared;
    final difference = (declared ?? 0) - _allocationTotal;
    final matches = declared != null &&
        declared > 0 &&
        difference == 0 &&
        _allocationTotal > 0;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: const Text('رفع إيصال التحويل'),
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('نطاق الدفع',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<PaymentScope>(
              segments: const [
                ButtonSegment(
                    value: PaymentScope.self,
                    label: Text('عن نفسي'),
                    icon: Icon(Icons.person_outline)),
                ButtonSegment(
                    value: PaymentScope.others,
                    label: Text('عن آخرين'),
                    icon: Icon(Icons.group_outlined)),
                ButtonSegment(
                    value: PaymentScope.mixed,
                    label: Text('مختلط'),
                    icon: Icon(Icons.groups_outlined)),
              ],
              selected: {_scope},
              onSelectionChanged: (value) => _changeScope(value.first),
            ),
            if (_scope != PaymentScope.self) ...[
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'ابحث باسم العضو',
                  helperText: 'يبدأ البحث بعد ثلاثة أحرف',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              for (final result in _searchResults)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: result.photoUrl == null
                          ? null
                          : NetworkImage(result.photoUrl!),
                      child: result.photoUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(result.fullName),
                    subtitle: Text('رقم العضوية: ${result.memberNumber}'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _addBeneficiary(result),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            const Text('الأعضاء والرسوم المختارة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            if (_loadingCharges) const LinearProgressIndicator(),
            for (final beneficiary in _beneficiaries.values)
              if (!(_scope == PaymentScope.others &&
                  beneficiary.membershipId == _payerMembershipId))
                _BeneficiaryCharges(
                  beneficiary: beneficiary,
                  charges:
                      _chargesByMember[beneficiary.membershipId] ?? const [],
                  allocations: _allocations,
                  removable: beneficiary.membershipId != _payerMembershipId,
                  onRemove: () => setState(
                      () => _removeBeneficiary(beneficiary.membershipId)),
                  onToggle: (charge, selected) => setState(() {
                    if (selected) {
                      _allocations[charge.id] = charge.balanceBaisa;
                    } else {
                      _allocations.remove(charge.id);
                    }
                  }),
                  onEdit: _editAllocation,
                ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountController,
              onChanged: (_) => setState(() {}),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع فعليًا في التحويل',
                hintText: '12.500',
                suffixText: 'ر.ع',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _AmountMatchCard(
                declared: declared,
                allocated: _allocationTotal,
                difference: difference,
                matches: matches),
            const SizedBox(height: 20),
            const Text('ملف الإيصال',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('الكاميرا'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('المعرض'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _pickPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'))),
            ]),
            if (_selectedFile != null)
              Card(
                child: ListTile(
                  leading: Icon(
                      _isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                      color: _isPdf ? Colors.red : AppColors.primary),
                  title: Text(_fileName ?? 'الإيصال'),
                  trailing: IconButton(
                      onPressed: () => setState(() => _selectedFile = null),
                      icon: const Icon(Icons.close)),
                ),
              ),
            const SizedBox(height: 20),
            if (upload.isUploading) ...[
              LinearProgressIndicator(value: upload.progress),
              const SizedBox(height: 8),
              const Center(
                  child: Text('جاري رفع الإيصال والتحقق من التوزيع...')),
            ] else
              FilledButton.icon(
                onPressed: matches && _selectedFile != null ? _submit : null,
                icon: const Icon(Icons.send_outlined),
                label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('إرسال للمراجعة')),
              ),
          ],
        ),
      ),
    );
  }
}

class _BeneficiaryCharges extends StatelessWidget {
  const _BeneficiaryCharges({
    required this.beneficiary,
    required this.charges,
    required this.allocations,
    required this.removable,
    required this.onRemove,
    required this.onToggle,
    required this.onEdit,
  });
  final MemberDirectoryEntry beneficiary;
  final List<FinancialCharge> charges;
  final Map<String, int> allocations;
  final bool removable;
  final VoidCallback onRemove;
  final void Function(FinancialCharge, bool) onToggle;
  final Future<void> Function(FinancialCharge) onEdit;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      '${beneficiary.fullName} • ${beneficiary.memberNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              if (removable)
                IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, color: Colors.red)),
            ]),
            if (charges.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('لا توجد رسوم متاحة للدفع.'))
            else
              for (final charge in charges)
                CheckboxListTile(
                  value: allocations.containsKey(charge.id),
                  onChanged: (value) => onToggle(charge, value == true),
                  title: Text(charge.titleArabic),
                  subtitle: Text(
                      'الرصيد ${formatBaisa(charge.balanceBaisa)}${allocations[charge.id] == null ? '' : ' • المخصص ${formatBaisa(allocations[charge.id]!)}'}'),
                  secondary: allocations.containsKey(charge.id)
                      ? IconButton(
                          onPressed: () => onEdit(charge),
                          icon: const Icon(Icons.edit_outlined))
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
          ]),
        ),
      );
}

class _AmountMatchCard extends StatelessWidget {
  const _AmountMatchCard(
      {required this.declared,
      required this.allocated,
      required this.difference,
      required this.matches});
  final int? declared;
  final int allocated;
  final int difference;
  final bool matches;
  @override
  Widget build(BuildContext context) {
    final color = matches ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'المبلغ المكتوب: ${declared == null ? '-' : formatBaisa(declared!)}'),
        Text('مجموع المبالغ الموزعة: ${formatBaisa(allocated)}'),
        Text('الفرق: ${formatBaisa(difference)}'),
        const SizedBox(height: 6),
        Row(children: [
          Icon(matches ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color),
          const SizedBox(width: 6),
          Text(matches ? 'المبلغ مطابق' : 'يجب أن يتطابق المبلغ مع التوزيع',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }
}
