import 'dart:ui' as ui;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_settings.dart';
import '../../../core/theme/app_theme.dart';

/// إعدادات الإشعارات: تفعيل/إيقاف الصوت والاهتزاز، واختيار نغمة الإشعار عبر
/// إعدادات النظام (لأن أندرويد يثبّت النغمة على مستوى القناة). تُحفظ التفضيلات
/// محليًّا وعلى Firestore فيحترمها Push حتى والتطبيق مغلق.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final controller = ref.read(notificationSettingsProvider.notifier);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('إعدادات الإشعارات'),
          centerTitle: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_up_outlined),
                    title: const Text('صوت الإشعار'),
                    subtitle: const Text('تشغيل صوت عند وصول إشعار'),
                    value: settings.soundEnabled,
                    onChanged: controller.setSound,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.vibration),
                    title: const Text('الاهتزاز'),
                    subtitle: const Text('اهتزاز الجهاز عند وصول إشعار'),
                    value: settings.vibrationEnabled,
                    onChanged: controller.setVibration,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.music_note_outlined),
                title: const Text('اختيار نغمة الإشعار'),
                subtitle: const Text(
                  'يفتح إعدادات إشعارات التطبيق في النظام لاختيار النغمة',
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => AppSettings.openAppSettings(
                  type: AppSettingsType.notification,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يحفظ أندرويد نغمة الإشعار على مستوى القناة، لذا يُختار الصوت '
                      'من إعدادات النظام. مفاتيح الصوت والاهتزاز هنا تُطبَّق فورًا '
                      'على الإشعارات الجديدة داخل التطبيق وخارجه.',
                      style: TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
