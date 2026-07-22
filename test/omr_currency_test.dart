import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/formatters/omr_currency.dart';
import 'package:village_council_app/data/models/app_notification_model.dart';
import 'package:village_council_app/presentation/widgets/omr_amount.dart';

void main() {
  test('OMR formatter always uses three decimal places', () {
    expect(formatOmaniRialNumber(5000), '5.000');
    expect(formatOmaniRialNumber(8000), '8.000');
    expect(formatOmaniRialNumber(12500), '12.500');
    expect(formatOmaniRialNumber(7500), '7.500');
    expect(formatOmaniRialNumber(1), '0.001');
    expect(formatOmaniRialNumber(1999), '1.999');
  });

  test('OMR input accepts Arabic and English digits and decimal separators',
      () {
    expect(parseOmaniRialInput('5'), 5000);
    expect(parseOmaniRialInput('5.000'), 5000);
    expect(parseOmaniRialInput('12,500'), 12500);
    expect(parseOmaniRialInput('١٢٫٥٠٠'), 12500);
    expect(parseOmaniRialInput('۱۲٫۵۰۰'), 12500);
    expect(parseOmaniRialInput('١٬٢٣٤٫٥٠٠'), 1234500);
    expect(parseOmaniRialInput('12.5000'), isNull);
    expect(parseOmaniRialInput('-1'), isNull);
    expect(parseOmaniRialInput('1.2.3'), isNull);
  });

  test('system notification fallback never exposes the raw internal unit', () {
    expect(formatOmaniRialForSystemNotification(12500), '12.500 ر.ع.');
    expect(
        formatOmaniRialForSystemNotification(12500), isNot(contains('12500')));
    expect(
        formatOmaniRialForSystemNotification(12500), isNot(contains('بيسة')));
  });

  test('legacy notification bodies are upgraded for official-symbol display',
      () {
    final parsed = parseLegacyNotificationAmount(
      'تم اعتماد دفعة بقيمة 8000 بيسة.',
    );
    expect(parsed?.amountBaisa, 8000);
    expect(parsed?.bodyTemplate, 'تم اعتماد دفعة بقيمة {amount}.');
  });

  testWidgets('OmrAmount renders the official local asset before the number',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OmrAmount(amountBaisa: 12500)),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('12.500'), findsOneWidget);
    final row = tester.widget<Row>(find.byType(Row).first);
    expect(row.children.first, isA<OmrSymbol>());
  });

  testWidgets('OmrSymbol renders the rial mark bold by default via dilation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OmrSymbol(height: 18)),
      ),
    );
    expect(find.byType(OmrSymbol), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('OmrSymbol bold can be disabled without dilation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OmrSymbol(height: 18, bold: false)),
      ),
    );
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('OmrAmount keeps the number readable and the symbol bold',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OmrAmount(amountBaisa: 7500)),
      ),
    );
    // Symbol stays a single image, bolded, left of the (unchanged) number.
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('7.500'), findsOneWidget);
  });

  test('presentation sources do not regress to textual or manual currency', () {
    final files = Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('formatBaisa(')), reason: file.path);
      expect(source, isNot(contains('بيسة')), reason: file.path);
      expect(source, isNot(contains("suffixText: 'ر.ع")), reason: file.path);
      expect(source, isNot(contains('toStringAsFixed(3)')), reason: file.path);
    }
  });
}
