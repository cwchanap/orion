# Orion Tower Variety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand Orion into an eight-wave tower-defense run with eight tower types, wave-based tower unlocks, hybrid upgrades, lightweight enemy counters, and focused test coverage.

**Architecture:** Preserve the current split between pure Dart rules and Flame presentation. Add model and session capabilities first, then pure combat-effect helpers, then component/runtime integration, then assets and UI. Keep board geometry, path cells, terrain rendering, path-tile rendering, and the existing win/loss loop stable.

**Tech Stack:** Flutter, Dart, Flame, flutter_test, flutter_lints.

---

## Scope Check

This spec is large, but it remains one feature because every subsystem supports a single player-facing goal: tower variety. The plan keeps the work sequential and independently testable by layering models, state rules, combat math, runtime behavior, assets, and UI.

## File Structure

- Modify: `lib/game/models/game_models.dart`
  - Add tower roster, specialization data, enemy traits, wave groups, expanded stats, unlock metadata, and compatibility getters used while runtime migration is in progress.
- Modify: `lib/game/rules/game_session.dart`
  - Enforce tower unlocks, clear bonuses, upgrade rules, specialization rules, and reset behavior.
- Create: `lib/game/rules/combat_effects.dart`
  - Pure helper for shield, armor, corrosion, slow stacking, chain selection, pierce selection, and drone cap math.
- Modify: `lib/game/rules/tower_targeting.dart`
  - Keep closest-to-base targeting and add explicit chain/pierce candidate helpers only where pure helpers need geometry data.
- Modify: `lib/game/components/enemy_component.dart`
  - Add shield, max health, regen, corrosion, armor, and status ticking while preserving path movement.
- Modify: `lib/game/components/projectile_component.dart`
  - Delegate hit math to `combat_effects.dart` and route tower behaviors.
- Modify: `lib/game/components/tower_component.dart`
  - Render all tower types through sprite or color fallback and launch behavior-specific projectiles.
- Create: `lib/game/components/gravity_field_component.dart`
  - Temporary area effect for Gravity Well.
- Create: `lib/game/components/drone_component.dart`
  - Capped autonomous Drone Bay attack unit.
- Modify: `lib/game/orion_defense_game.dart`
  - Spawn wave groups, unlock towers after cleared waves, launch new effects/components, clear active combat components, and publish expanded snapshots.
- Create: `lib/game/assets/game_tower_variety_sheet.dart`
  - Fixed 4 by 4 atlas metadata for the new tower variety sheet.
- Modify: `lib/game/assets/game_sprite_sheet.dart`
  - Keep existing indices stable and return old sprites only for old objects.
- Modify: `lib/game/ui/orion_game_page.dart`
  - Progressive tower reveal, compact eight-tower picker, specialization buttons, and updated HUD values.
- Modify: `pubspec.yaml`
  - Register `assets/images/orion_tower_variety_sheet.png`.
- Add: `assets/images/orion_tower_variety_sheet.png`
  - 4 by 4 raster atlas matching the approved design.
- Modify: `test/game/game_balance_test.dart`
  - Expanded roster, costs, waves, enemy archetypes, and atlas-independent balance checks.
- Modify: `test/game/game_session_test.dart`
  - Unlock, locked placement, clear bonus, upgrade, specialization, and restart coverage.
- Create: `test/game/combat_effects_test.dart`
  - Pure combat math coverage.
- Modify: `test/game/enemy_component_test.dart`
  - Runtime status, shield, regen, corrosion, and path-stability coverage.
- Modify: `test/game/tower_targeting_test.dart`
  - Chain/pierce helper coverage if those helpers live in `tower_targeting.dart`.
- Modify: `test/game/game_sprite_sheet_test.dart`
  - Keep old sprite sheet stable and add tests for the new tower variety atlas metadata.
- Modify: `test/widget_test.dart`
  - Updated HUD and initial tower picker expectations.

## Task 1: Expand Models, Balance, And Wave Data

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Modify: `test/game/game_balance_test.dart`

- [ ] **Step 1: Replace the balance tests with expanded expectations**

Replace `test/game/game_balance_test.dart` with this file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameBalance', () {
    test('matches the expanded starting economy and base health', () {
      expect(GameBalance.startingGold, 150);
      expect(GameBalance.initialBaseHealth, 20);
    });

    test('defines the expanded tower roster in stable order', () {
      expect(TowerType.values, const [
        TowerType.laser,
        TowerType.rocket,
        TowerType.cryo,
        TowerType.railgun,
        TowerType.ionChain,
        TowerType.nanite,
        TowerType.gravityWell,
        TowerType.droneBay,
      ]);
    });

    test('defines wave-based tower unlocks', () {
      expect(GameBalance.towerUnlockWave(TowerType.laser), 1);
      expect(GameBalance.towerUnlockWave(TowerType.rocket), 1);
      expect(GameBalance.towerUnlockWave(TowerType.cryo), 1);
      expect(GameBalance.towerUnlockWave(TowerType.railgun), 2);
      expect(GameBalance.towerUnlockWave(TowerType.ionChain), 3);
      expect(GameBalance.towerUnlockWave(TowerType.nanite), 4);
      expect(GameBalance.towerUnlockWave(TowerType.gravityWell), 5);
      expect(GameBalance.towerUnlockWave(TowerType.droneBay), 6);
    });

    test('defines two specializations for every tower', () {
      for (final type in TowerType.values) {
        final options = GameBalance.specializationsFor(type);
        expect(options, hasLength(2));
        for (final specialization in options) {
          expect(specialization.type, type);
          expect(specialization.label, isNotEmpty);
        }
      }
    });

    test('defines starter costs for each tower tier', () {
      const expectedCosts = {
        TowerType.laser: (cost: 50, upgrade: 70, specialization: 120),
        TowerType.rocket: (cost: 80, upgrade: 100, specialization: 150),
        TowerType.cryo: (cost: 70, upgrade: 90, specialization: 140),
        TowerType.railgun: (cost: 110, upgrade: 150, specialization: 210),
        TowerType.ionChain: (cost: 95, upgrade: 130, specialization: 190),
        TowerType.nanite: (cost: 90, upgrade: 125, specialization: 180),
        TowerType.gravityWell: (cost: 120, upgrade: 160, specialization: 220),
        TowerType.droneBay: (cost: 130, upgrade: 170, specialization: 240),
      };

      for (final entry in expectedCosts.entries) {
        final base = GameBalance.towerStats(entry.key, level: 1);
        final upgraded = GameBalance.towerStats(entry.key, level: 2);
        final specialized = GameBalance.towerStats(
          entry.key,
          level: 3,
          specialization: GameBalance.specializationsFor(entry.key).first,
        );

        expect(base.cost, entry.value.cost);
        expect(base.upgradeCost, entry.value.upgrade);
        expect(base.specializationCost, entry.value.specialization);
        expect(upgraded.cost, entry.value.cost);
        expect(upgraded.upgradeCost, entry.value.upgrade);
        expect(upgraded.specializationCost, entry.value.specialization);
        expect(specialized.specializationCost, entry.value.specialization);
        expect(base.canUpgrade, isTrue);
        expect(upgraded.canSpecialize, isTrue);
        expect(specialized.isMaxLevel, isTrue);
      }
    });

    test('defines enemy archetype traits and defenses', () {
      final armored = GameBalance.enemyArchetype(EnemyArchetype.armoredDrone);
      expect(armored.traits, contains(EnemyTrait.armored));
      expect(armored.armorReduction, 0.30);
      expect(armored.shieldHealth, 0);

      final shielded = GameBalance.enemyArchetype(EnemyArchetype.shieldedDrone);
      expect(shielded.traits, contains(EnemyTrait.shielded));
      expect(shielded.shieldHealth, 35);
      expect(shielded.armorReduction, 0);

      final regenHeavy =
          GameBalance.enemyArchetype(EnemyArchetype.regenHeavyDrone);
      expect(regenHeavy.traits, containsAll([
        EnemyTrait.regen,
        EnemyTrait.heavy,
      ]));
      expect(regenHeavy.regenPerSecond, 3.0);
      expect(regenHeavy.baseDamage, 3);
    });

    test('defines eight wave groups and clear bonuses', () {
      expect(GameBalance.waves, hasLength(8));

      final expected = [
        (enemyCount: 8, clearBonus: 30),
        (enemyCount: 10, clearBonus: 40),
        (enemyCount: 14, clearBonus: 50),
        (enemyCount: 16, clearBonus: 65),
        (enemyCount: 24, clearBonus: 80),
        (enemyCount: 22, clearBonus: 95),
        (enemyCount: 28, clearBonus: 115),
        (enemyCount: 46, clearBonus: 0),
      ];

      for (final (index, expectation) in expected.indexed) {
        final wave = GameBalance.waves[index];
        expect(wave.enemyCount, expectation.enemyCount);
        expect(wave.clearBonus, expectation.clearBonus);
        expect(wave.groups, isNotEmpty);
      }

      expect(
        GameBalance.waves[7].groups.map((group) => group.enemyStats.traits),
        contains(contains(EnemyTrait.swarm)),
      );
    });

    test('rejects invalid tower stat requests', () {
      expect(
        () => GameBalance.towerStats(TowerType.laser, level: 0),
        throwsArgumentError,
      );
      expect(
        () => GameBalance.towerStats(TowerType.laser, level: 3),
        throwsArgumentError,
      );
      expect(
        () => GameBalance.towerStats(
          TowerType.laser,
          level: 3,
          specialization:
              GameBalance.specializationsFor(TowerType.rocket).first,
        ),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run the balance test and verify it fails**

Run:

```bash
flutter test test/game/game_balance_test.dart
```

Expected: fails because the expanded tower, specialization, enemy trait, and wave APIs do not exist yet.

- [ ] **Step 3: Update the model types**

In `lib/game/models/game_models.dart`, update the existing enums and value objects to match this public API. Keep `GridPosition`, `PlacementResult`, and `GamePhase` behavior intact.

```dart
enum TowerType {
  laser,
  rocket,
  cryo,
  railgun,
  ionChain,
  nanite,
  gravityWell,
  droneBay,
}

enum TowerSpecialization {
  pulseLaser(TowerType.laser, 'Pulse Laser'),
  prismLaser(TowerType.laser, 'Prism Laser'),
  siegeRocket(TowerType.rocket, 'Siege Rocket'),
  clusterRocket(TowerType.rocket, 'Cluster Rocket'),
  deepFreeze(TowerType.cryo, 'Deep Freeze'),
  frostbite(TowerType.cryo, 'Frostbite'),
  lanceRailgun(TowerType.railgun, 'Lance Railgun'),
  magneticRailgun(TowerType.railgun, 'Magnetic Railgun'),
  stormRelay(TowerType.ionChain, 'Storm Relay'),
  overloadRelay(TowerType.ionChain, 'Overload Relay'),
  dissolverNanites(TowerType.nanite, 'Dissolver Nanites'),
  replicatorNanites(TowerType.nanite, 'Replicator Nanites'),
  singularityWell(TowerType.gravityWell, 'Singularity Well'),
  crushWell(TowerType.gravityWell, 'Crush Well'),
  interceptorBay(TowerType.droneBay, 'Interceptor Bay'),
  hunterBay(TowerType.droneBay, 'Hunter Bay');

  const TowerSpecialization(this.type, this.label);

  final TowerType type;
  final String label;
}

enum EnemyTrait { armored, shielded, swarm, regen, heavy }

enum EnemyArchetype {
  basicDrone,
  basicEliteDrone,
  armoredDrone,
  shieldedDrone,
  swarmDrone,
  regenDrone,
  heavyDrone,
  armoredHeavyDrone,
  regenHeavyDrone,
}
```

Replace `PlacementFailure` with a version that includes locked tower placement:

```dart
enum PlacementFailure {
  invalidPhase,
  offBoard,
  pathBlocked,
  occupied,
  lockedTower,
  insufficientGold,
}
```

Update `TowerStats` to keep old fields and add behavior fields with defaults:

```dart
class TowerStats {
  const TowerStats({
    required this.type,
    required this.level,
    required this.cost,
    required this.upgradeCost,
    required this.specializationCost,
    required this.range,
    required this.damage,
    required this.fireInterval,
    required this.projectileSpeed,
    this.specialization,
    this.splashRadius = 0,
    this.slowMultiplier = 1,
    this.slowDuration = 0,
    this.pierceCount = 0,
    this.pierceWidth = 0,
    this.chainCount = 0,
    this.chainRange = 0,
    this.chainFalloff = 1,
    this.corrosionDamagePerSecond = 0,
    this.corrosionDuration = 0,
    this.armorShred = 0,
    this.fieldRadius = 0,
    this.fieldDuration = 0,
    this.fieldTickInterval = 0,
    this.droneCount = 0,
    this.droneLifetime = 0,
    this.droneDamage = 0,
    this.droneAttackInterval = 0,
    this.maxActiveDrones = 0,
    this.shieldDamageMultiplier = 1,
    this.armorDamageMultiplier = 1,
    this.slowedDamageMultiplier = 1,
    this.prismSplitDamageMultiplier = 0,
    this.prismSplitRange = 0,
    this.clusterBurstCount = 0,
    this.clusterBurstDamageMultiplier = 0,
    this.clusterBurstRadius = 0,
  });

  final TowerType type;
  final int level;
  final int cost;
  final int upgradeCost;
  final int specializationCost;
  final double range;
  final double damage;
  final double fireInterval;
  final double projectileSpeed;
  final TowerSpecialization? specialization;
  final double splashRadius;
  final double slowMultiplier;
  final double slowDuration;
  final int pierceCount;
  final double pierceWidth;
  final int chainCount;
  final double chainRange;
  final double chainFalloff;
  final double corrosionDamagePerSecond;
  final double corrosionDuration;
  final double armorShred;
  final double fieldRadius;
  final double fieldDuration;
  final double fieldTickInterval;
  final int droneCount;
  final double droneLifetime;
  final double droneDamage;
  final double droneAttackInterval;
  final int maxActiveDrones;
  final double shieldDamageMultiplier;
  final double armorDamageMultiplier;
  final double slowedDamageMultiplier;
  final double prismSplitDamageMultiplier;
  final double prismSplitRange;
  final int clusterBurstCount;
  final double clusterBurstDamageMultiplier;
  final double clusterBurstRadius;

  bool get canUpgrade => level == 1;
  bool get canSpecialize => level == 2;
  bool get isMaxLevel => level >= 3;
}
```

Update `EnemyStats`, add `WaveGroup`, and keep compatibility getters on `WaveDefinition` until the runtime migrates to groups:

```dart
class EnemyStats {
  const EnemyStats({
    required this.health,
    required this.speed,
    required this.baseDamage,
    required this.goldReward,
    this.traits = const <EnemyTrait>{},
    this.shieldHealth = 0,
    this.armorReduction = 0,
    this.regenPerSecond = 0,
  });

  final double health;
  final double speed;
  final int baseDamage;
  final int goldReward;
  final Set<EnemyTrait> traits;
  final double shieldHealth;
  final double armorReduction;
  final double regenPerSecond;

  bool hasTrait(EnemyTrait trait) => traits.contains(trait);
}

class WaveGroup {
  const WaveGroup({
    required this.enemyCount,
    required this.enemyStats,
    this.spawnInterval = 0.85,
    this.initialDelay = 0,
  });

  final int enemyCount;
  final EnemyStats enemyStats;
  final double spawnInterval;
  final double initialDelay;
}

class WaveDefinition {
  const WaveDefinition({
    required this.groups,
    required this.clearBonus,
  });

  final List<WaveGroup> groups;
  final int clearBonus;

  int get enemyCount =>
      groups.fold(0, (total, group) => total + group.enemyCount);
  EnemyStats get enemyStats => groups.first.enemyStats;
  double get spawnInterval => groups.first.spawnInterval;
}
```

Update `PlacedTower` to preserve existing upgrade behavior and add specialization:

```dart
class PlacedTower {
  const PlacedTower({
    required this.id,
    required this.type,
    required this.position,
    this.level = 1,
    this.specialization,
  });

  final int id;
  final TowerType type;
  final GridPosition position;
  final int level;
  final TowerSpecialization? specialization;

  bool get canUpgrade => level == 1;
  bool get canSpecialize => level == 2 && specialization == null;
  bool get isMaxLevel => level >= 3;

  PlacedTower upgraded() {
    if (!canUpgrade) {
      throw StateError('Tower cannot be upgraded');
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: 2,
    );
  }

  PlacedTower specialized(TowerSpecialization chosenSpecialization) {
    if (!canSpecialize) {
      throw StateError('Tower cannot be specialized');
    }
    if (chosenSpecialization.type != type) {
      throw ArgumentError.value(
        chosenSpecialization,
        'chosenSpecialization',
        'Specialization does not match tower type',
      );
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: 3,
      specialization: chosenSpecialization,
    );
  }
}
```

- [ ] **Step 4: Add expanded balance data**

In `GameBalance`, set `startingGold` to `150`, add the unlock/specialization helpers, add `enemyArchetype`, and replace the wave list. Use the exact wave groups from the spec:

```dart
static const int startingGold = 150;
static const int initialBaseHealth = 20;

static int towerUnlockWave(TowerType type) {
  return switch (type) {
    TowerType.laser || TowerType.rocket || TowerType.cryo => 1,
    TowerType.railgun => 2,
    TowerType.ionChain => 3,
    TowerType.nanite => 4,
    TowerType.gravityWell => 5,
    TowerType.droneBay => 6,
  };
}

static List<TowerSpecialization> specializationsFor(TowerType type) {
  return TowerSpecialization.values
      .where((specialization) => specialization.type == type)
      .toList(growable: false);
}
```

Use this `enemyArchetype` switch:

```dart
static EnemyStats enemyArchetype(EnemyArchetype archetype) {
  return switch (archetype) {
    EnemyArchetype.basicDrone => const EnemyStats(
      health: 36,
      speed: 74,
      baseDamage: 1,
      goldReward: 8,
    ),
    EnemyArchetype.basicEliteDrone => const EnemyStats(
      health: 90,
      speed: 86,
      baseDamage: 1,
      goldReward: 13,
    ),
    EnemyArchetype.armoredDrone => const EnemyStats(
      health: 70,
      speed: 66,
      baseDamage: 1,
      goldReward: 12,
      traits: {EnemyTrait.armored},
      armorReduction: 0.30,
    ),
    EnemyArchetype.shieldedDrone => const EnemyStats(
      health: 48,
      speed: 78,
      baseDamage: 1,
      goldReward: 12,
      traits: {EnemyTrait.shielded},
      shieldHealth: 35,
    ),
    EnemyArchetype.swarmDrone => const EnemyStats(
      health: 22,
      speed: 100,
      baseDamage: 1,
      goldReward: 5,
      traits: {EnemyTrait.swarm},
    ),
    EnemyArchetype.regenDrone => const EnemyStats(
      health: 78,
      speed: 72,
      baseDamage: 1,
      goldReward: 14,
      traits: {EnemyTrait.regen},
      regenPerSecond: 2.5,
    ),
    EnemyArchetype.heavyDrone => const EnemyStats(
      health: 150,
      speed: 58,
      baseDamage: 2,
      goldReward: 18,
      traits: {EnemyTrait.heavy},
    ),
    EnemyArchetype.armoredHeavyDrone => const EnemyStats(
      health: 175,
      speed: 54,
      baseDamage: 2,
      goldReward: 22,
      traits: {EnemyTrait.armored, EnemyTrait.heavy},
      armorReduction: 0.35,
    ),
    EnemyArchetype.regenHeavyDrone => const EnemyStats(
      health: 190,
      speed: 54,
      baseDamage: 3,
      goldReward: 25,
      traits: {EnemyTrait.regen, EnemyTrait.heavy},
      regenPerSecond: 3.0,
    ),
  };
}
```

Define `waves` as:

```dart
static List<WaveGroup> _groups(List<(EnemyArchetype, int)> groups) {
  return [
    for (final (archetype, count) in groups)
      WaveGroup(
        enemyCount: count,
        enemyStats: enemyArchetype(archetype),
        spawnInterval: switch (archetype) {
          EnemyArchetype.basicDrone => 0.85,
          EnemyArchetype.basicEliteDrone => 0.75,
          EnemyArchetype.armoredDrone => 1.00,
          EnemyArchetype.shieldedDrone => 0.90,
          EnemyArchetype.swarmDrone => 0.35,
          EnemyArchetype.regenDrone => 1.00,
          EnemyArchetype.heavyDrone => 1.20,
          EnemyArchetype.armoredHeavyDrone => 1.25,
          EnemyArchetype.regenHeavyDrone => 1.30,
        },
      ),
  ];
}

static final List<WaveDefinition> waves = [
  WaveDefinition(
    groups: _groups([(EnemyArchetype.basicDrone, 8)]),
    clearBonus: 30,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.basicDrone, 8),
      (EnemyArchetype.armoredDrone, 2),
    ]),
    clearBonus: 40,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.basicDrone, 10),
      (EnemyArchetype.shieldedDrone, 4),
    ]),
    clearBonus: 50,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.basicDrone, 8),
      (EnemyArchetype.armoredDrone, 4),
      (EnemyArchetype.shieldedDrone, 4),
    ]),
    clearBonus: 65,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.swarmDrone, 20),
      (EnemyArchetype.heavyDrone, 4),
    ]),
    clearBonus: 80,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.shieldedDrone, 10),
      (EnemyArchetype.regenDrone, 6),
      (EnemyArchetype.swarmDrone, 6),
    ]),
    clearBonus: 95,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.armoredHeavyDrone, 8),
      (EnemyArchetype.shieldedDrone, 8),
      (EnemyArchetype.swarmDrone, 12),
    ]),
    clearBonus: 115,
  ),
  WaveDefinition(
    groups: _groups([
      (EnemyArchetype.basicEliteDrone, 8),
      (EnemyArchetype.shieldedDrone, 8),
      (EnemyArchetype.armoredDrone, 8),
      (EnemyArchetype.swarmDrone, 18),
      (EnemyArchetype.regenHeavyDrone, 4),
    ]),
    clearBonus: 0,
  ),
];
```

Update `towerStats` to accept specializations:

```dart
static TowerStats towerStats(
  TowerType type, {
  required int level,
  TowerSpecialization? specialization,
}) {
  if (level < 1 || level > 3) {
    throw ArgumentError.value(level, 'level', 'Tower level must be 1, 2, or 3');
  }
  if (level == 3) {
    if (specialization == null || specialization.type != type) {
      throw ArgumentError.value(
        specialization,
        'specialization',
        'Level 3 stats require a matching specialization',
      );
    }
  }
  if (level < 3 && specialization != null) {
    throw ArgumentError.value(
      specialization,
      'specialization',
      'Only level 3 stats can use a specialization',
    );
  }

  return _towerStatsByKey[(type, level, specialization)]!;
}
```

Populate `_towerStatsByKey` with these minimum values. Keep the constructor fields not shown at their defaults.

| Key | Range | Damage | Interval | Projectile | Splash | Slow | Special Fields |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Laser L1 | 145 | 12 | 0.42 | 420 | 0 | none | none |
| Laser L2 | 160 | 18 | 0.34 | 460 | 0 | none | none |
| Pulse Laser | 165 | 18 | 0.24 | 480 | 0 | none | none |
| Prism Laser | 170 | 20 | 0.34 | 470 | 0 | none | `prismSplitDamageMultiplier: 0.35`, `prismSplitRange: 55` |
| Rocket L1 | 165 | 26 | 1.15 | 300 | 58 | none | none |
| Rocket L2 | 180 | 40 | 1.00 | 330 | 72 | none | none |
| Siege Rocket | 190 | 54 | 1.05 | 330 | 96 | none | none |
| Cluster Rocket | 180 | 42 | 1.00 | 340 | 72 | none | `clusterBurstCount: 2`, `clusterBurstDamageMultiplier: 0.45`, `clusterBurstRadius: 42` |
| Cryo L1 | 135 | 5 | 0.85 | 360 | 0 | `0.62 for 1.4s` | none |
| Cryo L2 | 150 | 8 | 0.72 | 390 | 0 | `0.48 for 2.0s` | none |
| Deep Freeze | 160 | 8 | 0.70 | 400 | 0 | `0.38 for 2.8s` | none |
| Frostbite | 155 | 14 | 0.68 | 410 | 0 | `0.50 for 1.8s` | `slowedDamageMultiplier: 1.6` |
| Railgun L1 | 210 | 42 | 1.45 | 620 | 0 | none | `pierceCount: 2`, `pierceWidth: 22` |
| Railgun L2 | 230 | 62 | 1.30 | 680 | 0 | none | `pierceCount: 3`, `pierceWidth: 24` |
| Lance Railgun | 255 | 70 | 1.25 | 720 | 0 | none | `pierceCount: 5`, `pierceWidth: 28` |
| Magnetic Railgun | 235 | 68 | 1.28 | 700 | 0 | none | `pierceCount: 3`, `pierceWidth: 24`, `armorDamageMultiplier: 1.55` |
| Ion Chain L1 | 150 | 16 | 0.95 | 500 | 0 | none | `chainCount: 3`, `chainRange: 85`, `chainFalloff: 0.72` |
| Ion Chain L2 | 165 | 22 | 0.82 | 540 | 0 | none | `chainCount: 4`, `chainRange: 95`, `chainFalloff: 0.76` |
| Storm Relay | 175 | 24 | 0.78 | 560 | 0 | none | `chainCount: 6`, `chainRange: 110`, `chainFalloff: 0.78` |
| Overload Relay | 168 | 24 | 0.82 | 550 | 0 | none | `chainCount: 4`, `chainRange: 100`, `chainFalloff: 0.76`, `shieldDamageMultiplier: 1.65` |
| Nanite L1 | 140 | 6 | 0.90 | 360 | 0 | none | `corrosionDamagePerSecond: 6`, `corrosionDuration: 2.5`, `armorShred: 0.12` |
| Nanite L2 | 155 | 8 | 0.80 | 390 | 0 | none | `corrosionDamagePerSecond: 9`, `corrosionDuration: 3.2`, `armorShred: 0.18` |
| Dissolver Nanites | 165 | 9 | 0.78 | 400 | 0 | none | `corrosionDamagePerSecond: 11`, `corrosionDuration: 3.6`, `armorShred: 0.32` |
| Replicator Nanites | 160 | 8 | 0.76 | 410 | 0 | none | `corrosionDamagePerSecond: 10`, `corrosionDuration: 3.2`, `armorShred: 0.20` |
| Gravity Well L1 | 155 | 4 | 1.25 | 300 | 0 | none | `fieldRadius: 72`, `fieldDuration: 2.0`, `fieldTickInterval: 0.5` |
| Gravity Well L2 | 170 | 6 | 1.12 | 320 | 0 | none | `fieldRadius: 86`, `fieldDuration: 2.5`, `fieldTickInterval: 0.5` |
| Singularity Well | 185 | 6 | 1.05 | 330 | 0 | none | `fieldRadius: 104`, `fieldDuration: 3.1`, `fieldTickInterval: 0.45`, `slowMultiplier: 0.42`, `slowDuration: 0.7` |
| Crush Well | 175 | 14 | 1.10 | 330 | 0 | none | `fieldRadius: 88`, `fieldDuration: 2.8`, `fieldTickInterval: 0.45`, `slowMultiplier: 0.55`, `slowDuration: 0.6` |
| Drone Bay L1 | 150 | 0 | 2.50 | 0 | 0 | none | `droneCount: 2`, `droneLifetime: 4.0`, `droneDamage: 8`, `droneAttackInterval: 0.65`, `maxActiveDrones: 4` |
| Drone Bay L2 | 165 | 0 | 2.25 | 0 | 0 | none | `droneCount: 3`, `droneLifetime: 4.5`, `droneDamage: 10`, `droneAttackInterval: 0.58`, `maxActiveDrones: 6` |
| Interceptor Bay | 175 | 0 | 2.05 | 0 | 0 | none | `droneCount: 4`, `droneLifetime: 4.0`, `droneDamage: 9`, `droneAttackInterval: 0.50`, `maxActiveDrones: 8` |
| Hunter Bay | 175 | 0 | 2.30 | 0 | 0 | none | `droneCount: 2`, `droneLifetime: 5.4`, `droneDamage: 18`, `droneAttackInterval: 0.72`, `maxActiveDrones: 4` |

- [ ] **Step 5: Run the balance test and full current test suite**

Run:

```bash
flutter test test/game/game_balance_test.dart
flutter test
```

Expected: both pass. Existing runtime still compiles because `WaveDefinition.enemyCount`, `WaveDefinition.enemyStats`, and `WaveDefinition.spawnInterval` compatibility getters remain.

- [ ] **Step 6: Commit model and balance changes**

```bash
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: expand Orion tower and wave balance"
```

## Task 2: Add Session Unlocks, Clear Bonuses, And Specialization Rules

**Files:**
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/components/tower_component.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/game/game_session_test.dart`

- [ ] **Step 1: Add failing session tests**

Append these tests inside the `GameSession` group in `test/game/game_session_test.dart`:

```dart
test('starts with only the baseline towers unlocked', () {
  final session = GameSession.initial();

  expect(session.unlockedTowerTypes, [
    TowerType.laser,
    TowerType.rocket,
    TowerType.cryo,
  ]);
  expect(session.isTowerUnlocked(TowerType.railgun), isFalse);
  expect(session.isTowerUnlocked(TowerType.droneBay), isFalse);
});

test('denies locked tower placement without spending gold', () {
  final session = GameSession.initial(gold: 500);

  final result = session.placeTower(
    const GridPosition(0, 0),
    TowerType.droneBay,
  );

  expect(result.isAllowed, isFalse);
  expect(result.failure, PlacementFailure.lockedTower);
  expect(session.gold, 500);
  expect(session.towers, isEmpty);
});

test('unlocks towers after cleared waves and applies clear bonuses', () {
  final session = GameSession.initial();

  expect(session.startWave(), isTrue);
  session.finishActiveWave();

  expect(session.phase, GamePhase.build);
  expect(session.gold, 180);
  expect(session.isTowerUnlocked(TowerType.railgun), isTrue);
  expect(session.isTowerUnlocked(TowerType.ionChain), isFalse);
});

test('specializes a level two tower once and spends gold', () {
  final session = GameSession.initial(gold: 500);
  final position = const GridPosition(0, 0);
  session.placeTower(position, TowerType.laser);
  final tower = session.towers.single;
  expect(session.upgradeTower(tower.id), isTrue);

  final specialized = session.specializeTower(
    tower.id,
    TowerSpecialization.prismLaser,
  );

  expect(specialized, isTrue);
  final result = session.towers.single;
  expect(result.level, 3);
  expect(result.specialization, TowerSpecialization.prismLaser);
  expect(session.gold, 260);
  expect(session.specializeTower(tower.id, TowerSpecialization.pulseLaser),
      isFalse);
});

test('rejects specialization in invalid states without spending gold', () {
  final session = GameSession.initial(gold: 500);
  session.placeTower(const GridPosition(0, 0), TowerType.laser);
  final tower = session.towers.single;

  expect(
    session.specializeTower(tower.id, TowerSpecialization.prismLaser),
    isFalse,
  );
  expect(session.gold, 450);

  expect(session.upgradeTower(tower.id), isTrue);
  expect(
    session.specializeTower(tower.id, TowerSpecialization.siegeRocket),
    isFalse,
  );
  expect(session.gold, 380);

  expect(session.startWave(), isTrue);
  expect(
    session.specializeTower(tower.id, TowerSpecialization.prismLaser),
    isFalse,
  );
  expect(session.gold, 380);
});

test('restart resets unlock progress and specialized towers', () {
  final session = GameSession.initial(gold: 500);
  session.startWave();
  session.finishActiveWave();
  expect(session.isTowerUnlocked(TowerType.railgun), isTrue);
  session.placeTower(const GridPosition(0, 0), TowerType.railgun);

  session.restart();

  expect(session.waveIndex, 0);
  expect(session.gold, GameBalance.startingGold);
  expect(session.unlockedTowerTypes, [
    TowerType.laser,
    TowerType.rocket,
    TowerType.cryo,
  ]);
  expect(session.towers, isEmpty);
});
```

- [ ] **Step 2: Run the session test and verify it fails**

Run:

```bash
flutter test test/game/game_session_test.dart
```

Expected: fails because unlock and specialization APIs are not implemented.

- [ ] **Step 3: Implement unlock helpers and placement lockout**

In `GameSession`, add these getters:

```dart
int get clearedWaveCount => _waveIndex;

List<TowerType> get unlockedTowerTypes {
  final nextWaveNumber = _waveIndex + 1;
  return TowerType.values
      .where((type) => GameBalance.towerUnlockWave(type) <= nextWaveNumber)
      .toList(growable: false);
}

bool isTowerUnlocked(TowerType type) => unlockedTowerTypes.contains(type);
```

In `validatePlacement`, check locked towers after path/occupancy checks and before gold:

```dart
if (!isTowerUnlocked(type)) {
  return const PlacementResult.denied(PlacementFailure.lockedTower);
}
```

- [ ] **Step 4: Apply clear bonuses when waves finish**

Replace `finishActiveWave` with this implementation:

```dart
void finishActiveWave() {
  if (_phase != GamePhase.wave) {
    return;
  }

  final completedWave = activeWave;
  _waveIndex += 1;
  if (completedWave != null && _waveIndex < GameBalance.waves.length) {
    _gold += completedWave.clearBonus;
  }
  _phase = _waveIndex >= GameBalance.waves.length
      ? GamePhase.won
      : GamePhase.build;
}
```

- [ ] **Step 5: Add specialization support**

Add this method to `GameSession`:

```dart
bool specializeTower(int towerId, TowerSpecialization specialization) {
  if (_phase != GamePhase.build) {
    return false;
  }

  final entry = _findTowerEntry(towerId);
  if (entry == null) {
    return false;
  }

  final tower = entry.value;
  if (!tower.canSpecialize || specialization.type != tower.type) {
    return false;
  }

  final stats = GameBalance.towerStats(
    tower.type,
    level: 2,
  );
  if (_gold < stats.specializationCost) {
    return false;
  }

  _gold -= stats.specializationCost;
  _towersByPosition[entry.key] = tower.specialized(specialization);
  return true;
}
```

Update `upgradeTower` to use `tower.canUpgrade` instead of `tower.level >= 2`:

```dart
if (!tower.canUpgrade) {
  return false;
}
```

- [ ] **Step 6: Update runtime messages for locked placement**

In `OrionDefenseGame._placementMessage`, add the locked-tower case:

```dart
PlacementFailure.lockedTower => 'That tower unlocks after a later wave.',
```

In `_upgradeMessage`, use `tower.canUpgrade`:

```dart
if (!tower.canUpgrade) {
  return 'Choose a specialization or use a maxed tower.';
}
```

The specialization UI is added in Task 8; this message keeps current code compiling.

- [ ] **Step 7: Update tower stat lookups to pass specialization**

In `TowerComponent`, replace every direct call shaped like this:

```dart
GameBalance.towerStats(tower.type, level: tower.level)
```

with this form:

```dart
GameBalance.towerStats(
  tower.type,
  level: tower.level,
  specialization: tower.specialization,
)
```

Apply the same change in the constructor initializer and `updateTower`.

- [ ] **Step 8: Run tests**

Run:

```bash
flutter test test/game/game_session_test.dart
flutter test
```

Expected: all tests pass. Widget tests still expect the old HUD until Task 8.

- [ ] **Step 9: Commit session rule changes**

```bash
git add lib/game/rules/game_session.dart lib/game/orion_defense_game.dart lib/game/components/tower_component.dart lib/game/ui/orion_game_page.dart test/game/game_session_test.dart
git commit -m "feat: add tower unlock and specialization rules"
```

## Task 3: Add Pure Combat Effect Helpers

**Files:**
- Create: `lib/game/rules/combat_effects.dart`
- Create: `test/game/combat_effects_test.dart`

- [ ] **Step 1: Write failing combat helper tests**

Create `test/game/combat_effects_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/rules/combat_effects.dart';
import 'package:orion/game/rules/tower_targeting.dart';

void main() {
  group('CombatEffects', () {
    test('shield absorbs damage before health', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(
          health: 50,
          maxHealth: 50,
          shield: 20,
          damage: 15,
        ),
      );

      expect(result.health, 50);
      expect(result.shield, 5);
      expect(result.healthDamage, 0);
      expect(result.shieldDamage, 15);
    });

    test('overflow shield damage reaches health through armor', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 10,
          damage: 30,
          armorReduction: 0.25,
        ),
      );

      expect(result.shield, 0);
      expect(result.shieldDamage, 10);
      expect(result.healthDamage, 15);
      expect(result.health, 85);
    });

    test('armor reduction clamps and armor shred reduces the penalty', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 0,
          damage: 40,
          armorReduction: 0.95,
          armorShred: 0.35,
        ),
      );

      expect(result.healthDamage, closeTo(24, 0.001));
      expect(result.health, closeTo(76, 0.001));
    });

    test('corrosion bypasses armor and pauses regen', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 0,
          damage: 10,
          armorReduction: 0.50,
          bypassArmor: true,
        ),
      );

      expect(result.healthDamage, 10);
      expect(result.health, 90);
    });

    test('regen never exceeds max health and stops while corroded', () {
      expect(
        CombatEffects.applyRegen(
          health: 95,
          maxHealth: 100,
          regenPerSecond: 10,
          dt: 1,
          isCorroded: false,
        ),
        100,
      );
      expect(
        CombatEffects.applyRegen(
          health: 80,
          maxHealth: 100,
          regenPerSecond: 10,
          dt: 1,
          isCorroded: true,
        ),
        80,
      );
    });

    test('slow stacking keeps strongest multiplier and longest duration', () {
      final slow = CombatEffects.mergeSlow(
        currentMultiplier: 0.62,
        currentRemaining: 1.0,
        incomingMultiplier: 0.48,
        incomingDuration: 2.0,
      );

      expect(slow.multiplier, 0.48);
      expect(slow.remaining, 2.0);
    });

    test('slow multiplier is clamped', () {
      final slow = CombatEffects.mergeSlow(
        currentMultiplier: 1,
        currentRemaining: 0,
        incomingMultiplier: 0.05,
        incomingDuration: 2.0,
      );

      expect(slow.multiplier, 0.25);
      expect(slow.remaining, 2.0);
    });

    test('selects chain targets without repeats', () {
      const candidates = [
        TargetCandidate(id: 1, x: 0, y: 0, pathProgress: 0.3, isAlive: true),
        TargetCandidate(id: 2, x: 30, y: 0, pathProgress: 0.2, isAlive: true),
        TargetCandidate(id: 3, x: 64, y: 0, pathProgress: 0.1, isAlive: true),
        TargetCandidate(id: 4, x: 200, y: 0, pathProgress: 0.9, isAlive: true),
      ];

      final chain = CombatEffects.selectChainTargets(
        firstTarget: candidates.first,
        candidates: candidates,
        chainCount: 3,
        chainRange: 70,
      );

      expect(chain.map((candidate) => candidate.id), [1, 2, 3]);
    });

    test('selects pierce targets near a line through the primary target', () {
      const tower = TargetPoint(x: 0, y: 0);
      const primary = TargetCandidate(
        id: 1,
        x: 100,
        y: 0,
        pathProgress: 0.4,
        isAlive: true,
      );
      const candidates = [
        primary,
        TargetCandidate(id: 2, x: 140, y: 8, pathProgress: 0.5, isAlive: true),
        TargetCandidate(id: 3, x: 180, y: 40, pathProgress: 0.6, isAlive: true),
      ];

      final pierced = CombatEffects.selectPierceTargets(
        tower: tower,
        primaryTarget: primary,
        candidates: candidates,
        pierceCount: 3,
        pierceWidth: 20,
      );

      expect(pierced.map((candidate) => candidate.id), [1, 2]);
    });

    test('caps drone spawns by active count', () {
      expect(
        CombatEffects.allowedDroneLaunches(
          requested: 4,
          active: 5,
          maxActive: 8,
        ),
        3,
      );
      expect(
        CombatEffects.allowedDroneLaunches(
          requested: 2,
          active: 8,
          maxActive: 8,
        ),
        0,
      );
    });
  });
}
```

- [ ] **Step 2: Run the combat helper test and verify it fails**

Run:

```bash
flutter test test/game/combat_effects_test.dart
```

Expected: fails because `combat_effects.dart` does not exist.

- [ ] **Step 3: Implement pure combat helpers**

Create `lib/game/rules/combat_effects.dart`:

```dart
import 'dart:math' as math;

import 'tower_targeting.dart';

class DamageInput {
  const DamageInput({
    required this.health,
    required this.maxHealth,
    required this.shield,
    required this.damage,
    this.armorReduction = 0,
    this.armorShred = 0,
    this.shieldDamageMultiplier = 1,
    this.armorDamageMultiplier = 1,
    this.bypassArmor = false,
  });

  final double health;
  final double maxHealth;
  final double shield;
  final double damage;
  final double armorReduction;
  final double armorShred;
  final double shieldDamageMultiplier;
  final double armorDamageMultiplier;
  final bool bypassArmor;
}

class DamageResult {
  const DamageResult({
    required this.health,
    required this.shield,
    required this.healthDamage,
    required this.shieldDamage,
  });

  final double health;
  final double shield;
  final double healthDamage;
  final double shieldDamage;
}

class SlowMergeResult {
  const SlowMergeResult({required this.multiplier, required this.remaining});

  final double multiplier;
  final double remaining;
}

class CombatEffects {
  static DamageResult resolveDamage(DamageInput input) {
    final safeDamage = math.max(0, input.damage);
    var remainingDamage = safeDamage;
    var shield = math.max(0, input.shield);
    var shieldDamage = 0.0;

    if (shield > 0 && remainingDamage > 0) {
      final adjustedShieldDamage = remainingDamage * input.shieldDamageMultiplier;
      shieldDamage = math.min(shield, adjustedShieldDamage);
      shield -= shieldDamage;
      remainingDamage = math.max(0, remainingDamage - (shieldDamage / input.shieldDamageMultiplier));
    }

    var healthDamage = 0.0;
    if (remainingDamage > 0) {
      if (input.bypassArmor) {
        healthDamage = remainingDamage;
      } else {
        final armor = (input.armorReduction - input.armorShred).clamp(0, 0.75).toDouble();
        healthDamage = remainingDamage * (1 - armor) * input.armorDamageMultiplier;
      }
    }

    final health = (input.health - healthDamage).clamp(0, input.maxHealth).toDouble();
    return DamageResult(
      health: health,
      shield: shield,
      healthDamage: input.health - health,
      shieldDamage: shieldDamage,
    );
  }

  static double applyRegen({
    required double health,
    required double maxHealth,
    required double regenPerSecond,
    required double dt,
    required bool isCorroded,
  }) {
    if (isCorroded || regenPerSecond <= 0 || dt <= 0) {
      return health;
    }
    return (health + regenPerSecond * dt).clamp(0, maxHealth).toDouble();
  }

  static SlowMergeResult mergeSlow({
    required double currentMultiplier,
    required double currentRemaining,
    required double incomingMultiplier,
    required double incomingDuration,
  }) {
    if (incomingDuration <= 0 || incomingMultiplier <= 0 || incomingMultiplier >= 1) {
      return SlowMergeResult(
        multiplier: currentRemaining > 0 ? currentMultiplier : 1,
        remaining: math.max(0, currentRemaining),
      );
    }
    final clampedIncoming = incomingMultiplier.clamp(0.25, 1.0).toDouble();
    final activeCurrent = currentRemaining > 0 ? currentMultiplier : 1.0;
    return SlowMergeResult(
      multiplier: math.min(activeCurrent, clampedIncoming),
      remaining: math.max(currentRemaining, incomingDuration),
    );
  }

  static List<TargetCandidate> selectChainTargets({
    required TargetCandidate firstTarget,
    required Iterable<TargetCandidate> candidates,
    required int chainCount,
    required double chainRange,
  }) {
    if (chainCount <= 0 || !firstTarget.isAlive) {
      return const [];
    }
    final selected = <TargetCandidate>[firstTarget];
    var current = firstTarget;
    while (selected.length < chainCount) {
      TargetCandidate? nearest;
      var nearestDistanceSquared = double.infinity;
      for (final candidate in candidates) {
        if (!candidate.isAlive ||
            selected.any((selectedCandidate) => selectedCandidate.id == candidate.id)) {
          continue;
        }
        final dx = candidate.x - current.x;
        final dy = candidate.y - current.y;
        final distanceSquared = (dx * dx) + (dy * dy);
        if (distanceSquared <= chainRange * chainRange &&
            distanceSquared < nearestDistanceSquared) {
          nearest = candidate;
          nearestDistanceSquared = distanceSquared;
        }
      }
      if (nearest == null) {
        break;
      }
      selected.add(nearest);
      current = nearest;
    }
    return selected;
  }

  static List<TargetCandidate> selectPierceTargets({
    required TargetPoint tower,
    required TargetCandidate primaryTarget,
    required Iterable<TargetCandidate> candidates,
    required int pierceCount,
    required double pierceWidth,
  }) {
    if (pierceCount <= 0 || !primaryTarget.isAlive) {
      return const [];
    }

    final directionX = primaryTarget.x - tower.x;
    final directionY = primaryTarget.y - tower.y;
    final length = math.sqrt(directionX * directionX + directionY * directionY);
    if (length == 0) {
      return [primaryTarget];
    }
    final unitX = directionX / length;
    final unitY = directionY / length;

    final hits = <({TargetCandidate candidate, double projection})>[];
    for (final candidate in candidates) {
      if (!candidate.isAlive) {
        continue;
      }
      final relativeX = candidate.x - tower.x;
      final relativeY = candidate.y - tower.y;
      final projection = relativeX * unitX + relativeY * unitY;
      if (projection < 0) {
        continue;
      }
      final closestX = tower.x + unitX * projection;
      final closestY = tower.y + unitY * projection;
      final dx = candidate.x - closestX;
      final dy = candidate.y - closestY;
      final distanceToLine = math.sqrt(dx * dx + dy * dy);
      if (distanceToLine <= pierceWidth) {
        hits.add((candidate: candidate, projection: projection));
      }
    }
    hits.sort((a, b) => a.projection.compareTo(b.projection));
    return hits
        .take(pierceCount)
        .map((hit) => hit.candidate)
        .toList(growable: false);
  }

  static int allowedDroneLaunches({
    required int requested,
    required int active,
    required int maxActive,
  }) {
    if (requested <= 0 || maxActive <= 0 || active >= maxActive) {
      return 0;
    }
    return math.min(requested, maxActive - active);
  }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
dart format lib/game/rules/combat_effects.dart test/game/combat_effects_test.dart
flutter test test/game/combat_effects_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit combat helper**

```bash
git add lib/game/rules/combat_effects.dart test/game/combat_effects_test.dart
git commit -m "feat: add Orion combat effect rules"
```

## Task 4: Add Enemy Shield, Armor, Regen, Corrosion, And Slow Runtime

**Files:**
- Modify: `lib/game/components/enemy_component.dart`
- Modify: `test/game/enemy_component_test.dart`

- [ ] **Step 1: Add failing enemy component tests**

Append these tests inside the `EnemyComponent` group:

```dart
test('shield absorbs damage before health in runtime component', () {
  final enemy = EnemyComponent(
    enemyId: 1,
    stats: const EnemyStats(
      health: 50,
      speed: 10,
      baseDamage: 1,
      goldReward: 1,
      shieldHealth: 20,
    ),
    waypoints: [Vector2(0, 0), Vector2(10, 0)],
    onKilled: (_) {},
    onReachedBase: (_) {},
  );

  enemy.applyDamage(15);

  expect(enemy.health, 50);
  expect(enemy.shield, 5);
  expect(enemy.isAlive, isTrue);
});

test('regen restores health while corrosion pauses regen', () {
  final enemy = EnemyComponent(
    enemyId: 1,
    stats: const EnemyStats(
      health: 100,
      speed: 10,
      baseDamage: 1,
      goldReward: 1,
      traits: {EnemyTrait.regen},
      regenPerSecond: 10,
    ),
    waypoints: [Vector2(0, 0), Vector2(100, 0)],
    onKilled: (_) {},
    onReachedBase: (_) {},
  );

  enemy.applyDamage(30);
  enemy.update(1);
  expect(enemy.health, closeTo(80, 0.001));

  enemy.applyCorrosion(
    damagePerSecond: 5,
    duration: 2,
    armorShred: 0.1,
  );
  enemy.update(1);

  expect(enemy.health, closeTo(75, 0.001));
  expect(enemy.isCorroded, isTrue);
});

test('armor reduces health damage and corrosion damage bypasses armor', () {
  final enemy = EnemyComponent(
    enemyId: 1,
    stats: const EnemyStats(
      health: 100,
      speed: 10,
      baseDamage: 1,
      goldReward: 1,
      traits: {EnemyTrait.armored},
      armorReduction: 0.50,
    ),
    waypoints: [Vector2(0, 0), Vector2(10, 0)],
    onKilled: (_) {},
    onReachedBase: (_) {},
  );

  enemy.applyDamage(20);
  expect(enemy.health, 90);

  enemy.applyCorrosion(
    damagePerSecond: 10,
    duration: 1,
    armorShred: 0.2,
  );
  enemy.update(1);

  expect(enemy.health, 80);
});
```

- [ ] **Step 2: Run enemy component tests and verify they fail**

Run:

```bash
flutter test test/game/enemy_component_test.dart
```

Expected: fails because `EnemyComponent` has no shield/corrosion APIs.

- [ ] **Step 3: Add enemy state fields**

In `EnemyComponent`, add:

```dart
late double shield = stats.shieldHealth;
late final double maxHealth = stats.health;
double _corrosionDamagePerSecond = 0;
double _corrosionRemaining = 0;
double _armorShred = 0;

bool get isCorroded => _corrosionRemaining > 0;
bool get isSlowed => _slowRemaining > 0 && _slowMultiplier < 1;
double get armorReduction =>
    (stats.armorReduction - _armorShred).clamp(0, 0.75).toDouble();
```

- [ ] **Step 4: Route damage through `CombatEffects`**

Import `combat_effects.dart` and replace `applyDamage` with:

```dart
void applyDamage(
  double amount, {
  double shieldDamageMultiplier = 1,
  double armorDamageMultiplier = 1,
  double armorShred = 0,
  bool bypassArmor = false,
}) {
  if (!isAlive || amount <= 0) {
    return;
  }

  final result = CombatEffects.resolveDamage(
    DamageInput(
      health: health,
      maxHealth: maxHealth,
      shield: shield,
      damage: amount,
      armorReduction: stats.armorReduction,
      armorShred: math.max(_armorShred, armorShred),
      shieldDamageMultiplier: shieldDamageMultiplier,
      armorDamageMultiplier: armorDamageMultiplier,
      bypassArmor: bypassArmor,
    ),
  );
  health = result.health;
  shield = result.shield;
  if (health == 0) {
    _resolve(onKilled);
  }
}
```

- [ ] **Step 5: Add corrosion and regen ticking**

Add this method:

```dart
void applyCorrosion({
  required double damagePerSecond,
  required double duration,
  required double armorShred,
}) {
  if (!isAlive || duration <= 0 || damagePerSecond <= 0) {
    return;
  }
  _corrosionDamagePerSecond = math.max(
    _corrosionDamagePerSecond,
    damagePerSecond,
  );
  _corrosionRemaining = math.max(_corrosionRemaining, duration);
  _armorShred = math.max(_armorShred, armorShred);
}
```

At the start of `update`, after the `isAlive` guard and before movement, add:

```dart
_tickStatuses(dt);
if (!isAlive) {
  return;
}
```

Add `_tickStatuses`:

```dart
void _tickStatuses(double dt) {
  if (_corrosionRemaining > 0) {
    final tickDuration = math.min(dt, _corrosionRemaining);
    _corrosionRemaining = math.max(0, _corrosionRemaining - dt);
    applyDamage(
      _corrosionDamagePerSecond * tickDuration,
      bypassArmor: true,
    );
    if (_corrosionRemaining == 0) {
      _corrosionDamagePerSecond = 0;
      _armorShred = 0;
    }
  }

  health = CombatEffects.applyRegen(
    health: health,
    maxHealth: maxHealth,
    regenPerSecond: stats.regenPerSecond,
    dt: dt,
    isCorroded: isCorroded,
  );
}
```

- [ ] **Step 6: Route slow through `CombatEffects.mergeSlow`**

Replace the body of `applySlow` after validation with:

```dart
final merged = CombatEffects.mergeSlow(
  currentMultiplier: _slowMultiplier,
  currentRemaining: _slowRemaining,
  incomingMultiplier: multiplier,
  incomingDuration: duration,
);
_slowMultiplier = merged.multiplier;
_slowRemaining = merged.remaining;
```

- [ ] **Step 7: Run tests**

Run:

```bash
dart format lib/game/components/enemy_component.dart test/game/enemy_component_test.dart
flutter test test/game/enemy_component_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 8: Commit enemy runtime effects**

```bash
git add lib/game/components/enemy_component.dart test/game/enemy_component_test.dart
git commit -m "feat: add enemy defensive status runtime"
```

## Task 5: Spawn Wave Groups And Award Clear Bonuses In Runtime

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/game_session_test.dart`

- [ ] **Step 1: Add a session test for final-wave no clear bonus**

Append this test to `test/game/game_session_test.dart`:

```dart
test('final wave win does not add a clear bonus', () {
  final session = GameSession.initial();

  for (var wave = 0; wave < GameBalance.waves.length; wave += 1) {
    expect(session.startWave(), isTrue);
    session.finishActiveWave();
  }

  expect(session.phase, GamePhase.won);
  expect(session.gold, 150 + 30 + 40 + 50 + 65 + 80 + 95 + 115);
});
```

- [ ] **Step 2: Run the session test**

Run:

```bash
flutter test test/game/game_session_test.dart
```

Expected: passes if Task 2 clear bonus logic is correct. Fix Task 2 logic before continuing if it fails.

- [ ] **Step 3: Replace single-spawn counters with group spawn state**

In `OrionDefenseGame`, replace:

```dart
double _spawnTimer = 0;
int _spawnedCount = 0;
```

with:

```dart
double _spawnTimer = 0;
int _spawnedCount = 0;
int _activeGroupIndex = 0;
int _spawnedInGroup = 0;
```

In `startWave`, after `_spawnedCount = 0`, add:

```dart
_activeGroupIndex = 0;
_spawnedInGroup = 0;
```

Reset those same group fields in `restart`, `_handleEnemyReachedBase` loss cleanup, and `_finishWaveIfComplete`.

- [ ] **Step 4: Spawn from wave groups**

Replace `_spawnWaveEnemies` with:

```dart
void _spawnWaveEnemies(double dt) {
  final wave = _session.activeWave;
  if (wave == null || _spawnedCount >= wave.enemyCount) {
    return;
  }

  _spawnTimer -= dt;
  while (_spawnTimer <= 0 && _spawnedCount < wave.enemyCount) {
    final group = wave.groups[_activeGroupIndex];
    _spawnEnemy(group.enemyStats);
    _spawnedCount += 1;
    _spawnedInGroup += 1;

    if (_spawnedInGroup >= group.enemyCount) {
      _activeGroupIndex += 1;
      _spawnedInGroup = 0;
      if (_activeGroupIndex >= wave.groups.length) {
        _spawnTimer = 0;
        return;
      }
      _spawnTimer += wave.groups[_activeGroupIndex].initialDelay;
    } else {
      _spawnTimer += group.spawnInterval;
    }
  }
}
```

Replace `_spawnEnemy(WaveDefinition wave)` with:

```dart
void _spawnEnemy(EnemyStats stats) {
  final enemy = EnemyComponent(
    enemyId: _nextEnemyId,
    stats: stats,
    waypoints: _pathWaypoints(),
    spriteSheet: _spriteSheet,
    onKilled: _handleEnemyKilled,
    onReachedBase: _handleEnemyReachedBase,
    priority: 20,
  );
  _nextEnemyId += 1;
  _activeEnemyComponents[enemy.enemyId] = enemy;
  add(enemy);
}
```

Update `_finishWaveIfComplete` to check `_spawnedCount < wave.enemyCount`.

- [ ] **Step 5: Run tests**

Run:

```bash
dart format lib/game/orion_defense_game.dart test/game/game_session_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit wave group runtime**

```bash
git add lib/game/orion_defense_game.dart test/game/game_session_test.dart
git commit -m "feat: spawn Orion wave groups"
```

## Task 6: Add Tower Variety Atlas Metadata And Rendering Fallbacks

**Files:**
- Create: `lib/game/assets/game_tower_variety_sheet.dart`
- Modify: `lib/game/assets/game_sprite_sheet.dart`
- Modify: `lib/game/components/tower_component.dart`
- Modify: `lib/game/components/projectile_component.dart`
- Modify: `pubspec.yaml`
- Add: `assets/images/orion_tower_variety_sheet.png`
- Modify: `test/game/game_sprite_sheet_test.dart`

- [ ] **Step 1: Add failing atlas metadata tests**

Append these tests to `test/game/game_sprite_sheet_test.dart`:

```dart
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
```

Add inside `main`:

```dart
group('GameTowerVarietySheet', () {
  test('maps the 4x4 variety sheet cells in stable order', () {
    expect(GameTowerVarietySheet.columns, 4);
    expect(GameTowerVarietySheet.rows, 4);
    expect(GameTowerVarietySheet.fileName, 'orion_tower_variety_sheet.png');
    expect(
      GameTowerVarietySheet.assetPath,
      'assets/images/orion_tower_variety_sheet.png',
    );

    final railgunRect = GameTowerVarietySheet.sourceRectFor(
      GameTowerVarietySprite.railgunTower,
      imageWidth: 1024,
      imageHeight: 1024,
    );
    expect(railgunRect.left, 0);
    expect(railgunRect.top, 0);
    expect(railgunRect.width, 256);
    expect(railgunRect.height, 256);

    final finalRect = GameTowerVarietySheet.sourceRectFor(
      GameTowerVarietySprite.prismSplit,
      imageWidth: 1024,
      imageHeight: 1024,
    );
    expect(finalRect.left, 768);
    expect(finalRect.top, 768);
    expect(finalRect.width, 256);
    expect(finalRect.height, 256);
  });

  test('maps new tower and projectile sprites', () {
    expect(
      GameTowerVarietySheet.spriteForTower(TowerType.railgun),
      GameTowerVarietySprite.railgunTower,
    );
    expect(
      GameTowerVarietySheet.spriteForTower(TowerType.ionChain),
      GameTowerVarietySprite.ionChainTower,
    );
    expect(
      GameTowerVarietySheet.spriteForTower(TowerType.nanite),
      GameTowerVarietySprite.naniteTower,
    );
    expect(
      GameTowerVarietySheet.spriteForTower(TowerType.gravityWell),
      GameTowerVarietySprite.gravityWellTower,
    );
    expect(
      GameTowerVarietySheet.spriteForTower(TowerType.droneBay),
      GameTowerVarietySprite.droneBayTower,
    );
    expect(
      GameTowerVarietySheet.spriteForProjectile(TowerType.railgun),
      GameTowerVarietySprite.railSlug,
    );
  });
});
```

- [ ] **Step 2: Run sprite metadata tests and verify they fail**

Run:

```bash
flutter test test/game/game_sprite_sheet_test.dart
```

Expected: fails because `game_tower_variety_sheet.dart` does not exist.

- [ ] **Step 3: Add variety atlas metadata**

Create `lib/game/assets/game_tower_variety_sheet.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

enum GameTowerVarietySprite {
  railgunTower,
  ionChainTower,
  naniteTower,
  gravityWellTower,
  droneBayTower,
  railSlug,
  ionArc,
  naniteCloud,
  gravityField,
  drone,
  shieldIndicator,
  armorIndicator,
  regenIndicator,
  corrosionIndicator,
  clusterBurst,
  prismSplit,
}

class GameTowerVarietySheet {
  GameTowerVarietySheet._(this._sprites);

  static const String fileName = 'orion_tower_variety_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 4;

  final Map<GameTowerVarietySprite, Sprite> _sprites;

  static Future<GameTowerVarietySheet> load(Images images) async {
    final image = await images.load(fileName);
    return GameTowerVarietySheet.fromImage(image);
  }

  static GameTowerVarietySheet fromImage(ui.Image image) {
    final sprites = <GameTowerVarietySprite, Sprite>{};
    for (final sprite in GameTowerVarietySprite.values) {
      final sourceRect = sourceRectFor(
        sprite,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      sprites[sprite] = Sprite(
        image,
        srcPosition: Vector2(sourceRect.left, sourceRect.top),
        srcSize: Vector2(sourceRect.width, sourceRect.height),
      );
    }
    return GameTowerVarietySheet._(sprites);
  }

  Sprite sprite(GameTowerVarietySprite sprite) => _sprites[sprite]!;

  static ui.Rect sourceRectFor(
    GameTowerVarietySprite sprite, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final index = sprite.index;
    final cellWidth = imageWidth / columns;
    final cellHeight = imageHeight / rows;
    final column = index % columns;
    final row = index ~/ columns;
    return ui.Rect.fromLTWH(
      column * cellWidth,
      row * cellHeight,
      cellWidth,
      cellHeight,
    );
  }

  static bool hasTowerSprite(TowerType type) {
    return switch (type) {
      TowerType.laser || TowerType.rocket || TowerType.cryo => false,
      TowerType.railgun ||
      TowerType.ionChain ||
      TowerType.nanite ||
      TowerType.gravityWell ||
      TowerType.droneBay => true,
    };
  }

  static GameTowerVarietySprite spriteForTower(TowerType type) {
    return switch (type) {
      TowerType.railgun => GameTowerVarietySprite.railgunTower,
      TowerType.ionChain => GameTowerVarietySprite.ionChainTower,
      TowerType.nanite => GameTowerVarietySprite.naniteTower,
      TowerType.gravityWell => GameTowerVarietySprite.gravityWellTower,
      TowerType.droneBay => GameTowerVarietySprite.droneBayTower,
      TowerType.laser || TowerType.rocket || TowerType.cryo =>
        throw ArgumentError.value(type, 'type', 'Use GameSpriteSheet'),
    };
  }

  static GameTowerVarietySprite spriteForProjectile(TowerType type) {
    return switch (type) {
      TowerType.railgun => GameTowerVarietySprite.railSlug,
      TowerType.ionChain => GameTowerVarietySprite.ionArc,
      TowerType.nanite => GameTowerVarietySprite.naniteCloud,
      TowerType.gravityWell => GameTowerVarietySprite.gravityField,
      TowerType.droneBay => GameTowerVarietySprite.drone,
      TowerType.laser || TowerType.rocket || TowerType.cryo =>
        throw ArgumentError.value(type, 'type', 'Use GameSpriteSheet'),
    };
  }
}
```

- [ ] **Step 4: Update old sprite mapping to reject new tower sprites**

In `GameSpriteSheet.spriteForTower`, keep Laser/Rocket/Cryo and throw for new towers:

```dart
TowerType.railgun ||
TowerType.ionChain ||
TowerType.nanite ||
TowerType.gravityWell ||
TowerType.droneBay =>
  throw ArgumentError.value(type, 'type', 'Use GameTowerVarietySheet'),
```

Apply the same pattern to `spriteForProjectile`.

- [ ] **Step 5: Register and generate the new asset**

Add to `pubspec.yaml` assets:

```yaml
    - assets/images/orion_tower_variety_sheet.png
```

Generate a 4 by 4 PNG at `assets/images/orion_tower_variety_sheet.png` using this exact prompt:

```text
Create a single 4 by 4 sprite sheet for a top-down sci-fi tower defense game on a flat black transparent-friendly background. Sixteen evenly spaced cells, no text, no labels, no watermark. Cell order left to right, top to bottom: railgun tower with long silver barrel and blue coil; ion chain tower with forked antenna and violet arcs; nanite corrosion tower with green emitter canisters; gravity well tower with dark circular gravity core; drone bay tower with small launch pads; rail slug projectile; ion arc projectile; nanite cloud projectile; circular gravity field effect; small attack drone; shield indicator icon; armor indicator icon; regeneration indicator icon; corrosion indicator icon; compact cluster explosion burst; prism split beam effect. Match polished top-down orbital defense style, crisp silhouettes, generous padding, readable at 64 pixels.
```

After generation, place the final PNG in `assets/images/`. Keep the file dimensions square. The metadata tests only require a 4 by 4 grid and do not depend on exact dimensions.

- [ ] **Step 6: Load the new sheet in `OrionDefenseGame`**

Add field:

```dart
GameTowerVarietySheet? _towerVarietySheet;
```

In `onLoad`, after `_spriteSheet = await GameSpriteSheet.load(images);`, load:

```dart
_towerVarietySheet = await GameTowerVarietySheet.load(images);
```

Pass `towerVarietySheet: _towerVarietySheet` into `TowerComponent` and `ProjectileComponent`.

- [ ] **Step 7: Render old and new tower sprites from the correct atlas**

In `TowerComponent`, import `game_tower_variety_sheet.dart`, add a constructor argument and field:

```dart
this.towerVarietySheet,
```

```dart
final GameTowerVarietySheet? towerVarietySheet;
```

Update `OrionDefenseGame._addTowerComponent` to pass:

```dart
towerVarietySheet: _towerVarietySheet,
```

Replace the sprite branch in `TowerComponent.render` with:

```dart
if (_renderTowerSprite(canvas)) {
  canvas.drawCircle(Offset(radius, radius), radius - 1, _strokePaint);
  return;
}

super.render(canvas);
canvas.drawCircle(Offset(radius, radius), radius - 1, _strokePaint);
```

Add this helper:

```dart
bool _renderTowerSprite(Canvas canvas) {
  if (GameTowerVarietySheet.hasTowerSprite(placedTower.type)) {
    final towerVarietySheet = this.towerVarietySheet;
    if (towerVarietySheet == null) {
      return false;
    }
    towerVarietySheet
        .sprite(GameTowerVarietySheet.spriteForTower(placedTower.type))
        .render(
          canvas,
          position: Vector2(radius, radius),
          size: Vector2.all(radius * 2.4),
          anchor: Anchor.center,
        );
    return true;
  }

  final spriteSheet = this.spriteSheet;
  if (spriteSheet == null) {
    return false;
  }
  spriteSheet
      .sprite(GameSpriteSheet.spriteForTower(placedTower.type))
      .render(
        canvas,
        position: Vector2(radius, radius),
        size: Vector2.all(radius * 2.4),
        anchor: Anchor.center,
      );
  return true;
}
```

- [ ] **Step 8: Render old and new projectile sprites from the correct atlas**

In `ProjectileComponent`, import `game_tower_variety_sheet.dart`, add a constructor argument and field:

```dart
this.towerVarietySheet,
```

```dart
final GameTowerVarietySheet? towerVarietySheet;
```

Update `OrionDefenseGame._launchProjectile` to pass:

```dart
towerVarietySheet: _towerVarietySheet,
```

Replace the sprite branch in `ProjectileComponent.render` with:

```dart
if (_renderProjectileSprite(canvas)) {
  return;
}
super.render(canvas);
```

Add this helper:

```dart
bool _renderProjectileSprite(Canvas canvas) {
  if (GameTowerVarietySheet.hasTowerSprite(stats.type)) {
    final towerVarietySheet = this.towerVarietySheet;
    if (towerVarietySheet == null) {
      return false;
    }
    towerVarietySheet
        .sprite(GameTowerVarietySheet.spriteForProjectile(stats.type))
        .render(
          canvas,
          position: Vector2(radius, radius),
          size: Vector2.all(radius * 3),
          anchor: Anchor.center,
        );
    return true;
  }

  final spriteSheet = this.spriteSheet;
  if (spriteSheet == null) {
    return false;
  }
  spriteSheet
      .sprite(GameSpriteSheet.spriteForProjectile(stats.type))
      .render(
        canvas,
        position: Vector2(radius, radius),
        size: Vector2.all(radius * 3),
        anchor: Anchor.center,
      );
  return true;
}
```

- [ ] **Step 9: Add fallback color mapping**

In `TowerComponent._towerColor`, add new colors:

```dart
TowerType.railgun => const Color(0xFFC9D6E8),
TowerType.ionChain => const Color(0xFFB476FF),
TowerType.nanite => const Color(0xFF67D46E),
TowerType.gravityWell => const Color(0xFF6E7BFF),
TowerType.droneBay => const Color(0xFFFFD166),
```

In `ProjectileComponent._projectileColor`, add:

```dart
TowerType.railgun => const Color(0xFFE8F1FF),
TowerType.ionChain => const Color(0xFFD7B2FF),
TowerType.nanite => const Color(0xFF9EF59A),
TowerType.gravityWell => const Color(0xFFA9B0FF),
TowerType.droneBay => const Color(0xFFFFE08A),
```

- [ ] **Step 10: Run tests and asset validation**

Run:

```bash
dart format lib/game/assets/game_tower_variety_sheet.dart lib/game/assets/game_sprite_sheet.dart lib/game/components/tower_component.dart lib/game/components/projectile_component.dart lib/game/orion_defense_game.dart test/game/game_sprite_sheet_test.dart
sips -g pixelWidth -g pixelHeight assets/images/orion_tower_variety_sheet.png
flutter test test/game/game_sprite_sheet_test.dart
flutter test
```

Expected: `sips` prints nonzero pixel width and height, and all tests pass.

- [ ] **Step 11: Commit asset metadata and atlas**

```bash
git add pubspec.yaml assets/images/orion_tower_variety_sheet.png lib/game/assets/game_tower_variety_sheet.dart lib/game/assets/game_sprite_sheet.dart lib/game/components/tower_component.dart lib/game/components/projectile_component.dart lib/game/orion_defense_game.dart test/game/game_sprite_sheet_test.dart
git commit -m "feat: add Orion tower variety atlas"
```

## Task 7: Integrate New Tower Combat Behaviors

**Files:**
- Modify: `lib/game/components/projectile_component.dart`
- Modify: `lib/game/components/tower_component.dart`
- Create: `lib/game/components/gravity_field_component.dart`
- Create: `lib/game/components/drone_component.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/combat_effects_test.dart`

- [ ] **Step 1: Add behavior regression tests to combat helpers**

Append these tests to `test/game/combat_effects_test.dart`:

```dart
test('chain damage falls off by jump index', () {
  expect(
    CombatEffects.damageForChainJump(
      baseDamage: 100,
      chainFalloff: 0.75,
      jumpIndex: 0,
    ),
    100,
  );
  expect(
    CombatEffects.damageForChainJump(
      baseDamage: 100,
      chainFalloff: 0.75,
      jumpIndex: 2,
    ),
    closeTo(56.25, 0.001),
  );
});

test('slowed damage multiplier only applies to slowed enemies', () {
  expect(
    CombatEffects.damageAgainstSlowState(
      baseDamage: 10,
      slowedDamageMultiplier: 1.6,
      isSlowed: true,
    ),
    16,
  );
  expect(
    CombatEffects.damageAgainstSlowState(
      baseDamage: 10,
      slowedDamageMultiplier: 1.6,
      isSlowed: false,
    ),
    10,
  );
});
```

- [ ] **Step 2: Run the helper tests and verify they fail**

Run:

```bash
flutter test test/game/combat_effects_test.dart
```

Expected: fails because the two helper functions do not exist.

- [ ] **Step 3: Add helper functions**

In `CombatEffects`, add:

```dart
static double damageForChainJump({
  required double baseDamage,
  required double chainFalloff,
  required int jumpIndex,
}) {
  if (jumpIndex <= 0) {
    return baseDamage;
  }
  return baseDamage * math.pow(chainFalloff, jumpIndex);
}

static double damageAgainstSlowState({
  required double baseDamage,
  required double slowedDamageMultiplier,
  required bool isSlowed,
}) {
  return isSlowed ? baseDamage * slowedDamageMultiplier : baseDamage;
}
```

- [ ] **Step 4: Add gravity field component**

Create `lib/game/components/gravity_field_component.dart`:

```dart
import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

typedef GravityEnemiesProvider = Iterable<EnemyComponent> Function();

class GravityFieldComponent extends CircleComponent {
  GravityFieldComponent({
    required this.stats,
    required Vector2 center,
    required this.enemiesProvider,
    super.priority,
  }) : _remaining = stats.fieldDuration,
       _tickRemaining = 0,
       super(
         radius: stats.fieldRadius,
         anchor: Anchor.center,
         position: center.clone(),
         paint: Paint()..color = const Color(0x446E7BFF),
       );

  final TowerStats stats;
  final GravityEnemiesProvider enemiesProvider;
  double _remaining;
  double _tickRemaining;

  @override
  void update(double dt) {
    super.update(dt);
    _remaining -= dt;
    _tickRemaining -= dt;
    if (_remaining <= 0) {
      removeFromParent();
      return;
    }
    if (_tickRemaining > 0) {
      return;
    }
    _tickRemaining = stats.fieldTickInterval;
    for (final enemy in enemiesProvider()) {
      if (!enemy.isAlive || enemy.position.distanceTo(position) > radius) {
        continue;
      }
      if (stats.damage > 0) {
        enemy.applyDamage(stats.damage);
      }
      if (stats.slowMultiplier < 1 && stats.slowDuration > 0) {
        enemy.applySlow(
          multiplier: stats.slowMultiplier,
          duration: stats.slowDuration,
        );
      }
    }
  }
}
```

- [ ] **Step 5: Add drone component**

Create `lib/game/components/drone_component.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

typedef DroneTargetProvider = EnemyComponent? Function(Vector2 position);
typedef DroneExpiredCallback = void Function(DroneComponent drone);

class DroneComponent extends CircleComponent {
  DroneComponent({
    required this.ownerTowerId,
    required this.stats,
    required Vector2 startPosition,
    required this.acquireTarget,
    required this.onExpired,
    super.priority,
  }) : _remaining = stats.droneLifetime,
       _attackRemaining = 0,
       super(
         radius: 6,
         anchor: Anchor.center,
         position: startPosition.clone(),
         paint: Paint()..color = const Color(0xFFFFD166),
       );

  final int ownerTowerId;
  final TowerStats stats;
  final DroneTargetProvider acquireTarget;
  final DroneExpiredCallback onExpired;
  double _remaining;
  double _attackRemaining;

  @override
  void update(double dt) {
    super.update(dt);
    _remaining -= dt;
    _attackRemaining -= dt;
    if (_remaining <= 0) {
      _expire();
      return;
    }

    final target = acquireTarget(position);
    if (target == null || !target.isAlive) {
      return;
    }

    final toTarget = target.position - position;
    final distance = toTarget.length;
    final travel = 180 * dt;
    if (distance > 2) {
      position.add(toTarget.normalized()..scale(math.min(travel, distance)));
    }

    if (distance <= 24 && _attackRemaining <= 0) {
      target.applyDamage(stats.droneDamage);
      _attackRemaining = stats.droneAttackInterval;
    }
  }

  void _expire() {
    onExpired(this);
    removeFromParent();
  }
}
```

- [ ] **Step 6: Route projectile hits by tower behavior**

In `ProjectileComponent._resolveHit`, branch by stats:

```dart
if (stats.chainCount > 0) {
  _resolveChainHit();
  return;
}
if (stats.pierceCount > 0) {
  _resolvePierceHit();
  return;
}
if (stats.corrosionDuration > 0) {
  _resolveCorrosionHit();
  return;
}
if (stats.fieldRadius > 0 && stats.fieldDuration > 0) {
  target.applyDamage(stats.damage);
  _applySlowIfNeeded(target);
  return;
}
```

Add helper methods:

```dart
void _resolveChainHit() {
  final candidates = enemiesProvider()
      .where((enemy) => enemy.isAlive)
      .map((enemy) => enemy.targetCandidate)
      .toList(growable: false);
  final chain = CombatEffects.selectChainTargets(
    firstTarget: target.targetCandidate,
    candidates: candidates,
    chainCount: stats.chainCount,
    chainRange: stats.chainRange,
  );
  final enemyById = {
    for (final enemy in enemiesProvider()) enemy.enemyId: enemy,
  };
  for (final (index, candidate) in chain.indexed) {
    final enemy = enemyById[candidate.id];
    if (enemy == null || !enemy.isAlive) {
      continue;
    }
    enemy.applyDamage(
      CombatEffects.damageForChainJump(
        baseDamage: stats.damage,
        chainFalloff: stats.chainFalloff,
        jumpIndex: index,
      ),
      shieldDamageMultiplier: stats.shieldDamageMultiplier,
    );
  }
}

void _resolvePierceHit() {
  final candidates = enemiesProvider()
      .where((enemy) => enemy.isAlive)
      .map((enemy) => enemy.targetCandidate)
      .toList(growable: false);
  final pierced = CombatEffects.selectPierceTargets(
    tower: TargetPoint(x: position.x, y: position.y),
    primaryTarget: target.targetCandidate,
    candidates: candidates,
    pierceCount: stats.pierceCount,
    pierceWidth: stats.pierceWidth,
  );
  final enemyById = {
    for (final enemy in enemiesProvider()) enemy.enemyId: enemy,
  };
  for (final candidate in pierced) {
    enemyById[candidate.id]?.applyDamage(
      stats.damage,
      armorDamageMultiplier: stats.armorDamageMultiplier,
    );
  }
}

void _resolveCorrosionHit() {
  target.applyDamage(stats.damage);
  target.applyCorrosion(
    damagePerSecond: stats.corrosionDamagePerSecond,
    duration: stats.corrosionDuration,
    armorShred: stats.armorShred,
  );
}
```

Import `combat_effects.dart` and `tower_targeting.dart`.

- [ ] **Step 7: Launch gravity fields and drones from `OrionDefenseGame`**

In `_launchProjectile`, handle non-projectile behaviors before adding `ProjectileComponent`:

```dart
if (tower.stats.fieldRadius > 0 && tower.stats.fieldDuration > 0) {
  add(
    GravityFieldComponent(
      stats: tower.stats,
      center: target.position,
      enemiesProvider: () => _activeEnemyComponents.values,
      priority: 25,
    ),
  );
  return;
}

if (tower.stats.droneCount > 0) {
  _launchDrones(tower);
  return;
}
```

Add drone tracking:

```dart
final Map<int, int> _activeDronesByTower = {};
```

Add helper:

```dart
void _launchDrones(TowerComponent tower) {
  final active = _activeDronesByTower[tower.placedTower.id] ?? 0;
  final allowed = CombatEffects.allowedDroneLaunches(
    requested: tower.stats.droneCount,
    active: active,
    maxActive: tower.stats.maxActiveDrones,
  );
  if (allowed <= 0) {
    return;
  }
  _activeDronesByTower[tower.placedTower.id] = active + allowed;
  for (var index = 0; index < allowed; index += 1) {
    add(
      DroneComponent(
        ownerTowerId: tower.placedTower.id,
        stats: tower.stats,
        startPosition: tower.position,
        acquireTarget: _selectNearestEnemyForDrone,
        onExpired: _handleDroneExpired,
        priority: 35,
      ),
    );
  }
}

EnemyComponent? _selectNearestEnemyForDrone(Vector2 position) {
  EnemyComponent? selected;
  var selectedDistance = double.infinity;
  for (final enemy in _activeEnemyComponents.values) {
    if (!enemy.isAlive) {
      continue;
    }
    final distance = enemy.position.distanceTo(position);
    if (distance < selectedDistance) {
      selected = enemy;
      selectedDistance = distance;
    }
  }
  return selected;
}

void _handleDroneExpired(DroneComponent drone) {
  final current = _activeDronesByTower[drone.ownerTowerId] ?? 0;
  _activeDronesByTower[drone.ownerTowerId] = math.max(0, current - 1);
}
```

Import `dart:math` as `math`, `combat_effects.dart`, `drone_component.dart`, and `gravity_field_component.dart`.

Clear drone counts in `_clearCombatComponents`:

```dart
for (final drone in children.whereType<DroneComponent>().toList()) {
  drone.removeFromParent();
}
for (final field in children.whereType<GravityFieldComponent>().toList()) {
  field.removeFromParent();
}
_activeDronesByTower.clear();
```

- [ ] **Step 8: Apply Frostbite and Prism/Cluster special behavior**

In `_resolveHit` direct-hit path before `target.applyDamage`, compute:

```dart
final damage = CombatEffects.damageAgainstSlowState(
  baseDamage: stats.damage,
  slowedDamageMultiplier: stats.slowedDamageMultiplier,
  isSlowed: target.isSlowed,
);
target.applyDamage(damage);
```

After the primary direct hit, add:

```dart
if (stats.prismSplitDamageMultiplier > 0 && stats.prismSplitRange > 0) {
  _resolvePrismSplit();
}
```

For splash hits, after the existing splash loop, call:

```dart
if (stats.clusterBurstCount > 0) {
  _resolveClusterBursts(impactPosition);
}
```

Implement simple immediate secondary effects:

```dart
void _resolvePrismSplit() {
  EnemyComponent? selected;
  var selectedDistance = double.infinity;
  for (final enemy in enemiesProvider()) {
    if (identical(enemy, target) || !enemy.isAlive) {
      continue;
    }
    final distance = enemy.position.distanceTo(target.position);
    if (distance <= stats.prismSplitRange && distance < selectedDistance) {
      selected = enemy;
      selectedDistance = distance;
    }
  }
  selected?.applyDamage(stats.damage * stats.prismSplitDamageMultiplier);
}

void _resolveClusterBursts(Vector2 impactPosition) {
  for (var burst = 0; burst < stats.clusterBurstCount; burst += 1) {
    for (final enemy in enemiesProvider()) {
      if (!enemy.isAlive) {
        continue;
      }
      if (enemy.position.distanceTo(impactPosition) <= stats.clusterBurstRadius) {
        enemy.applyDamage(stats.damage * stats.clusterBurstDamageMultiplier);
      }
    }
  }
}
```

- [ ] **Step 9: Run tests**

Run:

```bash
dart format lib/game/rules/combat_effects.dart lib/game/components/projectile_component.dart lib/game/components/tower_component.dart lib/game/components/gravity_field_component.dart lib/game/components/drone_component.dart lib/game/orion_defense_game.dart test/game/combat_effects_test.dart
flutter test test/game/combat_effects_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 10: Commit combat integration**

```bash
git add lib/game/rules/combat_effects.dart lib/game/components/projectile_component.dart lib/game/components/tower_component.dart lib/game/components/gravity_field_component.dart lib/game/components/drone_component.dart lib/game/orion_defense_game.dart test/game/combat_effects_test.dart
git commit -m "feat: integrate expanded tower combat"
```

## Task 8: Update UI For Progressive Tower Reveal And Specializations

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Add failing widget expectations**

Replace `test/widget_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/main.dart';

void main() {
  testWidgets('boots into the expanded Orion tower defense shell',
      (tester) async {
    await tester.pumpWidget(const OrionApp());
    await tester.pump();

    expect(find.text('Orion'), findsOneWidget);
    expect(find.text('Gold 150'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/8'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run widget test and verify it fails**

Run:

```bash
flutter test test/widget_test.dart
```

Expected: fails if HUD still shows `Gold 120` or `Wave 1/5`.

- [ ] **Step 3: Expand `GameSnapshot`**

In `GameSnapshot`, add:

```dart
required this.unlockedTowerTypes,
```

and field:

```dart
final List<TowerType> unlockedTowerTypes;
```

In `GameSession.snapshot`, pass:

```dart
unlockedTowerTypes: unlockedTowerTypes,
```

- [ ] **Step 4: Expose specialization from the game**

Add to `OrionDefenseGame`:

```dart
void specializeSelectedTower(TowerSpecialization specialization) {
  final tower = _selectedTower;
  if (tower == null) {
    _publishSnapshot(feedback: 'Select a tower first.');
    return;
  }

  if (!_session.specializeTower(tower.id, specialization)) {
    _publishSnapshot(feedback: _specializationMessage(tower, specialization));
    return;
  }

  final specializedTower = _session.towerAt(tower.position);
  final component = _towerComponents[tower.id];
  if (specializedTower != null && component != null) {
    component.updateTower(specializedTower);
    _selectedTower = specializedTower;
  }
  _publishSnapshot();
}

String _specializationMessage(
  PlacedTower tower,
  TowerSpecialization specialization,
) {
  if (_session.phase != GamePhase.build) {
    return 'Specialize towers between waves.';
  }
  if (specialization.type != tower.type) {
    return 'That specialization belongs to another tower.';
  }
  if (!tower.canSpecialize) {
    return 'Upgrade this tower before specializing.';
  }
  return 'Not enough gold to specialize that tower.';
}
```

- [ ] **Step 5: Render progressive tower picker**

In `_TowerPicker`, replace the hard-coded three buttons with:

```dart
final unlockedTypes = TowerType.values
    .where((type) => unlockedTowerTypes.contains(type))
    .toList(growable: false);

Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final type in unlockedTypes)
      _TowerButton(
        label: _towerLabel(type),
        icon: _towerIcon(type),
        stats: GameBalance.towerStats(type, level: 1),
        phase: phase,
        gold: gold,
        onPressed: () => game.placeTower(type),
      ),
  ],
)
```

Add `unlockedTowerTypes` to `_TowerPicker` constructor and pass `snapshot.unlockedTowerTypes` from `_BottomControls`.

Add icon helper:

```dart
IconData _towerIcon(TowerType type) {
  return switch (type) {
    TowerType.laser => Icons.bolt,
    TowerType.rocket => Icons.rocket_launch,
    TowerType.cryo => Icons.ac_unit,
    TowerType.railgun => Icons.linear_scale,
    TowerType.ionChain => Icons.electrical_services,
    TowerType.nanite => Icons.bubble_chart,
    TowerType.gravityWell => Icons.blur_circular,
    TowerType.droneBay => Icons.hub,
  };
}
```

Update `_towerLabel`:

```dart
String _towerLabel(TowerType type) {
  return switch (type) {
    TowerType.laser => 'Laser',
    TowerType.rocket => 'Rocket',
    TowerType.cryo => 'Cryo',
    TowerType.railgun => 'Railgun',
    TowerType.ionChain => 'Ion Chain',
    TowerType.nanite => 'Nanite',
    TowerType.gravityWell => 'Gravity Well',
    TowerType.droneBay => 'Drone Bay',
  };
}
```

- [ ] **Step 6: Render specialization buttons**

In `_UpgradePanel`, replace the single button section with:

```dart
if (tower.canUpgrade)
  FilledButton.icon(
    onPressed: canUpgrade ? game.upgradeSelectedTower : null,
    icon: const Icon(Icons.upgrade),
    label: Text('Upgrade ${stats.upgradeCost}'),
  )
else if (tower.canSpecialize)
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final specialization in GameBalance.specializationsFor(tower.type))
        FilledButton.tonalIcon(
          onPressed: snapshot.phase == GamePhase.build &&
                  snapshot.gold >= stats.specializationCost
              ? () => game.specializeSelectedTower(specialization)
              : null,
          icon: const Icon(Icons.call_split),
          label: Text('${specialization.label} ${stats.specializationCost}'),
        ),
    ],
  )
else
  const FilledButton.icon(
    onPressed: null,
    icon: Icon(Icons.check),
    label: Text('Max'),
  )
```

Update the tower detail text to show specialization:

```dart
Text(
  tower.specialization == null
      ? 'Level ${tower.level}'
      : 'Level ${tower.level} • ${tower.specialization!.label}',
),
```

- [ ] **Step 7: Run UI tests**

Run:

```bash
dart format lib/game/models/game_models.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart test/widget_test.dart
flutter test test/widget_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 8: Commit UI changes**

```bash
git add lib/game/models/game_models.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: expose tower unlocks and specializations in UI"
```

## Task 9: Final Verification And Web Smoke

**Files:**
- Modify only files required by failures found in verification.

- [ ] **Step 1: Run formatter**

Run:

```bash
dart format lib test
```

Expected: formatter completes without errors.

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run full tests**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Launch web server**

Run:

```bash
flutter run -d web-server --web-port 5174
```

Expected: server starts and prints a local URL. Keep the process running for the smoke check.

- [ ] **Step 5: Smoke-test the page manually**

Open the printed URL in a browser and verify:

- HUD shows `Gold 150`, `Base 20`, and `Wave 1/8`.
- Initial tower picker shows Laser, Rocket, and Cryo only after selecting a buildable cell.
- A wave starts from the Start Wave button.
- After clearing wave 1, Railgun appears in the tower picker.
- A new tower can be placed on a buildable off-path cell.
- A level 2 tower shows two specialization buttons.
- Selecting a specialization updates the panel to maxed state.
- Waves can progress into waves 6 through 8 without asset-load errors.

- [ ] **Step 6: Stop the web server**

Stop the `flutter run` session with `Ctrl-C`.

Expected: terminal returns to the shell prompt.

- [ ] **Step 7: Check git state**

Run:

```bash
git status --short
```

Expected: either clean, or only intentional verification fixes are listed.

- [ ] **Step 8: Finish verification**

If Step 7 is clean, no verification commit is needed. If Step 7 lists changed files, return to the task that owns those files, make the focused correction there, rerun Steps 1 through 7, and commit that correction with the owning task's commit message pattern.
