import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/firebase/firebase_app_check_config.dart';
import 'core/firebase/firebase_emulator_config.dart';
import 'core/notifications/notification_tap_listener.dart';
import 'router/app_router.dart';
import 'data/services/notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseEmulatorConfig.initialize(
    DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseEmulatorConfig.connectIfRequested();
  await FirebaseAppCheckConfig.activate();
  // Push notifications: request permission, wire handlers and keep the signed-in
  // user's FCM token synced. Best-effort so it never blocks app startup.
  if (!FirebaseEmulatorConfig.enabled) {
    await NotificationService.instance.init().catchError((_) {});
  }
  await initializeDateFormatting('ar', null);
  runApp(const ProviderScope(child: VillageCouncilApp()));
}

class VillageCouncilApp extends ConsumerWidget {
  const VillageCouncilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'مجلس القرية',
      theme: AppTheme.theme,
      routerConfig: router,
      builder: (context, child) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Stack(
            children: [
              NotificationTapListener(child: child!),
              if (kDebugMode && FirebaseEmulatorConfig.enabled)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Colors.deepOrange,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          'بيئة اختبار محلية',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
