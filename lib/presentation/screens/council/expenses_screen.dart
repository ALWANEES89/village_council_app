import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/firebase_function_error_message.dart';
import '../../../core/formatters/omr_currency.dart';
import '../../../data/models/council_management_models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../domain/council_operations/council_operations_logic.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/omr_amount.dart';

const expenseCategories = <String>[
  'bills',
  'electricity',
  'water',
  'communications',
  'supplies',
  'maintenance',
  'cleaning',
  'equipment',
  'hospitality',
  'other',
];

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).valueOrNull;
    if (organizationId == null || access?.canViewFinancialReports != true) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.expenses)),
        body: Center(child: Text(strings.accessDenied)),
      );
    }
    final expenses = ref.watch(councilExpensesProvider(organizationId));
    return Scaffold(
      appBar: AppBar(title: Text(strings.expenses)),
      floatingActionButton: access?.canManageExpenses == true
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _ExpenseForm(organizationId: organizationId),
              ),
              icon: const Icon(Icons.add),
              label: Text(strings.addExpense),
            )
          : null,
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(strings.couldNotLoad)),
        data: (items) => items.isEmpty
            ? Center(child: Text(strings.noExpenses))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, index) => _ExpenseTile(
                  expense: items[index],
                  canManage: access?.canManageExpenses == true,
                  onEdit: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _ExpenseForm(
                      organizationId: organizationId,
                      expense: items[index],
                    ),
                  ),
                  onCancel: () => _cancelExpense(
                    context,
                    ref,
                    organizationId,
                    items[index],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _cancelExpense(
    BuildContext context,
    WidgetRef ref,
    String organizationId,
    CouncilExpense expense,
  ) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.cancelExpense),
            content: Text(strings.cancelExpenseConfirmation),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.close)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(strings.confirm)),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref.read(councilManagementRepositoryProvider).cancelExpense(
          organizationId: organizationId,
          expenseId: expense.id,
        );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.canManage,
    required this.onEdit,
    required this.onCancel,
  });
  final CouncilExpense expense;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
          title: Text(expense.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([
                _categoryLabel(context, expense.category),
                if (expense.expenseDate != null)
                  DateFormat.yMd(Localizations.localeOf(context).toString())
                      .format(expense.expenseDate!),
                if (expense.supplier?.isNotEmpty == true) expense.supplier!,
              ].join(' • ')),
              OmrAmount(amountBaisa: expense.amountBaisa),
            ],
          ),
          trailing: expense.status == 'cancelled'
              ? Text(AppLocalizations.of(context).cancelled)
              : canManage
                  ? PopupMenuButton<String>(
                      onSelected: (value) =>
                          value == 'edit' ? onEdit() : onCancel(),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                            value: 'edit',
                            child: Text(AppLocalizations.of(context).edit)),
                        PopupMenuItem(
                            value: 'cancel',
                            child: Text(
                                AppLocalizations.of(context).cancelExpense)),
                      ],
                    )
                  : OmrAmount(amountBaisa: expense.amountBaisa),
        ),
      );
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({required this.organizationId, this.expense});
  final String organizationId;
  final CouncilExpense? expense;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _key = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _supplier = TextEditingController();
  final _invoice = TextEditingController();
  final _note = TextEditingController();
  String _category = 'bills';
  DateTime _date = DateTime.now();
  bool _saving = false;
  File? _attachment;
  String? _attachmentName;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense == null) return;
    _title.text = expense.title;
    _amount.text = formatOmaniRialNumber(expense.amountBaisa);
    _supplier.text = expense.supplier ?? '';
    _invoice.text = expense.invoiceNumber ?? '';
    _note.text = expense.note ?? '';
    _category = expense.category;
    _date = expense.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final controller in [_title, _amount, _supplier, _invoice, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final strings = AppLocalizations.of(context);
    setState(() => _saving = true);
    final requestId = widget.expense?.id ?? const Uuid().v4();
    String attachmentPath = '';
    try {
      final user = ref.read(authServiceProvider).currentUser;
      if (_attachment != null && user != null) {
        final uploaded =
            await ref.read(storageServiceProvider).uploadExpenseAttachment(
                  file: _attachment!,
                  organizationId: widget.organizationId,
                  expenseId: requestId,
                  userId: user.uid,
                );
        attachmentPath = uploaded.fullPath;
      }
      final repository = ref.read(councilManagementRepositoryProvider);
      if (widget.expense == null) {
        await repository.createExpense(
          requestId: requestId,
          organizationId: widget.organizationId,
          title: _title.text,
          category: _category,
          amountBaisa: parseOmrToBaisa(_amount.text)!,
          expenseDate: _date,
          supplier: _supplier.text,
          invoiceNumber: _invoice.text,
          note: _note.text,
          attachmentStoragePath: attachmentPath,
        );
      } else {
        await repository.updateExpense(
          organizationId: widget.organizationId,
          expenseId: requestId,
          title: _title.text,
          category: _category,
          amountBaisa: parseOmrToBaisa(_amount.text)!,
          expenseDate: _date,
          supplier: _supplier.text,
          invoiceNumber: _invoice.text,
          note: _note.text,
          attachmentStoragePath: attachmentPath,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (attachmentPath.isNotEmpty) {
        try {
          await ref
              .read(storageServiceProvider)
              .deleteExpenseAttachment(attachmentPath);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(firebaseFunctionErrorMessage(
            error,
            fallback: strings.couldNotSaveExpense,
            unavailableMessage: strings.serviceUnavailable,
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 20, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _key,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(strings.addExpense,
                  style: Theme.of(context).textTheme.titleLarge),
              TextFormField(
                controller: _title,
                decoration:
                    InputDecoration(labelText: strings.expenseDescription),
                validator: (value) => value?.trim().isEmpty != false
                    ? strings.requiredField
                    : null,
              ),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: strings.amountOmr),
                validator: (value) => parseOmrToBaisa(value ?? '') == null
                    ? strings.invalidPositiveAmount
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(labelText: strings.expenseCategory),
                items: expenseCategories
                    .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(_categoryLabel(context, value))))
                    .toList(),
                onChanged: (value) => setState(() => _category = value!),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.expenseDate),
                subtitle: Text(DateFormat.yMd().format(_date)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: _date,
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              TextField(
                  controller: _supplier,
                  decoration: InputDecoration(labelText: strings.supplier)),
              TextField(
                  controller: _invoice,
                  decoration:
                      InputDecoration(labelText: strings.invoiceNumber)),
              TextField(
                  controller: _note,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: strings.notes)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_attachmentName ?? strings.expenseAttachment),
                subtitle: Text(strings.optionalPdfOrImage),
                onTap: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const [
                      'jpg',
                      'jpeg',
                      'png',
                      'webp',
                      'pdf'
                    ],
                  );
                  final path = result?.files.single.path;
                  if (path != null && mounted) {
                    setState(() {
                      _attachment = File(path);
                      _attachmentName = result!.files.single.name;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _saving ? null : _save, child: Text(strings.save)),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoryLabel(BuildContext context, String value) {
  final strings = AppLocalizations.of(context);
  return switch (value) {
    'bills' => strings.expenseBills,
    'electricity' => strings.expenseElectricity,
    'water' => strings.expenseWater,
    'communications' => strings.expenseCommunications,
    'supplies' => strings.expenseSupplies,
    'maintenance' => strings.expenseMaintenance,
    'cleaning' => strings.expenseCleaning,
    'equipment' => strings.expenseEquipment,
    'hospitality' => strings.expenseHospitality,
    _ => strings.expenseOther,
  };
}
