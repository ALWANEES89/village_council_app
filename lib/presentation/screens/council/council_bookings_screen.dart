import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/booking_model.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../domain/council_operations/council_operations_logic.dart';
import '../../../providers/app_providers.dart';
import '../member/council_booking_screen.dart';

class CouncilBookingsScreen extends ConsumerStatefulWidget {
  const CouncilBookingsScreen({super.key});

  @override
  ConsumerState<CouncilBookingsScreen> createState() =>
      _CouncilBookingsScreenState();
}

class _CouncilBookingsScreenState extends ConsumerState<CouncilBookingsScreen> {
  late DateTime _month;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final organizationId = ref
        .watch(organizationContextProvider)
        .currentOrganization?['organizationId'] as String?;
    final access = ref.watch(adminAccessProvider).valueOrNull;
    final canReview = access?.isPlatformOwner == true ||
        access?.isOrgOwner == true ||
        access?.isChairman == true ||
        access?.has('bookings.manage') == true ||
        access?.has('bookings.approve') == true;
    if (organizationId == null || !canReview) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.councilBookings)),
        body: Center(child: Text(strings.accessDenied)),
      );
    }
    final bookings = ref.watch(organizationBookingsProvider(organizationId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(strings.councilBookings)),
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(strings.couldNotLoad)),
        data: (items) {
          final approved = approvedUpcomingBookings(items);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              BookingAvailabilityPanel(
                availability: AsyncValue.data(items),
                month: _month,
                selectedDate: _selectedDay,
                onPrevious: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1)),
                onNext: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1)),
                onSelected: (date) => setState(() => _selectedDay = date),
              ),
              const SizedBox(height: 16),
              Text(strings.approvedUpcomingBookings,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (approved.isEmpty)
                Card(child: ListTile(title: Text(strings.noUpcomingBookings)))
              else
                for (final booking in approved)
                  _BookingCard(
                    booking: booking,
                    allBookings: items,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.allBookings});

  final BookingModel booking;
  final List<BookingModel> allBookings;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final pendingOnDay = allBookings.where((item) =>
        item.status == 'pending' &&
        item.bookingDate.year == booking.bookingDate.year &&
        item.bookingDate.month == booking.bookingDate.month &&
        item.bookingDate.day == booking.bookingDate.day);
    final time = [booking.startTime, booking.endTime]
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .join(' – ');
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.event_available)),
        title: Text(booking.requesterName.isEmpty
            ? strings.bookingNumber(booking.bookingId)
            : booking.requesterName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMMd(Localizations.localeOf(context).toString())
                .format(booking.bookingDate)),
            if (time.isNotEmpty) Text(time),
            Text('${strings.bookingStatus}: ${strings.approved}'),
            if (pendingOnDay.isNotEmpty)
              Chip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text(strings.additionalRequests(pendingOnDay.length)),
              ),
          ],
        ),
      ),
    );
  }
}
