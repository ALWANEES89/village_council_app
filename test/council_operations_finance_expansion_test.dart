import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/data/models/booking_model.dart';
import 'package:village_council_app/domain/council_operations/council_operations_logic.dart';
import 'package:village_council_app/router/app_router.dart';

BookingModel booking(String id, DateTime date, String status) => BookingModel(
      bookingId: id,
      organizationId: 'org-a',
      userId: 'user-$id',
      membershipId: 'member-$id',
      requesterName: 'Member $id',
      requesterPhone: '',
      bookingDate: date,
      occasionType: 'occasion',
      notes: '',
      status: status,
    );

void main() {
  test('expanded council routes compile', () {
    expect(routerProvider, isNotNull);
  });

  test('approved council bookings are nearest first and pending is excluded',
      () {
    final result = approvedUpcomingBookings([
      booking('late', DateTime(2026, 10, 20), 'approved'),
      booking('pending', DateTime(2026, 9, 10), 'pending'),
      booking('near', DateTime(2026, 9, 15), 'confirmed'),
    ], now: DateTime(2026, 9, 7));
    expect(result.map((item) => item.bookingId), ['near', 'late']);
  });

  test('booked date detects only confirmed or approved bookings', () {
    final date = DateTime(2026, 9, 15);
    expect(dateHasConfirmedBooking([booking('a', date, 'approved')], date),
        isTrue);
    expect(dateHasConfirmedBooking([booking('p', date, 'pending')], date),
        isFalse);
  });

  test('OMR input becomes positive integer baisa without double storage', () {
    expect(parseOmrToBaisa('12.345'), 12345);
    expect(parseOmrToBaisa('1.5'), 1500);
    expect(parseOmrToBaisa('-1'), isNull);
    expect(parseOmrToBaisa('1.2345'), isNull);
    expect(parseOmrToBaisa('abc'), isNull);
  });

  test(
      'main home and council dashboard keep personal and council providers separate',
      () {
    final home = File('lib/presentation/screens/member/member_home_screen.dart')
        .readAsStringSync();
    final dashboard =
        File('lib/presentation/screens/council/council_dashboard_screen.dart')
            .readAsStringSync();
    final councilBookings =
        File('lib/presentation/screens/council/council_bookings_screen.dart')
            .readAsStringSync();
    expect(home, contains('userBookingsProvider'));
    expect(home, isNot(contains('organizationBookingsProvider')));
    expect(dashboard, contains("pushNamed('councilBookings')"));
    expect(councilBookings, contains('organizationBookingsProvider'));
  });

  test('member home latest notification is scoped to selected council', () {
    final home = File(
      'lib/presentation/screens/member/member_home_screen.dart',
    ).readAsStringSync();
    expect(home, contains('organizationId: selected?.organizationId'));
    expect(home, contains('item.organizationId == organizationId'));
  });

  test('dashboard interactive cards and activity have real navigation', () {
    final source =
        File('lib/presentation/screens/council/council_dashboard_screen.dart')
            .readAsStringSync();
    expect(source, contains("pushNamed('importantAlerts')"));
    expect(source, contains('NotificationDeepLink.open'));
    expect(source, contains("pushNamed('financialReport')"));
    expect(source, contains("pushNamed('expenses')"));
    expect(source, contains("pushNamed('sendCouncilNotification')"));
  });

  test('important alert rows keep an action bound to their own alert type', () {
    final source = File(
      'lib/presentation/screens/council/council_dashboard_screen.dart',
    ).readAsStringSync();
    expect(source,
        contains("action: () => context.pushNamed('bookingRequestsReview')"));
    expect(
        source, contains("action: () => context.pushNamed('financialReview')"));
    expect(source,
        contains("action: () => context.pushNamed('financialManagement')"));
    expect(source, contains('onTap: alerts[index].action'));
    expect(source, isNot(contains('_alertAction(')));
  });

  test('financial review follows app locale without forcing Arabic RTL', () {
    final source = File(
      'lib/presentation/screens/admin/financial_review_screen.dart',
    ).readAsStringSync();
    expect(source, contains('AppLocalizations.of(context)'));
    expect(source, isNot(contains('TextDirection.rtl')));
    expect(source, isNot(contains("Text('ت")));
    expect(source, isNot(contains("Text('ر")));
  });

  test('notification and expense client calls are tenant scoped', () {
    final repository =
        File('lib/data/repositories/council_management_repository.dart')
            .readAsStringSync();
    expect(repository, contains("'organizationId': organizationId"));
    expect(repository, contains("httpsCallable('sendCouncilNotification')"));
    expect(repository, contains("httpsCallable('createCouncilExpense')"));
    expect(repository, contains("'amountBaisa': amountBaisa"));
  });

  test('booked request warning keeps submission available', () {
    final client =
        File('lib/presentation/screens/member/council_booking_screen.dart')
            .readAsStringSync();
    final server = File('functions/production_security.js').readAsStringSync();
    expect(client, contains('bookedDateRequestWarning'));
    expect(client, contains('dateHasConfirmedBooking'));
    expect(server, contains('status: "pending"'));
    expect(server, contains('hasConfirmedConflict'));
  });

  test('receipt timeline resolves reviewer name through server activity detail',
      () {
    final screen =
        File('lib/presentation/screens/member/transaction_timeline_screen.dart')
            .readAsStringSync();
    final server = File('functions/council_management.js').readAsStringSync();
    expect(screen, contains('reviewedByName'));
    expect(screen, contains('councilActivityDetailProvider'));
    expect(server, contains('resolveUserName(reviewedBy'));
  });
}
