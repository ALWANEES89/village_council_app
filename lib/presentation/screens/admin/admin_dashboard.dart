import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/dashboard/system_dashboard_metrics.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});

  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _councilsKey = GlobalKey();
  String _query = '';
  String? _openingId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final access = ref.watch(systemOwnerAccessProvider);
    if (access.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (access.hasError || access.valueOrNull != true) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.systemAdministration),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline,
                  size: 56, color: AppColors.primary),
              const SizedBox(height: 14),
              Text(l.systemAccessDenied, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.goNamed('memberHome'),
                child: Text(l.returnHome),
              ),
            ]),
          ),
        ),
      );
    }

    final organizationsState = ref.watch(allOrganizationsProvider);
    final summaryState = ref.watch(systemDashboardSummaryProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = user == null
        ? null
        : ref.watch(userProfileProvider(user.uid)).valueOrNull;
    final language = Localizations.localeOf(context).languageCode;
    final query = _query.trim().toLowerCase();
    final organizations = (organizationsState.valueOrNull ?? const [])
        .where((org) => query.isEmpty || _searchText(org).contains(query))
        .toList();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FB),
      drawer: _SystemDrawer(
        onHome: () => _closeDrawerAndScroll(null),
        onCouncils: () => _closeDrawerAndScroll(_councilsKey),
      ),
      appBar: AppBar(
        title: Text(l.systemAdministration),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allOrganizationsProvider);
          ref.invalidate(systemDashboardSummaryProvider);
          await ref.read(allOrganizationsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SystemHeader(
              name: profile?.fullName ?? user?.displayName ?? l.systemOwner,
              photoUrl: profile?.photoUrl,
              onProfile: () => context.pushNamed('profileEdit'),
            ),
            const SizedBox(height: 18),
            _SystemSummary(state: summaryState),
            const SizedBox(height: 20),
            _QuickActions(
              onCreate: () => context.pushNamed('createOrganization'),
              onManage: () => context.pushNamed('organizationsManagement'),
            ),
            const SizedBox(height: 20),
            _SystemAlerts(state: summaryState),
            const SizedBox(height: 20),
            KeyedSubtree(
              key: _councilsKey,
              child: _Heading(
                title: l.councilsInSystem,
                subtitle: l.councilsInSystemDescription,
                icon: Icons.account_balance_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.searchCouncils,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            if (organizationsState.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (organizationsState.hasError)
              _Message(
                icon: Icons.cloud_off_outlined,
                text: l.couldNotLoad,
                action: l.retry,
                onTap: () => ref.invalidate(allOrganizationsProvider),
              )
            else if (organizations.isEmpty)
              _Message(icon: Icons.inbox_outlined, text: l.noCouncils)
            else
              for (final org in organizations) ...[
                _CouncilCard(
                  organization: org,
                  language: language,
                  counts: summaryState
                      .valueOrNull?.countsByOrganization[org['organizationId']],
                  opening: _openingId == org['organizationId'],
                  onOpen: () => _openCouncil(org),
                  onManage: () => context.pushNamed(
                    'createOrganization',
                    extra: org,
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _openCouncil(Map<String, dynamic> organization) async {
    final l = AppLocalizations.of(context);
    final id = organization['organizationId'] as String;
    if (_openingId != null || organization['status'] != 'active') return;
    setState(() => _openingId = id);
    try {
      await ref
          .read(organizationContextProvider.notifier)
          .selectOrganizationAsSuperAdmin(id);
      if (mounted) context.pushNamed('councilDashboard');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.couldNotOpenCouncil)));
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _closeDrawerAndScroll(GlobalKey? key) async {
    _scaffoldKey.currentState?.closeDrawer();
    if (key == null) {
      PrimaryScrollController.maybeOf(context)?.animateTo(0,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final target = key.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }
}

class _SystemHeader extends StatelessWidget {
  const _SystemHeader(
      {required this.name, this.photoUrl, required this.onProfile});
  final String name;
  final String? photoUrl;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasPhoto = photoUrl?.trim().isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF123A78), Color(0xFF246BCE)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x24123A78), blurRadius: 22, offset: Offset(0, 9)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(
            radius: 27,
            backgroundColor: Colors.white,
            child: Icon(Icons.public, color: Color(0xFF1769E0), size: 29),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.systemAdministration,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold)),
              Text(l.systemAdministrationDescription,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Material(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onProfile,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                CircleAvatar(
                  radius: 21,
                  foregroundImage:
                      hasPhoto ? NetworkImage(photoUrl!.trim()) : null,
                  child: hasPhoto ? null : const Icon(Icons.person_outline),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        Text(l.systemOwner,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ]),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SystemSummary extends StatelessWidget {
  const _SystemSummary({required this.state});
  final AsyncValue<SystemDashboardSummary> state;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final value = state.valueOrNull;
    final cards = [
      _Stat(
          l.totalCouncils,
          state.isLoading ? null : '${value?.totalCouncils ?? '—'}',
          Icons.account_balance_outlined,
          const Color(0xFF1769E0)),
      _Stat(
          l.activeCouncils,
          state.isLoading ? null : '${value?.activeCouncils ?? '—'}',
          Icons.verified_outlined,
          const Color(0xFF0A8F63)),
      _Stat(
          l.pendingActions,
          state.isLoading ? null : '${value?.pendingActions ?? '—'}',
          Icons.pending_actions_outlined,
          const Color(0xFFE06B17)),
    ];
    return LayoutBuilder(builder: (_, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final card in cards)
          SizedBox(width: width, child: _StatCard(data: card)),
      ]);
    });
  }
}

class _Stat {
  const _Stat(this.title, this.value, this.icon, this.color);
  final String title;
  final String? value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _Stat data;
  @override
  Widget build(BuildContext context) => Container(
        height: 138,
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              backgroundColor: data.color.withValues(alpha: .1),
              child: Icon(data.icon, color: data.color)),
          const Spacer(),
          if (data.value == null)
            const SizedBox.square(
                dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Text(data.value!,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
        ]),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onCreate, required this.onManage});
  final VoidCallback onCreate;
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Heading(title: l.quickActions, icon: Icons.bolt_outlined),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: _Action(Icons.add_business_outlined, l.createCouncil,
                const Color(0xFF0A8F63), onCreate)),
        const SizedBox(width: 12),
        Expanded(
            child: _Action(Icons.account_balance_outlined, l.manageCouncils,
                const Color(0xFF1769E0), onManage)),
      ]),
    ]);
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.title, this.color, this.onTap);
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 108,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 29),
                    const SizedBox(height: 9),
                    Text(title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ]),
            ),
          ),
        ),
      );
}

class _SystemAlerts extends StatelessWidget {
  const _SystemAlerts({required this.state});
  final AsyncValue<SystemDashboardSummary> state;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pending = state.valueOrNull?.pendingActions;
    final child = state.isLoading
        ? const Center(child: CircularProgressIndicator())
        : state.hasError || pending == null
            ? _Inline(Icons.cloud_off_outlined, l.couldNotLoad)
            : pending == 0
                ? _Inline(Icons.check_circle_outline, l.noSystemAlerts)
                : Row(children: [
                    const Icon(Icons.pending_actions_outlined,
                        color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.pendingActionsAlert)),
                    Badge(label: Text('$pending')),
                  ]);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Heading(
            title: l.systemAlerts, icon: Icons.notification_important_outlined),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _CouncilCard extends StatelessWidget {
  const _CouncilCard({
    required this.organization,
    required this.language,
    required this.counts,
    required this.opening,
    required this.onOpen,
    required this.onManage,
  });
  final Map<String, dynamic> organization;
  final String language;
  final Map<String, int>? counts;
  final bool opening;
  final VoidCallback onOpen;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = organization['status'] as String? ?? 'inactive';
    final active = status == 'active';
    final logo = organization['logoUrl'] as String?;
    final created = organization['createdAt'];
    final date = created is Timestamp
        ? DateFormat.yMd(language).format(created.toDate())
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFFEAF3FF),
            foregroundImage:
                logo?.isNotEmpty == true ? NetworkImage(logo!) : null,
            child: logo?.isNotEmpty == true
                ? null
                : const Icon(Icons.account_balance_outlined,
                    color: Color(0xFF1769E0)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_organizationName(organization, language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              _Status(label: _statusLabel(status, l), active: active),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 14, runSpacing: 8, children: [
          _Meta(
              Icons.groups_outlined,
              counts == null
                  ? '${l.members}: —'
                  : '${l.members}: ${counts!['members'] ?? 0}'),
          if (date != null)
            _Meta(Icons.calendar_today_outlined, '${l.createdOn}: $date'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: active && !opening ? onOpen : null,
              icon: opening
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.open_in_new, size: 18),
              label: Text(l.openCouncil),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: Text(l.manage),
          ),
        ]),
      ]),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.active});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE7F8F2) : const Color(0xFFFFF0E8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color:
                    active ? const Color(0xFF087A55) : const Color(0xFFC45117),
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      );
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: const Color(0xFF667085)),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
      ]);
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.icon, this.subtitle});
  final String title;
  final String? subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFEAF3FF),
          child: Icon(icon, color: const Color(0xFF1769E0)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null)
              Text(subtitle!,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF667085))),
          ]),
        ),
      ]);
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon, required this.text, this.action, this.onTap});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(),
        child: Column(children: [
          Icon(icon, size: 38, color: const Color(0xFF98A2B3)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
          if (onTap != null && action != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onTap, child: Text(action!)),
          ],
        ]),
      );
}

class _Inline extends StatelessWidget {
  const _Inline(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFF98A2B3)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(text, style: const TextStyle(color: Color(0xFF667085)))),
      ]);
}

class _SystemDrawer extends StatelessWidget {
  const _SystemDrawer({required this.onHome, required this.onCouncils});
  final VoidCallback onHome;
  final VoidCallback onCouncils;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NavigationDrawer(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFEAF3FF),
            child: Icon(Icons.public, color: Color(0xFF1769E0), size: 30),
          ),
          const SizedBox(height: 12),
          Text(l.systemAdministration,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(l.systemOwner,
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
        ]),
      ),
      const Divider(),
      ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(l.systemHome),
          onTap: onHome),
      ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: Text(l.manageCouncils),
          onTap: onCouncils),
    ]);
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE6EBF2)),
      boxShadow: const [
        BoxShadow(
            color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
      ],
    );

String _organizationName(Map<String, dynamic> organization, String locale) {
  final preferred = locale == 'en'
      ? organization['officialNameEnglish']
      : organization['officialNameArabic'];
  if (preferred is String && preferred.trim().isNotEmpty) return preferred;
  final fallback = locale == 'en'
      ? organization['officialNameArabic']
      : organization['officialNameEnglish'];
  if (fallback is String && fallback.trim().isNotEmpty) return fallback;
  return organization['shortName'] as String? ??
      organization['organizationId'] as String? ??
      '-';
}

String _searchText(Map<String, dynamic> organization) => [
      organization['officialNameArabic'],
      organization['officialNameEnglish'],
      organization['shortName'],
    ].whereType<String>().join(' ').toLowerCase();

String _statusLabel(String status, AppLocalizations l) => switch (status) {
      'active' => l.active,
      'archived' => l.archived,
      'suspended' => l.suspended,
      _ => l.inactive,
    };
