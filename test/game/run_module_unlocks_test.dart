import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/run_module_unlocks.dart';

const clearedResult = StageResult(medal: StageMedal.clear, bestBaseHealth: 5);

const gatedBlueprints = {
  RunModuleId.relayCalibration,
  RunModuleId.relayArc,
  RunModuleId.salvagedDrones,
  RunModuleId.foundryNanites,
  RunModuleId.auroraFocus,
  RunModuleId.siegeRounds,
  RunModuleId.gravityEcho,
};

void main() {
  test('base modules contain every ungated catalog module', () {
    final catalogIds = runModuleCatalog
        .map((definition) => definition.id)
        .toSet();

    expect(catalogIds, containsAll(RunModuleUnlocks.baseModules));
    expect(RunModuleUnlocks.baseModules.intersection(gatedBlueprints), isEmpty);
    expect(catalogIds.difference(RunModuleUnlocks.baseModules), {
      RunModuleId.relayCalibration,
      RunModuleId.relayArc,
      RunModuleId.salvagedDrones,
      RunModuleId.foundryNanites,
      RunModuleId.auroraFocus,
      RunModuleId.siegeRounds,
      RunModuleId.gravityEcho,
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

  test('clearing each stage in isolation unlocks only its blueprint', () {
    for (final stage in OrionCampaign.stages) {
      final progress = CampaignProgress().recordResult(stage.id, clearedResult);

      expect(RunModuleUnlocks.availableFor(progress), {
        ...RunModuleUnlocks.baseModules,
        stage.blueprint!,
      }, reason: '${stage.id} clear must unlock exactly ${stage.blueprint}');
    }
  });

  test('multiple clears union blueprint eligibility', () {
    var progress = CampaignProgress();
    final expected = <RunModuleId>{...RunModuleUnlocks.baseModules};

    for (final stage in OrionCampaign.stages) {
      progress = progress.recordResult(stage.id, clearedResult);
      expected.add(stage.blueprint!);
      expect(RunModuleUnlocks.availableFor(progress), expected);
    }
    expect(
      expected,
      runModuleCatalog.map((definition) => definition.id).toSet(),
    );
  });

  test('resetting to empty progress removes blueprint unlocks', () {
    var progress = CampaignProgress();
    for (final stage in OrionCampaign.stages) {
      progress = progress.recordResult(stage.id, clearedResult);
    }
    expect(RunModuleUnlocks.availableFor(progress), hasLength(13));

    expect(
      RunModuleUnlocks.availableFor(CampaignProgress()),
      RunModuleUnlocks.baseModules,
    );
  });

  test('empty progress removes the derived unlock', () {
    expect(
      RunModuleUnlocks.availableFor(CampaignProgress()),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });
}
