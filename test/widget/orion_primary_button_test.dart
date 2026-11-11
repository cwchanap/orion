import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Widget host({
  required VoidCallback? onPressed,
  OrionButtonVariant variant = OrionButtonVariant.primary,
  bool loading = false,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: OrionPrimaryButton(
            label: 'Deploy',
            icon: Icons.play_arrow,
            onPressed: onPressed,
            variant: variant,
            loading: loading,
          ),
        ),
      ),
    ),
  );
}

Container buttonFrame(WidgetTester tester) {
  return tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(OrionPrimaryButton),
          matching: find.byType(Container),
        ),
      )
      .firstWhere((c) => c.decoration is BoxDecoration);
}

void main() {
  test('three action variants exist', () {
    expect(OrionButtonVariant.values, [
      OrionButtonVariant.primary,
      OrionButtonVariant.secondary,
      OrionButtonVariant.danger,
    ]);
  });

  testWidgets('primary renders the amber ramp on its 5px lip', (t) async {
    await t.pumpWidget(host(onPressed: () {}));
    final decoration = buttonFrame(t).decoration! as BoxDecoration;
    expect(
      (decoration.gradient! as LinearGradient).colors,
      orionPrimaryFill.colors,
    );
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', orionPrimaryLip)
            .having((s) => s.offset, 'offset', const Offset(0, 5))
            .having((s) => s.blurRadius, 'blurRadius', 0),
      ),
    );
  });

  testWidgets('secondary renders the cyan ramp on its own lip', (t) async {
    await t.pumpWidget(
      host(onPressed: () {}, variant: OrionButtonVariant.secondary),
    );
    final decoration = buttonFrame(t).decoration! as BoxDecoration;
    expect(
      (decoration.gradient! as LinearGradient).colors,
      orionSecondaryFill.colors,
    );
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', orionSecondaryLip)
            .having((s) => s.offset, 'offset', const Offset(0, 5)),
      ),
    );
  });

  testWidgets('danger renders the destructive edge and lip', (t) async {
    await t.pumpWidget(
      host(onPressed: () {}, variant: OrionButtonVariant.danger),
    );
    final decoration = buttonFrame(t).decoration! as BoxDecoration;
    expect(
      (decoration.gradient! as LinearGradient).colors,
      orionDangerFill.colors,
    );
    final border = decoration.border! as Border;
    expect(border.top.color, orionDangerEdge);
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', orionDangerLip)
            .having((s) => s.offset, 'offset', const Offset(0, 4)),
      ),
    );
  });

  testWidgets('light action surfaces keep their dark labels crisp', (t) async {
    for (final variant in [
      OrionButtonVariant.primary,
      OrionButtonVariant.secondary,
    ]) {
      await t.pumpWidget(host(onPressed: () {}, variant: variant));
      final label = t.widget<Text>(find.text('Deploy'));
      expect(label.style!.shadows, isEmpty);
    }
  });

  testWidgets('danger paints its lit top edge inside the frame', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: OrionPrimaryButton(
              label: 'Purge',
              icon: Icons.delete,
              onPressed: () {},
              variant: OrionButtonVariant.danger,
            ),
          ),
        ),
      ),
    );
    late ByteData bytes;
    late int width;
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      width = image.width;
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    int channel(int x, int y, int c) => bytes.getUint8((y * width + x) * 4 + c);
    final x = width ~/ 2;
    expect(
      channel(x, 3, 0) - channel(x, 6, 0),
      greaterThan(4),
      reason: 'the .danger top glint must land inside the 1.5px frame',
    );
  });

  testWidgets('fires onPressed', (t) async {
    var taps = 0;
    await t.pumpWidget(host(onPressed: () => taps++));
    await t.tap(find.byType(OrionPrimaryButton));
    expect(taps, 1);
  });

  testWidgets('press sinks the whole button onto a 1px lip', (t) async {
    await t.pumpWidget(host(onPressed: () {}));
    final center = t.getCenter(find.byType(OrionPrimaryButton));
    final gesture = await t.startGesture(center);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final frame = buttonFrame(t);
    expect(frame.transform!.getTranslation().y, 4);
    final decoration = frame.decoration! as BoxDecoration;
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', orionPrimaryLip)
            .having((s) => s.offset, 'offset', const Offset(0, 1)),
      ),
    );

    await gesture.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(buttonFrame(t).transform!.getTranslation().y, 0);
  });

  testWidgets('press snaps when animations are disabled', (t) async {
    await t.pumpWidget(host(onPressed: () {}, disableAnimations: true));
    final center = t.getCenter(find.byType(OrionPrimaryButton));
    final gesture = await t.startGesture(center);
    await t.pump();
    expect(buttonFrame(t).transform!.getTranslation().y, 4);
    await gesture.up();
    await t.pump();
    expect(buttonFrame(t).transform!.getTranslation().y, 0);
  });

  testWidgets('a keyboard press sinks the button and releasing fires it', (
    t,
  ) async {
    var taps = 0;
    await t.pumpWidget(host(onPressed: () => taps++));
    Focus.of(
      t.element(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(Icon),
        ),
      ),
    ).requestFocus();
    await t.pump();

    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(
      buttonFrame(t).transform!.getTranslation().y,
      4,
      reason: 'a held keyboard press must sink the button like a pointer',
    );

    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(buttonFrame(t).transform!.getTranslation().y, 0);
    expect(taps, 1);
  });

  testWidgets('a pointer that loses its gesture releases the pressed visual '
      'without firing', (t) async {
    var taps = 0;
    await t.pumpWidget(host(onPressed: () => taps++));
    final center = t.getCenter(find.byType(OrionPrimaryButton));
    final gesture = await t.startGesture(center);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(buttonFrame(t).transform!.getTranslation().y, 4);

    await gesture.moveBy(const Offset(0, 80));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(
      buttonFrame(t).transform!.getTranslation().y,
      0,
      reason:
          'the tap is dead once the pointer leaves, so the press chrome must '
          'release while the pointer is still down',
    );

    await gesture.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(buttonFrame(t).transform!.getTranslation().y, 0);
    expect(taps, 0);
  });

  testWidgets('disabled renders the grayscale rule and cannot fire', (t) async {
    var taps = 0;
    await t.pumpWidget(host(onPressed: null));
    expect(
      find.descendant(
        of: find.byType(OrionPrimaryButton),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );
    final decoration = buttonFrame(t).decoration! as BoxDecoration;
    expect(
      decoration.boxShadow,
      contains(
        isA<BoxShadow>()
            .having((s) => s.color, 'color', orionDisabledLip)
            .having((s) => s.offset, 'offset', const Offset(0, 5)),
      ),
    );
    expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    await t.tap(find.byType(OrionPrimaryButton), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('loading shows the busy glyph and does not fire', (t) async {
    var taps = 0;
    await t.pumpWidget(host(onPressed: () => taps++, loading: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(
      t.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
      reason: 'a loading action is in flight, not tappable',
    );
    await t.tap(find.byType(OrionPrimaryButton), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('keeps button semantics and a 48dp+ target', (t) async {
    await t.pumpWidget(host(onPressed: () {}));
    expect(
      find.descendant(
        of: find.byType(OrionPrimaryButton),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.enabled == true,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Deploy'), findsOneWidget);
    expect(
      t.getSize(find.byType(OrionPrimaryButton)).height,
      greaterThanOrEqualTo(48),
    );
  });
}
