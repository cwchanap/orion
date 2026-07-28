import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  test('every modifier has non-empty metadata', () {
    for (final modifier in StageModifier.values) {
      final metadata = StageModifierMetadata.forModifier(modifier);
      expect(metadata.title, isNotEmpty);
      expect(metadata.description, isNotEmpty);
    }
  });

  test('numeric copy matches GameBalance tuning', () {
    expect(
      StageModifierMetadata.forModifier(
        StageModifier.shieldRecharge,
      ).description,
      'Shielded enemies recharge 10% max shields per second after '
      '3 seconds without damage.',
    );
    expect(
      StageModifierMetadata.forModifier(
        StageModifier.amplifiedGravityWells,
      ).description,
      'Gravity Well fields gain 20% radius and 25% duration.',
    );
  });

  test('defines the standard-conditions fallback', () {
    expect(
      StageModifierMetadata.standardConditions.title,
      'Standard Conditions',
    );
    expect(
      StageModifierMetadata.standardConditions.description,
      'No environmental modifiers',
    );
  });
}
