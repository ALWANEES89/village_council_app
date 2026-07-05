import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timeline_tile/timeline_tile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/transaction_model.dart';
import '../../../providers/app_providers.dart';

class TransactionTimelineScreen extends ConsumerWidget {
  final String transactionId;
  const TransactionTimelineScreen({super.key, required this.transactionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(currentMemberProvider);

    return memberAsync.when(
      loading: () => const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (member) {
        if (member == null) return const Scaffold(body: SizedBox());
        final txsAsync = ref.watch(memberTransactionsProvider(member.id));
        return txsAsync.when(
          loading: () => const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: AppColors.primary))),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (txs) {
            final matches = txs.where((t) => t.id == transactionId);
            final tx = matches.isEmpty ? null : matches.first;
            if (tx == null) {
              return const Scaffold(
                  body: Center(child: Text('لم يتم العثور على المعاملة')));
            }
            return _TimelineContent(tx: tx);
          },
        );
      },
    );
  }
}

class _TimelineContent extends StatelessWidget {
  final TransactionModel tx;
  const _TimelineContent({required this.tx});

  @override
  Widget build(BuildContext context) {
    final allSteps = [
      TransactionStatus.submitted,
      TransactionStatus.underReview,
      TransactionStatus.approved,
    ];

    final isRejected = tx.currentStatus == TransactionStatus.rejected;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('تتبع المعاملة',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: AppColors.primary,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBanner(status: tx.currentStatus),
              const SizedBox(height: 24),
              const Text('مراحل المعاملة:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textDark)),
              const SizedBox(height: 16),
              if (!isRejected)
                ...allSteps.asMap().entries.map((entry) {
                  final i = entry.key;
                  final step = entry.value;
                  final matchingEvents =
                      tx.timeline.where((e) => e.status == step);
                  final event =
                      matchingEvents.isEmpty ? null : matchingEvents.first;
                  final isCompleted = tx.timeline.any((e) => e.status == step);
                  final isLast = i == allSteps.length - 1;

                  return _TimelineStep(
                    event: event,
                    stepStatus: step,
                    isCompleted: isCompleted,
                    isLast: isLast,
                  );
                })
              else ...[
                _TimelineStep(
                  event: (() {
                    final events = tx.timeline
                        .where((e) => e.status == TransactionStatus.submitted);
                    return events.isEmpty ? null : events.first;
                  })(),
                  stepStatus: TransactionStatus.submitted,
                  isCompleted: true,
                  isLast: false,
                ),
                _RejectedStep(
                  event: (() {
                    final events = tx.timeline
                        .where((e) => e.status == TransactionStatus.rejected);
                    return events.isEmpty ? null : events.first;
                  })(),
                  reason: tx.rejectionReason,
                ),
              ],
              const SizedBox(height: 24),
              if (tx.receiptUrl.isNotEmpty) ...[
                const Text('صورة الإيصال:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textDark)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    tx.receiptUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      color: Colors.grey.shade200,
                      child: const Center(child: Text('تعذر تحميل الصورة')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final TransactionStatus status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case TransactionStatus.submitted:
        color = Colors.blue;
        icon = Icons.send;
        label = 'تم الإرسال - بانتظار المراجعة';
        break;
      case TransactionStatus.underReview:
        color = Colors.orange;
        icon = Icons.hourglass_empty;
        label = 'قيد المراجعة من الإدارة';
        break;
      case TransactionStatus.approved:
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'تم الاعتماد والتفعيل';
        break;
      case TransactionStatus.rejected:
        color = Colors.red;
        icon = Icons.cancel;
        label = 'تم الرفض';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final TransactionEvent? event;
  final TransactionStatus stepStatus;
  final bool isCompleted;
  final bool isLast;

  const _TimelineStep({
    this.event,
    required this.stepStatus,
    required this.isCompleted,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCompleted ? Colors.green : Colors.grey.shade400;

    return TimelineTile(
      alignment: TimelineAlign.start,
      isLast: isLast,
      indicatorStyle: IndicatorStyle(
        width: 28,
        height: 28,
        color: color,
        iconStyle: IconStyle(
          iconData: isCompleted ? Icons.check : Icons.circle_outlined,
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      beforeLineStyle: LineStyle(color: color, thickness: 2),
      endChild: Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 24, top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getLabel(stepStatus),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isCompleted ? AppColors.textDark : Colors.grey,
              ),
            ),
            if (event != null) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat('yyyy/MM/dd - HH:mm').format(event!.timestamp),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              if (event!.adminName != null)
                Text(
                  'بواسطة: ${event!.adminName}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _getLabel(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.submitted:
        return 'تم إرسال الإيصال';
      case TransactionStatus.underReview:
        return 'قيد المراجعة';
      case TransactionStatus.approved:
        return 'تم الاعتماد والتفعيل';
      case TransactionStatus.rejected:
        return 'تم الرفض';
    }
  }
}

class _RejectedStep extends StatelessWidget {
  final TransactionEvent? event;
  final String? reason;

  const _RejectedStep({this.event, this.reason});

  @override
  Widget build(BuildContext context) {
    return TimelineTile(
      alignment: TimelineAlign.start,
      isLast: true,
      indicatorStyle: IndicatorStyle(
        width: 28,
        height: 28,
        color: Colors.red,
        iconStyle: IconStyle(
          iconData: Icons.close,
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      beforeLineStyle: const LineStyle(color: Colors.red, thickness: 2),
      endChild: Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 24, top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تم الرفض',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.red)),
            if (event != null) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat('yyyy/MM/dd - HH:mm').format(event!.timestamp),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
            if (reason != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text('سبب الرفض: $reason',
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
