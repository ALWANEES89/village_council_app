import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/booking_model.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/reason_input_dialog.dart';

class BookingRequestsReviewScreen extends ConsumerStatefulWidget {
  const BookingRequestsReviewScreen({super.key});

  @override
  ConsumerState<BookingRequestsReviewScreen> createState() =>
      _BookingRequestsReviewScreenState();
}

class _BookingRequestsReviewScreenState
    extends ConsumerState<BookingRequestsReviewScreen> {
  String? _processingId;

  Future<void> _approve(BookingModel booking) async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;
    setState(() => _processingId = booking.bookingId);
    try {
      await ref.read(bookingRepositoryProvider).approve(
            organizationId: booking.organizationId,
            bookingId: booking.bookingId,
            reviewedBy: user.uid,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد الحجز')),
        );
      }
    } catch (error) {
      debugPrint('[BookingReview] approve failed type=${error.runtimeType}');
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _reject(BookingModel booking) async {
    final reason = await showReasonDialog(
      context: context,
      title: 'سبب رفض الحجز',
      hint: 'اكتب سبب الرفض',
      actionLabel: 'رفض',
      confirmColor: Colors.red,
      required: true,
    );
    if (!mounted || reason == null || reason.isEmpty) return;
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;
    setState(() => _processingId = booking.bookingId);
    try {
      await ref.read(bookingRepositoryProvider).reject(
            organizationId: booking.organizationId,
            bookingId: booking.bookingId,
            reviewedBy: user.uid,
            rejectionReason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفض الحجز')),
        );
      }
    } catch (error) {
      debugPrint('[BookingReview] reject failed type=${error.runtimeType}');
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _reviewCancellation(BookingModel booking, bool approve) async {
    final reason = await showReasonDialog(
      context: context,
      title: approve ? 'اعتماد إلغاء الحجز' : 'رفض إلغاء الحجز',
      hint: approve ? 'ملاحظة اختيارية' : 'سبب الرفض',
      actionLabel: approve ? 'اعتماد الإلغاء' : 'رفض الطلب',
      confirmColor: approve ? Colors.red : Colors.orange,
      required: !approve,
    );
    if (!mounted || reason == null) return;
    setState(() => _processingId = booking.bookingId);
    try {
      await ref.read(bookingRepositoryProvider).reviewCancellation(
            organizationId: booking.organizationId,
            bookingId: booking.bookingId,
            approve: approve,
            reason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(approve ? 'تم اعتماد إلغاء الحجز.' : 'تم رفض طلب الإلغاء.'),
        ));
      }
    } catch (error) {
      debugPrint(
          '[BookingReview] cancellation failed type=${error.runtimeType}');
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر تحديث طلب الحجز. حاول مرة أخرى.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organizationId =
        organizationContext.currentOrganization?['organizationId'] as String?;
    final membership = organizationContext.currentMembership;
    final access = ref.watch(adminAccessProvider).asData?.value;
    final permissions = membership?.permissionsSnapshot ?? const [];
    final allowed = access?.isSuperAdmin == true ||
        membership?.roleId == 'chairman' ||
        membership?.roleId == 'adminManager' ||
        permissions.contains('bookings.manage') ||
        permissions.contains('bookings.approve');
    final bookings = organizationId == null
        ? null
        : ref.watch(organizationBookingsProvider(organizationId));
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('طلبات حجز المجلس'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: organizationId == null
            ? const Center(child: Text('اختر مجلسًا أولًا'))
            : !allowed
                ? const Center(
                    child: Text('لا تملك صلاحية مراجعة طلبات الحجز'),
                  )
                : bookings!.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Center(
                      child: Text('تعذر تحميل طلبات الحجز.'),
                    ),
                    data: (items) {
                      final pending = items
                          .where((booking) =>
                              booking.status == 'pending' ||
                              booking.status == 'cancellationRequested')
                          .toList();
                      if (pending.isEmpty) {
                        return const Center(
                            child: Text('لا توجد طلبات قيد المراجعة'));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: pending.length,
                        itemBuilder: (context, index) {
                          final booking = pending[index];
                          final processing = _processingId == booking.bookingId;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.requesterName.isEmpty
                                        ? 'مستخدم'
                                        : booking.requesterName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                  Text(
                                      'الهاتف: ${booking.requesterPhone.isEmpty ? '-' : booking.requesterPhone}'),
                                  Text(
                                      'التاريخ: ${DateFormat('yyyy/MM/dd').format(booking.bookingDate)}'),
                                  Text('المناسبة: ${booking.occasionType}'),
                                  Text(booking.status == 'cancellationRequested'
                                      ? 'الحالة: طلب إلغاء بانتظار القرار'
                                      : 'الحالة: قيد المراجعة'),
                                  if (booking.startTime != null ||
                                      booking.endTime != null)
                                    Text(
                                        'الوقت: ${booking.startTime ?? '-'} - ${booking.endTime ?? '-'}'),
                                  if (booking.notes.isNotEmpty)
                                    Text('ملاحظات: ${booking.notes}'),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: processing
                                              ? null
                                              : () => booking.status ==
                                                      'cancellationRequested'
                                                  ? _reviewCancellation(
                                                      booking, true)
                                                  : _approve(booking),
                                          icon: Icon(booking.status ==
                                                  'cancellationRequested'
                                              ? Icons.cancel
                                              : Icons.check),
                                          label: Text(booking.status ==
                                                  'cancellationRequested'
                                              ? 'اعتماد الإلغاء'
                                              : 'اعتماد'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: processing
                                              ? null
                                              : () => booking.status ==
                                                      'cancellationRequested'
                                                  ? _reviewCancellation(
                                                      booking, false)
                                                  : _reject(booking),
                                          icon: const Icon(Icons.close),
                                          label: Text(booking.status ==
                                                  'cancellationRequested'
                                              ? 'رفض الإلغاء'
                                              : 'رفض'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}
