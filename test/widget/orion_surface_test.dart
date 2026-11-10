import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

typedef Shot = ({int width, int height, ByteData bytes});

Future<Shot> shotOf(WidgetTester tester, GlobalKey key) async {
  late Shot shot;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    shot = (
      width: image.width,
      height: image.height,
      bytes: (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
    );
    image.dispose();
  });
  return shot;
}

int channel(Shot shot, int x, int y, int c) =>
    shot.bytes.getUint8((y * shot.width + x) * 4 + c);

void main() {
  test('edge bands land inside the deflated frame', () async {
    const size = Size(50, 30);
    Future<ui.Image> paint({
      Color? top,
      double? tw,
      Color? bottom,
      double? bw,
    }) {
      final recorder = ui.PictureRecorder();
      OrionInsetEdgePainter(
        borderRadius: BorderRadius.circular(4),
        inset: 2,
        topColor: top,
        topWidth: tw ?? 0,
        bottomColor: bottom,
        bottomWidth: bw ?? 0,
      ).paint(Canvas(recorder), size);
      return recorder.endRecording().toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
    }

    Future<int> alphaAt(ui.Image image, int x, int y) async {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return bytes.getUint8((y * image.width + x) * 4 + 3);
    }

    final topImage = await paint(top: const Color(0xFF000000), tw: 2);
    addTearDown(topImage.dispose);
    expect(await alphaAt(topImage, 25, 3), 255);
    final bottomImage = await paint(bottom: const Color(0xFF000000), bw: 4);
    addTearDown(bottomImage.dispose);
    expect(await alphaAt(bottomImage, 25, 24), 255);
    expect(await alphaAt(bottomImage, 25, 25), 255);
  });

  testWidgets('card paints its lit top edge inside the frame', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: OrionSurface(
              role: OrionSurfaceRole.card,
              radius: 8,
              padding: EdgeInsets.zero,
              child: const SizedBox(width: 80, height: 48),
            ),
          ),
        ),
      ),
    );
    final shot = await shotOf(t, key);
    final x = shot.width ~/ 2;
    expect(
      channel(shot, x, 2, 0) - channel(shot, x, 6, 0),
      greaterThan(4),
      reason: 'the .card top glint must land inside the 1.5px frame',
    );
  });

  testWidgets('sheet paints its lit top edge inside the frame', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: OrionSurface(
              role: OrionSurfaceRole.sheet,
              radius: 8,
              padding: EdgeInsets.zero,
              child: const SizedBox(width: 80, height: 48),
            ),
          ),
        ),
      ),
    );
    final shot = await shotOf(t, key);
    final x = shot.width ~/ 2;
    expect(
      channel(shot, x, 2, 0) - channel(shot, x, 6, 0),
      greaterThan(4),
      reason: 'the .panel top glint must land inside the 1.5px frame',
    );
  });

  test('exactly four semantic roles exist', () {
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
    // Border(top: ...) leaves left/right/bottom at BorderSide.none, unlike
    // Border.fromBorderSide (the default), which sets all four sides equal
    // to the same visible side.
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
