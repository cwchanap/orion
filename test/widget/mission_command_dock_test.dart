import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_surface.dart';
import 'package:orion/game/ui/orion_surface.dart';

import '../support/command_deck_fixtures.dart';
import '../support/real_fonts.dart';

Widget railHost({
  int gold = 9999,
  List<TowerType>? unlockedTowerTypes,
  ValueChanged<TowerType>? onPlaceTower,
  ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent,
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
          onPlacementPreviewEvent: onPlacementPreviewEvent,
        ),
      ),
    ),
  );
}

void main() {
  group('scene 1e long-press drag placement preview', () {
    testWidgets('normal physical tap places exactly once, never previews', (
      tester,
    ) async {
      final placed = <TowerType>[];
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(
        railHost(onPlaceTower: placed.add, onPlacementPreviewEvent: events.add),
      );

      await tester.tap(find.byKey(const ValueKey('tower-card-laser')));

      expect(placed, [TowerType.laser]);
      expect(events, isEmpty);
    });

    testWidgets('semantics tap places exactly once, never previews', (
      tester,
    ) async {
      final placed = <TowerType>[];
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(
        railHost(onPlaceTower: placed.add, onPlacementPreviewEvent: events.add),
      );
      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        final data = tester.getSemantics(
          find.bySemanticsLabel(
            RegExp(r'Laser, unlocked, cost \d+, affordable'),
          ),
        );
        // ignore: deprecated_member_use
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          data.id,
          SemanticsAction.tap,
        );
        await tester.pump();

        expect(placed, [TowerType.laser]);
        expect(events, isEmpty);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('short press below the long-press threshold never previews', (
      tester,
    ) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(railHost(onPlacementPreviewEvent: events.add));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
      );
      await tester.pump(kLongPressTimeout - const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      expect(events, isEmpty);
    });

    testWidgets('horizontal swipe scrolls the rail and never previews', (
      tester,
    ) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(railHost(onPlacementPreviewEvent: events.add));

      await tester.drag(
        find.byKey(const ValueKey('tower-card-laser')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.pixels, greaterThan(0));
      expect(events, isEmpty);
    });

    testWidgets('long press begins the preview exactly once', (tester) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(railHost(onPlacementPreviewEvent: events.add));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events.single, isA<TowerPlacementPreviewBegin>());
      expect(
        (events.single as TowerPlacementPreviewBegin).type,
        TowerType.laser,
      );

      // Releasing with no pointer position ever recorded cancels — never a
      // commit at a guessed position.
      await gesture.up();
      await tester.pump();
      expect(events, hasLength(2));
      expect(events.last, isA<TowerPlacementPreviewCancel>());
    });

    testWidgets(
      'long-press drag streams updates, then commits once with the latest '
      'global pointer',
      (tester) async {
        final events = <TowerPlacementPreviewEvent>[];
        await tester.pumpWidget(railHost(onPlacementPreviewEvent: events.add));

        final start = tester.getCenter(
          find.byKey(const ValueKey('tower-card-laser')),
        );
        final gesture = await tester.startGesture(start);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveBy(const Offset(40, -30));
        await tester.pump();
        await gesture.moveBy(const Offset(40, -30));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(events.first, isA<TowerPlacementPreviewBegin>());
        final updates = events
            .whereType<TowerPlacementPreviewUpdate>()
            .toList();
        expect(updates, hasLength(2));
        expect(updates.first.globalPosition, start + const Offset(40, -30));
        expect(updates.last.globalPosition, start + const Offset(80, -60));
        expect(events.last, isA<TowerPlacementPreviewCommit>());
        expect(
          (events.last as TowerPlacementPreviewCommit).globalPosition,
          start + const Offset(80, -60),
        );
        expect(events.whereType<TowerPlacementPreviewCommit>(), hasLength(1));
      },
    );

    testWidgets('recognizer cancel clears the preview and never commits', (
      tester,
    ) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(railHost(onPlacementPreviewEvent: events.add));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      // Stream an update so a later drag end would commit at the last
      // pointer — the exact failure a recognizer cancel must never cause.
      await gesture.moveBy(const Offset(40, -30));
      await tester.pump();

      expect(events.first, isA<TowerPlacementPreviewBegin>());
      expect(events.whereType<TowerPlacementPreviewUpdate>(), isNotEmpty);
      expect(find.text('DROP TO BUILD'), findsOneWidget);
      expect(find.text('LIFTED'), findsOneWidget);

      // OS pointer interruption (incoming call, notification shade, app
      // switcher) surfaces as a recognizer cancel, not a drag end.
      await gesture.cancel();
      await tester.pump();

      expect(events.whereType<TowerPlacementPreviewCancel>(), hasLength(1));
      expect(events.whereType<TowerPlacementPreviewCommit>(), isEmpty);
      expect(find.text('DROP TO BUILD'), findsNothing);
      expect(find.text('LIFTED'), findsNothing);
    });

    testWidgets('locked card cannot begin a preview', (tester) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(
        railHost(
          unlockedTowerTypes: const [TowerType.laser],
          onPlacementPreviewEvent: events.add,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-railgun'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      expect(events, isEmpty);
    });

    testWidgets('active-wave card cannot begin a preview', (tester) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 375,
              height: 104,
              child: TowerBuildRail(
                phase: GamePhase.wave,
                gold: 9999,
                unlockedTowerTypes: TowerType.values,
                onPlaceTower: (_) {},
                onPlacementPreviewEvent: events.add,
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      expect(events, isEmpty);
    });

    testWidgets(
      'unaffordable unlocked card may preview; the game authority reports '
      'insufficientGold on validate',
      (tester) async {
        // Affordability is authority-driven: the drag begins and the game's
        // validatePlacement (pinned in orion_defense_game_test.dart) denies
        // with insufficientGold. The UI never reimplements the rule.
        final events = <TowerPlacementPreviewEvent>[];
        await tester.pumpWidget(
          railHost(gold: 0, onPlacementPreviewEvent: events.add),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

        expect(events, hasLength(1));
        expect(events.single, isA<TowerPlacementPreviewBegin>());

        // The unaffordable feedback states the real need, not fake success.
        expect(find.text('need 50 more'), findsOneWidget);

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('LIFTED source and DROP TO BUILD appear only while dragging', (
      tester,
    ) async {
      final events = <TowerPlacementPreviewEvent>[];
      await tester.pumpWidget(railHost(onPlacementPreviewEvent: events.add));

      expect(find.text('LIFTED'), findsNothing);
      expect(find.text('DROP TO BUILD'), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('LIFTED'), findsOneWidget);
      expect(find.text('DROP TO BUILD'), findsOneWidget);

      await gesture.up();
      await tester.pump();

      expect(find.text('LIFTED'), findsNothing);
      expect(find.text('DROP TO BUILD'), findsNothing);
    });

    testWidgets('affordable drag feedback shows cost delta to remaining gold', (
      tester,
    ) async {
      await tester.pumpWidget(railHost(gold: 150));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-card-laser'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();

      // Laser costs 50: −50 → 100 remaining.
      expect(find.text('−50 → 100'), findsOneWidget);

      await gesture.up();
      await tester.pump();
    });
  });

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

  testWidgets('the rail reuses its dock blur and its tiles are flat', (
    tester,
  ) async {
    await tester.pumpWidget(railHost());

    expect(find.byType(BackdropFilter), findsNothing);
    // Each tile still carries tier chrome, but flat: blurring a child of a
    // blurred container is the anti-pattern OrionSurface names, and eight
    // blurred tiles are what pushed this scene past its 5-9 budget.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tower-card-laser')),
        matching: find.byType(OrionInnerSurface),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tower-card-laser')),
        matching: find.byType(OrionSurface),
      ),
      findsNothing,
    );
  });

  testWidgets('idle dock surfaces carry no frame chrome', (tester) async {
    Future<void> pumpIdle(GameSnapshot snapshot) => tester.pumpWidget(
      MaterialApp(
        home: MissionCommandDock(
          snapshot: snapshot,
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
    );

    Finder surfaces() => find.descendant(
      of: find.byType(MissionCommandDock),
      matching: find.byType(OrionSurface),
    );

    // Artboard 1a's dock is two rows during build -- pacing controls, then
    // the tower rail -- so two surfaces, not one.
    await pumpIdle(commandDeckSnapshot());
    expect(surfaces(), findsOneWidget);
    final shelf = tester.widget<OrionSurface>(surfaces());
    expect(shelf.tier, OrionSurfaceTier.t4);
    expect(shelf.topBorderOnly, isTrue);
    expect(shelf.radius, 0);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.byKey(const ValueKey('command-dock-persistent-rail')),
      findsOneWidget,
    );

    // Once the wave is running there is nothing to build, and the dock
    // collapses back to the single control row.
    await pumpIdle(commandDeckSnapshot(phase: GamePhase.wave));
    expect(surfaces(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('command-dock-persistent-rail')),
      findsNothing,
    );

    // The invariant this test exists for: the reactor button carries its own
    // internal octagon frames, so no OrionSurface chrome may wrap a dock
    // surface in either state.
    for (final element in surfaces().evaluate()) {
      expect(
        find.ancestor(
          of: find.byWidget(element.widget),
          matching: find.byType(OrionSurface),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('rail cards put the cost above the name', (tester) async {
    // The artboard's card template is icon, cost, name -- the cost is the
    // decision, so it outranks the name. Ours had the name above a
    // bolt-prefixed cost.
    await tester.pumpWidget(railHost());

    final card = find.byKey(const ValueKey('tower-card-laser'));
    final cost = find.descendant(
      of: card,
      matching: find.text(
        '${GameBalance.towerStats(TowerType.laser, level: 1).cost}',
      ),
    );
    final name = find.descendant(
      of: card,
      matching: find.text(TowerType.laser.label.toUpperCase()),
    );

    expect(
      tester.getCenter(cost).dy,
      lessThan(tester.getCenter(name).dy),
      reason: 'the cost does not sit above the name',
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
    expect(first.width, 70); // artboard 1a's rail card
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
    expect(first.width, closeTo(70 * 1.3, 0.01));
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
    // One speed button showing the current speed, not three segments.
    expect(find.byTooltip('Game speed'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsOneWidget);
    // World Map left the dock contract; the chrome layer owns it now.
    expect(find.text('World Map'), findsNothing);

    await tester.tap(find.byTooltip('Game speed'));
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
    expect(find.byTooltip('World Map'), findsOneWidget);
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

    expect(find.byTooltip('Start Wave'), findsNothing);
    expect(find.byTooltip('Start Now'), findsOneWidget);
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
    expect(find.byTooltip('Start Wave'), findsOneWidget);
    expect(find.byTooltip('World Map'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);

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

  testWidgets(
    'idle dock is compact and quiet while the primary action is a wide '
    'filled pill',
    (tester) async {
      await loadRealFonts(withMaterialIcons: false);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 390,
              child: IdleCommandBar(
                snapshot: commandDeckSnapshot(),
                onTogglePause: () {},
                onSpeedSelected: (_) {},
                onToggleAutoStart: () {},
                onStartWave: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final dockRect = tester.getRect(find.byType(IdleCommandBar));
      expect(dockRect.height, lessThanOrEqualTo(80));
      expect(find.byType(MissionSurface), findsNothing);

      // Start Wave is the dominant, wide, filled action: 48-56dp tall,
      // clearly wider than a quarter of the dock, filled cyan with dark
      // content.
      final startRect = tester.getRect(find.byTooltip('Start Wave'));
      expect(
        startRect.height,
        inInclusiveRange(48, 56),
        reason:
            'Start Wave is ${startRect.height}px tall; the primary action '
            'must be a 48-56dp control.',
      );
      expect(
        startRect.width,
        // The dock's own horizontal chrome (deck margins, surface padding,
        // border) is not part of the action row; the pill must dominate the
        // row's content width.
        greaterThanOrEqualTo((dockRect.width - 40) / 4),
        reason:
            'Start Wave width ${startRect.width} must dominate the dock '
            'action row.',
      );
      final fill = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byTooltip('Start Wave'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final gradient =
          (fill.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors, const [
        Color(0xFF7FF0FF),
        Color(0xFF13B8E6),
        Color(0xFF0A7EA3),
      ]);
    },
  );
}
