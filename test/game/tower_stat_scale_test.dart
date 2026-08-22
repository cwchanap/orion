import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';

void main() {
  test('every tower scale matches the pinned tuning maxima', () {
    // Independent expected values, pinned to the GameBalance tables rather
    // than recomputing _build's reduce(max) formulas: damage is the highest
    // damage across level 1, level 2, and both level-3 specializations,
    // shotsPerSecond is 1 / the fastest fire interval, range is the longest
    // range, and secondary is the strongest secondary stat.
    const expected =
        <
          TowerType,
          ({
            double damage,
            double shotsPerSecond,
            double range,
            double? secondary,
          })
        >{
          TowerType.laser: (
            damage: 20,
            shotsPerSecond: 25 / 6,
            range: 170,
            secondary: null,
          ),
          TowerType.rocket: (
            damage: 54,
            shotsPerSecond: 1,
            range: 190,
            secondary: 96,
          ),
          TowerType.cryo: (
            damage: 14,
            shotsPerSecond: 1.470588,
            range: 160,
            secondary: 2.8,
          ),
          TowerType.railgun: (
            damage: 70,
            shotsPerSecond: 0.8,
            range: 255,
            secondary: null,
          ),
          TowerType.ionChain: (
            damage: 24,
            shotsPerSecond: 1.282051,
            range: 175,
            secondary: null,
          ),
          TowerType.nanite: (
            damage: 9,
            shotsPerSecond: 1.315789,
            range: 165,
            secondary: 11,
          ),
          TowerType.gravityWell: (
            damage: 14,
            shotsPerSecond: 0.952381,
            range: 185,
            secondary: null,
          ),
          TowerType.droneBay: (
            damage: 0,
            shotsPerSecond: 0.487805,
            range: 175,
            secondary: 18,
          ),
        };

    for (final type in TowerType.values) {
      final scale = TowerStatScale.forType(type);
      final values = expected[type]!;
      expect(
        scale.damageMax,
        closeTo(values.damage, 1e-6),
        reason: '${type.name} damage',
      );
      expect(
        scale.shotsPerSecondMax,
        closeTo(values.shotsPerSecond, 1e-6),
        reason: '${type.name} shots per second',
      );
      expect(
        scale.rangeMax,
        closeTo(values.range, 1e-6),
        reason: '${type.name} range',
      );
      expect(
        scale.secondaryMax,
        values.secondary == null ? isNull : closeTo(values.secondary!, 1e-6),
        reason: '${type.name} secondary',
      );
    }
  });

  test('resolved modifier values clamp without entering the denominator', () {
    final base = GameBalance.towerStats(TowerType.laser, level: 1);
    final scale = TowerStatScale.forType(TowerType.laser);
    final boosted = base.copyWith(
      damage: scale.damageMax * 2,
      range: scale.rangeMax * 2,
      fireInterval: 1 / (scale.shotsPerSecondMax * 2),
    );

    expect(scale.damageFill(boosted), 1);
    expect(scale.fireFill(boosted), 1);
    expect(scale.rangeFill(boosted), 1);
  });

  test('secondary metrics resolve to their corresponding stat', () {
    final cryo = GameBalance.towerStats(TowerType.cryo, level: 1);
    final rocket = GameBalance.towerStats(TowerType.rocket, level: 1);
    final nanite = GameBalance.towerStats(TowerType.nanite, level: 1);
    final droneBay = GameBalance.towerStats(TowerType.droneBay, level: 1);

    expect(
      TowerStatScale.forType(TowerType.cryo).secondaryMetric!.valueOf(cryo),
      cryo.slowDuration,
    );
    expect(
      TowerStatScale.forType(TowerType.rocket).secondaryMetric!.valueOf(rocket),
      rocket.splashRadius,
    );
    expect(
      TowerStatScale.forType(TowerType.nanite).secondaryMetric!.valueOf(nanite),
      nanite.corrosionDamagePerSecond,
    );
    expect(
      TowerStatScale.forType(
        TowerType.droneBay,
      ).secondaryMetric!.valueOf(droneBay),
      droneBay.droneDamage,
    );
  });
}
