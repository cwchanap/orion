import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/enemy_overlay.dart';
import 'package:orion/game/rules/enemy_overlay_state.dart';

void main() {
  group('EnemyOverlayRenderer', () {
    test('render draws status rings for slowed and corroded states', () {
      final state = EnemyOverlayState(
        shouldRender: true,
        isExpanded: false,
        healthRatio: 0.5,
        shieldRatio: 0.25,
        showHealthBar: true,
        showShieldBar: true,
        badges: [EnemyOverlayBadge.corroded, EnemyOverlayBadge.slowed],
      );
      final renderer = EnemyOverlayRenderer();

      expect(
        () => _renderOverlayToCanvas(
          renderer: renderer,
          state: state,
          radius: 20,
        ),
        returnsNormally,
      );
    });
  });
}

void _renderOverlayToCanvas({
  required EnemyOverlayRenderer renderer,
  required EnemyOverlayState state,
  required double radius,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(60, 80);
  renderer.render(canvas, state: state, radius: radius);
  recorder.endRecording().dispose();
}
