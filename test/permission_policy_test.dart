import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/auth/permission_policy.dart';

void main() {
  test('member role never retains fullAccess', () {
    expect(
      sanitizePermissionsForRole(
        'member',
        ['profile.read', 'fullAccess', 'payments.read', 'fullAccess'],
      ),
      ['payments.read', 'profile.read'],
    );
    expect(
      memberRoleHasSafePermissions('member', ['fullAccess']),
      isFalse,
    );
  });

  test('administrative roles retain fullAccess', () {
    expect(
      sanitizePermissionsForRole('owner', ['fullAccess']),
      ['fullAccess'],
    );
    expect(
      memberRoleHasSafePermissions('owner', ['fullAccess']),
      isTrue,
    );
  });

  test('ordinary role-change flow cannot assign ownership roles', () {
    final repository = File(
      'lib/features/member_management/data/member_management_repository.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/member_management/presentation/member_details_screen.dart',
    ).readAsStringSync();
    for (final role in ['owner', 'council_owner', 'system_owner']) {
      expect(repository, contains("'$role'"));
      expect(screen, contains("'$role'"));
    }
    expect(repository, contains('protected transfer flow'));
  });
}
