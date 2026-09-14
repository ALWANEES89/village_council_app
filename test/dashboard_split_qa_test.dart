import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dashboard split QA', () {
    late String councilSource;
    late String systemSource;

    setUpAll(() {
      councilSource = File(
        'lib/presentation/screens/council/council_dashboard_screen.dart',
      ).readAsStringSync();
      systemSource = File(
        'lib/presentation/screens/admin/admin_dashboard.dart',
      ).readAsStringSync();
    });

    test('council dashboard does not expose platform management actions', () {
      expect(councilSource, isNot(contains("pushNamed('createOrganization')")));
      expect(
        councilSource,
        isNot(contains("pushNamed('organizationsManagement')")),
      );
    });

    test('system dashboard does not watch a selected council', () {
      expect(
        systemSource,
        isNot(contains('watch(organizationContextProvider)')),
      );
      expect(systemSource, contains('systemOwnerAccessProvider'));
      expect(systemSource, contains('allOrganizationsProvider'));
      expect(systemSource, contains('systemDashboardSummaryProvider'));

      final providersSource =
          File('lib/providers/app_providers.dart').readAsStringSync();
      final platformAccessStart =
          providersSource.indexOf('final systemOwnerAccessProvider');
      final councilAccessStart =
          providersSource.indexOf('final adminAccessProvider');
      expect(platformAccessStart, greaterThanOrEqualTo(0));
      expect(councilAccessStart, greaterThan(platformAccessStart));
      final platformAccessSource =
          providersSource.substring(platformAccessStart, councilAccessStart);
      expect(
        platformAccessSource,
        isNot(contains('organizationContextProvider')),
      );
    });

    test('council data providers and activity use the selected organization',
        () {
      expect(
        councilSource,
        contains('councilDashboardMetricsProvider(organizationId)'),
      );
      expect(
        councilSource,
        contains('organizationBookingsProvider(organizationId)'),
      );
      expect(
        councilSource,
        contains('pendingFinancialReceiptsProvider(organizationId)'),
      );
      expect(
        councilSource,
        contains('organizationChargesProvider(organizationId)'),
      );
      expect(
        councilSource,
        contains('item.organizationId == organizationId'),
      );
    });

    test('council switcher limits normal users to active memberships', () {
      expect(
          councilSource, contains('activeUserMembershipsProvider(user.uid)'));
      expect(
        councilSource,
        contains('membershipByOrganization.containsKey(id)'),
      );
      expect(councilSource, contains('selectOrganizationAsSuperAdmin'));
      expect(councilSource, contains('.selectOrganization('));
      expect(councilSource, contains("organization['officialNameArabic']"));
      expect(councilSource, contains("organization['officialNameEnglish']"));
    });

    test('council dashboard delegates full access to central AdminAccess', () {
      expect(councilSource, contains('access.isOrgOwner'));
      expect(councilSource, contains('access.isChairman'));
      expect(
        councilSource,
        isNot(contains("permissions.contains('fullAccess')")),
      );
    });

    test('new shared dashboard code has no Android-only API dependency', () {
      final sharedSources = [
        councilSource,
        systemSource,
        File('lib/presentation/widgets/language_switcher.dart')
            .readAsStringSync(),
        File('lib/providers/locale_provider.dart').readAsStringSync(),
        File('lib/domain/dashboard/council_dashboard_metrics.dart')
            .readAsStringSync(),
        File('lib/domain/dashboard/system_dashboard_metrics.dart')
            .readAsStringSync(),
      ];

      for (final source in sharedSources) {
        expect(source, isNot(contains("import 'dart:io'")));
        expect(source, isNot(contains('Platform.isAndroid')));
      }
    });
  });
}
