import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/membership_model.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/main_bottom_navigation.dart';
import 'council_booking_screen.dart';

class MyAccountScreen extends ConsumerWidget {
  const MyAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).valueOrNull ??
        ref.read(authServiceProvider).currentUser;
    if (user == null) {
      return Scaffold(body: Center(child: Text(strings.systemAccessDenied)));
    }
    final profile = ref.watch(userProfileProvider(user.uid)).valueOrNull;
    final memberships = ref
            .watch(activeUserMembershipsProvider(user.uid))
            .valueOrNull
            ?.memberships ??
        const <MembershipModel>[];
    final councilContext = ref.watch(organizationContextProvider);
    final membership = councilContext.currentMembership ??
        (memberships.isEmpty ? null : memberships.first);
    final organizations =
        ref.watch(organizationsProvider).valueOrNull ?? const [];
    final organization = councilContext.currentOrganization ??
        _organizationFor(organizations, membership?.organizationId);
    final locale = Localizations.localeOf(context).languageCode;
    final councilName = organization == null
        ? null
        : _localizedOrganizationName(organization, locale);
    final name = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : user.displayName ?? strings.member;

    Future<bool> selectMembership() async {
      if (membership == null) return false;
      if (councilContext.currentMembership?.id == membership.id &&
          councilContext.currentMembership?.organizationId ==
              membership.organizationId) {
        return true;
      }
      await ref.read(organizationContextProvider.notifier).selectOrganization(
            organizationId: membership.organizationId,
            userId: membership.userId,
            membershipId: membership.id,
          );
      return context.mounted;
    }

    Future<void> openBooking() async {
      if (membership != null && !await selectMembership()) return;
      if (!context.mounted) return;
      context.pushNamed(
        'rentalPlaceholder',
        extra: CouncilBookingArguments(
          organizationId: membership?.organizationId,
          membershipId: membership?.id,
        ),
      );
    }

    Future<void> openPayments() async {
      if (membership == null || !await selectMembership()) return;
      if (context.mounted) context.pushNamed('dashboard');
    }

    Future<void> signOut() async {
      ref.read(organizationContextProvider.notifier).clearOrganization();
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) context.goNamed('login');
    }

    Future<void> openContact() async {
      final phone = organization?['phone'] as String?;
      final email = organization?['email'] as String?;
      final uri = phone?.trim().isNotEmpty == true
          ? Uri(scheme: 'tel', path: phone!.trim())
          : email?.trim().isNotEmpty == true
              ? Uri(scheme: 'mailto', path: email!.trim())
              : null;
      if (uri != null) await launchUrl(uri);
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(
        title: Text(strings.myAccount),
      ),
      bottomNavigationBar: MainBottomNavigation(
        selectedIndex: 4,
        onSelected: (index) async {
          switch (index) {
            case 0:
              context.goNamed('memberHome');
              return;
            case 1:
              await openBooking();
              return;
            case 2:
              await openPayments();
              return;
            case 3:
              if (context.mounted) context.pushNamed('notifications');
              return;
            case 4:
              return;
          }
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _ProfileCard(
            name: name,
            photoUrl: profile?.photoUrl,
            councilName: councilName,
            memberNumber: membership?.memberNumber,
            role: membership == null
                ? null
                : _roleLabel(membership.roleId, strings),
            onEdit: () => context.pushNamed('profileEdit'),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: strings.accountSection,
            children: [
              _SettingsItem(
                icon: Icons.person_outline,
                title: strings.personalInformation,
                onTap: () => context.pushNamed('profileEdit'),
              ),
              _SettingsItem(
                icon: Icons.notifications_outlined,
                title: strings.notificationSettings,
                onTap: () => context.pushNamed('notificationSettings'),
              ),
              _LanguageSettingsItem(strings: strings),
            ],
          ),
          _SettingsSection(
            title: strings.councilsAndMemberships,
            children: [
              _SettingsItem(
                icon: Icons.account_balance_outlined,
                title: strings.myCouncils,
                subtitle: '${memberships.length}',
                onTap: () => context.goNamed('memberHome'),
              ),
              _SettingsItem(
                icon: Icons.add_business_outlined,
                title: strings.joinAnotherCouncil,
                onTap: () => context.pushNamed('joinRequest'),
              ),
              if (membership != null)
                _SettingsItem(
                  icon: Icons.badge_outlined,
                  title: strings.membershipDetails,
                  subtitle:
                      '${strings.memberNumber}: ${membership.memberNumber}',
                ),
              if (membership != null)
                _SettingsItem(
                  icon: Icons.admin_panel_settings_outlined,
                  title: strings.membershipsAndRoles,
                  subtitle: _roleLabel(membership.roleId, strings),
                ),
            ],
          ),
          _SettingsSection(
            title: strings.finance,
            children: [
              _SettingsItem(
                icon: Icons.receipt_long_outlined,
                title: strings.myPaymentsAndReceipts,
                onTap: () => context.pushNamed('receiptHistory'),
              ),
              _SettingsItem(
                icon: Icons.card_membership_outlined,
                title: strings.mySubscriptions,
                onTap: membership == null ? null : openPayments,
              ),
            ],
          ),
          _SettingsSection(
            title: strings.help,
            children: [
              _SettingsItem(
                icon: Icons.support_agent_outlined,
                title: strings.contactUs,
                onTap: organization?['phone'] != null ||
                        organization?['email'] != null
                    ? openContact
                    : null,
              ),
            ],
          ),
          _SettingsSection(
            title: strings.legal,
            children: [
              _SettingsItem(
                icon: Icons.info_outline,
                title: strings.aboutApp,
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: strings.appTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: signOut,
            icon: const Icon(Icons.logout),
            label: Text(strings.signOut),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.photoUrl,
    required this.councilName,
    required this.memberNumber,
    required this.role,
    required this.onEdit,
  });
  final String name;
  final String? photoUrl;
  final String? councilName;
  final String? memberNumber;
  final String? role;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(children: [
        CircleAvatar(
          radius: 42,
          foregroundImage: photoUrl?.trim().isNotEmpty == true
              ? NetworkImage(photoUrl!)
              : null,
          child: photoUrl?.trim().isNotEmpty == true
              ? null
              : const Icon(Icons.person_outline, size: 42),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        if (councilName != null)
          Text(councilName!, style: const TextStyle(color: Colors.white70)),
        if (role != null)
          Text(
            '${strings.basicMember} • $role',
            style: const TextStyle(color: Colors.white),
          ),
        if (memberNumber != null)
          Text(
            '${strings.memberNumber}: $memberNumber',
            style: const TextStyle(color: Colors.white70),
          ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonalIcon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: Text(strings.editProfile),
        ),
      ]),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ]),
      );
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 58,
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: onTap == null
            ? null
            : const Icon(Icons.arrow_forward_ios, size: 15),
        onTap: onTap,
      );
}

class _LanguageSettingsItem extends StatelessWidget {
  const _LanguageSettingsItem({required this.strings});
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 58,
        leading: const Icon(Icons.language, color: AppColors.primary),
        title: Text(strings.language),
        subtitle: Text(
          Localizations.localeOf(context).languageCode == 'ar'
              ? strings.arabic
              : strings.english,
        ),
        trailing: const LanguageSwitcher(compact: true),
      );
}

String _localizedOrganizationName(
  Map<String, dynamic> organization,
  String locale,
) {
  final names = locale == 'en'
      ? [
          organization['officialNameEnglish'],
          organization['officialNameArabic']
        ]
      : [
          organization['officialNameArabic'],
          organization['officialNameEnglish']
        ];
  for (final name in [...names, organization['shortName']]) {
    if (name is String && name.trim().isNotEmpty) return name.trim();
  }
  return organization['organizationId'] as String? ?? '-';
}

Map<String, dynamic>? _organizationFor(
  List<Map<String, dynamic>> organizations,
  String? organizationId,
) {
  if (organizationId == null) return null;
  for (final organization in organizations) {
    if (organization['organizationId'] == organizationId) return organization;
  }
  return null;
}

String _roleLabel(String roleId, AppLocalizations strings) => switch (roleId) {
      'owner' || 'council_owner' => strings.councilOwnerRole,
      'chairman' => strings.chairmanRole,
      'adminManager' => strings.administrativeManagerRole,
      'financialManager' => strings.financialManagerRole,
      'financialReviewer' => strings.financialReviewerRole,
      _ => strings.memberRole,
    };
