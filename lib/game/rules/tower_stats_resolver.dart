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
/// moves both onto [PlacedTower] and makes this path the only one.
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
    }
    final stageAdjusted = StageModifierRules.effectiveTowerStats(
      resolvedStats: adjusted,
      stageModifiers: stageModifiers,
    );
    return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
  }
}
