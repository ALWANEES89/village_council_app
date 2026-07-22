import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/data/models/booking_model.dart';
import 'package:village_council_app/data/repositories/booking_repository.dart';
import 'package:village_council_app/presentation/screens/member/council_booking_screen.dart';

void main() {
  const organizationId = 'council-a';
  final month = DateTime(2099, 8);

  Widget harness(AsyncValue<List<BookingModel>> availability,
      {ValueChanged<DateTime>? onSelected}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BookingAvailabilityPanel(
            availability: availability,
            month: month,
            selectedDate: null,
            onPrevious: () {},
            onNext: () {},
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    );
  }

  test('availability parser keeps only redacted calendar fields', () {
    final rows = parseBookingAvailability({
      'days': [
        {
          'date': '2099-08-02T08:00:00.000Z',
          'status': 'approved',
          'requesterName': 'must not escape',
          'requesterPhone': '00000000',
          'receiptUrl': 'private',
          'amountBaisa': 5000,
        }
      ],
    }, organizationId: organizationId);

    expect(rows, hasLength(1));
    expect(rows.single.organizationId, organizationId);
    expect(rows.single.status, 'approved');
    expect(rows.single.userId, isEmpty);
    expect(rows.single.membershipId, isEmpty);
    expect(rows.single.requesterName, isEmpty);
    expect(rows.single.requesterPhone, isEmpty);
    expect(rows.single.notes, isEmpty);
    expect(rows.single.financialChargeId, isNull);
  });

  testWidgets('availability panel renders loading state', (tester) async {
    await tester.pumpWidget(harness(const AsyncValue.loading()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('availability panel renders safe error state', (tester) async {
    await tester.pumpWidget(harness(
      AsyncValue.error(StateError('permission-denied'), StackTrace.empty),
    ));

    expect(
        find.text('تعذر تحميل مواعيد الحجز. حاول مرة أخرى.'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
  });

  testWidgets('empty availability keeps the calendar usable', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(harness(
      const AsyncValue.data([]),
      onSelected: (date) => selected = date,
    ));

    expect(find.text('🔴 غير متاح'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('booking-day-2')));
    expect(selected, DateTime(2099, 8, 2));
  });

  testWidgets('approved redacted day is shown but cannot be selected',
      (tester) async {
    var selectionCount = 0;
    final unavailable = BookingModel(
      bookingId: '',
      organizationId: organizationId,
      userId: '',
      membershipId: '',
      requesterName: '',
      requesterPhone: '',
      bookingDate: DateTime(2099, 8, 2),
      occasionType: '',
      notes: '',
      status: 'approved',
    );
    await tester.pumpWidget(harness(
      AsyncValue.data([unavailable]),
      onSelected: (_) => selectionCount += 1,
    ));

    final inkWell = tester.widget<InkWell>(
      find.byKey(const ValueKey('booking-day-2')),
    );
    expect(inkWell.onTap, isNull);
    expect(selectionCount, 0);
  });
}
