import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('receipt upload never creates a long-lived download token', () {
    final storage = source('lib/data/services/storage_service.dart');
    final receiptSection = storage.substring(
      storage.indexOf('Future<StorageUploadResult> uploadReceipt'),
      storage.indexOf('Future<void> deleteReceipt'),
    );
    expect(receiptSection, isNot(contains('getDownloadURL')));
    expect(receiptSection, contains('fullPath: ref.fullPath'));

    final financial = source('lib/data/repositories/financial_repository.dart');
    final booking = source('lib/data/repositories/booking_repository.dart');
    expect(financial, isNot(contains("'receiptUrl': receiptUrl")));
    expect(booking, isNot(contains("'receiptUrl': receiptUrl")));
  });

  test('all receipt viewers use callable access instead of stored URLs', () {
    for (final path in [
      'lib/presentation/screens/admin/admin_review_screen.dart',
      'lib/presentation/screens/admin/financial_review_screen.dart',
      'lib/presentation/screens/member/transaction_timeline_screen.dart',
    ]) {
      final contents = source(path);
      expect(contents, contains('getFinancialReceiptAccess'), reason: path);
      expect(contents, isNot(contains('Image.network')), reason: path);
      expect(contents, isNot(contains('transaction.receiptUrl')), reason: path);
      expect(contents, isNot(contains('tx.receiptUrl')), reason: path);
    }
  });

  test('financial member administration follows every server page', () {
    final contents = source('lib/data/repositories/financial_repository.dart');
    final section = contents.substring(
      contents
          .indexOf('Future<List<MemberDirectoryEntry>> listFinancialMembers'),
      contents
          .indexOf('Stream<List<FinancialCharge>> streamOrganizationCharges'),
    );
    expect(section, contains("'pageSize': 50"));
    expect(section, contains("'pageToken': pageToken"));
    expect(section, contains("result.data['nextPageToken']"));
    expect(section, contains('seenTokens'));
  });

  test('debug local notification hook is absent from release sources', () {
    final receiver = source(
      'android/app/src/debug/kotlin/com/alrahmat/village_council/'
      'QaLocalNotificationReceiver.kt',
    );
    final debugManifest = source('android/app/src/debug/AndroidManifest.xml');
    final mainManifest = source('android/app/src/main/AndroidManifest.xml');
    expect(receiver, contains('setOf(5000, 7500, 8000, 12500)'));
    expect(receiver, contains(r'return "$rials.$fraction"'));
    expect(debugManifest, contains('.QaLocalNotificationReceiver'));
    expect(mainManifest, isNot(contains('QaLocalNotificationReceiver')));
  });

  test('user-facing financial surfaces do not expose raw baisa wording', () {
    final roots = [Directory('lib/presentation'), Directory('lib/features')];
    final files = roots
        .expand((root) => root.listSync(recursive: true))
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final contents = file.readAsStringSync();
      expect(contents, isNot(contains('بيسة')), reason: file.path);
    }
  });

  test(
      'booking calendar uses redacted availability while my bookings stay owner-scoped',
      () {
    final screen = source(
      'lib/presentation/screens/member/council_booking_screen.dart',
    );
    expect(screen, contains('bookingAvailabilityProvider'));
    expect(screen, isNot(contains('organizationBookingsProvider')));
    expect(screen, contains('userBookingsProvider'));

    final repository = source('lib/data/repositories/booking_repository.dart');
    expect(repository, contains("httpsCallable('getBookingAvailability')"));
    expect(repository, contains(".where('userId', isEqualTo: userId)"));
  });
}
