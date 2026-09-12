import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/hold_to_salvage.dart';

void main() {
  testWidgets('reduced motion does not shorten salvage confirmation', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    var sells = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HoldToSalvage(refund: 35, onSell: () => sells++)),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('tower-sell'))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    expect(
      sells,
      0,
      reason: 'A 250 ms press must not satisfy an 800 ms salvage hold.',
    );
  });
  testWidgets(
    'short press and cancelled hold never sell; complete hold sells once',
    (tester) async {
      var sells = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HoldToSalvage(refund: 35, onSell: () => sells++),
          ),
        ),
      );
      final target = find.byKey(const ValueKey('tower-sell'));
      await tester.tap(target);
      await tester.pump();
      expect(sells, 0);
      final cancelled = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 400));
      await cancelled.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(sells, 0);
      final held = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 900));
      expect(sells, 1);
      await tester.pump(const Duration(seconds: 2));
      await held.up();
      expect(sells, 1);
    },
  );

  testWidgets('phase change cancels an in-progress salvage', (tester) async {
    var sells = 0;
    Widget host(bool enabled) => MaterialApp(
      home: Scaffold(
        body: HoldToSalvage(refund: 35, onSell: enabled ? () => sells++ : null),
      ),
    );
    await tester.pumpWidget(host(true));
    final held = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('tower-sell'))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(seconds: 1));
    await held.up();
    expect(sells, 0);
  });
}
