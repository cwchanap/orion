import '../models/game_models.dart';

class StageModifierMetadata {
  const StageModifierMetadata({required this.title, required this.description});

  final String title;
  final String description;

  static const standardConditions = StageModifierMetadata(
    title: 'Standard Conditions',
    description: 'No environmental modifiers',
  );

  static StageModifierMetadata forModifier(StageModifier modifier) {
    return switch (modifier) {
      StageModifier.shieldRecharge => StageModifierMetadata(
        title: 'Shield Recharge',
        description:
            'Shielded enemies recharge '
            '${_percent(GameBalance.shieldRechargeRatePerSecond)} max shields '
            'per second after '
            '${_number(GameBalance.shieldRechargeDelay)} seconds without damage.',
      ),
      StageModifier.swarmBounty => StageModifierMetadata(
        title: 'Swarm Bounty',
        description:
            'Swarm enemies grant '
            '${_percent(GameBalance.swarmBountyMultiplier - 1)} more kill gold, '
            'rounded to whole gold.',
      ),
      StageModifier.reinforcedArmor => StageModifierMetadata(
        title: 'Reinforced Armor',
        description:
            'Armored enemies gain '
            '${(GameBalance.reinforcedArmorBonus * 100).round()} percentage '
            'points of armor.',
      ),
      StageModifier.regenPressurePulses => StageModifierMetadata(
        title: 'Pressure Pulses',
        description:
            'Regen enemies arrive in bursts of '
            '${GameBalance.regenPulseBurstSize}.',
      ),
      StageModifier.reducedStartingHealth => StageModifierMetadata(
        title: 'Fragile Base',
        description:
            'Begin with ${GameBalance.reducedStartingHealthPenalty} less base health.',
      ),
      StageModifier.enhancedClearBonus => StageModifierMetadata(
        title: 'Salvage Reserves',
        description:
            'Wave clear bonuses are increased by '
            '${_percent(GameBalance.enhancedClearBonusMultiplier - 1)}.',
      ),
      StageModifier.enemySpeedSurge => StageModifierMetadata(
        title: 'Temporal Surge',
        description:
            'Enemies move '
            '${_percent(GameBalance.enemySpeedSurgeMultiplier - 1)} faster.',
      ),
      StageModifier.amplifiedGravityWells => StageModifierMetadata(
        title: 'Amplified Wells',
        description:
            'Gravity Well fields gain '
            '${_percent(GameBalance.amplifiedGravityWellRadiusMultiplier - 1)} '
            'radius and '
            '${_percent(GameBalance.amplifiedGravityWellDurationMultiplier - 1)} '
            'duration.',
      ),
    };
  }

  static String _percent(double value) => '${(value * 100).round()}%';

  static String _number(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }
}
