import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../data/services/organization_seed_service.dart';
import '../../../providers/app_providers.dart';
import '../data/membership_request_model.dart';
import '../providers/membership_request_providers.dart';

class JoinRequestScreen extends ConsumerStatefulWidget {
  const JoinRequestScreen({
    super.key,
    this.organizationId,
    this.joinCode,
  });

  final String? organizationId;
  final String? joinCode;

  @override
  ConsumerState<JoinRequestScreen> createState() => _JoinRequestScreenState();
}

class _JoinRequestScreenState extends ConsumerState<JoinRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _civilIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _reasonController = TextEditingController();

  String? _organizationId;
  bool _didPrefill = false;
  bool _isResolvingQr = false;
  String? _qrError;
  Map<String, dynamic>? _qrOrganization;
  bool _isSeedingOrganizations = false;
  bool _organizationSeedFailed = false;

  bool get _isQrFlow =>
      widget.organizationId?.trim().isNotEmpty == true ||
      widget.joinCode?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    if (_isQrFlow) {
      _isResolvingQr = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveQr());
    }
  }

  @override
  void didUpdateWidget(covariant JoinRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.joinCode != widget.joinCode) {
      _organizationId = null;
      _qrOrganization = null;
      _qrError = null;
      _isResolvingQr = _isQrFlow;
      if (_isQrFlow) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _resolveQr());
      }
    }
  }

  Future<void> _resolveQr() async {
    final joinCode = widget.joinCode?.trim();
    final expectedOrganizationId = widget.organizationId?.trim();
    if (joinCode == null || joinCode.isEmpty) {
      _setInvalidQr();
      return;
    }

    try {
      final organization = await ref
          .read(organizationRepositoryProvider)
          .getOrganizationByJoinCode(joinCode);
      if (!mounted) return;

      final resolvedId = organization?['organizationId'] as String?;
      final organizationMatches = expectedOrganizationId == null ||
          expectedOrganizationId.isEmpty ||
          resolvedId == expectedOrganizationId;
      if (organization == null || !organizationMatches || resolvedId == null) {
        _setInvalidQr();
        return;
      }

      setState(() {
        _organizationId = resolvedId;
        _qrOrganization = organization;
        _qrError = null;
        _isResolvingQr = false;
      });
    } catch (_) {
      if (mounted) _setInvalidQr();
    }
  }

  void _setInvalidQr() {
    if (!mounted) return;
    setState(() {
      _organizationId = null;
      _qrOrganization = null;
      _isResolvingQr = false;
      _qrError = 'رمز الانضمام غير صالح أو منتهي';
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _civilIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _prefill(MemberModel member, UserProfileModel? profile) {
    if (_didPrefill) return;
    _didPrefill = true;
    _fullNameController.text = profile?.fullName ?? member.fullName;
    _civilIdController.text = profile?.civilId ?? member.civilId;
    _phoneController.text = profile?.phone ?? member.phone;
    _emailController.text = profile?.email ?? '';
    _addressController.text = profile?.address ?? '';
  }

  Future<void> _seedOrganizations() async {
    if (_isSeedingOrganizations) return;
    setState(() {
      _isSeedingOrganizations = true;
      _organizationSeedFailed = false;
    });
    try {
      await OrganizationSeedService.instance.ensureSeeded();
      ref.invalidate(organizationsProvider);
    } catch (_) {
      if (mounted) setState(() => _organizationSeedFailed = true);
    } finally {
      if (mounted) setState(() => _isSeedingOrganizations = false);
    }
  }

  Future<void> _submit(MemberModel member) async {
    if (!_formKey.currentState!.validate()) return;
    final organizationId = _organizationId;
    if (organizationId == null) return;

    final request = MembershipRequestModel(
      requestId: member.userId,
      organizationId: organizationId,
      userId: member.userId,
      fullName: _fullNameController.text.trim(),
      civilId: _civilIdController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      requestedRole: 'member',
      status: MembershipRequestStatus.pending,
      submittedAt: DateTime.now(),
      notes: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
    );

    final submitted = await ref
        .read(membershipRequestSubmissionProvider.notifier)
        .submit(request);
    if (!mounted) return;

    if (submitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب الانضمام بنجاح')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(currentMemberProvider);
    final userId = ref.watch(authStateProvider).value?.uid;
    final profileAsync =
        userId == null ? null : ref.watch(userProfileProvider(userId));
    final submission = ref.watch(membershipRequestSubmissionProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('طلب الانضمام'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: memberAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const _ScreenMessage(
            message: 'تعذر تحميل بيانات حسابك. حاول مرة أخرى.',
          ),
          data: (member) {
            if (member == null) {
              return const _ScreenMessage(
                message: 'تعذر العثور على بيانات المستخدم',
              );
            }
            if (profileAsync?.isLoading == true) {
              return const Center(child: CircularProgressIndicator());
            }
            if (profileAsync?.hasError == true) {
              return const _ScreenMessage(
                message: 'تعذر تحميل الملف الشخصي. حاول مرة أخرى.',
              );
            }
            _prefill(member, profileAsync?.asData?.value);
            if (_isQrFlow) {
              if (_isResolvingQr) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_qrError != null || _qrOrganization == null) {
                return _InvalidQrMessage(
                  message: _qrError ?? 'رمز الانضمام غير صالح أو منتهي',
                );
              }
              return _buildForm(
                member: member,
                organizations: [_qrOrganization!],
                submission: submission,
                organizationLocked: true,
              );
            }

            final organizationsAsync = ref.watch(organizationsProvider);
            return organizationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _OrganizationLoadState(
                message: 'تعذر تحميل المجالس المتاحة',
                onRetry: _seedOrganizations,
              ),
              data: (organizations) {
                if (organizations.isEmpty) {
                  if (!_isSeedingOrganizations && !_organizationSeedFailed) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _seedOrganizations(),
                    );
                  }
                  return _OrganizationLoadState(
                    message: _organizationSeedFailed
                        ? 'تعذر تجهيز بيانات المجلس. حاول مرة أخرى.'
                        : 'جاري تجهيز بيانات المجلس...',
                    loading: _isSeedingOrganizations,
                    onRetry: _seedOrganizations,
                  );
                }
                return _buildForm(
                  member: member,
                  organizations: organizations,
                  submission: submission,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm({
    required MemberModel member,
    required List<Map<String, dynamic>> organizations,
    required MembershipRequestSubmissionState submission,
    bool organizationLocked = false,
  }) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ProfileSummary(
            fullName: _fullNameController.text,
            civilId: _civilIdController.text,
            phone: _phoneController.text,
            email: _emailController.text,
            address: _addressController.text,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _reasonController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'سبب الانضمام (اختياري)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 14),
          if (organizationLocked)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'المجلس',
              ),
              child: _OrganizationChoiceContent(
                organization: organizations.single,
              ),
            )
          else
            FormField<String>(
              initialValue: _organizationId,
              validator: (value) =>
                  value == null ? 'اختر المجلس الذي تريد الانضمام إليه' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'اختر المجلس',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  for (final organization in organizations)
                    _OrganizationChoiceCard(
                      organization: organization,
                      selected: field.value ==
                          organization['organizationId'] as String,
                      enabled: !submission.isSubmitting,
                      onTap: () {
                        final value = organization['organizationId'] as String;
                        setState(() => _organizationId = value);
                        field.didChange(value);
                      },
                    ),
                  if (field.hasError) ...[
                    const SizedBox(height: 6),
                    Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (submission.error != null) ...[
            const SizedBox(height: 16),
            Text(
              submission.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: submission.isSubmitting || organizations.isEmpty
                ? null
                : () => _submit(member),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: submission.isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }
}

class _ScreenMessage extends StatelessWidget {
  const _ScreenMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({
    required this.fullName,
    required this.civilId,
    required this.phone,
    required this.email,
    required this.address,
  });

  final String fullName;
  final String civilId;
  final String phone;
  final String email;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'بيانات مقدم الطلب',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _ProfileSummaryRow(label: 'الاسم', value: fullName),
            _ProfileSummaryRow(label: 'الرقم المدني', value: civilId),
            _ProfileSummaryRow(label: 'الهاتف', value: phone),
            if (email.isNotEmpty)
              _ProfileSummaryRow(label: 'البريد الإلكتروني', value: email),
            if (address.isNotEmpty)
              _ProfileSummaryRow(label: 'العنوان', value: address),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummaryRow extends StatelessWidget {
  const _ProfileSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text('$label: ${value.isEmpty ? '-' : value}'),
    );
  }
}

class _OrganizationLoadState extends StatelessWidget {
  const _OrganizationLoadState({
    required this.message,
    required this.onRetry,
    this.loading = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              const Icon(
                Icons.account_balance_outlined,
                size: 56,
                color: AppColors.primary,
              ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (!loading) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrganizationChoiceCard extends StatelessWidget {
  const _OrganizationChoiceCard({
    required this.organization,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Map<String, dynamic> organization;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: selected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: _OrganizationChoiceContent(
                  organization: organization,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrganizationChoiceContent extends StatelessWidget {
  const _OrganizationChoiceContent({required this.organization});

  final Map<String, dynamic> organization;

  @override
  Widget build(BuildContext context) {
    final logo = organization['logoUrl'] ?? organization['logo'];
    final description = _organizationDescription(organization);
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: logo is String && logo.trim().isNotEmpty
              ? Image.network(
                  logo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.account_balance,
                    color: AppColors.primary,
                  ),
                )
              : const Icon(
                  Icons.account_balance,
                  color: AppColors.primary,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _organizationName(organization),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InvalidQrMessage extends StatelessWidget {
  const _InvalidQrMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _organizationName(Map<String, dynamic> organization) {
  final arabicName = organization['officialNameArabic'];
  if (arabicName is String && arabicName.trim().isNotEmpty) return arabicName;
  final shortName = organization['shortName'];
  if (shortName is String && shortName.trim().isNotEmpty) return shortName;
  final displayName = organization['displayName'];
  if (displayName is Map && displayName['ar'] is String) {
    return displayName['ar'] as String;
  }
  return organization['organizationId'] as String;
}

String _organizationDescription(Map<String, dynamic> organization) {
  final description = organization['description'];
  if (description is Map && description['ar'] is String) {
    return description['ar'] as String;
  }
  if (description is String) return description;
  return '';
}
