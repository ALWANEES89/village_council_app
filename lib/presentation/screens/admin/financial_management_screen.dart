import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/financial_models.dart';
import '../../../providers/app_providers.dart';

class FinancialManagementScreen extends ConsumerWidget {
  const FinancialManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).value;
    final allowed = access?.isPlatformOwner == true ||
        access?.isOrgOwner == true ||
        access?.has('payments.manage') == true ||
        access?.has('receipts.review') == true;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('إدارة الرسوم والاشتراكات'),
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            bottom: const TabBar(
              tabs: [
                Tab(text: 'الإعدادات'),
                Tab(text: 'الباقات'),
                Tab(text: 'حسابات الأعضاء')
              ],
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
            ),
          ),
          body: organizationId == null || !allowed
              ? const Center(child: Text('لا تملك صلاحية إدارة النظام المالي.'))
              : TabBarView(children: [
                  _SettingsTab(organizationId: organizationId),
                  _PlansTab(organizationId: organizationId),
                  _MembersTab(organizationId: organizationId),
                ]),
        ),
      ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab({required this.organizationId});
  final String organizationId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(financialSettingsProvider(organizationId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('تعذر تحميل الإعدادات.')),
          data: (settings) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(
                icon: Icons.account_balance_outlined,
                title: 'نوع المجلس المالي',
                value: _feeModeLabel(settings.feeMode),
                onTap: () => _editSettings(context, ref, settings),
              ),
              _InfoCard(
                  icon: Icons.event_seat_outlined,
                  title: 'رسم حجز العضو',
                  value: formatBaisa(settings.memberBookingFeeBaisa),
                  onTap: () => _editSettings(context, ref, settings)),
              _InfoCard(
                  icon: Icons.person_add_alt_outlined,
                  title: 'رسم حجز غير العضو',
                  value: formatBaisa(settings.nonMemberBookingFeeBaisa),
                  onTap: () => _editSettings(context, ref, settings)),
              _InfoCard(
                  icon: Icons.celebration_outlined,
                  title: 'رسم المناسبة',
                  value: formatBaisa(settings.eventBookingFeeBaisa),
                  onTap: () => _editSettings(context, ref, settings)),
              const Card(
                child: ListTile(
                  leading:
                      Icon(Icons.receipt_long_outlined, color: Colors.green),
                  title: Text('التحويل البنكي ورفع الإيصال'),
                  subtitle: Text('مفعّل'),
                ),
              ),
              const Card(
                child: ListTile(
                  leading:
                      Icon(Icons.credit_card_off_outlined, color: Colors.grey),
                  title: Text('الدفع الإلكتروني'),
                  subtitle: Text('مخفي ومعطّل حتى ربط مزود دفع آمن'),
                ),
              ),
            ],
          ),
        );
  }

  Future<void> _editSettings(
      BuildContext context, WidgetRef ref, FinancialSettings settings) async {
    var mode = settings.feeMode;
    final member = TextEditingController(
        text: (settings.memberBookingFeeBaisa / 1000).toStringAsFixed(3));
    final nonMember = TextEditingController(
        text: (settings.nonMemberBookingFeeBaisa / 1000).toStringAsFixed(3));
    final event = TextEditingController(
        text: (settings.eventBookingFeeBaisa / 1000).toStringAsFixed(3));
    final updated = await showDialog<FinancialSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('الإعدادات المالية'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<FinancialFeeMode>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'نوع الرسوم'),
                    items: FinancialFeeMode.values
                        .map((item) => DropdownMenuItem(
                            value: item, child: Text(_feeModeLabel(item))))
                        .toList(),
                    onChanged: (value) => setState(() => mode = value ?? mode),
                  ),
                  TextField(
                      controller: member,
                      decoration: const InputDecoration(
                          labelText: 'رسم حجز العضو (ر.ع)')),
                  TextField(
                      controller: nonMember,
                      decoration: const InputDecoration(
                          labelText: 'رسم حجز غير العضو (ر.ع)')),
                  TextField(
                      controller: event,
                      decoration: const InputDecoration(
                          labelText: 'رسم المناسبة (ر.ع)')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () {
                        final memberValue = parseOmaniRialsToBaisa(member.text);
                        final nonMemberValue =
                            parseOmaniRialsToBaisa(nonMember.text);
                        final eventValue = parseOmaniRialsToBaisa(event.text);
                        if (memberValue == null ||
                            nonMemberValue == null ||
                            eventValue == null) {
                          return;
                        }
                        Navigator.pop(
                            context,
                            FinancialSettings(
                              organizationId: settings.organizationId,
                              feeMode: mode,
                              memberBookingFeeBaisa: memberValue,
                              nonMemberBookingFeeBaisa: nonMemberValue,
                              eventBookingFeeBaisa: eventValue,
                              receiptPaymentsEnabled: true,
                              onlinePaymentsEnabled: false,
                              allowMonthlyPlans: settings.allowMonthlyPlans,
                              allowAnnualPlans: settings.allowAnnualPlans,
                            ));
                      },
                      child: const Text('حفظ')),
                ],
              )),
    );
    member.dispose();
    nonMember.dispose();
    event.dispose();
    if (updated == null || !context.mounted) return;
    final actor = ref.read(authServiceProvider).currentUser?.uid;
    if (actor != null) {
      await ref.read(financialRepositoryProvider).saveSettings(updated, actor);
    }
  }
}

class _PlansTab extends ConsumerWidget {
  const _PlansTab({required this.organizationId});
  final String organizationId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(subscriptionPlansProvider(organizationId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _planDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('باقة جديدة')),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('تعذر تحميل الباقات.')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('لم تُنشأ باقات بعد.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final plan = items[index];
                  return Card(
                      child: ListTile(
                    leading: Icon(
                        plan.active
                            ? Icons.workspace_premium
                            : Icons.pause_circle_outline,
                        color:
                            plan.active ? Colors.amber.shade800 : Colors.grey),
                    title: Text(plan.nameArabic,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${_cycleLabel(plan.billingCycle)} • ${formatBaisa(plan.amountBaisa)}\n${plan.descriptionArabic}'),
                    isThreeLine: true,
                    trailing:
                        Chip(label: Text(plan.active ? 'مفعلة' : 'معطلة')),
                    onTap: () => _planDialog(context, ref, plan: plan),
                  ));
                },
              ),
      ),
    );
  }

  Future<void> _planDialog(BuildContext context, WidgetRef ref,
      {SubscriptionPlan? plan}) async {
    final name = TextEditingController(text: plan?.nameArabic);
    final description = TextEditingController(text: plan?.descriptionArabic);
    final amount = TextEditingController(
        text: plan == null ? '' : (plan.amountBaisa / 1000).toStringAsFixed(3));
    var cycle = plan?.billingCycle ?? BillingCycle.monthly;
    var active = plan?.active ?? true;
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: Text(plan == null ? 'إنشاء باقة' : 'تعديل الباقة'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: 'اسم الباقة بالعربية')),
                    TextField(
                        controller: description,
                        decoration: const InputDecoration(labelText: 'الوصف')),
                    TextField(
                        controller: amount,
                        decoration:
                            const InputDecoration(labelText: 'المبلغ (ر.ع)')),
                    DropdownButtonFormField<BillingCycle>(
                        initialValue: cycle,
                        items: BillingCycle.values
                            .map((item) => DropdownMenuItem(
                                value: item, child: Text(_cycleLabel(item))))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => cycle = value ?? cycle)),
                    SwitchListTile(
                        value: active,
                        onChanged: (value) => setState(() => active = value),
                        title: const Text('الباقة مفعلة')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('حفظ'))
                  ],
                )));
    final amountBaisa = parseOmaniRialsToBaisa(amount.text);
    if (save == true &&
        amountBaisa != null &&
        name.text.trim().isNotEmpty &&
        context.mounted) {
      final actor = ref.read(authServiceProvider).currentUser!.uid;
      await ref.read(financialRepositoryProvider).savePlan(
            organizationId: organizationId,
            actorId: actor,
            planId: plan?.id,
            nameArabic: name.text,
            descriptionArabic: description.text,
            billingCycle: cycle,
            amountBaisa: amountBaisa,
            active: active,
          );
    }
    name.dispose();
    description.dispose();
    amount.dispose();
  }
}

enum _MemberFilter { all, regular, overdue, pending, exempt }

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  String _query = '';
  _MemberFilter _filter = _MemberFilter.all;
  @override
  Widget build(BuildContext context) {
    final directory =
        ref.watch(financialMemberDirectoryProvider(widget.organizationId));
    final charges =
        ref.watch(organizationChargesProvider(widget.organizationId));
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
              onChanged: (value) =>
                  setState(() => _query = normalizeArabicSearch(value)),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'بحث بالاسم أو رقم العضوية',
                  border: OutlineInputBorder()))),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
              children: _MemberFilter.values
                  .map((item) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                          label: Text(_memberFilterLabel(item)),
                          selected: _filter == item,
                          onSelected: (_) => setState(() => _filter = item))))
                  .toList())),
      Expanded(
          child: directory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('تعذر تحميل دليل الأعضاء.')),
        data: (members) {
          final allCharges = charges.value ?? const <FinancialCharge>[];
          final visible = members.where((member) {
            final memberCharges = allCharges
                .where((charge) => charge.membershipId == member.membershipId)
                .toList();
            final searchMatch = _query.isEmpty ||
                normalizeArabicSearch(member.fullName).contains(_query) ||
                member.memberNumber.contains(_query);
            if (!searchMatch) return false;
            return switch (_filter) {
              _MemberFilter.all => true,
              _MemberFilter.regular =>
                memberCharges.every((charge) => charge.balanceBaisa == 0),
              _MemberFilter.overdue => memberCharges
                  .any((charge) => charge.status == ChargeStatus.overdue),
              _MemberFilter.pending => memberCharges
                  .any((charge) => charge.status == ChargeStatus.pendingReview),
              _MemberFilter.exempt => memberCharges
                  .any((charge) => charge.status == ChargeStatus.waived),
            };
          }).toList();
          return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: visible.length,
              itemBuilder: (_, index) {
                final member = visible[index];
                final memberCharges = allCharges
                    .where(
                        (charge) => charge.membershipId == member.membershipId)
                    .toList();
                final due = memberCharges.fold<int>(
                    0, (sum, item) => sum + item.amountDueBaisa);
                final paid = memberCharges.fold<int>(
                    0, (sum, item) => sum + item.amountPaidBaisa);
                final balance = memberCharges.fold<int>(
                    0, (sum, item) => sum + item.balanceBaisa);
                return Card(
                    child: ExpansionTile(
                  leading: CircleAvatar(
                      backgroundImage: member.photoUrl == null
                          ? null
                          : NetworkImage(member.photoUrl!),
                      child: member.photoUrl == null
                          ? const Icon(Icons.person)
                          : null),
                  title: Text(member.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'رقم ${member.memberNumber} • المتبقي ${formatBaisa(balance)}'),
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            'المطلوب ${formatBaisa(due)}  •  المدفوع ${formatBaisa(paid)}  •  المتبقي ${formatBaisa(balance)}')),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(
                          onPressed: () => _accountDialog(member),
                          child: const Text('الباقة/الإعفاء')),
                      OutlinedButton(
                          onPressed: () => _manualChargeDialog(member),
                          child: const Text('رسم يدوي')),
                      OutlinedButton(
                          onPressed: () => context.pushNamed('financialReview'),
                          child: const Text('الإيصالات')),
                    ]),
                    const SizedBox(height: 10),
                  ],
                ));
              });
        },
      )),
    ]);
  }

  Future<void> _accountDialog(MemberDirectoryEntry member) async {
    final plans =
        await ref.read(subscriptionPlansProvider(widget.organizationId).future);
    if (!mounted) return;
    String? planId;
    var override = FeeOverrideType.defaultFee;
    final amount = TextEditingController();
    final reason = TextEditingController();
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: Text('حساب ${member.fullName}'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                        initialValue: planId,
                        decoration: const InputDecoration(labelText: 'الباقة'),
                        items: plans
                            .map((plan) => DropdownMenuItem(
                                value: plan.id, child: Text(plan.nameArabic)))
                            .toList(),
                        onChanged: (value) => setState(() => planId = value)),
                    DropdownButtonFormField<FeeOverrideType>(
                        initialValue: override,
                        decoration:
                            const InputDecoration(labelText: 'نوع المعاملة'),
                        items: FeeOverrideType.values
                            .map((item) => DropdownMenuItem(
                                value: item, child: Text(_overrideLabel(item))))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => override = value ?? override)),
                    if (override == FeeOverrideType.custom)
                      TextField(
                          controller: amount,
                          decoration: const InputDecoration(
                              labelText: 'المبلغ المخصص (ر.ع)')),
                    if (override == FeeOverrideType.exempt)
                      TextField(
                          controller: reason,
                          decoration: const InputDecoration(
                              labelText: 'سبب الإعفاء الإلزامي')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('حفظ'))
                  ],
                )));
    if (save == true && mounted) {
      final custom = override == FeeOverrideType.custom
          ? parseOmaniRialsToBaisa(amount.text)
          : null;
      if (override == FeeOverrideType.exempt && reason.text.trim().isEmpty) {
        return;
      }
      await ref.read(financialRepositoryProvider).updateMemberAccount(
            organizationId: widget.organizationId,
            membershipId: member.membershipId,
            userId: member.userId,
            actorId: ref.read(authServiceProvider).currentUser!.uid,
            planId: planId,
            overrideType: override,
            customAmountBaisa: custom,
            exemptionReason: reason.text,
          );
    }
    amount.dispose();
    reason.dispose();
  }

  Future<void> _manualChargeDialog(MemberDirectoryEntry member) async {
    final requestId = const Uuid().v4();
    final title = TextEditingController();
    final description = TextEditingController();
    final amount = TextEditingController();
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('رسم يدوي لـ ${member.fullName}'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    decoration:
                        const InputDecoration(labelText: 'عنوان الرسم')),
                TextField(
                    controller: description,
                    decoration:
                        const InputDecoration(labelText: 'الوصف والتوثيق')),
                TextField(
                    controller: amount,
                    decoration:
                        const InputDecoration(labelText: 'المبلغ (ر.ع)')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('إنشاء'))
              ],
            ));
    final baisa = parseOmaniRialsToBaisa(amount.text);
    if (save == true &&
        baisa != null &&
        title.text.trim().isNotEmpty &&
        mounted) {
      final now = DateTime.now();
      await ref.read(financialRepositoryProvider).createManualCharge(
            organizationId: widget.organizationId,
            membershipId: member.membershipId,
            userId: member.userId,
            actorId: ref.read(authServiceProvider).currentUser!.uid,
            titleArabic: title.text,
            descriptionArabic: description.text,
            amountBaisa: baisa,
            dueDate: now,
            idempotencyKey: requestId,
          );
    }
    title.dispose();
    description.dispose();
    amount.dispose();
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.value,
      required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title),
          subtitle: Text(value),
          trailing: const Icon(Icons.edit_outlined),
          onTap: onTap));
}

String _feeModeLabel(FinancialFeeMode mode) => switch (mode) {
      FinancialFeeMode.free => 'مجلس مجاني',
      FinancialFeeMode.subscription => 'اشتراكات فقط',
      FinancialFeeMode.booking => 'رسوم حجوزات فقط',
      FinancialFeeMode.subscriptionAndBooking => 'اشتراكات وحجوزات'
    };
String _cycleLabel(BillingCycle cycle) => switch (cycle) {
      BillingCycle.monthly => 'شهري',
      BillingCycle.annual => 'سنوي',
      BillingCycle.oneTime => 'مرة واحدة'
    };
String _overrideLabel(FeeOverrideType type) => switch (type) {
      FeeOverrideType.defaultFee => 'باقة المجلس',
      FeeOverrideType.exempt => 'إعفاء',
      FeeOverrideType.custom => 'مبلغ مخصص'
    };
String _memberFilterLabel(_MemberFilter filter) => switch (filter) {
      _MemberFilter.all => 'الكل',
      _MemberFilter.regular => 'منتظم',
      _MemberFilter.overdue => 'متأخر',
      _MemberFilter.pending => 'قيد المراجعة',
      _MemberFilter.exempt => 'معفى'
    };
