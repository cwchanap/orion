import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/enemy_overlay.dart';
import 'package:orion/game/rules/enemy_overlay_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnemyOverlayRenderer', () {
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
