import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/acquired_run_module_control.dart';
import 'package:orion/game/ui/mission_collapsible.dart';

const _collapsedTrigger = ValueKey('acquired-modules-collapsed');
const _expandedDetails = ValueKey('acquired-modules-expanded');

const _threeModules = [
  RunModuleId.heavyCaliber,
  RunModuleId.cryoReservoir,
  RunModuleId.rocketFusing,
];

Widget controlHost(
  List<RunModuleId> moduleIds, {
  bool collapseRequested = false,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        // Copy (not replace) the ambient media query so the expanded sheet's
        // viewport-derived max height stays real.
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Align(
          alignment: Alignment.topRight,
          child: AcquiredRunModuleControl(
            moduleIds: moduleIds,
            collapseRequested: collapseRequested,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty module list renders no trigger at all', (tester) async {
    await tester.pumpWidget(controlHost(const []));

    expect(find.byType(MissionCollapsible), findsNothing);
    expect(find.byKey(_collapsedTrigger), findsNothing);
    expect(find.textContaining('Modules'), findsNothing);
  });

  testWidgets('three modules produce a Modules 3 trigger', (tester) async {
    await tester.pumpWidget(controlHost(_threeModules));

    expect(find.byKey(_collapsedTrigger), findsOneWidget);
    expect(find.text('Modules 3'), findsOneWidget);
  });

  testWidgets('collapsed trigger is at least 48dp', (tester) async {
    await tester.pumpWidget(controlHost(_threeModules));

    final size = tester.getSize(find.byKey(_collapsedTrigger));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('semantics announce the acquired module count and button state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(controlHost(_threeModules));

      final node = find.bySemanticsLabel(RegExp('Acquired modules: 3'));
      expect(node, findsOneWidget);
      final data = tester.getSemantics(node).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.actions & SemanticsAction.tap.index, isNot(0));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('opening shows every title, effect, and affinity row', (
    tester,
  ) async {
    await tester.pumpWidget(controlHost(_threeModules));

    await tester.tap(find.text('Modules 3'));
    await tester.pumpAndSettle();

    expect(find.byKey(_expandedDetails), findsOneWidget);
    expect(find.byKey(_collapsedTrigger), findsNothing);
    expect(find.text('Heavy Caliber'), findsOneWidget);
    expect(find.textContaining('All tower damage rises'), findsOneWidget);
    expect(find.text('Universal'), findsOneWidget);
    expect(find.text('Cryo Reservoir'), findsOneWidget);
    expect(find.textContaining('Cryo slows last'), findsOneWidget);
    expect(find.text('Cryo'), findsOneWidget);
    expect(find.text('Rocket Fusing'), findsOneWidget);
    expect(find.textContaining('Rocket splash grows'), findsOneWidget);
    expect(find.text('Rocket'), findsOneWidget);
  });

  testWidgets('collapseRequested closes the expansion', (tester) async {
    await tester.pumpWidget(controlHost(_threeModules));
    await tester.tap(find.text('Modules 3'));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedDetails), findsOneWidget);

    await tester.pumpWidget(
      controlHost(_threeModules, collapseRequested: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_collapsedTrigger), findsOneWidget);
    expect(find.byKey(_expandedDetails), findsNothing);
  });

  testWidgets('module-list content change resets expansion closed', (
    tester,
  ) async {
    await tester.pumpWidget(controlHost(_threeModules));
    await tester.tap(find.text('Modules 3'));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedDetails), findsOneWidget);

    await tester.pumpWidget(
      controlHost([..._threeModules, RunModuleId.emergencySalvage]),
    );

    expect(find.byKey(_collapsedTrigger), findsOneWidget);
    expect(find.byKey(_expandedDetails), findsNothing);
    expect(find.text('Modules 4'), findsOneWidget);
  });

  testWidgets('uses the shared MissionCollapsible, not an overlay menu', (
    tester,
  ) async {
    await tester.pumpWidget(controlHost(_threeModules));

    // The low-level collapse invariant (hit-area release, Reduced Motion,
    // pointer blocking) is owned by MissionCollapsible's own tests; this
    // pins that the module control routes through it instead of building a
    // bespoke Overlay/MenuAnchor popup.
    expect(find.byType(MissionCollapsible), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AcquiredRunModuleControl),
        matching: find.byType(Overlay),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AcquiredRunModuleControl),
        matching: find.byType(MenuAnchor),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AcquiredRunModuleControl),
        matching: find.byType(PopupMenuButton<void>),
      ),
      findsNothing,
    );
  });

  testWidgets('reduced motion expands after one pump', (tester) async {
    await tester.pumpWidget(
      controlHost(_threeModules, disableAnimations: true),
    );

    await tester.tap(find.text('Modules 3'));
    await tester.pump();
    expect(find.byKey(_expandedDetails), findsOneWidget);

    await tester.tap(find.byKey(_expandedDetails));
    await tester.pump();
    expect(find.byKey(_collapsedTrigger), findsOneWidget);
  });
}
