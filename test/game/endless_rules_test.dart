import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/endless_rules.dart';

void main() {
  group('EndlessRules', () {
    const script = GameBalance.waves;

    test(
      'waveAt wraps the script by index and returns identical instances',
      () {
        const expectations = {0: 0, 7: 7, 8: 0, 15: 7, 16: 0};

        for (final entry in expectations.entries) {
          expect(
            identical(
              EndlessRules.waveAt(script, entry.key),
              script[entry.value],
            ),
            isTrue,
            reason:
                'waveIndex ${entry.key} should map to script[${entry.value}]',
          );
        }
      },
    );

    test('loopFor returns the completed-loop index for each wave', () {
      const expectations = {0: 0, 7: 0, 8: 1, 15: 1, 16: 2};

      for (final entry in expectations.entries) {
        expect(
          EndlessRules.loopFor(entry.key, script.length),
          entry.value,
          reason: 'waveIndex ${entry.key} should be in loop ${entry.value}',
        );
      }
    });

    test('healthMultiplier compounds by loop index', () {
      const expectations = {0: 1.0, 1: 1.6, 2: 2.56, 3: 4.096};

      for (final entry in expectations.entries) {
        final waveIndex = entry.key * script.length;
        expect(
          EndlessRules.healthMultiplier(waveIndex, script.length),
          closeTo(entry.value, 1e-9),
          reason: 'loop ${entry.key} should scale by ${entry.value}',
        );
      }
    });
  });
}
