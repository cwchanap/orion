import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import 'package:orion/game/ui/mission_report_panel.dart';

void main() {
  testWidgets('saving victory shows save copy and disables both exits', (
    tester,
  ) async {
    // Catches a production panel that exposes replay/map before save truth is
    // resolved, which could discard an improving result.
    await _pumpPanel(tester, _victoryContent(MissionSaveState.saving));

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
}

MissionReportContent _victoryContent(
  MissionSaveState saveState, {
  List<RunModuleId> moduleIds = const [],
  MissionRewardFact? reward,
}) {
  final saveText = switch (saveState) {
    MissionSaveState.saving => 'Saving result…',
    MissionSaveState.saved => 'Saved.',
    MissionSaveState.failed => 'Save failed — progress unchanged.',
  };
  final nextOpportunityText = switch (saveState) {
    MissionSaveState.saving => 'Saving must finish before you replay or leave.',
    MissionSaveState.saved =>
      'Replay for a better result or continue on the World Map.',
    MissionSaveState.failed =>
      'Retry saving, or return without keeping this result.',
  };

  return MissionReportContent(
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    didWin: true,
    outcomeText: 'Gold medal • Base 20/20',
    comparisonText: 'New first-clear result',
    moduleIds: moduleIds,
    emptyModulesText: moduleIds.isEmpty ? 'No Salvage Modules acquired' : null,
    saveState: saveState,
    saveText: saveText,
    reward: reward,
    nextOpportunityText: nextOpportunityText,
  );
}

MissionReportContent _lossContent() {
  return MissionReportContent(
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    didWin: false,
    outcomeText: 'Reached Wave 5/8',
    moduleIds: [],
    emptyModulesText: 'No Salvage Modules acquired',
    nextOpportunityText: 'Adjust your build and retry when ready.',
  );
}
