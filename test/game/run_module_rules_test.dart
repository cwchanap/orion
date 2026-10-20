import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/run_module_rules.dart';

void main() {
  test(
    'applies universal damage and fire interval modules in catalog order',
    () {
      final laser = GameBalance.towerStats(TowerType.laser, level: 1);
      final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
      final overclock = runModuleDefinition(RunModuleId.overclockRelay);

      final overclocked = RunModuleRules.applyTowerStats(laser, const [
        RunModuleId.overclockRelay,
      ]);
      expect(
        overclocked.fireInterval,
        closeTo(laser.fireInterval * overclock.fireIntervalMultiplier, 1e-9),
      );
      expect(
        overclocked.damage,
        closeTo(laser.damage * overclock.damageMultiplier, 1e-9),
      );

      final composed = RunModuleRules.applyTowerStats(laser, const [
        RunModuleId.heavyCaliber,
        RunModuleId.overclockRelay,
      ]);
      expect(
        composed.damage,
        closeTo(
          laser.damage * heavy.damageMultiplier * overclock.damageMultiplier,
          1e-9,
        ),
      );
      expect(
        composed.fireInterval,
        closeTo(
          laser.fireInterval *
              heavy.fireIntervalMultiplier *
              overclock.fireIntervalMultiplier,
          1e-9,
        ),
      );
    },
  );

  test('applies module damage to corrosion and drone channels', () {
    final heavy = runModuleDefinition(RunModuleId.heavyCaliber);

    final nanite = GameBalance.towerStats(TowerType.nanite, level: 1);
    final heavyNanite = RunModuleRules.applyTowerStats(nanite, const [
      RunModuleId.heavyCaliber,
    ]);
    expect(
      heavyNanite.corrosionDamagePerSecond,
      closeTo(nanite.corrosionDamagePerSecond * heavy.damageMultiplier, 1e-9),
    );

    final drone = GameBalance.towerStats(TowerType.droneBay, level: 1);
    final heavyDrone = RunModuleRules.applyTowerStats(drone, const [
      RunModuleId.heavyCaliber,
    ]);
    expect(heavyDrone.damage, 0);
    expect(
      heavyDrone.droneDamage,
      closeTo(drone.droneDamage * heavy.damageMultiplier, 1e-9),
    );
    expect(
      heavyDrone.fireInterval,
      closeTo(drone.fireInterval * heavy.fireIntervalMultiplier, 1e-9),
    );

    final overclock = runModuleDefinition(RunModuleId.overclockRelay);
    final overclockDrone = RunModuleRules.applyTowerStats(drone, const [
      RunModuleId.overclockRelay,
    ]);
    expect(
      overclockDrone.droneDamage,
      closeTo(drone.droneDamage * overclock.damageMultiplier, 1e-9),
    );
    expect(
      overclockDrone.fireInterval,
      closeTo(drone.fireInterval * overclock.fireIntervalMultiplier, 1e-9),
    );
  });

  test('applies Long Sight range to every tower', () {
    final laser = GameBalance.towerStats(TowerType.laser, level: 1);
    final longSight = runModuleDefinition(RunModuleId.longSight);
    final adjusted = RunModuleRules.applyTowerStats(laser, const [
      RunModuleId.longSight,
    ]);

    expect(
      adjusted.range,
      closeTo(laser.range * longSight.rangeMultiplier, 1e-9),
    );
  });

  test('Relay Calibration reuses range and fire-interval multipliers', () {
    final base = GameBalance.towerStats(TowerType.laser, level: 1);

    final resolved = RunModuleRules.applyTowerStats(base, const [
      RunModuleId.relayCalibration,
    ]);

    expect(resolved.range, closeTo(base.range * 1.08, 0.0001));
    expect(resolved.fireInterval, closeTo(base.fireInterval * 0.92, 0.0001));
    expect(resolved.damage, base.damage);
    expect(resolved.splashRadius, base.splashRadius);
  });

  test('Cryo Reservoir extends slow duration only on Cryo towers', () {
    final cryo = GameBalance.towerStats(TowerType.cryo, level: 1);
    final laser = GameBalance.towerStats(TowerType.laser, level: 1);
    final cryoReservoir = runModuleDefinition(RunModuleId.cryoReservoir);

    final adjustedCryo = RunModuleRules.applyTowerStats(cryo, const [
      RunModuleId.cryoReservoir,
    ]);
    expect(
      adjustedCryo.slowDuration,
      closeTo(cryo.slowDuration + cryoReservoir.slowDurationBonus, 1e-9),
    );

    final unchangedLaser = RunModuleRules.applyTowerStats(laser, const [
      RunModuleId.cryoReservoir,
    ]);
    expect(unchangedLaser.slowDuration, laser.slowDuration);
  });

  test('effectText describes every catalog entry', () {
    for (final id in RunModuleId.values) {
      expect(runModuleDefinition(id).effectText, isNotEmpty);
    }
    expect(
      runModuleDefinition(RunModuleId.overclockRelay).effectText,
      'Attack interval drops 15%; all tower damage drops 8%.',
    );
    expect(
      runModuleDefinition(RunModuleId.longSight).effectText,
      'All towers gain 15% range.',
    );
    expect(
      runModuleDefinition(RunModuleId.rocketFusing).effectText,
      'Rocket splash grows 25%; damage drops 10%.',
    );
    expect(
      runModuleDefinition(RunModuleId.relayArc).effectText,
      'Ion Chain arcs to 1 more target.',
    );
    expect(
      runModuleDefinition(RunModuleId.salvagedDrones).effectText,
      'Drone attacks deal 20% more damage.',
    );
    expect(
      runModuleDefinition(RunModuleId.foundryNanites).effectText,
      'Nanite impact and corrosion damage rise 20%.',
    );
    expect(
      runModuleDefinition(RunModuleId.auroraFocus).effectText,
      'Laser attack interval drops 12%.',
    );
    expect(
      runModuleDefinition(RunModuleId.siegeRounds).effectText,
      'Railgun shots pierce 1 more target.',
    );
    expect(
      runModuleDefinition(RunModuleId.gravityEcho).effectText,
      'Gravity Well field radius grows 15%.',
    );
  });

  test('Rocket Fusing changes splash and damage only on Rocket towers', () {
    final rocket = GameBalance.towerStats(TowerType.rocket, level: 1);
    final laser = GameBalance.towerStats(TowerType.laser, level: 1);
    final rocketFusing = runModuleDefinition(RunModuleId.rocketFusing);

    final adjustedRocket = RunModuleRules.applyTowerStats(rocket, const [
      RunModuleId.rocketFusing,
    ]);
    expect(
      adjustedRocket.splashRadius,
      closeTo(rocket.splashRadius * rocketFusing.splashRadiusMultiplier, 1e-9),
    );
    expect(
      adjustedRocket.damage,
      closeTo(rocket.damage * rocketFusing.damageMultiplier, 1e-9),
    );

    final unchangedLaser = RunModuleRules.applyTowerStats(laser, const [
      RunModuleId.rocketFusing,
    ]);
    expect(unchangedLaser.splashRadius, laser.splashRadius);
    expect(unchangedLaser.damage, laser.damage);
  });
  group('boss blueprint family modules', () {
    // Every stat RunModuleRules can mutate, so "no unrelated stat change" is
    // checked across the full mutation surface of the resolver.
    final statFields = <String, double Function(TowerStats)>{
      'damage': (stats) => stats.damage,
      'fireInterval': (stats) => stats.fireInterval,
      'range': (stats) => stats.range,
      'splashRadius': (stats) => stats.splashRadius,
      'slowDuration': (stats) => stats.slowDuration,
      'corrosionDamagePerSecond': (stats) => stats.corrosionDamagePerSecond,
      'droneDamage': (stats) => stats.droneDamage,
      'chainCount': (stats) => stats.chainCount.toDouble(),
      'pierceCount': (stats) => stats.pierceCount.toDouble(),
      'fieldRadius': (stats) => stats.fieldRadius,
    };

    final familyCases =
        <
          (
            RunModuleId,
            TowerType,
            Map<String, double Function(TowerStats base)>,
          )
        >[
          (
            RunModuleId.relayArc,
            TowerType.ionChain,
            {'chainCount': (base) => (base.chainCount + 1).toDouble()},
          ),
          (
            RunModuleId.salvagedDrones,
            TowerType.droneBay,
            {'droneDamage': (base) => base.droneDamage * 1.20},
          ),
          (
            RunModuleId.foundryNanites,
            TowerType.nanite,
            {
              'damage': (base) => base.damage * 1.20,
              'corrosionDamagePerSecond': (base) =>
                  base.corrosionDamagePerSecond * 1.20,
            },
          ),
          (
            RunModuleId.auroraFocus,
            TowerType.laser,
            {'fireInterval': (base) => base.fireInterval * 0.88},
          ),
          (
            RunModuleId.siegeRounds,
            TowerType.railgun,
            {'pierceCount': (base) => (base.pierceCount + 1).toDouble()},
          ),
          (
            RunModuleId.gravityEcho,
            TowerType.gravityWell,
            {'fieldRadius': (base) => base.fieldRadius * 1.15},
          ),
        ];

    test('each module changes only its tower family across every level', () {
      for (final (id, towerType, expectedChanges) in familyCases) {
        final definition = runModuleDefinition(id);
        expect(definition.tower, towerType, reason: id.name);

        final progression =
            <({int level, TowerSpecialization? specialization})>[
              (level: 1, specialization: null),
              (level: 2, specialization: null),
              for (final specialization in GameBalance.specializationsFor(
                towerType,
              ))
                (level: 3, specialization: specialization),
            ];

        for (final stage in progression) {
          final reason = '${id.name} ${towerType.name} ${stage.specialization}';
          final base = GameBalance.towerStats(
            towerType,
            level: stage.level,
            specialization: stage.specialization,
          );
          final resolved = RunModuleRules.applyTowerStats(base, [id]);

          for (final entry in statFields.entries) {
            final expected = expectedChanges[entry.key];
            if (expected == null) {
              expect(
                entry.value(resolved),
                entry.value(base),
                reason: '$reason unexpectedly changes ${entry.key}',
              );
            } else {
              expect(
                entry.value(resolved),
                closeTo(expected(base), 1e-9),
                reason: '$reason wrong ${entry.key} delta',
              );
            }
          }
        }
      }
    });

    test('no family module touches any unrelated tower family', () {
      for (final (id, towerType, _) in familyCases) {
        for (final other in TowerType.values.where(
          (type) => type != towerType,
        )) {
          final base = GameBalance.towerStats(other, level: 1);
          final resolved = RunModuleRules.applyTowerStats(base, [id]);
          for (final entry in statFields.entries) {
            expect(
              entry.value(resolved),
              entry.value(base),
              reason: '${id.name} must not change ${other.name}.${entry.key}',
            );
          }
        }
      }
    });
  });

  test('only Emergency Salvage leaves tower stats unchanged', () {
    for (final definition in runModuleCatalog) {
      expect(
        definition.affectsTowerStats,
        definition.id != RunModuleId.emergencySalvage,
        reason: definition.id.name,
      );
    }
  });

  group('beneficiaryCount', () {
    PlacedTower tower(int id, TowerType type) =>
        PlacedTower(id: id, type: type, position: GridPosition(id, 4));

    final towers = [
      tower(1, TowerType.cryo),
      tower(2, TowerType.cryo),
      tower(3, TowerType.laser),
    ];

    int count(RunModuleId id, Iterable<PlacedTower> placed) =>
        RunModuleRules.beneficiaryCount(runModuleDefinition(id), placed);

    test('universal stat modules count every placed tower', () {
      expect(count(RunModuleId.heavyCaliber, towers), 3);
      expect(count(RunModuleId.longSight, towers), 3);
    });

    test('family modules count one matching tower as 1, unrelated as 0', () {
      const familyCases = <(RunModuleId, TowerType)>[
        (RunModuleId.cryoReservoir, TowerType.cryo),
        (RunModuleId.rocketFusing, TowerType.rocket),
        (RunModuleId.relayArc, TowerType.ionChain),
        (RunModuleId.salvagedDrones, TowerType.droneBay),
        (RunModuleId.foundryNanites, TowerType.nanite),
        (RunModuleId.auroraFocus, TowerType.laser),
        (RunModuleId.siegeRounds, TowerType.railgun),
        (RunModuleId.gravityEcho, TowerType.gravityWell),
      ];
      for (final (id, family) in familyCases) {
        expect(runModuleDefinition(id).tower, family, reason: id.name);
        expect(count(id, [tower(1, family)]), 1, reason: id.name);
        final unrelated = TowerType.values.firstWhere((type) => type != family);
        expect(count(id, [tower(2, unrelated)]), 0, reason: id.name);
      }
    });

    test('economy modules affect no towers', () {
      expect(count(RunModuleId.emergencySalvage, towers), 0);
    });

    test('no placed towers means no current beneficiaries', () {
      for (final definition in runModuleCatalog) {
        expect(count(definition.id, const []), 0);
      }
    });
  });
}
