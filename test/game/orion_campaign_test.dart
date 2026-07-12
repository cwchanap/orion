import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
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

    test('wave group lists are immutable', () {
      final extraGroup = WaveGroup(
        enemyCount: 1,
        enemyStats: GameBalance.enemyArchetype(EnemyArchetype.basicDrone),
      );

      for (final stage in OrionCampaign.stages) {
        for (final wave in stage.waves) {
          expect(() => wave.groups.add(extraGroup), throwsUnsupportedError);
        }
      }
    });

    test(
      'defines approved main path order and side stage order invariants',
      () {
        expect(OrionCampaign.mainStages.map((stage) => stage.mainPathOrder), [
          1,
          2,
          3,
          4,
          5,
        ]);
        expect(
          OrionCampaign.sideStages.map((stage) => stage.mainPathOrder),
          everyElement(isNull),
        );
      },
    );

    test('validation reports malformed main path order data', () {
      final invalidStages = [
        _stage(id: 'stage-one', mainPathOrder: 1),
        _stage(id: 'stage-two'),
        _stage(id: 'stage-three', mainPathOrder: 1),
        _stage(id: 'side-stage', isMainPath: false, mainPathOrder: 2),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(errors, contains('stage-two main stage must have an order.'));
      expect(errors, contains('side-stage side stage must not have an order.'));
      expect(errors, contains('Duplicate main path order: 1.'));
      expect(
        errors,
        contains('Main path orders must be exactly [1, 2, 3, 4, 5].'),
      );
    });

    test('validation returns no errors for shipped campaign data', () {
      expect(OrionCampaign.validate(), isEmpty);
    });

    test('side stages carry campaign rewards and main stages do not', () {
      expect(
        OrionCampaign.stageById('salvage-rift').reward,
        CampaignReward.bonusGold,
      );
      expect(
        OrionCampaign.stageById('void-bastion').reward,
        CampaignReward.bonusHealth,
      );
      for (final stage in OrionCampaign.mainStages) {
        expect(stage.reward, isNull, reason: stage.id);
      }
    });

    test('validation rejects main stage with a reward', () {
      final invalidStages = [
        _stage(
          id: 'stage-1',
          mainPathOrder: 1,
          reward: CampaignReward.bonusGold,
        ),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5),
        _stage(
          id: 'side-a',
          isMainPath: false,
          reward: CampaignReward.bonusGold,
        ),
        _stage(
          id: 'side-b',
          isMainPath: false,
          reward: CampaignReward.bonusHealth,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(errors, contains('stage-1 main stage must not have a reward.'));
    });

    test('validation rejects side stage without a reward', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5),
        _stage(id: 'side-a', isMainPath: false),
        _stage(
          id: 'side-b',
          isMainPath: false,
          reward: CampaignReward.bonusHealth,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(errors, contains('side-a side stage must have a reward.'));
    });

    test('validation rejects challengeBadge on an individual stage', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5),
        _stage(
          id: 'side-a',
          isMainPath: false,
          reward: CampaignReward.bonusGold,
        ),
        _stage(
          id: 'side-b',
          isMainPath: false,
          reward: CampaignReward.challengeBadge,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(
        errors,
        contains(
          'side-b must not carry challengeBadge; it is compound-derived.',
        ),
      );
    });
  });
}

StageDefinition _stage({
  required String id,
  bool isMainPath = true,
  int? mainPathOrder,
  CampaignReward? reward,
}) {
  return StageDefinition(
    id: id,
    name: id,
    mapLabel: id,
    description: id,
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: GameBalance.waves,
    isMainPath: isMainPath,
    mainPathOrder: mainPathOrder,
    reward: reward,
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}
