import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/util/format.dart';

void main() {
  test('percent rounds to nearest whole percent', () {
    expect(percent(0.5), '50%');
    expect(percent(0.424), '42%');
    expect(percent(1.2), '120%');
  });

  test('number drops trailing .0 for whole values, else one decimal', () {
    expect(number(2.0), '2');
    expect(number(2.5), '2.5');
    expect(number(0.45), '0.5');
  });

  test('cadence preserves up to two decimals and strips trailing zeroes', () {
    expect(cadence(2.0), '2');
    expect(cadence(0.24), '0.24');
    expect(cadence(0.45), '0.45');
    expect(cadence(0.65), '0.65');
    // One-decimal values keep a single digit, not "0.50".
    expect(cadence(0.5), '0.5');
    expect(cadence(1.12), '1.12');
    // Rounds to two decimals from noisier inputs.
    expect(cadence(0.246), '0.25');
  });
}
