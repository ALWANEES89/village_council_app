import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).asData?.value;
    final count = user == null
        ? 0
        : ref.watch(unreadNotificationsCountProvider(user.uid));
    return IconButton(
      tooltip: 'الإشعارات',
      onPressed: user == null ? null : () => context.pushNamed('notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(Icons.notifications_none_rounded, color: color),
      ),
    );
  }
}
