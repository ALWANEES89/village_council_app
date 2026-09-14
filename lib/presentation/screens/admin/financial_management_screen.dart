import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/firebase_function_error_message.dart';
import '../../../core/formatters/omr_currency.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/financial_models.dart';
import '../../../domain/financial/financial_logic.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/omr_amount.dart';

class FinancialManagementScreen extends ConsumerStatefulWidget {
  const FinancialManagementScreen({super.key});

  @override
  ConsumerState<FinancialManagementScreen> createState() =>
      _FinancialManagementScreenState();
}

class _FinancialManagementScreenState
    extends ConsumerState<FinancialManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final accessState = ref.watch(adminAccessProvider);
    final access = accessState.value;
    final allowed = access?.canManageFinancialSettings == true;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إدارة الرسوم والاشتراكات'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'الإعدادات'),
              Tab(text: 'الباقات'),
              Tab(text: 'حسابات الأعضاء')
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
          ),
        ),
        body: accessState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : organizationId == null
                ? const Center(child: Text('اختر مجلسًا لإدارة رسومه.'))
                : !allowed
                    ? const Center(
                        child: Text('لا تملك صلاحية إدارة النظام المالي.'),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _SettingsTab(organizationId: organizationId),
                          _PlansTab(organizationId: organizationId),
                          _MembersTab(organizationId: organizationId),
                        ],
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
    final settingsState = ref.watch(financialSettingsProvider(organizationId));
    final plansState = ref.watch(subscriptionPlansProvider(organizationId));
    return settingsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذر تحميل الإعدادات.')),
      data: (settings) {
        final plans = plansState.value ?? const <SubscriptionPlan>[];
        final defaultPlan = _resolveDefaultPlan(settings, plans);
        final bookingEnabled = _bookingFeesEnabled(settings.feeMode);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  settings.supportsSubscriptions
                      ? Icons.workspace_premium
                      : Icons.volunteer_activism_outlined,
                  color: settings.supportsSubscriptions
                      ? Colors.amber.shade800
                      : Colors.green,
                ),
                title: const Text('اشتراك المجلس'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(settings.supportsSubscriptions
                        ? 'المجلس مدفوع'
                        : 'المجلس مجاني (دون اشتراك عضوية)'),
                    if (settings.supportsSubscriptions && defaultPlan != null)
                      LabeledOmrAmount(
                        label: '${_cycleLabel(defaultPlan.billingCycle)} •',
                        amountBaisa: defaultPlan.amountBaisa,
                      ),
                    if (settings.supportsSubscriptions && defaultPlan == null)
                      Text(plansState.hasError
                          ? 'تعذر تحميل الباقة الحالية.'
                          : 'لم تُحدد قيمة الاشتراك بعد.'),
                  ],
                ),
                isThreeLine: settings.supportsSubscriptions,
                trailing: plansState.isLoading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(plansState.hasError
                        ? Icons.refresh
                        : Icons.edit_outlined),
                onTap: plansState.hasError
                    ? () => ref.invalidate(
                          subscriptionPlansProvider(organizationId),
                        )
                    : plansState.isLoading
                        ? null
                        : () => _editCouncilSubscription(
                              context,
                              ref,
                              settings,
                              plans,
                              defaultPlan,
                            ),
              ),
            ),
            _InfoCard(
              icon: Icons.event_available_outlined,
              title: 'رسوم الحجوزات',
              value: bookingEnabled ? 'مفعّلة' : 'معطّلة',
              onTap: () => _editBookingSettings(context, ref, settings),
            ),
            _InfoCard(
              icon: Icons.event_seat_outlined,
              title: 'رسم حجز العضو',
              amountBaisa: settings.memberBookingFeeBaisa,
              onTap: () => _editBookingSettings(context, ref, settings),
            ),
            _InfoCard(
              icon: Icons.person_add_alt_outlined,
              title: 'رسم حجز غير العضو',
              amountBaisa: settings.nonMemberBookingFeeBaisa,
              onTap: () => _editBookingSettings(context, ref, settings),
            ),
            _InfoCard(
              icon: Icons.celebration_outlined,
              title: 'رسم المناسبة',
              amountBaisa: settings.eventBookingFeeBaisa,
              onTap: () => _editBookingSettings(context, ref, settings),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: Colors.green),
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
        );
      },
    );
  }

  Future<void> _editCouncilSubscription(
    BuildContext context,
    WidgetRef ref,
    FinancialSettings settings,
    List<SubscriptionPlan> plans,
    SubscriptionPlan? defaultPlan,
  ) async {
    if (organizationId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديد المجلس الحالي.')),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    var paid = settings.supportsSubscriptions;
    var selectedPlanId = defaultPlan?.id;
    var cycle = defaultPlan?.billingCycle ?? BillingCycle.monthly;
    var amountText = defaultPlan == null
        ? ''
        : formatOmaniRialNumber(defaultPlan.amountBaisa);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إعدادات اشتراك المجلس'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<bool>(
                    groupValue: paid,
                    onChanged: (value) => setState(() => paid = value ?? false),
                    child: const Column(
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          title: Text('المجلس مجاني'),
                          subtitle: Text('لا تُنشأ استحقاقات اشتراك جديدة.'),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          title: Text('المجلس مدفوع'),
                          subtitle: Text('تُطبق باقة المجلس على الأعضاء.'),
                        ),
                      ],
                    ),
                  ),
                  if (paid) ...[
                    if (plans.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedPlanId,
                        decoration: const InputDecoration(
                          labelText: 'الباقة الافتراضية',
                        ),
                        items: plans
                            .map(
                              (plan) => DropdownMenuItem(
                                value: plan.id,
                                child: Text(plan.nameArabic),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          SubscriptionPlan? selected;
                          for (final plan in plans) {
                            if (plan.id == value) {
                              selected = plan;
                              break;
                            }
                          }
                          setState(() {
                            selectedPlanId = value;
                            if (selected != null) {
                              cycle = selected.billingCycle;
                              amountText = formatOmaniRialNumber(
                                selected.amountBaisa,
                              );
                            }
                          });
                        },
                      ),
                    DropdownButtonFormField<BillingCycle>(
                      initialValue: cycle,
                      decoration: const InputDecoration(
                        labelText: 'دورية الاشتراك',
                      ),
                      items: BillingCycle.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_cycleLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => cycle = value ?? cycle),
                    ),
                    TextFormField(
                      key: ValueKey('subscription-amount-$selectedPlanId'),
                      initialValue: amountText,
                      onChanged: (value) => amountText = value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: omrAmountInputDecoration(
                        labelText: 'قيمة الاشتراك بالريال العُماني',
                      ),
                      validator: (value) {
                        final parsed = parseOmaniRialsToBaisa(value ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'أدخل مبلغًا صحيحًا أكبر من صفر.';
                        }
                        return null;
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (paid && formKey.currentState?.validate() != true) return;
                Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final amountBaisa = paid ? parseOmaniRialsToBaisa(amountText) : null;
    if (save != true || !context.mounted) return;
    try {
      final result = await ref
          .read(financialRepositoryProvider)
          .configureCouncilSubscription(
            organizationId: organizationId,
            subscriptionEnabled: paid,
            planId: selectedPlanId,
            billingCycle: paid ? cycle : null,
            amountBaisa: amountBaisa,
          );
      if (!context.mounted) return;
      final details = paid && result.accountsSynced > 0
          ? ' وتم تحديث ${result.accountsSynced} حسابًا.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ إعدادات اشتراك المجلس$details')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(firebaseFunctionErrorMessage(
            error,
            fallback: 'تعذر حفظ إعدادات الاشتراك.',
            unavailableMessage:
                'خدمة إعداد اشتراك المجلس غير متاحة في إصدار الخادم الحالي.',
          )),
        ),
      );
    }
  }

  Future<void> _editBookingSettings(
      BuildContext context, WidgetRef ref, FinancialSettings settings) async {
    if (organizationId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديد المجلس الحالي.')),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    var bookingEnabled = _bookingFeesEnabled(settings.feeMode);
    var memberAmountText =
        formatOmaniRialNumber(settings.memberBookingFeeBaisa);
    var nonMemberAmountText =
        formatOmaniRialNumber(settings.nonMemberBookingFeeBaisa);
    var eventAmountText = formatOmaniRialNumber(settings.eventBookingFeeBaisa);
    final updated = await showDialog<FinancialSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('إعدادات رسوم الحجوزات'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SwitchListTile(
                      value: bookingEnabled,
                      onChanged: (value) =>
                          setState(() => bookingEnabled = value),
                      title: const Text('تفعيل رسوم الحجوزات'),
                    ),
                    TextFormField(
                        initialValue: memberAmountText,
                        onChanged: (value) => memberAmountText = value,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: omrAmountInputDecoration(
                            labelText: 'رسم حجز العضو'),
                        validator: _nonNegativeAmountValidator),
                    TextFormField(
                        initialValue: nonMemberAmountText,
                        onChanged: (value) => nonMemberAmountText = value,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: omrAmountInputDecoration(
                            labelText: 'رسم حجز غير العضو'),
                        validator: _nonNegativeAmountValidator),
                    TextFormField(
                        initialValue: eventAmountText,
                        onChanged: (value) => eventAmountText = value,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            omrAmountInputDecoration(labelText: 'رسم المناسبة'),
                        validator: _nonNegativeAmountValidator),
                  ])),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() != true) return;
                        final memberValue =
                            parseOmaniRialsToBaisa(memberAmountText);
                        final nonMemberValue =
                            parseOmaniRialsToBaisa(nonMemberAmountText);
                        final eventValue =
                            parseOmaniRialsToBaisa(eventAmountText);
                        if (memberValue == null ||
                            nonMemberValue == null ||
                            eventValue == null) {
                          return;
                        }
                        Navigator.pop(
                            context,
                            FinancialSettings(
                              organizationId: organizationId,
                              feeMode: _feeModeFor(
                                subscriptionEnabled:
                                    settings.supportsSubscriptions,
                                bookingEnabled: bookingEnabled,
                              ),
                              memberBookingFeeBaisa: memberValue,
                              nonMemberBookingFeeBaisa: nonMemberValue,
                              eventBookingFeeBaisa: eventValue,
                              receiptPaymentsEnabled:
                                  settings.receiptPaymentsEnabled,
                              onlinePaymentsEnabled: false,
                              allowMonthlyPlans: settings.allowMonthlyPlans,
                              allowAnnualPlans: settings.allowAnnualPlans,
                              defaultSubscriptionPlanId:
                                  settings.defaultSubscriptionPlanId,
                            ));
                      },
                      child: const Text('حفظ')),
                ],
              )),
    );
    if (updated == null || !context.mounted) return;
    try {
      await ref.read(financialRepositoryProvider).saveSettings(updated);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ رسوم الحجوزات.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(firebaseFunctionErrorMessage(
            error,
            fallback: 'تعذر حفظ رسوم الحجوزات.',
            unavailableMessage:
                'خدمة إعداد رسوم الحجوزات غير متاحة في إصدار الخادم الحالي.',
          )),
        ),
      );
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LabeledOmrAmount(
                          label: '${_cycleLabel(plan.billingCycle)} •',
                          amountBaisa: plan.amountBaisa,
                        ),
                        Text(plan.descriptionArabic),
                      ],
                    ),
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
    var nameText = plan?.nameArabic ?? '';
    var descriptionText = plan?.descriptionArabic ?? '';
    var amountText =
        plan == null ? '' : formatOmaniRialNumber(plan.amountBaisa);
    var cycle = plan?.billingCycle ?? BillingCycle.monthly;
    var active = plan?.active ?? true;
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: Text(plan == null ? 'إنشاء باقة' : 'تعديل الباقة'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        initialValue: nameText,
                        onChanged: (value) => nameText = value,
                        decoration: const InputDecoration(
                            labelText: 'اسم الباقة بالعربية')),
                    TextFormField(
                        initialValue: descriptionText,
                        onChanged: (value) => descriptionText = value,
                        decoration: const InputDecoration(labelText: 'الوصف')),
                    TextFormField(
                        initialValue: amountText,
                        onChanged: (value) => amountText = value,
                        decoration:
                            omrAmountInputDecoration(labelText: 'المبلغ')),
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
    final amountBaisa = parseOmaniRialsToBaisa(amountText);
    if (save == true &&
        amountBaisa != null &&
        nameText.trim().isNotEmpty &&
        context.mounted) {
      final actor = ref.read(authServiceProvider).currentUser!.uid;
      await ref.read(financialRepositoryProvider).savePlan(
            organizationId: organizationId,
            actorId: actor,
            planId: plan?.id,
            nameArabic: nameText,
            descriptionArabic: descriptionText,
            billingCycle: cycle,
            amountBaisa: amountBaisa,
            active: active,
          );
    }
  }
}

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  String _query = '';
  FinancialMemberFilter _filter = FinancialMemberFilter.all;
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
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
              children: FinancialMemberFilter.values
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
        error: (error, _) => _FinancialMembersLoadError(
          message: firebaseFunctionErrorMessage(
            error,
            fallback: 'تعذر تحميل دليل الأعضاء.',
            unavailableMessage:
                'خدمة دليل الحسابات المالية غير متاحة في إصدار الخادم الحالي.',
          ),
          onRetry: () => ref.invalidate(
              financialMemberDirectoryProvider(widget.organizationId)),
        ),
        data: (members) {
          return charges.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _FinancialMembersLoadError(
              message: 'تعذر تحميل حالات رسوم الأعضاء.',
              onRetry: () => ref.invalidate(
                  organizationChargesProvider(widget.organizationId)),
            ),
            data: (allCharges) {
              final chargesByMembership = <String, List<FinancialCharge>>{};
              for (final charge in allCharges) {
                chargesByMembership
                    .putIfAbsent(charge.membershipId, () => [])
                    .add(charge);
              }
              final visible = members.where((member) {
                final memberCharges =
                    chargesByMembership[member.membershipId] ?? const [];
                final searchMatch = _query.isEmpty ||
                    normalizeArabicSearch(member.fullName).contains(_query) ||
                    member.memberNumber.contains(_query);
                return searchMatch &&
                    memberMatchesFinancialFilter(
                      filter: _filter,
                      charges: memberCharges,
                    );
              }).toList();
              if (visible.isEmpty) {
                return const Center(
                  child: Text('لا توجد حسابات مطابقة للبحث والحالة المختارة.'),
                );
              }
              return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (_, index) {
                    final member = visible[index];
                    final memberCharges =
                        chargesByMembership[member.membershipId] ?? const [];
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
                      subtitle: LabeledOmrAmount(
                        label: 'رقم ${member.memberNumber} • المتبقي',
                        amountBaisa: balance,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OmrAmountPairLine(
                                firstLabel: 'المطلوب',
                                firstAmountBaisa: due,
                                secondLabel: 'المدفوع',
                                secondAmountBaisa: paid,
                              ),
                              LabeledOmrAmount(
                                label: 'المتبقي',
                                amountBaisa: balance,
                              ),
                            ],
                          ),
                        ),
                        Wrap(spacing: 8, children: [
                          OutlinedButton(
                              onPressed: () => _accountDialog(member),
                              child: const Text('الباقة/الإعفاء')),
                          OutlinedButton(
                              onPressed: () => _manualChargeDialog(member),
                              child: const Text('رسم يدوي')),
                          OutlinedButton(
                              onPressed: () =>
                                  context.pushNamed('financialReview'),
                              child: const Text('الإيصالات')),
                        ]),
                        const SizedBox(height: 10),
                      ],
                    ));
                  });
            },
          );
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
    var amountText = '';
    var reasonText = '';
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
                      TextFormField(
                          initialValue: amountText,
                          onChanged: (value) => amountText = value,
                          decoration: omrAmountInputDecoration(
                              labelText: 'المبلغ المخصص')),
                    if (override == FeeOverrideType.exempt)
                      TextFormField(
                          initialValue: reasonText,
                          onChanged: (value) => reasonText = value,
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
          ? parseOmaniRialsToBaisa(amountText)
          : null;
      if (override == FeeOverrideType.exempt && reasonText.trim().isEmpty) {
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
            exemptionReason: reasonText,
          );
    }
  }

  Future<void> _manualChargeDialog(MemberDirectoryEntry member) async {
    final requestId = const Uuid().v4();
    var titleText = '';
    var descriptionText = '';
    var amountText = '';
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('رسم يدوي لـ ${member.fullName}'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                    onChanged: (value) => titleText = value,
                    decoration:
                        const InputDecoration(labelText: 'عنوان الرسم')),
                TextFormField(
                    onChanged: (value) => descriptionText = value,
                    decoration:
                        const InputDecoration(labelText: 'الوصف والتوثيق')),
                TextFormField(
                    onChanged: (value) => amountText = value,
                    decoration: omrAmountInputDecoration(labelText: 'المبلغ')),
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
    final baisa = parseOmaniRialsToBaisa(amountText);
    if (save == true &&
        baisa != null &&
        titleText.trim().isNotEmpty &&
        mounted) {
      final now = DateTime.now();
      await ref.read(financialRepositoryProvider).createManualCharge(
            organizationId: widget.organizationId,
            membershipId: member.membershipId,
            userId: member.userId,
            actorId: ref.read(authServiceProvider).currentUser!.uid,
            titleArabic: titleText,
            descriptionArabic: descriptionText,
            amountBaisa: baisa,
            dueDate: now,
            idempotencyKey: requestId,
          );
    }
  }
}

class _FinancialMembersLoadError extends StatelessWidget {
  const _FinancialMembersLoadError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon,
      required this.title,
      this.value,
      this.amountBaisa,
      required this.onTap})
      : assert(value != null || amountBaisa != null);
  final IconData icon;
  final String title;
  final String? value;
  final int? amountBaisa;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title),
          subtitle: amountBaisa == null
              ? Text(value!)
              : OmrAmount(amountBaisa: amountBaisa!),
          trailing: const Icon(Icons.edit_outlined),
          onTap: onTap));
}

SubscriptionPlan? _resolveDefaultPlan(
  FinancialSettings settings,
  List<SubscriptionPlan> plans,
) {
  final defaultPlanId = settings.defaultSubscriptionPlanId;
  if (defaultPlanId != null) {
    for (final plan in plans) {
      if (plan.id == defaultPlanId) return plan;
    }
  }
  for (final plan in plans) {
    if (plan.active) return plan;
  }
  return plans.isEmpty ? null : plans.first;
}

bool _bookingFeesEnabled(FinancialFeeMode mode) =>
    mode == FinancialFeeMode.booking ||
    mode == FinancialFeeMode.subscriptionAndBooking;

FinancialFeeMode _feeModeFor({
  required bool subscriptionEnabled,
  required bool bookingEnabled,
}) {
  if (subscriptionEnabled) {
    return bookingEnabled
        ? FinancialFeeMode.subscriptionAndBooking
        : FinancialFeeMode.subscription;
  }
  return bookingEnabled ? FinancialFeeMode.booking : FinancialFeeMode.free;
}

String? _nonNegativeAmountValidator(String? value) {
  if (parseOmaniRialsToBaisa(value ?? '') == null) {
    return 'أدخل مبلغًا صحيحًا غير سالب.';
  }
  return null;
}

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
String _memberFilterLabel(FinancialMemberFilter filter) => switch (filter) {
      FinancialMemberFilter.all => 'الكل',
      FinancialMemberFilter.regular => 'منتظم',
      FinancialMemberFilter.unpaid => 'غير مدفوع',
      FinancialMemberFilter.partial => 'سداد جزئي',
      FinancialMemberFilter.overdue => 'متأخر',
      FinancialMemberFilter.pendingReview => 'قيد المراجعة',
      FinancialMemberFilter.paid => 'مدفوع',
      FinancialMemberFilter.exempt => 'معفى',
      FinancialMemberFilter.rejected => 'مرفوض',
      FinancialMemberFilter.cancelled => 'ملغى',
      FinancialMemberFilter.refundRequired => 'يتطلب استردادًا'
    };
