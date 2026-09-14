import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:village_council_app/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to Arabic and persists an English selection', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = LocaleNotifier();
    await notifier.ready;

    expect(notifier.state, const Locale('ar'));
    await notifier.setLocale(const Locale('en'));
    expect(notifier.state, const Locale('en'));

    final restored = LocaleNotifier();
    await restored.ready;
    expect(restored.state, const Locale('en'));
  });

  test('ignores unsupported locales', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
    final notifier = LocaleNotifier();
    await notifier.ready;

    await notifier.setLocale(const Locale('fr'));
    expect(notifier.state, const Locale('ar'));
  });
}
