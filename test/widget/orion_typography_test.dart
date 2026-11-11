import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_typography.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

import '../support/real_fonts.dart';

void main() {
  test('sheetBlack sits between voidBlack and hullBlack', () {
    const t = OrionUiTheme.dark;
    expect(t.sheetBlack, const Color(0xFF080D13));
    expect(t.sheetBlack.r, greaterThan(t.voidBlack.r));
    expect(t.sheetBlack.r, lessThan(t.hullBlack.r));
  });

  test('sheetBlack survives copyWith and lerp', () {
    const t = OrionUiTheme.dark;
    expect(t.copyWith().sheetBlack, t.sheetBlack);
    expect(t.lerp(t, 0.5).sheetBlack, t.sheetBlack);
  });

  test('the shared text shadow lives in the theme tokens', () {
    expect(
      OrionTypography.shadow,
      const Shadow(
        color: Color(0xE605080D),
        offset: Offset(0, 1),
        blurRadius: 4,
      ),
    );
    expect(OrionTypography.shadow, orionTextShadow);
  });

  test(
    'readout is Oxanium at variable weight 800 with Chakra Petch fallback',
    () {
      final s = OrionTypography.readout(color: const Color(0xFFFFC857));
      expect(s.fontFamily, 'Oxanium');
      expect(s.fontVariations, contains(const FontVariation('wght', 800)));
      expect(s.fontSize, 24);
      expect(s.shadows, isNotEmpty);
      expect(s.fontFamilyFallback, ['ChakraPetch']);
    },
  );

  test('title is tracked caps-oriented Oxanium with Chakra Petch fallback', () {
    final s = OrionTypography.title(color: const Color(0xFFF4F8FB));
    expect(s.fontFamily, 'Oxanium');
    expect(s.fontSize, 15);
    expect(s.letterSpacing, greaterThan(0));
    expect(s.fontFamilyFallback, ['ChakraPetch']);
  });

  test('microLabel defaults to the 10px floor with design tracking', () {
    final s = OrionTypography.microLabel();
    expect(s.fontFamily, 'ChakraPetch');
    expect(s.fontWeight, FontWeight.w700);
    expect(s.fontSize, 10);
    expect(s.letterSpacing! / s.fontSize!, inInclusiveRange(0.08, 0.12));
  });

  test('microLabel asserts explicit sizes stay at or above the floor', () {
    expect(() => OrionTypography.microLabel(size: 9), throwsA(anything));
    expect(() => OrionTypography.microLabel(size: 8), throwsA(anything));
    expect(() => OrionTypography.microLabel(size: 9.9), throwsA(anything));
    expect(OrionTypography.microLabel(size: 10).fontSize, 10);
  });

  test('OrionText.micro shares the floor', () {
    const label = OrionText.micro('x');
    expect(label.size, 10);
    const explicit = OrionText.micro('x', size: 11);
    expect(explicit.size, 11);
  });

  test('microLabel refuses textPrimary', () {
    expect(
      () => OrionTypography.microLabel(color: OrionUiTheme.dark.textPrimary),
      throwsArgumentError,
    );
  });

  testWidgets('OrionReadout renders a muted, smaller denominator', (t) async {
    await loadRealFonts();
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrionReadout(
            value: '03',
            denominator: '12',
            color: Color(0xFF46E6FF),
          ),
        ),
      ),
    );
    final value = t.widget<Text>(find.text('03'));
    final denom = t.widget<Text>(find.text('/12'));
    // The denominator is subordinate but still legible: 0.45 of the value's
    // resolved size, not the illegible 0.45 the sheet's earlier ratio gave
    // at in-use sizes.
    expect(
      denom.style!.fontSize,
      closeTo(value.style!.fontSize! * 0.45, 0.001),
    );
    expect(denom.style!.color, isNot(value.style!.color));
  });

  testWidgets('readout renders the U+2192 arrow through the Chakra Petch '
      'fallback', (t) async {
    await loadRealFonts();

    double widthOf(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: '\u2192', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    final readoutArrow = widthOf(
      OrionTypography.readout(size: 24, color: const Color(0xFFF4F8FB)),
    );
    final chakraArrow = widthOf(
      const TextStyle(
        fontFamily: 'ChakraPetch',
        fontWeight: FontWeight.w700,
        fontSize: 24,
        height: 1,
      ),
    );
    expect(chakraArrow, greaterThan(0));
    expect(readoutArrow, closeTo(chakraArrow, 0.01));

    final titleArrow = widthOf(
      OrionTypography.title(size: 20, color: const Color(0xFFF4F8FB)),
    );
    final chakraTitleArrow = widthOf(
      const TextStyle(
        fontFamily: 'ChakraPetch',
        fontWeight: FontWeight.w700,
        fontSize: 20,
        height: 1,
        letterSpacing: 20 * 0.08,
      ),
    );
    expect(titleArrow, closeTo(chakraTitleArrow, 0.01));
  });
}
