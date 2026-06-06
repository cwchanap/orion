import 'package:orion/game/campaign/stage_definition.dart';

enum StageProgressStatus { locked, unlocked, cleared }

class CampaignProgress {
  CampaignProgress({Set<String> clearedStageIds = const <String>{}})
    : _clearedStageIds = Set.unmodifiable(clearedStageIds);

  final Set<String> _clearedStageIds;

  Set<String> get clearedStageIds => _clearedStageIds;

  bool isCleared(String stageId) {
    return _clearedStageIds.contains(stageId);
  }

  bool isUnlocked(StageDefinition stage) {
    return stage.unlockDependencies.every(_clearedStageIds.contains);
  }

  StageProgressStatus statusFor(StageDefinition stage) {
    if (isCleared(stage.id)) {
      return StageProgressStatus.cleared;
    }

    if (isUnlocked(stage)) {
      return StageProgressStatus.unlocked;
    }

    return StageProgressStatus.locked;
  }

  bool isCampaignComplete(Iterable<StageDefinition> stages) {
    return stages
        .where((stage) => stage.isMainPath)
        .every((stage) => isCleared(stage.id));
  }

  CampaignProgress withoutUnknownStages(Iterable<StageDefinition> stages) {
    final knownStageIds = stages.map((stage) => stage.id).toSet();

    return CampaignProgress(
      clearedStageIds: _clearedStageIds.where(knownStageIds.contains).toSet(),
    );
  }

  CampaignProgress markCleared(String stageId) {
    return CampaignProgress(clearedStageIds: {..._clearedStageIds, stageId});
  }
}
