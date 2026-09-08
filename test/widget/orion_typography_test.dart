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

  test('motion durations match the design system sheet', () {
    expect(orionPressDuration, const Duration(milliseconds: 90));
    expect(orionSheetDuration, const Duration(milliseconds: 220));
    expect(orionLaneFlowDuration, const Duration(milliseconds: 1100));
    expect(orionHullPulseDuration, const Duration(milliseconds: 2400));
    expect(orionIdleBobDuration, const Duration(milliseconds: 1600));
  });

  test('readout is Oxanium at variable weight 800', () {
    final s = OrionTypography.readout(color: const Color(0xFFFFC857));
    expect(s.fontFamily, 'Oxanium');
    expect(s.fontVariations, contains(const FontVariation('wght', 800)));
    expect(s.fontSize, 24);
    expect(s.shadows, isNotEmpty);
  });

  test('title is tracked caps-oriented Oxanium', () {
    final s = OrionTypography.title(color: const Color(0xFFF4F8FB));
    expect(s.fontFamily, 'Oxanium');
    expect(s.fontSize, 15);
    expect(s.letterSpacing, greaterThan(0));
  });

  test('microLabel is Chakra Petch 700 with design tracking', () {
    final s = OrionTypography.microLabel();
    expect(s.fontFamily, 'ChakraPetch');
    expect(s.fontWeight, FontWeight.w700);
    expect(s.fontSize, inInclusiveRange(7, 9));
    expect(s.letterSpacing! / s.fontSize!, inInclusiveRange(0.14, 0.24));
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
    expect(denom.style!.fontSize, lessThan(value.style!.fontSize!));
    expect(denom.style!.color, isNot(value.style!.color));
  });
}
