/// Normalize Arabic and Persian digits without modifying a user's edit buffer.
String normalizeNumber(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in input.trim().runes) {
    final character = String.fromCharCode(rune);
    final arabicIndex = arabic.indexOf(character);
    final persianIndex = persian.indexOf(character);
    if (arabicIndex >= 0) {
      buffer.write(arabicIndex);
    } else if (persianIndex >= 0) {
      buffer.write(persianIndex);
    } else {
      buffer.write(character == '٫' ? '.' : character);
    }
  }
  return buffer.toString();
}

/// Plain decimal notation only: no exponent, grouping separator, NaN or infinity.
double? parseDecimal(String input) {
  final normalized = normalizeNumber(input);
  if (!RegExp(r'^\+?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(normalized)) {
    return null;
  }
  final value = double.tryParse(normalized);
  return value != null && value.isFinite && value >= 0 ? value : null;
}

int? parsePositiveCount(String input) {
  final normalized = normalizeNumber(input);
  if (!RegExp(r'^\d+$').hasMatch(normalized)) return null;
  final value = int.tryParse(normalized);
  // Exact integer arithmetic across mobile and JavaScript targets.
  return value != null && value > 0 && value <= 9007199254740991 ? value : null;
}

String formatNumber(num value) {
  if (!value.isFinite) return '—';
  final fixed = _expandExponent(value.toStringAsFixed(2));
  final parts = fixed.split('.');
  final integer = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  if (parts.length == 1) return integer;
  final fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? integer : '$integer.$fraction';
}

String inputNumber(num value) => _expandExponent(
  value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toString(),
);

// Dart switches to exponent notation for large/small finite doubles. Expand it
// so a persisted valid input remains a valid plain-decimal edit buffer.
String _expandExponent(String value) {
  final match = RegExp(
    r'^(-?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$',
  ).firstMatch(value);
  if (match == null) return value;
  final sign = match[1]!;
  final integer = match[2]!;
  final fraction = match[3] ?? '';
  final digits = integer + fraction;
  final position = integer.length + int.parse(match[4]!);
  if (position <= 0) return '${sign}0.${'0' * -position}$digits';
  if (position >= digits.length) {
    return '$sign$digits${'0' * (position - digits.length)}';
  }
  return '$sign${digits.substring(0, position)}.${digits.substring(position)}';
}
