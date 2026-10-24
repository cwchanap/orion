import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/contextual_tips.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:orion/game/orion_defense_game.dart';
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
}
