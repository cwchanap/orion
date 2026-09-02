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
  testWidgets('default surface is a translucent rounded hull panel', (
    tester,
  ) async {
    await tester.pumpWidget(surfaceHost());

    final decoration = surfaceDecoration(tester);
    expect(
      decoration.color,
      OrionUiTheme.dark.hullBlack.withValues(alpha: 0.85),
    );
    expect(decoration.borderRadius, BorderRadius.circular(18));

    final border = decoration.border! as Border;
    expect(
      border.top.color,
      OrionUiTheme.dark.systemCyan.withValues(alpha: 0.25),
    );
    expect(border.top.width, 1);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets(
    'emphasized surface uses strong cyan border and one restrained shadow',
    (tester) async {
      await tester.pumpWidget(surfaceHost(emphasized: true));

      final decoration = surfaceDecoration(tester);
      final border = decoration.border! as Border;
      expect(border.top.color, OrionUiTheme.dark.systemCyanStrong);
      expect(border.top.width, 2);

      expect(decoration.boxShadow, hasLength(1));
      final shadow = decoration.boxShadow!.single;
      expect(
        shadow.color,
        OrionUiTheme.dark.systemCyanStrong.withValues(alpha: 0.25),
      );
      expect(shadow.blurRadius, 12);
    },
  );

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
