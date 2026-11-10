import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Widget host({
  required OrionSurfaceRole role,
  double radius = 18,
  EdgeInsetsGeometry? padding,
  bool topBorderOnly = false,
  Widget child = const SizedBox.shrink(),
}) {
  return MaterialApp(
    home: Scaffold(
      body: OrionSurface(
        key: const ValueKey('surface'),
        role: role,
        radius: radius,
        topBorderOnly: topBorderOnly,
        padding: padding ?? const EdgeInsets.all(8),
        child: child,
      ),
    ),
  );
}

BoxDecoration surfaceDecoration(WidgetTester tester) {
  return tester
          .widget<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('surface')),
              matching: find.byType(Container),
            ),
          )
          .decoration
      as BoxDecoration;
}

void main() {
  test('exactly four semantic roles exist', () {
    // The kit's surface vocabulary: floating controls on live art, content
    // cards, scene-covering sheets and the dock shelf. The old t1-t4 blur
    // tier names are gone for good.
    expect(OrionSurfaceRole.values, [
      OrionSurfaceRole.floating,
      OrionSurfaceRole.card,
      OrionSurfaceRole.sheet,
      OrionSurfaceRole.shelf,
    ]);
  });

  testWidgets('no role renders a BackdropFilter', (t) async {
    for (final role in OrionSurfaceRole.values) {
      await t.pumpWidget(host(role: role));
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'role $role: surfaces are solid; the blur tier is retired',
      );
    }
  });

  testWidgets('every role is fully solid', (t) async {
    for (final role in OrionSurfaceRole.values) {
      await t.pumpWidget(host(role: role));
      final decoration = surfaceDecoration(t);
      final colors = decoration.gradient is LinearGradient
          ? (decoration.gradient! as LinearGradient).colors
          : [decoration.color!];
      for (final c in colors) {
        expect(
          c.a,
          greaterThanOrEqualTo(0.85),
          reason:
              'role $role: the art stays visible behind the panel, not '
              'through it',
        );
      }
    }
  });

  testWidgets('card renders the kit .card chrome', (t) async {
    await t.pumpWidget(host(role: OrionSurfaceRole.card));
    final decoration = surfaceDecoration(t);
    expect(
      (decoration.gradient! as LinearGradient).colors,
      orionCardFill.colors,
    );
    final border = decoration.border! as Border;
    expect(border.top.color, orionCardEdge);
    expect(border.top.width, 1.5);
    // The 0 3px 0 bottom lip is the card's depth cue.
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', orionCardLip)
            .having((s) => s.offset, 'offset', const Offset(0, 3))
            .having((s) => s.blurRadius, 'blurRadius', 0),
      ),
    );
  });

  testWidgets('sheet renders the kit .panel chrome with corner brackets', (
    t,
  ) async {
    await t.pumpWidget(host(role: OrionSurfaceRole.sheet));
    final decoration = surfaceDecoration(t);
    expect(
      (decoration.gradient! as LinearGradient).colors,
      orionPanelFill.colors,
    );
    final border = decoration.border! as Border;
    expect(border.top.color, orionPanelEdge);
    expect(border.top.width, 1.5);
    expect(decoration.boxShadow, orionPanelShadow);
    // The kit's restrained .br corner brackets ride on the framed panel.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('surface')),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.foregroundPainter != null,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('floating renders the kit fab chrome', (t) async {
    await t.pumpWidget(host(role: OrionSurfaceRole.floating));
    final decoration = surfaceDecoration(t);
    expect(
      decoration.color,
      OrionUiTheme.dark.hullBlack.withValues(alpha: 0.88),
    );
    final border = decoration.border! as Border;
    expect(border.top.color, orionFloatingEdge);
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', OrionUiTheme.dark.voidBlack)
            .having((s) => s.offset, 'offset', const Offset(0, 3)),
      ),
    );
  });

  testWidgets('shelf renders the dock tray chrome, top edge only', (t) async {
    await t.pumpWidget(
      host(role: OrionSurfaceRole.shelf, radius: 0, topBorderOnly: true),
    );
    final decoration = surfaceDecoration(t);
    expect(
      (decoration.gradient! as LinearGradient).colors,
      orionShelfFill.colors,
    );
    final border = decoration.border! as Border;
    expect(border.top.color, orionShelfEdge);
    expect(border.top.style, BorderStyle.solid);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
    expect(border.bottom, BorderSide.none);
  });

  testWidgets('custom radius and padding are honored', (t) async {
    const padding = EdgeInsets.symmetric(horizontal: 4, vertical: 2);
    await t.pumpWidget(
      host(
        role: OrionSurfaceRole.card,
        radius: 10,
        padding: padding,
        child: const SizedBox(width: 50, height: 50),
      ),
    );
    final decoration = surfaceDecoration(t);
    expect(decoration.borderRadius, BorderRadius.circular(10));
    // The kit's border-box model: content sits `padding` inside the 1.5px
    // frame, so 4/2 padding lands 5.5/3.5 in from the surface's outer edge.
    final surfaceRect = t.getRect(find.byKey(const ValueKey('surface')));
    final childRect = t.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('surface')),
        matching: find.byType(SizedBox),
      ),
    );
    expect(childRect.left - surfaceRect.left, closeTo(5.5, 0.01));
    expect(childRect.top - surfaceRect.top, closeTo(3.5, 0.01));
  });

  testWidgets('introduces no gesture handling or semantics by itself', (
    tester,
  ) async {
    Widget bareHost() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: OrionSurface(
          key: const ValueKey('surface'),
          role: OrionSurfaceRole.card,
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
        reason: 'OrionSurface must not produce a semantics node by itself.',
      );
    } finally {
      handle.dispose();
    }
  });
}
