/// Shared, dependency-free formatting helpers used by campaign metadata and
/// the codex. Lives in neutral `util/` so neither layer depends on the other.
String percent(double value) => '${(value * 100).round()}%';

String number(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

/// Precision-preserving formatter for cadence values (fire intervals, field
/// tick intervals, drone attack intervals). Rounds to at most two decimals and
/// strips trailing zeroes so 0.24, 0.45, and 0.65 keep their distinguishing
/// precision instead of collapsing to 0.2 / 0.5 / 0.7 as `number` would.
/// Integers render without a decimal point.
String cadence(double value) => decimal(value);

/// General precision-preserving decimal formatter. Rounds to at most two
/// decimals and strips trailing zeroes so values like 1.55 and 1.65 keep their
/// distinguishing precision instead of collapsing to 1.6 as `number` would.
/// Integers render without a decimal point. Used for damage multipliers and
/// other non-cadence values where one-decimal rounding would lose tuning
/// precision.
String decimal(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
