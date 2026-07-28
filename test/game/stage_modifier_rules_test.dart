import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/stage_modifier_rules.dart';

double _delay(EnemyStats stats, int spawnedInGroup) {
  return StageModifierRules.nextSpawnDelay(
    stats: stats,
    spawnedInGroup: spawnedInGroup,
    baseSpawnInterval: 1,
    stageModifiers: const [StageModifier.regenPressurePulses],
  );
}

void main() {
  test('empty modifiers are identity operations', () {
    const stats = EnemyStats(
      health: 10,
      speed: 20,
      baseDamage: 1,
      goldReward: 5,
      traits: {EnemyTrait.armored, EnemyTrait.shielded},
      shieldHealth: 100,
      armorReduction: 0.3,
    );

    expect(
      StageModifierRules.effectiveStartingBaseHealth(
        campaignAdjustedBaseHealth: 20,
        stageModifiers: const [],
      ),
      20,
    );
    expect(
      StageModifierRules.effectiveKillReward(
        stats: stats,
        stageModifiers: const [],
      ),
      5,
    );
    final profile = StageModifierRules.enemyProfile(
      stats: stats,
      stageModifiers: const [],
    );
    expect(profile.speedMultiplier, 1);
    expect(profile.armorReductionBonus, 0);
    expect(profile.shieldRecharge, isNull);
  });

  test('swarm bounty rounds 5 gold to 8 and filters by trait', () {
    const swarm = EnemyStats(
      health: 1,
      speed: 1,
      baseDamage: 1,
      goldReward: 5,
      traits: {EnemyTrait.swarm},
    );
    const normal = EnemyStats(
      health: 1,
      speed: 1,
      baseDamage: 1,
      goldReward: 5,
    );
    const modifier = [StageModifier.swarmBounty];

    expect(
      StageModifierRules.effectiveKillReward(
        stats: swarm,
        stageModifiers: modifier,
      ),
      8,
    );
    expect(
      StageModifierRules.effectiveKillReward(
        stats: normal,
        stageModifiers: modifier,
      ),
      5,
    );
  });

  test('Salvage Rift current kill economy increases by 253 gold', () {
    final stage = OrionCampaign.stageById('salvage-rift');
    var delta = 0;
    for (final wave in stage.waves) {
      for (final group in wave.groups) {
        final adjusted = StageModifierRules.effectiveKillReward(
          stats: group.enemyStats,
          stageModifiers: stage.modifiers,
        );
        delta += (adjusted - group.enemyStats.goldReward) * group.enemyCount;
      }
    }
    expect(delta, 253);
  });

  test('enemy profile composes speed armor and shield policy', () {
    const stats = EnemyStats(
      health: 10,
      speed: 10,
      baseDamage: 1,
      goldReward: 1,
      traits: {EnemyTrait.armored, EnemyTrait.shielded},
      shieldHealth: 200,
      armorReduction: 0.7,
    );
    final profile = StageModifierRules.enemyProfile(
      stats: stats,
      stageModifiers: const [
        StageModifier.shieldRecharge,
        StageModifier.reinforcedArmor,
        StageModifier.enemySpeedSurge,
      ],
    );

    expect(profile.speedMultiplier, 1.15);
    expect(profile.armorReductionBonus, 0.10);
    expect(profile.shieldRecharge?.delay, 3);
    expect(profile.shieldRecharge?.ratePerSecond, 0.10);
  });

  test('regen pulses use intra-burst interval and inter-burst gap', () {
    const regen = EnemyStats(
      health: 1,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
      traits: {EnemyTrait.regen},
    );

    expect(_delay(regen, 1), 0.2);
    expect(_delay(regen, 2), 0.2);
    expect(_delay(regen, 3), 2.0);
    expect(_delay(regen, 4), 0.2);
  });

  test('pressure pulses produce the accepted six- and eight-enemy times', () {
    const regen = EnemyStats(
      health: 1,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
      traits: {EnemyTrait.regen},
    );

    List<double> timesFor(int count) {
      final times = <double>[0];
      for (var spawned = 1; spawned < count; spawned += 1) {
        times.add(times.last + _delay(regen, spawned));
      }
      return times;
    }

    for (final (actual, expected) in [
      (timesFor(6), [0, 0.2, 0.4, 2.4, 2.6, 2.8]),
      (timesFor(8), [0, 0.2, 0.4, 2.4, 2.6, 2.8, 4.8, 5.0]),
    ]) {
      expect(actual, hasLength(expected.length));
      for (var index = 0; index < expected.length; index += 1) {
        expect(actual[index], closeTo(expected[index], 0.0001));
      }
    }
  });

  test('pressure pulses leave non-regen intervals unchanged', () {
    const normal = EnemyStats(
      health: 1,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
    );
    expect(_delay(normal, 3), 1);
  });

  test('starting health and clear bonuses clamp and preserve zero', () {
    expect(
      StageModifierRules.effectiveStartingBaseHealth(
        campaignAdjustedBaseHealth: 4,
        stageModifiers: const [StageModifier.reducedStartingHealth],
      ),
      1,
    );
    expect(
      StageModifierRules.effectiveClearBonus(
        campaignAdjustedClearBonus: 38,
        stageModifiers: const [StageModifier.enhancedClearBonus],
      ),
      57,
    );
    expect(
      StageModifierRules.effectiveClearBonus(
        campaignAdjustedClearBonus: 0,
        stageModifiers: const [StageModifier.enhancedClearBonus],
      ),
      0,
    );
  });

  test('modifier order does not change the resolved profile', () {
    const stats = EnemyStats(
      health: 10,
      speed: 10,
      baseDamage: 1,
      goldReward: 1,
      traits: {EnemyTrait.armored, EnemyTrait.shielded},
      shieldHealth: 100,
      armorReduction: 0.2,
    );
    final forward = StageModifierRules.enemyProfile(
      stats: stats,
      stageModifiers: const [
        StageModifier.shieldRecharge,
        StageModifier.reinforcedArmor,
        StageModifier.enemySpeedSurge,
      ],
    );
    final reverse = StageModifierRules.enemyProfile(
      stats: stats,
      stageModifiers: const [
        StageModifier.enemySpeedSurge,
        StageModifier.reinforcedArmor,
        StageModifier.shieldRecharge,
      ],
    );

    expect(reverse.speedMultiplier, forward.speedMultiplier);
    expect(reverse.armorReductionBonus, forward.armorReductionBonus);
    expect(reverse.shieldRecharge?.delay, forward.shieldRecharge?.delay);
    expect(
      reverse.shieldRecharge?.ratePerSecond,
      forward.shieldRecharge?.ratePerSecond,
    );
  });

  test('amplified wells affect every level and specialization only', () {
    final towers = <PlacedTower>[
      const PlacedTower(
        id: 1,
        type: TowerType.gravityWell,
        position: GridPosition(0, 0),
      ),
      const PlacedTower(
        id: 2,
        type: TowerType.gravityWell,
        position: GridPosition(0, 0),
        level: 2,
      ),
      const PlacedTower(
        id: 3,
        type: TowerType.gravityWell,
        position: GridPosition(0, 0),
        level: 3,
        specialization: TowerSpecialization.singularityWell,
      ),
      const PlacedTower(
        id: 4,
        type: TowerType.gravityWell,
        position: GridPosition(0, 0),
        level: 3,
        specialization: TowerSpecialization.crushWell,
      ),
    ];

    for (final tower in towers) {
      final base = GameBalance.towerStats(
        tower.type,
        level: tower.level,
        specialization: tower.specialization,
      );
      final adjusted = StageModifierRules.effectiveTowerStats(
        resolvedStats: base,
        stageModifiers: const [StageModifier.amplifiedGravityWells],
      );
      expect(adjusted.fieldRadius, closeTo(base.fieldRadius * 1.20, 0.001));
      expect(adjusted.fieldDuration, closeTo(base.fieldDuration * 1.25, 0.001));
    }

    final laser = GameBalance.towerStats(TowerType.laser, level: 1);
    expect(
      StageModifierRules.effectiveTowerStats(
        resolvedStats: laser,
        stageModifiers: const [StageModifier.amplifiedGravityWells],
      ),
      same(laser),
    );
  });
}
