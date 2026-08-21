import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_command_dock.dart';

import '../support/command_deck_fixtures.dart';

Widget railHost({
  int gold = 9999,
  List<TowerType> unlockedTowerTypes = const [
    TowerType.laser,
    TowerType.rocket,
    TowerType.cryo,
    TowerType.railgun,
    TowerType.ionChain,
    TowerType.nanite,
    TowerType.gravityWell,
    TowerType.droneBay,
  ],
  ValueChanged<TowerType>? onPlaceTower,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: 375,
        height: 104,
        child: TowerBuildRail(
          phase: GamePhase.build,
          gold: gold,
          unlockedTowerTypes: unlockedTowerTypes,
          onPlaceTower: onPlaceTower ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'build rail shows every tower and preserves lock/affordability callbacks',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final placed = <TowerType>[];
        await tester.pumpWidget(
          MaterialApp(
            home: TowerBuildRail(
              phase: GamePhase.build,
              gold: 0,
              unlockedTowerTypes: const [TowerType.laser],
              onPlaceTower: placed.add,
            ),
          ),
        );

        for (final type in TowerType.values) {
          expect(
            find.byKey(ValueKey('tower-card-${type.name}')),
            findsOneWidget,
          );
        }

        await tester.tap(find.byKey(const ValueKey('tower-card-laser')));
        expect(placed, [TowerType.laser]);

        await tester.tap(find.byKey(const ValueKey('tower-card-railgun')));
        expect(placed, [TowerType.laser]);
        expect(
          find.bySemanticsLabel(RegExp(r'Railgun, locked until wave')),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('five art cards fit or peek at 375dp and the rail scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(railHost());

    final first = tester.getRect(
      find.byKey(const ValueKey('tower-card-laser')),
    );
    final fifth = tester.getRect(
      find.byKey(const ValueKey('tower-card-ionChain')),
    );
    expect(first.width, 64);
    expect(fifth.left, lessThan(375));
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('card semantics distinguish affordable and unaffordable towers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: TowerBuildRail(
            phase: GamePhase.build,
            gold: 50,
            unlockedTowerTypes: const [TowerType.laser, TowerType.rocket],
            onPlaceTower: (_) {},
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Laser, unlocked, cost 50, affordable, place on selected cell',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Rocket, unlocked, cost 80, unaffordable, place on selected cell',
          ),
        ),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('locked cards never call placement even with enough gold', (
    tester,
  ) async {
    final placed = <TowerType>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TowerBuildRail(
          phase: GamePhase.build,
          gold: 9999,
          unlockedTowerTypes: const [TowerType.laser],
          onPlaceTower: placed.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tower-card-railgun')));
    expect(placed, isEmpty);
  });

  testWidgets('active-wave phase prevents every build callback', (
    tester,
  ) async {
    final placed = <TowerType>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TowerBuildRail(
          phase: GamePhase.wave,
          gold: 9999,
          unlockedTowerTypes: TowerType.values,
          onPlaceTower: placed.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tower-card-laser')));
    await tester.tap(find.byKey(const ValueKey('tower-card-droneBay')));
    expect(placed, isEmpty);
  });

  testWidgets('idle World Map and Start Wave actions obey snapshot gating', (
    tester,
  ) async {
    var worldMapTaps = 0;
    var startWaveTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: IdleCommandBar(
          snapshot: commandDeckSnapshot(),
          onWorldMap: () => worldMapTaps += 1,
          onStartWave: () => startWaveTaps += 1,
        ),
      ),
    );

    expect(find.text('World Map'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
    await tester.tap(find.byTooltip('World Map'));
    await tester.tap(find.byTooltip('Start Wave'));
    expect((worldMapTaps, startWaveTaps), (1, 1));

    await tester.pumpWidget(
      MaterialApp(
        home: IdleCommandBar(
          snapshot: commandDeckSnapshot(phase: GamePhase.wave),
          onWorldMap: () => worldMapTaps += 1,
          onStartWave: () => startWaveTaps += 1,
        ),
      ),
    );
    await tester.tap(find.byTooltip('World Map'));
    await tester.tap(find.byTooltip('Wave 1 of 8'));
    expect((worldMapTaps, startWaveTaps), (1, 1));
  });

  testWidgets('idle bar keeps Start Now visible during the countdown', (
    tester,
  ) async {
    var startWaveTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: IdleCommandBar(
          snapshot: commandDeckSnapshot(
            autoStartEnabled: true,
            autoStartCountdownRemaining: 2.2,
          ),
          onWorldMap: () {},
          onStartWave: () => startWaveTaps += 1,
        ),
      ),
    );

    expect(find.text('Start Wave'), findsNothing);
    expect(find.text('Start Now'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Wave 1 of 8, countdown 3 seconds')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Start Now'));
    expect(startWaveTaps, 1);
  });

  testWidgets('active wave reactor exposes progress and cannot start a wave', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      var startWaveTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: IdleCommandBar(
            snapshot: commandDeckSnapshot(
              phase: GamePhase.wave,
              waveNumber: 3,
              waveTotal: 8,
            ),
            onWorldMap: () {},
            onStartWave: () => startWaveTaps += 1,
          ),
        ),
      );

      expect(find.text('3/8'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Wave 3 of 8, active')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Wave 3 of 8'));
      expect(startWaveTaps, 0);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('reduced motion sets the idle reactor transition to zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: IdleCommandBar(
            snapshot: commandDeckSnapshot(),
            onWorldMap: () {},
            onStartWave: () {},
          ),
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('idle-command-reactor-transition')),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('dock prioritizes selected tower over selected cell and idle', (
    tester,
  ) async {
    const tower = PlacedTower(
      id: 7,
      type: TowerType.laser,
      position: GridPosition(2, 3),
    );
    final callbacks = <String, VoidCallback>{
      'worldMap': () {},
      'startWave': () {},
      'placeTower': () {},
      'upgrade': () {},
      'specialize': () {},
      'targeting': () {},
      'sell': () {},
    };

    Widget dock(GameSnapshot snapshot) {
      return MaterialApp(
        home: MissionCommandDock(
          snapshot: snapshot,
          onWorldMap: callbacks['worldMap']!,
          onStartWave: callbacks['startWave']!,
          onPlaceTower: (_) => callbacks['placeTower']!(),
          onUpgrade: callbacks['upgrade']!,
          onSpecialize: (_) => callbacks['specialize']!(),
          onTargetingChanged: (_) => callbacks['targeting']!(),
          onSell: callbacks['sell']!,
        ),
      );
    }

    await tester.pumpWidget(
      dock(
        commandDeckSnapshot(
          selectedCell: const GridPosition(1, 1),
          selectedTower: tower,
          selectedTowerStats: GameBalance.towerStats(
            tower.type,
            level: tower.level,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('command-dock-tower')), findsOneWidget);

    await tester.pumpWidget(
      dock(commandDeckSnapshot(selectedCell: const GridPosition(1, 1))),
    );
    expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

    await tester.pumpWidget(dock(commandDeckSnapshot()));
    expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
  });

  testWidgets('dock transition honors reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MissionCommandDock(
            snapshot: commandDeckSnapshot(),
            onWorldMap: () {},
            onStartWave: () {},
            onPlaceTower: (_) {},
            onUpgrade: () {},
            onSpecialize: (_) {},
            onTargetingChanged: (_) {},
            onSell: () {},
          ),
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('mission-command-dock-transition')),
    );
    expect(switcher.duration, Duration.zero);
  });
}
