import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class FirebaseEmulatorConfig {
  const FirebaseEmulatorConfig._();

  static const enabled = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  static const host = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const qaProjectId = 'demo-financial-prestaging';
  static const authPort = int.fromEnvironment(
    'FIREBASE_AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const firestorePort = int.fromEnvironment(
    'FIRESTORE_EMULATOR_PORT',
    defaultValue: 8080,
  );
  static const functionsPort = int.fromEnvironment(
    'FIREBASE_FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );
  static const storagePort = int.fromEnvironment(
    'FIREBASE_STORAGE_EMULATOR_PORT',
    defaultValue: 9199,
  );

  static FirebaseOptions optionsFor(FirebaseOptions defaultOptions) {
    if (!enabled) return defaultOptions;
    _validateSafety();
    return FirebaseOptions(
      apiKey: defaultOptions.apiKey,
      appId: defaultOptions.appId,
      messagingSenderId: defaultOptions.messagingSenderId,
      projectId: projectId,
      storageBucket: '$projectId.appspot.com',
      iosClientId: defaultOptions.iosClientId,
      iosBundleId: defaultOptions.iosBundleId,
    );
  }

  static Future<void> initialize(FirebaseOptions defaultOptions) async {
    final app = await Firebase.initializeApp(
      options: optionsFor(defaultOptions),
    );
    if (enabled && app.options.projectId != projectId) {
      throw StateError(
        'Firebase initialized with an unexpected projectId: '
        '${app.options.projectId}.',
      );
    }
  }

  static Future<void> connectIfRequested() async {
    if (!enabled) return;
    _validateSafety();
    if (host.trim().isEmpty) {
      throw StateError(
        'FIREBASE_EMULATOR_HOST is required when USE_FIREBASE_EMULATORS=true.',
      );
    }
    await FirebaseAuth.instance.useAuthEmulator(
      host,
      authPort,
      automaticHostMapping: false,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      firestorePort,
      automaticHostMapping: false,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      host,
      functionsPort,
      automaticHostMapping: false,
    );
    await FirebaseStorage.instance.useStorageEmulator(
      host,
      storagePort,
      automaticHostMapping: false,
    );
  }

  static void _validateSafety() {
    if (kReleaseMode) {
      throw StateError(
          'Firebase Emulator mode cannot be enabled in release builds.');
    }
    if (projectId != qaProjectId) {
      throw StateError(
        'Firebase Emulator mode requires projectId=$qaProjectId.',
      );
    }
  }
}
