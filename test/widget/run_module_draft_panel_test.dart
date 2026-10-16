import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/orion_finders.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_surface.dart';
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

    expect(findOrionTitle('Salvage Module 2 of 3'), findsOneWidget);
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
    expect(find.byType(OrionSurface), findsWidgets);

    final semanticsHandle = tester.ensureSemantics();
    try {
      // With no placed towers, stat modules say who they will benefit.
      const contextById = {
        RunModuleId.heavyCaliber: '. Affects every tower you build',
        RunModuleId.emergencySalvage: '',
        RunModuleId.cryoReservoir: '. Benefits Cryo towers you build later',
      };
      for (final id in offer.moduleIds) {
        final definition = runModuleDefinition(id);
        expect(
          find.bySemanticsLabel(
            '${definition.title}. ${definition.effectText} '
            'Affinity: ${definition.affinity.label}${contextById[id]}',
          ),
          findsOneWidget,
        );
      }
    } finally {
      semanticsHandle.dispose();
    }

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
    expect(find.byType(OrionSurface), findsWidgets);
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
  group('current-run context', () {
    Future<void> pumpPanel(
      WidgetTester tester,
      List<RunModuleId> moduleIds,
      Map<RunModuleId, int> beneficiaries, {
      ValueChanged<RunModuleId>? onSelected,
    }) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RunModuleDraftPanel(
              offer: RunModuleOffer(
                offerId: 1,
                draftNumber: 1,
                draftTotal: GameBalance.moduleDraftWaves.length,
                moduleIds: moduleIds,
              ),
              beneficiaries: beneficiaries,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('universal and affinity modules count placed towers', (
      tester,
    ) async {
      RunModuleId? selected;
      await pumpPanel(
        tester,
        const [
          RunModuleId.heavyCaliber,
          RunModuleId.cryoReservoir,
          RunModuleId.longSight,
        ],
        const {
          RunModuleId.heavyCaliber: 3,
          RunModuleId.cryoReservoir: 2,
          RunModuleId.longSight: 1,
        },
        onSelected: (id) => selected = id,
      );

      expect(find.text('Affects your 3 placed towers'), findsOneWidget);
      expect(find.text('Affects your 2 placed Cryo towers'), findsOneWidget);
      expect(find.text('Affects your 1 placed tower'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final semantics = tester.ensureSemantics();
      try {
        final cryo = runModuleDefinition(RunModuleId.cryoReservoir);
        expect(
          find.bySemanticsLabel(
            '${cryo.title}. ${cryo.effectText} Affinity: Cryo. '
            'Affects your 2 placed Cryo towers',
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }

      await tester.tap(find.text('Long Sight'));
      expect(selected, RunModuleId.longSight);
    });

    testWidgets('zero beneficiaries use honest future-facing wording', (
      tester,
    ) async {
      await pumpPanel(tester, const [
        RunModuleId.heavyCaliber,
        RunModuleId.cryoReservoir,
        RunModuleId.rocketFusing,
      ], const {});

      expect(find.text('Affects every tower you build'), findsOneWidget);
      expect(find.text('Benefits Cryo towers you build later'), findsOneWidget);
      expect(
        find.text('Benefits Rocket towers you build later'),
        findsOneWidget,
      );
    });

    testWidgets('economy modules keep their direct wording only', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        const [
          RunModuleId.emergencySalvage,
          RunModuleId.heavyCaliber,
          RunModuleId.longSight,
        ],
        const {
          RunModuleId.emergencySalvage: 0,
          RunModuleId.heavyCaliber: 2,
          RunModuleId.longSight: 2,
        },
      );

      expect(find.textContaining('Affects'), findsNWidgets(2));
      expect(find.textContaining('build later'), findsNothing);
      expect(find.textContaining('you build'), findsNothing);

      final semantics = tester.ensureSemantics();
      try {
        final salvage = runModuleDefinition(RunModuleId.emergencySalvage);
        expect(
          find.bySemanticsLabel(
            '${salvage.title}. ${salvage.effectText} '
            'Affinity: ${salvage.affinity.label}',
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });
  });
}
