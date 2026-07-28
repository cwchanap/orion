import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/tower_stats_resolver.dart';

void main() {
  // Use the simplest possible PlacedTower fixtures. The resolver only reads
  // tower.type / level / specialization, so position is irrelevant.
  PlacedTower tower(TowerType type) =>
      PlacedTower(id: 1, type: type, position: const GridPosition(0, 0));

  group('TowerStatsResolver.resolve', () {
    test('laser damage multiplied by (1 + laserDamageFraction)', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final stats = TowerStatsResolver.resolve(
        tower(TowerType.laser),
        campaignModifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(stats.damage, closeTo(base.damage * 1.10, 1e-9));
    });

    test('laser damage unchanged when laserDamageFraction is 0', () {
      final stats = TowerStatsResolver.resolve(
        tower(TowerType.laser),
        campaignModifiers: CampaignModifiers.empty,
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(stats.damage, base.damage);
    });

    test('cryo slowDuration extended by cryoSlowDurationBonus', () {
      const mods = CampaignModifiers(cryoSlowDurationBonus: 0.30);
      final stats = TowerStatsResolver.resolve(
        tower(TowerType.cryo),
        campaignModifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.cryo, level: 1);
      expect(stats.slowDuration, closeTo(base.slowDuration + 0.30, 1e-9));
    });

    test('non-laser, non-cryo tower is unaffected by both combat upgrades', () {
      const mods = CampaignModifiers(
        laserDamageFraction: 0.10,
        cryoSlowDurationBonus: 0.30,
      );
      final stats = TowerStatsResolver.resolve(
        tower(TowerType.rocket),
        campaignModifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.rocket, level: 1);
      expect(stats.damage, base.damage);
      expect(stats.slowDuration, base.slowDuration);
    });

    test('re-applies multiplier on upgraded laser', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final upgraded = tower(TowerType.laser).upgraded();
      final stats = TowerStatsResolver.resolve(
        upgraded,
        campaignModifiers: mods,
      );
      final baseL2 = GameBalance.towerStats(TowerType.laser, level: 2);
      expect(stats.damage, closeTo(baseL2.damage * 1.10, 1e-9));
    });

    test('re-applies multiplier on specialized cryo', () {
      const mods = CampaignModifiers(cryoSlowDurationBonus: 0.30);
      // Upgrade to L2, then specialize.
      final specialized = tower(
        TowerType.cryo,
      ).upgraded().specialized(TowerSpecialization.deepFreeze);
      final stats = TowerStatsResolver.resolve(
        specialized,
        campaignModifiers: mods,
      );
      final baseL3DeepFreeze = GameBalance.towerStats(
        TowerType.cryo,
        level: 3,
        specialization: TowerSpecialization.deepFreeze,
      );
      expect(
        stats.slowDuration,
        closeTo(baseL3DeepFreeze.slowDuration + 0.30, 1e-9),
      );
    });

    test(
      'amplifies Gravity Well radius and duration after base resolution',
      () {
        const tower = PlacedTower(
          id: 1,
          type: TowerType.gravityWell,
          position: GridPosition(0, 0),
        );
        final base = GameBalance.towerStats(TowerType.gravityWell, level: 1);

        final resolved = TowerStatsResolver.resolve(
          tower,
          stageModifiers: const [StageModifier.amplifiedGravityWells],
        );

        expect(resolved.fieldRadius, closeTo(base.fieldRadius * 1.20, 0.001));
        expect(
          resolved.fieldDuration,
          closeTo(base.fieldDuration * 1.25, 0.001),
        );
        expect(resolved.damage, base.damage);
        expect(resolved.range, base.range);
      },
    );

    test('amplified wells leave every other tower type unchanged', () {
      for (final type in TowerType.values.where(
        (type) => type != TowerType.gravityWell,
      )) {
        final tower = PlacedTower(
          id: type.index,
          type: type,
          position: const GridPosition(0, 0),
        );
        final base = GameBalance.towerStats(type, level: 1);
        final resolved = TowerStatsResolver.resolve(
          tower,
          stageModifiers: const [StageModifier.amplifiedGravityWells],
        );

        expect(resolved.fieldRadius, base.fieldRadius);
        expect(resolved.fieldDuration, base.fieldDuration);
        expect(resolved.damage, base.damage);
        expect(resolved.range, base.range);
      }
    });
  });
}
