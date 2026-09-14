import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/auth/admin_access.dart';

void main() {
  group('System Admin Dashboard access', () {
    test('only the platform system owner has system-level access', () {
      const systemOwner = AdminAccess(isSuperAdmin: true);

      expect(systemOwner.isSystemOwner, isTrue);
      for (final role in const [
        'owner',
        'chairman',
        'adminManager',
        'financialManager',
        'financialReviewer',
        'member',
      ]) {
        final councilAccess = AdminAccess(roleId: role, status: 'active');
        expect(
          councilAccess.isSystemOwner,
          isFalse,
          reason: '$role is a council role, not a platform role',
        );
      }
    });

    test('screen enforces system-owner guard and avoids council-context watch',
        () {
      final source = File(
        'lib/presentation/screens/admin/admin_dashboard.dart',
      ).readAsStringSync();

      expect(source, contains('ref.watch(systemOwnerAccessProvider)'));
      expect(source, contains('access.valueOrNull != true'));
      expect(source, isNot(contains('watch(organizationContextProvider)')));
      expect(source, contains('selectOrganizationAsSuperAdmin'));
      expect(source, contains("pushNamed('councilDashboard')"));
    });

    test('council dashboard gives the platform owner an explicit return path',
        () {
      final source = File(
        'lib/presentation/screens/council/council_dashboard_screen.dart',
      ).readAsStringSync();

      expect(source, contains('if (access.isPlatformOwner)'));
      expect(source, contains("goNamed('adminDashboard')"));
    });

    test('direct system-management screens enforce a system-owner guard', () {
      final createSource = File(
        'lib/presentation/screens/admin/create_organization_screen.dart',
      ).readAsStringSync();
      final manageSource = File(
        'lib/presentation/screens/admin/organizations_management_screen.dart',
      ).readAsStringSync();

      expect(
        createSource,
        contains('ref.watch(systemOwnerAccessProvider)'),
      );
      expect(
        createSource,
        contains('if (!isSystemOwner || user == null)'),
      );
      expect(
        manageSource,
        contains('ref.watch(systemOwnerAccessProvider)'),
      );
    });
  });
}
