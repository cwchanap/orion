import 'package:orion/game/campaign/stage_definition.dart';

enum StageProgressStatus { locked, unlocked, cleared }

class CampaignProgress {
  const factory CampaignProgress({Set<String> clearedStageIds}) =
      CampaignProgress._;

  const CampaignProgress._({this.clearedStageIds = const <String>{}});

  final Set<String> clearedStageIds;

  bool isCleared(String stageId) {
    return clearedStageIds.contains(stageId);
  }

  bool isUnlocked(StageDefinition stage) {
    return isCleared(stage.id) ||
        stage.unlockDependencies.every(clearedStageIds.contains);
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

  bool isCampaignComplete(List<StageDefinition> stages) {
    return stages
        .where((stage) => stage.isMainPath)
        .every((stage) => isCleared(stage.id));
  }

  CampaignProgress markCleared(String stageId) {
    return CampaignProgress._(
      clearedStageIds: Set.unmodifiable({...clearedStageIds, stageId}),
    );
  }
}
