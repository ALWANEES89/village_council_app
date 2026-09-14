import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_deeplink.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/omr_amount.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final user = ref.watch(authStateProvider).asData?.value;
    final notifications =
        user == null ? null : ref.watch(userNotificationsProvider(user.uid));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(strings.notifications),
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
                  if (context.mounted) _showError(context, strings);
                }
              },
              child: Text(
                strings.markAllAsRead,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: notifications == null
          ? Center(child: Text(strings.signInToViewNotifications))
          : notifications.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(strings.couldNotLoadNotifications),
              ),
              data: (items) => items.isEmpty
                  ? Center(child: Text(strings.noNotifications))
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
        if (context.mounted) {
          _showError(context, AppLocalizations.of(context));
        }
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

  static void _showError(
    BuildContext context,
    AppLocalizations strings,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.couldNotUpdateNotification),
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
    final locale = Localizations.localeOf(context).languageCode;
    final organization = notification.organizationId == null
        ? null
        : ref.watch(
            organizationDetailsProvider(notification.organizationId!),
          );
    final organizationName = organization?.maybeWhen(
      data: (data) {
        final official = data == null
            ? null
            : data[
                locale == 'en' ? 'officialNameEnglish' : 'officialNameArabic'];
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
