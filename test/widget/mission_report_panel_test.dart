import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import 'package:orion/game/ui/mission_report_panel.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import '../support/orion_finders.dart';
import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

void main() {
  testWidgets('saving victory shows save copy and disables both exits', (
    tester,
  ) async {
    // Catches a production panel that exposes replay/map before save truth is
    // resolved, which could discard an improving result. Callbacks are provided
    // so the test verifies the panel actively disables otherwise available
    // exits — not merely that no callback was supplied.
    var replayed = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.saving),
      onReplay: () => replayed = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Saving result…'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    final replayButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('Replay Mission'),
        matching: find.byType(IconButton),
      ),
    );
    final mapButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('World Map'),
        matching: find.byType(IconButton),
      ),
    );
    expect(replayButton.onPressed, isNull);
    expect(mapButton.onPressed, isNull);
    expect(replayed, isFalse);
    expect(returned, isFalse);
  });

  testWidgets('saved victory enables replay and world map actions', (
    tester,
  ) async {
    // Catches a production panel that leaves actions disabled after persistence
    // succeeds, preventing the player from continuing the campaign.
    var replayed = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.saved),
      onReplay: () => replayed = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Replay Mission'));
    await tester.tap(find.byTooltip('World Map'));
    expect(replayed, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('failed victory offers retry save and unsaved map only', (
    tester,
  ) async {
    // Catches a production panel that presents a failed write as replayable or
    // silently labels the map exit as if the result had been committed.
    var retried = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.failed),
      onRetrySave: () => retried = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
    expect(find.text('Retry Save'), findsOneWidget);
    expect(find.text('World Map (Unsaved)'), findsOneWidget);
    expect(find.text('Replay Mission'), findsNothing);

    await tester.tap(find.byTooltip('Retry Save'));
    await tester.tap(find.byTooltip('World Map (Unsaved)'));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('loss offers retry and world map actions', (tester) async {
    // Catches a production panel that omits a recovery path after a lost run.
    var retried = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _lossContent(),
      onReplay: () => retried = true,
      onReturnToMap: () => returned = true,
    );

    expect(find.text('Mission Failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry'));
    await tester.tap(find.byTooltip('World Map'));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('module IDs reuse acquired strip title and effect copy', (
    tester,
  ) async {
    // Catches a production panel that forks module rendering and drifts from
    // the existing in-run title/effect text.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        moduleIds: const [RunModuleId.heavyCaliber],
      ),
    );

    final definition = runModuleDefinition(RunModuleId.heavyCaliber);
    expect(find.textContaining(definition.title), findsOneWidget);
    expect(find.textContaining(definition.effectText), findsOneWidget);
  });

  testWidgets('empty module IDs show the projected empty-state copy', (
    tester,
  ) async {
    // Catches a production panel that invents a second empty-state string or
    // leaves the Salvage Modules section blank.
    await _pumpPanel(tester, _victoryContent(MissionSaveState.saved));

    expect(find.text('No Salvage Modules acquired'), findsOneWidget);
  });

  testWidgets('optional reward fact renders its title and detail', (
    tester,
  ) async {
    // Catches a production panel that drops the typed reward seam needed by
    // the follow-up reward slice.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        reward: const MissionRewardFact(
          title: 'Blueprint fragment',
          detail: 'Unlocks a new blueprint after saving.',
        ),
      ),
    );

    expect(find.text('Blueprint fragment'), findsOneWidget);
    expect(find.text('Unlocks a new blueprint after saving.'), findsOneWidget);
  });

  testWidgets(
    'null saveState victory fails closed with both actions disabled',
    (tester) async {
      // Catches a production panel that fails open for an unknown/null victory
      // save state, enabling Replay/World Map before persistence is resolved.
      // The production page only renders a victory report after
      // _missionSaveState != null, so null is not normally reachable. Still,
      // failing closed is the safe default: treat null like saving so a future
      // integration mistake cannot silently permit leaving with an uncommitted
      // result.
      var replayed = false;
      var returned = false;
      await _pumpPanel(
        tester,
        _victoryContentNullSaveState(),
        onReplay: () => replayed = true,
        onReturnToMap: () => returned = true,
      );

      expect(find.text('Replay Mission'), findsOneWidget);
      expect(find.text('World Map'), findsOneWidget);

      final replayButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byTooltip('Replay Mission'),
          matching: find.byType(IconButton),
        ),
      );
      final mapButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byTooltip('World Map'),
          matching: find.byType(IconButton),
        ),
      );
      expect(replayButton.onPressed, isNull);
      expect(mapButton.onPressed, isNull);
      expect(replayed, isFalse);
      expect(returned, isFalse);
    },
  );

  testWidgets('null saveState victory shows the info save-status icon', (
    tester,
  ) async {
    // Catches a production _SaveStateRow that drops the null-state icon case.
    await _pumpPanel(tester, _victoryContentNullSaveState());

    expect(find.bySemanticsLabel('Save status'), findsOneWidget);
  });

  testWidgets('three module IDs fit the 360 by 640 surface without overflow', (
    tester,
  ) async {
    // Catches a production layout that lets the report body push fixed actions
    // off-screen or overflow instead of scrolling its content.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        moduleIds: const [
          RunModuleId.heavyCaliber,
          RunModuleId.overclockRelay,
          RunModuleId.longSight,
        ],
      ),
    );

    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    // Verify the action buttons are physically reachable within the viewport,
    // not merely present in the widget tree.
    final replayRect = tester.getRect(
      find.descendant(
        of: find.byTooltip('Replay Mission'),
        matching: find.byType(IconButton),
      ),
    );
    final mapRect = tester.getRect(
      find.descendant(
        of: find.byTooltip('World Map'),
        matching: find.byType(IconButton),
      ),
    );
    expect(replayRect.top, greaterThanOrEqualTo(0));
    expect(replayRect.bottom, lessThanOrEqualTo(640));
    expect(mapRect.top, greaterThanOrEqualTo(0));
    expect(mapRect.bottom, lessThanOrEqualTo(640));

    expect(tester.takeException(), isNull);
  });

  testWidgets('saved victory fixture: debrief backdrop, victory banner, '
      'medal glyphs, real facts', (tester) async {
    // Scene 1h restyle pin: the report reads as a debrief over the approved
    // backdrop, with exactly ONE result banner selected through
    // OrionArt.result(content.result), medal treatment derived from the real
    // StageResult.medal (vector glyphs, no per-medal bitmaps), and the real
    // stage facts. No score/time/kills/damage/R&D analytics exist here.
    await _pumpPanel(
      tester,
      _victoryContent(
        MissionSaveState.saved,
        moduleIds: const [RunModuleId.heavyCaliber],
        reward: const MissionRewardFact(
          title: 'Blueprint fragment',
          detail: 'Unlocks a new blueprint after saving.',
        ),
      ),
      onReplay: () {},
      onReturnToMap: () {},
    );

    // Debrief-hall backdrop + readability scrim, art cover-fit under the scrim.
    expect(
      find.byKey(const ValueKey('mission-report-backdrop')),
      findsOneWidget,
    );
    final backdropArt = find.descendant(
      of: find.byKey(const ValueKey('mission-report-backdrop')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is OrionAtlasSprite &&
            widget.art.fileName ==
                'reactor_rim_ui/backdrops/mission-report-debrief.png',
      ),
    );
    expect(backdropArt, findsOneWidget);
    final backdropStack = tester.widget<Stack>(
      find.ancestor(of: backdropArt, matching: find.byType(Stack)).first,
    );
    final layerKeys = [
      for (final child in backdropStack.children)
        (child is Positioned ? child.child : child).key,
    ];
    final artIndex = layerKeys.indexOf(
      const ValueKey('mission-report-backdrop-art'),
    );
    final scrimIndex = layerKeys.indexOf(
      const ValueKey('mission-report-scrim'),
    );
    expect(artIndex, greaterThanOrEqualTo(0));
    expect(scrimIndex, greaterThan(artIndex));

    // Exactly ONE victory banner via OrionArt.result(non-null result); the
    // defeat art must never appear next to it.
    expect(
      find.byKey(const ValueKey('mission-report-result-art')),
      findsOneWidget,
    );
    expect(_resultArt('reactor_rim_ui/results/victory.png'), findsOneWidget);
    expect(_resultArt('reactor_rim_ui/results/defeat.png'), findsNothing);

    // Medal glyph/color derives from the real StageResult.medal: gold rank 3.
    expect(find.byIcon(Icons.workspace_premium), findsNWidgets(3));
    final glyph = tester.widget<Icon>(
      find.byIcon(Icons.workspace_premium).first,
    );
    expect(glyph.color, OrionUiTheme.dark.creditGold);

    // Stage identity, real base-health result, comparison copy, save state.
    expect(find.text('Victory'), findsOneWidget);
    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expect(find.text('Gold medal • Base 20/20'), findsOneWidget);
    expect(find.text('New first-clear result'), findsOneWidget);
    expect(find.text('Saved.'), findsOneWidget);

    // Module content/count and reward as subordinate sections.
    expect(find.text('Salvage Modules · 1'), findsOneWidget);
    expect(
      find.textContaining(runModuleDefinition(RunModuleId.heavyCaliber).title),
      findsOneWidget,
    );
    expect(find.text('Blueprint fragment'), findsOneWidget);

    // Current state-appropriate actions.
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);
  });

  testWidgets('loss shows the defeat banner and keeps Retry + World Map', (
    tester,
  ) async {
    // OrionArt.result(null) must resolve the defeat banner; a loss has no
    // StageResult, so no medal treatment may appear.
    var retried = false;
    var returned = false;
    await _pumpPanel(
      tester,
      _lossContent(),
      onReplay: () => retried = true,
      onReturnToMap: () => returned = true,
    );

    expect(
      find.byKey(const ValueKey('mission-report-result-art')),
      findsOneWidget,
    );
    expect(_resultArt('reactor_rim_ui/results/defeat.png'), findsOneWidget);
    expect(_resultArt('reactor_rim_ui/results/victory.png'), findsNothing);
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    expect(find.text('Mission Failed'), findsOneWidget);
    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expect(find.text('Reached Wave 5/8'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry'));
    await tester.tap(find.byTooltip('World Map'));
    expect(retried, isTrue);
    expect(returned, isTrue);
  });

  testWidgets('Reduced Motion leaves saved-victory actions immediately '
      'available', (tester) async {
    // No entrance animation may delay action availability: with animations
    // disabled the Replay action fires on the very first frame, with no
    // settling pumps in between.
    var replayed = false;
    await _pumpPanel(
      tester,
      _victoryContent(MissionSaveState.saved),
      onReplay: () => replayed = true,
      disableAnimations: true,
    );

    await tester.tap(find.byTooltip('Replay Mission'));
    expect(replayed, isTrue);
  });

  testWidgets('capture scene 1h fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1h state: saved victory — debrief backdrop + scrim,
    // victory result banner, gold medal glyphs, real stage facts, module strip
    // + reward, Replay/World Map actions. Real Roboto + Material icons so the
    // evidence shows true text metrics.
    await loadRealFonts();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same keys the OrionArt descriptors use) so the art renders.
    await tester.runAsync(() async {
      await Flame.images.load(
        'reactor_rim_ui/backdrops/mission-report-debrief.png',
      );
      await Flame.images.load('reactor_rim_ui/results/victory.png');
    });

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: orionThemeData,
          home: Scaffold(
            body: MissionReportPanel(
              content: _victoryContent(
                MissionSaveState.saved,
                moduleIds: const [
                  RunModuleId.heavyCaliber,
                  RunModuleId.overclockRelay,
                ],
                reward: const MissionRewardFact(
                  title: 'Blueprint fragment',
                  detail: 'Unlocks a new blueprint after saving.',
                ),
              ),
              onReplay: () {},
              onReturnToMap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mission-report-backdrop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mission-report-backdrop-art')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mission-report-scrim')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mission-report-result-art')),
      findsOneWidget,
    );
    expect(_resultArt('reactor_rim_ui/results/victory.png'), findsOneWidget);
    expect(find.text('Victory'), findsOneWidget);
    expect(findOrionTitle('Outpost Alpha'), findsOneWidget);
    expect(find.text('Gold medal • Base 20/20'), findsOneWidget);
    expect(find.text('New first-clear result'), findsOneWidget);
    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Salvage Modules · 2'), findsOneWidget);
    expect(find.text('Blueprint fragment'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1h.png'),
    );
  });
}

Finder _resultArt(String fileName) => find.byWidgetPredicate(
  (widget) => widget is OrionAtlasSprite && widget.art.fileName == fileName,
);

Future<void> _pumpPanel(
  WidgetTester tester,
  MissionReportContent content, {
  VoidCallback? onReplay,
  VoidCallback? onReturnToMap,
  VoidCallback? onRetrySave,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: Scaffold(
          body: MissionReportPanel(
            content: content,
            onReplay: onReplay,
            onReturnToMap: onReturnToMap,
            onRetrySave: onRetrySave,
          ),
        ),
      ),
    ),
  );

  expect(find.byType(OrionSurface), findsWidgets);
}

GameSnapshot _syntheticSnapshot({
  List<RunModuleId> modules = const [],
  int baseHealth = 20,
  int waveNumber = 8,
  GamePhase phase = GamePhase.won,
}) {
  return commandDeckSnapshot(
    phase: phase,
    gold: 120,
    baseHealth: baseHealth,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    stageLabel: 'Alpha',
    unlockedTowerTypes: const [TowerType.laser, TowerType.cryo],
    acquiredRunModules: modules,
  );
}

MissionReportContent _victoryContent(
  MissionSaveState saveState, {
  List<RunModuleId> moduleIds = const [],
  MissionRewardFact? reward,
}) {
  return projectVictoryReport(
    snapshot: _syntheticSnapshot(modules: moduleIds),
    result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    priorSavedResult: null,
    saveState: saveState,
    reward: reward,
  );
}

MissionReportContent _victoryContentNullSaveState() {
  return MissionReportContent(
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    didWin: true,
    outcomeText: 'Gold medal • Base 20/20',
    comparisonText: 'New first-clear result',
    moduleIds: const [],
    emptyModulesText: 'No Salvage Modules acquired',
    saveState: null,
    saveText: 'Save status pending.',
    nextOpportunityText:
        'Replay for a better result or continue on the World Map.',
  );
}

MissionReportContent _lossContent() {
  return projectLossReport(
    snapshot: _syntheticSnapshot(
      phase: GamePhase.lost,
      baseHealth: 0,
      waveNumber: 5,
    ),
  );
}
