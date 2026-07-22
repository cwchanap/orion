import '../campaign/campaign_progress.dart';
import '../models/game_models.dart';

/// Resolves a tower's runtime [TowerStats] from [GameBalance], then applies
/// the laser/cryo tech-tree combat upgrades. Pure: identical inputs yield
/// identical outputs. The laser/cryo branches are filtered by tower type so
/// a non-matching tower is unaffected.
class TowerStatsResolver {
  static TowerStats resolve(PlacedTower tower, CampaignModifiers modifiers) {
    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    if (tower.type == TowerType.laser && modifiers.laserDamageFraction > 0) {
      return base.copyWith(
        damage: base.damage * (1 + modifiers.laserDamageFraction),
      );
    }
    if (tower.type == TowerType.cryo && modifiers.cryoSlowDurationBonus > 0) {
      return base.copyWith(
        slowDuration: base.slowDuration + modifiers.cryoSlowDurationBonus,
      );
    }
    return base;
  }
}
