import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameBalance', () {
    test('matches the approved starting economy and base health', () {
      expect(GameBalance.startingGold, 150);
      expect(GameBalance.initialBaseHealth, 20);
    });

    test('defines tower order and unlock waves', () {
      expect(TowerType.values, [
        TowerType.laser,
        TowerType.rocket,
        TowerType.cryo,
        TowerType.railgun,
        TowerType.ionChain,
        TowerType.nanite,
        TowerType.gravityWell,
        TowerType.droneBay,
      ]);

      const expectedUnlockWaves = {
        TowerType.laser: 1,
        TowerType.rocket: 1,
        TowerType.cryo: 1,
        TowerType.railgun: 2,
        TowerType.ionChain: 3,
        TowerType.nanite: 4,
        TowerType.gravityWell: 5,
        TowerType.droneBay: 6,
      };

      for (final entry in expectedUnlockWaves.entries) {
        expect(GameBalance.towerUnlockWave(entry.key), entry.value);
      }
    });

    test('defines two labeled specializations for each tower', () {
      const expectedSpecializations = {
        TowerType.laser: [
          TowerSpecialization.pulseLaser,
          TowerSpecialization.prismLaser,
        ],
        TowerType.rocket: [
          TowerSpecialization.siegeRocket,
          TowerSpecialization.clusterRocket,
        ],
        TowerType.cryo: [
          TowerSpecialization.deepFreeze,
          TowerSpecialization.frostbite,
        ],
        TowerType.railgun: [
          TowerSpecialization.lanceRailgun,
          TowerSpecialization.magneticRailgun,
        ],
        TowerType.ionChain: [
          TowerSpecialization.stormRelay,
          TowerSpecialization.overloadRelay,
        ],
        TowerType.nanite: [
          TowerSpecialization.dissolverNanites,
          TowerSpecialization.replicatorNanites,
        ],
        TowerType.gravityWell: [
          TowerSpecialization.singularityWell,
          TowerSpecialization.crushWell,
        ],
        TowerType.droneBay: [
          TowerSpecialization.interceptorBay,
          TowerSpecialization.hunterBay,
        ],
      };

      for (final entry in expectedSpecializations.entries) {
        final specializations = GameBalance.specializationsFor(entry.key);

        expect(specializations, entry.value);
        expect(specializations, hasLength(2));
        for (final specialization in specializations) {
          expect(specialization.type, entry.key);
          expect(specialization.label, isNotEmpty);
        }
      }
    });

    test('defines the approved tower specialization labels', () {
      const expectedLabels = {
        TowerSpecialization.pulseLaser: 'Pulse Laser',
        TowerSpecialization.prismLaser: 'Prism Laser',
        TowerSpecialization.siegeRocket: 'Siege Rocket',
        TowerSpecialization.clusterRocket: 'Cluster Rocket',
        TowerSpecialization.deepFreeze: 'Deep Freeze',
        TowerSpecialization.frostbite: 'Frostbite',
        TowerSpecialization.lanceRailgun: 'Lance Railgun',
        TowerSpecialization.magneticRailgun: 'Magnetic Railgun',
        TowerSpecialization.stormRelay: 'Storm Relay',
        TowerSpecialization.overloadRelay: 'Overload Relay',
        TowerSpecialization.dissolverNanites: 'Dissolver Nanites',
        TowerSpecialization.replicatorNanites: 'Replicator Nanites',
        TowerSpecialization.singularityWell: 'Singularity Well',
        TowerSpecialization.crushWell: 'Crush Well',
        TowerSpecialization.interceptorBay: 'Interceptor Bay',
        TowerSpecialization.hunterBay: 'Hunter Bay',
      };

      expect(TowerSpecialization.values, expectedLabels.keys.toList());
      for (final entry in expectedLabels.entries) {
        expect(entry.key.label, entry.value);
      }
    });

    test(
      'defines starter cost, upgrade, and specialization cost per tower',
      () {
        const expectedCosts = {
          TowerType.laser: _ExpectedTowerCosts(
            cost: 50,
            upgradeCost: 70,
            specializationCost: 120,
          ),
          TowerType.rocket: _ExpectedTowerCosts(
            cost: 80,
            upgradeCost: 100,
            specializationCost: 150,
          ),
          TowerType.cryo: _ExpectedTowerCosts(
            cost: 70,
            upgradeCost: 90,
            specializationCost: 140,
          ),
          TowerType.railgun: _ExpectedTowerCosts(
            cost: 110,
            upgradeCost: 150,
            specializationCost: 210,
          ),
          TowerType.ionChain: _ExpectedTowerCosts(
            cost: 95,
            upgradeCost: 130,
            specializationCost: 190,
          ),
          TowerType.nanite: _ExpectedTowerCosts(
            cost: 90,
            upgradeCost: 125,
            specializationCost: 180,
          ),
          TowerType.gravityWell: _ExpectedTowerCosts(
            cost: 120,
            upgradeCost: 160,
            specializationCost: 220,
          ),
          TowerType.droneBay: _ExpectedTowerCosts(
            cost: 130,
            upgradeCost: 170,
            specializationCost: 240,
          ),
        };

        for (final entry in expectedCosts.entries) {
          final stats = GameBalance.towerStats(entry.key, level: 1);

          expect(stats.cost, entry.value.cost);
          expect(stats.upgradeCost, entry.value.upgradeCost);
          expect(stats.specializationCost, entry.value.specializationCost);
        }
      },
    );

    test('defines tower level progression flags', () {
      for (final type in TowerType.values) {
        final levelOneStats = GameBalance.towerStats(type, level: 1);
        final levelTwoStats = GameBalance.towerStats(type, level: 2);
        final specialization = GameBalance.specializationsFor(type).first;
        final specializedStats = GameBalance.towerStats(
          type,
          level: 3,
          specialization: specialization,
        );

        expect(levelOneStats.canUpgrade, isTrue);
        expect(levelOneStats.canSpecialize, isFalse);
        expect(levelOneStats.isMaxLevel, isFalse);
        expect(levelTwoStats.canUpgrade, isFalse);
        expect(levelTwoStats.canSpecialize, isTrue);
        expect(levelTwoStats.isMaxLevel, isFalse);
        expect(specializedStats.canUpgrade, isFalse);
        expect(specializedStats.canSpecialize, isFalse);
        expect(specializedStats.isMaxLevel, isTrue);
        expect(specializedStats.specialization, specialization);
      }
    });

    test('defines the approved tower stat values', () {
      const expectedStats = [
        _ExpectedTowerStats(
          type: TowerType.laser,
          level: 1,
          range: 145,
          damage: 12,
          fireInterval: 0.42,
          projectileSpeed: 420,
        ),
        _ExpectedTowerStats(
          type: TowerType.laser,
          level: 2,
          range: 160,
          damage: 18,
          fireInterval: 0.34,
          projectileSpeed: 460,
        ),
        _ExpectedTowerStats(
          type: TowerType.laser,
          level: 3,
          specialization: TowerSpecialization.pulseLaser,
          range: 165,
          damage: 18,
          fireInterval: 0.24,
          projectileSpeed: 480,
        ),
        _ExpectedTowerStats(
          type: TowerType.laser,
          level: 3,
          specialization: TowerSpecialization.prismLaser,
          range: 170,
          damage: 20,
          fireInterval: 0.34,
          projectileSpeed: 470,
          prismSplitDamageMultiplier: 0.35,
          prismSplitRange: 55,
        ),
        _ExpectedTowerStats(
          type: TowerType.rocket,
          level: 1,
          range: 165,
          damage: 26,
          fireInterval: 1.15,
          projectileSpeed: 300,
          splashRadius: 58,
        ),
        _ExpectedTowerStats(
          type: TowerType.rocket,
          level: 2,
          range: 180,
          damage: 40,
          fireInterval: 1.00,
          projectileSpeed: 330,
          splashRadius: 72,
        ),
        _ExpectedTowerStats(
          type: TowerType.rocket,
          level: 3,
          specialization: TowerSpecialization.siegeRocket,
          range: 190,
          damage: 54,
          fireInterval: 1.05,
          projectileSpeed: 330,
          splashRadius: 96,
        ),
        _ExpectedTowerStats(
          type: TowerType.rocket,
          level: 3,
          specialization: TowerSpecialization.clusterRocket,
          range: 180,
          damage: 42,
          fireInterval: 1.00,
          projectileSpeed: 340,
          splashRadius: 72,
          clusterBurstCount: 2,
          clusterBurstDamageMultiplier: 0.45,
          clusterBurstRadius: 42,
        ),
        _ExpectedTowerStats(
          type: TowerType.cryo,
          level: 1,
          range: 135,
          damage: 5,
          fireInterval: 0.85,
          projectileSpeed: 360,
          slowMultiplier: 0.62,
          slowDuration: 1.4,
        ),
        _ExpectedTowerStats(
          type: TowerType.cryo,
          level: 2,
          range: 150,
          damage: 8,
          fireInterval: 0.72,
          projectileSpeed: 390,
          slowMultiplier: 0.48,
          slowDuration: 2.0,
        ),
        _ExpectedTowerStats(
          type: TowerType.cryo,
          level: 3,
          specialization: TowerSpecialization.deepFreeze,
          range: 160,
          damage: 8,
          fireInterval: 0.70,
          projectileSpeed: 400,
          slowMultiplier: 0.38,
          slowDuration: 2.8,
        ),
        _ExpectedTowerStats(
          type: TowerType.cryo,
          level: 3,
          specialization: TowerSpecialization.frostbite,
          range: 155,
          damage: 14,
          fireInterval: 0.68,
          projectileSpeed: 410,
          slowMultiplier: 0.50,
          slowDuration: 1.8,
          slowedDamageMultiplier: 1.6,
        ),
        _ExpectedTowerStats(
          type: TowerType.railgun,
          level: 1,
          range: 210,
          damage: 42,
          fireInterval: 1.45,
          projectileSpeed: 620,
          pierceCount: 2,
          pierceWidth: 22,
        ),
        _ExpectedTowerStats(
          type: TowerType.railgun,
          level: 2,
          range: 230,
          damage: 62,
          fireInterval: 1.30,
          projectileSpeed: 680,
          pierceCount: 3,
          pierceWidth: 24,
        ),
        _ExpectedTowerStats(
          type: TowerType.railgun,
          level: 3,
          specialization: TowerSpecialization.lanceRailgun,
          range: 255,
          damage: 70,
          fireInterval: 1.25,
          projectileSpeed: 720,
          pierceCount: 5,
          pierceWidth: 28,
        ),
        _ExpectedTowerStats(
          type: TowerType.railgun,
          level: 3,
          specialization: TowerSpecialization.magneticRailgun,
          range: 235,
          damage: 68,
          fireInterval: 1.28,
          projectileSpeed: 700,
          pierceCount: 3,
          pierceWidth: 24,
          armorDamageMultiplier: 1.55,
        ),
        _ExpectedTowerStats(
          type: TowerType.ionChain,
          level: 1,
          range: 150,
          damage: 16,
          fireInterval: 0.95,
          projectileSpeed: 500,
          chainCount: 3,
          chainRange: 85,
          chainFalloff: 0.72,
        ),
        _ExpectedTowerStats(
          type: TowerType.ionChain,
          level: 2,
          range: 165,
          damage: 22,
          fireInterval: 0.82,
          projectileSpeed: 540,
          chainCount: 4,
          chainRange: 95,
          chainFalloff: 0.76,
        ),
        _ExpectedTowerStats(
          type: TowerType.ionChain,
          level: 3,
          specialization: TowerSpecialization.stormRelay,
          range: 175,
          damage: 24,
          fireInterval: 0.78,
          projectileSpeed: 560,
          chainCount: 6,
          chainRange: 110,
          chainFalloff: 0.78,
        ),
        _ExpectedTowerStats(
          type: TowerType.ionChain,
          level: 3,
          specialization: TowerSpecialization.overloadRelay,
          range: 168,
          damage: 24,
          fireInterval: 0.82,
          projectileSpeed: 550,
          chainCount: 4,
          chainRange: 100,
          chainFalloff: 0.76,
          shieldDamageMultiplier: 1.65,
        ),
        _ExpectedTowerStats(
          type: TowerType.nanite,
          level: 1,
          range: 140,
          damage: 6,
          fireInterval: 0.90,
          projectileSpeed: 360,
          corrosionDamagePerSecond: 6,
          corrosionDuration: 2.5,
          armorShred: 0.12,
        ),
        _ExpectedTowerStats(
          type: TowerType.nanite,
          level: 2,
          range: 155,
          damage: 8,
          fireInterval: 0.80,
          projectileSpeed: 390,
          corrosionDamagePerSecond: 9,
          corrosionDuration: 3.2,
          armorShred: 0.18,
        ),
        _ExpectedTowerStats(
          type: TowerType.nanite,
          level: 3,
          specialization: TowerSpecialization.dissolverNanites,
          range: 165,
          damage: 9,
          fireInterval: 0.78,
          projectileSpeed: 400,
          corrosionDamagePerSecond: 11,
          corrosionDuration: 3.6,
          armorShred: 0.32,
        ),
        _ExpectedTowerStats(
          type: TowerType.nanite,
          level: 3,
          specialization: TowerSpecialization.replicatorNanites,
          range: 160,
          damage: 8,
          fireInterval: 0.76,
          projectileSpeed: 410,
          corrosionDamagePerSecond: 10,
          corrosionDuration: 3.2,
          armorShred: 0.20,
        ),
        _ExpectedTowerStats(
          type: TowerType.gravityWell,
          level: 1,
          range: 155,
          damage: 4,
          fireInterval: 1.25,
          projectileSpeed: 300,
          fieldRadius: 72,
          fieldDuration: 2.0,
          fieldTickInterval: 0.5,
        ),
        _ExpectedTowerStats(
          type: TowerType.gravityWell,
          level: 2,
          range: 170,
          damage: 6,
          fireInterval: 1.12,
          projectileSpeed: 320,
          fieldRadius: 86,
          fieldDuration: 2.5,
          fieldTickInterval: 0.5,
        ),
        _ExpectedTowerStats(
          type: TowerType.gravityWell,
          level: 3,
          specialization: TowerSpecialization.singularityWell,
          range: 185,
          damage: 6,
          fireInterval: 1.05,
          projectileSpeed: 330,
          slowMultiplier: 0.42,
          slowDuration: 0.7,
          fieldRadius: 104,
          fieldDuration: 3.1,
          fieldTickInterval: 0.45,
        ),
        _ExpectedTowerStats(
          type: TowerType.gravityWell,
          level: 3,
          specialization: TowerSpecialization.crushWell,
          range: 175,
          damage: 14,
          fireInterval: 1.10,
          projectileSpeed: 330,
          slowMultiplier: 0.55,
          slowDuration: 0.6,
          fieldRadius: 88,
          fieldDuration: 2.8,
          fieldTickInterval: 0.45,
        ),
        _ExpectedTowerStats(
          type: TowerType.droneBay,
          level: 1,
          range: 150,
          damage: 0,
          fireInterval: 2.50,
          projectileSpeed: 0,
          droneCount: 2,
          droneLifetime: 4.0,
          droneDamage: 8,
          droneAttackInterval: 0.65,
          maxActiveDrones: 4,
        ),
        _ExpectedTowerStats(
          type: TowerType.droneBay,
          level: 2,
          range: 165,
          damage: 0,
          fireInterval: 2.25,
          projectileSpeed: 0,
          droneCount: 3,
          droneLifetime: 4.5,
          droneDamage: 10,
          droneAttackInterval: 0.58,
          maxActiveDrones: 6,
        ),
        _ExpectedTowerStats(
          type: TowerType.droneBay,
          level: 3,
          specialization: TowerSpecialization.interceptorBay,
          range: 175,
          damage: 0,
          fireInterval: 2.05,
          projectileSpeed: 0,
          droneCount: 4,
          droneLifetime: 4.0,
          droneDamage: 9,
          droneAttackInterval: 0.50,
          maxActiveDrones: 8,
        ),
        _ExpectedTowerStats(
          type: TowerType.droneBay,
          level: 3,
          specialization: TowerSpecialization.hunterBay,
          range: 175,
          damage: 0,
          fireInterval: 2.30,
          projectileSpeed: 0,
          droneCount: 2,
          droneLifetime: 5.4,
          droneDamage: 18,
          droneAttackInterval: 0.72,
          maxActiveDrones: 4,
        ),
      ];

      for (final expected in expectedStats) {
        final stats = GameBalance.towerStats(
          expected.type,
          level: expected.level,
          specialization: expected.specialization,
        );

        expect(stats.type, expected.type);
        expect(stats.level, expected.level);
        expect(stats.specialization, expected.specialization);
        expect(stats.range, expected.range);
        expect(stats.damage, expected.damage);
        expect(stats.fireInterval, expected.fireInterval);
        expect(stats.projectileSpeed, expected.projectileSpeed);
        expect(stats.splashRadius, expected.splashRadius);
        expect(stats.slowMultiplier, expected.slowMultiplier);
        expect(stats.slowDuration, expected.slowDuration);
        expect(stats.pierceCount, expected.pierceCount);
        expect(stats.pierceWidth, expected.pierceWidth);
        expect(stats.chainCount, expected.chainCount);
        expect(stats.chainRange, expected.chainRange);
        expect(stats.chainFalloff, expected.chainFalloff);
        expect(
          stats.corrosionDamagePerSecond,
          expected.corrosionDamagePerSecond,
        );
        expect(stats.corrosionDuration, expected.corrosionDuration);
        expect(stats.armorShred, expected.armorShred);
        expect(stats.fieldRadius, expected.fieldRadius);
        expect(stats.fieldDuration, expected.fieldDuration);
        expect(stats.fieldTickInterval, expected.fieldTickInterval);
        expect(stats.droneCount, expected.droneCount);
        expect(stats.droneLifetime, expected.droneLifetime);
        expect(stats.droneDamage, expected.droneDamage);
        expect(stats.droneAttackInterval, expected.droneAttackInterval);
        expect(stats.maxActiveDrones, expected.maxActiveDrones);
        expect(stats.shieldDamageMultiplier, expected.shieldDamageMultiplier);
        expect(stats.armorDamageMultiplier, expected.armorDamageMultiplier);
        expect(stats.slowedDamageMultiplier, expected.slowedDamageMultiplier);
        expect(
          stats.prismSplitDamageMultiplier,
          expected.prismSplitDamageMultiplier,
        );
        expect(stats.prismSplitRange, expected.prismSplitRange);
        expect(stats.clusterBurstCount, expected.clusterBurstCount);
        expect(
          stats.clusterBurstDamageMultiplier,
          expected.clusterBurstDamageMultiplier,
        );
        expect(stats.clusterBurstRadius, expected.clusterBurstRadius);
      }
    });

    test('defines the approved enemy archetype table', () {
      const expectedArchetypes = {
        EnemyArchetype.basicDrone: _ExpectedEnemyStats(
          health: 36,
          speed: 74,
          baseDamage: 1,
          goldReward: 8,
        ),
        EnemyArchetype.basicEliteDrone: _ExpectedEnemyStats(
          health: 90,
          speed: 86,
          baseDamage: 1,
          goldReward: 13,
        ),
        EnemyArchetype.armoredDrone: _ExpectedEnemyStats(
          health: 70,
          speed: 66,
          baseDamage: 1,
          goldReward: 12,
          traits: {EnemyTrait.armored},
          armorReduction: 0.30,
        ),
        EnemyArchetype.shieldedDrone: _ExpectedEnemyStats(
          health: 48,
          speed: 78,
          baseDamage: 1,
          goldReward: 12,
          traits: {EnemyTrait.shielded},
          shieldHealth: 35,
        ),
        EnemyArchetype.swarmDrone: _ExpectedEnemyStats(
          health: 22,
          speed: 100,
          baseDamage: 1,
          goldReward: 5,
          traits: {EnemyTrait.swarm},
        ),
        EnemyArchetype.regenDrone: _ExpectedEnemyStats(
          health: 78,
          speed: 72,
          baseDamage: 1,
          goldReward: 14,
          traits: {EnemyTrait.regen},
          regenPerSecond: 2.5,
        ),
        EnemyArchetype.heavyDrone: _ExpectedEnemyStats(
          health: 150,
          speed: 58,
          baseDamage: 2,
          goldReward: 18,
          traits: {EnemyTrait.heavy},
        ),
        EnemyArchetype.armoredHeavyDrone: _ExpectedEnemyStats(
          health: 175,
          speed: 54,
          baseDamage: 2,
          goldReward: 22,
          traits: {EnemyTrait.armored, EnemyTrait.heavy},
          armorReduction: 0.35,
        ),
        EnemyArchetype.regenHeavyDrone: _ExpectedEnemyStats(
          health: 190,
          speed: 54,
          baseDamage: 3,
          goldReward: 25,
          traits: {EnemyTrait.regen, EnemyTrait.heavy},
          regenPerSecond: 3.0,
        ),
      };

      for (final entry in expectedArchetypes.entries) {
        final stats = GameBalance.enemyArchetype(entry.key);

        expect(stats.health, entry.value.health);
        expect(stats.speed, entry.value.speed);
        expect(stats.baseDamage, entry.value.baseDamage);
        expect(stats.goldReward, entry.value.goldReward);
        expect(stats.traits, entry.value.traits);
        expect(stats.shieldHealth, entry.value.shieldHealth);
        expect(stats.armorReduction, entry.value.armorReduction);
        expect(stats.regenPerSecond, entry.value.regenPerSecond);
        for (final trait in EnemyTrait.values) {
          expect(stats.hasTrait(trait), entry.value.traits.contains(trait));
        }
      }
    });

    test(
      'defines eight waves with approved enemy counts and clear bonuses',
      () {
        const expectedWaves = [
          _ExpectedWave(enemyCount: 8, clearBonus: 30),
          _ExpectedWave(enemyCount: 10, clearBonus: 40),
          _ExpectedWave(enemyCount: 14, clearBonus: 50),
          _ExpectedWave(enemyCount: 16, clearBonus: 65),
          _ExpectedWave(enemyCount: 24, clearBonus: 80),
          _ExpectedWave(enemyCount: 22, clearBonus: 95),
          _ExpectedWave(enemyCount: 28, clearBonus: 115),
          _ExpectedWave(enemyCount: 46, clearBonus: 0),
        ];

        expect(GameBalance.waves, hasLength(expectedWaves.length));
        for (final (index, expected) in expectedWaves.indexed) {
          final wave = GameBalance.waves[index];

          expect(wave.enemyCount, expected.enemyCount);
          expect(wave.clearBonus, expected.clearBonus);
        }
      },
    );

    test('defines the approved wave groups and spawn intervals', () {
      const expectedWaves = [
        [_ExpectedWaveGroup(EnemyArchetype.basicDrone, 8, 0.85)],
        [
          _ExpectedWaveGroup(EnemyArchetype.basicDrone, 8, 0.85),
          _ExpectedWaveGroup(EnemyArchetype.armoredDrone, 2, 1.00),
        ],
        [
          _ExpectedWaveGroup(EnemyArchetype.basicDrone, 10, 0.85),
          _ExpectedWaveGroup(EnemyArchetype.shieldedDrone, 4, 0.90),
        ],
        [
          _ExpectedWaveGroup(EnemyArchetype.basicDrone, 8, 0.85),
          _ExpectedWaveGroup(EnemyArchetype.armoredDrone, 4, 1.00),
          _ExpectedWaveGroup(EnemyArchetype.shieldedDrone, 4, 0.90),
        ],
        [
          _ExpectedWaveGroup(EnemyArchetype.swarmDrone, 20, 0.35),
          _ExpectedWaveGroup(EnemyArchetype.heavyDrone, 4, 1.20),
        ],
        [
          _ExpectedWaveGroup(EnemyArchetype.shieldedDrone, 10, 0.90),
          _ExpectedWaveGroup(EnemyArchetype.regenDrone, 6, 1.00),
          _ExpectedWaveGroup(EnemyArchetype.swarmDrone, 6, 0.35),
        ],
        [
          _ExpectedWaveGroup(EnemyArchetype.armoredHeavyDrone, 8, 1.25),
          _ExpectedWaveGroup(EnemyArchetype.shieldedDrone, 8, 0.90),
          _ExpectedWaveGroup(EnemyArchetype.swarmDrone, 12, 0.35),
        ],
        [
          _ExpectedWaveGroup(EnemyArchetype.basicEliteDrone, 8, 0.75),
          _ExpectedWaveGroup(EnemyArchetype.shieldedDrone, 8, 0.90),
          _ExpectedWaveGroup(EnemyArchetype.armoredDrone, 8, 1.00),
          _ExpectedWaveGroup(EnemyArchetype.swarmDrone, 18, 0.35),
          _ExpectedWaveGroup(EnemyArchetype.regenHeavyDrone, 4, 1.30),
        ],
      ];

      expect(GameBalance.waves, hasLength(expectedWaves.length));
      for (final (waveIndex, expectedGroups) in expectedWaves.indexed) {
        final wave = GameBalance.waves[waveIndex];

        expect(wave.groups, hasLength(expectedGroups.length));
        for (final (groupIndex, expectedGroup) in expectedGroups.indexed) {
          final group = wave.groups[groupIndex];
          final enemyStats = GameBalance.enemyArchetype(
            expectedGroup.archetype,
          );

          expect(group.enemyCount, expectedGroup.enemyCount);
          expect(group.enemyStats, enemyStats);
          expect(group.spawnInterval, expectedGroup.spawnInterval);
          expect(group.initialDelay, 0);
        }
      }

      expect(
        GameBalance.waves[7].groups.any(
          (group) => group.enemyStats.hasTrait(EnemyTrait.swarm),
        ),
        isTrue,
      );
    });

    test('builds a preview for a multi-group baseline wave', () {
      final preview = GameBalance.wavePreview(
        wave: GameBalance.waves[4],
        waveNumber: 5,
        waveTotal: 8,
        unlockedTowerTypes: const [
          TowerType.laser,
          TowerType.rocket,
          TowerType.cryo,
          TowerType.railgun,
          TowerType.ionChain,
          TowerType.nanite,
          TowerType.gravityWell,
        ],
      );

      expect(preview.waveNumber, 5);
      expect(preview.waveTotal, 8);
      expect(preview.clearBonus, 80);
      expect(
        preview.groups.map((group) => '${group.enemyCount} ${group.label}'),
        ['20 Swarm Drones', '4 Heavy Drones'],
      );
      expect(preview.traits.toList(), [EnemyTrait.swarm, EnemyTrait.heavy]);
      expect(preview.recommendedTowerTypes, [
        TowerType.rocket,
        TowerType.cryo,
        TowerType.gravityWell,
      ]);
    });

    test('filters wave preview recommendations to unlocked towers', () {
      final preview = GameBalance.wavePreview(
        wave: GameBalance.waves[4],
        waveNumber: 5,
        waveTotal: 8,
        unlockedTowerTypes: const [TowerType.laser, TowerType.rocket],
      );

      expect(preview.recommendedTowerTypes, [TowerType.rocket]);
    });

    test('labels every approved enemy archetype in wave previews', () {
      const expectedLabels = {
        EnemyArchetype.basicDrone: 'Drones',
        EnemyArchetype.basicEliteDrone: 'Elite Drones',
        EnemyArchetype.armoredDrone: 'Armored Drones',
        EnemyArchetype.shieldedDrone: 'Shielded Drones',
        EnemyArchetype.swarmDrone: 'Swarm Drones',
        EnemyArchetype.regenDrone: 'Regen Drones',
        EnemyArchetype.heavyDrone: 'Heavy Drones',
        EnemyArchetype.armoredHeavyDrone: 'Armored Heavy Drones',
        EnemyArchetype.regenHeavyDrone: 'Regen Heavy Drones',
      };

      for (final entry in expectedLabels.entries) {
        final preview = GameBalance.wavePreview(
          wave: WaveDefinition(
            groups: [
              WaveGroup(
                enemyCount: 1,
                enemyStats: GameBalance.enemyArchetype(entry.key),
              ),
            ],
            clearBonus: 0,
          ),
          waveNumber: 1,
          waveTotal: 1,
          unlockedTowerTypes: const [],
        );

        expect(preview.groups.single.label, entry.value);
      }
    });

    test('uses trait fallback labels for custom enemy stats', () {
      final preview = GameBalance.wavePreview(
        wave: const WaveDefinition(
          groups: [
            WaveGroup(
              enemyCount: 3,
              enemyStats: EnemyStats(
                health: 111,
                speed: 42,
                baseDamage: 2,
                goldReward: 9,
                traits: {EnemyTrait.shielded, EnemyTrait.armored},
                shieldHealth: 10,
                armorReduction: 0.1,
              ),
            ),
          ],
          clearBonus: 12,
        ),
        waveNumber: 1,
        waveTotal: 1,
        unlockedTowerTypes: const [],
      );

      expect(preview.groups.single.label, 'Armored Shielded Drones');
      expect(preview.groups.single.traits.toList(), [
        EnemyTrait.armored,
        EnemyTrait.shielded,
      ]);
      expect(preview.traits.toList(), [
        EnemyTrait.armored,
        EnemyTrait.shielded,
      ]);
      expect(preview.recommendedTowerTypes, isEmpty);
    });

    test('builds an empty wave preview without filler text data', () {
      final preview = GameBalance.wavePreview(
        wave: const WaveDefinition(groups: [], clearBonus: 0),
        waveNumber: 1,
        waveTotal: 1,
        unlockedTowerTypes: const [TowerType.laser],
      );

      expect(preview.groups, isEmpty);
      expect(preview.traits, isEmpty);
      expect(preview.clearBonus, 0);
      expect(preview.recommendedTowerTypes, isEmpty);
    });

    test('wave preview collections cannot be mutated', () {
      final preview = GameBalance.wavePreview(
        wave: GameBalance.waves.first,
        waveNumber: 1,
        waveTotal: 8,
        unlockedTowerTypes: const [TowerType.laser],
      );

      expect(
        () => preview.groups.add(
          WavePreviewGroup(enemyCount: 1, label: 'Drones', traits: const {}),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => preview.traits.add(EnemyTrait.heavy),
        throwsUnsupportedError,
      );
      expect(
        () => preview.recommendedTowerTypes.add(TowerType.rocket),
        throwsUnsupportedError,
      );
    });

    test('keeps wave compatibility getters backed by the first group', () {
      final wave = GameBalance.waves[1];
      final firstGroup = wave.groups.first;

      expect(wave.enemyCount, 10);
      expect(wave.enemyStats, firstGroup.enemyStats);
      expect(wave.spawnInterval, firstGroup.spawnInterval);
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
          specialization: TowerSpecialization.siegeRocket,
        ),
        throwsArgumentError,
      );
      expect(
        () => GameBalance.towerStats(
          TowerType.laser,
          level: 1,
          specialization: TowerSpecialization.pulseLaser,
        ),
        throwsArgumentError,
      );
      expect(
        () => GameBalance.towerStats(
          TowerType.laser,
          level: 2,
          specialization: TowerSpecialization.pulseLaser,
        ),
        throwsArgumentError,
      );
    });
  });
}

class _ExpectedTowerCosts {
  const _ExpectedTowerCosts({
    required this.cost,
    required this.upgradeCost,
    required this.specializationCost,
  });

  final int cost;
  final int upgradeCost;
  final int specializationCost;
}

class _ExpectedTowerStats {
  const _ExpectedTowerStats({
    required this.type,
    required this.level,
    this.specialization,
    required this.range,
    required this.damage,
    required this.fireInterval,
    required this.projectileSpeed,
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
  final TowerSpecialization? specialization;
  final double range;
  final double damage;
  final double fireInterval;
  final double projectileSpeed;
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
}

class _ExpectedEnemyStats {
  const _ExpectedEnemyStats({
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
}

class _ExpectedWave {
  const _ExpectedWave({required this.enemyCount, required this.clearBonus});

  final int enemyCount;
  final int clearBonus;
}

class _ExpectedWaveGroup {
  const _ExpectedWaveGroup(this.archetype, this.enemyCount, this.spawnInterval);

  final EnemyArchetype archetype;
  final int enemyCount;
  final double spawnInterval;
}
