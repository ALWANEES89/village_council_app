import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/auth/admin_access.dart';
import 'package:village_council_app/l10n/generated/app_localizations.dart';
import 'package:village_council_app/presentation/widgets/main_bottom_navigation.dart';

Widget localizedNavigation(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        bottomNavigationBar: MainBottomNavigation(
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );

void main() {
  test('home and account use real providers, global language, and real routes',
      () {
    final home = File(
      'lib/presentation/screens/member/member_home_screen.dart',
    ).readAsStringSync();
    final account = File(
      'lib/presentation/screens/member/my_account_screen.dart',
    ).readAsStringSync();
    final router = File('lib/router/app_router.dart').readAsStringSync();

    expect(home, contains('userBookingsProvider'));
    expect(home, contains('memberChargesProvider'));
    expect(home, contains('userNotificationsProvider'));
    expect(home, isNot(contains('LanguageSwitcher')));
    expect(home, contains('access.canAccessGoldenAdminPanel'));
    expect(home, contains('systemOwnerAccessProvider'));
    expect(account, contains('LanguageSwitcher'));
    expect(account, contains("pushNamed('profileEdit')"));
    expect(account, contains("pushNamed('receiptHistory')"));
    expect(account, isNot(contains('deleteAccount')));
    expect(router, contains("name: 'myAccount'"));
  });

  test('council shortcut is role-aware without granting plain members access',
      () {
    const financialManager = AdminAccess(
      roleId: 'financialManager',
      status: 'active',
    );
    const financialReviewer = AdminAccess(
      roleId: 'financialReviewer',
      status: 'active',
    );
    const member = AdminAccess(roleId: 'member', status: 'active');
    const pollutedMember = AdminAccess(
      roleId: 'member',
      status: 'active',
      permissions: ['fullAccess'],
    );
    const systemOwner = AdminAccess(isSuperAdmin: true);

    expect(financialManager.canAccessGoldenAdminPanel, isTrue);
    expect(financialReviewer.canAccessGoldenAdminPanel, isTrue);
    expect(member.canAccessGoldenAdminPanel, isFalse);
    expect(pollutedMember.canAccessGoldenAdminPanel, isFalse);
    expect(systemOwner.canAccessGoldenAdminPanel, isTrue);
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets(
      'mobile navigation renders five destinations without overflow in ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(localizedNavigation(locale));
        await tester.pumpAndSettle();

        expect(find.byType(NavigationDestination), findsNWidgets(5));
        expect(
            Directionality.of(tester.element(find.byType(NavigationBar))),
            locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
