import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';

void main() {
  test(
    'every tower scale covers level 1, level 2, and both specializations',
    () {
      for (final type in TowerType.values) {
        final scale = TowerStatScale.forType(type);
        final candidates = [
          GameBalance.towerStats(type, level: 1),
          GameBalance.towerStats(type, level: 2),
          for (final specialization in GameBalance.specializationsFor(type))
            GameBalance.towerStats(
              type,
              level: 3,
              specialization: specialization,
            ),
        ];

        expect(candidates, hasLength(4), reason: type.name);
        expect(
          scale.damageMax,
          candidates.map((stats) => stats.damage).reduce(max),
          reason: type.name,
        );
        expect(
          scale.shotsPerSecondMax,
          candidates.map((stats) => 1 / stats.fireInterval).reduce(max),
          reason: type.name,
        );
        expect(
          scale.rangeMax,
          candidates.map((stats) => stats.range).reduce(max),
          reason: type.name,
        );

        final expectedSecondary = switch (type) {
          TowerType.cryo =>
            candidates.map((stats) => stats.slowDuration).reduce(max),
          TowerType.rocket =>
            candidates.map((stats) => stats.splashRadius).reduce(max),
          TowerType.nanite =>
            candidates
                .map((stats) => stats.corrosionDamagePerSecond)
                .reduce(max),
          TowerType.droneBay =>
            candidates.map((stats) => stats.droneDamage).reduce(max),
          TowerType.laser ||
          TowerType.railgun ||
          TowerType.ionChain ||
          TowerType.gravityWell => null,
        };
        expect(scale.secondaryMax, expectedSecondary, reason: type.name);
      }
    },
  );

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
