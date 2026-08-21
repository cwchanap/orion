import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/run_module_draft_panel.dart';

void main() {
  testWidgets('draft panel shows the offer and selects a module', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final offer = RunModuleOffer(
      offerId: 4,
      draftNumber: 2,
      draftTotal: GameBalance.moduleDraftWaves.length,
      moduleIds: const [
        RunModuleId.heavyCaliber,
        RunModuleId.emergencySalvage,
        RunModuleId.cryoReservoir,
      ],
    );
    var selectedCount = 0;
    RunModuleId? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunModuleDraftPanel(
            offer: offer,
            onSelected: (moduleId) {
              selectedCount += 1;
              selected = moduleId;
            },
          ),
        ),
      ),
    );

    expect(find.text('Salvage Module 2 of 3'), findsOneWidget);
    for (final id in offer.moduleIds) {
      final definition = runModuleDefinition(id);
      expect(find.text(definition.title), findsOneWidget);
      expect(find.text(definition.effectText), findsOneWidget);
      expect(find.text(definition.affinity.label), findsAtLeastNWidgets(1));
    }
    expect(
      find.byKey(const ValueKey('run-module-draft-frame')),
      findsOneWidget,
    );
    expect(find.byType(CommandFrame), findsWidgets);

    await tester.tap(find.text('Heavy Caliber'));
    await tester.pump();
    expect(selectedCount, 1);
    expect(selected, RunModuleId.heavyCaliber);
    expect(tester.takeException(), isNull);
  });

  testWidgets('acquired reminder renders title and inline effect text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AcquiredRunModuleStrip(moduleIds: [RunModuleId.heavyCaliber]),
        ),
      ),
    );

    final definition = runModuleDefinition(RunModuleId.heavyCaliber);
    expect(find.textContaining(definition.title), findsOneWidget);
    expect(find.textContaining(definition.effectText), findsOneWidget);
    expect(find.byType(CommandFrame), findsWidgets);
    expect(find.byType(InkResponse), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('empty acquired reminder renders no module copy', (tester) async {
    final definition = runModuleDefinition(RunModuleId.heavyCaliber);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AcquiredRunModuleStrip(moduleIds: [])),
      ),
    );

    expect(find.textContaining(definition.title), findsNothing);
    expect(find.textContaining(definition.effectText), findsNothing);
  });
}
