import 'dart:ui' show SemanticsFlags, Tristate;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_typography.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/run_module_draft_panel.dart';
import '../support/command_deck_fixtures.dart';

void main() {
  testWidgets('status HUD exposes exact snapshot values through semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final snapshot = commandDeckSnapshot(
        baseHealth: 8,
        startingBaseHealth: 20,
        gold: 150,
        waveNumber: 3,
        missionWaveTotal: 8,
      );
      await tester.pumpWidget(
        MaterialApp(home: MissionStatusHud(snapshot: snapshot)),
      );

      expect(find.bySemanticsLabel('Base 8 of 20'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Outpost Alpha. Wave 3 of 8, Build'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Credits 150'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('endless status HUD shows the wave number without a total', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: MissionStatusHud(
            snapshot: commandDeckSnapshot(
              phase: GamePhase.wave,
              waveNumber: 12,
              missionWaveTotal: null,
            ),
          ),
        ),
      );

      final stageAnchor = find.byKey(const ValueKey('mission-status-stage'));
      final readout = tester.widget<OrionReadout>(
        find.descendant(of: stageAnchor, matching: find.byType(OrionReadout)),
      );
      // The denominator is a true null so nothing renders — never the
      // string 'null' or a leftover mission total.
      expect(readout.value, '12');
      expect(readout.denominator, isNull);
      expect(find.textContaining('of 8'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(
        find.bySemanticsLabel('Outpost Alpha. Endless. Wave 12, Wave Active'),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('status HUD semantics carry the live phase and paused state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: MissionStatusHud(
            snapshot: commandDeckSnapshot(
              phase: GamePhase.wave,
              isPaused: true,
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Outpost Alpha. Wave 1 of 8, Paused'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MissionStatusHud(
            snapshot: commandDeckSnapshot(phase: GamePhase.wave),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Outpost Alpha. Wave 1 of 8, Wave Active'),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'wave pacing exposes the segmented speed set, pause and auto once',
    (tester) async {
      var pauseTaps = 0;
      var autoTaps = 0;
      double? speed;
      await tester.pumpWidget(
        MaterialApp(
          theme: orionThemeData,
          home: MissionPacingControls(
            snapshot: commandDeckSnapshot(phase: GamePhase.wave),
            onTogglePause: () => pauseTaps += 1,
            onSpeedSelected: (value) => speed = value,
            onToggleAutoStart: () => autoTaps += 1,
          ),
        ),
      );

      Finder speedLabel(String label) => find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == label,
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && const {'1x', '2x', '3x'}.contains(widget.data),
        ),
        findsNWidgets(3),
        reason:
            'wave phase must present the kit segmented speed control: '
            '1x, 2x and 3x as separately selectable cells',
      );

      // The speed button cycles: from the fixture's 1x, one tap selects 2x.
      await tester.tap(speedLabel('2x'));
      expect(speed, 2.0);
      await tester.tap(speedLabel('3x'));
      expect(speed, 3.0);
      await tester.tap(speedLabel('1x'));
      expect(speed, 1.0);

      await tester.tap(find.byTooltip('Pause'));
      await tester.tap(find.byTooltip('Auto-start waves'));
      expect((pauseTaps, autoTaps), (1, 1));
    },
  );

  testWidgets('auto-start countdown keeps pause reachable during build', (
    tester,
  ) async {
    var pauseTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MissionPacingControls(
          snapshot: commandDeckSnapshot(
            phase: GamePhase.build,
            autoStartEnabled: true,
            autoStartCountdownRemaining: 5,
          ),
          onTogglePause: () => pauseTaps += 1,
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
        ),
      ),
    );

    // Countdowns run during GamePhase.build, so pausing must work there.
    await tester.tap(find.byTooltip('Pause'));
    expect(pauseTaps, 1);
    expect(find.text('5s'), findsOneWidget);
  });

  testWidgets('the phase pair is green while building, muted in a wave', (
    tester,
  ) async {
    // Artboard 1a colours this pair by phase: BUILD is the state that invites
    // action, so it is naniteGreen, not chrome grey.
    Future<void> pumpPhase(GamePhase phase) => tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: MissionStatusHud(snapshot: commandDeckSnapshot(phase: phase)),
      ),
    );

    await pumpPhase(GamePhase.build);
    expect(
      tester.widget<Text>(find.text('BUILD')).style!.color!.toARGB32(),
      OrionUiTheme.dark.naniteGreen.toARGB32(),
    );

    await pumpPhase(GamePhase.wave);
    expect(
      tester.widget<Text>(find.text('WAVE ACTIVE')).style!.color!.toARGB32(),
      OrionUiTheme.dark.textMuted.toARGB32(),
    );
  });

  testWidgets('the three pacing chips share one shape', (tester) async {
    // They used to be a circular IconButton, a stadium OutlinedButton and a
    // rounded FilterChip, so the row read as three unrelated controls.
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: MissionPacingControls(
          snapshot: commandDeckSnapshot(phase: GamePhase.build),
          onTogglePause: () {},
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
        ),
      ),
    );

    final sizes = [
      'Pause',
      'Game speed',
      'Auto-start waves',
    ].map((tooltip) => tester.getSize(find.byTooltip(tooltip))).toList();
    for (final size in sizes) {
      expect(
        size.height,
        sizes.first.height,
        reason: 'a pacing chip is a different height from its neighbours',
      );
      expect(
        size.width,
        sizes.first.width,
        reason: 'a pacing chip is a different width from its neighbours',
      );
    }

    // Size alone would pass for a circle and a square of the same box, so the
    // corner radius is the half of "one shape" that size cannot see.
    for (final tooltip in ['Pause', 'Game speed', 'Auto-start waves']) {
      final shape =
          tester
                  .widget<Material>(
                    find.descendant(
                      of: find.byTooltip(tooltip),
                      matching: find.byType(Material),
                    ),
                  )
                  .shape
              as RoundedRectangleBorder;

      expect(shape.borderRadius, BorderRadius.circular(14));
      expect(shape.side.width, 1);
    }
  });

  testWidgets('pacing controls preserve 48dp hit targets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MissionPacingControls(
          snapshot: commandDeckSnapshot(phase: GamePhase.build),
          onTogglePause: () {},
          onSpeedSelected: (_) {},
          onToggleAutoStart: () {},
        ),
      ),
    );

    // All three are one widget now, told apart by tooltip rather than by
    // Material type.
    const minimumHitTarget = 48.0;
    for (final tooltip in ['Pause', 'Game speed', 'Auto-start waves']) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(
        rect.width,
        greaterThanOrEqualTo(minimumHitTarget),
        reason: '$tooltip is narrower than a 48dp target',
      );
      expect(
        rect.height,
        greaterThanOrEqualTo(minimumHitTarget),
        reason: '$tooltip is shorter than a 48dp target',
      );
    }
  });

  testWidgets('status passes taps through while pacing consumes them', (
    tester,
  ) async {
    var backgroundTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps += 1,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: IgnorePointer(
                          child: MissionStatusHud(
                            snapshot: commandDeckSnapshot(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(key: ValueKey('top-flow-gap'), height: 6),
                  MissionPacingControls(
                    snapshot: commandDeckSnapshot(phase: GamePhase.wave),
                    onTogglePause: () {},
                    onSpeedSelected: (_) {},
                    onToggleAutoStart: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mission-status-hud')));
    expect(backgroundTaps, 1);
    await tester.tap(find.byKey(const ValueKey('top-flow-gap')));
    expect(backgroundTaps, 2);
    await tester.tap(find.byTooltip('Pause'));
    expect(backgroundTaps, 2);
    // The controls shrink-wrap: space just beside them belongs to the board.
    final pacing = tester.getRect(find.byType(MissionPacingControls));
    await tester.tapAt(Offset(pacing.left - 1, pacing.center.dy));
    expect(backgroundTaps, 3);
  });

  testWidgets('base health fill uses the exact threshold colors', (
    tester,
  ) async {
    const cases = [(11, 'cyan'), (10, 'orange'), (5, 'red')];
    for (final (health, expected) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: MissionStatusHud(
            snapshot: commandDeckSnapshot(
              baseHealth: health,
              startingBaseHealth: 20,
            ),
          ),
        ),
      );
      final color = tester
          .widget<ColoredBox>(find.byKey(const ValueKey('base-health-fill')))
          .color;
      final uiTheme = OrionUiTheme.dark;
      expect(color, switch (expected) {
        'cyan' => uiTheme.systemCyan,
        'orange' => uiTheme.warningOrange,
        _ => uiTheme.dangerRed,
      });
    }
  });

  testWidgets('hull readout paints segmented blocks over the exact fill', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          home: MissionStatusHud(snapshot: commandDeckSnapshot()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final track = tester.getRect(
      find.byKey(const ValueKey('base-health-fill-track')),
    );
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    int brightness(double dx) {
      final x = (track.left + dx).round();
      final y = track.center.dy.round();
      final offset = (y * 390 + x) * 4;
      return pixels!.getUint8(offset) +
          pixels.getUint8(offset + 1) +
          pixels.getUint8(offset + 2);
    }

    expect(
      brightness(7),
      lessThan(brightness(4) ~/ 2),
      reason: 'A dark divider should separate the first two hull blocks.',
    );
  });

  testWidgets('status HUD is one framed top bar holding all three readouts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: MissionStatusHud(snapshot: commandDeckSnapshot()),
      ),
    );

    expect(find.byKey(const ValueKey('mission-status-hud')), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-status-base')), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-status-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mission-status-credits')),
      findsOneWidget,
    );

    // Artboard 1a floats these readouts on the live board rather than giving
    // each its own pill. Their contrast comes from the type roles' shadow,
    // which exists so it never depends on a surface fill.
    final frame = find.ancestor(
      of: find.byKey(const ValueKey('mission-status-hud')),
      matching: find.byType(OrionSurface),
    );
    expect(
      frame,
      findsOneWidget,
      reason: 'the status readouts must sit inside one framed top bar',
    );
    for (final key in [
      'mission-status-base',
      'mission-status-stage',
      'mission-status-credits',
    ]) {
      expect(
        find.descendant(of: frame, matching: find.byKey(ValueKey(key))),
        findsOneWidget,
        reason: '$key escaped the shared HUD frame',
      );
    }

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mission-status-hud')),
        matching: find.byType(OrionSurface),
      ),
      findsNothing,
      reason: 'a pill per readout is the old look; one frame wraps them all',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mission-status-hud')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'status anchors stay on screen for long stage names at 390x844 scale 1.3',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Stack(
            children: [
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: IgnorePointer(
                  child: MissionStatusHud(
                    snapshot: commandDeckSnapshot(
                      stageName: 'Helios Terminus Orbital Relay Station',
                      stageLabel: 'Terminus Relay',
                      waveNumber: 8,
                      missionWaveTotal: 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (final key in [
        'mission-status-base',
        'mission-status-stage',
        'mission-status-credits',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(0), reason: key);
        expect(rect.top, greaterThanOrEqualTo(0), reason: key);
        expect(rect.right, lessThanOrEqualTo(390), reason: key);
        expect(rect.bottom, lessThanOrEqualTo(844), reason: key);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('countdown is exposed in auto-start semantics', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: MissionPacingControls(
            snapshot: commandDeckSnapshot(
              phase: GamePhase.build,
              autoStartEnabled: true,
              autoStartCountdownRemaining: 2.2,
            ),
            onTogglePause: () {},
            onSpeedSelected: (_) {},
            onToggleAutoStart: () {},
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Auto-start waves, 3 seconds'),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets(
      'top row reflows with modules and scanner at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final snapshot = commandDeckSnapshot(
          phase: GamePhase.build,
          acquiredRunModules: const [RunModuleId.heavyCaliber],
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Row(
                    key: const ValueKey('top-status-row'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: IgnorePointer(
                          child: MissionStatusHud(snapshot: snapshot),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: IgnorePointer(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: AcquiredRunModuleStrip(
                              moduleIds: snapshot.acquiredRunModules,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      NextWaveScanner(
                        preview: commandDeckPreview(),
                        modifierTitles: const ['Standard Conditions'],
                        collapseRequested: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        // Within the row, modules sit between status and scanner; nothing
        // overflows the viewport at elevated text scales.
        final status = tester.getRect(
          find.byKey(const ValueKey('mission-status-hud')),
        );
        final modules = tester.getRect(find.byType(AcquiredRunModuleStrip));
        final scanner = tester.getRect(
          find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        );
        expect(status.right, lessThanOrEqualTo(modules.left));
        expect(modules.right, lessThanOrEqualTo(scanner.left));
        for (final finder in [
          find.byTooltip('Expand next-wave scanner'),
          find.textContaining(
            runModuleDefinition(RunModuleId.heavyCaliber).title,
          ),
        ]) {
          final rect = tester.getRect(finder.first);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(rect.bottom, lessThanOrEqualTo(640));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'three acquired modules render fully without clipping at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        const moduleIds = [
          RunModuleId.heavyCaliber,
          RunModuleId.overclockRelay,
          RunModuleId.longSight,
        ];
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: IgnorePointer(
                          child: MissionStatusHud(
                            snapshot: commandDeckSnapshot(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: IgnorePointer(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: AcquiredRunModuleStrip(moduleIds: moduleIds),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        // Every label is laid out on screen — no viewport clips them away, so
        // all three acquired modules stay inspectable.
        for (final id in moduleIds) {
          final rect = tester.getRect(
            find.textContaining(runModuleDefinition(id).title),
          );
          expect(rect.height, greaterThan(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(rect.bottom, lessThanOrEqualTo(640));
        }

        // The status HUD is a Wrap now: it reflows vertically when squeezed
        // narrow, so both chrome pieces must simply stay on screen; taps still
        // pass through to the board underneath.
        final strip = tester.getRect(find.byType(AcquiredRunModuleStrip));
        final status = tester.getRect(
          find.byKey(const ValueKey('mission-status-hud')),
        );
        expect(status.bottom, lessThanOrEqualTo(640));
        expect(strip.bottom, lessThanOrEqualTo(640));
        expect(
          find.ancestor(
            of: find.byType(AcquiredRunModuleStrip),
            matching: find.byWidgetPredicate(
              (widget) => widget is IgnorePointer && widget.ignoring,
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('status readouts are hero scale with room to breathe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MissionStatusHud(snapshot: commandDeckSnapshot())),
    );

    // The sheet puts readout's hero range at 22-40. These were sitting at
    // 14-16 inside pills, which read as small button labels; unboxing frees
    // the width to run them at hero scale. Base health renders through
    // OrionReadout, so the whole value is its own Text node separate from
    // its muted denominator.
    for (final value in ['20', '150']) {
      final text = tester.widget<Text>(find.text(value));
      expect(
        text.style?.fontSize,
        greaterThanOrEqualTo(22),
        reason: '"$value" is below the sheet\'s hero readout range',
      );
    }

    // Without pills, the gap between groups is what separates them, so it
    // has to be generous rather than the old chip-to-chip tightness.
    final baseRect = tester.getRect(
      find.byKey(const ValueKey('mission-status-base')),
    );
    final stageRect = tester.getRect(
      find.byKey(const ValueKey('mission-status-stage')),
    );
    expect(
      stageRect.left - baseRect.right,
      greaterThanOrEqualTo(10),
      reason:
          'Unboxed readouts ${stageRect.left - baseRect.right}px apart read '
          'as one run-together string.',
    );
  });

  group('wave speed segments accessibility', () {
    Widget pacingHost({double speed = 1, ValueChanged<double>? onSelected}) =>
        MaterialApp(
          theme: orionThemeData,
          home: Scaffold(
            body: Center(
              child: MissionPacingControls(
                snapshot: commandDeckSnapshot(
                  phase: GamePhase.wave,
                  speedMultiplier: speed,
                ),
                onTogglePause: () {},
                onSpeedSelected: onSelected ?? (_) {},
                onToggleAutoStart: () {},
              ),
            ),
          ),
        );

    testWidgets('segments expose selected-state semantics as one group', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(pacingHost());
        await tester.pump();

        SemanticsFlags flagsOf(String label) => tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .flagsCollection;

        for (final label in ['Speed 1x', 'Speed 2x', 'Speed 3x']) {
          final flags = flagsOf(label);
          expect(
            flags.isButton,
            isTrue,
            reason: '$label must stay a semantic button',
          );
          expect(
            flags.isInMutuallyExclusiveGroup,
            isTrue,
            reason:
                '$label is one cell of a segmented control; without the '
                'mutually-exclusive flag semantics announce three '
                'unrelated buttons',
          );
          expect(
            flags.isFocused,
            isNot(Tristate.none),
            reason:
                '$label must be a focusable keyboard target; a bare '
                'GestureDetector publishes no focus state at all',
          );
        }
        expect(
          flagsOf('Speed 1x').isSelected,
          Tristate.isTrue,
          reason: 'the active segment must announce its selection',
        );
        expect(
          flagsOf('Speed 2x').isSelected,
          Tristate.isFalse,
          reason: 'an inactive segment must announce it is not selected',
        );
      } finally {
        handle.dispose();
      }
    });

    for (final viewport in [const Size(390, 844), const Size(360, 640)]) {
      testWidgets('every speed segment keeps a 48dp target at '
          '${viewport.width.toInt()}x${viewport.height.toInt()}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        try {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(pacingHost());
          await tester.pump();

          for (final label in ['Speed 1x', 'Speed 2x', 'Speed 3x']) {
            final rect = tester.getRect(find.bySemanticsLabel(label));
            expect(
              rect.width,
              greaterThanOrEqualTo(48),
              reason:
                  '$label is ${rect.width.toStringAsFixed(1)}px wide — '
                  'below the 48dp touch floor at $viewport',
            );
            expect(
              rect.height,
              greaterThanOrEqualTo(48),
              reason:
                  '$label is ${rect.height.toStringAsFixed(1)}px tall — '
                  'below the 48dp touch floor at $viewport',
            );
          }
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets('keyboard focus and activation select a segment', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        double? speed;
        await tester.pumpWidget(pacingHost(onSelected: (v) => speed = v));
        await tester.pump();

        Future<void> tabToSegment(String label) async {
          for (var i = 0; i < 8; i += 1) {
            final focused =
                tester
                    .getSemantics(find.bySemanticsLabel(label))
                    .getSemanticsData()
                    .flagsCollection
                    .isFocused ==
                Tristate.isTrue;
            if (focused) return;
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          fail('$label never received keyboard focus within 8 Tab presses');
        }

        await tabToSegment('Speed 2x');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(speed, 2.0, reason: 'Enter must activate the focused segment');

        await tabToSegment('Speed 3x');
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(speed, 3.0, reason: 'Space must activate the focused segment');
      } finally {
        handle.dispose();
      }
    });
  });
}
