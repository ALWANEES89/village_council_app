import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/notifications/notification_settings.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // في الخلفية/الإغلاق يَعرض النظامُ إشعارَ FCM تلقائيًّا (الحمولة تحوي
  // notification) باستخدام القناة المحددة من Cloud Function/manifest — فلا
  // نعرض نسخةً ثانية هنا منعًا للتكرار. النقر يُعالَج عبر
  // onMessageOpenedApp (خلفية) و getInitialMessage (إغلاق).
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  final _tapController = StreamController<Map<String, String>>.broadcast();
  Map<String, String>? _pendingInitialTap;

  /// يبثّ حمولة (data) الإشعار عند النقر عليه — Push في الخلفية أو إشعار محلي
  /// في المقدّمة — ليُوجّه الجذرُ المستخدمَ إلى الشاشة الصحيحة.
  Stream<Map<String, String>> get onNotificationTap => _tapController.stream;

  Future<void> init() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // صلاحية الإشعارات على أندرويد 13+.
    await androidPlugin?.requestNotificationsPermission();
    // أنشئ كل القنوات مرّة واحدة؛ نختار منها حسب تفضيل المستخدم عند العرض.
    for (final channel in kNotificationChannels) {
      await androidPlugin?.createNotificationChannel(channel);
    }

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // المقدّمة: FCM لا يعرض تلقائيًّا، فنعرض إشعارًا محليًّا بقناة المستخدم.
    FirebaseMessaging.onMessage.listen(showLocalNotification);
    // نقر إشعار Push والتطبيق في الخلفية.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _emitTap(m.data));
    // فتح التطبيق من الإغلاق عبر النقر على إشعار: نخزّنه ليستهلكه الجذر.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _pendingInitialTap = _stringify(initial.data);

    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user != null) unawaited(registerTokenForUser(user.uid));
      },
    );
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      unawaited(registerTokenForUser(currentUser.uid));
    }
  }

  /// يُرجع (ويستهلك مرّة واحدة) الإشعار الذي فُتح به التطبيق من حالة الإغلاق.
  Map<String, String>? consumePendingTap() {
    final pending = _pendingInitialTap;
    _pendingInitialTap = null;
    return pending;
  }

  void _emitTap(Map<String, dynamic> data) => _tapController.add(_stringify(data));

  Map<String, String> _stringify(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, '${value ?? ''}'));

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      _emitTap(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<String?> getToken() async => await _fcm.getToken();

  /// يجلب توكن الجهاز ويحفظه على `users/{uid}`، ويحدّثه عند التغيّر.
  /// أفضل جهد: لا تظهر الأخطاء للمستخدم.
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
    // توافق خلفي للحسابات التي تملك members/{uid} فقط.
    try {
      await firestore.collection('members').doc(userId).update({
        'fcmToken': token,
      });
    } on FirebaseException catch (error) {
      debugPrint('[Push] members token persist skipped code=${error.code}');
    }
  }

  /// حذف توكن هذا الجهاز عند تسجيل الخروج حتى لا تصل إشعارات المستخدم السابق.
  Future<void> deleteTokenForUser(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
      await _fcm.deleteToken();
    } catch (error) {
      debugPrint('[Push] token deletion skipped: $error');
    }
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final settings = await NotificationSettingsStore.loadLocal();
    final channelId = settings.channelId;
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelName(channelId),
          channelDescription: 'إشعارات المجلس',
          importance: settings.soundEnabled || settings.vibrationEnabled
              ? Importance.high
              : Importance.low,
          priority: Priority.high,
          playSound: settings.soundEnabled,
          enableVibration: settings.vibrationEnabled,
        ),
        iOS: DarwinNotificationDetails(presentSound: settings.soundEnabled),
      ),
      payload: jsonEncode(message.data),
    );
  }

  String _channelName(String id) => kNotificationChannels
      .firstWhere((c) => c.id == id, orElse: () => kNotificationChannels.first)
      .name;

  /// توافق خلفي: مسار الطابور القديم (لم يعد يُستخدم بعد onNotificationCreated).
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
