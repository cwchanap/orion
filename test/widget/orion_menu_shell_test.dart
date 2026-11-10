import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_menu_shell.dart';
import 'package:orion/game/ui/orion_theme_data.dart';

Widget buildShell({
  OrionMenuDestination destination = OrionMenuDestination.sectors,
  int medalEarned = 4,
  int medalTotal = 15,
  int researchPoints = 7,
  ValueChanged<OrionMenuDestination>? onDestinationSelected,
  VoidCallback? onOpenSettings,
  bool navigationEnabled = true,
  bool settingsEnabled = true,
  String? feedback,
  Widget child = const SizedBox.expand(),
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: orionThemeData,
    home: OrionMenuShell(
      destination: destination,
      medalEarned: medalEarned,
      medalTotal: medalTotal,
      researchPoints: researchPoints,
      onDestinationSelected: onDestinationSelected ?? (_) {},
      onOpenSettings: onOpenSettings ?? () {},
      navigationEnabled: navigationEnabled,
      settingsEnabled: settingsEnabled,
      feedback: feedback,
      child: child,
    ),
  );
}

void main() {
  testWidgets('top bar carries the resource chips and the Settings gear', (
    tester,
  ) async {
    var settingsTaps = 0;
    await tester.pumpWidget(
      buildShell(
        medalEarned: 4,
        medalTotal: 15,
        researchPoints: 7,
        onOpenSettings: () => settingsTaps += 1,
      ),
    );

    // The shared campaign readouts live in the top chrome on every
    // destination — not per-view.
    expect(find.text('4/15'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.bySemanticsLabel('4 of 15 campaign medals'), findsOneWidget);
    expect(find.bySemanticsLabel('7 research points'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    expect(settingsTaps, 1);
  });

  testWidgets('bottom tabs report every destination and mark the active one', (
    tester,
  ) async {
    final selected = <OrionMenuDestination>[];
    await tester.pumpWidget(
      buildShell(
        destination: OrionMenuDestination.sectors,
        onDestinationSelected: selected.add,
      ),
    );

    for (final tab in const ['Map', 'R&D', 'Codex']) {
      expect(find.byTooltip(tab), findsOneWidget);
    }

    await tester.tap(find.byTooltip('Codex'));
    await tester.tap(find.byTooltip('R&D'));
    await tester.tap(find.byTooltip('Map'));
    expect(selected, [
      OrionMenuDestination.codex,
      OrionMenuDestination.research,
      OrionMenuDestination.sectors,
    ]);

    // The active destination reads as selected in the semantics tree so
    // assistive tech can announce it.
    expect(
      tester
          .widget<Semantics>(
            find.ancestor(
              of: find.byTooltip('Map'),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.selected != null,
              ),
            ),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('navigationEnabled false leaves the tabs inert', (tester) async {
    final selected = <OrionMenuDestination>[];
    var settingsTaps = 0;
    await tester.pumpWidget(
      buildShell(
        navigationEnabled: false,
        onDestinationSelected: selected.add,
        onOpenSettings: () => settingsTaps += 1,
      ),
    );

    // The tabs stay visible (the player can see where they are) but report
    // nothing — navigation must not interleave with a campaign write.
    for (final tab in const ['Map', 'R&D', 'Codex']) {
      await tester.tap(find.byTooltip(tab));
    }
    expect(selected, isEmpty);

    // The settings gear is independent of campaign busy state.
    await tester.tap(find.byTooltip('Settings'));
    expect(settingsTaps, 1);
  });

  testWidgets('settingsEnabled false disables only the gear', (tester) async {
    final selected = <OrionMenuDestination>[];
    var settingsTaps = 0;
    await tester.pumpWidget(
      buildShell(
        settingsEnabled: false,
        onDestinationSelected: selected.add,
        onOpenSettings: () => settingsTaps += 1,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    expect(settingsTaps, 0);

    await tester.tap(find.byTooltip('Codex'));
    expect(selected, [OrionMenuDestination.codex]);
  });

  testWidgets('the shared breadcrumb line renders between chrome and child', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildShell(
        feedback: 'Saving campaign progress…',
        child: const ColoredBox(
          key: ValueKey('shell-child'),
          color: Colors.black,
        ),
      ),
    );

    expect(find.text('Saving campaign progress…'), findsOneWidget);
    final feedbackRect = tester.getRect(find.text('Saving campaign progress…'));
    final gearRect = tester.getRect(find.byTooltip('Settings'));
    final tabRect = tester.getRect(find.byTooltip('Map'));
    final childRect = tester.getRect(find.byKey(const ValueKey('shell-child')));

    // Stacked in the fixed order: top bar, breadcrumb, child, tab bar.
    expect(feedbackRect.top, greaterThanOrEqualTo(gearRect.bottom));
    expect(childRect.top, greaterThanOrEqualTo(feedbackRect.bottom));
    expect(tabRect.top, greaterThanOrEqualTo(childRect.bottom));
  });
}
