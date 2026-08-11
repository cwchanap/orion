import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/run_module_unlocks.dart';

const clearedResult = StageResult(medal: StageMedal.clear, bestBaseHealth: 5);

void main() {
  test('base modules contain every ungated catalog module', () {
    final catalogIds = runModuleCatalog
        .map((definition) => definition.id)
        .toSet();

    expect(catalogIds, containsAll(RunModuleUnlocks.baseModules));
    expect(
      RunModuleUnlocks.baseModules,
      isNot(contains(RunModuleId.relayCalibration)),
    );
    expect(catalogIds.difference(RunModuleUnlocks.baseModules), {
      RunModuleId.relayCalibration,
    });
  });

  test('committed Outpost Alpha clear unlocks Relay Calibration', () {
    final progress = CampaignProgress().recordResult(
      OrionCampaign.stageOneId,
      clearedResult,
    );

    expect(
      RunModuleUnlocks.availableFor(progress),
      contains(RunModuleId.relayCalibration),
    );
  });

  test('unrelated clear does not unlock Relay Calibration', () {
    final progress = CampaignProgress().recordResult(
      'nebula-relay',
      clearedResult,
    );

    expect(
      RunModuleUnlocks.availableFor(progress),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });

  test('empty progress removes the derived unlock', () {
    expect(
      RunModuleUnlocks.availableFor(CampaignProgress()),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });
}
