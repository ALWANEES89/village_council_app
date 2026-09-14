import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:village_council_app/l10n/generated/app_localizations.dart';
import 'package:village_council_app/presentation/widgets/language_switcher.dart';
import 'package:village_council_app/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switches repeatedly between Arabic RTL and English LTR',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final notifier = LocaleNotifier();
    await notifier.ready;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localeProvider.overrideWith((ref) => notifier)],
        child: Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(localeProvider);
            return MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(body: LanguageSwitcher()),
            );
          },
        ),
      ),
    );

    expect(Directionality.of(tester.element(find.byType(LanguageSwitcher))),
        TextDirection.rtl);
    expect(find.text('AR'), findsOneWidget);

    await tester.tap(find.text('AR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('EN'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(LanguageSwitcher))),
        TextDirection.ltr);

    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(find.text('AR'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(LanguageSwitcher))),
        TextDirection.rtl);

    await tester.tap(find.text('AR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('EN'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(LanguageSwitcher))),
        TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });
}
