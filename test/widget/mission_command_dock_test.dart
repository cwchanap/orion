import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_surface.dart';

import '../support/command_deck_fixtures.dart';

Widget railHost({
  int gold = 9999,
  List<TowerType>? unlockedTowerTypes,
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
          unlockedTowerTypes: unlockedTowerTypes ?? TowerType.values,
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

  testWidgets('rail and tower cards use MissionSurface, not CommandFrame', (
    tester,
  ) async {
    await tester.pumpWidget(railHost());

    expect(find.byType(CommandFrame), findsNothing);
    // The rail shell surfaces the whole strip...
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('tower-card-laser')),
        matching: find.byType(MissionSurface),
      ),
      findsOneWidget,
    );
    // ...and each card is itself surfaced.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tower-card-laser')),
        matching: find.byType(MissionSurface),
      ),
      findsOneWidget,
    );
  });

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
      find.byKey(ValueKey('tower-card-${TowerType.values[4].name}')),
    );
    expect(first.width, 64);
    expect(fifth.left, lessThan(375));
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('build rail cards grow with text scale up to 1.3x', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: railHost(),
      ),
    );

    // The scaler is capped at 1.3 and the card dimensions follow it.
    final first = tester.getRect(
      find.byKey(const ValueKey('tower-card-laser')),
    );
    expect(first.width, closeTo(64 * 1.3, 0.01));
    expect(find.byType(TowerBuildRail), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('idle dock hosts pacing controls and the primary action', (
    tester,
  ) async {
    var pauseTaps = 0;
    var autoTaps = 0;
    var startWaveTaps = 0;
    double? speed;
    await tester.pumpWidget(
      MaterialApp(
        home: MissionCommandDock(
          snapshot: commandDeckSnapshot(),
          onTogglePause: () => pauseTaps += 1,
          onSpeedSelected: (value) => speed = value,
          onToggleAutoStart: () => autoTaps += 1,
          onStartWave: () => startWaveTaps += 1,
          onPlaceTower: (_) {},
          onUpgrade: () {},
          onSpecialize: (_) {},
          onTargetingChanged: (_) {},
          onSell: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
    // World Map left the dock contract; the chrome layer owns it now.
    expect(find.text('World Map'), findsNothing);

    await tester.tap(find.text('2x'));
    await tester.tap(find.byTooltip('Auto-start waves'));
    await tester.tap(find.byTooltip('Start Wave'));
    // Pause is gated off during a plain build phase (no countdown, not
    // paused); the paused variant below proves the callback wiring.
    await tester.tap(find.byTooltip('Pause'));
    expect((pauseTaps, speed, autoTaps, startWaveTaps), (0, 2.0, 1, 1));
  });

  testWidgets('idle dock shows Resume while paused', (tester) async {
    var pauseTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: IdleCommandBar(
          snapshot: commandDeckSnapshot(isPaused: true),
          onTogglePause: () => pauseTaps += 1,
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
          onStartWave: () {},
        ),
      ),
    );

    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byTooltip('Resume'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume'));
    expect(pauseTaps, 1);
  });

  testWidgets('World Map action obeys its build-phase gate', (tester) async {
    var mapTaps = 0;
    Widget host({required bool enabled}) => MaterialApp(
      home: Center(
        child: WorldMapAction(enabled: enabled, onWorldMap: () => mapTaps += 1),
      ),
    );

    await tester.pumpWidget(host(enabled: true));
    expect(find.text('World Map'), findsOneWidget);
    await tester.tap(find.byTooltip('World Map'));
    expect(mapTaps, 1);

    await tester.pumpWidget(host(enabled: false));
    await tester.tap(find.byTooltip('World Map'));
    expect(mapTaps, 1);
  });

  testWidgets('idle dock keeps Start Now visible during the countdown', (
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
          onTogglePause: () {},
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
          onStartWave: () => startWaveTaps += 1,
        ),
      ),
    );

    expect(find.text('Start Wave'), findsNothing);
    expect(find.text('Start Now'), findsOneWidget);
    final handle = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('Auto-start waves, 3 seconds'),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
    await tester.tap(find.byTooltip('Start Now'));
    expect(startWaveTaps, 1);
  });

  testWidgets('active wave reactor exposes progress and cannot start a wave', (
    tester,
  ) async {
    var startWaveTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: IdleCommandBar(
          snapshot: commandDeckSnapshot(
            phase: GamePhase.wave,
            waveNumber: 3,
            waveTotal: 8,
          ),
          onTogglePause: () {},
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
          onStartWave: () => startWaveTaps += 1,
        ),
      ),
    );

    expect(find.text('3/8'), findsOneWidget);
    await tester.tap(find.byTooltip('Wave 3 of 8'));
    expect(startWaveTaps, 0);
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
            onTogglePause: () {},
            onSpeedSelected: (_) {},
            onToggleAutoStart: () {},
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

  testWidgets(
    'primary and World Map actions keep 48dp targets and invoke once',
    (tester) async {
      var startWaveTaps = 0;
      var mapTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IdleCommandBar(
                snapshot: commandDeckSnapshot(),
                onTogglePause: () {},
                onSpeedSelected: (_) {},
                onToggleAutoStart: () {},
                onStartWave: () => startWaveTaps += 1,
              ),
              WorldMapAction(enabled: true, onWorldMap: () => mapTaps += 1),
            ],
          ),
        ),
      );

      final startRect = tester.getRect(find.byTooltip('Start Wave'));
      expect(startRect.width, greaterThanOrEqualTo(48));
      expect(startRect.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byTooltip('Start Wave'));
      expect(startWaveTaps, 1);

      final mapRect = tester.getRect(find.byTooltip('World Map'));
      expect(mapRect.width, greaterThanOrEqualTo(48));
      expect(mapRect.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byTooltip('World Map'));
      expect(mapTaps, 1);
    },
  );

  testWidgets('primary and World Map semantics tap fires each callback once', (
    tester,
  ) async {
    var startWaveTaps = 0;
    var mapTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IdleCommandBar(
              snapshot: commandDeckSnapshot(),
              onTogglePause: () {},
              onSpeedSelected: (_) {},
              onToggleAutoStart: () {},
              onStartWave: () => startWaveTaps += 1,
            ),
            WorldMapAction(enabled: true, onWorldMap: () => mapTaps += 1),
          ],
        ),
      ),
    );

    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      final startData = tester.getSemantics(
        find.bySemanticsLabel('Start Wave'),
      );
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        startData.id,
        SemanticsAction.tap,
      );
      expect(startWaveTaps, 1);

      final mapData = tester.getSemantics(find.bySemanticsLabel('World Map'));
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        mapData.id,
        SemanticsAction.tap,
      );
      expect(mapTaps, 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'disabled primary and World Map actions carry no semantics tap action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IdleCommandBar(
                snapshot: commandDeckSnapshot(phase: GamePhase.wave),
                onTogglePause: () {},
                onSpeedSelected: (_) {},
                onToggleAutoStart: () {},
                onStartWave: () {},
              ),
              WorldMapAction(enabled: false, onWorldMap: () {}),
            ],
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Wave 1 of 8')),
          matchesSemantics(
            label: 'Wave 1 of 8',
            tooltip: '',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('World Map')),
          matchesSemantics(
            label: 'World Map',
            tooltip: '',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
        );
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('primary and World Map labels survive text scale 3.0', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3.0)),
          child: child!,
        ),
        home: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IdleCommandBar(
              snapshot: commandDeckSnapshot(),
              onTogglePause: () {},
              onSpeedSelected: (_) {},
              onToggleAutoStart: () {},
              onStartWave: () {},
            ),
            WorldMapAction(enabled: true, onWorldMap: () {}),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Start Wave'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);
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
          onTogglePause: () {},
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
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
            onTogglePause: () {},
            onSpeedSelected: (_) {},
            onToggleAutoStart: () {},
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
