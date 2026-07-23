import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import 'firebase_emulator_config.dart';

class FirebaseAppCheckConfig {
  const FirebaseAppCheckConfig._();

  static Future<void> activate() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return Future<void>.value();
    }
    const debugProvider = kDebugMode || FirebaseEmulatorConfig.enabled;
    return FirebaseAppCheck.instance.activate(
      androidProvider:
          debugProvider ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          debugProvider ? AppleProvider.debug : AppleProvider.appAttest,
    );
  }
}
