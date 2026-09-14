import '../../data/models/booking_model.dart';

bool sameCalendarDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool dateHasConfirmedBooking(
  Iterable<BookingModel> bookings,
  DateTime date,
) =>
    bookings.any((booking) =>
        const {'approved', 'confirmed'}.contains(booking.status) &&
        sameCalendarDay(booking.bookingDate, date));

List<BookingModel> approvedUpcomingBookings(
  Iterable<BookingModel> bookings, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final result = bookings
      .where((booking) =>
          const {'approved', 'confirmed'}.contains(booking.status) &&
          !booking.bookingDate.isBefore(today))
      .toList();
  result.sort((left, right) => left.bookingDate.compareTo(right.bookingDate));
  return List.unmodifiable(result);
}

int? parseOmrToBaisa(String input) {
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,3}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final rials = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  final amount = rials * 1000 + (fraction.isEmpty ? 0 : int.parse(fraction));
  return amount > 0 ? amount : null;
}
