import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/auth/admin_access.dart';

void main() {
  group('صلاحية إعدادات الرسوم والاشتراكات', () {
    test('المدير المالي يفتح الإعدادات حتى مع snapshot قديم بلا صلاحيات', () {
      const access = AdminAccess(
        roleId: 'financialManager',
        status: 'active',
      );

      expect(access.canManageFinancialSettings, isTrue);
    });

    test('المراجع المالي لا يعدل الإعدادات بصلاحية مراجعة الإيصالات فقط', () {
      const access = AdminAccess(
        roleId: 'financialReviewer',
        status: 'active',
        permissions: ['receipts.review'],
      );

      expect(access.canReviewReceipts, isTrue);
      expect(access.canManageFinancialSettings, isFalse);
    });

    test('العضو العادي لا يستطيع تعديل الإعدادات', () {
      const access = AdminAccess(roleId: 'member', status: 'active');

      expect(access.canManageFinancialSettings, isFalse);
    });

    test('fullAccess الملوث لا يصعّد دور member', () {
      const access = AdminAccess(
        roleId: 'member',
        status: 'active',
        permissions: ['fullAccess', 'profile.read'],
      );
      expect(access.isOrgOwner, isFalse);
      expect(access.canManageFinancialSettings, isFalse);
      expect(access.canReviewReceipts, isFalse);
    });

    test('مالك المجلس ومالك المنصة يستطيعان تعديل الإعدادات', () {
      const councilOwner = AdminAccess(
        roleId: 'owner',
        status: 'active',
      );
      const systemOwner = AdminAccess(isSuperAdmin: true);

      expect(councilOwner.canManageFinancialSettings, isTrue);
      expect(systemOwner.canManageFinancialSettings, isTrue);
    });

    test('صفحة المجلس تعرض مدخل الإدارة المالية حسب الصلاحية المركزية', () {
      final source = File(
        'lib/presentation/screens/council/council_dashboard_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('adminAccess?.canManageFinancialSettings == true'),
      );
      expect(source, contains("context.pushNamed('financialManagement')"));
    });

    test('نوافذ الرسوم لا تتخلص من متحكم النص قبل انتهاء إغلاقها', () {
      final source = File(
        'lib/presentation/screens/admin/financial_management_screen.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('amount.dispose()')));
      expect(source, isNot(contains('member.dispose()')));
      expect(source, isNot(contains('nonMember.dispose()')));
      expect(source, isNot(contains('event.dispose()')));
    });
  });
}
