import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('normal application startup cannot invoke organization seed writes', () {
    final main = source('lib/main.dart');
    final seed = source('lib/data/services/organization_seed_service.dart');
    final organizations =
        source('lib/data/repositories/organization_repository.dart');
    expect(main, isNot(contains('OrganizationSeedService')));
    expect(organizations, isNot(contains('ensureSeeded()')));
    expect(seed, contains('!kDebugMode || !FirebaseEmulatorConfig.enabled'));
    expect(seed, contains('explicit Debug Emulator run'));
  });

  test(
      'App Check uses debug only for debug/emulator and Play Integrity in release',
      () {
    final config = source('lib/core/firebase/firebase_app_check_config.dart');
    final main = source('lib/main.dart');
    expect(main, contains('FirebaseAppCheckConfig.activate()'));
    expect(config, contains('AndroidProvider.playIntegrity'));
    expect(config, contains('AndroidProvider.debug'));
    expect(config, contains('kDebugMode || FirebaseEmulatorConfig.enabled'));
    expect(config, isNot(contains('token')));
  });

  test('booking mutations and bootstrap are callable-mediated', () {
    final bookings = source('lib/data/repositories/booking_repository.dart');
    final organizations =
        source('lib/data/repositories/organization_repository.dart');
    expect(bookings, contains("httpsCallable('createBooking')"));
    expect(bookings, contains("httpsCallable('reviewBooking')"));
    expect(bookings, isNot(contains('await reference.set')));
    expect(organizations, contains("httpsCallable('bootstrapOrganization')"));
    expect(
      organizations,
      contains("httpsCallable('repairOrganizationStructure')"),
    );
    expect(organizations, isNot(contains('entry.key.set')));
  });

  test('notification repository is read-state only', () {
    final notifications =
        source('lib/data/repositories/notification_repository.dart');
    final pushService = source('lib/data/services/notification_service.dart');
    expect(notifications, isNot(contains('createForUser')));
    expect(notifications, isNot(contains('notifyOrganizationReviewers')));
    expect(notifications, isNot(contains('.set(')));
    expect(notifications, contains("'status': 'read'"));
    expect(pushService, isNot(contains("collection('notifications_queue')")));
    expect(pushService, isNot(contains('sendNotificationToMember')));
  });

  test('Android release signing never falls back to debug credentials', () {
    final gradle = source('android/app/build.gradle.kts');
    final ignore = source('.gitignore');
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('hasReleaseSigning'));
    expect(gradle, contains('VC_RELEASE_STORE_FILE'));
    expect(ignore, contains('android/key.properties'));
    expect(ignore, contains('*.jks'));
  });
}
