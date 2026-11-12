import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/enemy_overlay.dart';
import 'package:orion/game/rules/enemy_overlay_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnemyOverlayRenderer', () {
    test('boss name remains legible when the battlefield is scaled down', () {
      final state = EnemyOverlayState(
        shouldRender: true,
        isExpanded: false,
        isSlowed: false,
        isCorroded: false,
        healthRatio: 1,
        shieldRatio: 0,
        showHealthBar: true,
        showShieldBar: false,
        badges: const [],
      );
      final canvas = _ScaledCanvas(0.5);
      EnemyOverlayRenderer().render(
        canvas,
        state: state,
        radius: 20,
        name: 'Relay Breaker',
      );
      expect(
        canvas.paragraphHeight! * 0.5,
        greaterThanOrEqualTo(12),
        reason: 'the name should remain at least 12 logical pixels high',
      );
    });

    test('boss bars sit close above the sprite without covering it', () {
      final state = EnemyOverlayState(
        shouldRender: true,
        isExpanded: false,
        isSlowed: false,
        isCorroded: false,
        healthRatio: 0.5,
        shieldRatio: 0.25,
        showHealthBar: true,
        showShieldBar: true,
        badges: const [],
      );
      final canvas = TestRecordingCanvas();
      EnemyOverlayRenderer().render(canvas, state: state, radius: 20);
      final bars = canvas.invocations
          .where((call) => call.invocation.memberName == #drawRRect)
          .map((call) => call.invocation.positionalArguments.first as RRect)
          .toList();
      final shieldBottom = bars.last.outerRect.bottom;
      const spriteTop = 20 - 1.75 * 20;
      expect(shieldBottom, lessThanOrEqualTo(spriteTop));
      expect(
        shieldBottom,
        greaterThanOrEqualTo(spriteTop - 12),
        reason: 'the bars must stay visually attached to the boss',
      );
    });

    test('render paints status rings for slowed and corroded states', () {
      final state = EnemyOverlayState(
        shouldRender: true,
        isExpanded: false,
        isSlowed: true,
        isCorroded: true,
        healthRatio: 0.5,
        shieldRatio: 0.25,
        showHealthBar: true,
        showShieldBar: true,
        badges: [EnemyOverlayBadge.corroded, EnemyOverlayBadge.slowed],
      );
      const radius = 20.0;
      final layout = EnemyOverlayLayout.compute(state, radius);
      final canvas = TestRecordingCanvas();

      EnemyOverlayRenderer().render(canvas, state: state, radius: radius);

      // The rings must actually be painted at the layout's radii — badge
      // fallback circles use different radii, so these two matches pin the
      // status-ring draw calls specifically.
      final drawnCircleRadii = canvas.invocations
          .where((call) => call.invocation.memberName == #drawCircle)
          .map((call) => call.invocation.positionalArguments[1] as double)
          .toList();
      expect(drawnCircleRadii, contains(layout.corrodedRingRadius));
      expect(drawnCircleRadii, contains(layout.slowedRingRadius));
    });

    test('render paints no status rings without status flags', () {
      final state = EnemyOverlayState(
        shouldRender: true,
        isExpanded: false,
        isSlowed: false,
        isCorroded: false,
        healthRatio: 0.5,
        shieldRatio: 0,
        showHealthBar: true,
        showShieldBar: false,
        badges: const [],
      );
      final canvas = TestRecordingCanvas();

      EnemyOverlayRenderer().render(canvas, state: state, radius: 20);

      // Bars still draw, but no circle-based element (rings or badges)
      // may appear.
      expect(
        canvas.invocations.where(
          (call) => call.invocation.memberName == #drawCircle,
        ),
        isEmpty,
      );
    });
  });
}

class _ScaledCanvas extends TestRecordingCanvas {
  _ScaledCanvas(this.boardScale);

  final double boardScale;
  double? paragraphHeight;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphHeight = paragraph.height;
    super.drawParagraph(paragraph, offset);
  }

  @override
  Float64List getTransform() => Float64List.fromList([
    boardScale,
    0,
    0,
    0,
    0,
    boardScale,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);
}
