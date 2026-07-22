import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/data/models/financial_models.dart';
import 'package:village_council_app/data/repositories/financial_repository.dart';

void main() {
  test('production receipt access parses a typed HTTPS URL', () {
    final access = FinancialReceiptAccess.fromMap(const {
      'kind': 'url',
      'url': 'https://storage.invalid/signed',
      'fileName': 'receipt.pdf',
      'contentType': 'application/pdf',
    });
    expect(access, isA<FinancialReceiptUrlAccess>());
    expect((access as FinancialReceiptUrlAccess).url.scheme, 'https');
  });

  test('emulator receipt access decodes typed bytes and checks their size', () {
    final bytes = utf8.encode('%PDF-1.7');
    final access = FinancialReceiptAccess.fromMap({
      'kind': 'bytes',
      'bytesBase64': base64Encode(bytes),
      'sizeBytes': bytes.length,
      'fileName': 'receipt.pdf',
      'contentType': 'application/pdf',
    });
    expect(access, isA<FinancialReceiptBytesAccess>());
    expect((access as FinancialReceiptBytesAccess).bytes, bytes);
    expect(
      () => FinancialReceiptAccess.fromMap({
        'kind': 'bytes',
        'bytesBase64': base64Encode(bytes),
        'sizeBytes': bytes.length + 1,
        'fileName': 'receipt.pdf',
        'contentType': 'application/pdf',
      }),
      throwsFormatException,
    );
  });

  test('pending receipt charge is visible but not payable', () {
    final charge = FinancialCharge.fromMap(const {
      'chargeId': 'c1',
      'organizationId': 'o1',
      'membershipId': 'm1',
      'userId': 'u1',
      'chargeType': 'subscription',
      'titleArabic': 'اشتراك',
      'amountDueBaisa': 12500,
      'amountPaidBaisa': 0,
      'balanceBaisa': 12500,
      'status': 'unpaid',
      'hasPendingReceipt': true,
      'pendingTransactionId': 'r1',
    });
    expect(charge.hasPendingReceipt, isTrue);
    expect(charge.pendingTransactionId, 'r1');
    expect(charge.isPayable, isFalse);
  });
}
