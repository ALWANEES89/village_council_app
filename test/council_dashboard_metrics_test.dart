import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/data/models/booking_model.dart';
import 'package:village_council_app/data/models/financial_models.dart';
import 'package:village_council_app/domain/dashboard/council_dashboard_metrics.dart';

void main() {
  BookingModel booking(DateTime date, String status) => BookingModel(
        bookingId: '$date-$status',
        organizationId: 'org-a',
        userId: 'user-a',
        membershipId: 'member-a',
        requesterName: 'Member',
        requesterPhone: '90000000',
        bookingDate: date,
        occasionType: 'event',
        notes: '',
        status: status,
      );

  FinancialCharge charge({
    required ChargeType type,
    required ChargeStatus status,
    required int balanceBaisa,
  }) =>
      FinancialCharge(
        id: '${type.name}-${status.name}',
        organizationId: 'org-a',
        membershipId: 'member-a',
        userId: 'user-a',
        chargeType: type,
        titleArabic: 'رسم',
        amountDueBaisa: balanceBaisa,
        amountPaidBaisa: 0,
        balanceBaisa: balanceBaisa,
        status: status,
      );

  test('upcoming bookings include only approved future or same-day items', () {
    final now = DateTime(2026, 9, 6, 12);
    final bookings = [
      booking(DateTime(2026, 9, 6), 'approved'),
      booking(DateTime(2026, 9, 7), 'confirmed'),
      booking(DateTime(2026, 9, 8), 'pending'),
      booking(DateTime(2026, 9, 5), 'approved'),
    ];

    expect(countUpcomingBookings(bookings, now: now), 2);
  });

  test('outstanding subscriptions exclude paid, waived and other fees', () {
    final charges = [
      charge(
          type: ChargeType.subscription,
          status: ChargeStatus.unpaid,
          balanceBaisa: 5000),
      charge(
          type: ChargeType.subscription,
          status: ChargeStatus.partial,
          balanceBaisa: 2000),
      charge(
          type: ChargeType.subscription,
          status: ChargeStatus.paid,
          balanceBaisa: 0),
      charge(
          type: ChargeType.subscription,
          status: ChargeStatus.waived,
          balanceBaisa: 5000),
      charge(
          type: ChargeType.booking,
          status: ChargeStatus.unpaid,
          balanceBaisa: 5000),
    ];

    expect(countOutstandingSubscriptions(charges), 2);
    expect(charges.first.balanceBaisa, isA<int>());
  });
}
