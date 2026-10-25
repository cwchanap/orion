import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/contextual_tips.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/first_mission_guide_callout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/command_deck_fixtures.dart';
import '../widget_test.dart' as harness;

const _bossCopy = 'Boss ahead. Check the scanner and prepare your defense.';

/// Alpha's finale preview: ordinary groups plus the Relay Breaker boss.
WavePreview _bossPreview({int waveNumber = 8}) => commandDeckPreview(
  waveNumber: waveNumber,
  groups: [
    WavePreviewGroup(enemyCount: 6, label: 'Basic Drones', traits: const {}),
    WavePreviewGroup(enemyCount: 1, label: 'Relay Breaker', traits: const {}),
  ],
);

/// Mutable holder for the mounted game so a test can re-enter a stage and
/// still reach the freshly created game through the page's own callback.
class _GameRef {
  OrionDefenseGame? game;
}

/// Counts write-throughs so a multi-fact snapshot can prove it issues
/// exactly ONE setSeenTips call.
class _CountingFirstMissionGuideStore extends InMemoryFirstMissionGuideStore {
  _CountingFirstMissionGuideStore({required super.completed});

  int setSeenTipsCalls = 0;

  @override
  Future<void> setSeenTips(Set<ContextualTip> tips) async {
    setSeenTipsCalls++;
    await super.setSeenTips(tips);
  }
}

/// Holds each setSeenTips write until the test completes it, exposing both
/// the issued order and the hazard of writes finishing out of order.
class _GatedFirstMissionGuideStore extends InMemoryFirstMissionGuideStore {
  _GatedFirstMissionGuideStore({required super.completed});

  final pendingWrites = <Completer<void>>[];
  final issuedWrites = <Set<ContextualTip>>[];

  @override
  Future<void> setSeenTips(Set<ContextualTip> tips) {
    issuedWrites.add(Set.of(tips));
    final gate = Completer<void>();
    pendingWrites.add(gate);
    return gate.future.then((_) => super.setSeenTips(tips));
  }
}

/// setCompleted always rejects: a reported replay failure must not leave
/// the cleared seen-tip set persisted behind it.
class _FailingCompletionGuideStore extends InMemoryFirstMissionGuideStore {
  _FailingCompletionGuideStore({required super.completed, super.seenTips});

  @override
  Future<void> setCompleted(bool completed) =>
      Future.error(StateError('simulated persistence failure'));
}

/// Pumps the page at the 360x640 viewport, starts Alpha from its briefing,
/// and returns the captor holding the mounted game.
Future<_GameRef> _pumpMission(
  WidgetTester tester, {
  required FirstMissionGuideStore guideStore,
  _GameRef? ref,
  CampaignProgressStore? progressStore,
  String actionLabel = 'Start Mission',
}) async {
  final gameRef = ref ?? _GameRef();
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Tear the mounted game down so its live ticker never outlives the test.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
  await tester.pumpWidget(
    harness.testGamePage(
      progressStore: progressStore,
      firstMissionGuideStore: guideStore,
      onGameCreated: (created) => gameRef.game = created,
    ),
  );
  await tester.pumpAndSettle();
  await harness.startStageFromBriefing(tester, actionLabel: actionLabel);
  // The mounted game loop never settles under fake async: fixed pumps only.
  await tester.pump();
  await tester.pump();
  if (gameRef.game == null) {
    fail('OrionDefenseGame was not created.');
  }
  return gameRef;
}

/// Projects a fixture snapshot into the live page and lets the callout
/// measure its anchor plus one motion window before assertions.
Future<void> _project(
  WidgetTester tester,
  OrionDefenseGame game,
  GameSnapshot snapshot,
) async {
  game.stateNotifier.value = snapshot;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

void main() {
  // The page builds default SharedPreferences-backed stores unless injected,
  // so every test needs the in-memory plugin mock.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Retires the current page/game loop or its live ticker keeps the next
  /// pumpAndSettle from ever settling.
  Future<void> retireMission(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'first boss preview shows the boss tip anchored at the collapsed scanner',
    (tester) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);

      await _project(
        tester,
        ref.game!,
        commandDeckSnapshot(nextWavePreview: _bossPreview()),
      );

      expect(find.text(_bossCopy), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(find.text('Skip tutorial'), findsNothing);
      // The anchor is the existing collapsed scanner control: the bubble
      // sits against its edge without covering it.
      final bubble = tester.getRect(
        find.byKey(const ValueKey('first-mission-guide-callout-bubble')),
      );
      final scanner = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      );
      expect(
        bubble.top,
        greaterThanOrEqualTo(scanner.bottom),
        reason: 'the bubble must not cover the scanner control',
      );
    },
  );

  testWidgets('an active HPA-412 guide suppresses the boss tip', (
    tester,
  ) async {
    final store = InMemoryFirstMissionGuideStore();
    final ref = await _pumpMission(tester, guideStore: store);
    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

    await _project(
      tester,
      ref.game!,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );

    expect(find.text(_bossCopy), findsNothing);
    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
  });

  testWidgets('no boss tip during combat, draft, report or selection', (
    tester,
  ) async {
    final store = InMemoryFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);
    final game = ref.game!;

    await _project(
      tester,
      game,
      commandDeckSnapshot(
        phase: GamePhase.wave,
        waveNumber: 8,
        nextWavePreview: _bossPreview(),
      ),
    );
    expect(find.text(_bossCopy), findsNothing);

    await _project(
      tester,
      game,
      commandDeckSnapshot(
        nextWavePreview: _bossPreview(),
        pendingRunModuleOffer: RunModuleOffer(
          offerId: 1,
          draftNumber: 1,
          draftTotal: 3,
          moduleIds: const [RunModuleId.heavyCaliber],
        ),
      ),
    );
    expect(find.text(_bossCopy), findsNothing);

    await _project(
      tester,
      game,
      commandDeckSnapshot(
        phase: GamePhase.lost,
        baseHealth: 0,
        nextWavePreview: _bossPreview(),
      ),
    );
    expect(find.text(_bossCopy), findsNothing);

    await _project(
      tester,
      game,
      commandDeckSnapshot(
        nextWavePreview: _bossPreview(),
        selectedCell: const GridPosition(2, 2),
      ),
    );
    expect(find.text(_bossCopy), findsNothing);

    await _project(
      tester,
      game,
      commandDeckSnapshot(
        nextWavePreview: _bossPreview(),
        selectedTower: const PlacedTower(
          id: 1,
          type: TowerType.laser,
          position: GridPosition(2, 2),
        ),
      ),
    );
    expect(find.text(_bossCopy), findsNothing);
  });

  testWidgets('Got it persists: once-seen survives a page remount', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesFirstMissionGuideStore(
      preferences: preferences,
    );
    await store.setCompleted(true);
    final ref = await _pumpMission(tester, guideStore: store);
    final game = ref.game!;

    await _project(
      tester,
      game,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_bossCopy), findsNothing);
    expect(await store.loadSeenTips(), {ContextualTip.bossWave});

    // Reprojecting the same preview stays suppressed within the mission.
    await _project(
      tester,
      game,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    expect(find.text(_bossCopy), findsNothing);

    // A fresh page mount loads the persisted seen set before the gate clears.
    await retireMission(tester);
    await _pumpMission(tester, guideStore: store, ref: ref);
    await _project(
      tester,
      ref.game!,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    expect(find.text(_bossCopy), findsNothing);
  });

  testWidgets('starting the wave while the boss tip shows acknowledges it '
      'without blocking', (tester) async {
    final store = InMemoryFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);
    final game = ref.game!;

    await _project(
      tester,
      game,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    expect(find.text(_bossCopy), findsOneWidget);

    await tester.tap(find.byTooltip('Start Wave'));
    await tester.pump();
    await tester.pump();

    // The wave start is never blocked or delayed by the acknowledgement…
    expect(game.snapshot.phase, GamePhase.wave);
    // …and the tip counts as seen.
    expect(await store.loadSeenTips(), {ContextualTip.bossWave});
    expect(find.text(_bossCopy), findsNothing);
  });

  testWidgets('an auto-started boss wave leaves the displayed tip unseen', (
    tester,
  ) async {
    final store = InMemoryFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);
    final game = ref.game!;

    await _project(
      tester,
      game,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    expect(find.text(_bossCopy), findsOneWidget);

    // The auto-start countdown calls game.startWave() directly, bypassing
    // the chrome's onStartWave — model its snapshot transition straight
    // from the boss-preview build phase into the wave. Only "Got it" or a
    // PLAYER's wave start may acknowledge, so nothing was learned here.
    await _project(
      tester,
      game,
      commandDeckSnapshot(phase: GamePhase.wave, waveNumber: 8),
    );
    await tester.pump();

    expect(await store.loadSeenTips(), isEmpty);

    // The next eligible boss-preview build phase guides again: a player
    // who looked away during the countdown still gets the tip.
    await _project(
      tester,
      game,
      commandDeckSnapshot(waveNumber: 8, nextWavePreview: _bossPreview()),
    );
    expect(find.text(_bossCopy), findsOneWidget);
  });

  testWidgets('a wave start never acknowledges non-boss tips', (tester) async {
    final store = InMemoryFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);
    final game = ref.game!;

    // An unlock tip is displayed on the selected-cell rail when the wave
    // begins — it must stay unseen for a later build phase.
    await _project(
      tester,
      game,
      commandDeckSnapshot(selectedCell: const GridPosition(2, 2)),
    );
    expect(
      find.text('Railgun unlocked. Pierces enemies in a line.'),
      findsOneWidget,
    );

    await _project(
      tester,
      game,
      commandDeckSnapshot(phase: GamePhase.wave, waveNumber: 2),
    );
    await tester.pump();

    expect(await store.loadSeenTips(), isEmpty);
  });

  testWidgets('rapid Got it taps acknowledge exactly once', (tester) async {
    final store = InMemoryFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);

    await _project(
      tester,
      ref.game!,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );

    // Two taps land before the next frame rebuilds the tree, so the button
    // handles both: the write-through still carries one immutable snapshot.
    await tester.tap(find.text('Got it'), warnIfMissed: false);
    await tester.tap(find.text('Got it'), warnIfMissed: false);
    await tester.pump();
    await tester.pump();

    expect(find.text(_bossCopy), findsNothing);
    expect(await store.loadSeenTips(), {ContextualTip.bossWave});
  });

  testWidgets('Replay Tutorial clears seen tips so the boss tip shows again', (
    tester,
  ) async {
    // Re-entry happens on Relay: replaying the tutorial also resets the
    // HPA-412 flag, so Alpha's guide would legitimately win again — the
    // boss tip must re-appear on a non-guide stage instead.
    final progressStore = await harness.storeWithResults({
      'outpost-alpha': const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
    });
    final store = InMemoryFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(
      tester,
      guideStore: store,
      progressStore: progressStore,
      // Alpha already has a gold result, so its briefing offers a replay.
      actionLabel: 'Replay Mission',
    );

    await _project(
      tester,
      ref.game!,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump();
    expect(await store.loadSeenTips(), {ContextualTip.bossWave});

    // Back to the world map and open Settings → Replay Tutorial.
    await tester.tap(find.byKey(const ValueKey('world-map-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay Tutorial'));
    await tester.pumpAndSettle();

    expect(
      find.text('Tutorial will replay on your next Outpost Alpha run.'),
      findsOneWidget,
    );
    expect(await store.loadSeenTips(), isEmpty);
    expect(await store.loadCompleted(), isFalse);

    // Re-enter Relay with the same page/store: the boss tip is eligible
    // again (the Relay run itself is not guide-eligible).
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await harness.startStageFromBriefing(tester, mapLabel: 'Relay');
    await tester.pump();
    await tester.pump();

    await _project(
      tester,
      ref.game!,
      commandDeckSnapshot(
        stageId: 'nebula-relay',
        stageName: 'Nebula Relay',
        stageLabel: 'NR',
        nextWavePreview: _bossPreview(),
      ),
    );
    expect(find.text(_bossCopy), findsOneWidget);
  });

  testWidgets('acknowledgement write-throughs stay ordered under overlap', (
    tester,
  ) async {
    final store = _GatedFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);
    final game = ref.game!;
    const cell = GridPosition(2, 2);
    const ionCopy = 'Ion Chain unlocked. Lightning jumps between targets.';

    await _project(tester, game, commandDeckSnapshot(selectedCell: cell));
    await tester.tap(find.text('Got it'));
    await tester.pump();
    // The chained tip animates in — let the entrance finish or its Got it
    // button is still inside an IgnorePointer.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text(ionCopy), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pump();

    // Releasing the gates newest-first must still leave both tips seen:
    // an older write can never overwrite a newer one.
    while (store.pendingWrites.isNotEmpty) {
      store.pendingWrites.removeLast().complete();
      await tester.pump();
    }
    expect(await store.loadSeenTips(), {
      ContextualTip.railgun,
      ContextualTip.ionChain,
    });
  });

  testWidgets('Replay Tutorial waits for pending tip writes before clearing', (
    tester,
  ) async {
    final store = _GatedFirstMissionGuideStore(completed: true);
    final ref = await _pumpMission(tester, guideStore: store);

    await _project(
      tester,
      ref.game!,
      commandDeckSnapshot(nextWavePreview: _bossPreview()),
    );
    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(store.pendingWrites, hasLength(1));

    // Open Settings → Replay Tutorial while the ack write is in flight.
    await tester.tap(find.byKey(const ValueKey('world-map-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay Tutorial'));
    await tester.pump();

    while (store.pendingWrites.isNotEmpty) {
      store.pendingWrites.removeLast().complete();
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      find.text('Tutorial will replay on your next Outpost Alpha run.'),
      findsOneWidget,
    );
    // The clear landed after the in-flight ack — the acknowledged tip can
    // never repopulate the replayed set.
    expect(store.issuedWrites.last, isEmpty);
    expect(await store.loadSeenTips(), isEmpty);
    expect(await store.loadCompleted(), isFalse);
  });

  testWidgets('a failed Replay Tutorial restores acknowledged tips', (
    tester,
  ) async {
    final store = _FailingCompletionGuideStore(
      completed: true,
      seenTips: const {ContextualTip.bossWave},
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.testGamePage(firstMissionGuideStore: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay Tutorial'));
    await tester.pumpAndSettle();

    // The sheet never confirms, and the previously persisted seen set is
    // restored rather than left cleared behind a reported failure.
    expect(
      find.text('Tutorial will replay on your next Outpost Alpha run.'),
      findsNothing,
    );
    expect(await store.loadSeenTips(), {ContextualTip.bossWave});
    expect(await store.loadCompleted(), isTrue);
  });

  group('unlock tips on the selected-cell rail', () {
    const railgunCopy = 'Railgun unlocked. Pierces enemies in a line.';
    const ionChainCopy = 'Ion Chain unlocked. Lightning jumps between targets.';
    const droneBayCopy =
        'Drone Bay unlocked. Launches autonomous interceptors.';
    const cell = GridPosition(2, 2);

    PlacedTower placedTower(TowerType type, int id) =>
        PlacedTower(id: id, type: type, position: GridPosition(2, 2 + id));

    testWidgets('tip anchors to the rail card; no Wave pill is present in '
        'this dock branch', (tester) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);

      await _project(
        tester,
        ref.game!,
        commandDeckSnapshot(selectedCell: cell),
      );

      expect(find.text(railgunCopy), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      // The selected-cell branch replaces the idle bar: no Wave pill exists
      // to obstruct, ever.
      expect(find.byTooltip('Start Wave'), findsNothing);

      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump();

      expect(find.text(railgunCopy), findsNothing);
      // The next unlock candidate chains in immediately.
      expect(find.text(ionChainCopy), findsOneWidget);
      expect(await store.loadSeenTips(), {ContextualTip.railgun});
    });

    testWidgets(
      'offscreen Drone Bay card is revealed once at 360x640 and 1.3x text '
      'scale, with Got it reachable',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        // Everything up to Drone Bay already seen: Drone Bay is the one
        // candidate, and its card sits past the 360px viewport's end.
        final preloaded = InMemoryFirstMissionGuideStore(
          completed: true,
          seenTips: {
            ContextualTip.railgun,
            ContextualTip.ionChain,
            ContextualTip.nanite,
            ContextualTip.gravityWell,
          },
        );
        final ref = await _pumpMission(tester, guideStore: preloaded);
        final game = ref.game!;

        await _project(tester, game, commandDeckSnapshot(selectedCell: cell));
        // The reveal animation's ticker starts in the mount frame's
        // post-frame callbacks, so its first tick lands one frame later;
        // give it its full 240ms window before asserting.
        await tester.pump(const Duration(milliseconds: 260));
        await tester.pump();

        expect(find.text(droneBayCopy), findsOneWidget);
        final card = tester.getRect(
          find.byKey(const ValueKey('tower-card-droneBay')),
        );
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(360));
        final gotIt = tester.getRect(find.text('Got it'));
        expect(gotIt.left, greaterThanOrEqualTo(0));
        expect(gotIt.right, lessThanOrEqualTo(360));
        expect(gotIt.top, greaterThanOrEqualTo(0));

        await tester.tap(find.text('Got it'));
        await tester.pump();
        await tester.pump();
        expect(await preloaded.loadSeenTips(), {
          ContextualTip.railgun,
          ContextualTip.ionChain,
          ContextualTip.nanite,
          ContextualTip.gravityWell,
          ContextualTip.droneBay,
        });
      },
    );

    testWidgets(
      'dock branch transitions with the tip active never duplicate the card '
      'GlobalKey',
      (tester) async {
        final store = InMemoryFirstMissionGuideStore(completed: true);
        final ref = await _pumpMission(tester, guideStore: store);
        final game = ref.game!;

        await _project(tester, game, commandDeckSnapshot(selectedCell: cell));
        expect(find.text(railgunCopy), findsOneWidget);

        // Deselect → idle branch (persistent rail, no anchor) runs through
        // the AnimatedSwitcher, then re-select → build branch again.
        await _project(tester, game, commandDeckSnapshot());
        await _project(tester, game, commandDeckSnapshot(selectedCell: cell));

        expect(tester.takeException(), isNull);
        expect(find.text(railgunCopy), findsOneWidget);
      },
    );

    testWidgets('placing a tower teaches its unlock tip without Got it', (
      tester,
    ) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);
      final game = ref.game!;

      // A snapshot fact: a Railgun is on the board. The learned union must
      // acknowledge it post-frame with no explicit Got it.
      await _project(
        tester,
        game,
        commandDeckSnapshot(placedTowers: [placedTower(TowerType.railgun, 1)]),
      );
      await tester.pump();
      expect(await store.loadSeenTips(), {ContextualTip.railgun});

      // Selecting a cell now skips Railgun: its lesson is learned.
      await _project(
        tester,
        game,
        commandDeckSnapshot(
          selectedCell: cell,
          placedTowers: [placedTower(TowerType.railgun, 1)],
        ),
      );
      expect(find.text(railgunCopy), findsNothing);
      expect(find.text(ionChainCopy), findsOneWidget);
    });
  });

  group('specialization and targeting tips', () {
    const specCopy =
        'Specialization ready. Choose one of two ways to evolve this tower.';
    const targetingCopy =
        'Targeting modes. Choose which enemies this tower attacks first.';
    final bubble = find.byKey(
      const ValueKey('first-mission-guide-callout-bubble'),
    );

    PlacedTower levelTwoTower({
      GridPosition position = const GridPosition(2, 11),
    }) => PlacedTower(
      id: 7,
      type: TowerType.railgun,
      position: position,
      level: 2,
    );

    testWidgets(
      'nothing selected: specialization points at the qualifying tower cell '
      'and never covers the Wave pill',
      (tester) async {
        final store = InMemoryFirstMissionGuideStore(completed: true);
        final ref = await _pumpMission(tester, guideStore: store);

        await _project(
          tester,
          ref.game!,
          // Railgun specialization costs 210 — above the fixture's 150
          // gold — so cover it for the tip to be eligible at all.
          commandDeckSnapshot(gold: 300, placedTowers: [levelTwoTower()]),
        );

        expect(find.text(specCopy), findsOneWidget);
        expect(find.text('Got it'), findsOneWidget);
        // The idle dock is live with nothing selected, so the board-cell
        // bubble must dodge the Wave pill.
        expect(
          tester
              .getRect(bubble)
              .intersect(tester.getRect(find.byTooltip('Start Wave'))),
          isEmpty,
        );
      },
    );

    testWidgets(
      'selecting the qualifying tower anchors specialization at its radial '
      'progression button, clear of the Wave pill',
      (tester) async {
        final store = InMemoryFirstMissionGuideStore(completed: true);
        final ref = await _pumpMission(tester, guideStore: store);
        final tower = levelTwoTower();

        await _project(
          tester,
          ref.game!,
          // Railgun specialization costs 210 — above the fixture's 150
          // gold — so cover it for the tip to be eligible at all.
          commandDeckSnapshot(
            gold: 300,
            placedTowers: [tower],
            selectedTower: tower,
            selectedTowerStats: GameBalance.towerStats(
              TowerType.railgun,
              level: 2,
            ),
          ),
        );

        expect(find.text(specCopy), findsOneWidget);
        final specialize = find.byTooltip('Specialize tower');
        expect(specialize, findsOneWidget);
        expect(
          tester.getRect(bubble).intersect(tester.getRect(specialize)),
          isEmpty,
          reason: 'the bubble must leave the progression button tappable',
        );
        expect(
          tester
              .getRect(bubble)
              .intersect(tester.getRect(find.byTooltip('Start Wave'))),
          isEmpty,
          reason: 'a bottom-row radial tip must never cover the Wave pill',
        );
      },
    );

    testWidgets(
      'a selected level-1 tower yields targeting at the real targeting '
      'button, never another tower\u2019s Upgrade',
      (tester) async {
        final store = InMemoryFirstMissionGuideStore(completed: true);
        final ref = await _pumpMission(tester, guideStore: store);
        final qualifying = levelTwoTower(position: const GridPosition(2, 2));
        final level1 = PlacedTower(
          id: 8,
          type: TowerType.laser,
          position: const GridPosition(5, 8),
        );

        await _project(
          tester,
          ref.game!,
          commandDeckSnapshot(
            placedTowers: [qualifying, level1],
            selectedTower: level1,
            selectedTowerStats: GameBalance.towerStats(
              TowerType.laser,
              level: 1,
            ),
          ),
        );

        expect(find.text(specCopy), findsNothing);
        expect(find.text(targetingCopy), findsOneWidget);
        final button = find.byTooltip('Targeting: First. Change targeting');
        expect(button, findsOneWidget);
        expect(
          tester.getRect(bubble).intersect(tester.getRect(button)),
          isEmpty,
          reason: 'the bubble must leave the targeting button tappable',
        );
        expect(
          tester
              .getRect(bubble)
              .intersect(tester.getRect(find.byTooltip('Start Wave'))),
          isEmpty,
        );
      },
    );

    testWidgets('the targeting bubble drops below the radial when room allows, '
        'clearing Inspect and Salvage', (tester) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);
      // A top-row tower: its radial anchors high, leaving the strip
      // below the targeting button free — the bubble belongs there
      // instead of over the Inspect/Salvage row above it.
      final level1 = PlacedTower(
        id: 8,
        type: TowerType.laser,
        position: const GridPosition(5, 1),
      );

      await _project(
        tester,
        ref.game!,
        commandDeckSnapshot(
          placedTowers: [level1],
          selectedTower: level1,
          selectedTowerStats: GameBalance.towerStats(TowerType.laser, level: 1),
        ),
      );

      expect(find.text(targetingCopy), findsOneWidget);
      final bubbleRect = tester.getRect(bubble);
      final targeting = tester.getRect(
        find.byTooltip('Targeting: First. Change targeting'),
      );
      expect(
        bubbleRect.top,
        greaterThanOrEqualTo(targeting.bottom),
        reason:
            'with room below the targeting row the bubble must not '
            'sit over the Inspect/Salvage row above it',
      );
      expect(
        bubbleRect.intersect(tester.getRect(find.byTooltip('Inspect tower'))),
        isEmpty,
      );
      expect(
        bubbleRect.intersect(
          tester.getRect(find.byKey(const ValueKey('radial-salvage-8'))),
        ),
        isEmpty,
      );
    });

    testWidgets('targeting Got it persists across a page remount', (
      tester,
    ) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);
      final level1 = PlacedTower(
        id: 8,
        type: TowerType.laser,
        position: const GridPosition(5, 8),
      );
      GameSnapshot withSelection() => commandDeckSnapshot(
        placedTowers: [level1],
        selectedTower: level1,
        selectedTowerStats: GameBalance.towerStats(TowerType.laser, level: 1),
      );

      await _project(tester, ref.game!, withSelection());
      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump();

      expect(find.text(targetingCopy), findsNothing);
      expect(await store.loadSeenTips(), {ContextualTip.targeting});

      // A fresh page mount reloads the persisted set before first build.
      await retireMission(tester);
      await _pumpMission(tester, guideStore: store, ref: ref);
      await _project(tester, ref.game!, withSelection());
      expect(find.text(targetingCopy), findsNothing);
    });

    testWidgets('starting the wave with the targeting tip up acknowledges '
        'nothing but the wave start', (tester) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);
      final game = ref.game!;
      final level1 = PlacedTower(
        id: 8,
        type: TowerType.laser,
        position: const GridPosition(5, 8),
      );
      GameSnapshot withSelection() => commandDeckSnapshot(
        placedTowers: [level1],
        selectedTower: level1,
        selectedTowerStats: GameBalance.towerStats(TowerType.laser, level: 1),
      );

      await _project(tester, game, withSelection());
      expect(find.text(targetingCopy), findsOneWidget);
      // The idle bar is live with the selection, so Wave is startable.
      expect(find.byTooltip('Start Wave'), findsOneWidget);

      await tester.tap(find.byTooltip('Start Wave'));
      await tester.pump();
      await tester.pump();

      // The wave starts and the tip disappears for its duration — only the
      // boss tip may ride the start-wave acknowledgement channel.
      expect(game.snapshot.phase, GamePhase.wave);
      expect(find.text(targetingCopy), findsNothing);
      expect(
        await store.loadSeenTips(),
        isNot(contains(ContextualTip.targeting)),
      );

      // Back to a build snapshot with the same selection: the tip is still
      // unseen, so it guides again.
      game.stateNotifier.value = withSelection();
      await tester.pump();
      await tester.pump();
      expect(find.text(targetingCopy), findsOneWidget);
    });

    testWidgets('no contextual tip over the modal tower inspector', (
      tester,
    ) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);
      final level1 = PlacedTower(
        id: 8,
        type: TowerType.laser,
        position: const GridPosition(5, 5),
      );
      Future<GameSnapshot> withSelection() async {
        await _project(
          tester,
          ref.game!,
          commandDeckSnapshot(
            placedTowers: [level1],
            selectedTower: level1,
            selectedTowerStats: GameBalance.towerStats(
              TowerType.laser,
              level: 1,
            ),
          ),
        );
        return ref.game!.stateNotifier.value;
      }

      await withSelection();
      expect(find.text(targetingCopy), findsOneWidget);

      // Opening the inspector through the radial's Inspect action must
      // yield the tip to the modal.
      await tester.tap(find.byTooltip('Inspect tower'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(find.text(targetingCopy), findsNothing);

      // Dismissing the barrier restores selection: the still-unseen tip
      // may guide again.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(find.text(targetingCopy), findsOneWidget);
    });

    testWidgets(
      'specialized and retargeted towers auto-acknowledge their tips',
      (tester) async {
        final store = InMemoryFirstMissionGuideStore(completed: true);
        final ref = await _pumpMission(tester, guideStore: store);

        // Snapshot facts alone — the bubble never showed — retire both
        // lessons post-frame.
        await _project(
          tester,
          ref.game!,
          commandDeckSnapshot(
            placedTowers: [
              PlacedTower(
                id: 7,
                type: TowerType.laser,
                position: const GridPosition(2, 2),
                level: 2,
                specialization: GameBalance.specializationsFor(
                  TowerType.laser,
                ).first,
              ),
              PlacedTower(
                id: 8,
                type: TowerType.laser,
                position: const GridPosition(3, 4),
                targetingMode: TowerTargetingMode.strongest,
              ),
            ],
          ),
        );
        await tester.pump();

        expect(find.text(specCopy), findsNothing);
        expect(find.text(targetingCopy), findsNothing);
        expect(
          await store.loadSeenTips(),
          containsAll({ContextualTip.specialization, ContextualTip.targeting}),
        );
      },
    );

    testWidgets('a multi-fact snapshot acknowledges with one store write', (
      tester,
    ) async {
      final store = _CountingFirstMissionGuideStore(completed: true);
      final ref = await _pumpMission(tester, guideStore: store);

      await _project(
        tester,
        ref.game!,
        commandDeckSnapshot(
          placedTowers: [
            PlacedTower(
              id: 7,
              type: TowerType.laser,
              position: const GridPosition(2, 2),
              level: 2,
              specialization: GameBalance.specializationsFor(
                TowerType.laser,
              ).first,
            ),
            PlacedTower(
              id: 8,
              type: TowerType.laser,
              position: const GridPosition(3, 4),
              targetingMode: TowerTargetingMode.strongest,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(store.setSeenTipsCalls, 1);
      expect(
        await store.loadSeenTips(),
        containsAll({ContextualTip.specialization, ContextualTip.targeting}),
      );
    });
  });

  group('stage-modifier briefing tip', () {
    const modifierCopy =
        'Stage modifier. These conditions change how this mission plays.';
    final bubble = find.byKey(
      const ValueKey('first-mission-guide-callout-bubble'),
    );

    const goldResult = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);

    /// Pumps the page onto the world map (no game started) with Relay
    /// already unlocked via a committed Alpha gold result.
    Future<void> pumpMap(
      WidgetTester tester, {
      required FirstMissionGuideStore guideStore,
      Map<String, StageResult> results = const {'outpost-alpha': goldResult},
      double textScaleFactor = 1,
    }) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (textScaleFactor != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
      }
      final progressStore = await harness.storeWithResults(results);
      await tester.pumpWidget(
        harness.testGamePage(
          progressStore: progressStore,
          firstMissionGuideStore: guideStore,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openBriefing(WidgetTester tester, String mapLabel) async {
      await tester.ensureVisible(find.text(mapLabel));
      await tester.tap(find.text(mapLabel));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Start Mission'), findsOneWidget);
    }

    Future<void> dismissBriefing(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
    }

    /// The bubble must never sit over its own anchor's interior or the
    /// sheet's launch action / dismiss control.
    void expectBubbleClearOfControls(WidgetTester tester) {
      final bubbleRect = tester.getRect(bubble);
      final tile = tester.getRect(
        find.byKey(const ValueKey('briefing-modifier')),
      );
      expect(
        bubbleRect.top >= tile.bottom || bubbleRect.bottom <= tile.top,
        isTrue,
        reason: 'the bubble must place against the modifier tile\u2019s edges',
      );
      expect(
        bubbleRect.intersect(tester.getRect(find.byTooltip('Start Mission'))),
        isEmpty,
        reason: 'the bubble must leave Start Mission tappable',
      );
      expect(
        bubbleRect.intersect(tester.getRect(find.byTooltip('Dismiss'))),
        isEmpty,
        reason: 'the bubble must leave the dismiss control tappable',
      );
    }

    testWidgets(
      'a modified briefing shows the once-only tip anchored at the modifier '
      'tile, exactly one callout overall',
      (tester) async {
        final store = InMemoryFirstMissionGuideStore(completed: true);
        await pumpMap(tester, guideStore: store);
        await openBriefing(tester, 'Relay');

        expect(find.text(modifierCopy), findsOneWidget);
        expect(find.text('Got it'), findsOneWidget);
        // At most one visible tip overall: the briefing route owns the only
        // candidate while it is open.
        expect(find.byType(ContextualTipCallout), findsOneWidget);
        expectBubbleClearOfControls(tester);
        // The modifier tile's effect copy is untouched beneath the tip.
        expect(find.byKey(const ValueKey('briefing-modifier')), findsOneWidget);
      },
    );

    testWidgets("Alpha's Standard Conditions briefing shows no modifier tip", (
      tester,
    ) async {
      // A fresh campaign: Alpha's briefing offers Start Mission.
      final store = InMemoryFirstMissionGuideStore(completed: true);
      await pumpMap(tester, guideStore: store, results: const {});
      await openBriefing(tester, 'Alpha');

      expect(find.text(modifierCopy), findsNothing);
      expect(find.text('Got it'), findsNothing);
      expect(find.byType(ContextualTipCallout), findsNothing);
    });

    testWidgets('leaving the briefing without Got it leaves the tip unseen '
        '(reopen, launch and page remount all keep it)', (tester) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      await pumpMap(tester, guideStore: store);

      // Dismiss without Got it.
      await openBriefing(tester, 'Relay');
      expect(find.text(modifierCopy), findsOneWidget);
      await dismissBriefing(tester);
      expect(await store.loadSeenTips(), isEmpty);

      // Reopen: still unseen.
      await openBriefing(tester, 'Relay');
      expect(find.text(modifierCopy), findsOneWidget);

      // Launch without Got it: starting the mission is not an
      // acknowledgement either.
      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pump();
      await tester.pump();
      expect(await store.loadSeenTips(), isEmpty);
      await tester.tap(find.byKey(const ValueKey('world-map-action')));
      await tester.pumpAndSettle();
      await openBriefing(tester, 'Relay');
      expect(find.text(modifierCopy), findsOneWidget);

      // A full page remount ("restart") still shows it.
      await dismissBriefing(tester);
      await tester.pumpWidget(
        harness.testGamePage(
          firstMissionGuideStore: store,
          progressStore: await harness.storeWithResults({
            'outpost-alpha': goldResult,
          }),
        ),
      );
      await tester.pumpAndSettle();
      await openBriefing(tester, 'Relay');
      expect(find.text(modifierCopy), findsOneWidget);
      expect(await store.loadSeenTips(), isEmpty);
    });

    testWidgets(
      'Got it hides the tip immediately inside the open sheet and persists '
      'across reopen and remount',
      (tester) async {
        final preferences = await SharedPreferences.getInstance();
        final store = SharedPreferencesFirstMissionGuideStore(
          preferences: preferences,
        );
        await store.setCompleted(true);
        await pumpMap(tester, guideStore: store);
        await openBriefing(tester, 'Relay');
        expect(find.text(modifierCopy), findsOneWidget);

        await tester.tap(find.text('Got it'));
        await tester.pump();
        await tester.pump();

        // Gone immediately while the sheet is still open.
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(find.text(modifierCopy), findsNothing);
        expect(await store.loadSeenTips(), {ContextualTip.stageModifier});

        // Reopen: the acknowledged tip stays suppressed.
        await dismissBriefing(tester);
        await openBriefing(tester, 'Relay');
        expect(find.text(modifierCopy), findsNothing);
        expect(find.byType(ContextualTipCallout), findsNothing);

        // And after a full page remount reading the persisted set.
        await dismissBriefing(tester);
        await tester.pumpWidget(
          harness.testGamePage(
            firstMissionGuideStore: store,
            progressStore: await harness.storeWithResults({
              'outpost-alpha': goldResult,
            }),
          ),
        );
        await tester.pumpAndSettle();
        await openBriefing(tester, 'Relay');
        expect(find.text(modifierCopy), findsNothing);
      },
    );

    testWidgets('a multi-modifier stage still shows exactly one tip', (
      tester,
    ) async {
      // Void Bastion carries two modifiers; only ONE tip may render.
      final store = InMemoryFirstMissionGuideStore(completed: true);
      await pumpMap(
        tester,
        guideStore: store,
        results: {
          'outpost-alpha': goldResult,
          'nebula-relay': goldResult,
          'asteroid-foundry': goldResult,
          'aurora-gate': goldResult,
        },
      );
      await openBriefing(tester, 'Bastion');

      expect(find.text(modifierCopy), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(find.byType(ContextualTipCallout), findsOneWidget);
      expectBubbleClearOfControls(tester);
    });

    testWidgets('360x640 at 1.3x text scale keeps the tip and launch action '
        'independently tappable', (tester) async {
      final store = InMemoryFirstMissionGuideStore(completed: true);
      await pumpMap(tester, guideStore: store, textScaleFactor: 1.3);
      await openBriefing(tester, 'Relay');

      expect(find.text(modifierCopy), findsOneWidget);
      expectBubbleClearOfControls(tester);
      final bubbleRect = tester.getRect(bubble);
      expect(bubbleRect.left, greaterThanOrEqualTo(0));
      expect(bubbleRect.right, lessThanOrEqualTo(360));
      expect(bubbleRect.top, greaterThanOrEqualTo(0));

      // Both controls answer their own taps: Got it retires the tip and
      // the launch action still pops the sheet to start the mission.
      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump();
      expect(find.text(modifierCopy), findsNothing);
      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
      expect(await store.loadSeenTips(), {ContextualTip.stageModifier});
      // Retire the started mission's game loop.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
