import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class FirebaseEmulatorConfig {
  const FirebaseEmulatorConfig._();

  static const enabled = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  static const host = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
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

  static Future<void> connectIfRequested() async {
    if (!enabled) return;
    if (kReleaseMode) {
      throw StateError(
          'Firebase Emulator mode cannot be enabled in release builds.');
    }
    if (host.trim().isEmpty) {
      throw StateError(
        'FIREBASE_EMULATOR_HOST is required when USE_FIREBASE_EMULATORS=true.',
      );
    }
    await FirebaseAuth.instance.useAuthEmulator(host, authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
    FirebaseFunctions.instance.useFunctionsEmulator(host, functionsPort);
    await FirebaseStorage.instance.useStorageEmulator(host, storagePort);
  }
}
