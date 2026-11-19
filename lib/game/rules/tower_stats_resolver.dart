import '../models/game_models.dart';
import 'run_module_rules.dart';
import 'stage_modifier_rules.dart';

/// Resolves a tower's runtime [TowerStats] from [GameBalance], then applies
/// the stage environmental modifiers via [StageModifierRules.effectiveTowerStats],
/// then applies run modules. Pure: identical inputs yield identical outputs.
///
/// Pipeline order (HPA-922): base style/tier stats derived from
/// [PlacedTower.type], [PlacedTower.level] and [PlacedTower.specialization] →
/// character rank + persistent level damage-channel scaling → stage → run
/// modules. Identity always comes from [PlacedTower.character] — there is no
/// external character bridge.
class TowerStatsResolver {
  static TowerStats resolve(
    PlacedTower tower, {
    Iterable<StageModifier> stageModifiers = const [],
    Iterable<RunModuleId> runModules = const [],
  }) {
    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    final characterScaled = base.scaleDamageChannels(
      GameBalance.characterScalingFactor(
        tower.character.rank,
        tower.characterLevel,
      ),
    );
    final stageAdjusted = StageModifierRules.effectiveTowerStats(
      resolvedStats: characterScaled,
      stageModifiers: stageModifiers,
    );
    return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
  }
}
