import 'package:orion/game/ui/tower_inspector.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/board_component.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/enemy_overlay.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/contextual_tips.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/game/rules/enemy_overlay_state.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/game/rules/module_offer_picker.dart';
import 'package:orion/game/ui/acquired_run_module_control.dart';
import 'package:orion/game/ui/camp_view.dart';
import 'package:orion/game/ui/first_mission_guide_callout.dart';
import 'package:orion/game/ui/flare_view.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_report_panel.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/ui/orion_menu_shell.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/run_module_draft_panel.dart';
import 'package:orion/game/ui/world_map_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/orion_finders.dart';
import 'support/command_deck_fixtures.dart';
import 'support/reactor_rim_visual_capture.dart';
import 'support/real_fonts.dart';

/// Common page shell for widget tests. Defaults to a no-op feedback service
/// so ordinary tests never touch the native audio/haptics layer, and to an
/// already-completed first-mission guide store so the tutorial overlay only
/// appears in tests that opt in with their own store.
Widget testGamePage({
  CampaignProgressStore? progressStore,
  Future<CampaignProgressStore> Function()? progressStoreLoader,
  FeedbackPreferencesStore? feedbackPreferencesStore,
  FirstMissionGuideStore? firstMissionGuideStore,
  ModuleOfferPicker? moduleOfferPicker,
  math.Random? flareRandom,
  ValueChanged<OrionDefenseGame>? onGameCreated,
  GameFeedback gameFeedback = const NoOpGameFeedback(),
  bool startOnWorldMap = true,
}) {
  return MaterialApp(
    // The product app hides this banner; a fixture host must too, or the
    // parity evidence carries a stripe the shipped game never shows.
    debugShowCheckedModeBanner: false,
    // The real theme, not Flutter's defaults: Material components the game
    // still uses (segmented button, chips, text buttons) take their colours
    // from here, so a bare MaterialApp renders evidence fixtures that do not
    // match the shipped app.
    theme: orionThemeData,
    home: OrionGamePage(
      startOnWorldMap: startOnWorldMap,
      progressStore: progressStore,
      progressStoreLoader: progressStoreLoader,
      feedbackPreferencesStore: feedbackPreferencesStore,
      // Guide OFF unless a test opts in: a store with no written record
      // loads `null` and resolves through campaign progress — empty test
      // progress means not-completed — so the callout would cover every
      // Alpha mount/parity capture that did not ask for it.
      firstMissionGuideStore:
          firstMissionGuideStore ??
          InMemoryFirstMissionGuideStore(completed: true),
      moduleOfferPicker: moduleOfferPicker,
      flareRandom: flareRandom,
      onGameCreated: onGameCreated,
      gameFeedback: gameFeedback,
    ),
  );
}

Future<void> openResetCampaignDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reset Campaign'));
  await tester.pumpAndSettle();
}

/// Opens the briefing for [mapLabel] and taps [actionLabel]. Launch awaits
/// one queued squad write before the route pops (HPA-922 task 6), so a
/// delayed store holds the stage start hostage: pass the store's
/// save-completions list as [drainCompletions] and this helper completes the
/// launch write so the stage can mount.
Future<void> startStageFromBriefing(
  WidgetTester tester, {
  String mapLabel = 'Alpha',
  String actionLabel = 'Start Mission',
  List<Completer<void>>? drainCompletions,
}) async {
  await tester.ensureVisible(find.text(mapLabel));
  await tester.tap(find.text(mapLabel));
  await tester.pumpAndSettle();
  expect(find.byTooltip(actionLabel), findsOneWidget);
  final completionsBefore = drainCompletions?.length ?? 0;
  await tester.tap(find.byTooltip(actionLabel));
  await tester.pump();
  if (drainCompletions != null) {
    await _pumpUntil(tester, () => drainCompletions.length > completionsBefore);
    drainCompletions[completionsBefore].complete();
    // Fixed pumps: the pop animation hands off to _startStage, and the
    // mounted game then keeps a live ticker that never settles.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }
}

void expectSemanticsLabel(
  WidgetTester tester,
  Pattern label,
  Matcher matcher, {
  String? reason,
}) {
  final handle = tester.ensureSemantics();
  try {
    expect(find.bySemanticsLabel(label), matcher, reason: reason);
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
      ownedLevels: CampaignSave.starterOwnedLevels,
      squad: CampaignSave.starterSquad,
      scrip: 0,
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

  testWidgets(
    'top-row build cell remains selectable without exiting the mission',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);
      await tester.runAsync(() async {
        for (final name in [
          'reactor_rim_ui/boards/nebula.png',
          'orion_path_tiles.png',
          'orion_sprite_sheet.png',
          'orion_tower_variety_sheet.png',
          'orion_boss_sheet.png',
          // onLoad also preloads the active squad's chibis — the default
          // page mounts the starter squad.
          'characters/haruto/chibi.png',
          'characters/mio/chibi.png',
        ]) {
          await Flame.images.load(name);
        }
      });
      // A cold-mount earlier in this file can leave pending futures in the
      // descriptor memo; clear it so the warmed cache is the one used.
      OrionArtDescriptor.resetSpriteCache();
      addTearDown(Flame.images.clearCache);
      OrionDefenseGame? game;
      await tester.pumpWidget(
        testGamePage(onGameCreated: (value) => game = value),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);
      await tester.pump();
      await tester.pump();
      final rect = tester.getRect(find.bySubtype<GameWidget>());
      final point =
          rect.topLeft + game!.boardCellCenter(const GridPosition(6, 0));
      expect(game!.boardCellAt(point - rect.topLeft), const GridPosition(6, 0));
      final mapRect = tester.getRect(
        find.byKey(const ValueKey('world-map-action')),
      );
      expect(mapRect.contains(point), isFalse);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.bySubtype<GameWidget>(), findsOneWidget);
      expect(game!.stateNotifier.value.selectedCell, const GridPosition(6, 0));
    },
  );

  for (final viewSize in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('capture scene 1e fixture $viewSize', (tester) async {
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final suffix = viewSize.height < 700 ? '-compact' : '';
      // Representative scene 1e state, captured mid-drag: a buildable cell is
      // selected (rail visible), the Laser card is long-press-lifted (source
      // LIFTED, rail header DROP TO BUILD, finger ghost + cost pill airborne)
      // and the pointer hovers a valid cell (allowed candidate, resolved range
      // ring, path danger wash on the board). Real Roboto for true metrics.
      await loadRealFonts();

      // Warm Flame's global image cache BEFORE the game exists so its onLoad
      // resolves from cache instead of racing real engine decodes, which
      // never complete under the fake-async test binding.
      await tester.runAsync(() async {
        for (final name in [
          'reactor_rim_ui/boards/nebula.png',
          'orion_path_tiles.png',
          'orion_sprite_sheet.png',
          'orion_tower_variety_sheet.png',
          'orion_boss_sheet.png',
          // onLoad also preloads the active squad's chibis — the default
          // page mounts the starter squad.
          'characters/haruto/chibi.png',
          'characters/mio/chibi.png',
        ]) {
          await Flame.images.load(name);
        }
      });
      OrionArtDescriptor.resetSpriteCache();

      final boundaryKey = GlobalKey();
      OrionDefenseGame? game;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: testGamePage(onGameCreated: (created) => game = created),
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);
      // Fixed pumps from here: once the warm-cache load completes the game
      // mounts and its live loop never lets pumpAndSettle settle.
      await tester.pump();
      await tester.pump();
      expect(game!.isMounted, isTrue);
      // Restore the cold image cache: later tests were written against the
      // never-mounts-under-test-binding behavior and their pumpAndSettles
      // would hang against a live mounted game loop.
      addTearDown(Flame.images.clearCache);

      final gameRect = tester.getRect(find.bySubtype<GameWidget>());
      Offset globalFor(GridPosition cell) =>
          gameRect.topLeft + game!.boardCellCenter(cell);

      // The mounted game loop never settles under fake async, so every frame
      // wait from here on is a fixed pump.
      game!.handleBoardTap(
        globalFor(const GridPosition(2, 3)) - gameRect.topLeft,
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

      final start = tester.getCenter(
        find.byKey(const ValueKey('tower-card-haruto')),
      );
      final holdTarget = globalFor(const GridPosition(4, 5));
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(holdTarget - start);
      await tester.pump();
      await tester.pump();

      // All five 1e treatments must be live while the gesture is held.
      expect(find.text('LIFTED'), findsOneWidget);
      expect(find.text('DROP TO BUILD'), findsOneWidget);
      expect(game!.placementPreview.cell, const GridPosition(4, 5));
      expect(game!.placementPreview.allowed, isTrue);
      expect(game!.placementPreview.range, greaterThan(0));

      // PNG encoding is real async engine work; capture while held.
      await tester.runAsync(
        () => captureReactorRimFixture(boundaryKey, 'fixture-1e$suffix.png'),
      );

      await gesture.moveTo(globalFor(const GridPosition(6, 5)));
      await tester.pump();
      expect(game!.placementPreview.allowed, isFalse);
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'fixture-1e-invalid$suffix.png',
        ),
      );
      await gesture.up();
      await tester.pump();
      expect(game!.stateNotifier.value.gold, 150);
      expect(game!.stateNotifier.value.selectedTower, isNull);
      // Tear the mounted game down so its live loop ticker does not leak into
      // the tests that follow this fixture.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  for (final viewSize in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('capture scene 1a fixture $viewSize', (tester) async {
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Scene 1a is the playable HUD *over the board* — the artboard's whole
      // subject is chrome reading against a live mission. Captured from the
      // real game page rather than a chrome-only host, which could only ever
      // show the bands floating on a flat fill.
      //
      // Capture both idle build controls and a selected tower with radial actions.
      await loadRealFonts();

      // Warm Flame's global image cache BEFORE the game exists so its onLoad
      // resolves from cache instead of racing real engine decodes, which never
      // complete under the fake-async test binding.
      await tester.runAsync(() async {
        for (final name in [
          'reactor_rim_ui/boards/nebula.png',
          'orion_path_tiles.png',
          'orion_sprite_sheet.png',
          'orion_tower_variety_sheet.png',
          'orion_boss_sheet.png',
          // onLoad also preloads the active squad's chibis — the default
          // page mounts the starter squad.
          'characters/haruto/chibi.png',
          'characters/mio/chibi.png',
        ]) {
          await Flame.images.load(name);
        }
      });

      // A cold-cache test earlier in this process can leave a pending future
      // in the sprite memo; clear it so this fixture resolves against the warm
      // cache instead of waiting on a load that already failed to arrive.
      OrionArtDescriptor.resetSpriteCache();

      final suffix = viewSize.height < 700 ? '-compact' : '';
      final boundaryKey = GlobalKey();
      OrionDefenseGame? game;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: testGamePage(onGameCreated: (created) => game = created),
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);
      // Fixed pumps from here: the mounted game's live loop never settles, so
      // pumpAndSettle would hang. The briefing is a route over the game page
      // and leaves on a 220ms transition, so give it real frames -- two bare
      // pumps capture the sheet still sitting on top of the scene.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game!.isMounted, isTrue);
      addTearDown(Flame.images.clearCache);

      // Guard the state, not merely the widgets: 'Start Wave' lives in the dock
      // *underneath* the briefing, so asserting it alone would pass on a
      // capture of the briefing sheet. The briefing being gone is the check.
      expect(
        find.byTooltip('Start Mission'),
        findsNothing,
        reason: 'the briefing route is still over the scene',
      );
      expect(find.bySubtype<GameWidget>(), findsOneWidget);
      expect(find.byKey(const ValueKey('mission-status-hud')), findsOneWidget);
      expect(find.byTooltip('Start Wave'), findsOneWidget);

      // The rail's cards render an empty SizedBox until their sprite futures
      // resolve, so capturing straight away photographs text-only cards. Give
      // the futures real time, then require the art: an OrionAtlasSprite only
      // becomes a SpriteWidget once it has a sprite.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('command-dock-persistent-rail')),
          matching: find.byType(SpriteWidget),
        ),
        findsWidgets,
        reason: 'the tower rail captured before its card art resolved',
      );

      final dockRect = tester.getRect(find.byType(MissionCommandDock));
      final scannerRect = tester.getRect(find.byType(NextWaveScanner));
      final gameRect = tester.getRect(find.bySubtype<GameWidget>());
      for (var row = 0; row < BoardLayout.rows; row++) {
        for (var column = 0; column < BoardLayout.columns; column++) {
          final center =
              gameRect.topLeft +
              game!.boardCellCenter(GridPosition(column, row));
          expect(center.dy, lessThan(dockRect.top));
          expect(scannerRect.contains(center), isFalse);
        }
      }
      // Every bottom-row cell remains reachable through the same canvas mapping.
      const bottomCell = GridPosition(7, 11);
      await tester.tapAt(gameRect.topLeft + game!.boardCellCenter(bottomCell));
      await tester.pump();
      expect(game!.snapshot.selectedCell, bottomCell);
      game!.handleBoardTap(Offset.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.runAsync(
        () => captureReactorRimFixture(boundaryKey, 'fixture-1a$suffix.png'),
      );
      game!.handleBoardTap(game!.boardCellCenter(const GridPosition(4, 5)));
      game!.placeTower(Character.haruto);
      game!.handleBoardTap(game!.boardCellCenter(const GridPosition(4, 5)));
      await tester.pump();
      await tester.pump();
      expect(game!.stateNotifier.value.selectedTower, isNotNull);
      expect(find.byTooltip('Inspect member'), findsOneWidget);
      expect(
        game!.children.whereType<BoardComponent>().single.selectedRange,
        game!.stateNotifier.value.selectedTowerStats!.range,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'fixture-1a-radial$suffix.png',
        ),
      );
      final gotIt = find.text('Got it');
      if (tester.any(gotIt)) {
        await tester.tap(gotIt);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => captureReactorRimFixture(
            boundaryKey,
            'fixture-1a-radial-clear$suffix.png',
          ),
        );
      }
      await tester.tap(find.byTooltip('Inspect member'));
      await tester.pump();
      expect(find.byType(TowerInspector), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tower-inspector-hero')),
          matching: find.byType(InternalSpriteWidget),
        ),
        findsWidgets,
        reason: 'The inspector artwork must load before the capture.',
      );
      await tester.runAsync(
        () =>
            captureReactorRimFixture(boundaryKey, 'inspector-live$suffix.png'),
      );
      final navigator = Navigator.of(
        tester.element(find.byType(TowerInspector)),
      );
      expect(await navigator.maybePop(), isTrue);
      await tester.pump();
      expect(find.byType(TowerInspector), findsNothing);

      // Tear the mounted game down so its ticker does not leak into the tests
      // that follow.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  testWidgets('boots into the Orion world map first', (tester) async {
    await tester.pumpWidget(testGamePage());
    await tester.pumpAndSettle();

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsNothing);
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

    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expectSemanticsLabel(tester, 'Standard Conditions', findsOneWidget);
    expect(find.text('No environmental modifiers'), findsOneWidget);
    expect(createdGame, isNull);

    await tester.tap(find.byTooltip('Start Mission'));
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
    expect(find.byTooltip('Replay Mission'), findsOneWidget);
    expect(find.text('Best: Silver • 14 base health'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
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
      final module = runModuleDefinition(OrionCampaign.stageOne.blueprint!);
      expect(
        find.text(
          'Blueprint recovered: ${module.title} • ${module.effectText}',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Replay Mission'), findsOneWidget);
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
      await tester.ensureVisible(find.text(stage.mapLabel));
      await tester.tap(find.text(stage.mapLabel));
      await tester.pumpAndSettle();
      for (final modifier in stage.modifiers) {
        final metadata = StageModifierMetadata.forModifier(modifier);
        // The lead modifier's name is the fact-row tile, which shows caps and
        // keeps real copy as its semantics label; later ones stay as
        // conditions rows. bySemanticsLabel matches both.
        expectSemanticsLabel(
          tester,
          metadata.title,
          findsOneWidget,
          reason:
              '${stage.id}: ${metadata.title} is not announced in the briefing',
        );
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
      await tester.ensureVisible(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss'));
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

    await tester.ensureVisible(find.text('Core'));
    await tester.pump();
    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Replay Mission'));
    await tester.pump();

    expect(find.byTooltip('Replay Mission'), findsOneWidget);
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
              startOnWorldMap: true,
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
        expect(findOrionTitle('Outpost Alpha'), findsOneWidget);

        final action = find.byTooltip('Start Mission');
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
    await tester.ensureVisible(find.text('Core'));
    await tester.pump();
    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Replay Mission'));
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
      missionWaveTotal: buildSnapshot.missionWaveTotal,
      wavesCleared: buildSnapshot.wavesCleared,
      stageId: buildSnapshot.stageId,
      stageName: buildSnapshot.stageName,
      stageLabel: buildSnapshot.stageLabel,
      unlockedTowerTypes: buildSnapshot.unlockedTowerTypes,
      squad: buildSnapshot.squad,
      squadLevels: buildSnapshot.squadLevels,
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
    expect(find.byTooltip('Start Wave'), findsOneWidget);
  });

  testWidgets('long-press drag commits placement through the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);
    await tester.pumpAndSettle();

    final gameRect = tester.getRect(find.bySubtype<GameWidget>());
    Offset globalFor(GridPosition cell) =>
        gameRect.topLeft + game!.boardCellCenter(cell);

    // Under the fake-async test binding the Flame surface never completes
    // onLoad (real image decode), so it never mounts and raw board taps are
    // inert. Route the selection exactly the way the chrome arbiters do.
    game!.handleBoardTap(
      globalFor(const GridPosition(2, 3)) - gameRect.topLeft,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

    // Long-press the Laser card, drag it over a buildable cell, release. The
    // commit must land through the page's event plumbing at the final global
    // pointer position — not at the selected cell.
    final laserCost = GameBalance.towerStats(TowerType.laser, level: 1).cost;
    final start = tester.getCenter(
      find.byKey(const ValueKey('tower-card-haruto')),
    );
    final dropTarget = globalFor(const GridPosition(4, 0));
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(dropTarget - start);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(game!.children.whereType<TowerComponent>(), hasLength(1));
    expect(game!.snapshot.gold, GameBalance.startingGold - laserCost);
    expect(game!.placementPreview.character, isNull);

    // Board interaction recovers after the drag ended: the next selection
    // goes through and leaves no preview state behind.
    game!.handleBoardTap(
      globalFor(const GridPosition(6, 0)) - gameRect.topLeft,
    );
    await tester.pump();
    expect(game!.snapshot.selectedCell, const GridPosition(6, 0));
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

      OrionDefenseGame? game;
      await tester.pumpWidget(
        testGamePage(onGameCreated: (value) => game = value),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      final gameRect = tester.getRect(find.bySubtype<GameWidget>());
      const topRightCell = GridPosition(7, 0);
      final topRightCenter =
          gameRect.topLeft + game!.boardCellCenter(topRightCell);
      final scannerRect = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      );
      final dockFrameRect = tester.getRect(
        find
            .descendant(
              of: find.byType(MissionCommandDock),
              matching: find.byType(OrionSurface),
            )
            .first,
      );

      expect(
        scannerRect.contains(topRightCenter),
        isFalse,
        reason: 'Scanner $scannerRect overlaps cell center $topRightCenter.',
      );
      expect(
        dockFrameRect.contains(topRightCenter),
        isFalse,
        reason:
            'Command dock frame $dockFrameRect overlaps cell center '
            '$topRightCenter.',
      );
    },
  );

  testWidgets('collapsed scanner stays above the board on short viewports', (
    tester,
  ) async {
    // Short viewport: the whole collapsed radar overlaps the board, so the
    // tap arbiter would otherwise claim every touch and leave touch users
    // no way to open the next-wave preview.
    tester.view.physicalSize = const Size(430, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    final gameRect = tester.getRect(find.bySubtype<GameWidget>());
    GridPosition? cellAtGlobal(Offset point) =>
        game!.boardCellAt(point - gameRect.topLeft);

    final scannerRect = tester.getRect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
    );
    final centerCell = cellAtGlobal(scannerRect.center);
    expect(
      centerCell,
      isNull,
      reason: 'The rendered board must clear the radar control.',
    );

    // The painted radar itself opens the preview…
    await tester.tapAt(scannerRect.center);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );
    expect(game!.snapshot.selectedCell, isNull);

    // The explicit close action returns to the board.
    await tester.tap(find.byTooltip('Collapse next-wave scanner'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );

    final boardPoint =
        gameRect.topLeft + game!.boardCellCenter(const GridPosition(6, 0));
    expect(scannerRect.contains(boardPoint), isFalse);
    expect(cellAtGlobal(boardPoint), const GridPosition(6, 0));
  });

  testWidgets('selection replaces pacing with build or inspector controls', (
    tester,
  ) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    // Pacing lives inside the idle dock while nothing is selected.
    expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);

    game!.stateNotifier.value = commandDeckSnapshot(
      selectedCell: const GridPosition(1, 1),
    );
    await tester.pump();

    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.text('1x'), findsNothing);
    expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

    final tower = const PlacedTower(
      id: 1,
      character: Character.haruto,
      position: GridPosition(1, 1),
    );
    game!.stateNotifier.value = commandDeckSnapshot(
      selectedTower: tower,
      selectedTowerStats: GameBalance.towerStats(
        tower.type,
        level: tower.level,
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byTooltip('Inspect member'), findsOneWidget);
    await tester.tap(find.byTooltip('Inspect member'));
    await tester.pump();
    expect(find.byKey(const ValueKey('tower-inspector')), findsOneWidget);
  });

  testWidgets('mission screen exposes pause speed and auto-start controls', (
    tester,
  ) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester);

    // Pacing lives inside the idle dock: pause must be reachable while an
    // auto-start countdown runs, and countdowns run during the build phase.
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Game speed'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsOneWidget);

    // Speed cycles during the build phase, and every multiplier is still
    // reachable: 1x -> 2x -> 3x -> 1x.
    await tester.tap(find.byTooltip('Game speed'));
    await tester.pump();
    expect(game!.speedMultiplier, 2.0);
    expect(find.text('2x'), findsOneWidget);

    await tester.tap(find.byTooltip('Game speed'));
    await tester.pump();
    expect(game!.speedMultiplier, 3.0);
    expect(find.text('3x'), findsOneWidget);

    await tester.tap(find.byTooltip('Game speed'));
    await tester.pump();
    expect(game!.speedMultiplier, 1.0);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsOneWidget);

    game!.stateNotifier.value = commandDeckSnapshot(
      phase: GamePhase.wave,
      acquiredRunModules: const [RunModuleId.heavyCaliber],
    );
    await tester.pump();
    // The GameWidget fills the full SafeArea so cellSize is preserved. The
    // status HUD is the non-interactive overlay (IgnorePointer) so taps pass
    // through to the board; the acquired-module details control stays
    // interactive (it collapses on selection) and pacing stays interactive
    // inside the idle dock in the bottom command chrome.
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Game speed'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
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
      _activeIgnorePointerAncestorsOf(find.byType(AcquiredRunModuleControl)),
      findsNothing,
    );
    expect(
      _activeIgnorePointerAncestorsOf(
        find.byKey(const ValueKey('command-dock-idle')),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'module draft and mission report stay later blocking stack entries',
    (tester) async {
      OrionDefenseGame? game;
      await tester.pumpWidget(
        testGamePage(onGameCreated: (created) => game = created),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      int stackIndexOfType(Type type) {
        final stack = tester.widget<Stack>(
          find
              .ancestor(
                of: find.bySubtype<GameWidget>(),
                matching: find.byType(Stack),
              )
              .first,
        );
        return stack.children.indexWhere((child) {
          final inner = child is Positioned ? child.child : child;
          return inner.runtimeType == type;
        });
      }

      // Mission-control coordinates recorded while the dock is reachable.
      final startWaveCenter = tester.getCenter(find.byTooltip('Start Wave'));
      final scannerCenter = tester.getCenter(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      );

      // The draft overlay is ordered after the chrome…
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
      expect(
        stackIndexOfType(MissionChrome),
        lessThan(stackIndexOfType(RunModuleDraftPanel)),
      );

      // …and blocks the board: a tap through the middle reaches no cell.
      await tester.tapAt(tester.getCenter(find.bySubtype<GameWidget>()));
      await tester.pump();
      expect(game!.snapshot.selectedCell, isNull);
      expect(find.byType(RunModuleDraftPanel), findsOneWidget);

      // Taps at the underlying mission-control coordinates reach neither the
      // dock (no wave start, no speed change) nor the scanner.
      await tester.tapAt(startWaveCenter);
      await tester.pump();
      await tester.tapAt(scannerCenter);
      await tester.pump();
      expect(game!.snapshot.phase, GamePhase.build);
      expect(game!.snapshot.speedMultiplier, 1);
      expect(game!.snapshot.selectedCell, isNull);
      expect(find.byType(RunModuleDraftPanel), findsOneWidget);

      // The loss report is likewise a later blocking entry.
      game!.selectRunModule(1, RunModuleId.heavyCaliber);
      await tester.pump();
      await publishLoss(tester, game!);
      expect(
        stackIndexOfType(MissionChrome),
        lessThan(stackIndexOfType(MissionReportPanel)),
      );

      // A tap at the underlying scanner coordinate is absorbed by the report
      // (its own action row owns the bottom edge, so the bottom-band dock
      // probes stay exclusive to the draft leg) and reaches neither the dock
      // nor the world map.
      await tester.tapAt(scannerCenter);
      await tester.pump();
      expect(game!.snapshot.phase, GamePhase.lost);
      expect(find.text('MISSION FAILED'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.bySubtype<GameWidget>()));
      await tester.pump();
      expect(find.text('MISSION FAILED'), findsOneWidget);
      expect(find.text('SECTOR MAP'), findsNothing);
    },
  );

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

    expect(find.text('SECTOR SECURED'), findsOneWidget);
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
      missionWaveTotal: snapshot.missionWaveTotal,
      wavesCleared: snapshot.wavesCleared,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      squad: snapshot.squad,
      squadLevels: snapshot.squadLevels,
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

    expect(find.text('MISSION FAILED'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Core'));
    await tester.pump();
    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();

    expect(find.text('Singularity Core is locked.'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsNothing);
    expect(find.byTooltip('Start Mission'), findsNothing);
    expect(find.byTooltip('Replay Mission'), findsNothing);
    expect(createdGame, isNull);
  });

  testWidgets('locked stage feedback stays in map slot without shifting nodes '
      'or leaking to other tabs', (tester) async {
    await tester.pumpWidget(testGamePage());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Core'));
    await tester.pump();
    final coreTopBefore = tester.getTopLeft(find.text('Core')).dy;
    final alphaTopBefore = tester.getTopLeft(find.text('Alpha')).dy;

    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();

    expect(find.text('Singularity Core is locked.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Core')).dy,
      closeTo(coreTopBefore, 0.01),
    );
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      closeTo(alphaTopBefore, 0.01),
    );

    await tester.tap(find.byTooltip('Codex'));
    await tester.pumpAndSettle();
    expect(find.text('Singularity Core is locked.'), findsNothing);

    await tester.tap(find.byTooltip('Camp'));
    await tester.pumpAndSettle();
    expect(find.text('Singularity Core is locked.'), findsNothing);

    await tester.tap(find.byTooltip('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Singularity Core is locked.'), findsOneWidget);
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
          ownedLevels: CampaignSave.starterOwnedLevels,
          squad: CampaignSave.starterSquad,
          scrip: 0,
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

    await openResetCampaignDialog(tester);

    expect(findOrionTitle('Reset Campaign'), findsOneWidget);
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
    expect(find.byTooltip('Start Wave'), findsNothing);
  });

  testWidgets('reset campaign wipes the Scrip wallet with the profile', (
    tester,
  ) async {
    // The reset rebuilds the whole aggregate — wallet included — so the
    // next load (and any view reading the committed save) sees 0 Scrip.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 5,
        Character.mio: 3,
        Character.sayo: 2,
      },
      squad: const [Character.sayo],
      scrip: 900,
    );
    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
    expect(store.scrip, 0);
    expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
    expect(store.squad, CampaignSave.starterSquad);

    final reloaded = await store.load();
    expect(reloaded.scrip, 0);
    expect(reloaded.ownedLevels, CampaignSave.starterOwnedLevels);
    expect(reloaded.squad, CampaignSave.starterSquad);
  });

  testWidgets('reset confirmation uses OrionSurface and keeps behavior', (
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
    await openResetCampaignDialog(tester);

    expect(find.byKey(const ValueKey('reset-campaign-dialog')), findsOneWidget);
    expect(find.byType(OrionSurface), findsWidgets);
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

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(find.text('Could not load campaign progress.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsNothing);
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
    store.saveCompletions[0].complete();
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
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(find.byTooltip('Replay Mission'), findsOneWidget);

    await tester.tap(find.byTooltip('Replay Mission'));
    await tester.pumpAndSettle();

    // The mission report is gone and the stage is back in build phase.
    expect(find.text('Saved.'), findsNothing);
    expect(find.byTooltip('Start Wave'), findsOneWidget);
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

      store.saveCompletions[0].complete();
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
      expect(find.byTooltip('Start Wave'), findsOneWidget);
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
        actionLabel: 'Start Mission',
      );

      expect(game!.snapshot.gold, GameBalance.startingGold);

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions[0].complete();
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
      final store = _TestCampaignProgressStore(failOnSaveIndices: {0});
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
    store.saveCompletions[0].complete();
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

  // The Mission Report resolves the module generically from the mission's
  // own stage: a side-stage first clear must celebrate ITS blueprint,
  // not Alpha's.
  testWidgets(
    'side-stage first-clear Mission Report reports that stage\'s blueprint',
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
        actionLabel: 'Start Mission',
      );

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      expect(find.text('Blueprint recovery pending'), findsOneWidget);
      expect(
        find.text('Salvaged Drones unlocks after this result is saved.'),
        findsOneWidget,
      );

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(find.text('Blueprint recovered: Salvaged Drones'), findsOneWidget);
    },
  );

  // HPA-415 Task 4: the Alpha lifecycle proof replayed on a non-Alpha
  // blueprint — a first Nebula Relay clear must not carry Relay Arc while
  // the save is pending, must celebrate Relay Arc after commit, and a
  // same-object Replay must pick up the refreshed eligibility.
  testWidgets(
    'Nebula Relay first-clear commit then same-game Replay refreshes Relay Arc eligibility',
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
      await startStageFromBriefing(
        tester,
        mapLabel: 'Relay',
        actionLabel: 'Start Mission',
      );

      final firstAttemptGame = game!;
      expect(
        firstAttemptGame.availableRunModules,
        isNot(contains(RunModuleId.relayArc)),
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
        isNot(contains(RunModuleId.relayArc)),
      );

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(find.text('Blueprint recovered: Relay Arc'), findsOneWidget);

      await tester.tap(find.byTooltip('Replay Mission'));
      await tester.pumpAndSettle();

      expect(identical(game, firstAttemptGame), isTrue);
      expect(
        firstAttemptGame.availableRunModules,
        contains(RunModuleId.relayArc),
      );
      expect(find.byTooltip('Start Wave'), findsOneWidget);
    },
  );

  // HPA-415 Task 4: the retry path on a later optional stage — Void
  // Bastion's failed first-clear save reports Blueprint not recovered, and
  // Retry Save then recovers Siege Rounds, the stage's own blueprint.
  testWidgets(
    'Void Bastion failed Retry Save then success recovers Siege Rounds',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
          'aurora-gate',
        }),
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
      await startStageFromBriefing(
        tester,
        mapLabel: 'Bastion',
        actionLabel: 'Start Mission',
      );
      expect(
        game!.availableRunModules,
        isNot(contains(RunModuleId.siegeRounds)),
      );

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(find.text('Blueprint not recovered'), findsOneWidget);
      expect(find.byTooltip('Retry Save'), findsOneWidget);
      store.failOnSaveIndices.clear();

      await tester.tap(find.byTooltip('Retry Save'));
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(find.text('Blueprint recovered: Siege Rounds'), findsOneWidget);
    },
  );

  // HPA-415 Task 4: an already-cleared non-Alpha replay stays silent about
  // first-clear recovery even when the replay earns a better medal.
  testWidgets(
    'already-cleared Nebula Relay replay with a better medal has no recovery fact',
    (tester) async {
      final store = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
        'nebula-relay': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
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
      await startStageFromBriefing(
        tester,
        mapLabel: 'Relay',
        actionLabel: 'Replay Mission',
      );

      // A strictly better result on a cleared stage is retained — the
      // first-clear reward copy must not appear.
      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      await tester.pumpAndSettle();

      expect(find.text('Blueprint recovery pending'), findsNothing);
      expect(find.text('Blueprint not recovered'), findsNothing);
      expect(find.text('Blueprint recovered: Relay Arc'), findsNothing);
    },
  );

  // HPA-415 Task 4: reset clears a non-Alpha blueprint both ways — the map
  // node loses its Recovered status, and eligibility observed through a
  // Replay before the reset no longer survives it (the node itself locks
  // again; rules-level removal is covered by run_module_unlocks_test).
  testWidgets(
    'campaign reset removes Nebula Relay recovered status and eligibility',
    (tester) async {
      final store = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
        'nebula-relay': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
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

      expectSemanticsLabel(
        tester,
        RegExp(r'Nebula Relay.*Blueprint • Recovered'),
        findsOneWidget,
      );

      await startStageFromBriefing(
        tester,
        mapLabel: 'Relay',
        actionLabel: 'Replay Mission',
      );
      expect(game!.availableRunModules, contains(RunModuleId.relayArc));

      await tester.tap(find.byTooltip('World Map').last);
      await tester.pumpAndSettle();

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(find.text('Campaign reset.'), findsOneWidget);
      expectSemanticsLabel(
        tester,
        RegExp(r'Nebula Relay.*Blueprint • Locked'),
        findsOneWidget,
      );
      expectSemanticsLabel(
        tester,
        RegExp(r'Blueprint • Recovered'),
        findsNothing,
      );
    },
  );

  testWidgets('mission save composes with a subsequent mission save', (
    tester,
  ) async {
    const expectedResult = StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    );
    const relayResult = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    // A non-default, subset-ordered profile: result writes must carry these
    // levels and this squad order through every composed save unchanged, and
    // each launched game must read them from committed state.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 5,
        Character.sayo: 9,
        Character.tetsuo: 4,
      },
      squad: const [Character.tetsuo, Character.sayo],
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

    // The first game launches on the committed non-default squad, in order.
    expect(game!.snapshot.squadLevels.keys.toList(), [
      Character.tetsuo,
      Character.sayo,
    ]);
    expect(game!.snapshot.squadLevels.values.toList(), [4, 9]);

    await publishVictory(tester, game!, result: expectedResult);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();

    expect(store.progress.resultFor('outpost-alpha'), expectedResult);
    await tester.tap(find.byTooltip('World Map').last);
    await tester.pumpAndSettle();

    await startStageFromBriefing(
      tester,
      mapLabel: 'Relay',
      actionLabel: 'Start Mission',
    );
    // The second launch reads the same committed squad and levels.
    expect(game!.snapshot.squadLevels.keys.toList(), [
      Character.tetsuo,
      Character.sayo,
    ]);
    expect(game!.snapshot.squadLevels.values.toList(), [4, 9]);
    await publishVictory(tester, game!, result: relayResult);
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(store.progress.resultFor('outpost-alpha'), expectedResult);
    expect(store.progress.resultFor('nebula-relay'), relayResult);
    // Ownership and squad carry through every composed save untouched.
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 5,
      Character.sayo: 9,
      Character.tetsuo: 4,
    });
    expect(store.squad, [Character.tetsuo, Character.sayo]);
  });

  testWidgets('Mission save failure reports unchanged progress', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      scrip: 300,
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
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();

    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
    expect(find.text('Could not save campaign progress.'), findsNothing);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    );
    // The failed write credited nothing: the wallet is the committed 300.
    expect(store.scrip, 300);
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
    store.saveCompletions[0].complete();
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
      scrip: 300,
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
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Retry Save'), findsOneWidget);
    expect(store.saveCalls, 1);
    store.failOnSaveIndices.clear();

    // Both taps happen before the first retry completion. The save-state
    // guard must collapse them into one additional queued write — and the
    // wallet must credit the captured award exactly once.
    final retryButton = find.byTooltip('Retry Save');
    await tester.tap(retryButton);
    await tester.tap(retryButton);
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);

    expect(store.saveCalls, 2);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(store.saveCalls, 2);
    expect(find.text('Saved.'), findsOneWidget);
    expect(store.scrip, 450);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  testWidgets('Mission loss does not write campaign progress', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      scrip: 500,
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
      missionWaveTotal: snapshot.missionWaveTotal,
      wavesCleared: snapshot.wavesCleared,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      squad: snapshot.squad,
      squadLevels: snapshot.squadLevels,
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

    expect(find.text('MISSION FAILED'), findsOneWidget);
    expect(store.saveCalls, 0);
    // A loss is never a Scrip event: the wallet stays exactly as committed.
    expect(store.scrip, 500);
    expect(
      find.descendant(
        of: find.byType(MissionReportPanel),
        matching: find.textContaining('Scrip'),
      ),
      findsNothing,
    );
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
    expect(find.text('MISSION FAILED'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(game!.snapshot.phase, GamePhase.build);

    // Second loss → Retry. Previously crashed on `_missionStageId!`.
    await publishLoss(tester, game!);
    expect(find.text('MISSION FAILED'), findsOneWidget);
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
    expect(find.text('SECTOR MAP'), findsNothing);

    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();
  });

  testWidgets('World Map stays reachable while a build cell is selected', (
    tester,
  ) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);
    await tester.pumpAndSettle();

    const cell = GridPosition(7, 11);
    game!.handleBoardTap(game!.boardCellCenter(cell));
    await tester.pump();
    expect(game!.snapshot.selectedCell, cell);
    expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

    expect(
      find.byTooltip('World Map'),
      findsWidgets,
      reason: 'selecting a build cell must not hide the only map exit',
    );
    await tester.tap(find.byTooltip('World Map').last);
    await tester.pumpAndSettle();
    expect(find.text('SECTOR MAP'), findsOneWidget);
  });

  testWidgets('an active wave exposes no actionable map exit', (tester) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);
    await tester.pumpAndSettle();

    game!.startWave();
    await tester.pump();
    expect(game!.snapshot.phase, GamePhase.wave);

    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      final exits = find.bySemanticsLabel('World Map');
      for (var index = 0; index < exits.evaluate().length; index += 1) {
        expect(
          tester.getSemantics(exits.at(index)),
          matchesSemantics(
            label: 'World Map',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
          reason: 'an active wave must never offer an actionable map exit',
        );
      }
    } finally {
      handle.dispose();
    }

    final chip = find.byTooltip('World Map');
    if (chip.evaluate().isNotEmpty) {
      await tester.tap(chip.last, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(find.text('SECTOR MAP'), findsNothing);
    expect(game!.snapshot.phase, GamePhase.wave);
  });

  testWidgets('a paused wave exposes no actionable map exit', (tester) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);
    await tester.pumpAndSettle();

    game!.startWave();
    game!.togglePause();
    await tester.pump();
    expect(game!.snapshot.phase, GamePhase.wave);
    expect(game!.snapshot.isPaused, isTrue);

    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      final exits = find.bySemanticsLabel('World Map');
      for (var index = 0; index < exits.evaluate().length; index += 1) {
        expect(
          tester.getSemantics(exits.at(index)),
          matchesSemantics(
            label: 'World Map',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
          reason: 'a paused wave must never offer an actionable map exit',
        );
      }
    } finally {
      handle.dispose();
    }

    final chip = find.byTooltip('World Map');
    if (chip.evaluate().isNotEmpty) {
      await tester.tap(chip.last, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(find.text('SECTOR MAP'), findsNothing);
    expect(game!.snapshot.isPaused, isTrue);
  });

  testWidgets(
    'endless waves past the scripted count still show no first-mission '
    'guide',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          firstMissionGuideStore: InMemoryFirstMissionGuideStore(
            completed: false,
          ),
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Endless');
      await tester.pumpAndSettle();
      expect(game!.mode, RunMode.endless);
      expect(find.byType(FirstMissionGuideCallout), findsNothing);

      await publishEndlessWaveClear(tester, game!, 8);
      await tester.pumpAndSettle();

      expect(game!.snapshot.waveNumber, 9);
      expect(game!.snapshot.missionWaveTotal, isNull);
      expect(find.byType(FirstMissionGuideCallout), findsNothing);
      expect(find.textContaining('Wave 9 of 8'), findsNothing);
    },
  );

  testWidgets('Mission failed exit leaves an unsaved breadcrumb', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
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
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('World Map (Unsaved)'));
    await tester.pumpAndSettle();

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(
      find.text('Mission result and 150 Scrip were not saved.'),
      findsOneWidget,
    );
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
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.saveCalls, 1);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    );
  });

  testWidgets('Endless launch is offered only after a committed clear', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(endlessBest: 3),
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    // Unlocked but uncleared: Nebula Relay opens on the Alpha clear yet has
    // no committed result, so the sheet keeps the single mission launch.
    await tester.ensureVisible(find.text('Relay'));
    await tester.tap(find.text('Relay'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start Mission'), findsOneWidget);
    expect(find.byTooltip('Endless'), findsNothing);
    expect(find.text('No endless run yet'), findsNothing);
    expect(find.textContaining('Endless best:'), findsNothing);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    // The committed Alpha clear offers Endless and surfaces the saved best.
    await tester.ensureVisible(find.text('Alpha'));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Replay Mission'), findsOneWidget);
    expect(find.byTooltip('Endless'), findsOneWidget);
    expect(find.text('Endless best: 3 waves'), findsOneWidget);
  });

  testWidgets('Endless launch mounts an endless run with the endless HUD', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Endless');
    await tester.pumpAndSettle();

    expect(game, isNotNull);
    expect(game!.mode, RunMode.endless);
    expect(game!.snapshot.isEndless, isTrue);
    expect(game!.snapshot.missionWaveTotal, isNull);
    expectSemanticsLabel(
      tester,
      'Outpost Alpha. Endless. Wave 1, Build',
      findsOneWidget,
    );
    expect(find.text('Wave 1 of 8'), findsNothing);
  });

  testWidgets('Endless wave clears save the best and lower runs keep it', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await tester.pumpAndSettle();
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);

    await publishEndlessWaveClear(tester, game!, 7);
    await tester.pumpAndSettle();
    expect(store.progress.endlessBestFor('outpost-alpha'), 7);
    expect(store.saveCalls, 2);
    // Endless writes never touch the mission result or award rewards.
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    );

    await publishLoss(tester, game!);
    await tester.pump();
    expect(find.text('ENDLESS RUN OVER'), findsOneWidget);
    expectSemanticsLabel(tester, 'Endless Run Over', findsOneWidget);
    expect(find.text('New best!'), findsOneWidget);
    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('R&D'), findsNothing);
    await tester.ensureVisible(find.text('MISSION DETAILS'));
    await tester.tap(find.text('MISSION DETAILS'));
    await tester.pump();
    expect(find.text('Survived 7 waves'), findsOneWidget);

    // Replay keeps the endless mode and recaptures the committed best.
    await tester.tap(find.byTooltip('Replay Endless'));
    await tester.pumpAndSettle();
    expect(game!.mode, RunMode.endless);
    expect(game!.snapshot.phase, GamePhase.build);
    expect(game!.snapshot.isEndless, isTrue);

    // A run that does not beat the saved best never queues a write.
    await publishEndlessWaveClear(tester, game!, 3);
    await tester.pumpAndSettle();
    expect(store.saveCalls, 2);
    expect(store.progress.endlessBestFor('outpost-alpha'), 7);

    await publishLoss(tester, game!);
    await tester.pump();
    expect(find.text('Best: 7 waves'), findsOneWidget);
    expect(find.text('Best result already saved.'), findsOneWidget);
    await tester.ensureVisible(find.text('MISSION DETAILS'));
    await tester.tap(find.text('MISSION DETAILS'));
    await tester.pump();
    expect(find.text('Survived 3 waves'), findsOneWidget);
  });

  testWidgets('Endless run never shows the first-mission guide', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(),
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(
          completed: false,
        ),
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();

    // Control: the same Alpha under the mission mode is guide-eligible.
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');
    expect(find.byType(FirstMissionGuideCallout), findsOneWidget);
    game!.returnToMap();
    await tester.pumpAndSettle();

    await startStageFromBriefing(tester, actionLabel: 'Endless');
    expect(game!.mode, RunMode.endless);
    expect(game!.snapshot.isEndless, isTrue);
    expect(find.byType(FirstMissionGuideCallout), findsNothing);
  });

  testWidgets('Endless best is cleared by reset campaign', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(endlessBest: 6),
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(store.progress.endlessBestFor('outpost-alpha'), isNull);
    expect(store.progress.isCleared('outpost-alpha'), isFalse);

    // Without the committed clear the briefing no longer offers Endless.
    await tester.ensureVisible(find.text('Alpha'));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start Mission'), findsOneWidget);
    expect(find.byTooltip('Endless'), findsNothing);
    expect(find.textContaining('Endless best:'), findsNothing);
  });

  testWidgets(
    'Endless defeat waits on the pending best write before enabling exits',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
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
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 5);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      await publishLoss(tester, game!);
      await tester.pump();
      expect(find.text('ENDLESS RUN OVER'), findsOneWidget);
      expect(find.text('Saving result…'), findsOneWidget);
      // Both report exits stay disabled while the best write is in flight.
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNull);
      expect(reportActionOnPressed(tester, 'World Map'), isNull);

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNotNull);
      expect(reportActionOnPressed(tester, 'World Map'), isNotNull);

      await tester.tap(find.byTooltip('Replay Endless'));
      await tester.pumpAndSettle();
      expect(game!.snapshot.phase, GamePhase.build);
      expect(game!.snapshot.isEndless, isTrue);

      // The replayed run sees the committed best: clearing the same count is
      // a no-op while the next higher count queues a fresh write.
      await publishEndlessWaveClear(tester, game!, 5);
      await tester.pumpAndSettle();
      expect(store.saveCalls, 1);
      await publishEndlessWaveClear(tester, game!, 6);
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();
      expect(store.progress.endlessBestFor('outpost-alpha'), 6);
    },
  );

  testWidgets(
    'Endless failed final write offers Retry Save that commits the run score',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
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
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 4);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      await publishLoss(tester, game!);
      await tester.pump();
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
      expect(find.byTooltip('Retry Save'), findsOneWidget);
      expect(find.byTooltip('World Map (Unsaved)'), findsOneWidget);
      expect(store.progress.endlessBestFor('outpost-alpha'), isNull);

      await tester.tap(find.byTooltip('Retry Save'));
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(find.text('Saved.'), findsOneWidget);
      expect(store.progress.endlessBestFor('outpost-alpha'), 4);
    },
  );

  testWidgets('Endless failed final write names the committed mid-run best', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(),
      delaySaves: true,
      failOnSaveIndices: {1},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    // Wave 4's record write commits; wave 7's fails. The report must name
    // the standing record — "progress unchanged" would be a lie here.
    await publishEndlessWaveClear(tester, game!, 4);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);

    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);

    await publishLoss(tester, game!);
    await tester.pump();
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(find.text('Save failed — best 4 waves kept.'), findsOneWidget);
    expect(find.text('Save failed — progress unchanged.'), findsNothing);
    expect(find.byTooltip('Retry Save'), findsOneWidget);
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);
  });

  testWidgets(
    'Endless Retry Save queues once while a retry is already in flight',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
        delaySaves: true,
        // The best write fails, and a duplicate retry (index 2) would fail
        // too if it ever queued.
        failOnSaveIndices: {0, 2},
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Endless');
      await tester.pumpAndSettle();

      await publishEndlessWaveClear(tester, game!, 4);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      await publishLoss(tester, game!);
      await tester.pump();
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retry Save'), findsOneWidget);

      // Two activations before the retry's rebuild: the second must not
      // queue a duplicate of the same score. Without a guard it sits in
      // the serialized queue behind the first retry, then its configured
      // failure flips the committed record's report back to failed.
      await tester.tap(find.byTooltip('Retry Save'));
      await tester.tap(find.byTooltip('Retry Save'));
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);

      store.saveCompletions.last.complete();
      await tester.pumpAndSettle();
      expect(store.saveCalls, 2);

      for (final pending in store.saveCompletions) {
        if (!pending.isCompleted) pending.complete();
      }
      await tester.pumpAndSettle();
      expect(store.progress.endlessBestFor('outpost-alpha'), 4);
      expect(find.text('Saved.'), findsOneWidget);
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNotNull);
    },
  );

  testWidgets('Endless failed final write still allows an unsaved exit', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(),
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
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    await publishLoss(tester, game!);
    await tester.pump();
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();

    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
    await tester.tap(find.byTooltip('World Map (Unsaved)'));
    await tester.pumpAndSettle();

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(find.text('Endless best was not saved.'), findsOneWidget);
    expect(store.progress.endlessBestFor('outpost-alpha'), isNull);
  });

  testWidgets(
    'Endless failed final write names committed best when leaving to map',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
        delaySaves: true,
        failOnSaveIndices: {1},
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      // Wave 4 commits; wave 7 fails.
      await publishEndlessWaveClear(tester, game!, 4);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(store.progress.endlessBestFor('outpost-alpha'), 4);

      await publishEndlessWaveClear(tester, game!, 7);
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);

      await publishLoss(tester, game!);
      await tester.pump();
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(find.text('Save failed — best 4 waves kept.'), findsOneWidget);
      await tester.tap(find.byTooltip('World Map (Unsaved)'));
      await tester.pumpAndSettle();

      expect(find.text('SECTOR MAP'), findsOneWidget);
      expect(
        find.text('Endless save failed — best 4 waves kept.'),
        findsOneWidget,
      );
      expect(store.progress.endlessBestFor('outpost-alpha'), 4);
    },
  );

  testWidgets(
    'in-game World Map button during in-flight Endless save reports feedback',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
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
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 4);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      // Tapping the in-game World Map button while save is in flight.
      await tester.tap(find.byTooltip('World Map'));
      await tester.pump();

      expect(find.text('SECTOR MAP'), findsNothing);
      expect(
        find.text('Saving Endless best… Finish saving before returning.'),
        findsOneWidget,
      );

      // After save settles, returning to map works.
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('World Map'));
      await tester.pumpAndSettle();
      expect(find.text('SECTOR MAP'), findsOneWidget);
    },
  );

  testWidgets(
    'earlier failed Endless write replaced by later queued write does not report failure',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
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
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 4);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      await publishEndlessWaveClear(tester, game!, 7);
      await tester.pump();

      // First best save fails.
      store.saveCompletions[0].complete();
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      await tester.pump();

      // Failure toast is suppressed because write 2 is queued.
      expect(find.text('Could not save campaign progress.'), findsNothing);

      // Second best save succeeds.
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(store.progress.endlessBestFor('outpost-alpha'), 7);
    },
  );

  testWidgets(
    'Endless queued writes keep the report saving until the last settles',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
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
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 4);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      // The second clear queues behind the in-flight write — the serialized
      // queue has not reached the store for it yet.
      await publishEndlessWaveClear(tester, game!, 7);
      await tester.pump();
      expect(store.saveCalls, 1);

      await publishLoss(tester, game!);
      await tester.pump();
      expect(find.text('Saving result…'), findsOneWidget);

      // The first commit's callback ran while the second write still counted
      // in _pendingSaves, so it must not unblock the report actions.
      store.saveCompletions[0].complete();
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      await tester.pump();
      expect(find.text('Saving result…'), findsOneWidget);
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNull);
      expect(reportActionOnPressed(tester, 'World Map'), isNull);

      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNotNull);
      // The larger queued score is what disk keeps.
      expect(store.progress.endlessBestFor('outpost-alpha'), 7);
    },
  );

  testWidgets(
    'Endless zero-wave and non-improving losses report saved with no write',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(endlessBest: 5),
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Endless');
      await tester.pumpAndSettle();

      // Wave-1 defeat clears nothing: the seeded saved state writes nothing
      // and both exit actions work immediately.
      await publishLoss(tester, game!);
      await tester.pump();
      expect(find.text('ENDLESS RUN OVER'), findsOneWidget);
      expect(find.text('Best: 5 waves'), findsOneWidget);
      expect(find.text('Best result already saved.'), findsOneWidget);
      expect(store.saveCalls, 0);
      await tester.ensureVisible(find.text('MISSION DETAILS'));
      await tester.tap(find.text('MISSION DETAILS'));
      await tester.pump();
      expect(find.text('Survived 0 waves'), findsOneWidget);

      await tester.tap(find.byTooltip('Replay Endless'));
      await tester.pumpAndSettle();
      expect(game!.snapshot.phase, GamePhase.build);
      expect(game!.snapshot.isEndless, isTrue);

      // A run that does not beat the saved best never queues a write.
      await publishEndlessWaveClear(tester, game!, 3);
      await tester.pumpAndSettle();
      expect(store.saveCalls, 0);

      await publishLoss(tester, game!);
      await tester.pump();
      expect(find.text('Best: 5 waves'), findsOneWidget);
      expect(find.text('Best result already saved.'), findsOneWidget);
      expect(reportActionOnPressed(tester, 'World Map'), isNotNull);
      await tester.tap(find.text('World Map'));
      await tester.pumpAndSettle();
      expect(find.text('SECTOR MAP'), findsOneWidget);
    },
  );

  testWidgets(
    'Endless first-attempt zero-wave loss reports no record and briefing agrees',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Endless');
      await tester.pumpAndSettle();

      await publishLoss(tester, game!);
      await tester.pump();
      expect(find.text('ENDLESS RUN OVER'), findsOneWidget);
      expect(find.text('No endless best yet'), findsOneWidget);
      expect(find.textContaining('New best'), findsNothing);
      expect(find.text('No result to save.'), findsOneWidget);
      expect(find.text('Best result already saved.'), findsNothing);
      expect(store.saveCalls, 0);
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNotNull);
      expect(reportActionOnPressed(tester, 'World Map'), isNotNull);

      await tester.tap(find.text('World Map'));
      await tester.pumpAndSettle();
      expect(find.text('SECTOR MAP'), findsOneWidget);

      await tester.ensureVisible(find.text('Alpha'));
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('No endless run yet'), findsOneWidget);
      expect(find.byTooltip('Endless'), findsOneWidget);
    },
  );

  testWidgets(
    'Endless save failure during an active run surfaces feedback and recovers',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
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
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 2);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions[0].complete();
      await tester.pump();
      await tester.pump();

      // The run is still active, so the suppressed default toast is re-raised
      // through the game feedback channel instead of the report.
      expect(game!.snapshot.isEnded, isFalse);
      expect(game!.snapshot.feedback, 'Could not save campaign progress.');
      expect(find.text('Could not save campaign progress.'), findsOneWidget);

      // The next improving wave recovers: a fresh write commits the best.
      await publishEndlessWaveClear(tester, game!, 3);
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();
      expect(store.progress.endlessBestFor('outpost-alpha'), 3);

      await publishLoss(tester, game!);
      await tester.pump();
      expect(find.text('Saved.'), findsOneWidget);
      expect(reportActionOnPressed(tester, 'Replay Endless'), isNotNull);

      await tester.tap(find.text('World Map'));
      await tester.pumpAndSettle();
      expect(find.text('SECTOR MAP'), findsOneWidget);
      expect(find.text('Could not save campaign progress.'), findsNothing);
    },
  );

  testWidgets('ordinary mission loss keeps the plain retry actions', (
    tester,
  ) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithAlphaCleared(),
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
    await tester.pump();
    expect(find.text('MISSION FAILED'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);
    expect(find.byTooltip('Retry Save'), findsNothing);
    expect(find.text('Saved.'), findsNothing);
    expect(find.text('Best result already saved.'), findsNothing);
  });

  testWidgets('queued endless saves drain in order while the map exit stays '
      'gated', (tester) async {
    // The serialized save queue composes each payload on the last committed
    // state: a second endless best queued behind the first still writes
    // after it drains, and the mission exit stays gated until the queue
    // empties. A non-default, subset-ordered profile must ride through every
    // queued write untouched — and launch the game with its own levels.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 6,
        Character.kaito: 8,
        Character.sayo: 3,
      },
      squad: const [Character.sayo, Character.kaito],
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
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    // The endless launch also reads the committed non-default squad.
    expect(game!.snapshot.squadLevels.keys.toList(), [
      Character.sayo,
      Character.kaito,
    ]);
    expect(game!.snapshot.squadLevels.values.toList(), [3, 8]);

    await publishEndlessWaveClear(tester, game!, 4);
    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    // Save A is in flight, save B is queued behind it — the exit is gated.
    game!.returnToMap();
    await tester.pump();
    expect(find.text('SECTOR MAP'), findsNothing);

    // Save A drains but B is still pending, so the exit stays gated.
    store.saveCompletions[0].complete();
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    game!.returnToMap();
    await tester.pump();
    expect(find.text('SECTOR MAP'), findsNothing);

    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    game!.returnToMap();
    await tester.pumpAndSettle();
    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(store.saveCalls, 2);
    // The queued saves committed in order: the later best (7) survives.
    expect(store.progress.endlessBestFor('outpost-alpha'), 7);
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 6,
      Character.kaito: 8,
      Character.sayo: 3,
    });
    expect(store.squad, [Character.sayo, Character.kaito]);
  });

  testWidgets('queued endless saves compose on the committed aggregate and '
      'keep the Scrip wallet', (tester) async {
    // Save B is queued while save A is in flight: B's payload builds on A's
    // committed result, so the wallet and roster ride through both writes
    // untouched (HPA-923 task 2 — no reconstruction may zero the wallet).
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 6,
        Character.kaito: 8,
      },
      squad: const [Character.mio, Character.kaito],
      scrip: 750,
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
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    // Wave 7's write is already queued behind the in-flight wave-4 write:
    // the queue serializes them — only save A has reached the store.
    expect(store.saveCalls, 1);

    // Save A drains first; save B was queued behind it and now runs.
    store.saveCompletions[0].complete();
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    expect(store.progress.endlessBestFor('outpost-alpha'), 7);
    expect(store.scrip, 750);
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 6,
      Character.kaito: 8,
    });
    expect(store.squad, [Character.mio, Character.kaito]);

    // The same aggregate survives the load path a restarted page would take.
    final reloaded = await store.load();
    expect(reloaded.scrip, 750);
    expect(reloaded.progress.endlessBestFor('outpost-alpha'), 7);
    expect(reloaded.ownedLevels, store.ownedLevels);
    expect(reloaded.squad, store.squad);
  });

  testWidgets('a failed second write keeps the last committed Scrip and '
      'roster', (tester) async {
    // Write A commits (best 4); write B fails. The committed aggregate —
    // not the attempted payload — is what every later view and reload sees.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 6,
        Character.sayo: 3,
      },
      squad: const [Character.mio, Character.sayo],
      scrip: 750,
      delaySaves: true,
      failOnSaveIndices: {1},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);

    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    await publishLoss(tester, game!);
    await tester.pump();
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    // Nothing from the failed payload advanced: committed best stays 4 and
    // the wallet and roster are exactly what write A committed.
    expect(find.text('Save failed — best 4 waves kept.'), findsOneWidget);
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);
    expect(store.scrip, 750);
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 6,
      Character.sayo: 3,
    });
    expect(store.squad, [Character.mio, Character.sayo]);

    final reloaded = await store.load();
    expect(reloaded.scrip, 750);
    expect(reloaded.progress.endlessBestFor('outpost-alpha'), 4);
  });

  testWidgets('a queued second write still commits after the in-flight '
      'first write fails', (tester) async {
    // Write B is issued while write A is in flight; A then fails. The
    // queue must not be poisoned: B still builds on the committed
    // aggregate and persists its own delta — a queue that dies on the
    // first failure, or that replays A's payload for B, fails this test.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 6,
        Character.kaito: 8,
      },
      squad: const [Character.mio, Character.kaito],
      scrip: 750,
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
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    // Wave 7's write is already queued behind in-flight write A: only A
    // has reached the store so far.
    expect(store.saveCalls, 1);

    // A fails; B runs anyway and commits on the committed aggregate.
    store.saveCompletions[0].complete();
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    // B persisted its own delta (best 7) despite A's failure. A's failure
    // is superseded by the newer queued write — no failure banner for the
    // player, and the wallet and roster rode through untouched.
    expect(store.saveCalls, 2);
    expect(store.progress.endlessBestFor('outpost-alpha'), 7);
    expect(store.scrip, 750);
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 6,
      Character.kaito: 8,
    });
    expect(store.squad, [Character.mio, Character.kaito]);
    expect(find.text('Could not save campaign progress.'), findsNothing);

    // Committed-profile probe, not just storage: a stale page aggregate
    // would surface here — the fresh briefing reads its endless best
    // straight from _committed.
    await publishLoss(tester, game!);
    await tester.pump();
    expect(find.text('Saved.'), findsOneWidget);
    await tester.tap(find.text('World Map'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Alpha'));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Endless best: 7 waves'), findsOneWidget);

    final reloaded = await store.load();
    expect(reloaded.scrip, 750);
    expect(reloaded.progress.endlessBestFor('outpost-alpha'), 7);
    expect(reloaded.ownedLevels, store.ownedLevels);
    expect(reloaded.squad, store.squad);
  });

  testWidgets('a queued second write that fails leaves the first write '
      'committed and reports live', (tester) async {
    // Write B is issued while write A is in flight; A commits, B fails.
    // Nothing from B's payload may advance: the committed aggregate keeps
    // exactly what A wrote, and the live run surfaces the failure.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 6,
        Character.kaito: 8,
      },
      squad: const [Character.mio, Character.kaito],
      scrip: 750,
      delaySaves: true,
      failOnSaveIndices: {1},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    expect(store.saveCalls, 1);

    store.saveCompletions[0].complete();
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();

    // Only A's delta is on disk and in the committed aggregate; B's
    // failure reports on the still-running game.
    expect(store.saveCalls, 2);
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);
    expect(store.scrip, 750);
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 6,
      Character.kaito: 8,
    });
    expect(store.squad, [Character.mio, Character.kaito]);
    expect(find.text('Could not save campaign progress.'), findsOneWidget);

    // Reload immediately after B's failure — before any later write — so
    // the outcome B failed into is what's asserted, not a superseding one.
    final failedReload = await store.load();
    expect(failedReload.scrip, 750);
    expect(failedReload.progress.endlessBestFor('outpost-alpha'), 4);

    // Committed-state UI probe: the ended report projects its saved best
    // straight from _committed — a stale page aggregate would render a
    // different "kept" best than the one write A committed.
    await publishLoss(tester, game!);
    await tester.pump();
    expect(find.text('Save failed — best 4 waves kept.'), findsOneWidget);
    expect(reportActionOnPressed(tester, 'Retry Save'), isNotNull);

    final reloaded = await store.load();
    expect(reloaded.scrip, 750);
    expect(reloaded.progress.endlessBestFor('outpost-alpha'), 4);
    expect(reloaded.ownedLevels, store.ownedLevels);
    expect(reloaded.squad, store.squad);
  });

  testWidgets('a write issued after a queued write fails recomposes on '
      'the committed aggregate', (tester) async {
    // Continuation counterpart to the second-write-failure case: the run
    // keeps going after a failed write, and the next cleared wave issues
    // a fresh write that must compose on the committed aggregate — the
    // failed payload's best never leaks into it.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      ownedLevels: const {
        Character.haruto: 1,
        Character.mio: 6,
        Character.kaito: 8,
      },
      squad: const [Character.mio, Character.kaito],
      scrip: 750,
      delaySaves: true,
      failOnSaveIndices: {1},
    );
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Endless');

    await publishEndlessWaveClear(tester, game!, 4);
    await publishEndlessWaveClear(tester, game!, 7);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    store.saveCompletions[0].complete();
    await _pumpUntil(tester, () => store.saveCompletions.length > 1);
    store.saveCompletions[1].complete();
    await tester.pumpAndSettle();
    expect(store.progress.endlessBestFor('outpost-alpha'), 4);

    await publishEndlessWaveClear(tester, game!, 9);
    await _pumpUntil(tester, () => store.saveCompletions.length > 2);
    store.saveCompletions[2].complete();
    await tester.pumpAndSettle();

    expect(store.saveCalls, 3);
    expect(store.progress.endlessBestFor('outpost-alpha'), 9);
    expect(store.scrip, 750);
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.mio: 6,
      Character.kaito: 8,
    });
    expect(store.squad, [Character.mio, Character.kaito]);

    final reloaded = await store.load();
    expect(reloaded.scrip, 750);
    expect(reloaded.progress.endlessBestFor('outpost-alpha'), 9);
    expect(reloaded.ownedLevels, store.ownedLevels);
    expect(reloaded.squad, store.squad);
  });

  testWidgets('navigation and Settings stay disabled while a campaign '
      'reset is in flight', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
      delayResets: true,
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await _pumpUntil(tester, () => store.resetCompletions.isNotEmpty);
    await tester.pump();

    // The bottom tabs are inert while the reset is in flight — Camp cannot
    // be reached.
    await tester.tap(find.byTooltip('Camp'));
    await tester.pumpAndSettle();
    expect(findOrionTitle('Camp'), findsNothing);
    expect(find.text('SECTOR MAP'), findsOneWidget);

    final settingsGear = tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Settings'),
        matching: find.byType(InkWell),
      ),
    );
    expect(settingsGear.onTap, isNull);

    store.resetCompletions.single.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'persists queued mission save even if page is disposed before it runs',
    (tester) async {
      const result = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
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

      await publishVictory(tester, game!, result: result);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 1);
      expect(store.progress.resultFor('outpost-alpha'), result);
      expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
      expect(store.squad, CampaignSave.starterSquad);
    },
  );

  testWidgets(
    'failed mission save after disposal does not call setState on a defunct '
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

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(store.saveCalls, 1);
    },
  );

  // HPA-923 task 3 mandatory regression: an unchanged best is a wallet
  // event, not a no-op — the run still queues exactly one win transaction
  // and the report's saved copy no longer implies nothing was earned.
  testWidgets(
    'retained replay result still pays its Scrip award once committed',
    (tester) async {
      const savedBest = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
      final store = _TestCampaignProgressStore(
        progress: CampaignProgress(
          bestResultsByStageId: {'outpost-alpha': savedBest},
        ),
        scrip: 500,
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
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      // The Silver replay award (100 × 125%) is pending — the report shows
      // the exact captured amount before the write commits.
      expect(store.saveCalls, 1);
      expect(find.text('Scrip pending'), findsOneWidget);
      expect(
        find.text('125 Scrip credits after this result is saved.'),
        findsOneWidget,
      );

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      // The stored Gold best is retained untouched while the wallet
      // still credits the replay award.
      expect(store.progress.resultFor('outpost-alpha'), savedBest);
      expect(store.scrip, 625);
      expect(find.text('Could not save campaign progress.'), findsNothing);
      expect(find.text('Best result already saved.'), findsNothing);
      expect(find.text('Result saved. Best medal unchanged.'), findsOneWidget);
      expect(find.text('Scrip credited: 125'), findsOneWidget);

      final reloaded = await store.load();
      expect(reloaded.scrip, 625);
      expect(reloaded.progress.resultFor('outpost-alpha'), savedBest);
    },
  );

  group('mission Scrip awards (HPA-923 task 3)', () {
    testWidgets(
      'first clear pays the first-clear award and reports pending then '
      'credited Scrip beside the blueprint fact',
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

        await publishVictory(
          tester,
          game!,
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

        // Alpha first clear at Gold: 900 + (100 × 150%) = 1050, shown as
        // exact pending copy before the write commits — never "credited".
        expect(find.text('Scrip pending'), findsOneWidget);
        expect(
          find.text('1,050 Scrip credits after this result is saved.'),
          findsOneWidget,
        );
        expect(find.textContaining('credited'), findsNothing);
        expect(find.text('Blueprint recovery pending'), findsOneWidget);

        store.saveCompletions[0].complete();
        await tester.pumpAndSettle();

        expect(store.scrip, 1050);
        expect(find.text('Scrip credited: 1,050'), findsOneWidget);
        expect(
          find.text('Blueprint recovered: Relay Calibration'),
          findsOneWidget,
        );

        final reloaded = await store.load();
        expect(reloaded.scrip, 1050);
        expect(
          reloaded.progress.resultFor('outpost-alpha'),
          const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
      },
    );

    // HPA-923 task 6: the report separates the medal it persisted from the
    // Scrip the run earned — both are their own MissionRewardFact entries,
    // tracked through pending and credited states alongside the blueprint.
    testWidgets(
      'a first-clear report lists the saved best medal and the run Scrip '
      'as separate rewards',
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

        await publishVictory(
          tester,
          game!,
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

        // While the write is in flight both facts are pending — neither
        // claims to be on record yet.
        expect(find.text('Best medal pending: Gold'), findsOneWidget);
        expect(find.text('Scrip pending'), findsOneWidget);
        expect(find.text('Blueprint recovery pending'), findsOneWidget);
        expect(find.text('Best medal saved: Gold'), findsNothing);

        store.saveCompletions[0].complete();
        await tester.pumpAndSettle();

        expect(find.text('Best medal saved: Gold'), findsOneWidget);
        expect(find.text('20 base health on record.'), findsOneWidget);
        expect(find.text('Scrip credited: 1,050'), findsOneWidget);
        expect(find.text('Added to your Scrip wallet.'), findsOneWidget);
        expect(
          find.text('Blueprint recovered: Relay Calibration'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a retained best lists the kept medal and the run Scrip as separate '
      'rewards',
      (tester) async {
        const savedBest = StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: 20,
        );
        final store = _TestCampaignProgressStore(
          progress: CampaignProgress(
            bestResultsByStageId: {'outpost-alpha': savedBest},
          ),
          scrip: 500,
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
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        );
        await tester.pumpAndSettle();

        // The kept record is the stored Gold best — not the run's Silver —
        // and it was never this save's doing, so the fact says the medal is
        // kept rather than newly saved. The Scrip fact still credits this
        // run's 125 award; the two entries must not collapse into one row.
        expect(
          find.text('Result saved. Best medal unchanged.'),
          findsOneWidget,
        );
        expect(find.text('Best medal kept: Gold'), findsOneWidget);
        expect(
          find.text(
            '20 base health already on record — this run did not replace it.',
          ),
          findsOneWidget,
        );
        expect(find.text('Best medal saved: Silver'), findsNothing);
        expect(find.text('Scrip credited: 125'), findsOneWidget);
        // A replay recovers no blueprint — the list has no third fact.
        expect(
          find.text('Blueprint recovered: Relay Calibration'),
          findsNothing,
        );
      },
    );

    // HPA-923 task 6 fix round 1: a non-improving replay must never frame
    // the committed medal as pending or unsaved — the stored record stays
    // on file through the failed write, and the retry that credits Scrip
    // still records no new medal.
    testWidgets('a retained best stays on record through a failed save and the '
        'scrip-crediting retry', (tester) async {
      const savedBest = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
      final store = _TestCampaignProgressStore(
        progress: CampaignProgress(
          bestResultsByStageId: {'outpost-alpha': savedBest},
        ),
        scrip: 500,
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
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

      // While the write runs the medal is not "pending" — it is already
      // committed; only the run's Scrip award is.
      expect(find.text('Best medal kept: Gold'), findsOneWidget);
      expect(find.text('Best medal pending: Gold'), findsNothing);
      expect(find.text('Scrip pending'), findsOneWidget);
      expect(
        find.text('125 Scrip credits after this result is saved.'),
        findsOneWidget,
      );

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      // The failed write leaves the stored record exactly where it was —
      // "not saved" would claim otherwise — while Scrip correctly reports
      // itself uncredited.
      expect(find.text('Best medal kept: Gold'), findsOneWidget);
      expect(find.text('Best medal not saved'), findsNothing);
      expect(find.text('Scrip not credited'), findsOneWidget);
      expect(
        find.text('Retry Save to keep this 125 Scrip award.'),
        findsOneWidget,
      );
      expect(store.scrip, 500);
      expect(store.progress.resultFor('outpost-alpha'), savedBest);

      store.failOnSaveIndices.clear();
      await tester.tap(find.byTooltip('Retry Save'));
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      // Retry credits the captured 125 once and still records no new
      // medal — the kept Gold record outlives every save state.
      expect(find.text('Best medal kept: Gold'), findsOneWidget);
      expect(find.text('Result saved. Best medal unchanged.'), findsOneWidget);
      expect(find.text('Scrip credited: 125'), findsOneWidget);
      expect(store.scrip, 625);
      expect(store.progress.resultFor('outpost-alpha'), savedBest);
      final reloaded = await store.load();
      expect(reloaded.scrip, 625);
      expect(reloaded.progress.resultFor('outpost-alpha'), savedBest);
    });

    testWidgets(
      'a failed save marks the best medal unsaved beside the uncredited '
      'Scrip, then retry commits both',
      (tester) async {
        const savedBest = StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        );
        final store = _TestCampaignProgressStore(
          progress: CampaignProgress(
            bestResultsByStageId: {'outpost-alpha': savedBest},
          ),
          scrip: 300,
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
        store.saveCompletions[0].complete();
        await tester.pumpAndSettle();

        expect(find.text('Best medal not saved'), findsOneWidget);
        expect(find.text('Scrip not credited'), findsOneWidget);
        expect(store.scrip, 300);
        expect(store.progress.resultFor('outpost-alpha'), savedBest);

        store.failOnSaveIndices.clear();
        await tester.tap(find.byTooltip('Retry Save'));
        await _pumpUntil(tester, () => store.saveCompletions.length > 1);
        store.saveCompletions[1].complete();
        await tester.pumpAndSettle();

        expect(find.text('Best medal saved: Gold'), findsOneWidget);
        expect(find.text('Scrip credited: 150'), findsOneWidget);
        expect(store.scrip, 450);
      },
    );

    testWidgets('a higher-medal replay pays more Scrip', (tester) async {
      // Alpha replay base 100 scales by medal: Clear pays 100, Gold 150.
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

      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      await tester.pumpAndSettle();
      expect(store.scrip, 150);

      // The same-stage replay at Clear pays less — medal scales the award.
      await tester.tap(find.byTooltip('Replay Mission'));
      await tester.pumpAndSettle();
      await publishVictory(
        tester,
        game!,
        result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 3),
      );
      await tester.pumpAndSettle();

      expect(store.scrip, 250);
      expect(find.text('Scrip credited: 100'), findsOneWidget);
      final reloaded = await store.load();
      expect(reloaded.scrip, 250);
    });

    testWidgets(
      'a failed save keeps prior Scrip and medal, then Retry Save credits '
      'the same captured award once',
      (tester) async {
        const savedBest = StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        );
        final store = _TestCampaignProgressStore(
          progress: CampaignProgress(
            bestResultsByStageId: {'outpost-alpha': savedBest},
          ),
          scrip: 300,
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
        store.saveCompletions[0].complete();
        await tester.pumpAndSettle();

        // Nothing advanced: wallet, best and report all say not credited.
        expect(find.text('Scrip not credited'), findsOneWidget);
        expect(
          find.text('Retry Save to keep this 150 Scrip award.'),
          findsOneWidget,
        );
        expect(store.scrip, 300);
        expect(store.progress.resultFor('outpost-alpha'), savedBest);

        store.failOnSaveIndices.clear();
        await tester.tap(find.byTooltip('Retry Save'));
        await _pumpUntil(tester, () => store.saveCompletions.length > 1);
        store.saveCompletions[1].complete();
        await tester.pumpAndSettle();

        // The retry credits the captured 150 — not recomputed, not doubled.
        expect(store.saveCalls, 2);
        expect(store.scrip, 450);
        expect(find.text('Scrip credited: 150'), findsOneWidget);
        expect(
          store.progress.resultFor('outpost-alpha'),
          const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        final reloaded = await store.load();
        expect(reloaded.scrip, 450);
      },
    );

    testWidgets('a duplicate stage-won callback does not double-pay', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore();
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);

      const result = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
      await publishVictory(tester, game!, result: result);
      // A second completion for the same attempt is dropped by the page's
      // first-StageCompletion guard before it can queue another award.
      game!.onStageWon?.call(
        StageCompletion(stage: game!.stage, result: result),
      );
      await tester.pumpAndSettle();

      expect(store.saveCalls, 1);
      expect(store.scrip, 1050);
    });

    testWidgets(
      'a replay after the committed first clear pays the replay award, '
      'not another first-clear bonus',
      (tester) async {
        final store = _TestCampaignProgressStore();
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
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        await tester.pumpAndSettle();
        expect(store.scrip, 1050);

        // Replay recaptures the committed result, so firstClear is false:
        // this win pays only the Gold replay award (150), never 1050 again.
        await tester.tap(find.byTooltip('Replay Mission'));
        await tester.pumpAndSettle();
        await publishVictory(
          tester,
          game!,
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        await tester.pumpAndSettle();

        expect(store.saveCalls, 2);
        expect(store.scrip, 1200);
        expect(find.text('Scrip credited: 150'), findsOneWidget);
        expect(
          find.text('Result saved. Best medal unchanged.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a win after reset pays the first-clear award again on the wiped '
      'profile',
      (tester) async {
        final store = _TestCampaignProgressStore();
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
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        await tester.pumpAndSettle();
        expect(store.scrip, 1050);

        await tester.tap(find.byTooltip('World Map'));
        await tester.pumpAndSettle();
        await openResetCampaignDialog(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Reset'));
        await tester.pumpAndSettle();
        expect(store.scrip, 0);

        await startStageFromBriefing(tester);
        await publishVictory(
          tester,
          game!,
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
        await tester.pumpAndSettle();

        // The reset wiped the committed best, so the next clear is a fresh
        // first clear — the award recomputes from the wiped profile.
        expect(store.scrip, 1050);
        expect(
          store.progress.resultFor('outpost-alpha'),
          const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        );
      },
    );

    testWidgets('endless clears and the run-over report never pay Scrip', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithAlphaCleared(),
        scrip: 500,
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Endless');

      await publishEndlessWaveClear(tester, game!, 4);
      await tester.pumpAndSettle();
      await publishLoss(tester, game!);
      await tester.pumpAndSettle();

      expect(find.text('ENDLESS RUN OVER'), findsOneWidget);
      expect(find.textContaining('Scrip'), findsNothing);
      expect(store.scrip, 500);
      final reloaded = await store.load();
      expect(reloaded.scrip, 500);
    });
  });

  testWidgets('failed reset retains a result committed before the reset runs', (
    tester,
  ) async {
    // The reset path is unreachable while a save is in flight — the
    // report's exit and the shell Settings entry are both busy-gated, so
    // the ordering can never be exercised. This test covers what the
    // sequence actually reaches: a save commits, then a reset runs and
    // fails. Progress — including the just-saved result — is retained.
    const result = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
      delaySaves: true,
      resetResults: [StateError('reset failed')],
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

    await publishVictory(tester, game!, result: result);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    // While the write is in flight the report's exit is disabled — Reset
    // cannot be reached from here or from the shell it leads back to.
    expect(
      tester
          .widget<OrionPrimaryButton>(
            find.widgetWithText(OrionPrimaryButton, 'World Map'),
          )
          .onPressed,
      isNull,
    );

    // Drain the pending save, then return to the map and trigger the
    // reset.
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('World Map').last);
    await tester.pumpAndSettle();

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reset campaign progress.'), findsOneWidget);
    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId.keys, {
      'outpost-alpha',
      'nebula-relay',
      'asteroid-foundry',
    });
    // The saved result and the profile survive the failed reset.
    expect(store.progress.resultFor('outpost-alpha'), result);
    expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
    expect(store.squad, CampaignSave.starterSquad);
  });

  testWidgets('a failed reset from the Codex keeps the Codex and reports the '
      'error through the shell', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      resetResults: [StateError('reset failed')],
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Codex'));
    await tester.pumpAndSettle();
    expect(findOrionTitle('Codex'), findsOneWidget);

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reset campaign progress.'), findsOneWidget);
    expect(findOrionTitle('Codex'), findsOneWidget);
    expect(find.text('SECTOR MAP'), findsNothing);
    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId.keys, {'outpost-alpha'});
  });

  testWidgets('successful reset from Codex keeps Codex active', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Codex'));
    await tester.pumpAndSettle();
    expect(findOrionTitle('Codex'), findsOneWidget);

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(findOrionTitle('Codex'), findsOneWidget);
    expect(find.text('SECTOR MAP'), findsNothing);
    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId, isEmpty);
  });

  testWidgets('successful reset from Title keeps Title active and Settings '
      'respects in-flight busy state', (tester) async {
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
      delayResets: true,
    );

    await tester.pumpWidget(
      testGamePage(progressStore: store, startOnWorldMap: false),
    );
    await tester.pumpAndSettle();

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pump();

    // While the reset is in flight, Title Settings must remain disabled.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    expect(find.text('Reset Campaign'), findsNothing);

    store.resetCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(find.text('SECTOR MAP'), findsNothing);
    expect(store.resetCalls, 1);
  });

  testWidgets('successful reset wipes a result committed before it runs', (
    tester,
  ) async {
    // The reset path is unreachable while a save is in flight — the
    // report's exit and the shell Settings entry are both busy-gated, so
    // the ordering can never be exercised. This test covers what the
    // sequence actually reaches: a save commits, then a reset runs and
    // wipes the store.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
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

    // While the write is in flight the report's exit is disabled — Reset
    // cannot be reached from here or from the shell it leads back to.
    expect(
      tester
          .widget<OrionPrimaryButton>(
            find.widgetWithText(OrionPrimaryButton, 'World Map'),
          )
          .onPressed,
      isNull,
    );

    // Drain the pending save first.
    store.saveCompletions[0].complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('World Map').last);
    await tester.pumpAndSettle();

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
    expect(store.progress.bestResultsByStageId, isEmpty);
    // The fresh profile restores the two starters and an empty progress.
    expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
    expect(store.squad, CampaignSave.starterSquad);
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

    await openResetCampaignDialog(tester);
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

    await openResetCampaignDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    // The reset is now in flight (delayed). The Reset button must be
    // disabled, so tapping it does nothing.
    expect(store.resetCalls, 1);
    expect(store.resetCompletions, isNotEmpty);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start Mission'), findsNothing);
    expect(find.byTooltip('Replay Mission'), findsNothing);
    expect(createdGame, isNull);

    final settingsGear = tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Settings'),
        matching: find.byType(InkWell),
      ),
    );
    expect(settingsGear.onTap, isNull);

    // No second reset was triggered.
    expect(store.resetCalls, 1);

    // Complete the in-flight reset.
    store.resetCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(store.resetCalls, 1);
  });

  testWidgets(
    'failed mission save reports failure on the report and a breadcrumb on '
    'the map',
    (tester) async {
      // A mission save that fails marks the report's save state and leaves
      // an unsaved breadcrumb once the player returns to the map.
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'asteroid-foundry',
        }),
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
      await tester.pumpAndSettle();

      // The report shows the failure inline.
      expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
      expect(find.text('Retry Save'), findsOneWidget);

      // Returning to the map leaves the unsaved breadcrumb.
      await tester.tap(find.byTooltip('World Map (Unsaved)'));
      await tester.pumpAndSettle();

      expect(
        find.text('Mission result and 150 Scrip were not saved.'),
        findsOneWidget,
      );
      expect(find.text('SECTOR MAP'), findsOneWidget);
    },
  );

  testWidgets('successful save retry clears the failed save state', (
    tester,
  ) async {
    // A failed mission save offers Retry Save; after the retry succeeds the
    // report reads saved and the map shows no stale failure breadcrumb. The
    // non-default levels and subset squad order ride through the failed
    // attempt and the retried write unchanged.
    final store = _TestCampaignProgressStore(
      progress: _progressWithResults({
        'outpost-alpha',
        'nebula-relay',
        'asteroid-foundry',
      }),
      ownedLevels: const {
        Character.haruto: 1,
        Character.sayo: 8,
        Character.kaito: 3,
      },
      squad: const [Character.kaito, Character.sayo],
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

    // First save attempt fails (save index 1).
    await publishVictory(
      tester,
      game!,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);

    // The retry (save index 2) succeeds.
    await tester.tap(find.byTooltip('Retry Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsOneWidget);

    // Returning to the map shows no stale failure breadcrumb.
    await tester.tap(find.byTooltip('World Map').last);
    await tester.pumpAndSettle();

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(find.text('Mission result was not saved.'), findsNothing);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    // Failure and retry never touched the roster halves of the save.
    expect(store.ownedLevels, {
      Character.haruto: 1,
      Character.sayo: 8,
      Character.kaito: 3,
    });
    expect(store.squad, [Character.kaito, Character.sayo]);
  });

  testWidgets('null store blocks launch without throwing', (tester) async {
    // The squad write is the launch precondition (HPA-922 task 6): with no
    // store it can never commit, so the sheet stays open with retryable
    // feedback and no run mounts — instead of launching a run whose report
    // could only fail.
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStoreLoader: () async => throw StateError('no store'),
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load campaign progress.'), findsOneWidget);

    await tester.ensureVisible(find.text('Alpha'));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start Mission'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save squad changes — tap a launch action to retry.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
    expect(game, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch retries store initialization after a failed load', (
    tester,
  ) async {
    // A transient initial-load failure leaves _store null; Launch must retry
    // the loader — not return false forever — so a recoverable failure cannot
    // permanently disable stage starts.
    var loadAttempts = 0;
    final recoveredStore = _TestCampaignProgressStore();
    OrionDefenseGame? game;

    await tester.pumpWidget(
      testGamePage(
        progressStoreLoader: () async {
          loadAttempts += 1;
          if (loadAttempts == 1) {
            throw StateError('no store');
          }
          return recoveredStore;
        },
        onGameCreated: (created) => game = created,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load campaign progress.'), findsOneWidget);

    await tester.ensureVisible(find.text('Alpha'));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start Mission'));
    await tester.pump();
    await tester.pump();

    expect(loadAttempts, 2);
    // The committed profile reloaded on retry and skipped the redundant squad
    // write, so the run mounts cleanly.
    expect(recoveredStore.saveCalls, 0);
    expect(recoveredStore.squad, CampaignSave.starterSquad);
    expect(game?.stage.id, 'outpost-alpha');
  });

  testWidgets('the economy tabs offer retry after a failed campaign load', (
    tester,
  ) async {
    var loadAttempts = 0;
    final recoveredStore = _TestCampaignProgressStore(scrip: 1240);

    await tester.pumpWidget(
      testGamePage(
        progressStoreLoader: () async {
          loadAttempts += 1;
          if (loadAttempts == 1) {
            throw StateError('no store');
          }
          return recoveredStore;
        },
      ),
    );
    await tester.pumpAndSettle();

    // The economy tabs would otherwise read the empty profile as dead
    // packs — the unavailable state carries the retry instead.
    await tester.tap(find.byTooltip('Flare'));
    await tester.pumpAndSettle();
    expect(find.text('CAMPAIGN PROGRESS UNAVAILABLE'), findsOneWidget);
    expect(find.byKey(const ValueKey('flare-fire-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('campaign-load-retry')));
    await tester.pumpAndSettle();

    expect(loadAttempts, 2);
    expect(findOrionTitle('Signal Flare'), findsOneWidget);
    expect(find.byKey(const ValueKey('flare-fire-1')), findsOneWidget);
    expect(find.text('Could not load campaign progress.'), findsNothing);
  });

  testWidgets(
    'shell retry locks navigation while in flight and announces failure to '
    'screen readers',
    (tester) async {
      var loadAttempts = 0;
      final retryCompleter = Completer<CampaignProgressStore>();

      await tester.pumpWidget(
        testGamePage(
          progressStoreLoader: () async {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              throw StateError('no store');
            }
            return retryCompleter.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Flare'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('campaign-load-retry')));
      await tester.pump();

      // While retrying, navigation stays disabled so another route cannot
      // start a competing retry.
      expect(
        tester
            .widget<OrionMenuShell>(find.byType(OrionMenuShell))
            .navigationEnabled,
        isFalse,
      );
      await tester.tap(find.byTooltip('Map'));
      await tester.pump();
      expect(findOrionTitle('Signal Flare'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      try {
        retryCompleter.completeError(StateError('still unavailable'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('campaign-load-retry-error')),
          findsOneWidget,
        );
        expect(
          find.text('Retry failed — could not load campaign progress.'),
          findsOneWidget,
        );
        final errorSemantics = tester.getSemantics(
          find.byKey(const ValueKey('campaign-load-retry-error')),
        );
        expect(errorSemantics.flagsCollection.isLiveRegion, isTrue);
        expect(
          tester
              .widget<OrionMenuShell>(find.byType(OrionMenuShell))
              .navigationEnabled,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'retrying campaign load infers first-mission guide completion for '
    'experienced players with no stored flag',
    (tester) async {
      var loadAttempts = 0;
      final recoveredStore = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
      );
      final guideStore = InMemoryFirstMissionGuideStore(completed: null);

      await tester.pumpWidget(
        testGamePage(
          progressStoreLoader: () async {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              throw StateError('no store');
            }
            return recoveredStore;
          },
          firstMissionGuideStore: guideStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Flare'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('campaign-load-retry')));
      await tester.pumpAndSettle();

      expect(guideStore.completed, isTrue);

      await tester.tap(find.byTooltip('Map'));
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

      expect(find.text('Tap an empty cell to build here.'), findsNothing);
    },
  );

  testWidgets('campaign retry honors a recovered guide flag before inferring '
      'completion from the Alpha result', (tester) async {
    var loadAttempts = 0;
    final recoveredStore = _TestCampaignProgressStore(
      progress: _progressWithResults({'outpost-alpha'}),
    );
    // A persisted Replay Tutorial flag whose startup read threw once:
    // inference is pending, and the retry must read the store again
    // instead of letting the recovered Alpha result mark the guide done.
    final guideStore = _FlakyLoadFirstMissionGuideStore(
      InMemoryFirstMissionGuideStore(completed: false),
    );

    await tester.pumpWidget(
      testGamePage(
        progressStoreLoader: () async {
          loadAttempts += 1;
          if (loadAttempts == 1) {
            throw StateError('no store');
          }
          return recoveredStore;
        },
        firstMissionGuideStore: guideStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Flare'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('campaign-load-retry')));
    await tester.pumpAndSettle();

    // The recovered false is honored: nothing inferred, nothing written.
    expect(guideStore.completed, isFalse);

    await tester.tap(find.byTooltip('Map'));
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester, actionLabel: 'Replay Mission');
    await tester.pump();
    await tester.pump();

    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed guide read on campaign retry writes nothing over a stored '
    'Replay Tutorial flag',
    (tester) async {
      var loadAttempts = 0;
      final recoveredStore = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
      );
      // The startup read throws AND the retry's re-read throws: the record
      // was never seen, so recovery must not write an inferred completion
      // over the stored false — inference stays pending for a later read.
      final guideStore = _FlakyLoadFirstMissionGuideStore(
        InMemoryFirstMissionGuideStore(completed: false),
        failLoadCount: 2,
      );

      await tester.pumpWidget(
        testGamePage(
          progressStoreLoader: () async {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              throw StateError('no store');
            }
            return recoveredStore;
          },
          firstMissionGuideStore: guideStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Flare'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('campaign-load-retry')));
      await tester.pumpAndSettle();

      // The unread record survives: no inferred true was persisted over
      // it, and the callout still re-arms on the next Alpha mount rather
      // than staying suppressed by a flag nobody could read.
      expect(guideStore.completed, isFalse);

      await tester.tap(find.byTooltip('Map'));
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester, actionLabel: 'Replay Mission');
      await tester.pump();
      await tester.pump();

      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed store.load() leaves no writable store so Launch cannot wipe saved campaign',
    (tester) async {
      final store = _TestCampaignProgressStore(
        loadError: StateError('corrupt save'),
        progress: _progressWithResults({'outpost-alpha'}),
        ownedLevels: const {Character.haruto: 5, Character.kaito: 7},
        squad: const [Character.kaito],
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Alpha'));
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();

      expect(store.saveCalls, 0);
      expect(store.squad, [Character.kaito]);
      expect(store.ownedLevels[Character.kaito], 7);
      expect(store.progress.resultFor('outpost-alpha'), isNotNull);
      expect(game, isNull);
    },
  );

  testWidgets(
    'launch retry recovering a non-starter profile does not overwrite the real squad or launch with stale briefing',
    (tester) async {
      var loadAttempts = 0;
      final realStore = _TestCampaignProgressStore(
        progress: _progressWithResults({
          'outpost-alpha',
          'nebula-relay',
          'salvage-rift',
        }),
        ownedLevels: const {
          Character.haruto: 1,
          Character.mio: 1,
          Character.kaito: 6,
          Character.sayo: 4,
        },
        squad: const [Character.kaito, Character.sayo],
      );
      final feedbackStore = InMemoryFeedbackPreferencesStore(
        value: const FeedbackPreferences(
          soundEffectsEnabled: true,
          hapticsEnabled: true,
          musicEnabled: true,
        ),
      );
      final guideStore = InMemoryFirstMissionGuideStore(completed: true);
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStoreLoader: () async {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              throw StateError('transient read failure');
            }
            return realStore;
          },
          feedbackPreferencesStore: feedbackStore,
          firstMissionGuideStore: guideStore,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();

      // Mutate tutorial state mid-session and poison the backing stores in
      // memory to verify Launch retry does not re-read guide/seenTips/feedback.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replay Tutorial'));
      await tester.pumpAndSettle();
      expect(guideStore.completed, isFalse);
      // Close Settings sheet.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      guideStore.completed = true;
      feedbackStore.value = const FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: false,
        musicEnabled: false,
      );

      // Open Alpha briefing while initial load failed (starter defaults shown).
      await tester.ensureVisible(find.text('Alpha'));
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();

      expect(loadAttempts, 2);
      expect(realStore.saveCalls, 0);
      expect(realStore.squad, [Character.kaito, Character.sayo]);
      expect(game, isNull);
      expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
      expect(
        find.text(
          'Campaign progress recovered — review squad before launching.',
        ),
        findsOneWidget,
      );

      // Reopening the briefing now displays the recovered real squad and
      // launches cleanly — and Replay Tutorial's in-memory false survived.
      await tester.ensureVisible(find.text('Alpha'));
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('briefing-squad-token-kaito')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-squad-token-sayo')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Replay Mission'));
      await tester.pump();
      await tester.pump();
      expect(game, isNotNull);
      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
    },
  );

  testWidgets(
    'a covered briefing keeps the recovery guard so a stale draft cannot launch',
    (tester) async {
      var loadAttempts = 0;
      final recoveryCompleter = Completer<CampaignProgressStore>();
      final realStore = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
        // The recovered profile owns no Mio — the starter draft the briefing
        // seeded from is stale once this profile lands.
        ownedLevels: const {
          Character.haruto: 1,
          Character.kaito: 6,
          Character.sayo: 4,
        },
        squad: const [Character.kaito, Character.sayo],
      );
      OrionDefenseGame? game;

      await tester.pumpWidget(
        testGamePage(
          progressStoreLoader: () async {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              throw StateError('transient read failure');
            }
            return recoveryCompleter.future;
          },
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();

      // Open the Alpha briefing while the initial load failed — it shows the
      // starter defaults.
      await tester.ensureVisible(find.text('Alpha'));
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      final sheetElement = tester.element(
        find.byKey(const ValueKey('stage-briefing')),
      );

      // Launch parks on the pending recovery; another route covering the
      // briefing keeps the mismatch pop from dismissing it.
      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pump();
      expect(loadAttempts, 2);
      unawaited(
        Navigator.of(sheetElement).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        ),
      );
      await tester.pump();
      recoveryCompleter.complete(realStore);
      await tester.pumpAndSettle();

      // Mismatch was detected but the covered sheet was not dismissed and
      // nothing was written.
      expect(realStore.saveCalls, 0);
      expect(find.text('cover'), findsOneWidget);

      // Uncover the briefing and retry — the guard must still abort instead
      // of writing the starter draft over the recovered squad.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();

      expect(realStore.saveCalls, 0);
      expect(realStore.squad, [Character.kaito, Character.sayo]);
      expect(realStore.ownedLevels.containsKey(Character.mio), isFalse);
      expect(game, isNull);
      expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
      expect(
        find.text(
          'Campaign progress recovered — review squad before launching.',
        ),
        findsOneWidget,
      );
    },
  );

  test('snapshot exposes the current tower unlocks', () {
    // Squad unlocks follow the wave schedule on the squad's own styles:
    // wave-1 styles first, railgun after Wave 1 clears.
    final session = GameSession.initial(
      squad: const {
        Character.haruto: 1,
        Character.mio: 1,
        Character.jin: 1,
        Character.elena: 1,
        Character.kaito: 1,
      },
    );

    // Squad styles are all placeable from wave 1 under the squad model;
    // the deduplicated list stays stable across waves.
    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
      TowerType.railgun,
      TowerType.ionChain,
    ]);

    expect(session.startWave(), isTrue);
    session.finishActiveWave();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
      TowerType.railgun,
      TowerType.ionChain,
    ]);
  });

  test('snapshot exposes stage identity and wave total', () {
    final snapshot = GameSession.initial().snapshot();

    expect(snapshot.stageId, 'outpost-alpha');
    expect(snapshot.stageName, 'Outpost Alpha');
    expect(snapshot.stageLabel, 'Alpha');
    expect(snapshot.missionWaveTotal, 8);
  });

  test('snapshot tower unlocks cannot be mutated after capture', () {
    final snapshot = GameSession.initial(
      squad: const {Character.haruto: 1, Character.mio: 1, Character.jin: 1},
    ).snapshot();

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

  testWidgets('tapping the Camp tab opens the roster and the Map tab returns', (
    tester,
  ) async {
    await tester.pumpWidget(testGamePage());
    await tester.pumpAndSettle();

    // Wired callback → button is visible and tappable.
    expect(find.byTooltip('Camp'), findsOneWidget);

    await tester.tap(find.byTooltip('Camp'));
    await tester.pumpAndSettle();

    // CampView is now rendered: its header appears and the world-map
    // header is replaced.
    expect(findOrionTitle('Camp'), findsOneWidget);
    expect(find.text('SECTOR MAP'), findsNothing);
    expect(find.byTooltip('Map'), findsOneWidget);

    // The two starters render as owned squad members.
    expect(find.byKey(const ValueKey('camp-card-haruto')), findsOneWidget);
    expect(find.byKey(const ValueKey('camp-card-mio')), findsOneWidget);

    // The Map tab returns the player to the world map.
    await tester.tap(find.byTooltip('Map'));
    await tester.pumpAndSettle();

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(findOrionTitle('Camp'), findsNothing);
  });

  group('camp level-up purchases (HPA-923 task 4)', () {
    /// Opens the Camp tab and the sheet for [character] on the running page.
    Future<void> openSheet(WidgetTester tester, Character character) async {
      await tester.tap(find.byTooltip('Camp'));
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('camp-card-${character.name}'));
      await tester.scrollUntilVisible(
        card,
        250,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
    }

    testWidgets(
      'a press commits one atomic write, republishes the sheet and the '
      'raised level reaches battle',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {Character.haruto: 4, Character.mio: 1},
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
        );
        OrionDefenseGame? game;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (created) => game = created,
          ),
        );
        await tester.pumpAndSettle();
        await openSheet(tester, Character.haruto);

        // levelUpCost(4) = 180 rides on the action label.
        expect(find.text('LEVEL UP · 180'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await tester.pumpAndSettle();

        // One write: the level raised and the wallet debited in the same
        // committed payload.
        expect(store.saveCalls, 1);
        expect(store.ownedLevels[Character.haruto], 5);
        expect(store.scrip, 320);

        // The sheet stays mounted and republishes committed state — level,
        // balance and the new 5→6 price all read the saved profile.
        expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
        expect(find.text('LV 5 / 40'), findsOneWidget);
        // The sheet chip and the shell's top-bar chip both read the
        // committed wallet; scope this to the sheet's own affordance.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('character-sheet')),
            matching: find.bySemanticsLabel('320 Scrip'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('LEVEL UP · ${GameBalance.levelUpCost(5)}'),
          findsOneWidget,
        );

        // Back to the roster — the committed level shows there too.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('camp-card-haruto')),
            matching: find.text('Lv 5'),
          ),
          findsOneWidget,
        );

        // The raised persistent level reaches battle: a launched run reads
        // the committed profile for its squad levels.
        await tester.tap(find.byTooltip('Map'));
        await tester.pumpAndSettle();
        await startStageFromBriefing(tester);
        expect(game!.snapshot.squadLevels[Character.haruto], 5);

        final reloaded = await store.load();
        expect(reloaded.ownedLevels[Character.haruto], 5);
        expect(reloaded.scrip, 320);
      },
    );

    testWidgets(
      'a failed write keeps level and wallet, leaves the sheet mounted '
      'and stays retryable',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {Character.haruto: 4, Character.mio: 1},
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
          delaySaves: true,
          failOnSaveIndices: {0},
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();
        await openSheet(tester, Character.haruto);

        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
        store.saveCompletions[0].complete();
        await tester.pumpAndSettle();

        // Nothing advanced: the committed level, wallet and sheet all read
        // the pre-press state, the shell breadcrumb reports, and the page
        // did not navigate anywhere.
        expect(find.text('Could not save campaign progress.'), findsOneWidget);
        expect(find.text('LV 4 / 40'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('character-sheet')),
            matching: find.bySemanticsLabel('500 Scrip'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
        expect(findOrionTitle('Camp'), findsOneWidget);
        expect(store.ownedLevels[Character.haruto], 4);
        expect(store.scrip, 500);
        expect(store.saveCalls, 1);

        // The action is retryable: not busy, not disabled.
        final retryable = tester.widget<OrionPrimaryButton>(
          find.byKey(const ValueKey('level-up-button')),
        );
        expect(retryable.onPressed, isNotNull);
        expect(retryable.loading, isFalse);

        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await _pumpUntil(tester, () => store.saveCompletions.length > 1);
        store.saveCompletions[1].complete();
        await tester.pumpAndSettle();

        expect(store.saveCalls, 2);
        expect(store.ownedLevels[Character.haruto], 5);
        expect(store.scrip, 320);
        expect(find.text('Could not save campaign progress.'), findsNothing);
        expect(find.text('LV 5 / 40'), findsOneWidget);

        final reloaded = await store.load();
        expect(reloaded.ownedLevels[Character.haruto], 5);
        expect(reloaded.scrip, 320);
      },
    );

    testWidgets('level up is single-flight on rapid taps', (tester) async {
      final store = _TestCampaignProgressStore(
        ownedLevels: const {Character.haruto: 4, Character.mio: 1},
        squad: const [Character.haruto, Character.mio],
        scrip: 500,
        delaySaves: true,
      );
      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();
      await openSheet(tester, Character.haruto);

      // Both presses land before the busy rebuild: the page's
      // single-flight guard must collapse them into one queued write —
      // the same protection the mission Retry Save guard provides.
      final levelUp = find.byKey(const ValueKey('level-up-button'));
      await tester.tap(levelUp);
      await tester.tap(levelUp);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      expect(store.saveCalls, 1);
      expect(store.saveCompletions, hasLength(1));

      // The busy rebuild lands on the next frame — the write is still in
      // flight, so the action renders inert and further taps reach nothing.
      await tester.pump();
      final busy = tester.widget<OrionPrimaryButton>(levelUp);
      expect(busy.loading, isTrue);
      // The pending reason announces itself to assistive tech as a live
      // region, not just visible copy.
      final semanticsHandle = tester.ensureSemantics();
      try {
        expect(
          tester
              .getSemantics(find.text('SAVING…'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
      } finally {
        semanticsHandle.dispose();
      }
      await tester.tap(levelUp);
      await tester.pump();
      expect(store.saveCalls, 1);

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(store.saveCalls, 1);
      expect(store.ownedLevels[Character.haruto], 5);
      expect(store.scrip, 320);
      expect(find.text('LV 5 / 40'), findsOneWidget);
    });

    testWidgets(
      'a committed purchase awaiting its frame rejects a stale-button '
      'press priced at the old level',
      (tester) async {
        // Immediate (undelayed) saves: the queued write drains on the
        // tap's own microtask flush, so _committed advances and _isBusy
        // clears before any rebuild — the previously rendered enabled
        // button still dispatches, carrying the OLD displayed level.
        final store = _TestCampaignProgressStore(
          ownedLevels: const {Character.haruto: 4, Character.mio: 1},
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();
        await openSheet(tester, Character.haruto);

        // Both presses land on the same stale sheet — no pump between.
        final levelUp = find.byKey(const ValueKey('level-up-button'));
        await tester.tap(levelUp);
        await tester.tap(levelUp);
        await tester.pumpAndSettle();

        // One write, one debit at the displayed 180: the stale second
        // press rejects instead of charging the 5→6 price, and nothing
        // reports a phantom failure over the committed purchase.
        expect(store.saveCalls, 1);
        expect(store.ownedLevels[Character.haruto], 5);
        expect(store.scrip, 320);
        expect(find.text('Could not complete level up.'), findsNothing);
        expect(find.text('Could not save campaign progress.'), findsNothing);
        expect(find.text('LV 5 / 40'), findsOneWidget);

        // The republished price is live: a new press buys 5→6 for 220.
        expect(
          find.text('LEVEL UP · ${GameBalance.levelUpCost(5)}'),
          findsOneWidget,
        );
        await tester.tap(levelUp);
        await tester.pumpAndSettle();
        expect(store.saveCalls, 2);
        expect(store.ownedLevels[Character.haruto], 6);
        expect(store.scrip, 100);
        expect(find.text('LV 6 / 40'), findsOneWidget);
      },
    );

    testWidgets(
      'insufficient funds and the cap keep the button off the write path',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: GameBalance.characterMaxLevel,
          },
          squad: const [Character.haruto],
          scrip: 30,
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();
        await openSheet(tester, Character.haruto);

        expect(
          find.text('NEEDS ${GameBalance.levelUpCost(1)} SCRIP'),
          findsOneWidget,
        );
        var button = tester.widget<OrionPrimaryButton>(
          find.byKey(const ValueKey('level-up-button')),
        );
        expect(button.onPressed, isNull);
        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await tester.pumpAndSettle();
        expect(store.saveCalls, 0);

        // Back to the roster and open the capped member: the cap reason
        // replaces the price and stays off the write path as well.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('camp-card-mio')));
        await tester.pumpAndSettle();
        expect(find.text('MAX LEVEL REACHED'), findsOneWidget);
        button = tester.widget<OrionPrimaryButton>(
          find.byKey(const ValueKey('level-up-button')),
        );
        expect(button.onPressed, isNull);
        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await tester.pumpAndSettle();

        expect(store.saveCalls, 0);
        expect(store.ownedLevels[Character.mio], GameBalance.characterMaxLevel);
        expect(store.scrip, 30);
      },
    );

    testWidgets('an in-flight reset holds Level Up off the write path from an '
        'open sheet', (tester) async {
      final store = _TestCampaignProgressStore(
        ownedLevels: const {Character.haruto: 4, Character.mio: 1},
        squad: const [Character.haruto, Character.mio],
        scrip: 500,
        delayResets: true,
      );
      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();
      await openSheet(tester, Character.haruto);

      // Confirming Reset dismisses the dialog and returns to the still-
      // open sheet while the store write runs.
      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await _pumpUntil(tester, () => store.resetCompletions.isNotEmpty);
      await tester.pump();

      expect(find.byKey(const ValueKey('character-sheet')), findsOneWidget);
      final levelUp = find.byKey(const ValueKey('level-up-button'));
      expect(tester.widget<OrionPrimaryButton>(levelUp).loading, isTrue);
      await tester.tap(levelUp);
      await tester.pump();
      expect(store.saveCalls, 0);

      store.resetCompletions.single.complete();
      await tester.pumpAndSettle();

      // The sheet republishes the wiped profile — starter level and
      // wallet, the reset notice intact, and no purchase queued behind
      // the reset to debit afterward or overwrite the breadcrumb.
      expect(find.text('Campaign reset.'), findsOneWidget);
      expect(find.text('Could not save campaign progress.'), findsNothing);
      expect(find.text('LV 1 / 40'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('character-sheet')),
          matching: find.bySemanticsLabel('0 Scrip'),
        ),
        findsOneWidget,
      );
      expect(find.text('NEEDS 60 SCRIP'), findsOneWidget);
      expect(store.saveCalls, 0);
      expect(store.ownedLevels[Character.haruto], 1);
      expect(store.scrip, 0);
    });

    testWidgets(
      'a failed reset queues no purchase and leaves Level Up retryable',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {Character.haruto: 4, Character.mio: 1},
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
          delayResets: true,
          resetResults: [StateError('reset failed')],
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();
        await openSheet(tester, Character.haruto);

        await openResetCampaignDialog(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Reset'));
        await _pumpUntil(tester, () => store.resetCompletions.isNotEmpty);
        await tester.pump();

        // Inert while the reset runs — nothing may queue behind it.
        expect(
          tester
              .widget<OrionPrimaryButton>(
                find.byKey(const ValueKey('level-up-button')),
              )
              .loading,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await tester.pump();
        expect(store.saveCalls, 0);

        store.resetCompletions.single.complete();
        await tester.pumpAndSettle();

        // The failed reset keeps the committed profile; the action is
        // retryable and a purchase now writes normally.
        expect(find.text('Could not reset campaign progress.'), findsOneWidget);
        expect(find.text('LV 4 / 40'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('character-sheet')),
            matching: find.bySemanticsLabel('500 Scrip'),
          ),
          findsOneWidget,
        );
        final retryable = tester.widget<OrionPrimaryButton>(
          find.byKey(const ValueKey('level-up-button')),
        );
        expect(retryable.onPressed, isNotNull);

        await tester.tap(find.byKey(const ValueKey('level-up-button')));
        await tester.pumpAndSettle();
        expect(store.saveCalls, 1);
        expect(store.ownedLevels[Character.haruto], 5);
        expect(store.scrip, 320);
      },
    );
  });

  group('flare purchases (HPA-923 task 5)', () {
    /// Opens the Flare tab on the running page.
    Future<void> openFlare(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Flare'));
      await tester.pumpAndSettle();
      expect(findOrionTitle('Signal Flare'), findsOneWidget);
    }

    Finder fireButton(int count) => find.byKey(ValueKey('flare-fire-$count'));

    testWidgets('the Flare tab shows the fixed rates, balance and both '
        'packs', (tester) async {
      final store = _TestCampaignProgressStore(scrip: 1240);
      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();
      await openFlare(tester);

      // The shell top bar carries the committed wallet next to the medals.
      expect(find.bySemanticsLabel('1,240 Scrip'), findsOneWidget);
      expect(find.bySemanticsLabel('0 of 21 campaign medals'), findsOneWidget);
      expect(find.text('WHO ANSWERS'), findsOneWidget);
      for (final rate in ['0.1%', '0.5%', '2%', '10%', '20%', '67.4%']) {
        expect(find.text(rate), findsOneWidget, reason: 'rate $rate');
      }
      expect(find.text('FIRE FLARE · 100'), findsOneWidget);
      expect(find.text('FIRE 10 · 1,000'), findsOneWidget);
    });

    testWidgets(
      'a fired flare rolls inside the queued save, commits one atomic '
      'write and reveals the batch without touching the squad',
      (tester) async {
        final store = _TestCampaignProgressStore(scrip: 1240);
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            // D-rank roll, first D pick → sayo, new to the starter roster.
            flareRandom: _ScriptedRandom([6740, 0]),
          ),
        );
        await tester.pumpAndSettle();
        await openFlare(tester);

        await tester.tap(fireButton(1));
        await tester.pumpAndSettle();

        // One write carried fee + recruit + no squad edit in a single
        // payload — 100 for the pack, sayo joins at level 1, squad stays
        // the two starters.
        expect(store.saveCalls, 1);
        expect(store.scrip, 1140);
        expect(store.ownedLevels[Character.sayo], 1);
        expect(store.squad, CampaignSave.starterSquad);

        // The committed result is revealed: kicker, hero card, draw tile,
        // refund summary and the post-pack balance in shell and summary.
        expect(find.text('1 FLARE FIRED'), findsOneWidget);
        expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);
        expect(find.byKey(const ValueKey('flare-draw-0')), findsOneWidget);
        expect(find.text('0 SPARE DOG TAGS TRADED'), findsOneWidget);
        expect(find.text('BALANCE'), findsOneWidget);
        // The balance readout and the shell's Scrip chip both carry 1,140.
        expect(find.text('1,140'), findsWidgets);
        expect(find.bySemanticsLabel('1,140 Scrip'), findsOneWidget);

        // TO ROSTER lands on Camp, where the recruit reads owned at
        // level 1 and the squad count is untouched.
        await tester.tap(find.byKey(const ValueKey('flare-to-roster')));
        await tester.pumpAndSettle();
        expect(findOrionTitle('Camp'), findsOneWidget);
        expect(find.text('SQUAD 2/6'), findsOneWidget);
        final sayoCard = find.byKey(const ValueKey('camp-card-sayo'));
        await tester.scrollUntilVisible(
          sayoCard,
          250,
          scrollable: find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          find.descendant(of: sayoCard, matching: find.text('Lv 1')),
          findsOneWidget,
        );

        // Returning to Flare shows the fire screen again — the revealed
        // batch does not linger across destinations.
        await tester.tap(find.byTooltip('Flare'));
        await tester.pumpAndSettle();
        expect(find.text('WHO ANSWERS'), findsOneWidget);
        expect(find.text('1 FLARE FIRED'), findsNothing);
      },
    );

    testWidgets('a ten-pull shows every ordered draw, refund totals and the '
        'resulting balance', (tester) async {
      final store = _TestCampaignProgressStore(scrip: 1240);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          // Rank roll then same-rank pick per draw:
          // sayo NEW, haruto dup+10, tetsuo NEW, mio dup+10, hikari NEW,
          // sayo in-batch dup+25, haruto dup+10, kaito NEW, mio dup+10,
          // elena NEW → 5 recruits, 65 refunded, balance 305.
          flareRandom: _ScriptedRandom([
            6740,
            0,
            0,
            0,
            6740,
            1,
            0,
            1,
            9990,
            0,
            6740,
            0,
            0,
            0,
            8740,
            1,
            0,
            1,
            9740,
            0,
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      await tester.tap(fireButton(10));
      await tester.pumpAndSettle();

      expect(store.saveCalls, 1);
      expect(store.scrip, 305);
      for (final recruit in [
        Character.sayo,
        Character.tetsuo,
        Character.hikari,
        Character.kaito,
        Character.elena,
      ]) {
        expect(store.ownedLevels[recruit], 1, reason: recruit.name);
      }
      expect(store.squad, CampaignSave.starterSquad);

      expect(find.text('10 FLARES FIRED'), findsOneWidget);
      expect(findOrionTitle('5 new recruits'), findsOneWidget);
      for (var index = 0; index < 10; index += 1) {
        expect(
          find.byKey(ValueKey('flare-draw-$index')),
          findsOneWidget,
          reason: 'draw $index',
        );
      }
      expect(find.text('5 SPARE DOG TAGS TRADED'), findsOneWidget);
      expect(find.text('+65 Scrip'), findsOneWidget);
      // The balance readout and the shell's Scrip chip both carry 305.
      expect(find.text('305'), findsWidgets);

      // FIRE AGAIN returns to the fire screen for another roll.
      await tester.tap(find.byKey(const ValueKey('flare-again')));
      await tester.pumpAndSettle();
      expect(find.text('WHO ANSWERS'), findsOneWidget);
      expect(find.text('FIRE FLARE · 100'), findsOneWidget);
    });

    testWidgets('the batch is revealed only after the save commits', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(scrip: 1240, delaySaves: true);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          flareRandom: _ScriptedRandom([6740, 0]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      await tester.tap(fireButton(1));
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      await tester.pump();

      // The write is still in flight: nothing is revealed and the fired
      // button holds its spinner while both stay inert.
      expect(find.text('1 FLARE FIRED'), findsNothing);
      expect(find.text('SAVING…'), findsOneWidget);
      expect(find.byKey(const ValueKey('flare-draw-0')), findsNothing);
      expect(
        tester.widget<OrionPrimaryButton>(fireButton(1)).onPressed,
        isNull,
      );

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      expect(find.text('1 FLARE FIRED'), findsOneWidget);
      expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);
    });

    testWidgets('a failed save keeps balance, roster and place; a retry '
        'rolls fresh', (tester) async {
      final store = _TestCampaignProgressStore(
        scrip: 1240,
        delaySaves: true,
        failOnSaveIndices: {0},
      );
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          // First roll recruits sayo (rejected write); the retry consumes
          // the next scripted pair and recruits tetsuo instead.
          flareRandom: _ScriptedRandom([6740, 0, 6740, 1]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      await tester.tap(fireButton(1));
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();

      // The shell breadcrumb reports on the Flare screen; nothing moved —
      // no result, no Scrip, no roster change, no navigation.
      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      expect(findOrionTitle('Signal Flare'), findsOneWidget);
      expect(find.text('1 FLARE FIRED'), findsNothing);
      expect(find.bySemanticsLabel('1,240 Scrip'), findsOneWidget);
      expect(store.saveCalls, 1);
      expect(store.scrip, 1240);
      expect(store.ownedLevels, CampaignSave.starterOwnedLevels);

      // Retry is a fresh roll — the second scripted pair recruits tetsuo.
      await tester.tap(fireButton(1));
      await _pumpUntil(tester, () => store.saveCompletions.length > 1);
      store.saveCompletions[1].complete();
      await tester.pumpAndSettle();

      expect(store.saveCalls, 2);
      expect(store.scrip, 1140);
      expect(store.ownedLevels[Character.tetsuo], 1);
      expect(store.ownedLevels.containsKey(Character.sayo), isFalse);
      expect(find.byKey(const ValueKey('flare-hero-tetsuo')), findsOneWidget);
      expect(find.text('Could not save campaign progress.'), findsNothing);
    });

    testWidgets('flare purchases are single-flight on rapid taps', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(scrip: 1240, delaySaves: true);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          // A second queued purchase could still roll and commit — the
          // script must survive long enough for that to be observable.
          flareRandom: _ScriptedRandom([6740, 0, 6740, 1]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      // Both presses land before the busy rebuild: the page guard must
      // collapse them into one queued write.
      final fire = fireButton(1);
      await tester.tap(fire);
      await tester.tap(fire);
      await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
      expect(store.saveCalls, 1);
      expect(store.saveCompletions, hasLength(1));

      // While the write is in flight a further tap reaches nothing.
      await tester.tap(fire);
      await tester.pump();
      expect(store.saveCalls, 1);

      store.saveCompletions[0].complete();
      await tester.pumpAndSettle();
      expect(store.saveCalls, 1);
      expect(store.scrip, 1140);
      // Rejected, not silently failed: no second write and no failure
      // breadcrumb from an exhausted or refused second roll.
      expect(find.text('Could not save campaign progress.'), findsNothing);
      expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);
    });

    testWidgets('a committed result awaiting its frame rejects a second '
        'fire dispatched by the stale button', (tester) async {
      // Immediate (undelayed) saves: the queued write drains on the tap's
      // own microtask flush, so _flareResult commits and _isBusy clears
      // before any rebuild — the previously rendered enabled Fire button
      // is what a second tap still dispatches against.
      final store = _TestCampaignProgressStore(scrip: 1240);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          flareRandom: _ScriptedRandom([6740, 0, 6740, 1]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      // Both presses land on the same stale fire screen — no pump between.
      final fire = fireButton(1);
      await tester.tap(fire);
      await tester.tap(fire);
      await tester.pumpAndSettle();

      // One write, one debit, and the FIRST batch revealed — a second
      // purchase must not have replaced the unseen result.
      expect(store.saveCalls, 1);
      expect(store.scrip, 1140);
      expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);
      expect(find.byKey(const ValueKey('flare-hero-tetsuo')), findsNothing);

      // FIRE AGAIN clears the committed batch and re-arms the packs: the
      // intended repeat-purchase path rolls the second scripted pair.
      await tester.tap(find.byKey(const ValueKey('flare-again')));
      await tester.pumpAndSettle();
      await tester.tap(fire);
      await tester.pumpAndSettle();
      expect(store.saveCalls, 2);
      expect(store.scrip, 1040);
      expect(find.byKey(const ValueKey('flare-hero-tetsuo')), findsOneWidget);
    });

    testWidgets('insufficient committed funds keep the pack off the write '
        'path', (tester) async {
      final store = _TestCampaignProgressStore(scrip: 500);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          // No values scripted: a reached roll would throw out of values.
          flareRandom: _ScriptedRandom([]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      // Fire 1 is affordable (500 >= 100); Fire 10 is not — the readable
      // reason rides above the disabled pack.
      expect(find.text('NEEDS 1,000 SCRIP'), findsOneWidget);
      expect(
        tester.widget<OrionPrimaryButton>(fireButton(10)).onPressed,
        isNull,
      );
      await tester.tap(fireButton(10));
      await tester.pumpAndSettle();
      expect(store.saveCalls, 0);
    });

    testWidgets('a Flare-route reset failure renders the shell breadcrumb', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(
        scrip: 1240,
        resetResults: [StateError('reset failed')],
      );
      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();
      await openFlare(tester);

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      // The failure must land on the visible shell line — not the hidden
      // map breadcrumb the old camp||codex branch would have used.
      expect(find.text('Could not reset campaign progress.'), findsOneWidget);
      expect(findOrionTitle('Signal Flare'), findsOneWidget);
      expect(find.bySemanticsLabel('1,240 Scrip'), findsOneWidget);
      expect(store.scrip, 1240);
      expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
    });

    testWidgets(
      'rejected purchases report domain reasons instead of save failure',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: GameBalance.characterMaxLevel,
            Character.mio: 1,
          },
          squad: const [Character.haruto, Character.mio],
          scrip: 10,
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();

        // Camp: unaffordable level-up reports "Not enough Scrip.".
        await tester.tap(find.byTooltip('Camp'));
        await tester.pumpAndSettle();
        final campView = tester.widget<CampView>(find.byType(CampView));
        campView.onLevelUp!(Character.mio, 1);
        await tester.pumpAndSettle();
        expect(find.text('Not enough Scrip.'), findsOneWidget);
        expect(find.text('Could not save campaign progress.'), findsNothing);

        // Camp: max-level character reports "Already at max level.".
        campView.onLevelUp!(Character.haruto, GameBalance.characterMaxLevel);
        await tester.pumpAndSettle();
        expect(find.text('Already at max level.'), findsOneWidget);
        expect(find.text('Could not save campaign progress.'), findsNothing);

        // Flare: unaffordable pack reports "Not enough Scrip.".
        await tester.tap(find.byTooltip('Flare'));
        await tester.pumpAndSettle();
        final flareView = tester.widget<FlareView>(find.byType(FlareView));
        flareView.onFire!(1);
        await tester.pumpAndSettle();
        expect(find.text('Not enough Scrip.'), findsOneWidget);
        expect(find.text('Could not save campaign progress.'), findsNothing);
        expect(store.saveCalls, 0);
      },
    );

    testWidgets('a Flare-route feedback-save failure renders the shell '
        'breadcrumb', (tester) async {
      final store = _TestCampaignProgressStore(scrip: 1240);
      final feedbackStore = _FailingFeedbackPreferencesStore(
        value: const FeedbackPreferences(
          soundEffectsEnabled: true,
          hapticsEnabled: true,
        ),
      );
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          feedbackPreferencesStore: feedbackStore,
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save feedback settings.'), findsOneWidget);
      expect(findOrionTitle('Signal Flare'), findsOneWidget);
    });

    testWidgets('an in-flight reset holds flare packs off the write path', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(scrip: 1240, delayResets: true);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          flareRandom: _ScriptedRandom([6740, 0]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await _pumpUntil(tester, () => store.resetCompletions.isNotEmpty);
      await tester.pump();

      // While the reset runs both packs are inert with a readable reason —
      // no purchase may queue behind the wipe.
      expect(find.text('SAVING…'), findsOneWidget);
      expect(
        tester.widget<OrionPrimaryButton>(fireButton(1)).onPressed,
        isNull,
      );
      await tester.tap(fireButton(1));
      await tester.tap(fireButton(10));
      await tester.pump();
      expect(store.saveCalls, 0);

      store.resetCompletions.single.complete();
      await tester.pumpAndSettle();

      // The wiped profile republishes: 'Campaign reset.' shows, the wallet
      // is 0 and the packs gate on funds instead of writing.
      expect(find.text('Campaign reset.'), findsOneWidget);
      expect(find.bySemanticsLabel('0 Scrip'), findsWidgets);
      expect(find.text('NEEDS 100 SCRIP'), findsOneWidget);
      expect(store.saveCalls, 0);
      expect(store.scrip, 0);
      expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
    });

    testWidgets('a newly recruited character is selectable in the briefing '
        'picker but never squad-edited', (tester) async {
      final store = _TestCampaignProgressStore(scrip: 1240);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          flareRandom: _ScriptedRandom([6740, 0]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);
      await tester.tap(fireButton(1));
      await tester.pumpAndSettle();
      expect(store.ownedLevels[Character.sayo], 1);
      expect(store.squad, CampaignSave.starterSquad);

      // The briefing's squad picker now offers sayo among owned members.
      await tester.tap(find.byTooltip('Map'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Alpha'));
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('briefing-squad-edit')),
      );
      await tester.tap(find.byKey(const ValueKey('briefing-squad-edit')));
      await tester.pumpAndSettle();
      final sayoPick = find.byKey(const ValueKey('briefing-squad-pick-sayo'));
      await tester.ensureVisible(sayoPick);
      expect(sayoPick, findsOneWidget);
      // And the committed squad is still the two starters — the draft
      // stayed untouched by the recruitment.
      expect(
        find.byKey(const ValueKey('briefing-squad-token-haruto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-squad-token-sayo')),
        findsNothing,
      );
    });

    testWidgets('a successful reset clears an open flare result', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(scrip: 1240);
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          flareRandom: _ScriptedRandom([6740, 0]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);
      await tester.tap(fireButton(1));
      await tester.pumpAndSettle();
      expect(find.text('1 FLARE FIRED'), findsOneWidget);
      expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      // The wiped profile cannot back a stale reveal: the result is
      // dismissed to the fire screen, the balance reads the reset wallet
      // and the recruit is gone from the save.
      expect(find.text('Campaign reset.'), findsOneWidget);
      expect(findOrionTitle('Signal Flare'), findsOneWidget);
      expect(find.text('1 FLARE FIRED'), findsNothing);
      expect(find.byKey(const ValueKey('flare-hero-sayo')), findsNothing);
      expect(find.text('WHO ANSWERS'), findsOneWidget);
      expect(find.bySemanticsLabel('0 Scrip'), findsWidgets);
      expect(find.text('NEEDS 100 SCRIP'), findsOneWidget);
      expect(store.scrip, 0);
      expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
    });

    testWidgets('a failed reset preserves an open flare result', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(
        scrip: 1240,
        resetResults: [StateError('reset failed')],
      );
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          flareRandom: _ScriptedRandom([6740, 0]),
        ),
      );
      await tester.pumpAndSettle();
      await openFlare(tester);
      await tester.tap(fireButton(1));
      await tester.pumpAndSettle();
      expect(find.text('1 FLARE FIRED'), findsOneWidget);

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      // The committed batch still matches the committed profile — nothing
      // about the reveal is dismissed by the rejected wipe.
      expect(find.text('Could not reset campaign progress.'), findsOneWidget);
      expect(find.text('1 FLARE FIRED'), findsOneWidget);
      expect(find.byKey(const ValueKey('flare-hero-sayo')), findsOneWidget);
      expect(find.bySemanticsLabel('1,140 Scrip'), findsOneWidget);
      expect(store.scrip, 1140);
      expect(store.ownedLevels[Character.sayo], 1);
    });
  });

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
          ),
        ),
      ),
    );

    expect(find.text('SECTOR MAP'), findsOneWidget);
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
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Core'));
    await tester.pump();
    await tester.tap(find.text('Core'));
    expect(selected, isEmpty);
    expect(locked, ['singularity-core']);

    await tester.ensureVisible(find.text('Alpha'));
    await tester.pump();
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
            ),
          ),
        ),
      );

      // Tapping a locked stage while busy must not fire either callback.
      await tester.ensureVisible(find.text('Core'));
      await tester.pump();
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
        character: Character.haruto,
        position: GridPosition(0, 0),
        targetingMode: TowerTargetingMode.strongest,
      );
      game!.stateNotifier.value = GameSnapshot(
        phase: GamePhase.build,
        gold: snapshot.gold,
        baseHealth: snapshot.baseHealth,
        startingBaseHealth: snapshot.startingBaseHealth,
        waveNumber: snapshot.waveNumber,
        missionWaveTotal: snapshot.missionWaveTotal,
        wavesCleared: snapshot.wavesCleared,
        stageId: snapshot.stageId,
        stageName: snapshot.stageName,
        stageLabel: snapshot.stageLabel,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
        squad: snapshot.squad,
        squadLevels: snapshot.squadLevels,
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
      await tester.tap(find.byTooltip('Inspect member'));
      await tester.pump();

      for (final mode in TowerTargetingMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tower-target-strongest')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
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
      character: Character.haruto,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.wave,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      missionWaveTotal: snapshot.missionWaveTotal,
      wavesCleared: snapshot.wavesCleared,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      squad: snapshot.squad,
      squadLevels: snapshot.squadLevels,
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
    await tester.tap(find.byTooltip('Inspect member'));
    await tester.pump();

    final firstCell = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('tower-target-first')),
        matching: find.byType(InkWell),
      ),
    );
    expect(firstCell.onTap, isNull);
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
      character: Character.haruto,
      position: GridPosition(0, 0),
      targetingMode: TowerTargetingMode.first,
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      missionWaveTotal: snapshot.missionWaveTotal,
      wavesCleared: snapshot.wavesCleared,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      squad: snapshot.squad,
      squadLevels: snapshot.squadLevels,
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
    await tester.tap(find.byTooltip('Inspect member'));
    await tester.pump();

    // The game session has no real selected member, so retargeting reports
    // the "select a member first" feedback — proving the chip callback ran.
    // The command-deck status HUD intentionally no longer renders legacy
    // feedback copy, so assert the snapshot seam instead of a removed text
    // label.
    await tester.tap(find.text('Weakest'));
    await tester.pump();

    expect(game!.snapshot.feedback, 'Select a member first.');
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
      character: Character.haruto,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.build,
      gold: snapshot.gold,
      baseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveNumber,
      missionWaveTotal: snapshot.missionWaveTotal,
      wavesCleared: snapshot.wavesCleared,
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      stageLabel: snapshot.stageLabel,
      unlockedTowerTypes: snapshot.unlockedTowerTypes,
      squad: snapshot.squad,
      squadLevels: snapshot.squadLevels,
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
    await tester.tap(find.byTooltip('Inspect member'));
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
          ownedLevels: CampaignSave.starterOwnedLevels,
          squad: CampaignSave.starterSquad,
          scrip: 0,
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
        ownedLevels: CampaignSave.starterOwnedLevels,
        squad: CampaignSave.starterSquad,
        scrip: 0,
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
          ownedLevels: CampaignSave.starterOwnedLevels,
          squad: CampaignSave.starterSquad,
          scrip: 0,
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
    'cleared Alpha world map shows blueprint recovered, other stages stay locked',
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
      expectSemanticsLabel(
        tester,
        RegExp(r'Outpost Alpha.*Blueprint • Locked'),
        findsNothing,
      );
      // Every other blueprint stage node keeps its Locked signal.
      expectSemanticsLabel(
        tester,
        RegExp(r'Blueprint • Locked'),
        findsNWidgets(6),
      );
      expectSemanticsLabel(
        tester,
        RegExp(r'Nebula Relay.*Blueprint • Locked'),
        findsOneWidget,
      );
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

    final module = runModuleDefinition(OrionCampaign.stageOne.blueprint!);
    expect(
      find.text('Blueprint recovered: ${module.title} • ${module.effectText}'),
      findsOneWidget,
    );
  });

  testWidgets('fresh Alpha briefing teases the locked blueprint module', (
    tester,
  ) async {
    final store = InMemoryCampaignProgressStore(
      knownStages: OrionCampaign.stages,
    );

    await tester.pumpWidget(testGamePage(progressStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final module = runModuleDefinition(OrionCampaign.stageOne.blueprint!);
    expect(
      find.text('Blueprint locked: ${module.title} • ${module.effectText}'),
      findsOneWidget,
    );
    expect(find.textContaining('Blueprint recovered'), findsNothing);
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

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expectSemanticsLabel(
        tester,
        RegExp(r'Outpost Alpha.*Blueprint • Locked'),
        findsOneWidget,
      );
      // The reset re-derives Locked for all seven blueprint stages.
      expectSemanticsLabel(
        tester,
        RegExp(r'Blueprint • Locked'),
        findsNWidgets(7),
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
    InkWell settingsGear() => tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Settings'),
        matching: find.byType(InkWell),
      ),
    );
    expect(settingsGear().onTap, isNull);
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
    expect(settingsGear().onTap, isNotNull);

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

    await openResetCampaignDialog(tester);
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

  testWidgets(
    'a changed settings draft finishes saving before the reset dialog '
    'opens',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
      );
      final feedbackStore = _DelayedFeedbackPreferencesStore(
        value: const FeedbackPreferences(hapticsEnabled: false),
      );

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          feedbackPreferencesStore: feedbackStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Haptics'));
      await tester.pump();
      await tester.tap(find.text('Reset Campaign'));
      await tester.pumpAndSettle();

      expect(feedbackStore.saveCompletions, hasLength(1));
      expect(find.byKey(const ValueKey('reset-campaign-dialog')), findsNothing);
      expect(store.resetCalls, 0);

      feedbackStore.saveCompletions.single.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reset-campaign-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(store.resetCalls, 1);
      expect(
        feedbackStore.value,
        const FeedbackPreferences(hapticsEnabled: true),
      );
      expect(find.text('Campaign reset.'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed settings save shows the error and never opens the reset '
    'dialog',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
      );
      final feedbackStore = _FailingFeedbackPreferencesStore();

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          feedbackPreferencesStore: feedbackStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Haptics'));
      await tester.pump();
      await tester.tap(find.text('Reset Campaign'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save feedback settings.'), findsOneWidget);
      expect(find.byKey(const ValueKey('reset-campaign-dialog')), findsNothing);
      expect(store.resetCalls, 0);
    },
  );

  testWidgets(
    'cancelling the reset dialog keeps the already-saved preferences',
    (tester) async {
      final store = _TestCampaignProgressStore(
        progress: _progressWithResults({'outpost-alpha'}),
      );
      final feedbackStore = InMemoryFeedbackPreferencesStore(
        value: const FeedbackPreferences(hapticsEnabled: false),
      );

      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          feedbackPreferencesStore: feedbackStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Haptics'));
      await tester.pump();
      await tester.tap(find.text('Reset Campaign'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reset-campaign-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(store.resetCalls, 0);
      expect(
        feedbackStore.value,
        const FeedbackPreferences(hapticsEnabled: true),
      );
      expect(find.text('Campaign reset.'), findsNothing);
    },
  );

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
    // whose enabled-closures read _feedbackPreferences. The audioplayers
    // channels are stubbed by the shared test/flutter_test_config.dart;
    // stub haptics here so the detached emit futures complete (with errors
    // PlatformGameFeedback swallows) instead of hanging on a missing engine.
    final binding = TestWidgetsFlutterBinding.instance;
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
          startOnWorldMap: true,
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
      // The audioplayers channels are stubbed by the shared
      // test/flutter_test_config.dart; only haptics need a local mock here.
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
            startOnWorldMap: true,
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
              startOnWorldMap: true,
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
      expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
      expect(find.byTooltip('Start Mission'), findsOneWidget);

      // Dismiss without starting the mission.
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Start Mission'), findsNothing);

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
              startOnWorldMap: true,
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

  // --- HPA-412 first-mission guidance: real-path, soft behavior, lifetime.

  testWidgets('first-mission guide walks the full fresh Alpha path to Got it', (
    tester,
  ) async {
    final guideStore = InMemoryFirstMissionGuideStore();
    final game = await pumpMountedMission(
      tester,
      firstMissionGuideStore: guideStore,
      moduleOfferPicker: _ScriptedModuleOfferPicker(_scriptedModuleOffers),
    );

    // Fresh Alpha build: the first callout points at the (2, 2) cell.
    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tapping the guided cell flips the callout to the tower lesson.
    await tapBoardCell(tester, game, const GridPosition(2, 2));
    expect(find.text('Pick a squad member.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Picking the laser mounts the tower and moves on to the wave copy.
    await tester.tap(find.byKey(const ValueKey('tower-card-haruto')));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        "Start the wave when you're ready. Your squad fires on their own.",
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // While Wave 1 is active no guide shows at all.
    await tester.tap(find.byTooltip('Start Wave'));
    await tester.pump();
    await tester.pump();
    expect(game.snapshot.phase, GamePhase.wave);
    expect(find.byType(FirstMissionGuideCallout), findsNothing);

    // Wave 1 clears into the Wave-2 build: the upgrade lesson appears.
    await advanceUntil(
      tester,
      game,
      (snapshot) =>
          snapshot.phase == GamePhase.build && snapshot.waveNumber == 2,
    );
    expect(
      find.text('Tap a deployed member, then Upgrade between waves.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Tapping the placed tower re-anchors the same copy on the radial
    // Upgrade control; upgrading past the lesson silences the guide.
    await tapBoardCell(tester, game, const GridPosition(2, 2));
    expect(
      find.text('Tap a deployed member, then Upgrade between waves.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Upgrade 70'));
    await tester.pump();
    await tester.pump();
    expect(game.snapshot.placedTowers.single.level, 2);
    expect(find.byType(FirstMissionGuideCallout), findsNothing);

    // Wave 2 ends in the first module draft: the salvage lesson.
    await tester.tap(find.byTooltip('Start Wave'));
    await tester.pump();
    await advanceUntil(
      tester,
      game,
      (snapshot) => snapshot.pendingRunModuleOffer != null,
    );
    // The anchored callout renders nothing until its post-frame measure
    // lands — give it a frame to attach.
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Salvage Modules last only for this mission.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Any offered module hands off to the scanner lesson.
    await tester.tap(find.text('Heavy Caliber'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Check the scanner before the next wave.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // The anchored scanner callout takes three frames to reveal — hidden
    // while the anchor measures, invisible while the bubble measures —
    // before its buttons are tappable.
    await tester.pump();

    // Got it completes the guide and retires the callout for this run.
    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump();
    expect(guideStore.completed, isTrue);
    expect(find.byType(FirstMissionGuideCallout), findsNothing);
  });

  testWidgets(
    'laser drag from the idle rail commits straight to the wave lesson',
    (tester) async {
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
      );
      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

      // Long-press-drag Laser from the persistent rail onto a buildable cell;
      // the soft callout never joins the gesture arena.
      final start = tester.getCenter(
        find.byKey(const ValueKey('tower-card-haruto')),
      );
      final dropTarget = boardCellPoint(tester, game, const GridPosition(4, 8));
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(dropTarget - start);
      await tester.pump();
      await tester.pump();
      expect(game.placementPreview.allowed, isTrue);
      await gesture.up();
      await tester.pump();
      await tester.pump();

      // Committed without ever selecting a cell first: the guide moves
      // straight to the wave copy.
      expect(game.stateNotifier.value.gold, GameBalance.startingGold - 50);
      expect(
        find.text(
          "Start the wave when you're ready. Your squad fires on their own.",
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a tower upgraded before Wave 1 clears silences the Wave-2 upgrade guide',
    (tester) async {
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
      );

      // Build and upgrade the laser out of order, before Wave 1 ever starts.
      await tapBoardCell(tester, game, const GridPosition(2, 2));
      await tester.tap(find.byKey(const ValueKey('tower-card-haruto')));
      await tester.pump();
      await tester.pump();
      await tapBoardCell(tester, game, const GridPosition(2, 2));
      await tester.tap(find.byTooltip('Upgrade 70'));
      await tester.pump();
      await tester.pump();
      expect(game.snapshot.placedTowers.single.level, 2);

      await tester.tap(find.byTooltip('Start Wave'));
      await tester.pump();
      await advanceUntil(
        tester,
        game,
        (snapshot) =>
            snapshot.phase == GamePhase.build && snapshot.waveNumber == 2,
      );

      // The upgrade milestone is already behind the player: no guide at all.
      expect(find.byType(FirstMissionGuideCallout), findsNothing);
      expect(
        find.text('Tap a deployed member, then Upgrade between waves.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'selecting a tower while gold is short of the upgrade cost shows no '
    'callout on the disabled Upgrade button',
    (tester) async {
      final drainStore = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await drainStore.save(
        CampaignSave(
          progress: CampaignProgress(),
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 1,
            Character.jin: 1,
            Character.elena: 1,
          },
          squad: const [
            Character.haruto,
            Character.mio,
            Character.jin,
            Character.elena,
          ],
          scrip: 0,
        ),
      );
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
        progressStore: drainStore,
        // The warm-up must cover every chibi this seeded squad preloads.
        squad: const [
          Character.haruto,
          Character.mio,
          Character.jin,
          Character.elena,
        ],
      );

      await tapBoardCell(tester, game, const GridPosition(2, 2));
      await tester.tap(find.byKey(const ValueKey('tower-card-haruto')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Start Wave'));
      await tester.pump();
      await advanceUntil(
        tester,
        game,
        (snapshot) =>
            snapshot.phase == GamePhase.build && snapshot.waveNumber == 2,
      );
      expect(
        find.text('Tap a deployed member, then Upgrade between waves.'),
        findsOneWidget,
      );

      // Drain gold below the 70g upgrade cost so the selected tower's
      // Upgrade button renders disabled. Upgrading any tower would mark the
      // milestone learned, so drain with placements only — needs a seeded
      // squad bigger than the two-member starter.
      const fillerCells = [
        GridPosition(0, 0),
        GridPosition(1, 0),
        GridPosition(3, 0),
        GridPosition(4, 0),
        GridPosition(5, 0),
        GridPosition(7, 0),
      ];
      const drainSquad = [
        Character.haruto,
        Character.mio,
        Character.jin,
        Character.elena,
      ];
      var placed = 0;
      while (game.snapshot.gold >= 70 && placed < drainSquad.length) {
        await tapBoardCell(tester, game, fillerCells[placed]);
        await tester.tap(
          find.byKey(ValueKey('tower-card-${drainSquad[placed].name}')),
        );
        await tester.pump();
        await tester.pump();
        placed += 1;
      }
      expect(game.snapshot.gold, lessThan(70));

      // Selected + unaffordable: the callout stays away rather than
      // pointing at a button that cannot respond.
      await tapBoardCell(tester, game, const GridPosition(2, 2));
      expect(game.snapshot.selectedTower, isNotNull);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FirstMissionGuideCallout), findsNothing);

      // Deselecting restores the hint, anchored back on the tower cell.
      await tapBoardCell(tester, game, const GridPosition(6, 0));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Tap a deployed member, then Upgrade between waves.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selecting a path cell keeps the build-cell lesson instead of the tower '
    'card',
    (tester) async {
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
      );
      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

      // (3, 2) is a path cell on Alpha: it still selects (enemies stay
      // inspectable there during waves), but no tower can be placed on it,
      // so the guide must not advance to a card that can only fail.
      await tapBoardCell(tester, game, const GridPosition(3, 2));
      expect(game.snapshot.selectedCell, const GridPosition(3, 2));
      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
      expect(find.text('Pick a squad member.'), findsNothing);

      // A buildable selection still advances the lesson as before.
      await tapBoardCell(tester, game, const GridPosition(2, 2));
      expect(find.text('Pick a squad member.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selecting a cell or tower during the scanner lesson redirects it to a '
    'usable target',
    (tester) async {
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
        moduleOfferPicker: _ScriptedModuleOfferPicker(_scriptedModuleOffers),
      );

      // Reach the Wave-3 scanner lesson with the laser still at Level 1.
      await tapBoardCell(tester, game, const GridPosition(2, 2));
      await tester.tap(find.byKey(const ValueKey('tower-card-haruto')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Start Wave'));
      await tester.pump();
      await advanceUntil(
        tester,
        game,
        (snapshot) =>
            snapshot.phase == GamePhase.build && snapshot.waveNumber == 2,
      );
      await tester.tap(find.byTooltip('Start Wave'));
      await tester.pump();
      await advanceUntil(
        tester,
        game,
        (snapshot) => snapshot.pendingRunModuleOffer != null,
      );
      await tester.tap(find.text('Heavy Caliber'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Check the scanner before the next wave.'),
        findsOneWidget,
      );

      // A cell selection collapses the scanner into a control that ignores
      // taps: the callout leaves it and points at the still-pending upgrade
      // milestone instead.
      await tapBoardCell(tester, game, const GridPosition(4, 8));
      expect(game.snapshot.selectedCell, const GridPosition(4, 8));
      expect(
        find.text('Check the scanner before the next wave.'),
        findsNothing,
      );
      expect(
        find.text('Tap a deployed member, then Upgrade between waves.'),
        findsOneWidget,
      );

      // Selecting the tower collapses the scanner the same way; the upgrade
      // copy re-anchors on the radial's usable Upgrade surface.
      await tapBoardCell(tester, game, const GridPosition(2, 2));
      expect(game.snapshot.selectedTower, isNotNull);
      expect(
        find.text('Check the scanner before the next wave.'),
        findsNothing,
      );
      expect(
        find.text('Tap a deployed member, then Upgrade between waves.'),
        findsOneWidget,
      );

      // Deselecting restores the scanner callout once the control can open.
      game.handleBoardTap(const Offset(-1, -1));
      await tester.pump();
      await tester.pump();
      expect(game.snapshot.selectedCell, isNull);
      expect(game.snapshot.selectedTower, isNull);
      expect(
        find.text('Check the scanner before the next wave.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the guide callout leaves gameplay interactive while visible', (
    tester,
  ) async {
    final game = await pumpMountedMission(
      tester,
      firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
    );
    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

    // With the callout up, another buildable cell still selects: the
    // tutorial guides, it never hard-locks the game. Selecting the cell
    // advances the (still visible) callout to the tower lesson.
    await tapBoardCell(tester, game, const GridPosition(6, 0));
    expect(game.stateNotifier.value.selectedCell, const GridPosition(6, 0));
    expect(find.text('Pick a squad member.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed guide never shows on a fresh Alpha run', (
    tester,
  ) async {
    await pumpMountedMission(
      tester,
      firstMissionGuideStore: InMemoryFirstMissionGuideStore(completed: true),
    );

    expect(find.byType(FirstMissionGuideCallout), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first-mission guide stays exclusive to Alpha', (
    tester,
  ) async {
    final progressStore = await storeWithResults({
      'outpost-alpha': const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
    });

    // An absent record would resolve through the committed Alpha result —
    // only an explicit false leaves the stage gate as the sole suppressor.
    await pumpMountedMission(
      tester,
      mapLabel: 'Relay',
      progressStore: progressStore,
      firstMissionGuideStore: InMemoryFirstMissionGuideStore(completed: false),
    );

    expect(find.byType(FirstMissionGuideCallout), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'skipping the first callout completes the guide for the next Alpha run',
    (tester) async {
      final guideStore = InMemoryFirstMissionGuideStore();
      await pumpMountedMission(tester, firstMissionGuideStore: guideStore);
      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

      await tester.tap(find.text('Skip tutorial'));
      await tester.pump();
      await tester.pump();
      expect(guideStore.completed, isTrue);
      expect(find.byType(FirstMissionGuideCallout), findsNothing);

      // Retire the first run's mounted game loop before relaunching, or its
      // live ticker keeps the next pumpAndSettle from ever settling.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));

      // Relaunching Alpha with the same persisted store shows no guide.
      await pumpMountedMission(tester, firstMissionGuideStore: guideStore);
      expect(find.byType(FirstMissionGuideCallout), findsNothing);
    },
  );

  testWidgets(
    'starting the next wave from the scanner callout completes the guide',
    (tester) async {
      final guideStore = InMemoryFirstMissionGuideStore();
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: guideStore,
      );

      // Project the Wave-3 post-draft state so the scanner lesson is up.
      game.stateNotifier.value = commandDeckSnapshot(
        waveNumber: 3,
        nextWavePreview: commandDeckPreview(waveNumber: 3),
        acquiredRunModules: const [RunModuleId.heavyCaliber],
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Check the scanner before the next wave.'),
        findsOneWidget,
      );
      expect(find.text('Got it'), findsOneWidget);

      // Starting the wave instead of tapping Got it still completes.
      await tester.tap(find.byTooltip('Start Wave'));
      await tester.pump();
      await tester.pump();
      expect(guideStore.completed, isTrue);
      expect(find.byType(FirstMissionGuideCallout), findsNothing);
    },
  );

  testWidgets(
    'a wave starting past the scanner lesson completes the guide even '
    'without the button path',
    (tester) async {
      final guideStore = InMemoryFirstMissionGuideStore();
      final game = await pumpMountedMission(
        tester,
        firstMissionGuideStore: guideStore,
      );

      // The auto-start countdown calls game.startWave() directly, so the
      // chrome's onStartWave never runs: completion must derive from the
      // snapshot itself — the wave left the build phase under the scanner
      // lesson's preconditions.
      game.stateNotifier.value = commandDeckSnapshot(
        phase: GamePhase.wave,
        waveNumber: 3,
        acquiredRunModules: const [RunModuleId.heavyCaliber],
      );
      await tester.pump();
      await tester.pump();

      expect(guideStore.completed, isTrue);
      expect(find.byType(FirstMissionGuideCallout), findsNothing);
    },
  );

  testWidgets(
    'a committed Alpha result with no guide record suppresses the tutorial',
    (tester) async {
      // The player cleared Outpost Alpha before the guide flag existed, so
      // a never-written guide store resolves the flag through campaign
      // progress: no record + an Alpha result means completed.
      final progressStore = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: 14,
        ),
      });
      await pumpMountedMission(
        tester,
        actionLabel: 'Replay Mission',
        progressStore: progressStore,
        firstMissionGuideStore: InMemoryFirstMissionGuideStore(),
      );

      expect(find.byType(FirstMissionGuideCallout), findsNothing);
      expect(find.text('Tap an empty cell to build here.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Replay Tutorial stays enabled without confirming when the guide '
      'store write fails', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testGamePage(firstMissionGuideStore: _FailingFirstMissionGuideStore()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay Tutorial'));
    await tester.pumpAndSettle();

    expect(
      find.text('Tutorial will replay on your next Outpost Alpha run.'),
      findsNothing,
    );
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Replay Tutorial'),
    );
    expect(tile.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a campaign load failure still builds the guide store so Skip persists',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);
      await _warmGameImages(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
      OrionDefenseGame? game;
      // No firstMissionGuideStore and a failing campaign store: the page's
      // catch branch must build the default SharedPreferences-backed guide
      // store itself, or Skip/Got it persist nothing.
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: orionThemeData,
          home: OrionGamePage(
            startOnWorldMap: true,
            progressStore: _TestCampaignProgressStore(
              loadError: StateError('campaign load failed'),
              failLoadCount: 1,
            ),
            onGameCreated: (value) => game = value,
            gameFeedback: const NoOpGameFeedback(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);
      // The mounted game loop never settles under fake async: fixed pumps.
      await tester.pump();
      await tester.pump();
      expect(game!.isMounted, isTrue);
      expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

      await tester.tap(find.text('Skip tutorial'));
      await tester.pump();
      await tester.pump();

      // The guide store was acquired in the catch branch, so the skip
      // actually persisted to SharedPreferences.
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool(SharedPreferencesFirstMissionGuideStore.key),
        isTrue,
        reason: 'Skip must persist even when campaign loading failed',
      );
    },
  );

  testWidgets('the default guide store persists Skip through the success-path '
      'SharedPreferences instance', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadRealFonts);
    await _warmGameImages(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
    OrionDefenseGame? game;
    // No stores injected anywhere: the page must reuse the
    // SharedPreferences instance acquired for the default campaign
    // store to back the default guide store on the successful load
    // path too — not only in the failure branch covered above.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: orionThemeData,
        home: OrionGamePage(
          startOnWorldMap: true,
          onGameCreated: (value) => game = value,
          gameFeedback: const NoOpGameFeedback(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);
    // The mounted game loop never settles under fake async: fixed pumps.
    await tester.pump();
    await tester.pump();
    expect(game!.isMounted, isTrue);
    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);

    await tester.tap(find.text('Skip tutorial'));
    await tester.pump();
    await tester.pump();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(SharedPreferencesFirstMissionGuideStore.key),
      isTrue,
      reason:
          'Skip must persist through the default guide store when '
          'campaign loading succeeded',
    );
  });

  testWidgets(
    'Reset Campaign leaves a completed first-mission guide completed',
    (tester) async {
      final guideStore = InMemoryFirstMissionGuideStore(completed: true);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testGamePage(firstMissionGuideStore: guideStore));
      await tester.pumpAndSettle();

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(guideStore.completed, isTrue);
    },
  );

  testWidgets(
    'an Alpha-result-inferred completion persists through Reset Campaign '
    'and relaunch',
    (tester) async {
      // A veteran who cleared Alpha before the flag existed has no record;
      // the load-time inference must be frozen into the guide store, or
      // wiping the campaign — which removes the result the inference
      // reads — re-arms the tutorial on the next launch.
      final progressStore = await storeWithResults({
        OrionCampaign.stageOneId: const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: 14,
        ),
      });
      final guideStore = InMemoryFirstMissionGuideStore();
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // The committed Alpha result renders a medal sprite on the world map.
      await tester.runAsync(loadRealFonts);
      await _warmGameImages(tester);
      await tester.pumpWidget(
        testGamePage(
          progressStore: progressStore,
          firstMissionGuideStore: guideStore,
        ),
      );
      await tester.pumpAndSettle();

      // The Alpha-result inference is frozen into the guide store at load.
      expect(guideStore.completed, isTrue);

      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();
      expect(guideStore.completed, isTrue);

      // Relaunch into Alpha: the reset campaign has no result left to
      // infer from, so only the persisted record suppresses the tutorial.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await pumpMountedMission(
        tester,
        progressStore: progressStore,
        firstMissionGuideStore: guideStore,
      );
      expect(find.byType(FirstMissionGuideCallout), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Replay Tutorial re-arms the guide for the next Alpha run', (
    tester,
  ) async {
    final guideStore = InMemoryFirstMissionGuideStore(completed: true);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testGamePage(firstMissionGuideStore: guideStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay Tutorial'));
    await tester.pumpAndSettle();
    expect(guideStore.completed, isFalse);
    expect(
      find.text('Tutorial will replay on your next Outpost Alpha run.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The next Alpha run opens with the build-cell callout again.
    await pumpMountedMission(tester, firstMissionGuideStore: guideStore);
    expect(find.text('Tap an empty cell to build here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an active wave renders live progress, hostiles and clear bonus from '
    'real wave state',
    (tester) async {
      final game = await pumpMountedMission(tester);
      final wave = OrionCampaign.stageOne.waves.first;
      final hostiles = find.byKey(const ValueKey('mission-hostiles-remaining'));

      game.startWave();
      await tester.pump();
      await tester.pump();

      expect(game.snapshot.phase, GamePhase.wave);
      expect(
        find.byKey(const ValueKey('mission-wave-progress')),
        findsOneWidget,
        reason: 'the running wave must show its progress readout',
      );
      expect(hostiles, findsOneWidget);
      expect(find.byKey(const ValueKey('mission-clear-bonus')), findsOneWidget);
      expect(
        find.descendant(
          of: hostiles,
          matching: find.textContaining('${wave.enemyCount}'),
        ),
        findsOneWidget,
        reason:
            'at wave start every hostile is unresolved; the readout must '
            'show the real ${wave.enemyCount}, not an invented count',
      );

      var pumps = 0;
      while (game.snapshot.baseHealth >= game.snapshot.startingBaseHealth &&
          pumps < 400) {
        await tester.pump(const Duration(milliseconds: 250));
        pumps += 1;
      }
      expect(
        game.snapshot.baseHealth,
        lessThan(game.snapshot.startingBaseHealth),
        reason:
            'untowered, every drone leaks for one base damage; the pump '
            'loop timed out before any hostile resolved',
      );
      final resolved =
          game.snapshot.startingBaseHealth - game.snapshot.baseHealth;
      final remaining = wave.enemyCount - resolved;
      expect(
        find.descendant(
          of: hostiles,
          matching: find.textContaining('$remaining'),
        ),
        findsOneWidget,
        reason:
            'with $resolved hostile(s) resolved the readout must show '
            '$remaining remaining — the live count, not the wave total',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mission-clear-bonus')),
          matching: find.textContaining('${wave.clearBonus}'),
        ),
        findsOneWidget,
        reason:
            'Outpost Alpha wave 1 still clears for ${wave.clearBonus} '
            'mid-wave; the readout must keep showing that reward',
      );
    },
  );

  for (final viewSize in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('capture active-wave evidence fixture $viewSize', (
      tester,
    ) async {
      final boundaryKey = GlobalKey();
      OrionDefenseGame? game;
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);
      await _warmGameImages(tester);
      OrionArtDescriptor.resetSpriteCache();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: testGamePage(onGameCreated: (value) => game = value),
        ),
      );
      await tester.pumpAndSettle();
      await startStageFromBriefing(tester);
      await tester.pump();
      await tester.pump();
      expect(game!.isMounted, isTrue);

      game!.startWave();
      await tester.pump();
      await tester.pump();
      expect(game!.snapshot.phase, GamePhase.wave);
      expect(
        game!.snapshot.waveHostilesTotal,
        OrionCampaign.stageOne.waves.first.enemyCount,
      );
      for (var i = 0; i < 12; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mission-status-base')),
          matching: find.byType(InternalSpriteWidget),
        ),
        findsOneWidget,
        reason: 'The hull emblem must load before the wave capture.',
      );

      final suffix = viewSize.height < 700 ? '-compact' : '';
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'fixture-live-wave$suffix.png',
        ),
      );
      final hudRect = tester.getRect(
        find.byKey(const ValueKey('mission-status-hud')),
      );
      final dockRect = tester.getRect(find.byType(MissionCommandDock));
      final gameRect = tester.getRect(find.bySubtype<GameWidget>());
      for (var column = 0; column < BoardLayout.columns; column++) {
        final topCell =
            gameRect.topLeft + game!.boardCellCenter(GridPosition(column, 0));
        final bottomCell =
            gameRect.topLeft +
            game!.boardCellCenter(GridPosition(column, BoardLayout.rows - 1));
        expect(topCell.dy, greaterThan(hudRect.bottom));
        expect(bottomCell.dy, lessThan(dockRect.top));
      }
    });
  }

  for (final viewSize in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('capture fighting-boss evidence fixture $viewSize', (
      tester,
    ) async {
      final boundaryKey = GlobalKey();
      Rect? reportedViewport;
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);
      await _warmGameImages(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });

      final game = OrionDefenseGame(
        stage: StageDefinition(
          id: 'boss-fight-fixture',
          name: 'Boss Fight Fixture',
          mapLabel: 'Boss',
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
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: orionThemeData,
            home: Scaffold(
              body: SafeArea(
                child: ValueListenableBuilder<GameSnapshot>(
                  valueListenable: game.stateNotifier,
                  builder: (context, snapshot, _) => Stack(
                    children: [
                      Positioned.fill(child: GameWidget(game: game)),
                      Positioned.fill(
                        child: MissionChrome(
                          snapshot: snapshot,
                          onBoardTapIntercept: (_) => false,
                          onWorldMap: game.returnToMap,
                          onStartWave: game.startWave,
                          onTogglePause: game.togglePause,
                          onSpeedSelected: game.setSpeedMultiplier,
                          onToggleAutoStart: game.toggleAutoStart,
                          onPlaceTower: game.placeTower,
                          onUpgrade: game.upgradeSelectedTower,
                          onTargetingChanged: game.setTargetingMode,
                          onSell: game.sellSelectedTower,
                          onBoardViewportChanged: (viewport) {
                            if (!viewport.isEmpty) {
                              reportedViewport = viewport;
                              game.setBoardViewport(viewport);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(game.isMounted, isTrue);

      game.startWave();
      await tester.pump();
      expect(game.snapshot.phase, GamePhase.wave);

      await advanceUntil(
        tester,
        game,
        (snapshot) => game.children
            .whereType<EnemyComponent>()
            .where((enemy) => enemy.minionOf != null && !enemy.isResolved)
            .isNotEmpty,
      );
      final enemies = game.children.whereType<EnemyComponent>().toList();
      final boss = enemies.singleWhere(
        (enemy) => enemy.stats is BossDefinition,
      );
      expect(boss.isAlive, isTrue, reason: 'the boss must be fighting');
      expect(
        boss.overlayState.shouldRender,
        isTrue,
        reason: 'a live boss paints its overlay chrome',
      );
      expect(
        boss.overlayState.showShieldBar && boss.overlayState.shieldRatio > 0,
        isTrue,
        reason:
            'Relay Breaker enters shielded: the fixture must show its '
            'live shield bar, not a generic health bar alone',
      );
      expect(boss.overlayState.showHealthBar, isTrue);
      expect(
        boss.stats.traits,
        containsAll(<EnemyTrait>{
          EnemyTrait.armored,
          EnemyTrait.shielded,
          EnemyTrait.heavy,
        }),
        reason: 'the real trait set feeds the overlay badges and rings',
      );
      expect(
        enemies
            .where((enemy) => enemy.minionOf != null && !enemy.isResolved)
            .length,
        greaterThan(0),
        reason: 'real summoned minions share the lane in the fixture',
      );

      final gameSize = game.size;
      final simCellSize = math.min(
        gameSize.x / BoardLayout.columns,
        gameSize.y / BoardLayout.rows,
      );
      final simBoardWidth = BoardLayout.columns * simCellSize;
      final simBoardHeight = BoardLayout.rows * simCellSize;
      final simBoardOrigin = Offset(
        (gameSize.x - simBoardWidth) / 2,
        math.max(0, (gameSize.y - simBoardHeight - 176) / 2),
      );
      final viewport = reportedViewport;
      expect(
        viewport,
        isNotNull,
        reason:
            'chrome must report its board viewport before geometry '
            'assertions can map simulation points to the screen',
      );
      final boardScale = math.min(
        1.0,
        math.min(
          viewport!.width / simBoardWidth,
          viewport.height / simBoardHeight,
        ),
      );
      final boardTranslation =
          viewport.center -
          (simBoardOrigin + Offset(simBoardWidth / 2, simBoardHeight / 2)) *
              boardScale;
      Offset simToCanvas(Offset sim) => sim * boardScale + boardTranslation;

      GridPosition? bossSimCell() => BoardLayout.cellAt(
        boss.position.toOffset(),
        cellSize: simCellSize,
        boardOrigin: simBoardOrigin,
      );

      await advanceUntil(
        tester,
        game,
        (snapshot) => (bossSimCell()?.row ?? 0) >= 3,
      );

      boss.applySlow(multiplier: 0.6, duration: 60);
      boss.applyCorrosion(damagePerSecond: 1, duration: 60, armorShred: 0.1);
      await tester.pump();
      final overlayState = boss.overlayState;
      expect(overlayState.isSlowed, isTrue, reason: 'applySlow is live');
      expect(overlayState.isCorroded, isTrue, reason: 'applyCorrosion is live');
      final overlayLayout = EnemyOverlayLayout.compute(
        overlayState,
        boss.radius,
      );
      expect(
        overlayLayout.slowedRingRadius,
        greaterThan(boss.radius),
        reason:
            'the slow ring must exceed the boss body to draw around it; '
            'a zero radius means applySlow never reached the overlay',
      );
      expect(
        overlayLayout.corrodedRingRadius,
        greaterThan(boss.radius),
        reason: 'the corrosion ring must exceed the boss body to draw',
      );
      expect(
        overlayLayout.slowedRingRadius,
        greaterThan(overlayLayout.corrodedRingRadius),
        reason: 'both rings must stay visible when they coexist',
      );
      expect(
        overlayLayout.originY,
        lessThan(0),
        reason: 'bars and badges hang above the boss, not on it',
      );

      final hudRect = tester.getRect(
        find.byKey(const ValueKey('mission-status-hud')),
      );
      final dockRect = tester.getRect(find.byType(MissionCommandDock));
      final gameRect = tester.getRect(find.bySubtype<GameWidget>());
      for (var column = 0; column < BoardLayout.columns; column++) {
        final topCell =
            gameRect.topLeft + game.boardCellCenter(GridPosition(column, 0));
        final bottomCell =
            gameRect.topLeft +
            game.boardCellCenter(GridPosition(column, BoardLayout.rows - 1));
        expect(topCell.dy, greaterThan(hudRect.bottom));
        expect(bottomCell.dy, lessThan(dockRect.top));
      }
      final bossCell = bossSimCell();
      expect(
        bossCell,
        isNotNull,
        reason: 'the live boss must be walking the lane',
      );
      final bossCanvas = simToCanvas(boss.position.toOffset());
      final bossScreen = gameRect.topLeft + bossCanvas;
      expect(
        bossScreen.dy > hudRect.bottom && bossScreen.dy < dockRect.top,
        isTrue,
        reason:
            'the fighting boss renders inside the board band, clear of '
            'the chrome the PNG photographs it under',
      );
      final radius = boss.radius;
      final name = (boss.stats as BossDefinition).name;
      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final badgeWidth =
          overlayState.badges.length * overlayLayout.badgeSize +
          (overlayState.badges.length - 1) * overlayLayout.badgeGap;
      final localBounds = <String, Rect>{
        'name': Rect.fromLTWH(
          radius - namePainter.width / 2,
          radius + overlayLayout.originY - namePainter.height - 2,
          namePainter.width,
          namePainter.height,
        ).inflate(2),
        'badges': Rect.fromLTWH(
          radius - badgeWidth / 2,
          radius + overlayLayout.badgesY!,
          badgeWidth,
          overlayLayout.badgeSize,
        ).inflate(0.5),
        'health bar': Rect.fromLTWH(
          radius - overlayLayout.healthBarWidth / 2,
          radius + overlayLayout.healthBarY!,
          overlayLayout.healthBarWidth,
          overlayLayout.healthBarHeight,
        ),
        'shield bar': Rect.fromLTWH(
          radius - overlayLayout.shieldBarWidth / 2,
          radius + overlayLayout.shieldBarY!,
          overlayLayout.shieldBarWidth,
          overlayLayout.shieldBarHeight,
        ),
        'slow ring': Rect.fromCircle(
          center: Offset(radius, radius),
          radius: overlayLayout.slowedRingRadius + 0.75,
        ),
        'corrosion ring': Rect.fromCircle(
          center: Offset(radius, radius),
          radius: overlayLayout.corrodedRingRadius + 0.75,
        ),
      };
      namePainter.dispose();

      Rect screenBounds(Rect rect) {
        final corners =
            [
              rect.topLeft,
              rect.topRight,
              rect.bottomLeft,
              rect.bottomRight,
            ].map((local) {
              final sim = boss.absolutePositionOf(Vector2(local.dx, local.dy));
              return gameRect.topLeft + simToCanvas(sim.toOffset());
            }).toList();
        return Rect.fromLTRB(
          corners.map((p) => p.dx).reduce(math.min),
          corners.map((p) => p.dy).reduce(math.min),
          corners.map((p) => p.dx).reduce(math.max),
          corners.map((p) => p.dy).reduce(math.max),
        );
      }

      final viewportScreen = viewport.shift(gameRect.topLeft);
      void expectClearance(String part, Rect rect) {
        final screen = screenBounds(rect);
        expect(screen.left, greaterThanOrEqualTo(gameRect.left), reason: part);
        expect(screen.right, lessThanOrEqualTo(gameRect.right), reason: part);
        expect(screen.top, greaterThanOrEqualTo(gameRect.top), reason: part);
        expect(screen.bottom, lessThanOrEqualTo(gameRect.bottom), reason: part);
        expect(
          screen.left,
          greaterThanOrEqualTo(viewportScreen.left),
          reason: part,
        );
        expect(
          screen.right,
          lessThanOrEqualTo(viewportScreen.right),
          reason: part,
        );
        expect(
          screen.top,
          greaterThanOrEqualTo(viewportScreen.top),
          reason: part,
        );
        expect(
          screen.bottom,
          lessThanOrEqualTo(viewportScreen.bottom),
          reason: part,
        );
        expect(screen.top, greaterThan(hudRect.bottom), reason: part);
        expect(screen.bottom, lessThan(dockRect.top), reason: part);
      }

      for (final entry in localBounds.entries) {
        expectClearance(entry.key, entry.value);
      }
      final localUnion = localBounds.values.reduce(
        (a, b) => a.expandToInclude(b),
      );
      expectClearance('complete overlay union', localUnion);

      const rasterSize = 256;
      const padding = 128.0;
      final pixels = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..translate(padding, padding);
        EnemyOverlayRenderer().render(
          canvas,
          state: overlayState,
          radius: radius,
          towerVarietySheet: boss.towerVarietySheet,
          name: name,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(rasterSize, rasterSize);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        picture.dispose();
        return bytes;
      });
      expect(pixels, isNotNull);
      var left = rasterSize;
      var top = rasterSize;
      var right = -1;
      var bottom = -1;
      final paintedByPart = <String, int>{
        'name': 0,
        'badges': 0,
        'health bar': 0,
        'shield bar': 0,
      };
      for (var y = 0; y < rasterSize; y++) {
        for (var x = 0; x < rasterSize; x++) {
          if (pixels!.getUint8((y * rasterSize + x) * 4 + 3) == 0) continue;
          left = math.min(left, x);
          top = math.min(top, y);
          right = math.max(right, x);
          bottom = math.max(bottom, y);
          final point = Offset(x + 0.5 - padding, y + 0.5 - padding);
          for (final part in paintedByPart.keys) {
            if (localBounds[part]!.contains(point)) {
              paintedByPart[part] = paintedByPart[part]! + 1;
            }
          }
        }
      }
      for (final entry in paintedByPart.entries) {
        expect(entry.value, greaterThan(0), reason: '${entry.key} must paint');
      }
      bool ringPainted(
        double ringRadius,
        bool Function(int, int) colorMatches,
      ) {
        final x = (padding + radius + ringRadius).round();
        final y = (padding + radius).round();
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final index = ((y + dy) * rasterSize + x + dx) * 4;
            if (pixels!.getUint8(index + 3) > 0 &&
                colorMatches(
                  pixels.getUint8(index + 1),
                  pixels.getUint8(index + 2),
                )) {
              return true;
            }
          }
        }
        return false;
      }

      expect(
        ringPainted(overlayLayout.slowedRingRadius, (g, b) => b > g),
        isTrue,
        reason: 'slow ring must paint at its own radius',
      );
      expect(
        ringPainted(overlayLayout.corrodedRingRadius, (g, b) => g > b + 30),
        isTrue,
        reason: 'corrosion ring must paint at its own radius',
      );
      expect(left, greaterThan(0));
      expect(top, greaterThan(0));
      expect(right, lessThan(rasterSize - 1));
      expect(bottom, lessThan(rasterSize - 1));
      final paintedBounds = Rect.fromLTRB(
        left - padding,
        top - padding,
        right + 1 - padding,
        bottom + 1 - padding,
      );
      final antialiasedUnion = localUnion.inflate(1.5);
      expect(paintedBounds.left, greaterThanOrEqualTo(antialiasedUnion.left));
      expect(paintedBounds.top, greaterThanOrEqualTo(antialiasedUnion.top));
      expect(paintedBounds.right, lessThanOrEqualTo(antialiasedUnion.right));
      expect(paintedBounds.bottom, lessThanOrEqualTo(antialiasedUnion.bottom));
      expectClearance('rasterized overlay', paintedBounds);

      final suffix = viewSize.height < 700 ? '-compact' : '';
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'fixture-boss-fight$suffix.png',
        ),
      );
    });
  }

  group('squad launch persistence (HPA-922 task 6)', () {
    Future<void> openBriefing(
      WidgetTester tester, {
      String mapLabel = 'Alpha',
    }) async {
      await tester.ensureVisible(find.text(mapLabel));
      await tester.tap(find.text(mapLabel));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
    }

    /// Toggles [member] inside the briefing's local draft via the picker's
    /// row — exactly what the draft-edit affordance renders as a tap.
    Future<void> pickSquadMember(WidgetTester tester, Character member) async {
      final pick = find.byKey(ValueKey('briefing-squad-pick-${member.name}'));
      // EDIT toggles — only open the picker when it isn't already showing.
      if (!tester.any(pick)) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('briefing-squad-edit')),
        );
        await tester.tap(find.byKey(const ValueKey('briefing-squad-edit')));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
    }

    /// Taps a launch action, then fixed-pumps: a mounted game keeps a live
    /// ticker so pumpAndSettle can never be used after launch. The pumps
    /// settle the queued squad save, the one route pop and the single
    /// _startStage continuation.
    Future<void> launchFromBriefing(
      WidgetTester tester, {
      String actionLabel = 'Start Mission',
    }) async {
      await tester.tap(find.byTooltip(actionLabel));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    testWidgets(
      'mission launch writes the drafted squad once and the game reads '
      'committed state',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 2,
            Character.sayo: 3,
          },
          squad: const [Character.haruto, Character.mio],
        );
        OrionDefenseGame? game;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (created) => game = created,
          ),
        );
        await tester.pumpAndSettle();

        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester);

        // Exactly one write: the whole atomic CampaignSave carries the draft.
        expect(store.saveCalls, 1);
        expect(store.squad, [Character.haruto, Character.mio, Character.sayo]);
        expect(store.ownedLevels, const {
          Character.haruto: 1,
          Character.mio: 2,
          Character.sayo: 3,
        });
        // The squad-only write must not touch committed progress.
        expect(store.progress.bestResultsByStageId, isEmpty);

        // The launched game reads the committed result, in draft order.
        expect(game, isNotNull);
        expect(game!.snapshot.squadLevels.keys.toList(), [
          Character.haruto,
          Character.mio,
          Character.sayo,
        ]);
        expect(game!.snapshot.squadLevels[Character.sayo], 3);
      },
    );

    testWidgets('cancel writes nothing and keeps the committed squad', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(
        ownedLevels: const {
          Character.haruto: 1,
          Character.mio: 1,
          Character.sayo: 3,
        },
        squad: const [Character.haruto, Character.mio],
      );
      await tester.pumpWidget(testGamePage(progressStore: store));
      await tester.pumpAndSettle();

      await openBriefing(tester);
      await pickSquadMember(tester, Character.sayo);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(store.saveCalls, 0);
      expect(store.squad, [Character.haruto, Character.mio]);
    });

    testWidgets('unchanged squad launch skips saving', (tester) async {
      final store = _TestCampaignProgressStore();
      OrionDefenseGame? game;
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) => game = created,
        ),
      );
      await tester.pumpAndSettle();

      await openBriefing(tester);
      await launchFromBriefing(tester);

      expect(store.saveCalls, 0);
      expect(game, isNotNull);
    });

    for (final (actionLabel, mode) in [
      ('Replay Mission', RunMode.mission),
      ('Endless', RunMode.endless),
    ]) {
      testWidgets('$actionLabel launch saves exactly once when squad changes', (
        tester,
      ) async {
        final store = _TestCampaignProgressStore(
          progress: _progressWithResults({OrionCampaign.stageOneId}),
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 1,
            Character.sayo: 3,
          },
          squad: CampaignSave.starterSquad,
        );
        OrionDefenseGame? game;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (created) => game = created,
          ),
        );
        await tester.pumpAndSettle();

        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester, actionLabel: actionLabel);

        expect(store.saveCalls, 1);
        expect(game, isNotNull);
        expect(game!.mode, mode);
        expect(game!.snapshot.squadLevels.keys.toList(), [
          ...CampaignSave.starterSquad,
          Character.sayo,
        ]);
      });
    }

    testWidgets(
      'an empty committed squad blocks launch until a member is picked',
      (tester) async {
        // A v4 profile can load with a fully-filtered empty squad; the
        // briefing must never launch it.
        final store = _TestCampaignProgressStore(squad: const []);
        OrionDefenseGame? game;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (created) => game = created,
          ),
        );
        await tester.pumpAndSettle();

        await openBriefing(tester);
        expect(
          find.text('Select at least one squad member to deploy.'),
          findsOneWidget,
        );
        await launchFromBriefing(tester);
        expect(store.saveCalls, 0);
        expect(game, isNull);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);

        await pickSquadMember(tester, Character.mio);
        await launchFromBriefing(tester);
        expect(store.saveCalls, 1);
        expect(store.squad, [Character.mio]);
        expect(game, isNotNull);
      },
    );

    testWidgets(
      'a pending launch save keeps the sheet mounted and blocks re-entry',
      (tester) async {
        final store = _TestCampaignProgressStore(delaySaves: true);
        var created = 0;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (game) => created += 1,
          ),
        );
        await tester.pumpAndSettle();

        await openBriefing(tester);
        await pickSquadMember(tester, Character.mio);
        await tester.tap(find.byTooltip('Start Mission'));
        await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
        // The save completer can be created during the tap's microtask drain,
        // before any frame rebuilds the dirty sheet.
        await tester.pump();

        // Mid-flight: the route is still up, the launch action is inert, and
        // a second tap must not enqueue another write.
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(find.text('Saving squad…'), findsOneWidget);
        await tester.tap(find.byTooltip('Start Mission'));
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pump();
        expect(store.saveCompletions, hasLength(1));
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);

        // Real dismissal paths — system back, the barrier's maybePop (its
        // literal onDismiss body) and a downward sheet drag — are all vetoed
        // while the save is in flight.
        await tester.binding.handlePopRoute();
        await tester.pump();
        final sheetContext = tester.element(
          find.byKey(const ValueKey('stage-briefing')),
        );
        await Navigator.maybePop(sheetContext);
        await tester.pump();
        await tester.fling(
          find.byTooltip('Dismiss'),
          const Offset(0, 300),
          1200,
        );
        await tester.pumpAndSettle();
        expect(store.saveCompletions, hasLength(1));
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(find.text('Saving squad…'), findsOneWidget);

        store.saveCompletions.single.complete();
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(created, 1);
        expect(store.squad, [Character.haruto]);
      },
    );

    testWidgets(
      'a failed launch save reports inside the still-open sheet and retry '
      'saves once then launches once',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 1,
            Character.sayo: 4,
          },
          squad: const [Character.haruto, Character.mio],
          failOnSaveIndices: {0},
        );
        var created = 0;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (game) => created += 1,
          ),
        );
        await tester.pumpAndSettle();

        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester);

        // Failed write: no navigation, no commit, draft preserved, retryable
        // feedback inside the modal.
        expect(store.saveCalls, 1);
        expect(created, 0);
        expect(store.squad, [Character.haruto, Character.mio]);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );

        await launchFromBriefing(tester);
        expect(store.saveCalls, 2);
        expect(created, 1);
        expect(store.squad, [Character.haruto, Character.mio, Character.sayo]);
        expect(store.ownedLevels[Character.sayo], 4);
      },
    );

    testWidgets(
      'a reloaded page seeds the briefing with the committed squad order',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 2,
            Character.sayo: 3,
          },
          squad: const [Character.haruto, Character.mio],
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();

        // Reorder to [mio, sayo, haruto] — drop/re-add pushes re-added
        // members to the end — then launch: one write.
        await openBriefing(tester);
        await pickSquadMember(tester, Character.haruto);
        await pickSquadMember(tester, Character.haruto);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester);
        expect(store.squad, [Character.mio, Character.haruto, Character.sayo]);

        // "Remount": a fresh page over the same store must reload the saved
        // order — and non-default levels ride along untouched. An empty
        // tree between mounts forces a new element tree: pumpWidget reuses
        // the root element when the root widget type is unchanged.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();
        await openBriefing(tester);
        final positions = <double>[];
        for (final member in const [
          Character.mio,
          Character.haruto,
          Character.sayo,
        ]) {
          final token = find.byKey(
            ValueKey('briefing-squad-token-${member.name}'),
          );
          await tester.ensureVisible(token);
          positions.add(tester.getRect(token).left);
        }
        expect(positions[0], lessThan(positions[1]));
        expect(positions[1], lessThan(positions[2]));

        // The remounted briefing carries the non-default persistent levels,
        // not starter 1s.
        for (final (member, level) in const [
          (Character.mio, 2),
          (Character.haruto, 1),
          (Character.sayo, 3),
        ]) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey('briefing-squad-token-${member.name}')),
              matching: find.text('Lv $level'),
            ),
            findsOneWidget,
            reason: member.name,
          );
        }
      },
    );

    testWidgets('reset restores the starter roster after a saved launch', (
      tester,
    ) async {
      final store = _TestCampaignProgressStore(
        ownedLevels: const {
          Character.haruto: 1,
          Character.mio: 2,
          Character.sayo: 4,
        },
        squad: const [Character.sayo],
      );
      OrionDefenseGame? game;
      var gameIndex = 0;
      await tester.pumpWidget(
        testGamePage(
          progressStore: store,
          onGameCreated: (created) {
            game = created;
            gameIndex += 1;
          },
        ),
      );
      await tester.pumpAndSettle();

      // A real saved launch first: the drafted subset order and non-default
      // levels reach both the store and the mounted game.
      await openBriefing(tester);
      await pickSquadMember(tester, Character.mio);
      await launchFromBriefing(tester);
      expect(store.saveCalls, 1);
      expect(store.squad, [Character.sayo, Character.mio]);
      expect(game, isNotNull);
      expect(gameIndex, 1);
      expect(game!.snapshot.squadLevels.keys.toList(), [
        Character.sayo,
        Character.mio,
      ]);
      expect(game!.snapshot.squadLevels.values.toList(), [4, 2]);

      // Back to the map, then reset — the page and store revert together.
      game!.returnToMap();
      await tester.pumpAndSettle();
      await openResetCampaignDialog(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(store.resetCalls, 1);
      expect(store.ownedLevels, CampaignSave.starterOwnedLevels);
      expect(store.squad, CampaignSave.starterSquad);

      // The live page already reflects the starters: its next briefing seeds
      // the starter draft in starter order — the sayo token is gone.
      await openBriefing(tester);
      expect(
        find.byKey(const ValueKey('briefing-squad-token-haruto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-squad-token-mio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-squad-token-sayo')),
        findsNothing,
      );

      // And the next launched game deploys the starter roster at level 1.
      await launchFromBriefing(tester);
      expect(gameIndex, 2);
      expect(game!.snapshot.squadLevels, {
        Character.haruto: 1,
        Character.mio: 1,
      });
    });

    testWidgets(
      'squad and victory writes compose on the committed aggregate and '
      'keep the wallet',
      (tester) async {
        const victory = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 2,
            Character.sayo: 3,
          },
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
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

        // Write A: the launch-time squad draft commits through the queue.
        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await tester.tap(find.byTooltip('Start Mission'));
        await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
        store.saveCompletions[0].complete();
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(game, isNotNull);
        expect(store.squad, [Character.haruto, Character.mio, Character.sayo]);

        // Write B: the victory result composes on write A's committed
        // payload — squad and wallet ride through; nothing is rebuilt to
        // zero (HPA-923 task 2).
        await publishVictory(tester, game!, result: victory);
        await _pumpUntil(tester, () => store.saveCompletions.length > 1);
        store.saveCompletions[1].complete();
        await tester.pumpAndSettle();

        expect(find.text('Saved.'), findsOneWidget);
        expect(store.progress.resultFor('outpost-alpha'), victory);
        expect(store.squad, [Character.haruto, Character.mio, Character.sayo]);
        expect(store.ownedLevels[Character.sayo], 3);
        // Task 3: the first-clear Gold award (1050) credits on top of the
        // wallet that write A carried through the queue.
        expect(store.scrip, 1550);

        // The composed aggregate is what a restarted page would reload.
        final reloaded = await store.load();
        expect(reloaded.scrip, 1550);
        expect(reloaded.squad, [
          Character.haruto,
          Character.mio,
          Character.sayo,
        ]);
        expect(reloaded.progress.resultFor('outpost-alpha'), victory);
      },
    );

    testWidgets(
      'a failed squad write leaves committed Scrip and roster out of every '
      'view',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 2,
            Character.sayo: 3,
          },
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
          failOnSaveIndices: {0},
        );
        await tester.pumpWidget(testGamePage(progressStore: store));
        await tester.pumpAndSettle();

        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester);

        // Failed write: nothing committed — wallet, roster and squad stay
        // put and the still-open sheet reports the retryable failure.
        expect(store.saveCalls, 1);
        expect(store.scrip, 500);
        expect(store.squad, [Character.haruto, Character.mio]);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );

        // Views read the committed aggregate only: Camp still shows sayo
        // owned at Lv 3 but never tags it SQUAD.
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Camp'));
        await tester.pumpAndSettle();

        final sayoCard = find.byKey(const ValueKey('camp-card-sayo'));
        expect(sayoCard, findsOneWidget);
        expect(
          find.descendant(of: sayoCard, matching: find.text('Lv 3')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sayoCard, matching: find.text('SQUAD')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('camp-card-mio')),
            matching: find.text('SQUAD'),
          ),
          findsOneWidget,
        );

        final reloaded = await store.load();
        expect(reloaded.scrip, 500);
        expect(reloaded.squad, [Character.haruto, Character.mio]);
      },
    );

    testWidgets(
      'a committed squad write updates Camp without a separate projection',
      (tester) async {
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 2,
            Character.sayo: 3,
          },
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
        );
        OrionDefenseGame? game;
        await tester.pumpWidget(
          testGamePage(
            progressStore: store,
            onGameCreated: (created) => game = created,
          ),
        );
        await tester.pumpAndSettle();

        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester);
        expect(game, isNotNull);
        // The squad-only write carries the wallet through untouched.
        expect(store.scrip, 500);

        // One aggregate assignment refreshes every view: back on the map,
        // Camp already tags the newly committed member — no projection
        // setter ran between the commit and this build.
        game!.returnToMap();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Camp'));
        await tester.pumpAndSettle();

        final sayoCard = find.byKey(const ValueKey('camp-card-sayo'));
        expect(
          find.descendant(of: sayoCard, matching: find.text('SQUAD')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sayoCard, matching: find.text('Lv 3')),
          findsOneWidget,
        );
      },
    );

    testWidgets('a failed victory write keeps the uncommitted win out of the '
        'following squad save and every view', (tester) async {
      const victory = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
      final store = _TestCampaignProgressStore(
        ownedLevels: const {
          Character.haruto: 1,
          Character.mio: 2,
          Character.sayo: 3,
        },
        squad: const [Character.haruto, Character.mio],
        scrip: 500,
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

      // Launch with the committed squad — no squad write — then win:
      // write index 0 is the victory save, and it fails.
      await startStageFromBriefing(tester);
      await publishVictory(tester, game!, result: victory);
      await tester.pumpAndSettle();
      expect(store.saveCalls, 1);
      expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
      expect(store.progress.resultFor('outpost-alpha'), isNull);
      expect(store.scrip, 500);

      // The failed write offered exit; committed progress still locks
      // Nebula Relay — the uncommitted win never advanced the aggregate.
      await tester.tap(find.byTooltip('World Map (Unsaved)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Relay'));
      await tester.tap(find.text('Relay'));
      await tester.pumpAndSettle();
      expect(find.text('Nebula Relay is locked.'), findsOneWidget);

      // The next write — the launch-time squad draft — must compose on
      // the committed aggregate: the squad delta lands WITHOUT the failed
      // victory resurrecting inside its payload.
      await openBriefing(tester);
      await pickSquadMember(tester, Character.sayo);
      await launchFromBriefing(tester);

      expect(store.saveCalls, 2);
      expect(store.squad, [Character.haruto, Character.mio, Character.sayo]);
      expect(store.progress.resultFor('outpost-alpha'), isNull);
      expect(store.ownedLevels, {
        Character.haruto: 1,
        Character.mio: 2,
        Character.sayo: 3,
      });
      expect(store.scrip, 500);
      // The relaunched run deploys the committed roster write 2 committed.
      expect(game!.snapshot.squadLevels, {
        Character.haruto: 1,
        Character.mio: 2,
        Character.sayo: 3,
      });

      // Reload sees exactly what the committed aggregate holds.
      final reloaded = await store.load();
      expect(reloaded.scrip, 500);
      expect(reloaded.squad, [Character.haruto, Character.mio, Character.sayo]);
      expect(reloaded.progress.resultFor('outpost-alpha'), isNull);
    });

    testWidgets(
      'a failed squad write after a committed victory keeps the win and '
      'wallet, and the retry composes on the committed aggregate',
      (tester) async {
        const victory = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
        final store = _TestCampaignProgressStore(
          ownedLevels: const {
            Character.haruto: 1,
            Character.mio: 2,
            Character.sayo: 3,
          },
          squad: const [Character.haruto, Character.mio],
          scrip: 500,
          failOnSaveIndices: {1},
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
        await publishVictory(tester, game!, result: victory);
        await tester.pumpAndSettle();

        // Write 1 committed: win, squad and wallet are all on disk — the
        // first-clear Gold award (1050) credited on top of the seeded 500.
        expect(find.text('Saved.'), findsOneWidget);
        expect(store.saveCalls, 1);
        expect(store.progress.resultFor('outpost-alpha'), victory);
        expect(store.scrip, 1550);

        await tester.tap(find.byTooltip('World Map').last);
        await tester.pumpAndSettle();

        // Write 2 — the squad draft — fails: nothing from it may advance.
        // The committed aggregate still carries write 1's win and wallet.
        // Alpha is cleared now, so the launch action reads Replay Mission.
        await openBriefing(tester);
        await pickSquadMember(tester, Character.sayo);
        await launchFromBriefing(tester, actionLabel: 'Replay Mission');

        expect(store.saveCalls, 2);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );
        expect(store.squad, [Character.haruto, Character.mio]);
        expect(store.progress.resultFor('outpost-alpha'), victory);
        expect(store.scrip, 1550);

        // The retry builds a fresh payload on the committed aggregate: the
        // draft squad lands with write 1's result still riding along.
        await launchFromBriefing(tester, actionLabel: 'Replay Mission');

        expect(store.saveCalls, 3);
        expect(store.squad, [Character.haruto, Character.mio, Character.sayo]);
        expect(store.progress.resultFor('outpost-alpha'), victory);
        expect(store.ownedLevels, {
          Character.haruto: 1,
          Character.mio: 2,
          Character.sayo: 3,
        });
        expect(store.scrip, 1550);
        expect(game!.snapshot.squadLevels, {
          Character.haruto: 1,
          Character.mio: 2,
          Character.sayo: 3,
        });

        // Reload sees exactly the last committed aggregate.
        final reloaded = await store.load();
        expect(reloaded.scrip, 1550);
        expect(reloaded.progress.resultFor('outpost-alpha'), victory);
        expect(reloaded.squad, [
          Character.haruto,
          Character.mio,
          Character.sayo,
        ]);
      },
    );
  });
}

/// Warms fonts and the game's sprite sheets into their process-global caches
/// so a mounted game's onLoad resolves instantly, pumps [testGamePage] at the
/// 360x640 guided-path viewport, starts the stage named by [mapLabel] from
/// its briefing, and returns the mounted game.
///
/// [squad] must name the members the mounted game's progress store will
/// launch with: onLoad preloads exactly those chibis, so the warm-up has to
/// cover them and nothing more.
Future<OrionDefenseGame> pumpMountedMission(
  WidgetTester tester, {
  String mapLabel = 'Alpha',
  String actionLabel = 'Start Mission',
  CampaignProgressStore? progressStore,
  FirstMissionGuideStore? firstMissionGuideStore,
  ModuleOfferPicker? moduleOfferPicker,
  Iterable<Character> squad = CampaignSave.starterSquad,
  Size viewSize = const Size(360, 640),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadRealFonts);
  await _warmGameImages(tester, squad: squad);
  // Tear the mounted game down so its live ticker never outlives the test.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
  OrionDefenseGame? game;
  await tester.pumpWidget(
    testGamePage(
      progressStore: progressStore,
      firstMissionGuideStore: firstMissionGuideStore,
      moduleOfferPicker: moduleOfferPicker,
      onGameCreated: (value) => game = value,
    ),
  );
  await tester.pumpAndSettle();
  await startStageFromBriefing(
    tester,
    mapLabel: mapLabel,
    actionLabel: actionLabel,
  );
  // The mounted game loop never settles under fake async: fixed pumps only.
  await tester.pump();
  await tester.pump();
  final mounted = game;
  if (mounted == null) {
    fail('OrionDefenseGame was not created.');
  }
  expect(mounted.isMounted, isTrue);
  return mounted;
}

/// Sprite sheets the mounted game's onLoad resolves from Flame's global
/// image cache.
const _gameImageNames = [
  'reactor_rim_ui/boards/nebula.png',
  'orion_path_tiles.png',
  'orion_sprite_sheet.png',
  'orion_tower_variety_sheet.png',
  'orion_boss_sheet.png',
];

/// Names this helper has already decoded. The warm cache deliberately
/// outlives these tests: they are the last tests in this file, and each
/// test file runs in its own isolate, so no other test observes the cache
/// state. Re-decoding real engine images per test has proven to stall late
/// in a long suite when an earlier test's codec callback was dropped across
/// the fake-async boundary.
final Set<String> _warmedGameImages = {};

/// Warms the sheets plus the chibis for exactly [squad] — the same set
/// onLoad preloads for the mounted game.
///
/// A name only counts as warm when this helper warmed it AND it is still in
/// Flame's cache: `containsKey` alone also reports the dead pending entries
/// a cold-mount test leaves behind, and a clearCache teardown between tests
/// empties names this helper decoded earlier.
Future<void> _warmGameImages(
  WidgetTester tester, {
  Iterable<Character> squad = CampaignSave.starterSquad,
}) async {
  final names = {
    ..._gameImageNames,
    for (final member in squad) OrionArt.characterChibi(member).fileName,
  };
  // The descriptor memo can hold a pending future from an earlier cold-mount
  // test in this process; drop it so this fixture's warmed cache is the one
  // the mounted game's onLoad resolves against.
  OrionArtDescriptor.resetSpriteCache();
  if (names.every(
    (name) =>
        _warmedGameImages.contains(name) && Flame.images.containsKey(name),
  )) {
    return;
  }
  // Flame's Images.load caches the pending future itself (`_assets[name] ??=
  // _ImageAsset.future(...)`). Tests earlier in this file mount games with a
  // cold cache under fake async, so their onLoad loads never complete and
  // those dead pending entries stay in the global cache forever — any later
  // load of the same name would await the dead future and stall. Dropping
  // them first lets the real runAsync decodes below register fresh entries.
  Flame.images.clearCache();
  OrionArtDescriptor.resetSpriteCache();
  for (final name in names) {
    var loaded = false;
    for (var attempt = 0; attempt < 3 && !loaded; attempt++) {
      try {
        await tester.runAsync(
          () => Flame.images.load(name).timeout(const Duration(seconds: 10)),
        );
        loaded = true;
      } on TimeoutException {
        // A dropped codec callback never recovers; re-issue the request.
      }
    }
    if (!loaded) {
      fail('Timed out loading $name for the mounted-game fixture.');
    }
    _warmedGameImages.add(name);
  }
}

/// Advances the mounted game in fixed update slices — the direct
/// game.update/pump technique the game-level tests use — until [until] holds,
/// with a generous tick cap so a broken expectation fails instead of hanging.
Future<void> advanceUntil(
  WidgetTester tester,
  OrionDefenseGame game,
  bool Function(GameSnapshot snapshot) until,
) async {
  for (var tick = 0; tick < 400 && !until(game.snapshot); tick++) {
    game.update(0.25);
    await tester.pump();
  }
  expect(until(game.snapshot), isTrue);
}

/// Global point of a board cell under the current viewport.
Offset boardCellPoint(
  WidgetTester tester,
  OrionDefenseGame game,
  GridPosition cell,
) {
  final gameRect = tester.getRect(find.bySubtype<GameWidget>());
  return gameRect.topLeft + game.boardCellCenter(cell);
}

/// Taps a board cell through the real page, then pumps long enough for the
/// gesture layer's double-tap countdown timers to expire and the snapshot
/// round-trip to rebuild the UI.
Future<void> tapBoardCell(
  WidgetTester tester,
  OrionDefenseGame game,
  GridPosition cell,
) async {
  await tester.tapAt(boardCellPoint(tester, game, cell));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
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
    waveNumber: snapshot.missionWaveTotal ?? snapshot.waveNumber,
    missionWaveTotal: snapshot.missionWaveTotal,
    wavesCleared: snapshot.missionWaveTotal ?? snapshot.wavesCleared,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    squad: snapshot.squad,
    squadLevels: snapshot.squadLevels,
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
  await tester.ensureVisible(find.text('MISSION DETAILS'));
  await tester.tap(find.text('MISSION DETAILS'));
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
    missionWaveTotal: snapshot.missionWaveTotal,
    wavesCleared: snapshot.wavesCleared,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    squad: snapshot.squad,
    squadLevels: snapshot.squadLevels,
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

/// Endless counterpart to publishLoss for a finished wave: the game publishes
/// the build-phase snapshot carrying the new cleared count before it invokes
/// onEndlessWaveCleared, so the helper does the same.
Future<void> publishEndlessWaveClear(
  WidgetTester tester,
  OrionDefenseGame game,
  int wavesCleared,
) async {
  final snapshot = game.stateNotifier.value;
  game.stateNotifier.value = GameSnapshot(
    phase: GamePhase.build,
    gold: snapshot.gold,
    baseHealth: snapshot.baseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
    waveNumber: wavesCleared + 1,
    missionWaveTotal: null,
    wavesCleared: wavesCleared,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    squad: snapshot.squad,
    squadLevels: snapshot.squadLevels,
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
  game.onEndlessWaveCleared?.call(wavesCleared);
  await tester.pump();
}

/// The onPressed backing a mission-report action label, or null when the
/// action is disabled. Non-tonal actions are IconButtons; the tonal exit is a
/// TextButton inside OrionPrimaryButton — disabled actions keep their label, so
/// onPressed is the enabled-state authority. Throws if the action label is not
/// rendered on the report.
VoidCallback? reportActionOnPressed(WidgetTester tester, String label) {
  expect(find.text(label), findsOneWidget);
  final iconButton = find.ancestor(
    of: find.text(label),
    matching: find.byType(IconButton),
  );
  if (iconButton.evaluate().isNotEmpty) {
    return tester.widget<IconButton>(iconButton).onPressed;
  }
  final textButton = find.ancestor(
    of: find.text(label),
    matching: find.byType(TextButton),
  );
  if (textButton.evaluate().isNotEmpty) {
    return tester.widget<TextButton>(textButton).onPressed;
  }
  fail('Action $label has neither IconButton nor TextButton ancestor');
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

/// Committed Alpha clear with an optional saved endless best — the launch
/// gate and the briefing best line both read committed progress.
CampaignProgress _progressWithAlphaCleared({int? endlessBest}) {
  return CampaignProgress(
    bestResultsByStageId: const {
      'outpost-alpha': StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
    },
    endlessBestByStageId: {'outpost-alpha': ?endlessBest},
  );
}

class _TestCampaignProgressStore implements CampaignProgressStore {
  _TestCampaignProgressStore({
    this.loadError,
    this.failLoadCount,
    this.delaySaves = false,
    this.delayResets = false,
    this.failOnSaveIndices = const {},
    this.resetResults = const [],
    CampaignProgress? progress,
    Map<Character, int>? ownedLevels,
    List<Character>? squad,
    this.scrip = 0,
  }) : progress = progress ?? CampaignProgress(),
       ownedLevels = ownedLevels ?? CampaignSave.starterOwnedLevels,
       squad = squad ?? CampaignSave.starterSquad;

  final Object? loadError;
  final int? failLoadCount;
  final bool delaySaves;
  final bool delayResets;
  final Set<int> failOnSaveIndices;
  final List<Object?> resetResults;
  final List<Completer<void>> saveCompletions = [];
  final List<Completer<void>> resetCompletions = [];
  CampaignProgress progress;
  Map<Character, int> ownedLevels;
  List<Character> squad;
  int scrip;
  int loadCalls = 0;
  int saveCalls = 0;
  int resetCalls = 0;

  @override
  Future<CampaignSave> load() async {
    loadCalls += 1;
    final error = loadError;
    if (error != null &&
        (failLoadCount == null || loadCalls <= failLoadCount!)) {
      throw error;
    }
    return CampaignSave(
      progress: progress,
      ownedLevels: ownedLevels,
      squad: squad,
      scrip: scrip,
    );
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
    progress = save.progress;
    ownedLevels = save.ownedLevels;
    squad = save.squad;
    scrip = save.scrip;
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
    ownedLevels = CampaignSave.starterOwnedLevels;
    squad = CampaignSave.starterSquad;
    scrip = 0;
  }
}

/// A guide store whose first [loadCompleted] calls throw before delegating
/// to the wrapped store — a transient startup read failure that recovers
/// by the campaign Retry, so the retry must re-read the flag instead of
/// inferring completion from progress alone. [failLoadCount] models a
/// read that is still failing when the retry reaches it.
class _FlakyLoadFirstMissionGuideStore implements FirstMissionGuideStore {
  _FlakyLoadFirstMissionGuideStore(this._inner, {int failLoadCount = 1})
    : _failLoadsRemaining = failLoadCount;

  final InMemoryFirstMissionGuideStore _inner;
  int _failLoadsRemaining;

  bool? get completed => _inner.completed;

  @override
  Future<bool?> loadCompleted() async {
    if (_failLoadsRemaining > 0) {
      _failLoadsRemaining -= 1;
      throw StateError('guide read failed');
    }
    return _inner.loadCompleted();
  }

  @override
  Future<void> setCompleted(bool completed) => _inner.setCompleted(completed);

  @override
  Future<Set<ContextualTip>> loadSeenTips() => _inner.loadSeenTips();

  @override
  Future<void> setSeenTips(Set<ContextualTip> tips) => _inner.setSeenTips(tips);

  @override
  Future<void> resetForReplay() => _inner.resetForReplay();
}

/// A guide store whose writes always fail — Replay Tutorial must surface
/// that failure (no confirmation, action stays enabled).
class _FailingFirstMissionGuideStore implements FirstMissionGuideStore {
  bool? completed = true;

  @override
  Future<bool?> loadCompleted() async => completed;

  @override
  Future<void> setCompleted(bool completed) async {
    throw StateError('guide write failed');
  }

  @override
  Future<Set<ContextualTip>> loadSeenTips() async => {};

  @override
  Future<void> setSeenTips(Set<ContextualTip> tips) async {
    throw StateError('guide write failed');
  }

  @override
  Future<void> resetForReplay() async {
    throw StateError('guide write failed');
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

/// Deterministic `math.Random` for injected flare rolls: each `nextInt`
/// returns the next scripted value (which must fit the requested bound), so
/// a page test can aim FlareRules at exact rank buckets and same-rank picks.
/// Each draw consumes two values — the rank roll, then the pick.
class _ScriptedRandom implements math.Random {
  _ScriptedRandom(List<int> values) : _values = List.of(values);

  final List<int> _values;
  var _nextIndex = 0;

  @override
  int nextInt(int max) {
    if (_nextIndex >= _values.length) {
      throw StateError('ScriptedRandom ran out of values.');
    }
    final value = _values[_nextIndex++];
    if (value < 0 || value >= max) {
      throw ArgumentError('Scripted value $value outside [0, $max).');
    }
    return value;
  }

  @override
  double nextDouble() => throw UnimplementedError('nextDouble is unused');

  @override
  bool nextBool() => throw UnimplementedError('nextBool is unused');
}

/// Offers handed out in order by [_ScriptedModuleOfferPicker] so the
/// first-mission module draft is deterministic.
const _scriptedModuleOffers = [
  [RunModuleId.heavyCaliber, RunModuleId.overclockRelay, RunModuleId.longSight],
];

/// A [ModuleOfferPicker] that returns scripted offers in order.
class _ScriptedModuleOfferPicker implements ModuleOfferPicker {
  _ScriptedModuleOfferPicker(this.offers);

  final List<List<RunModuleId>> offers;
  int _index = 0;

  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    final offer = offers[_index++];
    if (offer.length != count) {
      throw StateError('Scripted offer length ${offer.length} != $count');
    }
    return List.unmodifiable(offer);
  }
}
