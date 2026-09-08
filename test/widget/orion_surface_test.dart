import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/mission_surface.dart';
import 'package:orion/game/ui/orion_surface.dart';

void main() {
  test('exactly four tiers exist, with the sheet blur values', () {
    expect(OrionSurfaceTier.values.map((t) => t.blur).toList(), [
      7.0,
      6.0,
      12.0,
      14.0,
    ]);
  });

  testWidgets('every tier renders exactly one BackdropFilter', (t) async {
    for (final tier in OrionSurfaceTier.values) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrionSurface(tier: tier, child: const Text('x')),
          ),
        ),
      );
      expect(
        find.byType(BackdropFilter),
        findsOneWidget,
        reason: 'tier $tier must blur its container, not its children',
      );
    }
  });

  testWidgets('no tier is fully opaque', (t) async {
    for (final tier in OrionSurfaceTier.values) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrionSurface(tier: tier, child: const Text('x')),
          ),
        ),
      );
      final box = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(OrionSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      final colors = decoration.gradient is LinearGradient
          ? (decoration.gradient! as LinearGradient).colors
          : [decoration.color!];
      for (final c in colors) {
        expect(
          c.a,
          lessThan(1.0),
          reason: 'tier $tier: the art paid for is the art you see',
        );
      }
    }
  });

  testWidgets('MissionSurface delegates to a tiered OrionSurface', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MissionSurface(child: Text('x'))),
      ),
    );
    expect(find.byType(OrionSurface), findsOneWidget);
    expect(
      t.widget<OrionSurface>(find.byType(OrionSurface)).tier,
      OrionSurfaceTier.t2,
    );
  });

  testWidgets('an emphasized MissionSurface is a t3 sheet', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MissionSurface(emphasized: true, child: Text('x')),
        ),
      ),
    );
    expect(
      t.widget<OrionSurface>(find.byType(OrionSurface)).tier,
      OrionSurfaceTier.t3,
    );
  });
}
