import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  // Use the simplest possible PlacedTower fixtures. The resolver only reads
  // tower.type / level / specialization, so position is irrelevant.
  PlacedTower tower(TowerType type) =>
      PlacedTower(id: 1, type: type, position: const GridPosition(0, 0));

  group('TowerComponent stats resolution', () {
    test('laser damage multiplied by (1 + laserDamageFraction)', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final component = TowerComponent(
        tower: tower(TowerType.laser),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, _) {},
        modifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
    });

    test('laser damage unchanged when laserDamageFraction is 0', () {
      final component = TowerComponent(
        tower: tower(TowerType.laser),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, _) {},
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(component.stats.damage, base.damage);
    });

    test('cryo slowDuration extended by cryoSlowDurationBonus', () {
      const mods = CampaignModifiers(cryoSlowDurationBonus: 0.30);
      final component = TowerComponent(
        tower: tower(TowerType.cryo),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, _) {},
        modifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.cryo, level: 1);
      expect(
        component.stats.slowDuration,
        closeTo(base.slowDuration + 0.30, 1e-9),
      );
    });

    test('non-laser, non-cryo tower is unaffected by both combat upgrades', () {
      const mods = CampaignModifiers(
        laserDamageFraction: 0.10,
        cryoSlowDurationBonus: 0.30,
      );
      final component = TowerComponent(
        tower: tower(TowerType.rocket),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, _) {},
        modifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.rocket, level: 1);
      expect(component.stats.damage, base.damage);
      expect(component.stats.slowDuration, base.slowDuration);
    });

    test('updateTower re-applies multiplier on upgraded laser', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final component = TowerComponent(
        tower: tower(TowerType.laser),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, _) {},
        modifiers: mods,
      );
      final upgraded = tower(TowerType.laser).upgraded();
      component.updateTower(upgraded);
      final baseL2 = GameBalance.towerStats(TowerType.laser, level: 2);
      expect(component.stats.damage, closeTo(baseL2.damage * 1.10, 1e-9));
    });

    test('updateTower re-applies multiplier on specialized cryo', () {
      const mods = CampaignModifiers(cryoSlowDurationBonus: 0.30);
      final component = TowerComponent(
        tower: tower(TowerType.cryo),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, _) {},
        modifiers: mods,
      );
      // Upgrade to L2, then specialize.
      final upgraded = tower(TowerType.cryo).upgraded();
      component.updateTower(upgraded);
      final specialized = upgraded.specialized(TowerSpecialization.deepFreeze);
      component.updateTower(specialized);
      final baseL3DeepFreeze = GameBalance.towerStats(
        TowerType.cryo,
        level: 3,
        specialization: TowerSpecialization.deepFreeze,
      );
      expect(
        component.stats.slowDuration,
        closeTo(baseL3DeepFreeze.slowDuration + 0.30, 1e-9),
      );
    });
  });
}

Vector2 _zero() => Vector2(0, 0);
