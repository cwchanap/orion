import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';

void main() {
  group('OrionDefenseGame', () {
    test('defaults to campaign stage one', () {
      final game = OrionDefenseGame();

      expect(game.stage, OrionCampaign.stageOne);
      expect(game.snapshot.stageName, 'Outpost Alpha');
    });

    test('can be constructed for another stage', () {
      final stage = OrionCampaign.stageById('nebula-relay');
      final game = OrionDefenseGame(stage: stage);

      expect(game.stage, stage);
      expect(game.snapshot.stageName, 'Nebula Relay');
      expect(game.snapshot.waveTotal, 8);
    });

    test('returnToMap fires callback during build phase', () {
      var callCount = 0;
      final game = OrionDefenseGame(onReturnToMap: () => callCount += 1);

      game.returnToMap();

      expect(callCount, 1);
    });

    test('returnToMap is blocked during an active wave', () {
      var callCount = 0;
      final game = OrionDefenseGame(onReturnToMap: () => callCount += 1);

      game.startWave();
      game.returnToMap();

      expect(callCount, 0);
      expect(
        game.snapshot.feedback,
        'Finish the active wave before returning.',
      );
    });

    test('calls onStageWon after a wave clear publishes won phase', () {
      final stage = StageDefinition(
        id: 'one-wave-stage',
        name: 'One Wave Stage',
        mapLabel: 'One',
        description: 'Stage with one empty wave',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: const [WaveDefinition(groups: [], clearBonus: 0)],
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );
      final wonStages = <StageDefinition>[];
      final game = OrionDefenseGame(stage: stage, onStageWon: wonStages.add);

      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(wonStages, [stage]);
      expect(game.snapshot.phase, GamePhase.won);
    });
  });
}
