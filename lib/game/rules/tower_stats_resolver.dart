import '../campaign/campaign_progress.dart';
import '../models/game_models.dart';
import 'run_module_rules.dart';
import 'stage_modifier_rules.dart';

/// Resolves a tower's runtime [TowerStats] from [GameBalance], then applies
/// the laser/cryo tech-tree combat upgrades, then applies the stage
/// environmental modifiers via [StageModifierRules.effectiveTowerStats].
/// Pipeline order: base → campaign → stage → run modules. Pure: identical
/// inputs yield identical outputs. The laser/cryo branches are filtered by
/// tower type so a non-matching tower is unaffected.
class TowerStatsResolver {
  static TowerStats resolve(
    PlacedTower tower, {
    CampaignModifiers campaignModifiers = CampaignModifiers.empty,
    Iterable<StageModifier> stageModifiers = const [],
    Iterable<RunModuleId> runModules = const [],
  }) {
    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    var campaignAdjusted = base;
    if (tower.type == TowerType.laser &&
        campaignModifiers.laserDamageFraction > 0) {
      campaignAdjusted = base.copyWith(
        damage: base.damage * (1 + campaignModifiers.laserDamageFraction),
      );
    } else if (tower.type == TowerType.cryo &&
        campaignModifiers.cryoSlowDurationBonus > 0) {
      campaignAdjusted = base.copyWith(
        slowDuration:
            base.slowDuration + campaignModifiers.cryoSlowDurationBonus,
      );
    }
    final stageAdjusted = StageModifierRules.effectiveTowerStats(
      resolvedStats: campaignAdjusted,
      stageModifiers: stageModifiers,
    );
    return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
  }
}
