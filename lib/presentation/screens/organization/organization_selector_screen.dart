import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/role_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/membership_model.dart';
import '../../../providers/app_providers.dart';
import '../../../features/membership_request/data/membership_request_model.dart';
import '../../../features/membership_request/providers/membership_request_providers.dart';

class OrganizationSelectorScreen extends ConsumerStatefulWidget {
  const OrganizationSelectorScreen({super.key});

  @override
  ConsumerState<OrganizationSelectorScreen> createState() =>
      _OrganizationSelectorScreenState();
}

class _OrganizationSelectorScreenState
    extends ConsumerState<OrganizationSelectorScreen> {
  bool _isSelecting = false;
  String? _selectionError;
  String? _scheduledAutoSelection;

  Future<void> _selectOrganization(MembershipModel membership) async {
    if (_isSelecting) return;

    setState(() {
      _isSelecting = true;
      _selectionError = null;
    });

    try {
      await ref.read(organizationContextProvider.notifier).selectOrganization(
            organizationId: membership.organizationId,
            userId: membership.userId,
          );
      if (!mounted) return;
      context.goNamed('dashboard');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSelecting = false;
        _selectionError = _friendlyLoadError(error);
      });
    }
  }

  void _scheduleAutomaticSelection(MembershipModel membership) {
    final selectionKey = '${membership.organizationId}:${membership.id}';
    if (_scheduledAutoSelection == selectionKey) return;
    _scheduledAutoSelection = selectionKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectOrganization(membership);
    });
  }

  void _retryAutomaticSelection(MembershipModel membership) {
    setState(() {
      _scheduledAutoSelection = null;
      _selectionError = null;
    });
    _scheduleAutomaticSelection(membership);
  }

  void _showJoinRequestNotice() {
    context.pushNamed('joinRequest');
  }

  void _retryCurrentMember() {
    ref.invalidate(currentMemberProvider);
  }

  void _retryMembershipData(String userId) {
    ref.invalidate(userMembershipsProvider(userId));
    ref.invalidate(userMembershipRequestsProvider(userId));
  }

  @override
  Widget build(BuildContext context) {
    final currentMember = ref.watch(currentMemberProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('اختيار المجلس'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: true,
        ),
        body: currentMember.when(
          loading: () => const _CenteredProgress(),
          error: (error, _) => _LoadError(
            message: _friendlyLoadError(error),
            onRetry: _retryCurrentMember,
          ),
          data: (member) {
            if (member == null) {
              return _LoadError(
                message: 'تعذر العثور على بيانات المستخدم',
                onRetry: _retryCurrentMember,
              );
            }

            final memberships =
                ref.watch(userMembershipsProvider(member.userId));
            final requests =
                ref.watch(userMembershipRequestsProvider(member.userId));
            return memberships.when(
              loading: () => const _CenteredProgress(),
              error: (error, _) => _LoadError(
                message: _friendlyLoadError(error),
                onRetry: () => _retryMembershipData(member.userId),
              ),
              data: (items) => requests.when(
                loading: () => const _CenteredProgress(),
                error: (error, _) {
                  final hasActiveMembership = items.any(
                    (membership) =>
                        membership.status == MembershipStatus.active,
                  );
                  if (!hasActiveMembership) {
                    return _NoActiveMemberships(
                      pendingMemberships: items
                          .where(
                            (membership) =>
                                membership.status == MembershipStatus.pending,
                          )
                          .toList(),
                      pendingRequests: const [],
                      notice: _friendlyLoadError(error),
                      onRetry: () => _retryMembershipData(member.userId),
                      onJoinRequested: _showJoinRequestNotice,
                    );
                  }
                  return _LoadError(
                    message: _friendlyLoadError(error),
                    onRetry: () => _retryMembershipData(member.userId),
                  );
                },
                data: (requestItems) =>
                    _buildMembershipState(items, requestItems),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMembershipState(
    List<MembershipModel> memberships,
    List<MembershipRequestModel> requests,
  ) {
    final active = memberships
        .where((membership) => membership.status == MembershipStatus.active)
        .toList();
    final pending = memberships
        .where((membership) => membership.status == MembershipStatus.pending)
        .toList();
    final pendingRequests = requests
        .where(
          (request) => request.status == MembershipRequestStatus.pending,
        )
        .toList();

    if (active.length == 1) {
      final membership = active.single;
      _scheduleAutomaticSelection(membership);
      return _AutomaticSelection(
        error: _selectionError,
        onRetry: () => _retryAutomaticSelection(membership),
      );
    }

    if (active.length > 1) {
      return _MembershipList(
        memberships: [...active, ...pending],
        pendingRequests: pendingRequests,
        isSelecting: _isSelecting,
        onSelected: _selectOrganization,
      );
    }

    return _NoActiveMemberships(
      pendingMemberships: pending,
      pendingRequests: pendingRequests,
      onJoinRequested: _showJoinRequestNotice,
    );
  }
}

class _MembershipList extends StatelessWidget {
  const _MembershipList({
    required this.memberships,
    required this.pendingRequests,
    required this.isSelecting,
    required this.onSelected,
  });

  final List<MembershipModel> memberships;
  final List<MembershipRequestModel> pendingRequests;
  final bool isSelecting;
  final ValueChanged<MembershipModel> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'اختر المجلس الذي تريد الدخول إليه',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 16),
        for (final membership in memberships)
          _OrganizationCard(
            membership: membership,
            enabled:
                !isSelecting && membership.status == MembershipStatus.active,
            onTap: () => onSelected(membership),
          ),
        for (final request in pendingRequests)
          _PendingRequestCard(request: request),
      ],
    );
  }
}

class _NoActiveMemberships extends StatelessWidget {
  const _NoActiveMemberships({
    required this.pendingMemberships,
    required this.pendingRequests,
    required this.onJoinRequested,
    this.notice,
    this.onRetry,
  });

  final List<MembershipModel> pendingMemberships;
  final List<MembershipRequestModel> pendingRequests;
  final VoidCallback onJoinRequested;
  final String? notice;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.groups_outlined,
          size: 72,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 20),
        const Text(
          'ليس لديك عضوية في أي مجلس',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        if (notice != null) ...[
          const SizedBox(height: 16),
          Text(
            notice!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.orange),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ],
        if (pendingMemberships.isNotEmpty || pendingRequests.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text(
            'طلبات قيد المراجعة',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final membership in pendingMemberships)
            _OrganizationCard(
              membership: membership,
              enabled: false,
              onTap: () {},
            ),
          for (final request in pendingRequests)
            _PendingRequestCard(request: request),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onJoinRequested,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('طلب الانضمام إلى مجلس'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _PendingRequestCard extends ConsumerStatefulWidget {
  const _PendingRequestCard({required this.request});

  final MembershipRequestModel request;

  @override
  ConsumerState<_PendingRequestCard> createState() =>
      _PendingRequestCardState();
}

class _PendingRequestCardState extends ConsumerState<_PendingRequestCard> {
  late Future<Map<String, dynamic>?> _organization;

  @override
  void initState() {
    super.initState();
    _organization = ref
        .read(organizationRepositoryProvider)
        .getById(widget.request.organizationId);
  }

  @override
  void didUpdateWidget(covariant _PendingRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.organizationId != widget.request.organizationId) {
      _organization = ref
          .read(organizationRepositoryProvider)
          .getById(widget.request.organizationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _organization,
      builder: (context, snapshot) {
        final organization = snapshot.data ?? const <String, dynamic>{};
        final arabicName = _organizationName(
          organization,
          languageCode: 'ar',
          fallback: widget.request.organizationId,
        );
        final englishName = _organizationName(
          organization,
          languageCode: 'en',
          fallback: '',
        );
        final logo = organization['logo'] ?? organization['logoUrl'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _OrganizationLogo(value: logo is String ? logo : null),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arabicName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (englishName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          englishName,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text('الدور المطلوب: ${widget.request.requestedRole}'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const _StatusChip(status: MembershipStatus.pending),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OrganizationCard extends ConsumerStatefulWidget {
  const _OrganizationCard({
    required this.membership,
    required this.enabled,
    required this.onTap,
  });

  final MembershipModel membership;
  final bool enabled;
  final VoidCallback onTap;

  @override
  ConsumerState<_OrganizationCard> createState() => _OrganizationCardState();
}

class _OrganizationCardState extends ConsumerState<_OrganizationCard> {
  late Future<_OrganizationCardData> _data;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  @override
  void didUpdateWidget(covariant _OrganizationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membership.organizationId !=
            widget.membership.organizationId ||
        oldWidget.membership.roleId != widget.membership.roleId) {
      _data = _loadData();
    }
  }

  Future<_OrganizationCardData> _loadData() async {
    final organizationRepository = ref.read(organizationRepositoryProvider);
    final roleRepository = ref.read(roleRepositoryProvider);
    final results = await Future.wait<dynamic>([
      organizationRepository.getById(widget.membership.organizationId),
      roleRepository.getById(
        organizationId: widget.membership.organizationId,
        roleId: widget.membership.roleId,
      ),
    ]);

    return _OrganizationCardData(
      organization: results[0] as Map<String, dynamic>?,
      role: results[1] as Map<String, dynamic>?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OrganizationCardData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            margin: EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 132,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final data = snapshot.data;
        final organization = data?.organization ?? const <String, dynamic>{};
        final role = data?.role ?? const <String, dynamic>{};
        final arabicName = _organizationName(
          organization,
          languageCode: 'ar',
          fallback: widget.membership.organizationId,
        );
        final englishName = _organizationName(
          organization,
          languageCode: 'en',
          fallback: '',
        );
        final roleName = roleLabelArabic(
          widget.membership.roleId,
          role: widget.membership.role,
          fallback: _localizedValue(
            role['roleName'],
            languageCode: 'ar',
            fallback: widget.membership.roleId,
          ),
        );
        final logo = organization['logo'] ?? organization['logoUrl'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: widget.enabled ? 2 : 0,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _OrganizationLogo(value: logo is String ? logo : null),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          arabicName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (englishName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            englishName,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text('رقم العضو: ${widget.membership.memberNumber}'),
                        const SizedBox(height: 3),
                        Text('الدور: $roleName'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: widget.membership.status),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrganizationLogo extends StatelessWidget {
  const _OrganizationLogo({this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    final uri = value == null ? null : Uri.tryParse(value!);
    final isNetworkImage =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: isNetworkImage
          ? Image.network(
              value!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _OrganizationIcon(),
            )
          : const _OrganizationIcon(),
    );
  }
}

class _OrganizationIcon extends StatelessWidget {
  const _OrganizationIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.account_balance,
      color: AppColors.primary,
      size: 32,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MembershipStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      MembershipStatus.active => ('نشط', Colors.green),
      MembershipStatus.pending => ('قيد المراجعة', Colors.orange),
      MembershipStatus.suspended => ('موقوف', Colors.red),
      MembershipStatus.rejected => ('مرفوض', Colors.red),
      MembershipStatus.resigned => ('منسحب', Colors.grey),
      MembershipStatus.removed => ('تمت الإزالة', Colors.grey),
      MembershipStatus.cancelled => ('ملغى', Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AutomaticSelection extends StatelessWidget {
  const _AutomaticSelection({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const _CenteredProgress();
    return _LoadError(message: error!, onRetry: onRetry);
  }
}

class _CenteredProgress extends StatelessWidget {
  const _CenteredProgress();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
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

class _OrganizationCardData {
  const _OrganizationCardData({
    required this.organization,
    required this.role,
  });

  final Map<String, dynamic>? organization;
  final Map<String, dynamic>? role;
}

String _organizationName(
  Map<String, dynamic> organization, {
  required String languageCode,
  required String fallback,
}) {
  final directKey =
      languageCode == 'ar' ? 'officialNameArabic' : 'officialNameEnglish';
  final directValue = organization[directKey];
  if (directValue is String && directValue.trim().isNotEmpty) {
    return directValue;
  }
  return _localizedValue(
    organization['displayName'],
    languageCode: languageCode,
    fallback: fallback,
  );
}

String _localizedValue(
  dynamic value, {
  required String languageCode,
  required String fallback,
}) {
  if (value is String && value.trim().isNotEmpty) return value;
  if (value is Map) {
    final localized = value[languageCode];
    if (localized is String && localized.trim().isNotEmpty) return localized;
  }
  return fallback;
}

String _friendlyLoadError(Object error) {
  if (error is FirebaseException && error.code == 'failed-precondition') {
    return 'يتم تجهيز بيانات المجالس، حاول مرة أخرى بعد قليل';
  }
  return 'تعذر تحميل بيانات المجالس. حاول مرة أخرى.';
}
