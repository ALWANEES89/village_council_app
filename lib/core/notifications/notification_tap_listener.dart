import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/notification_service.dart';
import '../../providers/app_providers.dart';
import 'notification_deeplink.dart';

/// يلفّ محتوى التطبيق ويستمع لنقرات إشعارات Push (خلفية/إغلاق) والإشعارات
/// المحلية، فيوجّه المستخدم إلى الشاشة الصحيحة عبر [NotificationDeepLink].
class NotificationTapListener extends ConsumerStatefulWidget {
  const NotificationTapListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationTapListener> createState() =>
      _NotificationTapListenerState();
}

class _NotificationTapListenerState
    extends ConsumerState<NotificationTapListener> {
  StreamSubscription<Map<String, String>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        NotificationService.instance.onNotificationTap.listen(_handle);
    // فتح التطبيق من الإغلاق عبر النقر على إشعار: عالِجه بعد أوّل إطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.instance.consumePendingTap();
      if (pending != null) _handle(pending);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handle(Map<String, String> data) {
    if (!mounted) return;
    // لا نوجّه قبل تسجيل الدخول (تُعالَج بقية التدفّقات عبر redirect الراوتر).
    if (ref.read(authStateProvider).value == null) return;
    final organizationId = data['organizationId'];
    NotificationDeepLink.open(
      context,
      ref,
      type: data['type'] ?? '',
      relatedEntityType: data['relatedEntityType'] ?? '',
      relatedEntityId: data['relatedEntityId'] ?? '',
      organizationId: (organizationId == null || organizationId.isEmpty)
          ? null
          : organizationId,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
