/// Formats a whole number with comma thousands separators.
///
/// Examples: `999`, `1,000`, `12,345`, and `-12,345`.
String formatWholeNumber(int value) {
  final sign = value < 0 ? '-' : '';
  final digits = value.abs().toString();
  final formatted = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$sign$formatted';
}
