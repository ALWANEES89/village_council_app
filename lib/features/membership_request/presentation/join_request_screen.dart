import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/membership_model.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../l10n/generated/app_localizations.dart';
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
  final _searchController = TextEditingController();

  String? _organizationId;
  bool _didPrefill = false;
  bool _isResolvingQr = false;
  String? _qrError;
  Map<String, dynamic>? _qrOrganization;
  bool _isPickingOrganization = false;

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
    _searchController.dispose();
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

  Future<void> _submit(MemberModel member) async {
    if (ref.read(membershipRequestSubmissionProvider).isSubmitting) return;
    if (_formKey.currentState?.validate() != true) return;
    final organizationId = _organizationId;
    if (organizationId == null || organizationId.trim().isEmpty) return;

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
      final strings = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.joinRequestSent)),
      );
      ref.read(membershipRequestSubmissionProvider.notifier).reset();
    }
  }

  Future<void> _submitForOrganization(
    MemberModel member,
    String organizationId,
  ) async {
    if (organizationId.trim().isEmpty) return;
    setState(() => _organizationId = organizationId);
    await _submit(member);
  }

  Future<Map<String, dynamic>?> _pickOrganization(
    List<Map<String, dynamic>> organizations,
  ) async {
    if (_isPickingOrganization) return null;
    _isPickingOrganization = true;
    final searchController = TextEditingController();
    var query = '';
    var isClosing = false;
    try {
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = _normalizeSearchText(query);
            final filtered = normalizedQuery.isEmpty
                ? organizations
                : organizations.where((organization) {
                    final haystack = _normalizeSearchText(
                      '${_organizationName(organization)} '
                      '${_organizationDescription(organization)}',
                    );
                    return haystack.contains(normalizedQuery);
                  }).toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.48,
              maxChildSize: 0.92,
              expand: false,
              builder: (context, scrollController) => Material(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'اختر المجلس',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم المجلس',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البحث',
                                  onPressed: () {
                                    searchController.clear();
                                    setModalState(() => query = '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                        onChanged: (value) =>
                            setModalState(() => query = value),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('لا يوجد مجلس مطابق لبحثك'),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final organization = filtered[index];
                                final organizationId =
                                    organization['organizationId'] as String?;
                                final isSelected =
                                    organizationId == _organizationId;
                                return Card(
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      if (isClosing) return;
                                      isClosing = true;
                                      FocusScope.of(context).unfocus();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                        (_) {
                                          if (context.mounted) {
                                            Navigator.of(context)
                                                .pop(organization);
                                          }
                                        },
                                      );
                                    },
                                    contentPadding: const EdgeInsets.all(10),
                                    title: _OrganizationChoiceContent(
                                      organization: organization,
                                    ),
                                    trailing: Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.chevron_left,
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.grey,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      return selected;
    } finally {
      searchController.dispose();
      _isPickingOrganization = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final memberAsync = ref.watch(currentMemberProvider);
    final userId = ref.watch(authStateProvider).value?.uid;
    final profileAsync =
        userId == null ? null : ref.watch(userProfileProvider(userId));
    final submission = ref.watch(membershipRequestSubmissionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(strings.findAndJoinCouncil),
        actions: [
          IconButton(
            tooltip: strings.myAccount,
            onPressed: () => context.pushNamed('myAccount'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
        centerTitle: true,
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: memberAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ScreenMessage(message: strings.couldNotLoadAccount),
        data: (member) {
          if (member == null || userId == null) {
            return _ScreenMessage(message: strings.couldNotFindUser);
          }
          if (profileAsync?.isLoading == true) {
            return const Center(child: CircularProgressIndicator());
          }
          if (profileAsync?.hasError == true) {
            return _ScreenMessage(message: strings.couldNotLoadProfile);
          }
          _prefill(member, profileAsync?.asData?.value);
          if (_isQrFlow) {
            if (_isResolvingQr) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_qrError != null || _qrOrganization == null) {
              return _InvalidQrMessage(message: strings.invalidJoinCode);
            }
            return _buildForm(
              member: member,
              organizations: [_qrOrganization!],
              submission: submission,
              organizationLocked: true,
            );
          }

          final organizationsAsync = ref.watch(organizationsProvider);
          final requestsAsync =
              ref.watch(userMembershipRequestsProvider(userId));
          final membershipsAsync =
              ref.watch(activeUserMembershipsProvider(userId));
          if (requestsAsync.isLoading || membershipsAsync.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (requestsAsync.hasError) {
            return _OrganizationLoadState(
              message: strings.couldNotLoadJoinRequests,
              onRetry: () =>
                  ref.invalidate(userMembershipRequestsProvider(userId)),
              retryLabel: strings.retry,
            );
          }
          if (membershipsAsync.hasError ||
              membershipsAsync.valueOrNull?.loadFailed == true) {
            return _OrganizationLoadState(
              message: strings.couldNotLoadAccount,
              onRetry: () =>
                  ref.invalidate(activeUserMembershipsProvider(userId)),
              retryLabel: strings.retry,
            );
          }
          return organizationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => _OrganizationLoadState(
              message: strings.couldNotLoadCouncils,
              onRetry: () => ref.invalidate(organizationsProvider),
              retryLabel: strings.retry,
            ),
            data: (organizations) => _buildCouncilDiscovery(
              member: member,
              organizations: organizations,
              requests: requestsAsync.valueOrNull ?? const [],
              activeMemberships:
                  membershipsAsync.valueOrNull?.memberships ?? const [],
              submission: submission,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCouncilDiscovery({
    required MemberModel member,
    required List<Map<String, dynamic>> organizations,
    required List<MembershipRequestModel> requests,
    required List<MembershipModel> activeMemberships,
    required MembershipRequestSubmissionState submission,
  }) {
    final strings = AppLocalizations.of(context);
    final filtered = organizations
        .where((organization) => organizationMatchesJoinQuery(
              organization,
              _searchController.text,
            ))
        .toList(growable: false);
    final requestsByOrganization = <String, MembershipRequestModel>{
      for (final request in requests) request.organizationId: request,
    };
    final joinedOrganizations = activeMemberships
        .where((membership) => membership.status == MembershipStatus.active)
        .map((membership) => membership.organizationId)
        .toSet();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            strings.findAndJoinCouncil,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
          ),
          const SizedBox(height: 6),
          Text(strings.findCouncilDescription),
          const SizedBox(height: 18),
          TextField(
            key: const Key('joinCouncilSearchField'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: strings.searchByCouncilName,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: strings.close,
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (organizations.isEmpty)
            _InlineEmptyState(message: strings.noCouncilsAvailableToJoin)
          else if (filtered.isEmpty)
            _InlineEmptyState(message: strings.noMatchingCouncils)
          else
            for (final organization in filtered) ...[
              _CouncilJoinCard(
                organization: organization,
                request: requestsByOrganization[
                    organization['organizationId'] as String?],
                alreadyJoined: joinedOrganizations
                    .contains(organization['organizationId'] as String?),
                isSubmitting: submission.isSubmitting &&
                    _organizationId == organization['organizationId'],
                onJoin: () => _submitForOrganization(
                  member,
                  organization['organizationId'] as String? ?? '',
                ),
              ),
              const SizedBox(height: 10),
            ],
          if (submission.failure != null) ...[
            const SizedBox(height: 10),
            Text(
              _submissionFailureText(strings, submission.failure!),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm({
    required MemberModel member,
    required List<Map<String, dynamic>> organizations,
    required MembershipRequestSubmissionState submission,
    bool organizationLocked = false,
  }) {
    final strings = AppLocalizations.of(context);
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
              builder: (field) {
                final selected =
                    organizations.cast<Map<String, dynamic>?>().firstWhere(
                          (organization) =>
                              organization?['organizationId'] == field.value,
                          orElse: () => null,
                        );
                return InkWell(
                  onTap: submission.isSubmitting || _isPickingOrganization
                      ? null
                      : () async {
                          final organization =
                              await _pickOrganization(organizations);
                          if (organization == null || !mounted) return;
                          final value =
                              organization['organizationId'] as String?;
                          if (value == null || value.trim().isEmpty) return;
                          setState(() => _organizationId = value);
                          field.didChange(value);
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'اختر المجلس',
                      prefixIcon: const Icon(Icons.search),
                      errorText: field.errorText,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected == null
                                ? 'اضغط للبحث واختيار المجلس'
                                : _organizationName(selected),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected == null
                                  ? Colors.grey.shade600
                                  : Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
                              fontWeight: selected == null
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (submission.failure != null) ...[
            const SizedBox(height: 16),
            Text(
              _submissionFailureText(strings, submission.failure!),
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
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_outlined,
              size: 56,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(
              Icons.account_balance_outlined,
              size: 54,
              color: AppColors.primary,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _CouncilJoinCard extends StatelessWidget {
  const _CouncilJoinCard({
    required this.organization,
    required this.request,
    required this.alreadyJoined,
    required this.isSubmitting,
    required this.onJoin,
  });

  final Map<String, dynamic> organization;
  final MembershipRequestModel? request;
  final bool alreadyJoined;
  final bool isSubmitting;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final organizationId = organization['organizationId'] as String? ?? '';
    final status = alreadyJoined
        ? _JoinActionStatus.joined
        : switch (request?.status) {
            MembershipRequestStatus.pending => _JoinActionStatus.pending,
            MembershipRequestStatus.approved => _JoinActionStatus.approved,
            MembershipRequestStatus.rejected => _JoinActionStatus.rejected,
            _ => _JoinActionStatus.available,
          };
    final shortName = organization['shortName'];
    final shortNameText = shortName is String ? shortName.trim() : '';
    final displayedName = _organizationNameForLocale(
      organization,
      Localizations.localeOf(context).languageCode,
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OrganizationChoiceContent(organization: organization),
            if (shortNameText.isNotEmpty && shortNameText != displayedName) ...[
              const SizedBox(height: 8),
              Text(
                shortNameText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: Key('joinCouncilAction_$organizationId'),
              onPressed: status == _JoinActionStatus.available && !isSubmitting
                  ? onJoin
                  : null,
              icon: isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_joinActionIcon(status)),
              label: Text(_joinActionLabel(strings, status)),
            ),
          ],
        ),
      ),
    );
  }
}

enum _JoinActionStatus { available, pending, approved, rejected, joined }

IconData _joinActionIcon(_JoinActionStatus status) => switch (status) {
      _JoinActionStatus.available => Icons.person_add_alt_1_outlined,
      _JoinActionStatus.pending => Icons.schedule_outlined,
      _JoinActionStatus.approved ||
      _JoinActionStatus.joined =>
        Icons.check_circle_outline,
      _JoinActionStatus.rejected => Icons.cancel_outlined,
    };

String _joinActionLabel(
  AppLocalizations strings,
  _JoinActionStatus status,
) =>
    switch (status) {
      _JoinActionStatus.available => strings.requestToJoin,
      _JoinActionStatus.pending => strings.joinRequestPending,
      _JoinActionStatus.approved => strings.joinRequestApproved,
      _JoinActionStatus.rejected => strings.joinRequestRejected,
      _JoinActionStatus.joined => strings.alreadyJoined,
    };

String _submissionFailureText(
  AppLocalizations strings,
  MembershipRequestSubmissionFailure failure,
) =>
    switch (failure) {
      MembershipRequestSubmissionFailure.duplicatePending =>
        strings.joinRequestAlreadyPending,
      MembershipRequestSubmissionFailure.activeMembership =>
        strings.activeMembershipAlreadyExists,
      MembershipRequestSubmissionFailure.unavailable =>
        strings.couldNotSendJoinRequest,
    };

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
                _organizationNameForLocale(
                  organization,
                  Localizations.localeOf(context).languageCode,
                ),
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

String _normalizeSearchText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه');

bool organizationMatchesJoinQuery(
  Map<String, dynamic> organization,
  String query,
) {
  final normalizedQuery = _normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;
  final searchable = [
    organization['officialNameArabic'],
    organization['officialNameEnglish'],
    organization['shortName'],
  ].whereType<String>().join(' ');
  return _normalizeSearchText(searchable).contains(normalizedQuery);
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

String _organizationNameForLocale(
  Map<String, dynamic> organization,
  String languageCode,
) {
  final preferred = languageCode == 'en'
      ? organization['officialNameEnglish']
      : organization['officialNameArabic'];
  final fallback = languageCode == 'en'
      ? organization['officialNameArabic']
      : organization['officialNameEnglish'];
  for (final value in [preferred, fallback, organization['shortName']]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return organization['organizationId'] as String? ?? '';
}

String _organizationDescription(Map<String, dynamic> organization) {
  final description = organization['description'];
  if (description is Map && description['ar'] is String) {
    return description['ar'] as String;
  }
  if (description is String) return description;
  return '';
}
