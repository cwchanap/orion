import 'dart:ui' show Tristate;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/tower_inspector.dart';
import 'package:orion/game/ui/tower_stat_scale.dart';
import 'package:orion/game/util/format.dart';

import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

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
        theme: orionThemeData,
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
      expect(find.text('+41'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tower-upgrade')));
      await tester.tap(find.byKey(const ValueKey('tower-target-strongest')));
      await tester.ensureVisible(find.byKey(const ValueKey('tower-sell')));
      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-sell'))),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 900));
      await hold.up();
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
        theme: orionThemeData,
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
            theme: orionThemeData,
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
        theme: orionThemeData,
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
        theme: orionThemeData,
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

  testWidgets(
    'L2 inspector: dominant hero art, art-forward specialization cards',
    (tester) async {
      // Representative scene 1d state: level-2 tower with both specialization
      // choices affordable and visible.
      final tower = const PlacedTower(
        id: 7,
        type: TowerType.laser,
        position: GridPosition(2, 3),
        level: 2,
      );
      final stats = GameBalance.towerStats(tower.type, level: tower.level);
      final specializations = GameBalance.specializationsFor(tower.type);
      final chosen = <TowerSpecialization>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: orionThemeData,
          home: TowerInspector(
            snapshot: commandDeckSnapshot(
              gold: 9999,
              selectedTower: tower,
              selectedTowerStats: stats,
            ),
            onUpgrade: () {},
            onSpecialize: (specialization) => chosen.add(specialization),
            onTargetingChanged: (_) {},
            onSell: () {},
            sellRefund: 84,
          ),
        ),
      );

      // Tower art dominates the header instead of sitting inline at icon size.
      final heroArt = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('tower-inspector-hero')),
              matching: find.byType(OrionAtlasSprite),
            )
            .first,
      );
      expect(heroArt.shortestSide, greaterThanOrEqualTo(56));

      // The specialization choices surface under their own section label.
      expect(find.text('SPECIALIZE - LV 3'), findsOneWidget);

      // Each choice renders as an art-forward card with its resolved cost.
      for (final specialization in specializations) {
        final card = find.byKey(
          ValueKey('tower-specialization-${specialization.name}'),
        );
        expect(card, findsOneWidget, reason: specialization.name);
        final cardArt = tester.getSize(
          find
              .descendant(of: card, matching: find.byType(OrionAtlasSprite))
              .first,
        );
        expect(
          cardArt.shortestSide,
          greaterThanOrEqualTo(28),
          reason: specialization.name,
        );
        expect(
          find.descendant(of: card, matching: find.text(specialization.label)),
          findsOneWidget,
          reason: specialization.name,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('${stats.specializationCost}'),
          ),
          findsOneWidget,
          reason: specialization.name,
        );
      }

      // Both cards call onSpecialize independently.
      await tester.ensureVisible(
        find.byKey(
          ValueKey('tower-specialization-${specializations.first.name}'),
        ),
      );
      await tester.tap(
        find.byKey(
          ValueKey('tower-specialization-${specializations.first.name}'),
        ),
      );
      await tester.tap(
        find.byKey(
          ValueKey('tower-specialization-${specializations.last.name}'),
        ),
      );
      expect(chosen, specializations);

      // Existing gauge pipeline stays TowerStatScale-driven, restyled with
      // per-stat accents and a readable gauge height.
      final scale = TowerStatScale.forType(tower.type);
      final damageBar = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byKey(const ValueKey('tower-stat-damage')),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(damageBar.value, scale.damageFill(stats));
      expect(damageBar.color, OrionUiTheme.dark.dangerRed);
      expect(damageBar.strokeWidth, greaterThanOrEqualTo(7));
    },
  );

  testWidgets('capture scene 1d fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1d state: L2 laser with both specialization
    // choices affordable. Real Roboto so the evidence shows true metrics.
    await loadRealFonts();
    // The memo can hold a pending future from an earlier cold-cache test
    // in this process; clear it so this fixture's warmed cache is used.
    OrionArtDescriptor.resetSpriteCache();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same keys the OrionArt descriptors use) so tower art renders.
    await tester.runAsync(() async {
      await Flame.images.load(GameSpriteSheet.fileName);
      await Flame.images.load(GameTowerVarietySheet.fileName);
    });
    final tower = const PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
      level: 2,
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: orionThemeData,
          // Evidence frame: hide the debug CheckedModeBanner that would
          // otherwise stamp the top-right corner of the capture.
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: OrionUiTheme.dark.voidBlack,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TowerInspector(
                  snapshot: commandDeckSnapshot(
                    gold: 9999,
                    selectedTower: tower,
                    selectedTowerStats: GameBalance.towerStats(
                      tower.type,
                      level: tower.level,
                    ),
                    selectedTowerSpecializationStats: {
                      for (final spec in GameBalance.specializationsFor(
                        tower.type,
                      ))
                        spec: GameBalance.towerStats(
                          tower.type,
                          level: 3,
                          specialization: spec,
                        ),
                    },
                  ),
                  onUpgrade: () {},
                  onSpecialize: (_) {},
                  onTargetingChanged: (_) {},
                  onSell: () {},
                  sellRefund: 84,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1d.png'),
    );
  });

  testWidgets('inspector is surfaced with MissionSurface, a t2 tier', (
    tester,
  ) async {
    const tower = PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
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
          sellRefund: 41,
        ),
      ),
    );

    // MissionSurface is a thin deprecated adapter now, delegating to an
    // unemphasized (t2) OrionSurface internally.
    expect(
      tester.widget<OrionSurface>(find.byType(OrionSurface)).tier,
      OrionSurfaceTier.t3,
    );
    expect(find.byKey(const ValueKey('tower-inspector')), findsOneWidget);
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
        theme: orionThemeData,
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
    expect(inspector.height, lessThanOrEqualTo(600));
    expect(find.byType(Scrollable), findsWidgets);

    for (final mode in TowerTargetingMode.values) {
      final chip = tester.getRect(
        find.byKey(ValueKey('tower-target-${mode.name}')),
      );
      expect(chip.width, greaterThanOrEqualTo(48), reason: mode.name);
      expect(chip.height, greaterThanOrEqualTo(48), reason: mode.name);
    }
  });
  group('progression previews', () {
    Future<void> pumpInspector(
      WidgetTester tester, {
      required PlacedTower tower,
      required TowerStats stats,
      TowerStats? upgradeStats,
      Map<TowerSpecialization, TowerStats> specializationStats = const {},
      int gold = 9999,
      VoidCallback? onUpgrade,
      ValueChanged<TowerSpecialization>? onSpecialize,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: orionThemeData,
          home: TowerInspector(
            snapshot: commandDeckSnapshot(
              gold: gold,
              selectedTower: tower,
              selectedTowerStats: stats,
              selectedTowerUpgradeStats: upgradeStats,
              selectedTowerSpecializationStats: specializationStats,
            ),
            onUpgrade: onUpgrade ?? () {},
            onSpecialize: onSpecialize ?? (_) {},
            onTargetingChanged: (_) {},
            onSell: () {},
            sellRefund: 41,
          ),
        ),
      );
    }

    Finder inPreview(String key, String text) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.textContaining(text, findRichText: true),
    );

    testWidgets('level 1 shows changed stats beside the upgrade action', (
      tester,
    ) async {
      const tower = PlacedTower(
        id: 7,
        type: TowerType.laser,
        position: GridPosition(2, 3),
      );
      final current = GameBalance.towerStats(TowerType.laser, level: 1);
      final next = GameBalance.towerStats(TowerType.laser, level: 2);
      var upgrades = 0;
      await pumpInspector(
        tester,
        tower: tower,
        stats: current,
        upgradeStats: next,
        onUpgrade: () => upgrades++,
      );

      expect(find.text('UPGRADE - LV 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tower-upgrade-preview')),
        findsOneWidget,
      );
      expect(inPreview('tower-upgrade-preview', 'DAMAGE'), findsOneWidget);
      expect(inPreview('tower-upgrade-preview', '12 → 18'), findsOneWidget);
      expect(
        inPreview('tower-upgrade-preview', '0.42s → 0.34s'),
        findsOneWidget,
      );
      expect(inPreview('tower-upgrade-preview', '145 → 160'), findsOneWidget);
      expect(find.text('Upgrade ${current.upgradeCost}'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel(
            'Upgrade preview. Damage 12 to 18. '
            'Fire 0.42 seconds to 0.34 seconds. Range 145 to 160',
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }

      await tester.ensureVisible(find.byKey(const ValueKey('tower-upgrade')));
      await tester.tap(find.byKey(const ValueKey('tower-upgrade')));
      expect(upgrades, 1);
    });

    testWidgets('upgrade preview includes tower-specific mechanics', (
      tester,
    ) async {
      const expected = {
        TowerType.gravityWell: ['FIELD 72 → 86', 'FIELD TIME 2s → 2.5s'],
        TowerType.droneBay: [
          'DRONES 2 → 3',
          'MAX DRONES 4 → 6',
          'DRONE LIFE 4s → 4.5s',
          'DRONE FIRE 0.65s → 0.58s',
        ],
        TowerType.cryo: ['SLOW 1.4s → 2s', 'SLOW POWER 38% → 52%'],
        TowerType.ionChain: ['CHAIN RANGE 85 → 95', 'CHAIN DMG 72% → 76%'],
        TowerType.nanite: ['CORRODE TIME 2.5s → 3.2s', 'SHRED 12% → 18%'],
      };
      for (final MapEntry(key: type, value: rows) in expected.entries) {
        await pumpInspector(
          tester,
          tower: PlacedTower(
            id: 7,
            type: type,
            position: const GridPosition(2, 3),
          ),
          stats: GameBalance.towerStats(type, level: 1),
          upgradeStats: GameBalance.towerStats(type, level: 2),
        );
        for (final row in rows) {
          expect(
            inPreview('tower-upgrade-preview', row),
            findsOneWidget,
            reason: '${type.name}: $row',
          );
        }
      }

      final semantics = tester.ensureSemantics();
      try {
        // The last pumped tower is the Nanite one.
        expect(
          find.bySemanticsLabel(
            RegExp(
              r'^Upgrade preview\. .*Corrode time 2\.5 seconds to '
              r'3\.2 seconds\. Shred 12% to 18%$',
            ),
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('specialization cards keep the four inspector metrics', (
      tester,
    ) async {
      const tower = PlacedTower(
        id: 7,
        type: TowerType.droneBay,
        position: GridPosition(2, 3),
        level: 2,
      );
      await pumpInspector(
        tester,
        tower: tower,
        stats: GameBalance.towerStats(TowerType.droneBay, level: 2),
        specializationStats: {
          for (final spec in GameBalance.specializationsFor(TowerType.droneBay))
            spec: GameBalance.towerStats(
              TowerType.droneBay,
              level: 3,
              specialization: spec,
            ),
        },
      );

      expect(
        inPreview('tower-specialization-preview-hunterBay', 'DRONE DMG'),
        findsOneWidget,
      );
      expect(
        inPreview('tower-specialization-preview-hunterBay', 'DRONES'),
        findsNothing,
      );
    });

    testWidgets('unchanged values are hidden from the comparison', (
      tester,
    ) async {
      const tower = PlacedTower(
        id: 7,
        type: TowerType.cryo,
        position: GridPosition(2, 3),
      );
      final current = GameBalance.towerStats(TowerType.cryo, level: 1);
      await pumpInspector(
        tester,
        tower: tower,
        stats: current,
        upgradeStats: current.copyWith(damage: current.damage + 3),
      );

      expect(inPreview('tower-upgrade-preview', 'DAMAGE'), findsOneWidget);
      for (final label in ['FIRE', 'RANGE', 'SLOW']) {
        expect(inPreview('tower-upgrade-preview', label), findsNothing);
      }
    });

    testWidgets('missing upgrade preview leaves the action unchanged', (
      tester,
    ) async {
      const tower = PlacedTower(
        id: 7,
        type: TowerType.laser,
        position: GridPosition(2, 3),
      );
      final current = GameBalance.towerStats(TowerType.laser, level: 1);
      await pumpInspector(tester, tower: tower, stats: current);

      expect(find.byKey(const ValueKey('tower-upgrade-preview')), findsNothing);
      expect(find.text('Upgrade ${current.upgradeCost}'), findsOneWidget);
    });

    testWidgets('specialization cards explain role and payoff', (tester) async {
      const tower = PlacedTower(
        id: 7,
        type: TowerType.cryo,
        position: GridPosition(2, 3),
        level: 2,
      );
      final current = GameBalance.towerStats(TowerType.cryo, level: 2);
      final candidates = {
        for (final spec in GameBalance.specializationsFor(TowerType.cryo))
          spec: GameBalance.towerStats(
            TowerType.cryo,
            level: 3,
            specialization: spec,
          ),
      };
      final chosen = <TowerSpecialization>[];
      await pumpInspector(
        tester,
        tower: tower,
        stats: current,
        specializationStats: candidates,
        onSpecialize: chosen.add,
      );

      for (final spec in candidates.keys) {
        final card = find.byKey(ValueKey('tower-specialization-${spec.name}'));
        expect(
          find.descendant(of: card, matching: find.text(spec.role)),
          findsOneWidget,
          reason: spec.name,
        );
        expect(
          find.byKey(ValueKey('tower-specialization-preview-${spec.name}')),
          findsOneWidget,
          reason: spec.name,
        );
      }

      final deepFreeze = candidates[TowerSpecialization.deepFreeze]!;
      expect(
        inPreview(
          'tower-specialization-preview-deepFreeze',
          '${number(current.slowDuration)}s → '
              '${number(deepFreeze.slowDuration)}s',
        ),
        findsOneWidget,
      );

      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel(
            RegExp(
              '^Deep Freeze ${current.specializationCost}\\. '
              '${RegExp.escape(TowerSpecialization.deepFreeze.role)} '
              'Fire ',
            ),
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }

      await tester.ensureVisible(
        find.byKey(const ValueKey('tower-specialization-frostbite')),
      );
      await tester.tap(
        find.byKey(const ValueKey('tower-specialization-frostbite')),
      );
      expect(chosen, [TowerSpecialization.frostbite]);
    });

    testWidgets('missing specialization preview keeps the role sentence', (
      tester,
    ) async {
      const tower = PlacedTower(
        id: 7,
        type: TowerType.laser,
        position: GridPosition(2, 3),
        level: 2,
      );
      await pumpInspector(
        tester,
        tower: tower,
        stats: GameBalance.towerStats(TowerType.laser, level: 2),
      );

      for (final spec in GameBalance.specializationsFor(TowerType.laser)) {
        expect(find.text(spec.role), findsOneWidget, reason: spec.name);
        expect(
          find.byKey(ValueKey('tower-specialization-preview-${spec.name}')),
          findsNothing,
        );
      }
    });

    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets(
        'every tower type fits at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          for (final type in TowerType.values) {
            for (final level in const [1, 2]) {
              final tower = PlacedTower(
                id: 7,
                type: type,
                position: const GridPosition(2, 3),
                level: level,
              );
              await pumpInspector(
                tester,
                tower: tower,
                stats: GameBalance.towerStats(type, level: level),
                upgradeStats: level == 1
                    ? GameBalance.towerStats(type, level: 2)
                    : null,
                specializationStats: level == 2
                    ? {
                        for (final spec in GameBalance.specializationsFor(type))
                          spec: GameBalance.towerStats(
                            type,
                            level: 3,
                            specialization: spec,
                          ),
                      }
                    : const {},
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${type.name} L$level',
              );
            }
          }
        },
      );
    }
  });
}
