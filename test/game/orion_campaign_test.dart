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

    test('every stage wave 8 ends in a single boss with enemyCount 1', () {
      for (final stage in OrionCampaign.stages) {
        final wave = stage.waves.last;
        expect(wave.groups, isNotEmpty);
        final last = wave.groups.last;
        expect(
          last.enemyStats,
          isA<BossDefinition>(),
          reason: '${stage.id} wave 8 must end in a boss',
        );
        expect(
          last.enemyCount,
          1,
          reason: '${stage.id} boss group must be count 1',
        );
        for (var i = 0; i < wave.groups.length - 1; i++) {
          expect(
            wave.groups[i].enemyStats,
            isNot(isA<BossDefinition>()),
            reason: '${stage.id} has a non-final boss group',
          );
        }
        for (var w = 0; w < stage.waves.length - 1; w++) {
          for (final g in stage.waves[w].groups) {
            expect(
              g.enemyStats,
              isNot(isA<BossDefinition>()),
              reason: '${stage.id} has a boss before wave 8',
            );
          }
        }
      }
    });

    test('each stage wave-8 boss maps to its approved BossSprite', () {
      const expected = <String, BossSprite>{
        'outpost-alpha': BossSprite.relayBreaker,
        'nebula-relay': BossSprite.shieldMatriarch,
        'salvage-rift': BossSprite.swarmQueen,
        'asteroid-foundry': BossSprite.armoredExcavator,
        'aurora-gate': BossSprite.regenWarden,
        'void-bastion': BossSprite.siegeCarrier,
        'singularity-core': BossSprite.singularityCore,
      };

      for (final stage in OrionCampaign.stages) {
        final boss = stage.waves.last.groups.last.enemyStats;
        expect(boss, isA<BossDefinition>(), reason: stage.id);
        expect(
          (boss as BossDefinition).sprite,
          expected[stage.id],
          reason: '${stage.id} boss sprite mismatch',
        );
      }
    });

    test('validation rejects a stage whose final wave has no boss', () {
      final bosslessWaves = List<WaveDefinition>.generate(
        8,
        (_) => WaveDefinition(
          groups: [
            WaveGroup(
              enemyCount: 1,
              enemyStats: GameBalance.enemyArchetype(EnemyArchetype.basicDrone),
            ),
          ],
          clearBonus: 0,
        ),
      );

      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5, waves: bosslessWaves),
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

      expect(
        errors,
        contains('stage-5 must have exactly one boss group; found 0.'),
      );
    });

    test('validation rejects a boss that is not the final wave-8 group', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(
          id: 'stage-5',
          mainPathOrder: 5,
          waves: _bossShapedWaves(bossLastInWave: false),
        ),
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

      expect(
        errors,
        contains('stage-5 boss must be the final group of the final wave.'),
      );
    });

    test('validation rejects a boss placed before the final wave', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(
          id: 'stage-5',
          mainPathOrder: 5,
          waves: _bossShapedWaves(bossWaveIndex: 6),
        ),
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

      expect(errors, contains('stage-5 boss must be in the final wave.'));
    });

    test('validation rejects a boss group whose enemyCount is not 1', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(
          id: 'stage-5',
          mainPathOrder: 5,
          waves: _bossShapedWaves(bossEnemyCount: 2),
        ),
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

      expect(errors, contains('stage-5 boss group must have enemyCount 1.'));
    });

    test('validation rejects a wave-8 with more than one boss group', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(
          id: 'stage-5',
          mainPathOrder: 5,
          waves: _bossShapedWaves(bossCount: 2),
        ),
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

      expect(
        errors,
        contains('stage-5 must have exactly one boss group; found 2.'),
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

    test('validation rejects duplicate stat rewards across side stages', () {
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
          reward: CampaignReward.bonusGold,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(
        errors,
        contains(
          '${CampaignReward.bonusGold} reward appears on 2 stages; '
          'expected at most one.',
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
  List<WaveDefinition>? waves,
}) {
  return StageDefinition(
    id: id,
    name: id,
    mapLabel: id,
    description: id,
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: waves ?? GameBalance.waves,
    isMainPath: isMainPath,
    mainPathOrder: mainPathOrder,
    reward: reward,
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}

List<WaveDefinition> _bossShapedWaves({
  int bossWaveIndex = 7,
  int bossEnemyCount = 1,
  bool bossLastInWave = true,
  int bossCount = 1,
}) {
  final normalStats = GameBalance.enemyArchetype(EnemyArchetype.basicDrone);
  WaveGroup normalGroup() => WaveGroup(enemyCount: 4, enemyStats: normalStats);
  WaveGroup bossGroup() => WaveGroup(
    enemyCount: bossEnemyCount,
    enemyStats: GameBalance.relayBreaker,
  );
  final waves = <WaveDefinition>[];
  for (var w = 0; w < 8; w += 1) {
    final groups = <WaveGroup>[normalGroup()];
    if (w == bossWaveIndex) {
      for (var i = 0; i < bossCount; i += 1) {
        if (bossLastInWave) {
          groups.add(bossGroup());
        } else {
          groups.insert(0, bossGroup());
        }
      }
    }
    waves.add(WaveDefinition(groups: List.unmodifiable(groups), clearBonus: 0));
  }
  return List.unmodifiable(waves);
}
