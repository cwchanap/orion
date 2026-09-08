import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/mission_surface.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Widget surfaceHost({
  bool emphasized = false,
  double radius = 18,
  EdgeInsetsGeometry? padding,
}) {
  return MaterialApp(
    home: MissionSurface(
      key: const ValueKey('surface'),
      emphasized: emphasized,
      radius: radius,
      padding: padding ?? const EdgeInsets.all(8),
      child: const SizedBox.shrink(),
    ),
  );
}

BoxDecoration surfaceDecoration(WidgetTester tester) {
  return tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.byKey(const ValueKey('surface')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .decoration
      as BoxDecoration;
}

void main() {
  testWidgets('default surface delegates to the t2 tier', (tester) async {
    await tester.pumpWidget(surfaceHost());

    final decoration = surfaceDecoration(tester);
    expect(decoration.color, isNull);
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, [
      OrionUiTheme.dark.panelRaised.withValues(alpha: 0.66),
      OrionUiTheme.dark.hullBlack.withValues(alpha: 0.76),
    ]);
    expect(decoration.borderRadius, BorderRadius.circular(18));

    final border = decoration.border! as Border;
    expect(border.top.color, OrionUiTheme.dark.frameSteel);
    expect(border.top.width, 1);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('emphasized surface delegates to the t3 tier', (tester) async {
    await tester.pumpWidget(surfaceHost(emphasized: true));

    final decoration = surfaceDecoration(tester);
    expect(decoration.color, isNull);
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, [
      OrionUiTheme.dark.panelBlue.withValues(alpha: 0.90),
      OrionUiTheme.dark.sheetBlack.withValues(alpha: 0.94),
    ]);

    final border = decoration.border! as Border;
    expect(
      border.top.color,
      OrionUiTheme.dark.systemCyan.withValues(alpha: 0.3),
    );
    expect(border.top.width, 1);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('custom radius and padding are honored', (tester) async {
    const padding = EdgeInsets.symmetric(horizontal: 4, vertical: 2);
    await tester.pumpWidget(surfaceHost(radius: 10, padding: padding));

    final decoration = surfaceDecoration(tester);
    expect(decoration.borderRadius, BorderRadius.circular(10));

    final surfacePadding = tester.widget<Padding>(
      find.descendant(
        of: find.byKey(const ValueKey('surface')),
        matching: find.byType(Padding),
      ),
    );
    expect(surfacePadding.padding, padding);
  });

  testWidgets('introduces no gesture handling or semantics by itself', (
    tester,
  ) async {
    Widget bareHost() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: MissionSurface(
          key: const ValueKey('surface'),
          child: const SizedBox.shrink(),
        ),
      );
    }

    await tester.pumpWidget(bareHost());
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkWell), findsNothing);

    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(bareHost());
      final renderObject = tester.renderObject<RenderObject>(
        find.byKey(const ValueKey('surface')),
      );
      final root = renderObject.owner!.semanticsOwner!.rootSemanticsNode!;
      expect(
        root.childrenCount,
        0,
        reason: 'MissionSurface must not produce a semantics node by itself.',
      );
    } finally {
      handle.dispose();
    }
  });
}
