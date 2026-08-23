import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
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
        waveTotal: 8,
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

  testWidgets('pacing strip invokes existing control callbacks', (
    tester,
  ) async {
    var pauseTaps = 0;
    var autoTaps = 0;
    double? speed;
    await tester.pumpWidget(
      MaterialApp(
        home: MissionPacingStrip(
          snapshot: commandDeckSnapshot(phase: GamePhase.wave),
          onTogglePause: () => pauseTaps += 1,
          onSpeedSelected: (value) => speed = value,
          onToggleAutoStart: () => autoTaps += 1,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Pause'));
    await tester.tap(find.text('2x'));
    await tester.tap(find.byTooltip('Auto-start waves'));
    expect((pauseTaps, speed, autoTaps), (1, 2.0, 1));
  });

  testWidgets('auto-start countdown keeps pause reachable during build', (
    tester,
  ) async {
    var pauseTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MissionPacingStrip(
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
    expect(find.text('Auto 5s'), findsOneWidget);
  });

  testWidgets(
    'pacing controls preserve 48dp hit targets while shrink-wrapped',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MissionPacingStrip(
            snapshot: commandDeckSnapshot(phase: GamePhase.wave),
            onTogglePause: () {},
            onSpeedSelected: (_) {},
            onToggleAutoStart: () {},
          ),
        ),
      );

      const minimumHitTarget = 48.0;
      final pauseRect = tester.getRect(find.byType(IconButton));
      expect(pauseRect.width, greaterThanOrEqualTo(minimumHitTarget));
      expect(pauseRect.height, greaterThanOrEqualTo(minimumHitTarget));

      for (final label in ['1x', '2x', '3x']) {
        final segment = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        );
        final segmentRect = tester.getRect(segment);
        expect(segmentRect.width, greaterThanOrEqualTo(minimumHitTarget));
        expect(segmentRect.height, greaterThanOrEqualTo(minimumHitTarget));
      }

      final autoRect = tester.getRect(find.byType(FilterChip));
      expect(autoRect.width, greaterThanOrEqualTo(minimumHitTarget));
      expect(autoRect.height, greaterThanOrEqualTo(minimumHitTarget));

      final paintedFrameRect = tester.getRect(find.byType(CommandFrame));
      expect(paintedFrameRect.width, lessThan(800));
    },
  );

  testWidgets(
    'pacing frame ends at its controls so the adjacent board stays tappable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var backgroundTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
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
                child: MissionPacingStrip(
                  snapshot: commandDeckSnapshot(phase: GamePhase.wave),
                  onTogglePause: () {},
                  onSpeedSelected: (_) {},
                  onToggleAutoStart: () {},
                ),
              ),
            ],
          ),
        ),
      );

      final frame = tester.getRect(find.byType(CommandFrame));
      final controlRects = [
        tester.getRect(find.byType(IconButton)),
        tester.getRect(find.byType(SegmentedButton<double>)),
        tester.getRect(find.byType(FilterChip)),
      ];
      final controlsRight = controlRects
          .map((rect) => rect.right)
          .reduce((left, right) => left > right ? left : right);
      expect(frame.right - controlsRight, lessThanOrEqualTo(7));

      final strip = tester.getRect(find.byType(MissionPacingStrip));
      final pointImmediatelyOutsideFrame = Offset(
        frame.right + 1,
        frame.center.dy,
      );
      expect(pointImmediatelyOutsideFrame.dx, lessThan(strip.right));
      await tester.tapAt(pointImmediatelyOutsideFrame);
      expect(backgroundTaps, 1);
    },
  );

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
                  MissionPacingStrip(
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
    await tester.tapAt(tester.getTopLeft(find.byType(MissionPacingStrip)));
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

  testWidgets('countdown is exposed in auto-start semantics', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: MissionPacingStrip(
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

        // The strip grows past the fixed status-HUD height when the labels
        // need more room; taps still pass through to the board underneath.
        final strip = tester.getRect(find.byType(AcquiredRunModuleStrip));
        final status = tester.getRect(
          find.byKey(const ValueKey('mission-status-hud')),
        );
        expect(strip.bottom, greaterThanOrEqualTo(status.bottom));
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
}
