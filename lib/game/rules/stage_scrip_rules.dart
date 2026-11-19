import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';
import '../models/game_models.dart';

/// Pure Scrip payout rules (HPA-923): a successful mission clear pays the
/// stage's medal-scaled replay base plus, once, its first-clear bonus. No
/// wallet mutation and no stage-id registry — the award reads only the
/// stage's own Scrip fields.
abstract final class StageScripRules {
  /// Scrip earned by a mission victory on [stage] at [medal]:
  /// `(firstClear ? stage.firstClearScrip : 0) +
  /// floor(stage.replayScrip × medalPercent / 100)`.
  /// Always nonnegative; [firstClear] is the launch-time flag captured by
  /// the caller, never re-derived here from saved bests.
  static int award(
    StageDefinition stage,
    StageMedal medal, {
    required bool firstClear,
  }) {
    final medalPercent = switch (medal) {
      StageMedal.clear => GameBalance.scripMedalPercentClear,
      StageMedal.silver => GameBalance.scripMedalPercentSilver,
      StageMedal.gold => GameBalance.scripMedalPercentGold,
    };
    final total =
        (firstClear ? stage.firstClearScrip : 0) +
        stage.replayScrip * medalPercent ~/ 100;
    return total < 0 ? 0 : total;
  }
}
