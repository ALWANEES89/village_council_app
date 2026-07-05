import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.showLocalNotification(message);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  final _androidChannel = const AndroidNotificationChannel(
    'village_council_high',
    'إشعارات مجلس القرية',
    description: 'إشعارات اعتماد الدفعات ومتابعة الطلبات',
    importance: Importance.high,
  );

  Future<void> init() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    FirebaseMessaging.onMessage.listen(showLocalNotification);

    // Keep the signed-in user's FCM token synced so the Cloud Function can
    // deliver a device push for every notification created for that user.
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user != null) {
          unawaited(registerTokenForUser(user.uid));
        }
      },
    );
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      unawaited(registerTokenForUser(currentUser.uid));
    }
  }

  Future<String?> getToken() async => await _fcm.getToken();

  /// Fetches the device FCM token and stores it on `users/{userId}`, and keeps
  /// it updated on refresh. Best-effort: failures never surface to the user.
  Future<void> registerTokenForUser(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await _persistToken(userId, token);
      }
    } catch (error) {
      debugPrint('[Push] token registration skipped: $error');
    }
    _tokenRefreshSubscription ??= _fcm.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && token.isNotEmpty) {
        unawaited(_persistToken(uid, token));
      }
    });
  }

  Future<void> _persistToken(String userId, String token) async {
    final firestore = FirebaseFirestore.instance;
    try {
      await firestore.collection('users').doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    } on FirebaseException catch (error) {
      debugPrint('[Push] users token persist skipped code=${error.code}');
    }
    // Fallback for legacy accounts that only have a members/{uid} document
    // (no users/{uid} doc, or its update failed). The Cloud Function also
    // reads members.fcmToken, so the push still reaches these users.
    try {
      await firestore.collection('members').doc(userId).update({
        'fcmToken': token,
      });
    } on FirebaseException catch (error) {
      debugPrint('[Push] members token persist skipped code=${error.code}');
    }
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> sendNotificationToMember({
    required String fcmToken,
    required String title,
    required String body,
  }) async {
    await FirebaseFirestore.instance.collection('notifications_queue').add({
      'token': fcmToken,
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
