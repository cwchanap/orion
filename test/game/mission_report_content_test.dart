import 'package:flutter_test/flutter_test.dart';

import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import '../support/command_deck_fixtures.dart';

GameSnapshot terminalSnapshot({
  required GamePhase phase,
  int baseHealth = 14,
  int waveNumber = 8,
  int? missionWaveTotal = 8,
  int wavesCleared = 0,
  List<RunModuleId> modules = const [],
}) {
  return commandDeckSnapshot(
    phase: phase,
    gold: 120,
    baseHealth: baseHealth,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    missionWaveTotal: missionWaveTotal,
    wavesCleared: wavesCleared,
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

  group('projectEndlessReport', () {
    GameSnapshot endlessDefeat({int waveNumber = 6, int wavesCleared = 5}) {
      return terminalSnapshot(
        phase: GamePhase.lost,
        baseHealth: 0,
        waveNumber: waveNumber,
        missionWaveTotal: null,
        wavesCleared: wavesCleared,
      );
    }

    test('first run projects a new best with saved copy', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(),
        priorBest: null,
        savedBest: 5,
        saveState: MissionSaveState.saved,
      );

      expect(content.didWin, isFalse);
      expect(content.snapshot.isEndless, isTrue);
      expect(content.outcomeText, 'Survived 5 waves');
      expect(content.comparisonText, 'New best!');
      expect(content.result, isNull);
      expect(content.medalPoints, 0);
      expect(content.reward, isNull);
      expect(content.saveState, MissionSaveState.saved);
      expect(content.saveText, 'Saved.');
      expect(
        content.nextOpportunityText,
        'Replay for a better result or continue on the World Map.',
      );
    });

    test('new best reports the previous record', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(waveNumber: 18, wavesCleared: 17),
        priorBest: 12,
        savedBest: 17,
        saveState: MissionSaveState.saved,
      );

      expect(content.outcomeText, 'Survived 17 waves');
      expect(content.comparisonText, 'New best! Previous: 12 waves');
      expect(content.saveText, 'Saved.');
    });

    test('retained best reports the standing record', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(waveNumber: 13, wavesCleared: 12),
        priorBest: 20,
        savedBest: 20,
        saveState: MissionSaveState.saved,
      );

      expect(content.outcomeText, 'Survived 12 waves');
      expect(content.comparisonText, 'Best: 20 waves');
      expect(content.saveText, 'Best result already saved.');
    });

    test('saving reuses the mission pending copy', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(),
        priorBest: null,
        savedBest: null,
        saveState: MissionSaveState.saving,
      );

      expect(content.saveText, 'Saving result…');
      expect(
        content.nextOpportunityText,
        'Saving must finish before you replay or leave.',
      );
    });

    test('failed with nothing committed keeps the progress-unchanged copy', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(),
        priorBest: null,
        savedBest: null,
        saveState: MissionSaveState.failed,
      );

      expect(content.saveText, 'Save failed — progress unchanged.');
      expect(
        content.nextOpportunityText,
        'Retry saving, or return without keeping this result.',
      );
    });

    test('failed names the committed best instead of the unsaved score', () {
      // Mid-run record saves can commit before the final write fails: a run
      // that scored 5 against prior best 3 may still hold a committed 4.
      final content = projectEndlessReport(
        snapshot: endlessDefeat(waveNumber: 6, wavesCleared: 5),
        priorBest: 3,
        savedBest: 4,
        saveState: MissionSaveState.failed,
      );

      expect(content.comparisonText, 'New best! Previous: 3 waves');
      expect(content.saveText, 'Save failed — best 4 waves kept.');
      expect(
        content.nextOpportunityText,
        'Retry saving, or return without keeping this result.',
      );
    });

    test('uses singular wave when count is 1', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(waveNumber: 2, wavesCleared: 1),
        priorBest: 1,
        savedBest: 1,
        saveState: MissionSaveState.failed,
      );

      expect(content.outcomeText, 'Survived 1 wave');
      expect(content.comparisonText, 'Best: 1 wave');
      expect(content.saveText, 'Save failed — best 1 wave kept.');

      final newBestContent = projectEndlessReport(
        snapshot: endlessDefeat(waveNumber: 3, wavesCleared: 2),
        priorBest: 1,
        savedBest: 1,
        saveState: MissionSaveState.saved,
      );
      expect(newBestContent.comparisonText, 'New best! Previous: 1 wave');
    });

    test('a wave-one defeat survived zero waves', () {
      final content = projectEndlessReport(
        snapshot: endlessDefeat(waveNumber: 1, wavesCleared: 0),
        priorBest: null,
        savedBest: null,
        saveState: MissionSaveState.saved,
      );

      expect(content.outcomeText, 'Survived 0 waves');
      expect(content.comparisonText, 'No endless best yet');
      expect(content.saveState, MissionSaveState.saved);
      expect(content.saveText, 'No result to save.');
      expect(
        content.nextOpportunityText,
        'Replay for a better result or continue on the World Map.',
      );
    });

    test('module ids pass through with the shared empty-state copy', () {
      final withModules = projectEndlessReport(
        snapshot: terminalSnapshot(
          phase: GamePhase.lost,
          baseHealth: 0,
          missionWaveTotal: null,
          wavesCleared: 3,
          modules: const [RunModuleId.heavyCaliber],
        ),
        priorBest: null,
        savedBest: 3,
        saveState: MissionSaveState.saved,
      );
      final empty = projectEndlessReport(
        snapshot: endlessDefeat(),
        priorBest: null,
        savedBest: 5,
        saveState: MissionSaveState.saved,
      );

      expect(withModules.moduleIds, [RunModuleId.heavyCaliber]);
      expect(withModules.emptyModulesText, isNull);
      expect(empty.moduleIds, isEmpty);
      expect(empty.emptyModulesText, 'No Salvage Modules acquired');
    });
  });
}
