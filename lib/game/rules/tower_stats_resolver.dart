import '../campaign/campaign_progress.dart';
import '../models/game_models.dart';
import 'run_module_rules.dart';
import 'stage_modifier_rules.dart';

/// Resolves a tower's runtime [TowerStats] from [GameBalance], then applies
/// the stage environmental modifiers via [StageModifierRules.effectiveTowerStats],
/// then applies run modules. Pure: identical inputs yield identical outputs.
///
/// Pipeline order for new character-aware calls: base style/tier → character
/// rank+level damage-channel scaling → stage → run modules. The optional
/// [character]/[characterLevel] pair is the temporary Task-1 bridge: Task 3
/// moves both onto [PlacedTower] and makes this path the only one. The legacy
/// laser/cryo tech-tree combat upgrades still apply to pre-character calls
/// (filtered by tower type) until Task 2 removes them; character-aware calls
/// already follow the final pipeline and skip that step entirely.
class TowerStatsResolver {
  static TowerStats resolve(
    PlacedTower tower, {
    Character? character,
    int characterLevel = 1,
    CampaignModifiers campaignModifiers = CampaignModifiers.empty,
    Iterable<StageModifier> stageModifiers = const [],
    Iterable<RunModuleId> runModules = const [],
  }) {
    assert(
      character == null || character.style == tower.type,
      'character combat style must match tower type',
    );
    assert(
      character == null ||
          tower.specialization == null ||
          tower.specialization == character.signature,
      'character signature must match tower specialization',
    );

    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    var adjusted = base;
    if (character != null) {
      adjusted = base.scaleDamageChannels(
        GameBalance.characterScalingFactor(character.rank, characterLevel),
      );
    } else if (tower.type == TowerType.laser &&
        campaignModifiers.laserDamageFraction > 0) {
      adjusted = base.copyWith(
        damage: base.damage * (1 + campaignModifiers.laserDamageFraction),
      );
    } else if (tower.type == TowerType.cryo &&
        campaignModifiers.cryoSlowDurationBonus > 0) {
      adjusted = base.copyWith(
        slowDuration:
            base.slowDuration + campaignModifiers.cryoSlowDurationBonus,
      );
    }
    final stageAdjusted = StageModifierRules.effectiveTowerStats(
      resolvedStats: adjusted,
      stageModifiers: stageModifiers,
    );
    return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
  }
}
