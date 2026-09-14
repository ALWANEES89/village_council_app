import 'package:cloud_functions/cloud_functions.dart';

String firebaseFunctionErrorMessage(
  Object error, {
  required String fallback,
  required String unavailableMessage,
  String? unauthenticatedMessage,
  String? permissionDeniedMessage,
  String? rateLimitedMessage,
  String? networkMessage,
  String? invalidArgumentMessage,
  String? alreadyExistsMessage,
}) {
  if (error is! FirebaseFunctionsException) return fallback;
  return firebaseFunctionErrorMessageForCode(
    error.code,
    fallback: fallback,
    unavailableMessage: unavailableMessage,
    unauthenticatedMessage: unauthenticatedMessage,
    permissionDeniedMessage: permissionDeniedMessage,
    rateLimitedMessage: rateLimitedMessage,
    networkMessage: networkMessage,
    invalidArgumentMessage: invalidArgumentMessage,
    alreadyExistsMessage: alreadyExistsMessage,
  );
}

String firebaseFunctionErrorMessageForCode(
  String? code, {
  required String fallback,
  required String unavailableMessage,
  String? unauthenticatedMessage,
  String? permissionDeniedMessage,
  String? rateLimitedMessage,
  String? networkMessage,
  String? invalidArgumentMessage,
  String? alreadyExistsMessage,
}) {
  switch (code) {
    case 'not-found':
    case 'unimplemented':
      return unavailableMessage;
    case 'unauthenticated':
      return unauthenticatedMessage ??
          'انتهت جلسة الدخول. سجّل الدخول ثم حاول مجددًا.';
    case 'permission-denied':
      return permissionDeniedMessage ??
          'لا تملك الصلاحية لتنفيذ هذه العملية في المجلس الحالي.';
    case 'resource-exhausted':
      return rateLimitedMessage ??
          'تم تجاوز عدد المحاولات المسموح. انتظر قليلًا ثم حاول مجددًا.';
    case 'unavailable':
    case 'deadline-exceeded':
      return networkMessage ??
          'تعذر الاتصال بالخادم حاليًا. تحقق من الإنترنت ثم حاول مجددًا.';
    case 'invalid-argument':
      return invalidArgumentMessage ??
          'البيانات المدخلة غير صالحة. راجعها ثم حاول مجددًا.';
    case 'already-exists':
      return alreadyExistsMessage ?? 'تم تنفيذ هذه العملية مسبقًا.';
    default:
      return fallback;
  }
}
