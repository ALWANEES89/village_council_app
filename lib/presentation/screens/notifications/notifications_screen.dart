import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_deeplink.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/omr_amount.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).asData?.value;
    final notifications =
        user == null ? null : ref.watch(userNotificationsProvider(user.uid));
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('الإشعارات'),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          actions: [
            if (user != null)
              TextButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(notificationRepositoryProvider)
                        .markAllAsRead(user.uid);
                  } catch (_) {
                    if (context.mounted) _showError(context);
                  }
                },
                child: const Text(
                  'قراءة الكل',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
        body: notifications == null
            ? const Center(child: Text('سجّل الدخول لعرض الإشعارات'))
            : notifications.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(
                  child: Text('تعذر تحميل الإشعارات. حاول مرة أخرى.'),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('لا توجد إشعارات'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _NotificationCard(
                          notification: items[index],
                          onTap: () => _openNotification(
                            context,
                            ref,
                            user!.uid,
                            items[index],
                          ),
                        ),
                      ),
              ),
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    String userId,
    AppNotificationModel notification,
  ) async {
    if (notification.isUnread) {
      try {
        await ref.read(notificationRepositoryProvider).markAsRead(
              userId,
              notification.notificationId,
            );
      } catch (_) {
        if (context.mounted) _showError(context);
        return;
      }
    }
    if (!context.mounted) return;

    // التوجيه الموحّد (نفسه المستخدَم عند النقر على Push الخارجي).
    await NotificationDeepLink.open(
      context,
      ref,
      type: notification.type,
      relatedEntityType: notification.relatedEntityType,
      relatedEntityId: notification.relatedEntityId,
      organizationId: notification.organizationId,
    );
  }

  static void _showError(BuildContext context, {String? message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'تعذر تحديث الإشعار. حاول مرة أخرى.'),
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotificationModel notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organization = notification.organizationId == null
        ? null
        : ref.watch(
            organizationDetailsProvider(notification.organizationId!),
          );
    final organizationName = organization?.maybeWhen(
      data: (data) {
        final official = data?['officialNameArabic'];
        if (official is String && official.isNotEmpty) return official;
        final short = data?['shortName'];
        return short is String ? short : null;
      },
      orElse: () => null,
    );
    return Card(
      color: notification.isUnread ? const Color(0xFFF2EAFF) : Colors.white,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(_notificationIcon(notification.type)),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight:
                notification.isUnread ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NotificationBody(notification: notification),
            if (organizationName?.isNotEmpty == true) Text(organizationName!),
            Text(
              DateFormat('yyyy/MM/dd - HH:mm').format(notification.createdAt),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: notification.isUnread
            ? const Icon(Icons.circle, size: 10, color: AppColors.primary)
            : null,
      ),
    );
  }
}

class _NotificationBody extends StatelessWidget {
  const _NotificationBody({required this.notification});

  final AppNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    if (!notification.hasStructuredOmrAmount) {
      return Text(notification.body);
    }
    final parts = notification.bodyTemplate!.split('{amount}');
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (parts.first.isNotEmpty) Text(parts.first),
        OmrAmount(amountBaisa: notification.amountBaisa!),
        if (parts.length > 1 && parts.sublist(1).join('{amount}').isNotEmpty)
          Text(parts.sublist(1).join('{amount}')),
      ],
    );
  }
}

IconData _notificationIcon(String type) {
  if (type.startsWith('booking')) return Icons.event_available_outlined;
  if (type.startsWith('receipt')) return Icons.receipt_long_outlined;
  if (type.startsWith('membership')) return Icons.badge_outlined;
  return Icons.notifications_outlined;
}
