/// Shared, dependency-free formatting helpers used by campaign metadata and
/// the codex. Lives in neutral `util/` so neither layer depends on the other.
String percent(double value) => '${(value * 100).round()}%';

String number(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
