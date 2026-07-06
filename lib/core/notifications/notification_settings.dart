import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات إشعارات المستخدم (صوت/اهتزاز). تُحفظ محليًّا (shared_preferences)
/// ليقرأها NotificationService بسرعة حتى في الخلفية، وعلى Firestore
/// (users/{uid}.notificationSettings) لتقرأها Cloud Function عند إرسال Push
/// فتحترم اختيار المستخدم للصوت حتى والتطبيق مغلق.
@immutable
class NotificationSettings {
  const NotificationSettings({
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  final bool soundEnabled;
  final bool vibrationEnabled;

  NotificationSettings copyWith({bool? soundEnabled, bool? vibrationEnabled}) {
    return NotificationSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
      };

  factory NotificationSettings.fromMap(Map<String, dynamic>? map) {
    return NotificationSettings(
      soundEnabled: map?['soundEnabled'] as bool? ?? true,
      vibrationEnabled: map?['vibrationEnabled'] as bool? ?? true,
    );
  }

  /// القناة المطابقة للتفضيلات. لأن أندرويد يثبّت الصوت/الاهتزاز عند إنشاء
  /// القناة، نُنشئ قناةً لكل تركيبة ونختار الملائمة (بدل تعديل قناة قائمة).
  String get channelId {
    if (soundEnabled && vibrationEnabled) return 'vc_high_sv';
    if (soundEnabled && !vibrationEnabled) return 'vc_high_s';
    if (!soundEnabled && vibrationEnabled) return 'vc_silent_v';
    return 'vc_silent';
  }
}

/// القنوات الأربع (تُنشأ جميعها مرة واحدة عند الإقلاع؛ نختار منها حسب التفضيل).
const List<AndroidNotificationChannel> kNotificationChannels = [
  AndroidNotificationChannel(
    'vc_high_sv',
    'إشعارات المجلس (صوت واهتزاز)',
    description: 'إشعارات الطلبات والاعتمادات مع صوت واهتزاز',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  ),
  AndroidNotificationChannel(
    'vc_high_s',
    'إشعارات المجلس (صوت فقط)',
    description: 'إشعارات المجلس بصوت دون اهتزاز',
    importance: Importance.high,
    playSound: true,
    enableVibration: false,
  ),
  AndroidNotificationChannel(
    'vc_silent_v',
    'إشعارات المجلس (اهتزاز فقط)',
    description: 'إشعارات المجلس باهتزاز دون صوت',
    importance: Importance.high,
    playSound: false,
    enableVibration: true,
  ),
  AndroidNotificationChannel(
    'vc_silent',
    'إشعارات المجلس (صامت)',
    description: 'إشعارات المجلس دون صوت أو اهتزاز',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  ),
  // قناة قديمة تحسّبًا لإصدار سابق من Cloud Function لم يُعَد نشره بعد
  // (يرسل channelId=village_council_high). تبقى صالحة حتى لا تُسقط إشعارات الخلفية.
  AndroidNotificationChannel(
    'village_council_high',
    'إشعارات مجلس القرية',
    description: 'إشعارات اعتماد الدفعات ومتابعة الطلبات',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  ),
];

/// مخزن التفضيلات: قراءة/كتابة محلية + مزامنة إلى Firestore.
class NotificationSettingsStore {
  static const _soundKey = 'notif_sound_enabled';
  static const _vibrationKey = 'notif_vibration_enabled';

  /// قراءة سريعة محليّة (يستخدمها NotificationService لاختيار القناة).
  static Future<NotificationSettings> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return NotificationSettings(
        soundEnabled: prefs.getBool(_soundKey) ?? true,
        vibrationEnabled: prefs.getBool(_vibrationKey) ?? true,
      );
    } catch (_) {
      return const NotificationSettings();
    }
  }

  static Future<void> _saveLocal(NotificationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, settings.soundEnabled);
    await prefs.setBool(_vibrationKey, settings.vibrationEnabled);
  }

  /// حفظ محليًّا وعلى Firestore (لتقرأه Cloud Function للـ Push الخلفي).
  static Future<void> save(NotificationSettings settings) async {
    await _saveLocal(settings);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'notificationSettings': settings.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      debugPrint('[NotifSettings] firestore sync skipped: ${error.code}');
    }
  }
}

class NotificationSettingsController extends StateNotifier<NotificationSettings> {
  NotificationSettingsController() : super(const NotificationSettings()) {
    _load();
  }

  Future<void> _load() async {
    state = await NotificationSettingsStore.loadLocal();
  }

  Future<void> setSound(bool enabled) async {
    state = state.copyWith(soundEnabled: enabled);
    await NotificationSettingsStore.save(state);
  }

  Future<void> setVibration(bool enabled) async {
    state = state.copyWith(vibrationEnabled: enabled);
    await NotificationSettingsStore.save(state);
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsController, NotificationSettings>(
  (ref) => NotificationSettingsController(),
);
