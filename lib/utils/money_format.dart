/// Small, display-only Turkish Lira formatter used by the Expense/Bills
/// screen.
///
/// Single consistent style across the whole screen: `₺` prefix, thousands
/// separators, always two decimals (e.g. `₺1,250.00`).
///
/// Never returns NaN, Infinity, or malformed text: null, NaN and infinite
/// inputs fall back to `₺0.00`.
double sanitizeMoneyAmount(num? value) {
  if (value == null) {
    return 0;
  }
  final amount = value.toDouble();
  if (amount.isNaN || amount.isInfinite) {
    return 0;
  }
  return amount;
}

String formatLira(num? value) {
  final amount = sanitizeMoneyAmount(value);
  final isNegative = amount < 0;
  // toStringAsFixed on a finite double never yields NaN/Infinity.
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final fracPart = parts.length > 1 ? parts[1] : '00';

  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    buffer.write(intPart[i]);
    final posFromRight = intPart.length - i;
    if (posFromRight > 1 && posFromRight % 3 == 1) {
      buffer.write(',');
    }
  }

  final sign = isNegative ? '-' : '';
  return '$sign₺${buffer.toString()}.$fracPart';
}
