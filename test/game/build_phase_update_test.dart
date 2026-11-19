import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_board_skin.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/assets/game_path_tiles.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/projectile_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

import 'game_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One weak enemy on a short path; the scripted kill reward makes the
  /// post-settle gold assertion exact (the final mission wave pays no
  /// clear bonus, so the wave win must also come through cleanly).
  StageDefinition oneShotStage() {
    return StageDefinition(
      id: 'build-phase-stage',
      name: 'Build Phase Stage',
      mapLabel: 'Build',
      description: 'Single fragile wave for build-phase update tests',
      pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
      waves: const [
        WaveDefinition(
          groups: [
            WaveGroup(
              enemyCount: 1,
              enemyStats: EnemyStats(
                health: 100,
                speed: 10,
                baseDamage: 1,
                goldReward: 25,
              ),
            ),
          ],
          clearBonus: 30,
        ),
      ],
      mapColumn: 0,
      mapRow: 0,
    );
  }

  /// Mirrors the real stage scaffold: the snapshot listener wraps the
  /// GameWidget, so a publish inside the GameWidget's own layout pass marks
  /// a listening ancestor dirty — the exact markNeedsBuild-during-build
  /// path Flutter forbids.
  Widget host(OrionDefenseGame game) => ValueListenableBuilder<GameSnapshot>(
    valueListenable: game.stateNotifier,
    builder: (context, snapshot, _) => GameWidget(game: game),
  );

  Future<OrionDefenseGame> mountGame(
    WidgetTester tester, {
    void Function(StageCompletion completion)? onStageWon,
  }) async {
    final game = OrionDefenseGame(
      stage: oneShotStage(),
      squad: testStarterSquad,
      onStageWon: onStageWon,
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      for (final name in [
        GameBoardSkin.fileName,
        GamePathTiles.fileName,
        GameSpriteSheet.fileName,
        GameTowerVarietySheet.fileName,
        GameBossSheet.fileName,
        for (final member in [Character.haruto, Character.mio])
          OrionArt.characterChibi(member).fileName,
      ]) {
        await game.images.load(name);
      }
    });
    // Drop the onLoad-time memoized futures so the warmed cache resolves.
    OrionArtDescriptor.resetSpriteCache();
    await tester.pumpWidget(host(game));
    await tester.pump();
    await tester.pump();
    expect(game.isMounted, isTrue);
    // Stop the engine's ticker without pausing the game: GameWidget still
    // calls update(0) inside its LayoutBuilder build pass (it only skips
    // paused games), but no real tick can steal the scripted collision —
    // the only update that can resolve it is the one inside the build.
    game.renderBox.gameLoop?.stop();
    return game;
  }

  testWidgets(
    'a collision resolved by the GameWidget build-pass update does not '
    'throw during build and still settles the kill, gold, and victory',
    (tester) async {
      final completions = <StageCompletion>[];
      final game = await mountGame(tester, onStageWon: completions.add);

      // Deploy Haruto on a cell covering the short path, then start the wave.
      game.handleBoardTap(game.boardCellCenter(const GridPosition(0, 1)));
      game.placeTower(Character.haruto);
      expect(game.snapshot.placedTowers, hasLength(1));
      game.startWave();
      game.update(0.01);
      game.processLifecycleEvents();
      final enemy = game.children.whereType<EnemyComponent>().single;

      // Tick until the tower's projectile is live, then park it on the
      // target: the next update — even a zero-dt one — resolves the hit.
      ProjectileComponent? projectile;
      for (var i = 0; i < 300 && projectile == null; i++) {
        game.update(0.02);
        game.processLifecycleEvents();
        final live = game.children
            .whereType<ProjectileComponent>()
            .where((shot) => shot.isMounted && !shot.isRemoving)
            .toList();
        if (live.isNotEmpty) {
          projectile = live.first;
        }
      }
      expect(
        projectile,
        isNotNull,
        reason: 'fixture: the laser tower must fire a live projectile',
      );
      expect(enemy.isAlive, isTrue, reason: 'fixture: no early kill');
      enemy.applyDamage(99, bypassArmor: true);
      expect(enemy.health, 1);
      projectile!.position.setFrom(enemy.position);
      final goldBefore = game.snapshot.gold;

      // Rebuild the tree: the GameWidget's LayoutBuilder runs its build pass
      // during layout, where it calls update(0) — resolving the parked hit
      // mid-build. Before the fix this threw 'setState() or markNeedsBuild()
      // called during build' via the snapshot listener.
      await tester.pumpWidget(host(game));

      expect(tester.takeException(), isNull);
      expect(
        game.snapshot.gold,
        goldBefore + 25,
        reason:
            'the deferred settle must still award the kill reward — '
            'deferral must not drop the publish (the scripted wave pays no '
            'clear bonus: it is the final mission wave)',
      );
      expect(game.snapshot.wavesCleared, 1);
      expect(game.snapshot.phase, GamePhase.won);
      expect(completions, hasLength(1));

      // Immediate out-of-build actions keep synchronous publish semantics.
      var publishes = 0;
      game.stateNotifier.addListener(() => publishes += 1);
      game.restart();
      expect(
        publishes,
        greaterThan(0),
        reason: 'restart outside the build phase must publish synchronously',
      );
      expect(game.snapshot.phase, GamePhase.build);

      // A further rebuild on the restarted game stays clean too.
      await tester.pumpWidget(host(game));
      expect(tester.takeException(), isNull);
      expect(game.snapshot.phase, GamePhase.build);
    },
  );

  testWidgets(
    '_publishSnapshot defers notification during persistentCallbacks for any caller',
    (tester) async {
      final game = await mountGame(tester);
      var triggered = false;

      await tester.pumpWidget(
        ValueListenableBuilder<GameSnapshot>(
          valueListenable: game.stateNotifier,
          builder: (context, snapshot, _) {
            if (!triggered) {
              triggered = true;
              // Simulate a caller invoking _publishSnapshot during build.
              game.togglePause();
            }
            return GameWidget(game: game);
          },
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(game.snapshot.isPaused, isTrue);
    },
  );
}
