import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/payment_model.dart';
import '../../../providers/app_providers.dart';

class MemberDashboard extends ConsumerWidget {
  const MemberDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(currentMemberProvider);

    return memberAsync.when(
      loading: () => const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (_, __) => const Scaffold(
        body: Center(child: Text('تعذر تحميل بيانات العضو.')),
      ),
      data: (member) {
        if (member == null) {
          return const Scaffold(
            body: Center(child: Text('لم يتم العثور على بيانات العضو')),
          );
        }
        return _DashboardContent(memberId: member.id, member: member);
      },
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  final String memberId;
  final MemberModel member;

  const _DashboardContent({required this.memberId, required this.member});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(memberPaymentsProvider(memberId));
    final totalPaidAsync = ref.watch(totalPaidThisYearProvider(memberId));

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(context, ref),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MemberCard(member: member, totalPaidAsync: totalPaidAsync),
                    const SizedBox(height: 24),
                    _buildQuickActions(context, ref),
                    const SizedBox(height: 24),
                    const Text('الرسوم والاشتراكات',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark)),
                    const SizedBox(height: 12),
                    paymentsAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary)),
                      error: (_, __) =>
                          const Text('تعذر تحميل بيانات المدفوعات.'),
                      data: (payments) => _PaymentsList(
                        payments: payments,
                        memberId: memberId,
                        memberName: member.fullName,
                        fcmToken: member.fcmToken,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminAccessProvider).asData?.value;
    final canOpenAdmin = member.isAdmin ||
        access?.isSuperAdmin == true ||
        access?.canReviewRequests == true ||
        access?.canManageMembers == true ||
        access?.canManageRoles == true;
    return SliverAppBar(
      expandedHeight: 80,
      floating: true,
      pinned: true,
      backgroundColor: AppColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text('مجلس القرية',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        background: Container(
            decoration:
                const BoxDecoration(gradient: AppColors.primaryGradient)),
      ),
      actions: [
        if (canOpenAdmin)
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            tooltip: 'لوحة الأدمن',
            onPressed: () => context.pushNamed('adminDashboard'),
          ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () async {
            await ref.read(authServiceProvider).signOut();
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, WidgetRef ref) {
    final organizationContext = ref.watch(organizationContextProvider);
    final organizationId =
        organizationContext.currentOrganization?['organizationId'] as String?;
    final membership = organizationContext.currentMembership;
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.upload_file,
            label: 'رفع إيصال',
            color: AppColors.primary,
            onTap: () {
              if (organizationId == null || membership == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('اختر المجلس أولًا.')),
                );
                return;
              }
              context.pushNamed('uploadReceipt', extra: {
                'paymentId': '',
                'periodLabel': 'إيصال دفع عام',
                'organizationId': organizationId,
                'membershipId': membership.id,
                'userId': memberId,
              });
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.history,
            label: 'سجل المعاملات',
            color: AppColors.secondary,
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  final MemberModel member;
  final AsyncValue<double> totalPaidAsync;

  const _MemberCard({required this.member, required this.totalPaidAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [AppColors.primaryShadow],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.fullName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('عضو رقم: ${member.memberNumber}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(member.statusLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ),
          const Divider(color: Colors.white30, height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مدفوعات ${DateTime.now().year}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  totalPaidAsync.when(
                    loading: () => const Text('...',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    error: (_, __) => const Text('-',
                        style: TextStyle(color: Colors.white, fontSize: 22)),
                    data: (total) => Text('${total.toStringAsFixed(0)} ر.ع',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('تاريخ الانضمام',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('yyyy/MM/dd').format(member.joinDate),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _PaymentsList extends StatelessWidget {
  final List<PaymentModel> payments;
  final String memberId;
  final String memberName;
  final String? fcmToken;

  const _PaymentsList({
    required this.payments,
    required this.memberId,
    required this.memberName,
    required this.fcmToken,
  });

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('لا توجد رسوم مسجلة',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
        ),
      );
    }
    return Column(
      children: payments
          .map((p) => _PaymentCard(
                payment: p,
                memberId: memberId,
                memberName: memberName,
                fcmToken: fcmToken,
              ))
          .toList(),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentModel payment;
  final String memberId;
  final String memberName;
  final String? fcmToken;

  const _PaymentCard({
    required this.payment,
    required this.memberId,
    required this.memberName,
    required this.fcmToken,
  });

  Color get _statusColor {
    switch (payment.status) {
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.unpaid:
        return Colors.red;
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.rejected:
        return Colors.red.shade800;
    }
  }

  IconData get _statusIcon {
    switch (payment.status) {
      case PaymentStatus.paid:
        return Icons.check_circle;
      case PaymentStatus.unpaid:
        return Icons.cancel;
      case PaymentStatus.pending:
        return Icons.hourglass_empty;
      case PaymentStatus.rejected:
        return Icons.remove_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (payment.status == PaymentStatus.unpaid ||
              payment.status == PaymentStatus.rejected) {
            context.pushNamed('uploadReceipt', extra: {
              'paymentId': payment.id,
              'periodLabel': payment.periodLabel,
              'memberId': memberId,
              'memberName': memberName,
              'fcmToken': fcmToken,
            });
          } else if (payment.transactionId != null) {
            context.pushNamed('transactionTimeline',
                pathParameters: {'id': payment.transactionId!});
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.periodLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      '${payment.type == PaymentType.monthly ? "شهري" : "سنوي"} · ${payment.amount.toStringAsFixed(0)} ر.ع',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(payment.statusLabel,
                        style: TextStyle(
                            color: _statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ),
                  if (payment.status == PaymentStatus.unpaid ||
                      payment.status == PaymentStatus.rejected) ...[
                    const SizedBox(height: 6),
                    const Text('اضغط لرفع إيصال',
                        style:
                            TextStyle(color: AppColors.primary, fontSize: 11)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
