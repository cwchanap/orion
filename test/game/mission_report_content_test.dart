import 'package:flutter_test/flutter_test.dart';

import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import '../support/command_deck_fixtures.dart';

GameSnapshot terminalSnapshot({
  required GamePhase phase,
  int baseHealth = 14,
  int waveNumber = 8,
  List<RunModuleId> modules = const [],
}) {
  return commandDeckSnapshot(
    phase: phase,
    gold: 120,
    baseHealth: baseHealth,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    stageLabel: 'Alpha',
    unlockedTowerTypes: const [TowerType.laser, TowerType.cryo],
    acquiredRunModules: modules,
  );
}

void main() {
  test('projects first clear while saving', () {
    final content = projectVictoryReport(
      snapshot: terminalSnapshot(
        phase: GamePhase.won,
        modules: const [RunModuleId.heavyCaliber],
      ),
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      priorSavedResult: null,
      saveState: MissionSaveState.saving,
    );

    expect(content.outcomeText, 'Silver medal • Base 14/20');
    expect(content.comparison, MissionResultComparison.firstClear);
    expect(content.comparisonText, 'New first-clear result');
    expect(content.saveText, 'Saving result…');
    expect(
      content.nextOpportunityText,
      'Saving must finish before you replay or leave.',
    );
    expect(content.moduleIds, [RunModuleId.heavyCaliber]);
    expect(content.emptyModulesText, isNull);
  });

  test('projects medal improvement from isBetterThan result', () {
    final content = projectVictoryReport(
      snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 20),
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      priorSavedResult: const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
      saveState: MissionSaveState.saved,
    );

    expect(content.comparison, MissionResultComparison.medalImproved);
    expect(content.comparisonText, 'Medal improved: Silver → Gold');
    expect(content.saveText, 'Saved.');
    expect(
      content.nextOpportunityText,
      'Replay for a better result or continue on the World Map.',
    );
  });

  test('projects same-medal base-health improvement', () {
    final content = projectVictoryReport(
      snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 17),
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 17),
      priorSavedResult: const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
      saveState: MissionSaveState.saved,
    );

    expect(content.comparison, MissionResultComparison.baseHealthImproved);
    expect(content.comparisonText, 'Base health improved: 14 → 17');
  });

  test('projects retained best without implying a new write', () {
    final content = projectVictoryReport(
      snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 14),
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      priorSavedResult: const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
      saveState: MissionSaveState.saved,
    );

    expect(content.comparison, MissionResultComparison.retained);
    expect(
      content.comparisonText,
      'Saved best retained: Gold • 20 base health',
    );
    expect(content.saveText, 'Best result already saved.');
  });

  test('projects failed save copy', () {
    final content = projectVictoryReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      priorSavedResult: null,
      saveState: MissionSaveState.failed,
    );

    expect(content.saveText, 'Save failed — progress unchanged.');
    expect(
      content.nextOpportunityText,
      'Retry saving, or return without keeping this result.',
    );
  });

  test('projects loss without save state', () {
    final content = projectLossReport(
      snapshot: terminalSnapshot(
        phase: GamePhase.lost,
        baseHealth: 0,
        waveNumber: 5,
      ),
    );

    expect(content.didWin, isFalse);
    expect(content.outcomeText, 'Reached Wave 5/8');
    expect(content.saveState, isNull);
    expect(content.comparison, isNull);
  });

  test('projects empty module copy for victory and loss', () {
    final victory = projectVictoryReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      priorSavedResult: null,
      saveState: MissionSaveState.saving,
    );
    final loss = projectLossReport(
      snapshot: terminalSnapshot(phase: GamePhase.lost, baseHealth: 0),
    );

    expect(victory.moduleIds, isEmpty);
    expect(loss.moduleIds, isEmpty);
    expect(victory.emptyModulesText, 'No Salvage Modules acquired');
    expect(loss.emptyModulesText, 'No Salvage Modules acquired');
  });

  test('passes optional reward fact through unchanged', () {
    const reward = MissionRewardFact(
      title: 'Blueprint recovered',
      detail: 'Heavy Caliber Mk II',
    );
    final content = projectVictoryReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      priorSavedResult: null,
      saveState: MissionSaveState.saved,
      reward: reward,
    );

    expect(content.reward, same(reward));
  });
}
