import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/ui/run_module_draft_panel.dart';
import 'package:orion/game/ui/world_map_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/command_deck_fixtures.dart';

/// Common page shell for widget tests. Defaults to a no-op feedback service
/// so ordinary tests never touch the native audio/haptics layer.
Widget testGamePage({
  CampaignProgressStore? progressStore,
  Future<CampaignProgressStore> Function()? progressStoreLoader,
  FeedbackPreferencesStore? feedbackPreferencesStore,
  ValueChanged<OrionDefenseGame>? onGameCreated,
  GameFeedback gameFeedback = const NoOpGameFeedback(),
}) {
  return MaterialApp(
    home: OrionGamePage(
      progressStore: progressStore,
      progressStoreLoader: progressStoreLoader,
      feedbackPreferencesStore: feedbackPreferencesStore,
      onGameCreated: onGameCreated,
      gameFeedback: gameFeedback,
    ),
  );
}

Future<void> startStageFromBriefing(
  WidgetTester tester, {
  String mapLabel = 'Alpha',
  String actionLabel = 'Launch Mission',
}) async {
  await tester.tap(find.text(mapLabel));
  await tester.pumpAndSettle();
  expect(find.text(actionLabel), findsOneWidget);
  await tester.tap(find.text(actionLabel));
  await tester.pump();
}

void expectSemanticsLabel(WidgetTester tester, Pattern label, Matcher matcher) {
  final handle = tester.ensureSemantics();
  try {
    expect(find.bySemanticsLabel(label), matcher);
  } finally {
    handle.dispose();
  }
}

Future<InMemoryCampaignProgressStore> storeWithResults(
  Map<String, StageResult> results,
) async {
  final store = InMemoryCampaignProgressStore(
    knownStages: OrionCampaign.stages,
  );
  await store.save(
    CampaignSave(
      progress: CampaignProgress(bestResultsByStageId: results),
      techTree: CampaignTechTree(),
    ),
  );
  return store;
}

/// A [FeedbackPreferencesStore] whose [load] completes only when [complete]
/// is called, so a test can observe the window between campaign loading
/// finishing (_isLoading clearing) and the feedback preference store
/// resolving (_feedbackPreferencesLoaded flipping). The existing
/// [_DelayedFeedbackPreferencesStore] delays save, not load; this is the
/// load-side counterpart for the lifecycle-race regression.
class _LoadDelayedFeedbackPreferencesStore implements FeedbackPreferencesStore {
  _LoadDelayedFeedbackPreferencesStore(this._value);

  final FeedbackPreferences _value;
  final Completer<FeedbackPreferences> _loadCompleter =
      Completer<FeedbackPreferences>();

  void complete() {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete(_value);
    }
  }

  @override
  Future<FeedbackPreferences> load() => _loadCompleter.future;

  @override
  Future<void> save(FeedbackPreferences preferences) async {}
}

void main() {
  // The page now builds a default SharedPreferences-backed feedback store
  // whenever a test does not inject one, so every test needs the in-memory
  // plugin mock. Tests that seed specific values call setMockInitialValues
  // themselves after this, overriding the empty default.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('boots into the Orion world map first', (tester) async {
    await tester.pumpWidget(testGamePage());
    await tester.pumpAndSettle();

    expect(find.text('ORION SECTOR'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('unlocked stage opens briefing before game creation', (
    tester,
  ) async {
    OrionDefenseGame? createdGame;
    await tester.pumpWidget(
      testGamePage(
        progressStore: InMemoryCampaignProgressStore(
          knownStages: OrionCampaign.stages,
        ),
        onGameCreated: (game) => createdGame = game,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Standard Conditions'), findsOneWidget);
    expect(find.text('No environmental modifiers'), findsOneWidget);
    expect(createdGame, isNull);

    await tester.tap(find.text('Launch Mission'));
    await tester.pump();
    expect(createdGame?.stage.id, 'outpost-alpha');
  });

  testWidgets('dismiss does not launch and replay shows best result', (
    tester,
  ) async {
    final store = await storeWithResults({
      'outpost-alpha': const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
    });
    OrionDefenseGame? createdGame;
    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (game) => createdGame = game,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('Best: Silver • 14 base health'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(createdGame, isNull);
  });

  testWidgets(
    'briefing uses stage art and preserves committed blueprint copy',
    (tester) async {
      final store = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 5,
        ),
      });
      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('sector-stage-outpost-alpha')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
      expect(
        find.text('Blueprint recovered: Relay Calibration'),
        findsOneWidget,
      );
      expect(find.text('Replay Mission'), findsOneWidget);
      expect(find.byType(OrionAtlasSprite), findsWidgets);
    },
  );

  testWidgets('every modified stage shows its accepted briefing copy', (
    tester,
  ) async {
    final results = {
      for (final stage in OrionCampaign.stages)
        stage.id: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
    };
    final store = await storeWithResults(results);
    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    for (final stage in OrionCampaign.stages.skip(1)) {
      await tester.tap(find.text(stage.mapLabel));
      await tester.pumpAndSettle();
      for (final modifier in stage.modifiers) {
        final metadata = StageModifierMetadata.forModifier(modifier);
        expect(find.text(metadata.title), findsOneWidget);
        expect(find.text(metadata.description), findsOneWidget);
      }
      if (stage.id == 'salvage-rift') {
        expect(
          find.text('Reward earned: +${GameBalance.salvageRiftGoldBonus} Gold'),
          findsOneWidget,
        );
      }
      if (stage.id == 'void-bastion') {
        expect(
          find.text('Reward earned: +${GameBalance.voidBastionHealthBonus} HP'),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(find.text('Dismiss'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('briefing scrolls on a compact portrait surface', (tester) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await storeWithResults({
      for (final stage in OrionCampaign.stages)
        stage.id: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
    });
    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Replay Mission'));
    await tester.pump();

    expect(find.text('Replay Mission'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'briefing action stays reachable at 1.3x text across approved portraits',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final size in const [
        Size(375, 812),
        Size(390, 844),
        Size(430, 932),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: OrionGamePage(
              progressStore: InMemoryCampaignProgressStore(
                knownStages: OrionCampaign.stages,
              ),
              feedbackPreferencesStore: InMemoryFeedbackPreferencesStore(),
              gameFeedback: const NoOpGameFeedback(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alpha'));
        await tester.pump();
        expect(find.text('Outpost Alpha'), findsOneWidget);

        final action = find.text('Launch Mission');
        await tester.ensureVisible(action);
        await tester.pump();
        final actionRect = tester.getRect(action);
        expect(actionRect.left, greaterThanOrEqualTo(0));
        expect(actionRect.top, greaterThanOrEqualTo(0));
        expect(actionRect.right, lessThanOrEqualTo(size.width));
        expect(actionRect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets('next-wave scanner follows the build interaction flow', (
    tester,
  ) async {
    final store = await storeWithResults({
      for (final stage in OrionCampaign.stages)
        stage.id: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
    });
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (value) => game = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay Mission'));
    await tester.pump();

    expect(find.byKey(const ValueKey('mission-status-hud')), findsOneWidget);
    expect(find.byType(NextWaveScanner), findsOneWidget);
    expect(
      _activeIgnorePointerAncestorsOf(find.byType(NextWaveScanner)),
      findsNothing,
    );
    expect(find.textContaining('Environment:'), findsNothing);

    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );
    final formerExpandedRect = tester.getRect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
    );

    final buildSnapshot = game!.snapshot;
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: buildSnapshot.gold,
      baseHealth: buildSnapshot.baseHealth,
      startingBaseHealth: buildSnapshot.startingBaseHealth,
      waveNumber: buildSnapshot.waveNumber,
      waveTotal: buildSnapshot.waveTotal,
      stageId: buildSnapshot.stageId,
      stageName: buildSnapshot.stageName,
      stageLabel: buildSnapshot.stageLabel,
      unlockedTowerTypes: buildSnapshot.unlockedTowerTypes,
      stageModifiers: buildSnapshot.stageModifiers,
      nextWavePreview: buildSnapshot.nextWavePreview,
      selectedCell: const GridPosition(1, 1),
      selectedTower: buildSnapshot.selectedTower,
      selectedTowerStats: buildSnapshot.selectedTowerStats,
      feedback: buildSnapshot.feedback,
      isPaused: buildSnapshot.isPaused,
      speedMultiplier: buildSnapshot.speedMultiplier,
      autoStartEnabled: buildSnapshot.autoStartEnabled,
      autoStartCountdownRemaining: buildSnapshot.autoStartCountdownRemaining,
      pendingRunModuleOffer: buildSnapshot.pendingRunModuleOffer,
      acquiredRunModules: buildSnapshot.acquiredRunModules,
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsNothing,
    );
    // The old expanded detector must be gone before the fade settles, so the
    // board/build rail receives taps in the former 212 x 168 area.
    await tester.tapAt(formerExpandedRect.center);
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    game!.startWave();
    await tester.pump();
    expect(find.byType(NextWaveScanner), findsNothing);

    game!.stateNotifier.value = commandDeckSnapshot(
      nextWavePreview: commandDeckPreview(),
      pendingRunModuleOffer: RunModuleOffer(
        offerId: 1,
        draftNumber: 1,
        draftTotal: 3,
        moduleIds: const [RunModuleId.heavyCaliber],
      ),
    );
    await tester.pump();
    expect(find.byType(RunModuleDraftPanel), findsOneWidget);
    expect(find.byType(NextWaveScanner), findsNothing);
    expect(find.textContaining('Environment:'), findsNothing);
  });

  testWidgets('starts an unlocked stage from the world map', (tester) async {
    await tester.pumpWidget(testGamePage());
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Outpost Alpha'), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-status-hud')), findsOneWidget);
    expectSemanticsLabel(tester, 'Base 20 of 20', findsOneWidget);
    expectSemanticsLabel(tester, 'Credits 150', findsOneWidget);
    expectSemanticsLabel(
      tester,
      'Outpost Alpha. Wave 1 of 8, Build',
      findsOneWidget,
    );
    expect(find.textContaining('Next Wave'), findsNothing);
    expect(find.text('Start Wave'), findsOneWidget);
  });

  testWidgets('mission toast latches through null republishes', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    const feedback =
        'Not enough gold. This long mission feedback copy checks the portrait toast width cap.';
    game!.overrideFeedback(feedback);
    await tester.pump();
    expect(find.byKey(const ValueKey('mission-command-toast')), findsOneWidget);
    expect(find.text(feedback), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('command-toast'))).width,
      lessThanOrEqualTo(328),
    );

    game!.setSpeedMultiplier(2);
    await tester.pump();
    expect(find.text(feedback), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2399));
    expect(find.text(feedback), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text(feedback), findsNothing);

    game!.setSpeedMultiplier(1);
    await tester.pump();
    game!.overrideFeedback(feedback);
    await tester.pump();
    expect(find.text(feedback), findsOneWidget);
  });

  testWidgets(
    'top-right board cell stays outside interactive chrome on Android CI viewport',
    (tester) async {
      tester.view.physicalSize = const Size(411, 731);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testGamePage());
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      final gameRect = tester.getRect(find.bySubtype<GameWidget>());
      final cellSize = (gameRect.width / BoardLayout.columns).clamp(
        0.0,
        gameRect.height / BoardLayout.rows,
      );
      final boardHeight = BoardLayout.rows * cellSize;
      final boardTop = gameRect.top + (gameRect.height - boardHeight) / 2;
      const topRightCell = GridPosition(7, 0);
      final topRightCenter = Offset(
        gameRect.left + (topRightCell.column + 0.5) * cellSize,
        boardTop + (topRightCell.row + 0.5) * cellSize,
      );
      final scannerRect = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      );
      final pacingFrameRect = tester.getRect(
        find
            .descendant(
              of: find.byType(MissionPacingStrip),
              matching: find.byType(CommandFrame),
            )
            .first,
      );

      expect(
        scannerRect.contains(topRightCenter),
        isFalse,
        reason: 'Scanner $scannerRect overlaps cell center $topRightCenter.',
      );
      expect(
        pacingFrameRect.contains(topRightCenter),
        isFalse,
        reason:
            'Pacing frame $pacingFrameRect overlaps cell center $topRightCenter.',
      );
    },
  );

  testWidgets('mission screen exposes pause speed and auto-start controls', (
    tester,
  ) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester);

    expect(find.byType(MissionPacingStrip), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);

    game!.stateNotifier.value = commandDeckSnapshot(
      acquiredRunModules: const [RunModuleId.heavyCaliber],
    );
    await tester.pump();
    // The GameWidget fills the full SafeArea so cellSize is preserved.
    // The status HUD and module strip are non-interactive overlays
    // (IgnorePointer) so taps pass through to the board. The pacing strip
    // remains interactive.
    final gameRect = tester.getRect(find.bySubtype<GameWidget>());
    final safeAreaRect = tester.getRect(
      find
          .ancestor(
            of: find.bySubtype<GameWidget>(),
            matching: find.bySubtype<SafeArea>(),
          )
          .first,
    );
    expect(gameRect, equals(safeAreaRect));
    expect(
      _activeIgnorePointerAncestorsOf(
        find.byKey(const ValueKey('mission-status-hud')),
      ),
      findsOneWidget,
    );
    expect(
      _activeIgnorePointerAncestorsOf(find.byType(AcquiredRunModuleStrip)),
      findsOneWidget,
    );
    expect(
      _activeIgnorePointerAncestorsOf(find.byType(MissionPacingStrip)),
      findsNothing,
    );
  });

  testWidgets('victory panel shows earned medal and base health', (
    tester,
  ) async {
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester);

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );

    expect(find.text('Victory'), findsOneWidget);
    expect(find.text('Silver medal • Base 14/20'), findsOneWidget);
    expect(find.textContaining('Environment:'), findsNothing);
  });

  testWidgets('loss panel hides the environment reminder', (tester) async {
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester);

    final snapshot = game!.stateNotifier.value;
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.lost,
      gold: snapshot.gold,
      baseHealth: 0,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      stageModifiers: const [
        StageModifier.enemySpeedSurge,
        StageModifier.amplifiedGravityWells,
      ],
      nextWavePreview: null,
      selectedCell: snapshot.selectedCell,
      selectedTower: snapshot.selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    expect(find.text('Mission Failed'), findsOneWidget);
    expect(find.textContaining('Environment:'), findsNothing);
  });

  testWidgets('locked stage tap shows feedback and stays on map', (
    tester,
  ) async {
    OrionDefenseGame? createdGame;

    await tester.pumpWidget(
      testGamePage(onGameCreated: (game) => createdGame = game),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();

    expect(find.text('Singularity Core is locked.'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
    expect(find.text('Launch Mission'), findsNothing);
    expect(find.text('Replay Mission'), findsNothing);
    expect(createdGame, isNull);
  });

  testWidgets('reset confirmation clears campaign progress', (tester) async {
    SharedPreferences.setMockInitialValues({
      'orion.campaign.progress': CampaignProgressCodec.encode(
        CampaignSave(
          progress: _progressWithResults({
            'outpost-alpha',
            'nebula-relay',
            'asteroid-foundry',
            'aurora-gate',
          }),
          techTree: CampaignTechTree(),
        ),
      ),
    });

    await tester.pumpWidget(testGamePage());
    await tester.pumpAndSettle();

    expect(find.text('Core'), findsOneWidget);
    expectSemanticsLabel(
      tester,
      RegExp(r'Singularity Core.*Open'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Campaign'), findsOneWidget);
    expect(find.text('Clear all campaign progress?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expectSemanticsLabel(
      tester,
      RegExp(r'Singularity Core.*Locked'),
      findsOneWidget,
    );
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('reset confirmation uses command frame and keeps behavior', (
    tester,
  ) async {
    final store = await storeWithResults({
      OrionCampaign.stageOneId: const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 5,
      ),
    });
    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reset-campaign-dialog')), findsOneWidget);
    expect(find.byType(CommandFrame), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();
    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Blueprint • Locked'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to empty world map when progress load fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      testGamePage(
        progressStore: _TestCampaignProgressStore(loadError: StateError('no')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ORION SECTOR'), findsOneWidget);
    expect(find.text('Could not load campaign progress.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets(
    'Mission improving victory keeps visible progress unchanged while saving',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
        delaySaves: true,
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );

      expect(find.text('Saving result…'), findsOneWidget);
      expect(
        store.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
      );
    },
  );

  testWidgets('Mission save success publishes committed result', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  testWidgets('Mission Replay restarts the stage after a saved victory', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(find.byTooltip('Replay Mission'), findsOneWidget);

    await tester.tap(find.byTooltip('Replay Mission'));
    await tester.pumpAndSettle();

    // The mission report is gone and the stage is back in build phase.
    expect(find.text('Saved.'), findsNothing);
    expect(find.text('Start Wave'), findsOneWidget);
    expect(game!.snapshot.phase, GamePhase.build);
  });

  testWidgets(
    'stage launch derives module eligibility from committed progress',
    (tester) async {
      final store = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 5,
        ),
      });
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

      expect(game!.availableRunModules, contains(RunModuleId.relayCalibration));
    },
  );

  // The primary HPA-528 lifecycle proof: a first-clear attempt must NOT carry
  // Relay Calibration, the pending/saved reward copy must surface, and after
  // commit a Replay on the SAME game object must refresh module eligibility.
  testWidgets(
    'first-clear commit then same-game Replay refreshes module eligibility',
    (tester) async {
      final store = _TestCampaignProgressStore(delaySaves: true);
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      final firstAttemptGame = game!;
      expect(
        firstAttemptGame.availableRunModules,
        isNot(contains(RunModuleId.relayCalibration)),
      );

      await publishVictory(
        tester,
        firstAttemptGame,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      expect(find.text('Blueprint recovery pending'), findsOneWidget);
      expect(
        firstAttemptGame.availableRunModules,
        isNot(contains(RunModuleId.relayCalibration)),
      );

      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Blueprint recovered: Relay Calibration'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Replay Mission'));
      await tester.pumpAndSettle();

      expect(identical(game, firstAttemptGame), isTrue);
      expect(
        firstAttemptGame.availableRunModules,
        contains(RunModuleId.relayCalibration),
      );
      expect(find.text('Start Wave'), findsOneWidget);
    },
  );

  // Pre-existing stale-reward-on-replay regression, now fixed by the same
  // run-boundary rule that refreshes blueprints: Salvage Rift's bonus gold
  // must apply on the Replay after its first clear commits.
  testWidgets(
    'Salvage Rift first clear refreshes bonus gold on same-game Replay',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha', 'nebula-relay'}),
        delaySaves: true,
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(
        tester,
        mapLabel: 'Rift',
        actionLabel: 'Launch Mission',
      );

      expect(game!.snapshot.gold, GameBalance.startingGold);

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Replay Mission'));
      await tester.pumpAndSettle();

      expect(
        game!.snapshot.gold,
        GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
      );
    },
  );

  testWidgets(
    'fresh first-clear save failure reports Blueprint not recovered',
    (tester) async {
      final store = _TestCampaignProgressStore(
        saveError: StateError('save failed'),
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await tester.pumpAndSettle();

      expect(find.text('Blueprint not recovered'), findsOneWidget);
    },
  );

  testWidgets('failed Retry Save then success reports Blueprint recovered', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      delaySaves: true,
      failOnSaveIndices: {0},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Blueprint not recovered'), findsOneWidget);
    expect(find.byTooltip('Retry Save'), findsOneWidget);
    store.failOnSaveIndices.clear();

    await tester.tap(find.byTooltip('Retry Save'));
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(find.text('Blueprint recovered: Relay Calibration'), findsOneWidget);
  });

  testWidgets('already-cleared replay suppresses blueprint reward copy', (
    tester,
  ) async {
    final store = await storeWithResults({
      OrionCampaign.stageOneId: const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
    });
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    // A worse result on a cleared stage is retained — no first-clear reward.
    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blueprint recovery pending'), findsNothing);
    expect(find.text('Blueprint not recovered'), findsNothing);
    expect(find.text('Blueprint recovered: Relay Calibration'), findsNothing);
  });

  testWidgets('mission save composes with a subsequent tech-tree purchase', (
    tester,
  ) async {
    const expectedResult = StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    );
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(tester, game!, result: expectedResult);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(store.progress.resultFor('outpost-alpha'), expectedResult);
    await tester.tap(find.byTooltip('World Map').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tech Tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchase'));
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(store.progress.resultFor('outpost-alpha'), expectedResult);
    expect(
      store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
      isTrue,
    );
  });

  testWidgets('Mission save failure reports unchanged progress', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
      saveError: StateError('save failed'),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
    expect(find.text('Could not save campaign progress.'), findsNothing);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    );
  });

  testWidgets('Mission Retry Save retries once and can commit', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
      failOnSaveIndices: {0},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Retry Save'), findsOneWidget);
    expect(store.saveCalls, 1);
    store.failOnSaveIndices.clear();

    await tester.tap(find.byTooltip('Retry Save'));
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(store.saveCalls, 2);
    expect(find.text('Saved.'), findsOneWidget);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  testWidgets('Mission Retry Save is single-flight on rapid taps', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
      failOnSaveIndices: {0},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Retry Save'), findsOneWidget);
    expect(store.saveCalls, 1);
    store.failOnSaveIndices.clear();

    // Both taps happen before the first retry completion. The save-state
    // guard must collapse them into one additional queued write.
    final retryButton = find.byTooltip('Retry Save');
    await tester.tap(retryButton);
    await tester.tap(retryButton);
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);

    expect(store.saveCalls, 2);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(store.saveCalls, 2);
    expect(find.text('Saved.'), findsOneWidget);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  testWidgets('Mission loss does not write campaign progress', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    final snapshot = game!.stateNotifier.value;
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.lost,
      gold: snapshot.gold,
      baseHealth: 0,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      stageModifiers: snapshot.stageModifiers,
      nextWavePreview: null,
      selectedCell: null,
      selectedTower: null,
      feedback: null,
      isPaused: false,
      speedMultiplier: 1,
      autoStartEnabled: false,
      autoStartCountdownRemaining: null,
      acquiredRunModules: snapshot.acquiredRunModules,
    );
    await tester.pump();

    expect(find.text('Mission Failed'), findsOneWidget);
    expect(store.saveCalls, 0);
  });

  testWidgets('Mission Retry survives consecutive losses', (tester) async {
    // Regression: _restartFromMissionReport cleared _missionStageId, which is
    // only restored by _startStage (world-map re-launch) or _handleStageWon
    // (win). A loss does neither, so loss → Retry → loss → Retry hit the
    // `_missionStageId!` null check on the second retry.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    // First loss → Retry.
    await publishLoss(tester, game!);
    expect(find.text('Mission Failed'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(game!.snapshot.phase, GamePhase.build);

    // Second loss → Retry. Previously crashed on `_missionStageId!`.
    await publishLoss(tester, game!);
    expect(find.text('Mission Failed'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(game!.snapshot.phase, GamePhase.build);
    expect(store.saveCalls, 0);
  });

  testWidgets('Mission Retry is safe under rapid taps on a loss', (
    tester,
  ) async {
    // A fast double-tap on Retry before the report rebuilds reaches the same
    // `_missionStageId!` null assertion as the consecutive-loss path.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishLoss(tester, game!);
    final retryButton = find.byTooltip('Retry');
    expect(retryButton, findsOneWidget);

    // Both taps land before the report rebuilds.
    await tester.tap(retryButton);
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(game!.snapshot.phase, GamePhase.build);
    expect(store.saveCalls, 0);
  });

  testWidgets('Mission World Map exit stays blocked while saving', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    game!.returnToMap();
    await tester.pump();

    expect(find.text('Saving result…'), findsOneWidget);
    expect(find.text('ORION SECTOR'), findsNothing);

    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Mission failed exit leaves an unsaved breadcrumb', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      saveError: StateError('save failed'),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('World Map (Unsaved)'));
    await tester.pumpAndSettle();

    expect(find.text('ORION SECTOR'), findsOneWidget);
    expect(find.text('Mission result was not saved.'), findsOneWidget);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    );
    // The World Map derives its display from the page's in-memory _progress,
    // not the backing store. A regression that optimistically mutated
    // _progress before the save completed (e.g. reintroducing nextProgress:)
    // would show the unsaved Gold medal here while every store assertion
    // above stays green. Alpha must still display the previously committed
    // Clear result.
    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Medal • Clear'),
      findsOneWidget,
    );
    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Medal • Gold'),
      findsNothing,
    );
  });

  testWidgets('Mission delayed failure after disposal is setState safe', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delaySaves: true,
      failOnSaveIndices: {0},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');
    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.saveCalls, 1);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    );
  });

  testWidgets('blocks stage launch while a tech-tree save is in flight', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
      delaySaves: true,
      saveError: StateError('save failed'),
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tech Tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchase'));
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Relay'));
    await tester.pumpAndSettle();

    expect(find.text('ORION SECTOR'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
    expect(find.text('Launch Mission'), findsNothing);
    expect(find.text('Replay Mission'), findsNothing);

    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    await startStageFromBriefing(
      tester,
      mapLabel: 'Relay',
      actionLabel: 'Replay Mission',
    );

    expect(find.text('Start Wave'), findsOneWidget);
  });

  testWidgets(
    'persists queued tech save even if page is disposed before it runs',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        delaySaves: true,
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchase'));
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 1);
      expect(
        store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
        isTrue,
      );
    },
  );

  testWidgets(
    'failed tech save after disposal does not call setState on a defunct '
    'State',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        delaySaves: true,
        failOnSaveIndices: {0},
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchase'));
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(store.saveCalls, 1);
    },
  );

  testWidgets('retained replay result does not write a save', (tester) async {
    final store = _TestCampaignProgressStore(
      saveError: StateError('save failed'),
      progress: CampaignProgress(
        bestResultsByStageId: {
          'outpost-alpha': const StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
        },
      ),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );

    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    expect(store.saveCalls, 0);
    expect(find.text('Could not save campaign progress.'), findsNothing);
    expect(find.text('Best result already saved.'), findsOneWidget);
  });

  testWidgets(
    'failed reset retains progress after a pending save drains (serialized)',
    (tester) async {
      // Round-3 review P1/P2: the reset is serialized behind the save queue.
      // The pending save completes first (persisting its result), then the
      // reset runs and fails. Progress — including the just-saved result —
      // is retained. The generation bump is monotonic and never rolled back.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        delaySaves: true,
        resetResults: [StateError('reset failed')],
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchase'));
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // The Reset button is disabled while the save is in flight. Drain the
      // pending save first, then trigger the reset.
      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reset Campaign'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(find.text('Could not reset campaign progress.'), findsOneWidget);
      expect(store.resetCalls, 1);
      expect(store.progress.bestResultsByStageId.keys, {
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      });
      expect(
        store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
        isTrue,
      );
    },
  );

  testWidgets('successful reset after a pending save drains wipes the store', (
    tester,
  ) async {
    // Round-3 review P1/P2: the reset is serialized behind the save queue.
    // The pending save completes first (writing its data), then the reset
    // runs and wipes the store. No post-stale-save cleanup is needed
    // because the reset runs after — not racing with — the save.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
      delaySaves: true,
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tech Tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchase'));
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Drain the pending save first; the Reset button is disabled while
    // the save is in flight.
    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId, isEmpty);
    expect(store.techTree.purchased, isEmpty);
  });

  testWidgets('reset reports failure when no progress store is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      testGamePage(
        progressStoreLoader: () async => throw StateError('no store'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reset campaign progress.'), findsOneWidget);
    expect(find.text('Campaign reset.'), findsNothing);
  });

  testWidgets('reset is single-flight: a second reset is blocked', (
    tester,
  ) async {
    // Round-3 review P1: concurrent resets could move the generation
    // backwards and resurrect stale progress. The reset is now
    // single-flight — the Reset button is disabled while a reset is in
    // flight, and a second programmatic call is a no-op.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
      delayResets: true,
    );
    OrionDefenseGame? createdGame;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (game) => createdGame = game,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    // The reset is now in flight (delayed). The Reset button must be
    // disabled, so tapping it does nothing.
    expect(store.resetCalls, 1);
    expect(store.resetCompletions, isNotEmpty);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Launch Mission'), findsNothing);
    expect(find.text('Replay Mission'), findsNothing);
    expect(createdGame, isNull);

    final resetButton = find.byTooltip('Reset Campaign');
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    // No second reset was triggered.
    expect(store.resetCalls, 1);

    // Complete the in-flight reset.
    store.resetCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
  });

  testWidgets(
    'failed purchase save sets feedback on both tech tree and map views',
    (tester) async {
      // Dual-targeting feedback routing (HPA-100): a purchase save that fails
      // while on the tech tree view must set _techTreeFeedback (visible now)
      // AND _mapFeedback (breadcrumb for when the player returns to the map).
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        saveError: StateError('save failed'),
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      // _techTreeFeedback: the tech tree view shows the failure inline.
      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      // Rollback: Solar Capacitors is still purchasable (not "Purchased").
      expect(find.text('Purchase'), findsOneWidget);

      // _mapFeedback: return to the map and confirm the breadcrumb survives.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      expect(find.text('ORION SECTOR'), findsOneWidget);
    },
  );

  testWidgets(
    'successful purchase clears stale tech tree feedback from prior failure',
    (tester) async {
      // tech-tree-design.md:395 — _techTreeFeedback clears on the next
      // successful purchase. A prior failure's error must not persist on
      // screen after the retry succeeds.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
        failOnSaveIndices: {0},
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      // First purchase attempt fails (save index 0).
      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      // Rollback: still purchasable.
      expect(find.text('Purchase'), findsOneWidget);

      // Second purchase attempt succeeds (save index 1).
      await tester.tap(find.text('Purchase'));
      await tester.pumpAndSettle();

      // Stale feedback must be cleared.
      expect(find.text('Could not save campaign progress.'), findsNothing);
      // The upgrade is now purchased.
      expect(find.text('Purchase'), findsNothing);
      expect(
        store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
        isTrue,
      );

      // Round-4 review P2: the failed purchase also wrote the breadcrumb into
      // _mapFeedback. Returning to the world map after the successful retry
      // must NOT still show the stale failure.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('ORION SECTOR'), findsOneWidget);
      expect(find.text('Could not save campaign progress.'), findsNothing);
    },
  );

  testWidgets('null store marks Mission report failed without throwing', (
    tester,
  ) async {
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStoreLoader: () async => throw StateError('no store'),
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load campaign progress.'), findsOneWidget);

    await startStageFromBriefing(tester);

    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
    expect(find.text('Could not save campaign progress.'), findsNothing);
  });

  test('snapshot exposes the current tower unlocks', () {
    final session = GameSession.initial();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
    ]);

    expect(session.startWave(), isTrue);
    session.finishActiveWave();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
      TowerType.railgun,
    ]);
  });

  test('snapshot exposes stage identity and wave total', () {
    final snapshot = GameSession.initial().snapshot();

    expect(snapshot.stageId, 'outpost-alpha');
    expect(snapshot.stageName, 'Outpost Alpha');
    expect(snapshot.stageLabel, 'Alpha');
    expect(snapshot.waveTotal, 8);
  });

  test('snapshot tower unlocks cannot be mutated after capture', () {
    final snapshot = GameSession.initial().snapshot();

    expect(
      () => snapshot.unlockedTowerTypes[0] = TowerType.droneBay,
      throwsUnsupportedError,
    );
    expect(snapshot.unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
    ]);
  });

  testWidgets('Tech Tree button fires onOpenTechTree', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: const [],
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
            onOpenTechTree: () => tapped++,
          ),
        ),
      ),
    );

    // Wired callback → button is visible and tappable.
    await tester.tap(find.byTooltip('Tech Tree'));
    expect(tapped, 1);
  });

  testWidgets('Tech Tree button is hidden when onOpenTechTree is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: const [],
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Tech Tree'), findsNothing);
  });

  testWidgets(
    'tapping Tech Tree button opens TechTreeView and back returns to map',
    (tester) async {
      await tester.pumpWidget(testGamePage());
      await tester.pumpAndSettle();

      // Sanity: button is present on the world map header.
      expect(find.byTooltip('Tech Tree'), findsOneWidget);

      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.pumpAndSettle();

      // TechTreeView is now rendered (T12): its header appears and the
      // world-map header is replaced.
      expect(find.text('Campaign Tech Tree'), findsOneWidget);
      expect(find.text('ORION SECTOR'), findsNothing);

      // The back arrow returns the player to the world map.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('ORION SECTOR'), findsOneWidget);
      expect(find.text('Campaign Tech Tree'), findsNothing);
    },
  );

  testWidgets('world map shows locked, unlocked, and cleared stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(
              bestResultsByStageId: {
                'outpost-alpha': const StageResult(
                  medal: StageMedal.gold,
                  bestBaseHealth: 20,
                ),
              },
            ),
            feedback: null,
            onStageSelected: (_) {},
            onLockedStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    expect(find.text('ORION SECTOR'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Medal • Gold'),
      findsOneWidget,
    );
    expectSemanticsLabel(tester, RegExp(r'Nebula Relay.*Open'), findsOneWidget);
    expectSemanticsLabel(
      tester,
      RegExp(r'Singularity Core.*Locked'),
      findsOneWidget,
    );
  });

  testWidgets('locked stage tap uses locked callback only when locked', (
    tester,
  ) async {
    final selected = <String>[];
    final locked = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (stage) => selected.add(stage.id),
            onLockedStageSelected: (stage) => locked.add(stage.id),
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Core'));
    expect(selected, isEmpty);
    expect(locked, ['singularity-core']);

    await tester.tap(find.text('Alpha'));
    expect(selected, ['outpost-alpha']);
    expect(locked, ['singularity-core']);
  });

  testWidgets('locked stage node is disabled without locked callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    final coreInkWell = tester.widget<InkWell>(
      find.ancestor(of: find.text('Core'), matching: find.byType(InkWell)),
    );
    final alphaInkWell = tester.widget<InkWell>(
      find.ancestor(of: find.text('Alpha'), matching: find.byType(InkWell)),
    );

    expect(coreInkWell.onTap, isNull);
    expect(alphaInkWell.onTap, isNotNull);
  });

  testWidgets(
    'locked stage node is disabled while a save or reset is in flight',
    (tester) async {
      // Round-5 review P3: _StageNode._onTap previously checked isLocked
      // before isBusy, so a locked node remained tappable during save/reset
      // operations and could overwrite the "Saving…/Resetting…" breadcrumb
      // with a locked-stage message. isBusy must take precedence so every
      // node behaves consistently while the world map is disabled.
      final selected = <String>[];
      final locked = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldMapView(
              stages: OrionCampaign.stages,
              progress: CampaignProgress(),
              feedback: null,
              isSavingProgress: true,
              onStageSelected: (stage) => selected.add(stage.id),
              onLockedStageSelected: (stage) => locked.add(stage.id),
              onResetCampaign: () {},
            ),
          ),
        ),
      );

      // Tapping a locked stage while busy must not fire either callback.
      await tester.tap(find.text('Core'));
      expect(selected, isEmpty);
      expect(locked, isEmpty);

      // The busy breadcrumb is preserved, not replaced by a locked message.
      expect(find.text('Saving campaign progress…'), findsOneWidget);
      expect(find.text('Singularity Core is locked.'), findsNothing);
    },
  );

  testWidgets(
    'selected tower panel shows targeting chips reflecting the current mode',
    (tester) async {
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(onGameCreated: (created) => game = created),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      final snapshot = game!.stateNotifier.value;
      const selectedTower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        targetingMode: TowerTargetingMode.strongest,
      );
      game!.stateNotifier.value = GameSnapshot(
        phase: GamePhase.build,
        gold: snapshot.gold,
        baseHealth: snapshot.baseHealth,
        startingBaseHealth: snapshot.startingBaseHealth,
        waveNumber: snapshot.waveNumber,
        waveTotal: snapshot.waveTotal,
        stageId: snapshot.stageId,
        stageName: snapshot.stageName,
        stageLabel: snapshot.stageLabel,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
        stageModifiers: const [],
        nextWavePreview: snapshot.nextWavePreview,
        selectedCell: snapshot.selectedCell,
        selectedTower: selectedTower,
        feedback: snapshot.feedback,
        isPaused: snapshot.isPaused,
        speedMultiplier: snapshot.speedMultiplier,
        autoStartEnabled: snapshot.autoStartEnabled,
        autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
      );
      await tester.pump();

      for (final mode in TowerTargetingMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      final strongestChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Strongest'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(strongestChip.selected, isTrue);
    },
  );

  testWidgets('targeting chips are disabled during wave phase', (tester) async {
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    final snapshot = game!.stateNotifier.value;
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.wave,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      stageModifiers: const [],
      nextWavePreview: snapshot.nextWavePreview,
      selectedCell: snapshot.selectedCell,
      selectedTower: selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    final firstChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('First'), matching: find.byType(ChoiceChip)),
    );
    expect(firstChip.onSelected, isNull);
  });

  testWidgets('tapping a targeting chip invokes game.setTargetingMode', (
    tester,
  ) async {
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    final snapshot = game!.stateNotifier.value;
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
      targetingMode: TowerTargetingMode.first,
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      stageModifiers: const [],
      nextWavePreview: snapshot.nextWavePreview,
      selectedCell: snapshot.selectedCell,
      selectedTower: selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    // The game session has no real selected tower, so retargeting reports the
    // "select a tower first" feedback — proving the chip callback ran. The
    // command-deck status HUD intentionally no longer renders legacy feedback
    // copy, so assert the snapshot seam instead of a removed text label.
    await tester.tap(find.text('Weakest'));
    await tester.pump();

    expect(game!.snapshot.feedback, 'Select a tower first.');
  });

  testWidgets('selected tower panel stacks summary and actions when narrow', (
    tester,
  ) async {
    OrionDefenseGame? game;

    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    final snapshot = game!.stateNotifier.value;
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      stageModifiers: const [],
      nextWavePreview: snapshot.nextWavePreview,
      selectedCell: snapshot.selectedCell,
      selectedTower: selectedTower,
      feedback: snapshot.feedback,
      isPaused: snapshot.isPaused,
      speedMultiplier: snapshot.speedMultiplier,
      autoStartEnabled: snapshot.autoStartEnabled,
      autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    );
    await tester.pump();

    // The narrow-width branch renders the targeting picker; the "Targeting"
    // label confirms the panel built via the stacked Column layout.
    expect(find.text('Targeting'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets(
    'starting a stage after clearing salvage rift applies bonus gold',
    (tester) async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignSave(
          progress: CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'nebula-relay': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'salvage-rift': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
            },
          ),
          techTree: CampaignTechTree(),
        ),
      );

      OrionDefenseGame? game;
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();

      // Tap the salvage-rift stage node (it should be unlocked).
      await startStageFromBriefing(
        tester,
        mapLabel: 'Rift',
        actionLabel: 'Replay Mission',
      );

      expect(game, isNotNull);
      expect(
        game!.snapshot.gold,
        GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
      );
    },
  );

  testWidgets('world map shows reward teaser on uncleared side stage', (
    tester,
  ) async {
    final store = InMemoryCampaignProgressStore(
      knownStages: OrionCampaign.stages,
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    expectSemanticsLabel(
      tester,
      RegExp(r'Salvage Rift.*Reward: \+30 Gold'),
      findsOneWidget,
    );
    expectSemanticsLabel(
      tester,
      RegExp(r'Void Bastion.*Reward: \+5 HP'),
      findsOneWidget,
    );
  });

  testWidgets('world map shows earned reward label on cleared side stage', (
    tester,
  ) async {
    final store = InMemoryCampaignProgressStore(
      knownStages: OrionCampaign.stages,
    );
    await store.save(
      CampaignSave(
        progress: CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        ),
        techTree: CampaignTechTree(),
      ),
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    expectSemanticsLabel(
      tester,
      RegExp(r'Salvage Rift.*\+30 Gold'),
      findsOneWidget,
    );
  });

  testWidgets(
    'world map shows challenge badge when both side stages are cleared',
    (tester) async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignSave(
          progress: CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'nebula-relay': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'asteroid-foundry': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'aurora-gate': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'salvage-rift': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
              'void-bastion': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 1,
              ),
            },
          ),
          techTree: CampaignTechTree(),
        ),
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      expectSemanticsLabel(
        tester,
        'Challenge Badge Earned - All side stages cleared',
        findsOneWidget,
      );
    },
  );

  // HPA-528 Task 4: the Outpost Alpha node exposes the first blueprint
  // recovery through its compact glyph semantics. The label reflects
  // committed progress only — a fresh campaign reports Locked and a cleared
  // Alpha reports Recovered. Exactly one such signal exists across the map.
  testWidgets(
    'fresh world map shows Alpha blueprint locked and no recovered row',
    (tester) async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      expectSemanticsLabel(
        tester,
        RegExp(r'Outpost Alpha.*Blueprint • Locked'),
        findsOneWidget,
      );
      expectSemanticsLabel(
        tester,
        RegExp(r'Blueprint • Recovered'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'cleared Alpha world map shows blueprint recovered and no locked row',
    (tester) async {
      final store = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
      });

      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      expectSemanticsLabel(
        tester,
        RegExp(r'Outpost Alpha.*Blueprint • Recovered'),
        findsOneWidget,
      );
      expectSemanticsLabel(tester, RegExp(r'Blueprint • Locked'), findsNothing);
    },
  );

  testWidgets('Alpha briefing shows blueprint recovered line when committed', (
    tester,
  ) async {
    final store = await storeWithResults({
      OrionCampaign.stageOneId: const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 1,
      ),
    });

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Blueprint recovered: Relay Calibration'), findsOneWidget);
  });

  testWidgets('fresh Alpha briefing omits the blueprint recovered line', (
    tester,
  ) async {
    final store = InMemoryCampaignProgressStore(
      knownStages: OrionCampaign.stages,
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Blueprint recovered: Relay Calibration'), findsNothing);
  });

  testWidgets('Alpha blueprint glyph fits at 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithResults({
      OrionCampaign.stageOneId: const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 1,
      ),
    });

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Blueprint • Recovered'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // Reset proof (HPA-528 Task 4 Step 6): after a campaign reset the derived
  // blueprint unlock must disappear from BOTH surfaces — the Alpha map node
  // reverts to "Blueprint • Locked", and a fresh game launched on Alpha no
  // longer carries the Relay Calibration run module.
  testWidgets(
    'reset wipes first blueprint from map and run module eligibility',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
          'aurora-gate',
        }),
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();

      expectSemanticsLabel(
        tester,
        RegExp(r'Outpost Alpha.*Blueprint • Recovered'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Reset Campaign'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expectSemanticsLabel(
        tester,
        RegExp(r'Outpost Alpha.*Blueprint • Locked'),
        findsOneWidget,
      );
      expectSemanticsLabel(
        tester,
        RegExp(r'Blueprint • Recovered'),
        findsNothing,
      );

      await startStageFromBriefing(tester);
      expect(
        game!.availableRunModules,
        isNot(contains(RunModuleId.relayCalibration)),
      );
    },
  );

  testWidgets(
    'feedback settings reflect loaded preferences and persist toggles',
    (tester) async {
      final feedbackStore = InMemoryFeedbackPreferencesStore(
        value: const FeedbackPreferences(
          soundEffectsEnabled: false,
          hapticsEnabled: true,
        ),
      );

      await tester.pumpWidget(
        testGamePage(feedbackPreferencesStore: feedbackStore),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      SwitchListTile soundSwitch() => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Sound Effects'),
      );
      SwitchListTile hapticsSwitch() => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Haptics'),
      );
      expect(soundSwitch().value, isFalse);
      expect(hapticsSwitch().value, isTrue);

      // Toggle only Haptics off, then Done persists the draft.
      await tester.tap(find.widgetWithText(SwitchListTile, 'Haptics'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(
        feedbackStore.value,
        const FeedbackPreferences(
          soundEffectsEnabled: false,
          hapticsEnabled: false,
        ),
      );

      // Reopening Settings shows the effective saved state.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(soundSwitch().value, isFalse);
      expect(hapticsSwitch().value, isFalse);
    },
  );

  testWidgets('failed feedback save keeps values and shows breadcrumb', (
    tester,
  ) async {
    final feedbackStore = _FailingFeedbackPreferencesStore(
      value: const FeedbackPreferences(
        soundEffectsEnabled: true,
        hapticsEnabled: true,
      ),
    );

    await tester.pumpWidget(
      testGamePage(feedbackPreferencesStore: feedbackStore),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Effective values stay unchanged; the failure surfaces as a breadcrumb.
    expect(find.text('Could not save feedback settings.'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final soundSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Sound Effects'),
    );
    expect(soundSwitch.value, isTrue);
  });

  testWidgets('settings stay disabled while feedback save is in flight', (
    tester,
  ) async {
    // A slow store: save() blocks on a completer the test controls, so the
    // save stays pending until the test releases it.
    final feedbackStore = _DelayedFeedbackPreferencesStore(
      value: const FeedbackPreferences(
        soundEffectsEnabled: true,
        hapticsEnabled: true,
      ),
    );

    await tester.pumpWidget(
      testGamePage(feedbackPreferencesStore: feedbackStore),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The save is still pending: the Settings button is disabled and the
    // prior effective value is untouched.
    IconButton settingsButton() => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.settings_rounded),
    );
    expect(settingsButton().onPressed, isNull);
    expect(
      feedbackStore.value,
      const FeedbackPreferences(
        soundEffectsEnabled: true,
        hapticsEnabled: true,
      ),
    );

    // Release the save; the button re-enables and the new value is
    // effective in the reopened sheet.
    feedbackStore.saveCompletions.single.complete();
    await tester.pumpAndSettle();
    expect(settingsButton().onPressed, isNotNull);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final soundSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Sound Effects'),
    );
    expect(soundSwitch.value, isFalse);
    expect(
      feedbackStore.value,
      const FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      ),
    );
  });

  testWidgets('campaign reset leaves feedback preferences untouched', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
        'aurora-gate',
      }),
    );
    final feedbackStore = InMemoryFeedbackPreferencesStore(
      value: const FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: false,
      ),
    );

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        feedbackPreferencesStore: feedbackStore,
      ),
    );
    await tester.pumpAndSettle();
    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Blueprint • Recovered'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    // Campaign reset while the non-default feedback preferences survive.
    expectSemanticsLabel(
      tester,
      RegExp(r'Outpost Alpha.*Blueprint • Locked'),
      findsOneWidget,
    );
    expectSemanticsLabel(
      tester,
      RegExp(r'Blueprint • Recovered'),
      findsNothing,
    );
    expect(
      feedbackStore.value,
      const FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: false,
      ),
    );
  });

  testWidgets('feedback preferences load failure falls back to defaults', (
    tester,
  ) async {
    // A store whose load() throws must not block the page: defaults become
    // effective and settings still opens (with both toggles on), while the
    // store is wired so a later save can persist.
    final feedbackStore = _LoadFailingFeedbackPreferencesStore();

    await tester.pumpWidget(
      testGamePage(feedbackPreferencesStore: feedbackStore),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Sound Effects'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Haptics'),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful feedback save clears a stale failure breadcrumb', (
    tester,
  ) async {
    final feedbackStore = _FlakyFeedbackPreferencesStore(
      value: const FeedbackPreferences(
        soundEffectsEnabled: true,
        hapticsEnabled: true,
      ),
    )..failSave = true;

    await tester.pumpWidget(
      testGamePage(feedbackPreferencesStore: feedbackStore),
    );
    await tester.pumpAndSettle();

    // First save fails -> the breadcrumb appears on the world map.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save feedback settings.'), findsOneWidget);

    // Second save succeeds -> the matching breadcrumb is cleared.
    feedbackStore.failSave = false;
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save feedback settings.'), findsNothing);
  });

  testWidgets('default platform feedback reads the live preference toggles', (
    tester,
  ) async {
    // No gameFeedback is injected, so the page builds a PlatformGameFeedback
    // whose enabled-closures read _feedbackPreferences. Stub the audio and
    // haptic channels so the detached emit futures complete (with errors
    // PlatformGameFeedback swallows) instead of hanging on a missing
    // engine.
    final binding = TestWidgetsFlutterBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall call) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall call) async => throw Exception('audioplayers unavailable'),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => null,
    );

    final feedbackStore = InMemoryFeedbackPreferencesStore(
      value: const FeedbackPreferences(
        soundEffectsEnabled: true,
        hapticsEnabled: true,
      ),
    );
    OrionDefenseGame? capturedGame;
    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(
          progressStore: InMemoryCampaignProgressStore(
            knownStages: OrionCampaign.stages,
          ),
          feedbackPreferencesStore: feedbackStore,
          onGameCreated: (game) => capturedGame = game,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester);

    // Driving a feedback event exercises the page's PlatformGameFeedback
    // closures (soundEffectsEnabled/hapticsEnabled) without letting audio
    // or haptic failures escape.
    capturedGame!.gameFeedback.towerConfirmed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delayed feedback preference load: cues stay silent until the store '
    'resolves even when stored preferences are off',
    (tester) async {
      // Regression for the lifecycle race between campaign loading
      // (_isLoading clearing) and the feedback preference store resolving
      // (_feedbackPreferencesLoaded flipping). _feedbackPreferences defaults
      // to both-enabled; without gating the predicates on the loaded flag,
      // a cue fired during that window would honor the default true values
      // and violate a user's saved soundEffectsEnabled:false /
      // hapticsEnabled:false choice.
      final binding = TestWidgetsFlutterBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (MethodCall call) async => null,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (MethodCall call) async => throw Exception('audioplayers unavailable'),
      );
      final hapticCalls = <Object?>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalls.add(call.arguments);
          }
          return null;
        },
      );

      final feedbackStore = _LoadDelayedFeedbackPreferencesStore(
        const FeedbackPreferences(
          soundEffectsEnabled: false,
          hapticsEnabled: false,
        ),
      );
      OrionDefenseGame? capturedGame;
      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(
            progressStore: InMemoryCampaignProgressStore(
              knownStages: OrionCampaign.stages,
            ),
            feedbackPreferencesStore: feedbackStore,
            onGameCreated: (game) => capturedGame = game,
          ),
        ),
      );
      // Advance past campaign loading so _isLoading clears and the world map
      // becomes interactive — but the feedback store load is still pending
      // on the completer, so _feedbackPreferencesLoaded is still false.
      await tester.pumpAndSettle();

      await startStageFromBriefing(tester);
      final game = capturedGame;
      expect(game, isNotNull);

      // A cue fired during the pre-resolution window must be suppressed by
      // the loaded-flag gate, even though _feedbackPreferences still holds
      // the default both-enabled value.
      game!.gameFeedback.towerConfirmed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(hapticCalls, isEmpty);

      // Now resolve the store with both channels off. Cues must still be
      // silent — the loaded flag is now true, but the persisted values are
      // false.
      feedbackStore.complete();
      await tester.pumpAndSettle();
      game.gameFeedback.towerConfirmed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(hapticCalls, isEmpty);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion: briefing and settings sheets appear instantly on the '
    '360x640 view',
    (tester) async {
      // Geometry comes from the actual 360x640 test view, never from a
      // MediaQueryData.size wrapper above MaterialApp.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final campaignStore = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      final feedbackStore = InMemoryFeedbackPreferencesStore();

      // Inject only the accessibility state through MediaQuery; the explicit
      // no-op feedback keeps the native audio/haptics layer untouched.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: OrionGamePage(
              progressStore: campaignStore,
              feedbackPreferencesStore: feedbackStore,
              gameFeedback: const NoOpGameFeedback(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.view.physicalSize, const Size(360, 640));

      // The briefing sheet is already fully visible after a single pump — no
      // slide transition under reduced motion.
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      expect(find.text('Outpost Alpha'), findsOneWidget);
      expect(find.text('Launch Mission'), findsOneWidget);

      // Dismiss without starting the mission.
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Launch Mission'), findsNothing);

      // The Settings sheet is also visible immediately.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      expect(find.text('Follows system • On'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion status shows Off when system animations are enabled',
    (tester) async {
      final campaignStore = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      final feedbackStore = InMemoryFeedbackPreferencesStore();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: MaterialApp(
            home: OrionGamePage(
              progressStore: campaignStore,
              feedbackPreferencesStore: feedbackStore,
              gameFeedback: const NoOpGameFeedback(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Follows system • Off'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump();
  }

  fail('Condition was not met before pump limit.');
}

Future<void> publishVictory(
  WidgetTester tester,
  OrionDefenseGame game, {
  required StageResult result,
}) async {
  final snapshot = game.stateNotifier.value;
  game.stateNotifier.value = GameSnapshot(
    phase: GamePhase.won,
    gold: snapshot.gold,
    baseHealth: result.bestBaseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
    waveNumber: snapshot.waveTotal,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    stageModifiers: snapshot.stageModifiers,
    nextWavePreview: null,
    selectedCell: null,
    selectedTower: null,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    acquiredRunModules: snapshot.acquiredRunModules,
  );
  game.onStageWon?.call(StageCompletion(stage: game.stage, result: result));
  await tester.pump();
}

// Mirrors publishVictory but for the loss path: publishes a lost snapshot
// without invoking onStageWon (a loss never calls _handleStageWon), which is
// the exact condition that left _missionStageId unrestored between retries.
Future<void> publishLoss(WidgetTester tester, OrionDefenseGame game) async {
  final snapshot = game.stateNotifier.value;
  game.stateNotifier.value = GameSnapshot(
    phase: GamePhase.lost,
    gold: snapshot.gold,
    baseHealth: 0,
    startingBaseHealth: snapshot.startingBaseHealth,
    waveNumber: snapshot.waveNumber,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    stageModifiers: snapshot.stageModifiers,
    nextWavePreview: null,
    selectedCell: null,
    selectedTower: null,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    acquiredRunModules: snapshot.acquiredRunModules,
  );
  await tester.pump();
}

Finder _activeIgnorePointerAncestorsOf(Finder finder) {
  return find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) => widget is IgnorePointer && widget.ignoring,
      description: 'active IgnorePointer',
    ),
  );
}

CampaignProgress _progressWithResults(Iterable<String> stageIds) {
  return CampaignProgress(
    bestResultsByStageId: {
      for (final stageId in stageIds)
        stageId: const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    },
  );
}

class _TestCampaignProgressStore implements CampaignProgressStore {
  _TestCampaignProgressStore({
    this.loadError,
    this.saveError,
    this.delaySaves = false,
    this.delayResets = false,
    this.failOnSaveIndices = const {},
    this.resetResults = const [],
    CampaignProgress? progress,
    CampaignTechTree? techTree,
  }) : progress = progress ?? CampaignProgress(),
       techTree = techTree ?? CampaignTechTree();

  final Object? loadError;
  final Object? saveError;
  final bool delaySaves;
  final bool delayResets;
  final Set<int> failOnSaveIndices;
  final List<Object?> resetResults;
  final List<Completer<void>> saveCompletions = [];
  final List<Completer<void>> resetCompletions = [];
  CampaignProgress progress;
  CampaignTechTree techTree;
  int saveCalls = 0;
  int resetCalls = 0;

  @override
  Future<CampaignSave> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return CampaignSave(progress: progress, techTree: techTree);
  }

  @override
  Future<void> save(CampaignSave save) async {
    saveCalls += 1;

    if (delaySaves) {
      final completer = Completer<void>();
      saveCompletions.add(completer);
      await completer.future;
    }

    if (failOnSaveIndices.contains(saveCalls - 1)) {
      throw StateError('save ${saveCalls - 1} failed');
    }
    final error = saveError;
    if (error != null) {
      throw error;
    }

    progress = save.progress;
    techTree = save.techTree;
  }

  @override
  Future<void> reset() async {
    resetCalls += 1;

    if (delayResets) {
      final completer = Completer<void>();
      resetCompletions.add(completer);
      await completer.future;
    }

    final result = resetCalls - 1 < resetResults.length
        ? resetResults[resetCalls - 1]
        : null;
    if (result != null) {
      throw result;
    }

    progress = CampaignProgress();
    techTree = CampaignTechTree();
  }
}

class _FailingFeedbackPreferencesStore implements FeedbackPreferencesStore {
  _FailingFeedbackPreferencesStore({this.value = const FeedbackPreferences()});

  FeedbackPreferences value;

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    throw StateError('feedback save failed');
  }
}

class _DelayedFeedbackPreferencesStore implements FeedbackPreferencesStore {
  _DelayedFeedbackPreferencesStore({this.value = const FeedbackPreferences()});

  FeedbackPreferences value;
  final List<Completer<void>> saveCompletions = [];

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    final completer = Completer<void>();
    saveCompletions.add(completer);
    await completer.future;
    value = preferences;
  }
}

class _LoadFailingFeedbackPreferencesStore implements FeedbackPreferencesStore {
  @override
  Future<FeedbackPreferences> load() async =>
      throw StateError('feedback load failed');

  @override
  Future<void> save(FeedbackPreferences preferences) async {}
}

class _FlakyFeedbackPreferencesStore implements FeedbackPreferencesStore {
  _FlakyFeedbackPreferencesStore({this.value = const FeedbackPreferences()});

  FeedbackPreferences value;
  bool failSave = false;

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    if (failSave) {
      throw StateError('feedback save failed');
    }
    value = preferences;
  }
}
