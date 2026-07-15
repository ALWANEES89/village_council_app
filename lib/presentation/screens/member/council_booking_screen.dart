import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/booking_model.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/reason_input_dialog.dart';
import 'guest_booking_receipt_screen.dart';

class CouncilBookingArguments {
  const CouncilBookingArguments({this.organizationId, this.membershipId});

  final String? organizationId;
  final String? membershipId;
}

class CouncilBookingScreen extends ConsumerStatefulWidget {
  const CouncilBookingScreen({super.key, this.arguments});

  final CouncilBookingArguments? arguments;

  @override
  ConsumerState<CouncilBookingScreen> createState() =>
      _CouncilBookingScreenState();
}

class _CouncilBookingScreenState extends ConsumerState<CouncilBookingScreen> {
  late DateTime _visibleMonth;
  late Future<List<_BookingOrganization>> _availableOrganizations;
  String? _organizationId;
  String? _membershipId;
  DateTime? _selectedDate;
  bool get _organizationLocked => widget.arguments?.organizationId != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _organizationId = widget.arguments?.organizationId;
    _membershipId = widget.arguments?.membershipId;
    if (_organizationId != null) {
      debugPrint('[Bookings] organizationId=$_organizationId');
    }
    _availableOrganizations = _loadAvailableOrganizations();
  }

  Future<List<_BookingOrganization>> _loadAvailableOrganizations() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return const [];
    if (_organizationLocked) {
      final organization = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(_organizationId)
          .get();
      if (!organization.exists) return const [];
      var allowed = _membershipId?.isNotEmpty == true;
      if (!allowed) {
        final membership = await organization.reference
            .collection('memberships')
            .doc(user.uid)
            .get();
        if (membership.data()?['status'] == 'active') {
          _membershipId = membership.id;
          allowed = true;
        }
      }
      if (!allowed) {
        final settings = await organization.reference
            .collection('settings')
            .doc('organization')
            .get();
        allowed = settings.data()?['allowHallRental'] == true;
      }
      if (!allowed) return const [];
      return [
        _BookingOrganization(
          id: organization.id,
          name: _organizationName(organization.data() ?? const {}),
          membershipId: _membershipId ?? '',
        ),
      ];
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('organizations')
        .where('status', isEqualTo: 'active')
        .get();
    final result = <_BookingOrganization>[];
    for (final organization in snapshot.docs) {
      final data = organization.data();
      final membership = await organization.reference
          .collection('memberships')
          .doc(user.uid)
          .get();
      final suppliedMembership = organization.id == _organizationId &&
          _membershipId?.isNotEmpty == true;
      final isMember =
          suppliedMembership || membership.data()?['status'] == 'active';
      var publicRentalAllowed = false;
      if (!isMember) {
        final settings = await organization.reference
            .collection('settings')
            .doc('organization')
            .get();
        publicRentalAllowed = settings.data()?['allowHallRental'] == true;
      }
      if (isMember || publicRentalAllowed) {
        result.add(_BookingOrganization(
          id: organization.id,
          name: _organizationName(data),
          membershipId: suppliedMembership
              ? _membershipId!
              : (isMember ? membership.id : ''),
        ));
      }
    }
    if (_organizationId == null && result.length == 1 && mounted) {
      setState(() {
        _organizationId = result.single.id;
        _membershipId = result.single.membershipId;
      });
      debugPrint('[Bookings] organizationId=${result.single.id}');
    }
    return result;
  }

  Future<void> _submitBooking() async {
    final organizationId = _organizationId;
    final selectedDate = _selectedDate;
    final user = ref.read(authServiceProvider).currentUser;
    if (organizationId == null || selectedDate == null || user == null) return;

    // النموذج StatefulWidget يملك حقوله ويتخلّص من controllers في dispose()
    // بالترتيب الصحيح — يمنع crash "TextEditingController used after disposed"
    // و`_dependents.isEmpty`. والمحتوى قابل للتمرير — يمنع RenderFlex overflow
    // عند ظهور لوحة المفاتيح.
    final result = await showModalBottomSheet<_BookingFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BookingFormSheet(selectedDate: selectedDate),
    );
    if (result == null || !mounted) return;
    final occasionType = result.occasionType;
    final notes = result.notes;
    final startTime = result.startTime;
    final endTime = result.endTime;

    try {
      // A missing/migrating profile must not prevent an authenticated user
      // with a valid membership (or public-rental access) from booking.
      final profile = await ref
          .read(userProfileProvider(user.uid).future)
          .onError((_, __) => null);
      await ref.read(bookingRepositoryProvider).create(
            organizationId: organizationId,
            userId: user.uid,
            membershipId: _membershipId ?? '',
            requesterName: profile?.fullName ?? user.displayName ?? '',
            requesterPhone: profile?.phone ?? user.phoneNumber ?? '',
            bookingDate: selectedDate,
            startTime: startTime,
            endTime: endTime,
            occasionType: occasionType,
            notes: notes,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الحجز للمراجعة')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[Bookings] submit failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال طلب الحجز: $error')),
        );
      }
    }
  }

  Future<void> _requestCancellation(BookingModel booking) async {
    final reason = await showReasonDialog(
      context: context,
      title: booking.status == 'approved' ? 'طلب إلغاء الحجز' : 'إلغاء الحجز',
      hint: 'سبب الإلغاء (اختياري)',
      actionLabel: booking.status == 'approved' ? 'إرسال الطلب' : 'إلغاء الحجز',
      required: false,
      confirmColor: Colors.red,
    );
    if (!mounted || reason == null) return;
    try {
      final status =
          await ref.read(bookingRepositoryProvider).requestCancellation(
                organizationId: booking.organizationId,
                bookingId: booking.bookingId,
                reason: reason,
              );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'cancelled'
              ? 'تم إلغاء الحجز.'
              : 'تم إرسال طلب الإلغاء للإدارة.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إلغاء الحجز: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final guestMode = _membershipId?.isNotEmpty != true;
    final bookings = _organizationId == null
        ? null
        : guestMode
            ? ref.watch(bookingAvailabilityProvider((
                organizationId: _organizationId!,
                year: _visibleMonth.year,
                month: _visibleMonth.month,
              )))
            : ref.watch(organizationBookingsProvider(_organizationId!));
    final ownBookings = _organizationId == null || user == null
        ? null
        : ref.watch(userBookingsProvider((
            organizationId: _organizationId!,
            userId: user.uid,
          )));
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('حجز المجلس'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<List<_BookingOrganization>>(
          future: _availableOrganizations,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Text('تعذر تحميل المجالس المتاحة للحجز.'),
              );
            }
            final organizations = snapshot.data ?? const [];
            if (organizations.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد عضوية نشطة، والحجز العام غير متاح حاليًا.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_organizationLocked)
                  ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(organizations.single.name),
                    subtitle: const Text('المجلس المحدد'),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _organizationId,
                    decoration: const InputDecoration(labelText: 'المجلس'),
                    items: organizations
                        .map((organization) => DropdownMenuItem(
                              value: organization.id,
                              child: Text(organization.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      final selected =
                          organizations.where((item) => item.id == value).first;
                      debugPrint('[Bookings] organizationId=${selected.id}');
                      setState(() {
                        _organizationId = selected.id;
                        _membershipId = selected.membershipId;
                        _selectedDate = null;
                      });
                    },
                  ),
                const SizedBox(height: 14),
                if (bookings != null)
                  bookings.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Text(
                      'تعذر تحميل مواعيد الحجز. حاول مرة أخرى.',
                    ),
                    data: (items) => _MonthCalendar(
                      month: _visibleMonth,
                      bookings: items,
                      selectedDate: _selectedDate,
                      onPrevious: () => setState(() => _visibleMonth = DateTime(
                          _visibleMonth.year, _visibleMonth.month - 1)),
                      onNext: () => setState(() => _visibleMonth = DateTime(
                          _visibleMonth.year, _visibleMonth.month + 1)),
                      onSelected: (date) =>
                          setState(() => _selectedDate = date),
                    ),
                  ),
                const SizedBox(height: 14),
                if (_selectedDate != null)
                  FilledButton.icon(
                    onPressed: _submitBooking,
                    icon: const Icon(Icons.send),
                    label: const Text('طلب حجز هذا اليوم'),
                  ),
                const SizedBox(height: 20),
                if (ownBookings != null)
                  ownBookings.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('تعذر تحميل حجوزاتك.'),
                    data: (items) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'حجوزاتي',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (items.isEmpty) const Text('لا توجد حجوزات سابقة.'),
                        for (final booking in items)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(DateFormat('yyyy/MM/dd')
                                      .format(booking.bookingDate)),
                                  Text('الحالة: ${booking.status}'),
                                  if (booking.financialChargeId != null)
                                    const Text(
                                        'تم إنشاء رسم الحجز. افتح تفاصيل الدفع لعرض المبلغ والحالة.'),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (booking.status == 'pending' ||
                                          booking.status == 'approved')
                                        TextButton.icon(
                                          onPressed: () =>
                                              _requestCancellation(booking),
                                          icon:
                                              const Icon(Icons.cancel_outlined),
                                          label: Text(
                                              booking.status == 'approved'
                                                  ? 'طلب إلغاء'
                                                  : 'إلغاء'),
                                        ),
                                      if (booking.financialAccountType ==
                                              'guest' &&
                                          booking.financialChargeId != null)
                                        TextButton.icon(
                                          onPressed: () => context.pushNamed(
                                            'guestBookingReceipt',
                                            extra: GuestBookingReceiptArguments(
                                              organizationId:
                                                  booking.organizationId,
                                              bookingId: booking.bookingId,
                                            ),
                                          ),
                                          icon: const Icon(Icons.receipt_long),
                                          label: const Text('المبلغ والدفع'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.bookings,
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.onSelected,
  });

  final DateTime month;
  final List<BookingModel> bookings;
  final DateTime? selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday % 7;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_right)),
                Expanded(
                  child: Text(
                    DateFormat('yyyy/MM').format(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                    onPressed: onNext, icon: const Icon(Icons.chevron_left)),
              ],
            ),
            Row(
              children: [
                for (final day in ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'])
                  Expanded(child: Center(child: Text(day))),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: 42,
              itemBuilder: (context, index) {
                final day = index - offset + 1;
                if (day < 1 || day > days) return const SizedBox.shrink();
                final date = DateTime(month.year, month.month, day);
                final dayBookings = bookings.where(
                  (booking) => _sameDate(booking.bookingDate, date),
                );
                final approved =
                    dayBookings.any((booking) => booking.status == 'approved');
                final pending =
                    dayBookings.any((booking) => booking.status == 'pending');
                final selected =
                    selectedDate != null && _sameDate(selectedDate!, date);
                final past = date.isBefore(DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ));
                return InkWell(
                  onTap: approved || past ? null : () => onSelected(date),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: approved
                          ? Colors.red.shade100
                          : pending
                              ? Colors.orange.shade100
                              : selected
                                  ? AppColors.primary.withValues(alpha: 0.18)
                                  : null,
                      borderRadius: BorderRadius.circular(9),
                      border: selected
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: past ? Colors.grey : null,
                          fontWeight: approved || pending
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Wrap(
              spacing: 14,
              children: [
                Text('🔴 غير متاح'),
                Text('🟠 قيد المراجعة'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingOrganization {
  const _BookingOrganization({
    required this.id,
    required this.name,
    required this.membershipId,
  });

  final String id;
  final String name;
  final String membershipId;
}

class _BookingFormResult {
  const _BookingFormResult({
    required this.occasionType,
    required this.notes,
    required this.startTime,
    required this.endTime,
  });

  final String occasionType;
  final String notes;
  final String startTime;
  final String endTime;
}

/// نموذج طلب الحجز — StatefulWidget يملك حقوله ويتخلّص من controllers في
/// dispose() بالترتيب الصحيح (يمنع crash "TextEditingController used after
/// disposed"). المحتوى داخل SingleChildScrollView فلا يحدث RenderFlex overflow
/// عند ظهور لوحة المفاتيح.
class _BookingFormSheet extends StatefulWidget {
  const _BookingFormSheet({required this.selectedDate});

  final DateTime selectedDate;

  @override
  State<_BookingFormSheet> createState() => _BookingFormSheetState();
}

class _BookingFormSheetState extends State<_BookingFormSheet> {
  final _occasionController = TextEditingController();
  final _notesController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _occasionController.addListener(_onOccasionChanged);
  }

  void _onOccasionChanged() {
    final canSubmit = _occasionController.text.trim().isNotEmpty;
    if (canSubmit != _canSubmit) setState(() => _canSubmit = canSubmit);
  }

  @override
  void dispose() {
    _occasionController.dispose();
    _notesController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_occasionController.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _BookingFormResult(
        occasionType: _occasionController.text.trim(),
        notes: _notesController.text.trim(),
        startTime: _startController.text.trim(),
        endTime: _endController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'طلب حجز ${DateFormat('yyyy/MM/dd').format(widget.selectedDate)}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _occasionController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'نوع المناسبة *'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      textInputAction: TextInputAction.next,
                      decoration:
                          const InputDecoration(labelText: 'وقت البداية'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _endController,
                      textInputAction: TextInputAction.next,
                      decoration:
                          const InputDecoration(labelText: 'وقت النهاية'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: const Text('إرسال طلب الحجز'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _organizationName(Map<String, dynamic> organization) {
  final official = organization['officialNameArabic'];
  if (official is String && official.trim().isNotEmpty) return official;
  final short = organization['shortName'];
  if (short is String && short.trim().isNotEmpty) return short;
  return 'مجلس';
}
