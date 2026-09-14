import '../../data/models/booking_model.dart';
import '../../data/models/financial_models.dart';

int countUpcomingBookings(List<BookingModel> bookings, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  return bookings
      .where((item) =>
          !item.bookingDate.isBefore(today) &&
          const {'approved', 'confirmed'}.contains(item.status))
      .length;
}

int countOutstandingSubscriptions(List<FinancialCharge> charges) {
  return charges
      .where((item) =>
          item.chargeType == ChargeType.subscription &&
          item.balanceBaisa > 0 &&
          !const {
            ChargeStatus.paid,
            ChargeStatus.waived,
            ChargeStatus.cancelled,
          }.contains(item.status))
      .length;
}
