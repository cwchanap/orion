import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import 'package:orion/game/ui/mission_report_panel.dart';
import '../support/command_deck_fixtures.dart';

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
}

Future<void> _pumpPanel(
  WidgetTester tester,
  MissionReportContent content, {
  VoidCallback? onReplay,
  VoidCallback? onReturnToMap,
  VoidCallback? onRetrySave,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MissionReportPanel(
          content: content,
          onReplay: onReplay,
          onReturnToMap: onReturnToMap,
          onRetrySave: onRetrySave,
        ),
      ),
    ),
  );

  expect(find.byKey(const ValueKey('mission-report-frame')), findsOneWidget);
  expect(find.byType(CommandFrame), findsWidgets);
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
