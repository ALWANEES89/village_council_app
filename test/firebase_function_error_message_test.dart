import 'package:flutter_test/flutter_test.dart';
import 'package:village_council_app/core/errors/firebase_function_error_message.dart';

void main() {
  const fallback = 'تعذر تنفيذ العملية.';
  const unavailable = 'الخدمة المطلوبة غير متاحة في إصدار الخادم الحالي.';

  test('missing callable is reported as a server-version problem', () {
    expect(
      firebaseFunctionErrorMessageForCode(
        'not-found',
        fallback: fallback,
        unavailableMessage: unavailable,
      ),
      unavailable,
    );
    expect(
      firebaseFunctionErrorMessageForCode(
        'unimplemented',
        fallback: fallback,
        unavailableMessage: unavailable,
      ),
      unavailable,
    );
  });

  test('permission and connectivity failures have actionable messages', () {
    expect(
      firebaseFunctionErrorMessageForCode(
        'permission-denied',
        fallback: fallback,
        unavailableMessage: unavailable,
      ),
      contains('الصلاحية'),
    );
    expect(
      firebaseFunctionErrorMessageForCode(
        'unavailable',
        fallback: fallback,
        unavailableMessage: unavailable,
      ),
      contains('الإنترنت'),
    );
    expect(
      firebaseFunctionErrorMessageForCode(
        'internal',
        fallback: fallback,
        unavailableMessage: unavailable,
      ),
      fallback,
    );
  });
}
