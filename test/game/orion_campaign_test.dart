import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  group('OrionCampaign', () {
    test('defines seven stages with five main and two side stages', () {
      expect(OrionCampaign.stages, hasLength(7));
      expect(OrionCampaign.mainStages, hasLength(5));
      expect(OrionCampaign.sideStages, hasLength(2));
      expect(OrionCampaign.stageOne.id, 'outpost-alpha');
    });

    test('defines approved unlock graph', () {
      expect(OrionCampaign.stageById('outpost-alpha').unlockDependencies, []);
      expect(OrionCampaign.stageById('nebula-relay').unlockDependencies, [
        'outpost-alpha',
      ]);
      expect(OrionCampaign.stageById('salvage-rift').unlockDependencies, [
        'nebula-relay',
      ]);
      expect(OrionCampaign.stageById('asteroid-foundry').unlockDependencies, [
        'nebula-relay',
      ]);
      expect(OrionCampaign.stageById('aurora-gate').unlockDependencies, [
        'asteroid-foundry',
      ]);
      expect(OrionCampaign.stageById('void-bastion').unlockDependencies, [
        'aurora-gate',
      ]);
      expect(OrionCampaign.stageById('singularity-core').unlockDependencies, [
        'aurora-gate',
      ]);
    });

    test('each stage has eight waves and in-bounds continuous path cells', () {
      for (final stage in OrionCampaign.stages) {
        expect(stage.waves, hasLength(8), reason: stage.id);
        expect(stage.pathCells.length, greaterThanOrEqualTo(2));
        for (final position in stage.pathCells) {
          expect(BoardLayout.isInBounds(position), isTrue, reason: stage.id);
        }
        for (var index = 1; index < stage.pathCells.length; index += 1) {
          expect(
            stage.pathCells[index - 1].distanceTo(stage.pathCells[index]),
            1,
            reason: stage.id,
          );
        }
      }
    });

    test('stage one keeps the current baseline path and waves', () {
      final stage = OrionCampaign.stageOne;

      expect(stage.pathCells, BoardLayout.pathCells);
      expect(stage.waves, GameBalance.waves);
    });

    test('validation returns no errors for shipped campaign data', () {
      expect(OrionCampaign.validate(), isEmpty);
    });
  });
}
