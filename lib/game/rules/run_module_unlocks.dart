import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../models/game_models.dart';

abstract final class RunModuleUnlocks {
  /// Catalog modules eligible for a run: every module is available unless a
  /// stage owns it as its blueprint and that stage has no committed clear in
  /// [progress].
  static Set<RunModuleId> availableFor(CampaignProgress progress) =>
      Set<RunModuleId>.unmodifiable(
        runModuleCatalog
            .map((definition) => definition.id)
            .where(
              (id) => OrionCampaign.stages.every(
                (stage) =>
                    stage.blueprint != id || progress.isCleared(stage.id),
              ),
            ),
      );

  static final Set<RunModuleId> baseModules = availableFor(CampaignProgress());
}
