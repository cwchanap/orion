import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/tower_inspector.dart';
import 'package:orion/game/util/format.dart';

import '../support/command_deck_fixtures.dart';

void main() {
  testWidgets('inspector uses resolved costs and invokes public callbacks', (
    tester,
  ) async {
    const tower = PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
    );
    final resolved = GameBalance.towerStats(TowerType.laser, level: 1);
    var upgrades = 0;
    var sells = 0;
    TowerTargetingMode? targeting;

    await tester.pumpWidget(
      MaterialApp(
        home: TowerInspector(
          snapshot: commandDeckSnapshot(
            gold: 9999,
            selectedTower: tower,
            selectedTowerStats: resolved,
          ),
          onUpgrade: () => upgrades++,
          onSpecialize: (_) {},
          onTargetingChanged: (mode) => targeting = mode,
          onSell: () => sells++,
          sellRefund: 41,
        ),
      ),
    );

    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(
        find.bySemanticsLabel('Damage ${number(resolved.damage)}'),
        findsOneWidget,
      );
      expect(find.text('Upgrade ${resolved.upgradeCost}'), findsOneWidget);
      expect(find.text('Sell 41'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tower-upgrade')));
      await tester.tap(find.byKey(const ValueKey('tower-target-strongest')));
      await tester.ensureVisible(find.byKey(const ValueKey('tower-sell')));
      await tester.tap(find.byKey(const ValueKey('tower-sell')));
      expect(upgrades, 1);
      expect(targeting, TowerTargetingMode.strongest);
      expect(sells, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('inspector renders every resolved stat and secondary value', (
    tester,
  ) async {
    final stats = GameBalance.towerStats(
      TowerType.cryo,
      level: 1,
    ).copyWith(damage: 9.5, fireInterval: 0.57, range: 151, slowDuration: 2.7);
    await tester.pumpWidget(
      MaterialApp(
        home: TowerInspector(
          snapshot: commandDeckSnapshot(
            selectedTower: const PlacedTower(
              id: 7,
              type: TowerType.cryo,
              position: GridPosition(2, 3),
            ),
            selectedTowerStats: stats,
          ),
          onUpgrade: () {},
          onSpecialize: (_) {},
          onTargetingChanged: (_) {},
          onSell: () {},
          sellRefund: 41,
        ),
      ),
    );

    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(
        find.bySemanticsLabel('Damage ${number(stats.damage)}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Fire ${cadence(stats.fireInterval)}s'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Range ${number(stats.range)}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Slow ${number(stats.slowDuration)}s'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('active-wave selection disables every mutation action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final tower in [
        const PlacedTower(
          id: 7,
          type: TowerType.laser,
          position: GridPosition(2, 3),
        ),
        const PlacedTower(
          id: 8,
          type: TowerType.laser,
          position: GridPosition(2, 3),
          level: 2,
        ),
      ]) {
        var upgrades = 0;
        var specializations = 0;
        var targets = 0;
        var sells = 0;
        final stats = GameBalance.towerStats(tower.type, level: tower.level);
        await tester.pumpWidget(
          MaterialApp(
            home: TowerInspector(
              snapshot: commandDeckSnapshot(
                phase: GamePhase.wave,
                gold: 9999,
                selectedTower: tower,
                selectedTowerStats: stats,
              ),
              onUpgrade: () => upgrades++,
              onSpecialize: (_) => specializations++,
              onTargetingChanged: (_) => targets++,
              onSell: () => sells++,
              sellRefund: 41,
            ),
          ),
        );

        final actionKeys = <String>[
          if (tower.canUpgrade) 'tower-upgrade',
          if (tower.canSpecialize)
            for (final specialization in GameBalance.specializationsFor(
              tower.type,
            ))
              'tower-specialization-${specialization.name}',
          'tower-target-strongest',
          'tower-sell',
        ];
        for (final key in actionKeys) {
          final action = find.byKey(ValueKey(key));
          expect(action, findsOneWidget, reason: key);
          final flags = tester
              .getSemantics(action)
              .getSemanticsData()
              .flagsCollection;
          expect(flags.isEnabled, Tristate.isFalse, reason: key);
          await tester.ensureVisible(action);
          await tester.tap(action);
        }

        expect((upgrades, specializations, targets, sells), (0, 0, 0, 0));
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('null resolved stats omit bars and disable progression', (
    tester,
  ) async {
    final tower = const PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TowerInspector(
          snapshot: commandDeckSnapshot(
            selectedTower: tower,
            selectedTowerStats: null,
          ),
          onUpgrade: () {},
          onSpecialize: (_) {},
          onTargetingChanged: (_) {},
          onSell: () {},
          sellRefund: 41,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('tower-stat-damage')), findsNothing);
    expect(find.byKey(const ValueKey('tower-stat-fire')), findsNothing);
    expect(find.byKey(const ValueKey('tower-stat-range')), findsNothing);
    final semantics = tester.ensureSemantics();
    try {
      final flags = tester
          .getSemantics(find.byKey(const ValueKey('tower-upgrade')))
          .getSemanticsData()
          .flagsCollection;
      expect(flags.isEnabled, Tristate.isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('max-level inspector shows Max instead of progression actions', (
    tester,
  ) async {
    final tower = const PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
      level: 3,
      specialization: TowerSpecialization.pulseLaser,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TowerInspector(
          snapshot: commandDeckSnapshot(
            selectedTower: tower,
            selectedTowerStats: GameBalance.towerStats(
              tower.type,
              level: tower.level,
              specialization: tower.specialization,
            ),
          ),
          onUpgrade: () {},
          onSpecialize: (_) {},
          onTargetingChanged: (_) {},
          onSell: () {},
          sellRefund: 41,
        ),
      ),
    );

    expect(find.text('Max'), findsOneWidget);
    expect(find.byKey(const ValueKey('tower-upgrade')), findsNothing);
    for (final specialization in GameBalance.specializationsFor(tower.type)) {
      expect(
        find.byKey(ValueKey('tower-specialization-${specialization.name}')),
        findsNothing,
      );
    }
  });

  testWidgets('inspector caps height and scrolls internally on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tower = const PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
      level: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TowerInspector(
          snapshot: commandDeckSnapshot(
            selectedTower: tower,
            selectedTowerStats: GameBalance.towerStats(
              tower.type,
              level: tower.level,
            ),
          ),
          onUpgrade: () {},
          onSpecialize: (_) {},
          onTargetingChanged: (_) {},
          onSell: () {},
          sellRefund: 84,
        ),
      ),
    );

    final inspector = tester.getRect(
      find.byKey(const ValueKey('tower-inspector')),
    );
    expect(inspector.height, lessThanOrEqualTo(210));
    expect(find.byType(Scrollable), findsWidgets);

    for (final mode in TowerTargetingMode.values) {
      final chip = tester.getRect(
        find.byKey(ValueKey('tower-target-${mode.name}')),
      );
      expect(chip.width, greaterThanOrEqualTo(48), reason: mode.name);
      expect(chip.height, greaterThanOrEqualTo(48), reason: mode.name);
    }
  });
}
