import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/components/drone_component.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/gravity_field_component.dart';
import 'package:orion/game/components/projectile_component.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrionDefenseGame', () {
    test('defaults to campaign stage one', () {
      final game = OrionDefenseGame();

      expect(game.stage, OrionCampaign.stageOne);
      expect(game.snapshot.stageName, 'Outpost Alpha');
    });

    test('onLoad loads all sprite sheets including the boss sheet', () async {
      final game = OrionDefenseGame();
      game.onGameResize(Vector2(800, 1200));
      await game.onLoad();

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.hasLayout, isTrue);
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

    test('auto-start enabled before first wave does not start countdown', () {
      final game = OrionDefenseGame();

      game.toggleAutoStart();
      game.update(OrionDefenseGame.autoStartCountdownSeconds + 1);

      expect(game.snapshot.autoStartEnabled, isTrue);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.waveNumber, 1);
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

    test('calls onStageWon with a completion result after won snapshot', () {
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
      final completions = <StageCompletion>[];
      final game = OrionDefenseGame(stage: stage, onStageWon: completions.add);

      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(game.snapshot.phase, GamePhase.won);
      expect(completions, hasLength(1));
      expect(completions.single.stage, stage);
      expect(
        completions.single.result,
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
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

    test('auto-start toggled on after a cleared wave starts countdown', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage());

      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0);

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.waveNumber, 2);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);

      game.toggleAutoStart();

      expect(game.snapshot.autoStartEnabled, isTrue);
      expect(game.snapshot.autoStartCountdownRemaining, 3);
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.waveNumber, 2);
    });

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

    test('paused active-wave update does not run combat components', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      expect(game.children.whereType<ProjectileComponent>(), isEmpty);
      game.togglePause();

      expect(() {
        game.update(1);
        game.update(1);
        game.update(1);
        game.processLifecycleEvents();
      }, returnsNormally);

      expect(game.snapshot.phase, GamePhase.wave);
      expect(game.snapshot.isPaused, isTrue);
      expect(game.children.whereType<ProjectileComponent>(), isEmpty);
    });

    test('paused wave freezes enemy movement and spawn timer', () {
      final game = OrionDefenseGame(stage: _twoEnemyDelayedSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      final position = enemy.position.clone();
      final pathProgress = enemy.pathProgress;

      game.togglePause();
      game.update(10);
      game.processLifecycleEvents();

      expect(game.children.whereType<EnemyComponent>(), hasLength(1));
      expect(enemy.position, position);
      expect(enemy.pathProgress, pathProgress);
      expect(game.snapshot.phase, GamePhase.wave);
      expect(game.snapshot.isPaused, isTrue);
    });

    test('tapping an active enemy marks it inspected', () {
      final game = OrionDefenseGame(stage: _twoEnemyImmediateSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.05);
      game.processLifecycleEvents();

      final enemies = game.children.whereType<EnemyComponent>().toList();
      expect(enemies, hasLength(2));
      enemies[0].position = Vector2(120, 200);
      enemies[1].position = Vector2(420, 200);

      _tapPoint(game, enemies[0].position);

      expect(game.inspectedEnemyId, enemies[0].enemyId);
      expect(enemies[0].isInspected, isTrue);
      expect(enemies[1].isInspected, isFalse);
      expect(enemies[0].overlayState.isExpanded, isTrue);
    });

    test('tapping another active enemy switches inspection', () {
      final game = OrionDefenseGame(stage: _twoEnemyImmediateSpawnStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.05);
      game.processLifecycleEvents();

      final enemies = game.children.whereType<EnemyComponent>().toList();
      enemies[0].position = Vector2(120, 200);
      enemies[1].position = Vector2(420, 200);

      _tapPoint(game, enemies[0].position);
      _tapPoint(game, enemies[1].position);

      expect(game.inspectedEnemyId, enemies[1].enemyId);
      expect(enemies[0].isInspected, isFalse);
      expect(enemies[1].isInspected, isTrue);
    });

    test('tapping away from enemies clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.position = Vector2(120, 200);

      _tapPoint(game, enemy.position);
      _tapPoint(game, Vector2(700, 1100));

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isInspected, isFalse);
    });

    test('resolving the inspected enemy clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.position = Vector2(120, 200);
      _tapPoint(game, enemy.position);

      enemy.applyDamage(1000);
      game.processLifecycleEvents();

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isResolved, isTrue);
    });

    test('inspected enemy reaching the base clears inspection', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());

      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();

      final enemy = game.children.whereType<EnemyComponent>().single;
      _tapPoint(game, enemy.position);

      expect(game.inspectedEnemyId, enemy.enemyId);

      enemy.update(100);
      game.processLifecycleEvents();

      expect(game.inspectedEnemyId, isNull);
      expect(enemy.isResolved, isTrue);
    });

    test('3x speed accelerates real enemy progress compared with 1x', () {
      final oneXGame = OrionDefenseGame(stage: _singleEnemyStage());
      final threeXGame = OrionDefenseGame(stage: _singleEnemyStage());

      oneXGame.setSpeedMultiplier(1);
      threeXGame.setSpeedMultiplier(3);
      oneXGame.onGameResize(Vector2(800, 1200));
      threeXGame.onGameResize(Vector2(800, 1200));
      oneXGame.startWave();
      threeXGame.startWave();
      oneXGame.update(0.01);
      threeXGame.update(0.01);
      oneXGame.processLifecycleEvents();
      threeXGame.processLifecycleEvents();

      oneXGame.update(0.5);
      threeXGame.update(0.5);

      final oneXProgress = oneXGame.children
          .whereType<EnemyComponent>()
          .single
          .pathProgress;
      final threeXProgress = threeXGame.children
          .whereType<EnemyComponent>()
          .single
          .pathProgress;

      expect(threeXProgress, greaterThan(oneXProgress));
      expect(threeXProgress, closeTo(oneXProgress * 3, 0.001));
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

    test('lost state resets pacing state', () {
      final game = OrionDefenseGame(stage: _lethalSingleEnemyStage());

      game.toggleAutoStart();
      game.setSpeedMultiplier(3);
      game.startWave();
      game.onGameResize(Vector2(800, 1200));
      game.update(0.01);
      final enemy = game.children.whereType<EnemyComponent>().single;

      enemy.update(1);

      expect(game.snapshot.phase, GamePhase.lost);
      expect(game.snapshot.isPaused, isFalse);
      expect(game.snapshot.speedMultiplier, 1);
      expect(game.snapshot.autoStartEnabled, isFalse);
      expect(game.snapshot.autoStartCountdownRemaining, isNull);
      expect(game.timeScale, 1);
    });

    test('setTargetingMode without a selected tower reports feedback', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));

      game.setTargetingMode(TowerTargetingMode.strongest);

      expect(game.snapshot.feedback, 'Select a tower first.');
      expect(game.snapshot.selectedTower, isNull);
    });

    test('setTargetingMode updates the selected tower during build phase', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();

      // Re-tap the placed tower's cell to select it.
      _tapCell(game, const GridPosition(0, 1));
      game.processLifecycleEvents();

      final tower = game.snapshot.selectedTower;
      expect(tower, isNotNull);
      expect(tower!.targetingMode, TowerTargetingMode.first);

      game.setTargetingMode(TowerTargetingMode.strongest);

      expect(
        game.snapshot.selectedTower!.targetingMode,
        TowerTargetingMode.strongest,
      );
      expect(game.snapshot.feedback, isNull);
    });

    test('setTargetingMode is denied during an active wave', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      game.startWave();

      // startWave clears the selection; re-select the tower during the wave.
      _tapCell(game, const GridPosition(0, 1));
      game.processLifecycleEvents();
      expect(game.snapshot.selectedTower, isNotNull);

      game.setTargetingMode(TowerTargetingMode.strongest);

      expect(game.snapshot.phase, GamePhase.wave);
      expect(
        game.snapshot.feedback,
        'Targeting can only change during build phase.',
      );
      // Mode is unchanged.
      expect(
        game.snapshot.selectedTower!.targetingMode,
        TowerTargetingMode.first,
      );
    });

    test(
      'sellSelectedTower removes the component, clears selection, refunds',
      () {
        final game = OrionDefenseGame(stage: _singleEnemyStage());
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();
        expect(game.snapshot.selectedTower, isNotNull);
        expect(game.children.whereType<TowerComponent>(), hasLength(1));

        game.sellSelectedTower();
        game.processLifecycleEvents();

        expect(game.children.whereType<TowerComponent>(), isEmpty);
        expect(game.snapshot.selectedTower, isNull);
        expect(game.snapshot.feedback, 'Sold for 35 gold.');
        expect(game.snapshot.gold, GameBalance.startingGold - 50 + 35);
      },
    );

    test('sellSelectedTower with no selection reports feedback', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));

      game.sellSelectedTower();

      expect(game.snapshot.feedback, 'Select a tower first.');
    });

    test('sellSelectedTower is denied during an active wave', () {
      final game = OrionDefenseGame(stage: _singleEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();
      game.startWave();
      _tapCell(game, const GridPosition(0, 1)); // re-select during wave
      game.processLifecycleEvents();
      expect(game.snapshot.selectedTower, isNotNull);

      game.sellSelectedTower();
      game.processLifecycleEvents();

      expect(game.snapshot.feedback, 'Sell towers between waves.');
      expect(game.children.whereType<TowerComponent>(), hasLength(1));
    });

    test('sellSelectedTower despawns a sold drone bay live drones', () {
      final game = OrionDefenseGame(stage: _droneBayUnlockStage());
      game.onGameResize(Vector2(800, 1200));

      // Advance 5 empty waves so the drone bay (unlocks at wave 6) is available.
      for (var wave = 0; wave < 5; wave += 1) {
        game.startWave();
        game.update(0);
        game.processLifecycleEvents();
      }
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.unlockedTowerTypes, contains(TowerType.droneBay));

      // Place the drone bay adjacent to the wave-6 path and run that wave.
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.droneBay);
      game.processLifecycleEvents();
      expect(game.children.whereType<TowerComponent>(), hasLength(1));

      game.startWave(); // wave 6: one durable enemy
      game.update(0.01); // spawn the enemy
      game.processLifecycleEvents();
      // The game is not mounted in unit tests, so add() during updateTree
      // iteration modifies the children set directly instead of queueing,
      // which throws a concurrent-modification error when the drone bay fires
      // inside game.update(). Firing the tower via its own update() (outside
      // the iteration) launches the drones safely; the end state matches the
      // real mounted-game behavior.
      game.children.whereType<TowerComponent>().single.update(0.01);
      game.processLifecycleEvents();

      final dronesBefore = game.children.whereType<DroneComponent>().toList();
      expect(dronesBefore, isNotEmpty); // guards against a vacuous pass

      // End the wave (sell is build-phase only) by resolving the enemy.
      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.applyDamage(10000);
      game.update(0.01);
      game.processLifecycleEvents();
      expect(game.snapshot.phase, GamePhase.build);

      final droneBayId = game.snapshot.selectedTower?.id;
      expect(droneBayId, isNull); // not selected yet

      _tapCell(game, const GridPosition(0, 1)); // select the drone bay
      game.processLifecycleEvents();
      final ownerTowerId = game.snapshot.selectedTower!.id;

      game.sellSelectedTower();
      game.processLifecycleEvents();

      expect(
        game.children.whereType<DroneComponent>().where(
          (d) => d.ownerTowerId == ownerTowerId,
        ),
        isEmpty,
      );
      expect(game.children.whereType<TowerComponent>(), isEmpty);
    });

    test('sellSelectedTower despawns a sold gravity well lingering fields', () {
      final game = OrionDefenseGame(stage: _gravityWellUnlockStage());
      game.onGameResize(Vector2(800, 1200));

      // Advance 4 empty waves so the gravity well (unlocks at wave 5) is
      // available.
      for (var wave = 0; wave < 4; wave += 1) {
        game.startWave();
        game.update(0);
        game.processLifecycleEvents();
      }
      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.unlockedTowerTypes, contains(TowerType.gravityWell));

      // Place the gravity well adjacent to the wave-5 path and run that wave.
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.gravityWell);
      game.processLifecycleEvents();
      expect(game.children.whereType<TowerComponent>(), hasLength(1));

      game.startWave(); // wave 5: one durable enemy
      game.update(0.01); // spawn the enemy
      game.processLifecycleEvents();
      // See the drone bay test: firing the tower via its own update() avoids
      // a concurrent-modification error in unmounted unit tests.
      game.children.whereType<TowerComponent>().single.update(0.01);
      game.processLifecycleEvents();

      final fieldsBefore = game.children
          .whereType<GravityFieldComponent>()
          .toList();
      expect(fieldsBefore, isNotEmpty); // guards against a vacuous pass

      // End the wave (sell is build-phase only) by resolving the enemy. The
      // field's fieldDuration (2.0s) has NOT elapsed, so it would otherwise
      // linger into the next wave.
      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.applyDamage(10000);
      game.update(0.01);
      game.processLifecycleEvents();
      expect(game.snapshot.phase, GamePhase.build);

      // The lingering field is still on screen before the sell.
      final ownerTowerId = game.children
          .whereType<TowerComponent>()
          .single
          .placedTower
          .id;
      expect(
        game.children.whereType<GravityFieldComponent>().where(
          (f) => f.ownerTowerId == ownerTowerId,
        ),
        isNotEmpty,
      );

      _tapCell(game, const GridPosition(0, 1)); // select the gravity well
      game.processLifecycleEvents();
      game.sellSelectedTower();
      game.processLifecycleEvents();

      expect(
        game.children.whereType<GravityFieldComponent>().where(
          (f) => f.ownerTowerId == ownerTowerId,
        ),
        isEmpty,
      );
      expect(game.children.whereType<TowerComponent>(), isEmpty);
    });

    test('applies campaign modifiers to session starting values', () {
      final game = OrionDefenseGame(
        stage: _emptyWaveStage(),
        modifiers: const CampaignModifiers(bonusGold: 30, bonusHealth: 5),
      );

      expect(game.snapshot.gold, GameBalance.startingGold + 30);
      expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth + 5);
      expect(
        game.snapshot.startingBaseHealth,
        GameBalance.initialBaseHealth + 5,
      );
    });

    test('defaults to no modifiers and baseline economy', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage());

      expect(game.snapshot.gold, GameBalance.startingGold);
      expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth);
    });

    test('clearBonusFraction amplifies the wave-clear gold bonus when set', () {
      // Wave-clear bonus resolution lives in GameSession.finishActiveWave,
      // which reads session.modifiers.clearBonusFraction. If OrionDefenseGame
      // fails to forward its modifiers to GameSession.initial, the fraction
      // stays 0 and the bonus is unscaled.
      final game = OrionDefenseGame(
        stage: _clearBonusStage(clearBonus: 100),
        modifiers: const CampaignModifiers(clearBonusFraction: 0.5),
      );
      game.onGameResize(Vector2(800, 1200));

      final goldBefore = game.snapshot.gold;
      game.startWave();
      game.update(0);

      expect(game.snapshot.phase, GamePhase.build);
      // 100 * (1 + 0.5) = 150 added on top of the starting gold.
      expect(game.snapshot.gold, goldBefore + 150);
    });

    test('wave-clear gold bonus is unscaled when modifiers are absent', () {
      final game = OrionDefenseGame(stage: _clearBonusStage(clearBonus: 100));
      game.onGameResize(Vector2(800, 1200));

      final goldBefore = game.snapshot.gold;
      game.startWave();
      game.update(0);

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.gold, goldBefore + 100);
    });

    test('laser tower stats reflect laserDamageFraction from modifiers', () {
      // TowerComponent resolves its stats through TowerStatsResolver.resolve,
      // which reads its modifiers field. If OrionDefenseGame fails to forward
      // modifiers to _addTowerComponent, the placed tower uses
      // CampaignModifiers.empty and the damage is unscaled.
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final game = OrionDefenseGame(
        stage: _singleEnemyStage(),
        modifiers: mods,
      );
      game.onGameResize(Vector2(800, 1200));
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.laser);
      game.processLifecycleEvents();

      final component = game.children.whereType<TowerComponent>().single;
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
    });

    test(
      'upgrading a laser tower re-applies laserDamageFraction via updateTower',
      () {
        // Exercises the updateTower call site in upgradeSelectedTower.
        // If updateTower fails to re-resolve stats through
        // TowerStatsResolver.resolve, the upgraded tower uses the unmodified
        // level-2 base damage (18) instead of the scaled value (19.8).
        const mods = CampaignModifiers(laserDamageFraction: 0.10);
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          modifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();

        game.upgradeSelectedTower();
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(TowerType.laser, level: 2);
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
      },
    );

    test(
      'specializing a laser tower re-applies laserDamageFraction via updateTower',
      () {
        // Exercises the updateTower call site in specializeSelectedTower.
        // bonusGold covers place(50) + upgrade(70) + specialize(120) = 240.
        const mods = CampaignModifiers(
          laserDamageFraction: 0.10,
          bonusGold: 100,
        );
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          modifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();

        game.upgradeSelectedTower();
        game.processLifecycleEvents();

        game.specializeSelectedTower(TowerSpecialization.pulseLaser);
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(
          TowerType.laser,
          level: 3,
          specialization: TowerSpecialization.pulseLaser,
        );
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
      },
    );

    test(
      'retargeting a laser tower preserves laserDamageFraction via updateTower',
      () {
        // Exercises the updateTower call site in setTargetingMode
        // (orion_defense_game.dart:282). If updateTower fails to re-resolve
        // stats, the targeting-mode change drops the damage multiplier.
        const mods = CampaignModifiers(laserDamageFraction: 0.10);
        final game = OrionDefenseGame(
          stage: _singleEnemyStage(),
          modifiers: mods,
        );
        game.onGameResize(Vector2(800, 1200));
        _tapCell(game, const GridPosition(0, 1));
        game.placeTower(TowerType.laser);
        game.processLifecycleEvents();
        _tapCell(game, const GridPosition(0, 1)); // select the placed tower
        game.processLifecycleEvents();

        game.setTargetingMode(TowerTargetingMode.strongest);
        game.processLifecycleEvents();

        final component = game.children.whereType<TowerComponent>().single;
        final base = GameBalance.towerStats(TowerType.laser, level: 1);
        expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
        expect(
          component.placedTower.targetingMode,
          TowerTargetingMode.strongest,
        );
      },
    );

    test('restart resets base health to modifier-adjusted starting value', () {
      // A session created with non-zero modifiers must reset back to the
      // adjusted starting values (not the unmodified baseline, and not the
      // damaged mid-wave value) after restart.
      const bonusHealth = 5;
      const bonusGold = 30;
      const adjustedStartingHealth =
          GameBalance.initialBaseHealth + bonusHealth;
      const adjustedStartingGold = GameBalance.startingGold + bonusGold;
      final game = OrionDefenseGame(
        stage: _lethalSingleEnemyStage(),
        modifiers: const CampaignModifiers(
          bonusGold: bonusGold,
          bonusHealth: bonusHealth,
        ),
      );

      expect(game.snapshot.gold, adjustedStartingGold);
      expect(game.snapshot.baseHealth, adjustedStartingHealth);
      expect(game.snapshot.startingBaseHealth, adjustedStartingHealth);

      // Damage the base: the lethal enemy deals initialBaseHealth damage,
      // which the bonus health absorbs so the base survives but is hurt.
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();
      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.update(1);
      game.processLifecycleEvents();

      expect(
        game.snapshot.baseHealth,
        lessThan(adjustedStartingHealth),
        reason: 'base should be damaged before restart',
      );
      expect(game.snapshot.baseHealth, greaterThan(0));

      game.restart();

      expect(game.snapshot.phase, GamePhase.build);
      expect(game.snapshot.baseHealth, adjustedStartingHealth);
      expect(game.snapshot.startingBaseHealth, adjustedStartingHealth);
      expect(game.snapshot.gold, adjustedStartingGold);
    });

    test(
      'boss summons minions that path from its position and block completion',
      () {
        final game = OrionDefenseGame(stage: _bossSummonStage());
        game.onGameResize(Vector2(800, 1200));
        game.startWave();
        // Spawn the boss. firstDelay (0.5s) has not elapsed, so no summon yet
        // and no concurrent-modification risk on this tick.
        game.update(0.01);
        game.processLifecycleEvents();

        final boss = game.children.whereType<EnemyComponent>().single;
        expect(boss.stats, isA<BossDefinition>());

        // Advance the boss directly past firstDelay to trigger the summon.
        // Calling boss.update() outside game.update()'s tree iteration avoids
        // a concurrent-modification error when add() fires inside an
        // unmounted unit test (same workaround the drone bay sell test uses
        // for tower.update()).
        boss.update(0.5 + 0.01);
        game.processLifecycleEvents();

        final minions = game.children
            .whereType<EnemyComponent>()
            .where((e) => e.minionOf == boss.enemyId)
            .toList();
        // Boss requests count=3 per trigger but maxActive=2 caps the spawn.
        expect(minions, hasLength(2));
        for (final minion in minions) {
          expect(minion.pathProgress, closeTo(boss.pathProgress, 1e-6));
        }

        // Killing the boss leaves minions alive, blocking wave completion.
        boss.applyDamage(boss.maxHealth);
        game.processLifecycleEvents();
        game.update(0.01);
        game.processLifecycleEvents();

        expect(
          game.children.whereType<EnemyComponent>().where(
            (e) => e.minionOf != null,
          ),
          isNotEmpty,
        );
        expect(game.snapshot.phase, GamePhase.wave);

        // Clearing the minions completes the wave.
        for (final minion
            in game.children.whereType<EnemyComponent>().toList()) {
          minion.applyDamage(minion.maxHealth);
        }
        game.processLifecycleEvents();
        game.update(0.01);
        game.processLifecycleEvents();

        expect(game.children.whereType<EnemyComponent>(), isEmpty);
        expect(game.snapshot.phase, GamePhase.build);
      },
    );
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

StageDefinition _clearBonusStage({required int clearBonus, int waveCount = 2}) {
  return StageDefinition(
    id: 'clear-bonus-stage',
    name: 'Clear Bonus Stage',
    mapLabel: 'Bonus',
    description: 'Stage with non-zero clear bonus for modifier tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      waveCount,
      (_) => WaveDefinition(groups: const [], clearBonus: clearBonus),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _singleEnemyStage() {
  return StageDefinition(
    id: 'single-enemy-stage',
    name: 'Single Enemy Stage',
    mapLabel: 'Single',
    description: 'Stage with one enemy for pause timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 100,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _twoEnemyDelayedSpawnStage() {
  return StageDefinition(
    id: 'two-enemy-delayed-spawn-stage',
    name: 'Two Enemy Delayed Spawn Stage',
    mapLabel: 'Delayed',
    description: 'Stage with delayed second enemy for pause timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            spawnInterval: 5,
            enemyStats: EnemyStats(
              health: 100,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _twoEnemyImmediateSpawnStage() {
  return StageDefinition(
    id: 'two-enemy-immediate-spawn-stage',
    name: 'Two Enemy Immediate Spawn Stage',
    mapLabel: 'Immediate',
    description: 'Stage with two enemies for inspection tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 2,
            spawnInterval: 0.01,
            enemyStats: EnemyStats(
              health: 100,
              speed: 0,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _bossSummonStage() {
  return StageDefinition(
    id: 'boss-summon-stage',
    name: 'Boss Summon Stage',
    mapLabel: 'Boss',
    description: 'Stage with a summoning boss for minion spawn tests',
    pathCells: const [
      GridPosition(0, 0),
      GridPosition(1, 0),
      GridPosition(2, 0),
      GridPosition(3, 0),
      GridPosition(4, 0),
    ],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: BossDefinition(
              health: 5000,
              speed: 10,
              baseDamage: 1,
              goldReward: 0,
              sprite: BossSprite.swarmQueen,
              name: 'Swarm Queen',
              summonMechanic: SummonMechanic(
                interval: 100,
                firstDelay: 0.5,
                count: 3,
                maxActive: 2,
                minionStats: EnemyStats(
                  health: 50,
                  speed: 10,
                  baseDamage: 1,
                  goldReward: 0,
                ),
              ),
            ),
          ),
        ],
        clearBonus: 0,
      ),
      // A trailing empty wave so clearing the boss wave lands in build phase.
      WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

StageDefinition _lethalSingleEnemyStage() {
  return StageDefinition(
    id: 'lethal-single-enemy-stage',
    name: 'Lethal Single Enemy Stage',
    mapLabel: 'Lethal',
    description: 'Stage with one lethal enemy for loss reset tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 100,
              speed: 1000,
              baseDamage: GameBalance.initialBaseHealth,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

/// Stage whose first 5 waves are empty (to unlock the wave-6 drone bay) and
/// whose 6th wave spawns a single durable enemy for drone-launch tests.
StageDefinition _droneBayUnlockStage() {
  return StageDefinition(
    id: 'drone-bay-unlock-stage',
    name: 'Drone Bay Unlock Stage',
    mapLabel: 'Drone',
    description: 'Stage that unlocks the drone bay for sell tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 5; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 10000,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
      // A trailing empty wave so clearing wave 6 leaves the game in build
      // phase (not won), allowing the sell-during-build flow to be tested.
      const WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

/// Stage whose first 4 waves are empty (to unlock the wave-5 gravity well) and
/// whose 5th wave spawns a single durable enemy for gravity-field tests.
StageDefinition _gravityWellUnlockStage() {
  return StageDefinition(
    id: 'gravity-well-unlock-stage',
    name: 'Gravity Well Unlock Stage',
    mapLabel: 'Gravity',
    description: 'Stage that unlocks the gravity well for sell tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 4; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 10000,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
      // A trailing empty wave so clearing wave 5 leaves the game in build
      // phase (not won), allowing the sell-during-build flow to be tested.
      const WaveDefinition(groups: [], clearBonus: 0),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}

void _tapCell(OrionDefenseGame game, GridPosition position) {
  final center = BoardLayout.cellCenter(
    position,
    cellSize: 100,
    boardOrigin: Offset.zero,
  );
  game.onTapDown(TapDownEvent(1, game, TapDownDetails(globalPosition: center)));
}

void _tapPoint(OrionDefenseGame game, Vector2 point) {
  game.onTapDown(
    TapDownEvent(
      1,
      game,
      TapDownDetails(globalPosition: Offset(point.x, point.y)),
    ),
  );
}
