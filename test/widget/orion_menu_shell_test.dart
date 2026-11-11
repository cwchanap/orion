import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_menu_shell.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

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
  testWidgets('menu destinations identify the current scene beside resources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (destination, kicker, title) in [
      (OrionMenuDestination.sectors, 'ORION CAMPAIGN', 'ORION SECTOR'),
      (OrionMenuDestination.research, 'CAMPAIGN UPGRADES', 'R & D'),
      (OrionMenuDestination.codex, 'FIELD MANUAL', 'CODEX'),
    ]) {
      await tester.pumpWidget(buildShell(destination: destination));
      expect(find.text(kicker), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      final titleRect = tester.getRect(find.text(title));
      final medalsRect = tester.getRect(find.text('4/15'));
      expect(titleRect.right, lessThanOrEqualTo(medalsRect.left));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('active research tab uses the research accent', (tester) async {
    await tester.pumpWidget(
      buildShell(destination: OrionMenuDestination.research),
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('R&D'),
        matching: find.byIcon(Icons.biotech_rounded),
      ),
    );
    expect(icon.color, OrionUiTheme.dark.systemViolet);
  });

  testWidgets('research header announces the unspent balance', (tester) async {
    await tester.pumpWidget(
      buildShell(destination: OrionMenuDestination.research),
    );
    expect(find.bySemanticsLabel('Unspent: 7'), findsOneWidget);
  });

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

    expect(find.text('4/15'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.bySemanticsLabel('4 of 15 campaign medals'), findsOneWidget);
    expect(find.bySemanticsLabel('7 research points'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    expect(settingsTaps, 1);
  });

  testWidgets('the Settings gear keeps a 48x48 interaction region that fires '
      'from its edges', (tester) async {
    var settingsTaps = 0;
    await tester.pumpWidget(
      buildShell(onOpenSettings: () => settingsTaps += 1),
    );

    final inkWell = find.descendant(
      of: find.byTooltip('Settings'),
      matching: find.byType(InkWell),
    );
    final rect = tester.getRect(inkWell);
    expect(rect.width >= 48 && rect.height >= 48, isTrue, reason: '$rect');

    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    await tester.tapAt(Offset(rect.right - 5, rect.bottom - 5));
    expect(settingsTaps, 4);
  });

  testWidgets('the disabled Settings gear does not fire from its edges', (
    tester,
  ) async {
    var settingsTaps = 0;
    await tester.pumpWidget(
      buildShell(
        settingsEnabled: false,
        onOpenSettings: () => settingsTaps += 1,
      ),
    );

    final rect = tester.getRect(
      find.descendant(
        of: find.byTooltip('Settings'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
    expect(settingsTaps, 0);
  });

  testWidgets('the Settings gear stays in bounds at 360x640 without crowding '
      'the chips', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildShell());

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(
      find.descendant(
        of: find.byTooltip('Settings'),
        matching: find.byType(InkWell),
      ),
    );
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    final chip = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '7 research points',
      ),
    );
    expect(
      rect.left,
      greaterThanOrEqualTo(chip.right),
      reason: 'the 48dp region overlaps the research chip at $rect vs $chip',
    );
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

    for (final tab in const ['Map', 'R&D', 'Codex']) {
      await tester.tap(find.byTooltip(tab));
    }
    expect(selected, isEmpty);

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

  testWidgets('landscape side insets reach the embedded destination view', (
    tester,
  ) async {
    EdgeInsets? bodyPadding;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(left: 40, right: 20, top: 24),
          viewPadding: EdgeInsets.only(left: 40, right: 20, top: 24),
        ),
        child: buildShell(
          child: Builder(
            builder: (context) {
              bodyPadding = MediaQuery.paddingOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(bodyPadding, isNotNull);
    expect(bodyPadding!.left, 40);
    expect(bodyPadding!.right, 20);
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

    expect(feedbackRect.top, greaterThanOrEqualTo(gearRect.bottom));
    expect(childRect.top, greaterThanOrEqualTo(feedbackRect.bottom));
    expect(tabRect.top, greaterThanOrEqualTo(childRect.bottom));
  });
}
