import 'dart:math' as math;

import '../models/game_models.dart';

class ShieldRechargePolicy {
  const ShieldRechargePolicy({
    required this.delay,
    required this.ratePerSecond,
  });

  final double delay;
  final double ratePerSecond;
}

class EnemyModifierProfile {
  const EnemyModifierProfile({
    this.speedMultiplier = 1,
    this.armorReductionBonus = 0,
    this.shieldRecharge,
  });

  static const identity = EnemyModifierProfile();

  final double speedMultiplier;
  final double armorReductionBonus;
  final ShieldRechargePolicy? shieldRecharge;
}

class StageModifierRules {
  const StageModifierRules._();

  static int effectiveStartingBaseHealth({
    required int campaignAdjustedBaseHealth,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (!stageModifiers.contains(StageModifier.reducedStartingHealth)) {
      return campaignAdjustedBaseHealth;
    }
    return math.max(
      1,
      campaignAdjustedBaseHealth - GameBalance.reducedStartingHealthPenalty,
    );
  }

  static int effectiveKillReward({
    required EnemyStats stats,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (!stageModifiers.contains(StageModifier.swarmBounty) ||
        !stats.hasTrait(EnemyTrait.swarm)) {
      return stats.goldReward;
    }
    return (stats.goldReward * GameBalance.swarmBountyMultiplier).round();
  }

  static EnemyModifierProfile enemyProfile({
    required EnemyStats stats,
    required Iterable<StageModifier> stageModifiers,
  }) {
    final shieldRecharge =
        stageModifiers.contains(StageModifier.shieldRecharge) &&
            stats.hasTrait(EnemyTrait.shielded)
        ? const ShieldRechargePolicy(
            delay: GameBalance.shieldRechargeDelay,
            ratePerSecond: GameBalance.shieldRechargeRatePerSecond,
          )
        : null;
    return EnemyModifierProfile(
      speedMultiplier: stageModifiers.contains(StageModifier.enemySpeedSurge)
          ? GameBalance.enemySpeedSurgeMultiplier
          : 1,
      armorReductionBonus:
          stageModifiers.contains(StageModifier.reinforcedArmor) &&
              stats.hasTrait(EnemyTrait.armored)
          ? GameBalance.reinforcedArmorBonus
          : 0,
      shieldRecharge: shieldRecharge,
    );
  }

  static double nextSpawnDelay({
    required EnemyStats stats,
    required int spawnedInGroup,
    required double baseSpawnInterval,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (!stageModifiers.contains(StageModifier.regenPressurePulses) ||
        !stats.hasTrait(EnemyTrait.regen)) {
      return baseSpawnInterval;
    }
    return spawnedInGroup % GameBalance.regenPulseBurstSize == 0
        ? GameBalance.regenPulseGap
        : GameBalance.regenPulseInterval;
  }

  static int effectiveClearBonus({
    required int campaignAdjustedClearBonus,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (campaignAdjustedClearBonus <= 0 ||
        !stageModifiers.contains(StageModifier.enhancedClearBonus)) {
      return campaignAdjustedClearBonus;
    }
    return (campaignAdjustedClearBonus *
            GameBalance.enhancedClearBonusMultiplier)
        .round();
  }

  static TowerStats effectiveTowerStats({
    required TowerStats resolvedStats,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (resolvedStats.type != TowerType.gravityWell ||
        !stageModifiers.contains(StageModifier.amplifiedGravityWells)) {
      return resolvedStats;
    }
    return resolvedStats.copyWith(
      fieldRadius:
          resolvedStats.fieldRadius *
          GameBalance.amplifiedGravityWellRadiusMultiplier,
      fieldDuration:
          resolvedStats.fieldDuration *
          GameBalance.amplifiedGravityWellDurationMultiplier,
    );
  }
}
