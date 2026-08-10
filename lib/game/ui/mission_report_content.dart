import '../campaign/campaign_progress.dart';
import '../models/game_models.dart';

enum MissionSaveState { saving, saved, failed }

enum MissionResultComparison {
  firstClear,
  medalImproved,
  baseHealthImproved,
  retained,
}

final class MissionRewardFact {
  const MissionRewardFact({required this.title, required this.detail});

  final String title;
  final String detail;
}

final class MissionReportContent {
  MissionReportContent({
    required this.stageId,
    required this.stageName,
    required this.didWin,
    required this.outcomeText,
    this.result,
    this.comparison,
    this.comparisonText,
    required List<RunModuleId> moduleIds,
    this.emptyModulesText,
    this.saveState,
    this.saveText,
    this.reward,
    required this.nextOpportunityText,
  }) : moduleIds = List.unmodifiable(moduleIds);

  final String stageId;
  final String stageName;
  final bool didWin;
  final String outcomeText;
  final StageResult? result;
  final MissionResultComparison? comparison;
  final String? comparisonText;
  final List<RunModuleId> moduleIds;
  final String? emptyModulesText;
  final MissionSaveState? saveState;
  final String? saveText;
  final MissionRewardFact? reward;
  final String nextOpportunityText;
}

MissionResultComparison compareMissionResult(
  StageResult result,
  StageResult? prior,
) {
  if (prior == null) {
    return MissionResultComparison.firstClear;
  }
  if (!result.isBetterThan(prior)) {
    return MissionResultComparison.retained;
  }
  if (result.medal.rank > prior.medal.rank) {
    return MissionResultComparison.medalImproved;
  }
  return MissionResultComparison.baseHealthImproved;
}

MissionReportContent projectVictoryReport({
  required GameSnapshot snapshot,
  required StageResult result,
  required StageResult? priorSavedResult,
  required MissionSaveState saveState,
  MissionRewardFact? reward,
}) {
  final comparison = compareMissionResult(result, priorSavedResult);
  final comparisonText = switch (comparison) {
    MissionResultComparison.firstClear => 'New first-clear result',
    MissionResultComparison.medalImproved =>
      'Medal improved: ${priorSavedResult!.medal.label} → ${result.medal.label}',
    MissionResultComparison.baseHealthImproved =>
      'Base health improved: ${priorSavedResult!.bestBaseHealth} → ${result.bestBaseHealth}',
    MissionResultComparison.retained =>
      'Saved best retained: ${priorSavedResult!.medal.label} • ${priorSavedResult.bestBaseHealth} base health',
  };

  return MissionReportContent(
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    didWin: true,
    outcomeText:
        '${result.medal.label} medal • Base ${result.bestBaseHealth}/${snapshot.startingBaseHealth}',
    result: result,
    comparison: comparison,
    comparisonText: comparisonText,
    moduleIds: snapshot.acquiredRunModules,
    emptyModulesText: snapshot.acquiredRunModules.isEmpty
        ? 'No Salvage Modules acquired'
        : null,
    saveState: saveState,
    saveText: switch (saveState) {
      MissionSaveState.saving => 'Saving result…',
      MissionSaveState.saved =>
        comparison == MissionResultComparison.retained
            ? 'Best result already saved.'
            : 'Saved.',
      MissionSaveState.failed => 'Save failed — progress unchanged.',
    },
    reward: reward,
    nextOpportunityText: switch (saveState) {
      MissionSaveState.saving =>
        'Saving must finish before you replay or leave.',
      MissionSaveState.saved =>
        'Replay for a better result or continue on the World Map.',
      MissionSaveState.failed =>
        'Retry saving, or return without keeping this result.',
    },
  );
}

MissionReportContent projectLossReport({required GameSnapshot snapshot}) {
  return MissionReportContent(
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    didWin: false,
    outcomeText: 'Reached Wave ${snapshot.waveNumber}/${snapshot.waveTotal}',
    moduleIds: snapshot.acquiredRunModules,
    emptyModulesText: snapshot.acquiredRunModules.isEmpty
        ? 'No Salvage Modules acquired'
        : null,
    nextOpportunityText: 'Adjust your build and retry when ready.',
  );
}
