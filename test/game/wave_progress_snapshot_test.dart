import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';

/// Fix round 2 RED tests for live wave-progress projections.
///
/// Findings under test:
///  * Boss arrival publishes a snapshot inside `_spawnEnemy` *before*
///    `_spawnWaveEnemies` increments `_spawnedCount`, so a one-boss wave
///    resolves `-1` scripted enemies and reports an inflated remaining count.
///  * `_spawnMinion` inserts summoned enemies into `_activeEnemyComponents`
///    without publishing. `unresolvedActive` already counts minions, while
///    `_spawnedCount`/`waveHostilesTotal` only count scripted enemies, so the
///    projected `resolved = spawned - unresolved` can go negative and the
///    remaining-hostiles readout goes stale until the next unrelated publish.
///
/// Expected product behaviour these tests pin:
///  * `waveHostilesRemaining` is the number of live unresolved hostiles —
///    scripted *and* summoned — bounded by `0 .. waveHostilesTotal`.
///  * `waveHostilesTotal - waveHostilesRemaining` (the resolved count the
///    dock renders as "N of M hostiles resolved") never goes negative.
///  * Spawning a minion republishes like killing or leaking one does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Wave one opens with the real Relay Breaker — the only scripted hostile —
  /// so boss-arrival publication is the first wave event, exactly like the
  /// boss group in Outpost Alpha wave 8.
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
        // A trailing wave so a cleared boss wave lands back in build phase.
        WaveDefinition(groups: [], clearBonus: 0),
      ],
      mapColumn: 0,
      mapRow: 0,
    );
  }

  /// Scripted basic drones ahead of the same real boss: progress must keep
  /// scripted and summoned hostiles distinct without double counting either.
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
    StageDefinition stage, {
    RunMode mode = RunMode.mission,
  }) async {
    final game = OrionDefenseGame(stage: stage, mode: mode);
    game.onGameResize(Vector2(800, 1200));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.setMounted();
    game.startWave();
    return game;
  }

  int liveHostiles(OrionDefenseGame game) => game.children
      .whereType<EnemyComponent>()
      .where((enemy) => !enemy.isResolved)
      .length;

  test('a one-boss wave reports the scripted hostile count when the boss '
      'arrives — never an inflated remaining', () async {
    final game = await startBossWave(bossArrivalStage());
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
      game.snapshot.waveHostilesRemaining! <= game.snapshot.waveHostilesTotal!,
      isTrue,
      reason: 'remaining hostiles must never exceed the wave total',
    );
  });

  test('spawning summoned minions republishes so remaining equals every live '
      'hostile — scripted boss plus summons', () async {
    final game = await startBossWave(bossArrivalStage());
    game.update(0.01);
    game.processLifecycleEvents();
    expect(
      game.children.whereType<EnemyComponent>().single.stats,
      isA<BossDefinition>(),
      reason: 'fixture sanity: the relay breaker must be on the board',
    );

    var publishes = 0;
    game.stateNotifier.addListener(() => publishes += 1);
    // Relay Breaker firstDelay is 4.0s: tick past it so the real summon
    // mechanic fires _spawnMinion three times.
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
      game.snapshot.waveHostilesRemaining! <= game.snapshot.waveHostilesTotal!,
      isTrue,
      reason: 'remaining hostiles must stay within the wave total',
    );
  });

  test('scripted plus summoned waves count every live hostile and republish on '
      'summon', () async {
    final game = await startBossWave(scriptedThenBossStage());
    // 4 drones on a 0.3s interval plus the boss after a 0.4s group delay.
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
  });

  test('minion kills and leaks keep resolved non-negative and remaining within '
      'the wave total', () async {
    final game = await startBossWave(bossArrivalStage());
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

    // Kill one minion: any publish recomputes resolved as
    // _spawnedCount - unresolvedActive, which underflows to -2 here.
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

    // Leak one minion into the base: same invariants through the
    // reached-base publish path.
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
  });

  test('an endless summon wave publishes minions and keeps the same progress '
      'invariants', () async {
    final game = await startBossWave(bossArrivalStage(), mode: RunMode.endless);
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
      game.snapshot.waveHostilesRemaining! <= game.snapshot.waveHostilesTotal!,
      isTrue,
      reason: 'remaining hostiles must stay within the wave total',
    );
  });
}
