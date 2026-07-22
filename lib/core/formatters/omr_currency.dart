const String omrCurrencyCode = 'OMR';
const String omrSystemCurrencyLabel = 'ر.ع.';

String formatOmaniRialNumber(int amountBaisa) {
  final sign = amountBaisa < 0 ? '-' : '';
  final absolute = amountBaisa.abs();
  final rials = absolute ~/ 1000;
  final baisa = (absolute % 1000).toString().padLeft(3, '0');
  return '$sign$rials.$baisa';
}

/// Text fallback for surfaces that cannot embed the official image asset,
/// notably Android system notification text.
String formatOmaniRialForSystemNotification(int amountBaisa) =>
    '${formatOmaniRialNumber(amountBaisa)} $omrSystemCurrencyLabel';

/// Parses rial input using integer arithmetic. More than three fractional
/// digits are rejected instead of rounded so the stored amount remains exact.
int? parseOmaniRialInput(String input) {
  const arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
  const easternArabicDigits = '۰۱۲۳۴۵۶۷۸۹';
  var normalized = input.trim();
  for (var index = 0; index < 10; index++) {
    normalized = normalized
        .replaceAll(arabicIndicDigits[index], '$index')
        .replaceAll(easternArabicDigits[index], '$index');
  }
  normalized =
      normalized.replaceAll('٫', '.').replaceAll(',', '.').replaceAll('٬', '');
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(normalized)) return null;

  final parts = normalized.split('.');
  final rials = int.tryParse(parts.first);
  if (rials == null) return null;
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0'));
  return rials * 1000 + fraction;
}

/// Converts legacy rial values for display only. New financial calculations
/// and storage continue to use integer baisa fields.
int legacyOmaniRialDisplayBaisa(num value) => (value * 1000).round();
