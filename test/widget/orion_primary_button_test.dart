import 'package:flutter/material.dart';
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
    // One dominant action, a supporting one and the destructive one — the
    // kit's .btn.primary/.secondary/.danger set.
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
    // One frame to land the press and start the sink, a second for the
    // 90ms tween to complete.
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
    // No elapsed motion: reduced motion means the sink still applies, just
    // without a tween — the state is never ambiguous.
    await t.pump();
    expect(buttonFrame(t).transform!.getTranslation().y, 4);
    await gesture.up();
    await t.pump();
    expect(buttonFrame(t).transform!.getTranslation().y, 0);
  });

  testWidgets('disabled renders the grayscale rule and cannot fire', (t) async {
    var taps = 0;
    await t.pumpWidget(host(onPressed: null));
    // The kit's disabled rule is grayscale(1) brightness(.55) over a #222
    // lip — the same look for every variant.
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
    // The InkResponse inside TextButton owns the button flag; the variant
    // chrome sits outside it and must not swallow the role.
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
