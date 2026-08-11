import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../models/game_models.dart';

const _unlockStageByModule = <RunModuleId, String>{
  RunModuleId.relayCalibration: OrionCampaign.stageOneId,
};

abstract final class RunModuleUnlocks {
  static Set<RunModuleId> availableFor(CampaignProgress progress) =>
      Set<RunModuleId>.unmodifiable(
        runModuleCatalog.map((definition) => definition.id).where((id) {
          final unlockStageId = _unlockStageByModule[id];
          return unlockStageId == null || progress.isCleared(unlockStageId);
        }),
      );

  static final Set<RunModuleId> baseModules = availableFor(CampaignProgress());
}
