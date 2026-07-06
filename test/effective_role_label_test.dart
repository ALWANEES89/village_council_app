import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/auth/role_labels.dart';

void main() {
  group('effectiveRoleLabelArabic', () {
    test('العضو رقم 4 الحقيقي: roleId=member لكن permissionsSnapshot فيه fullAccess '
        '→ لا يظهر "عضو"', () {
      final label = effectiveRoleLabelArabic(
        'member',
        role: '',
        fallback: 'member',
        permissions: const [
          'fullAccess',
          'payments.read',
          'profile.read',
          'rentals.create',
        ],
      );
      expect(label, 'مدير (صلاحيات كاملة)');
      expect(label, isNot('عضو'));
    });

    test('عضو عادي فعلًا (لا صلاحيات إدارية) → يظهر "عضو"', () {
      final label = effectiveRoleLabelArabic(
        'member',
        role: '',
        permissions: const ['profile.read', 'payments.read'],
      );
      expect(label, 'عضو');
    });

    test('عضو roleId=member لكنه يملك membershipRequests.review '
        '→ يظهر مدير بصلاحيات مخصّصة', () {
      final label = effectiveRoleLabelArabic(
        'member',
        permissions: const ['membershipRequests.review'],
      );
      expect(label, 'مدير (صلاحيات مخصّصة)');
    });

    test('دور مميّز صريح adminManager يُعرض كما هو بغضّ النظر عن الصلاحيات', () {
      final label = effectiveRoleLabelArabic('adminManager', permissions: const []);
      expect(label, 'مدير إداري');
    });

    test('المالك الأعلى (system_owner) يُعرض المالك الأعلى', () {
      final label = effectiveRoleLabelArabic(
        'system_owner',
        role: 'owner',
        permissions: const ['fullAccess'],
      );
      expect(label, 'المالك الأعلى');
    });

    test('hasManagerPermissions يكشف fullAccess والصلاحيات الإدارية', () {
      expect(hasManagerPermissions(const ['fullAccess']), isTrue);
      expect(hasManagerPermissions(const ['members.manage']), isTrue);
      expect(hasManagerPermissions(const ['profile.read']), isFalse);
      expect(hasManagerPermissions(const []), isFalse);
    });
  });
}
