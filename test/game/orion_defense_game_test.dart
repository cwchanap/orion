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

    test('defaults to unpaused 1x pacing with auto-start disabled', () {
      final game = OrionDefenseGame();

      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('sets supported speed multipliers and ignores unsupported values', () {
      final game = OrionDefenseGame();

      game.setSpeedMultiplier(2);
      expect(game.snapshot.speedMultiplier, 2);
      expect(game.timeScale, 2);

      game.setSpeedMultiplier(3);
      expect(game.snapshot.speedMultiplier, 3);
      expect(game.timeScale, 3);

      game.setSpeedMultiplier(4);
      expect(game.snapshot.speedMultiplier, 3);
      expect(game.timeScale, 3);
    });

    test('pause freezes time scale and resume restores selected speed', () {
      final game = OrionDefenseGame();

      game.setSpeedMultiplier(3);
      game.startWave();
      game.togglePause();

      expect(game.snapshot.isPaused, isTrue);
      expect(game.timeScale, 0);

      game.togglePause();

      expect(game.snapshot.isPaused, isFalse);
      expect(game.timeScale, 3);
    });

    test(
      'toggleAutoStart updates snapshot and clears countdown when disabled',
      () {
        final game = OrionDefenseGame();

        game.toggleAutoStart();
        expect(game.snapshot.autoStartEnabled, isTrue);

        game.toggleAutoStart();
        expect(game.snapshot.autoStartEnabled, isFalse);
        expect(game.snapshot.autoStartCountdownRemaining, isNull);
      },
    );

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

    test(
      'wave clear starts auto-start countdown when another wave remains',
      () {
        final game = OrionDefenseGame(stage: _emptyWaveStage());

        game.toggleAutoStart();
        game.startWave();
        game.onGameResize(Vector2(800, 1200));
        game.update(0);

        expect(game.snapshot.phase, GamePhase.build);
        expect(game.snapshot.waveNumber, 2);
        expect(game.snapshot.autoStartEnabled, isTrue);
        expect(game.snapshot.autoStartCountdownRemaining, 3);
      },
    );

    test('auto-start countdown can be canceled by turning auto-start off', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage());

      game.toggleAutoStart();
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);
      game.toggleAutoStart();

      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.snapshot.phase, GamePhase.build);
    });

    test(
      'auto-start countdown starts next wave after scaled unpaused time',
      () {
        final game = OrionDefenseGame(stage: _emptyWaveStage());

        game.toggleAutoStart();
        game.setSpeedMultiplier(3);
        game.startWave();
        game.onGameResize(Vector2(800, 1200));
        game.update(0);

        game.update(1);

        expect(game.snapshot.phase, GamePhase.wave);
        expect(game.snapshot.waveNumber, 2);
        expect(game.snapshot.autoStartCountdownRemaining, isNull);
      },
    );

    test('paused auto-start countdown does not advance', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage());

      game.toggleAutoStart();
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);
      game.togglePause();

      game.update(10);

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.isPaused, isTrue);
      expect(game.snapshot.autoStartCountdownRemaining, 3);
    });

    test('restart resets pacing state', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage());

      game.toggleAutoStart();
      game.setSpeedMultiplier(3);
      game.startWave();
      game.togglePause();

      game.restart();

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('won state resets pacing state', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage(waveCount: 1));

      game.toggleAutoStart();
      game.setSpeedMultiplier(3);
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(game.snapshot.phase, GamePhase.won);
      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });
  });
}

StageDefinition _emptyWaveStage({int waveCount = 2}) {
  return StageDefinition(
    id: 'empty-wave-stage',
    name: 'Empty Wave Stage',
    mapLabel: 'Empty',
    description: 'Stage with empty waves for timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      waveCount,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
