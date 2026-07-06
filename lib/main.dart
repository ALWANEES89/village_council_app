import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/notifications/notification_tap_listener.dart';
import 'router/app_router.dart';
import 'data/services/organization_seed_service.dart';
import 'data/services/notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  OrganizationSeedService.instance.start();
  // Push notifications: request permission, wire handlers and keep the signed-in
  // user's FCM token synced. Best-effort so it never blocks app startup.
  await NotificationService.instance.init().catchError((_) {});
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
          child: NotificationTapListener(child: child!),
        );
      },
    );
  }
}
