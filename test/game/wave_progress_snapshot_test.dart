import 'dart:ui' show Size;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_board_skin.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/assets/game_path_tiles.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StageDefinition bossArrivalStage() {
    return StageDefinition(
      id: 'boss-arrival-stage',
      name: 'Boss Arrival Stage',
      mapLabel: 'Arrival',
      description: 'Real summoning boss opening wave one',
      pathCells: BoardLayout.pathCells,
      waves: const [
        WaveDefinition(
          groups: [
            WaveGroup(enemyCount: 1, enemyStats: GameBalance.relayBreaker),
          ],
          clearBonus: 40,
        ),
        WaveDefinition(groups: [], clearBonus: 0),
      ],
      mapColumn: 0,
      mapRow: 0,
    );
  }

  StageDefinition scriptedThenBossStage() {
    return StageDefinition(
      id: 'scripted-then-boss-stage',
      name: 'Scripted Then Boss Stage',
      mapLabel: 'Mixed',
      description: 'Real drones then a real summoning boss',
      pathCells: BoardLayout.pathCells,
      waves: [
        WaveDefinition(
          groups: [
            WaveGroup(
              enemyCount: 4,
              enemyStats: GameBalance.enemyArchetype(EnemyArchetype.basicDrone),
              spawnInterval: 0.3,
            ),
            const WaveGroup(
              enemyCount: 1,
              enemyStats: GameBalance.relayBreaker,
              initialDelay: 0.4,
            ),
          ],
          clearBonus: 30,
        ),
      ],
      mapColumn: 0,
      mapRow: 0,
    );
  }

  Future<OrionDefenseGame> startBossWave(
    WidgetTester tester,
    StageDefinition stage, {
    RunMode mode = RunMode.mission,
  }) async {
    final game = OrionDefenseGame(stage: stage, mode: mode);
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
      ]) {
        await game.images.load(name);
      }
    });
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    expect(game.isMounted, isTrue);
    game.pauseEngine();
    game.startWave();
    return game;
  }

  int liveHostiles(OrionDefenseGame game) => game.children
      .whereType<EnemyComponent>()
      .where((enemy) => !enemy.isResolved)
      .length;

  testWidgets(
    'a one-boss wave reports the scripted hostile count when the boss '
    'arrives — never an inflated remaining',
    (tester) async {
      final game = await startBossWave(tester, bossArrivalStage());
      expect(game.snapshot.waveHostilesTotal, 1);
      expect(game.snapshot.waveHostilesRemaining, 1);

      game.update(0.01);
      game.processLifecycleEvents();

      final boss = game.children.whereType<EnemyComponent>().single;
      expect(boss.stats, isA<BossDefinition>());
      expect(game.snapshot.bossActive, isTrue);
      expect(
        game.snapshot.waveHostilesTotal,
        1,
        reason: 'the scripted wave total does not change when the boss lands',
      );
      expect(
        game.snapshot.waveHostilesRemaining,
        1,
        reason:
            'boss arrival publishes before _spawnedCount increments: '
            'resolved = 0 - 1 = -1 leaves remaining at 2 — the "-1 of 1 '
            'hostiles resolved" off-by-one',
      );
      expect(
        game.snapshot.waveHostilesRemaining! <=
            game.snapshot.waveHostilesTotal!,
        isTrue,
        reason: 'remaining hostiles must never exceed the wave total',
      );
    },
  );

  testWidgets(
    'spawning summoned minions republishes so remaining equals every live '
    'hostile — scripted boss plus summons',
    (tester) async {
      final game = await startBossWave(tester, bossArrivalStage());
      game.update(0.01);
      game.processLifecycleEvents();
      expect(
        game.children.whereType<EnemyComponent>().single.stats,
        isA<BossDefinition>(),
        reason: 'fixture sanity: the relay breaker must be on the board',
      );

      var publishes = 0;
      game.stateNotifier.addListener(() => publishes += 1);
      game.update(4.5);
      game.processLifecycleEvents();

      final minions = game.children
          .whereType<EnemyComponent>()
          .where((enemy) => enemy.minionOf != null)
          .toList();
      expect(
        minions,
        hasLength(3),
        reason: 'fixture sanity: the summon mechanic must produce 3 minions',
      );
      final live = liveHostiles(game);
      expect(live, 4);
      expect(
        publishes,
        greaterThan(0),
        reason:
            'a minion entering play changes the hostile count exactly like a '
            'kill or a leak; _spawnMinion must publish the new snapshot',
      );
      expect(
        game.snapshot.waveHostilesRemaining,
        live,
        reason:
            'summoned hostiles are real threats the player must resolve; the '
            'readout must count them, not wait for the next unrelated event',
      );
      expect(
        game.snapshot.waveHostilesRemaining! <=
            game.snapshot.waveHostilesTotal!,
        isTrue,
        reason: 'remaining hostiles must stay within the wave total',
      );
    },
  );

  testWidgets(
    'scripted plus summoned waves count every live hostile and republish on '
    'summon',
    (tester) async {
      final game = await startBossWave(tester, scriptedThenBossStage());
      game.update(2.0);
      game.processLifecycleEvents();
      expect(
        game.children.whereType<EnemyComponent>(),
        hasLength(5),
        reason: 'fixture sanity: 4 drones + 1 boss must be live',
      );

      var publishes = 0;
      game.stateNotifier.addListener(() => publishes += 1);
      game.update(4.5);
      game.processLifecycleEvents();

      final live = liveHostiles(game);
      expect(
        live,
        8,
        reason: 'fixture sanity: 4 scripted drones + boss + 3 minions',
      );
      expect(
        publishes,
        greaterThan(0),
        reason: 'minion creation must republish the wave snapshot',
      );
      expect(
        game.snapshot.waveHostilesRemaining,
        live,
        reason:
            'scripted and summoned hostiles share one unresolved pool; the '
            'readout must not wait for a kill or a leak to notice minions',
      );
      expect(
        game.snapshot.waveHostilesTotal! - game.snapshot.waveHostilesRemaining!,
        greaterThanOrEqualTo(0),
        reason:
            'resolved hostiles can never be negative; minions in '
            'unresolvedActive must not underflow the scripted spawn count',
      );
    },
  );

  testWidgets(
    'minion kills and leaks keep resolved non-negative and remaining within '
    'the wave total',
    (tester) async {
      final game = await startBossWave(tester, bossArrivalStage());
      game.update(0.01);
      game.processLifecycleEvents();
      game.update(4.5);
      game.processLifecycleEvents();

      final minions = game.children
          .whereType<EnemyComponent>()
          .where((enemy) => enemy.minionOf != null)
          .toList();
      expect(minions, hasLength(3), reason: 'fixture sanity');
      final baseBefore = game.snapshot.baseHealth;

      minions.first.applyDamage(minions.first.maxHealth, bypassArmor: true);
      game.processLifecycleEvents();
      var snapshot = game.snapshot;
      expect(
        liveHostiles(game),
        3,
        reason: 'fixture sanity: boss + 2 minions after one kill',
      );
      expect(
        snapshot.waveHostilesTotal! - snapshot.waveHostilesRemaining!,
        greaterThanOrEqualTo(0),
        reason:
            'the resolved count the dock reads as "N of M resolved" must '
            'never be negative after a minion dies',
      );
      expect(
        snapshot.waveHostilesRemaining! <= snapshot.waveHostilesTotal!,
        isTrue,
        reason: 'remaining hostiles must stay within the wave total',
      );

      minions[1].resolveReachedBase();
      game.processLifecycleEvents();
      snapshot = game.snapshot;
      expect(
        snapshot.baseHealth,
        baseBefore - 1,
        reason: 'fixture sanity: the leaked minion dealt its base damage',
      );
      expect(
        liveHostiles(game),
        2,
        reason: 'fixture sanity: boss + 1 minion after kill + leak',
      );
      expect(
        snapshot.waveHostilesTotal! - snapshot.waveHostilesRemaining!,
        greaterThanOrEqualTo(0),
        reason: 'resolved must never go negative after a minion leaks',
      );
      expect(
        snapshot.waveHostilesRemaining! <= snapshot.waveHostilesTotal!,
        isTrue,
        reason: 'remaining hostiles must stay within the wave total',
      );
      expect(
        snapshot.waveHostilesRemaining! >= 0,
        isTrue,
        reason: 'remaining hostiles can never go negative',
      );
    },
  );

  testWidgets(
    'an endless summon wave publishes minions and keeps the same progress '
    'invariants',
    (tester) async {
      final game = await startBossWave(
        tester,
        bossArrivalStage(),
        mode: RunMode.endless,
      );
      game.update(0.01);
      game.processLifecycleEvents();
      expect(
        game.snapshot.waveHostilesTotal,
        1,
        reason: 'endless wave one replays the scripted boss group',
      );

      var publishes = 0;
      game.stateNotifier.addListener(() => publishes += 1);
      game.update(4.5);
      game.processLifecycleEvents();

      final live = liveHostiles(game);
      expect(
        live,
        4,
        reason: 'fixture sanity: boss + 3 minions in endless wave one',
      );
      expect(
        publishes,
        greaterThan(0),
        reason:
            'endless waves publish kills and leaks like mission waves; a '
            'summon must publish too',
      );
      expect(
        game.snapshot.waveHostilesRemaining,
        live,
        reason:
            'endless hostiles include summoned minions the moment they '
            'enter play',
      );
      expect(
        game.snapshot.waveHostilesTotal! - game.snapshot.waveHostilesRemaining!,
        greaterThanOrEqualTo(0),
        reason: 'resolved must never be negative in endless either',
      );
      expect(
        game.snapshot.waveHostilesRemaining! <=
            game.snapshot.waveHostilesTotal!,
        isTrue,
        reason: 'remaining hostiles must stay within the wave total',
      );
    },
  );
}
