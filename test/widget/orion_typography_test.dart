import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

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
}
