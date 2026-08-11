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
}
