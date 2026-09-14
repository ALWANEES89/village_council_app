import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:village_council_app/main.dart' as app;

const _userPhone = '90000001';
const _userPassword = 'QaUserA2026';
const _adminPhone = '90000002';
const _adminPassword = 'QaAdminA2026';
const _financePhone = '90000003';
const _financePassword = 'QaFinanceA2026';
const _organizationId = 'qa_council_a';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await binding.convertFlutterSurfaceToImage();
  });

  testWidgets('QA lifecycle login, tenant isolation, and role surfaces',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 8));

    expect(find.text('بيئة اختبار محلية'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));

    await _login(
      tester,
      phone: _userPhone,
      password: _userPassword,
    );

    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(FirebaseAuth.instance.currentUser, isNotNull);
    expect(find.byType(Scaffold), findsOneWidget);

    await _capture(binding, 'user-home');
    await _verifyUserTenantScope();
    await _openAccountAndReturn(tester);
    await _logout(tester);

    await _login(
      tester,
      phone: _adminPhone,
      password: _adminPassword,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await _capture(binding, 'admin-home');

    expect(find.byType(Scaffold), findsOneWidget);
    await _logout(tester);

    await _login(
      tester,
      phone: _financePhone,
      password: _financePassword,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(FirebaseAuth.instance.currentUser, isNotNull);
    await _capture(binding, 'finance-home');
    await _logout(tester);
  });
}

Future<void> _login(
  WidgetTester tester, {
  required String phone,
  required String password,
}) async {
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), phone);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.widgetWithText(ElevatedButton, 'تسجيل الدخول'));
  await tester.pumpAndSettle(const Duration(seconds: 6));
}

Future<void> _openAccountAndReturn(WidgetTester tester) async {
  final account = find.text('حسابي');
  if (account.evaluate().isNotEmpty) {
    await tester.tap(account.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(Scaffold), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }
}

Future<void> _logout(WidgetTester tester) async {
  final account = find.text('حسابي');
  if (account.evaluate().isNotEmpty) {
    await tester.tap(account.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  final signOut = find.text('تسجيل الخروج');
  expect(signOut, findsOneWidget);
  await tester.tap(signOut);
  await tester.pumpAndSettle(const Duration(seconds: 4));
  expect(find.text('تسجيل الدخول'), findsOneWidget);
}

Future<void> _verifyUserTenantScope() async {
  final user = FirebaseAuth.instance.currentUser;
  expect(user, isNotNull);
  final snapshot = await FirebaseFirestore.instance
      .collection('organizations')
      .doc(_organizationId)
      .collection('memberships')
      .doc(user!.uid)
      .get();
  expect(snapshot.exists, isFalse);
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  final bytes = await binding.takeScreenshot(name);
  final directory = Directory('project-brain/e2e-qa-screenshots');
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('${directory.path}/$name.png').writeAsBytesSync(bytes);
}
