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
      expect(find.bySemanticsLabel('Wave 3 of 8'), findsOneWidget);
      expect(find.bySemanticsLabel('Credits 150'), findsOneWidget);
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
                  IgnorePointer(
                    child: MissionStatusHud(snapshot: commandDeckSnapshot()),
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
    testWidgets('top flow reflows at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IgnorePointer(
                      child: MissionStatusHud(snapshot: commandDeckSnapshot()),
                    ),
                    const SizedBox(height: 6),
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

      final status = tester.getRect(
        find.byKey(const ValueKey('mission-status-hud')),
      );
      final pacing = tester.getRect(find.byType(MissionPacingStrip));
      expect(status.bottom, lessThanOrEqualTo(pacing.top));
      expect(tester.takeException(), isNull);
      for (final finder in [
        find.byTooltip('Pause'),
        find.text('1x'),
        find.text('2x'),
        find.text('3x'),
        find.byTooltip('Auto-start waves'),
      ]) {
        final rect = tester.getRect(finder.first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.bottom, lessThanOrEqualTo(640));
      }
    });

    testWidgets('complete top flow stays ordered at text scale $scale', (
      tester,
    ) async {
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
                child: Column(
                  key: const ValueKey('complete-top-flow'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IgnorePointer(child: MissionStatusHud(snapshot: snapshot)),
                    const SizedBox(height: 6),
                    MissionPacingStrip(
                      snapshot: snapshot,
                      onTogglePause: () {},
                      onSpeedSelected: (_) {},
                      onToggleAutoStart: () {},
                    ),
                    const SizedBox(height: 6),
                    Row(
                      key: const ValueKey('complete-top-flow-row'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const Spacer(),
                        NextWaveScanner(
                          preview: commandDeckPreview(),
                          modifierTitles: const ['Standard Conditions'],
                          collapseRequested: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      final status = tester.getRect(
        find.byKey(const ValueKey('mission-status-hud')),
      );
      final pacing = tester.getRect(find.byType(MissionPacingStrip));
      final modules = tester.getRect(find.byType(AcquiredRunModuleStrip));
      final scanner = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      );
      final flow = tester.getRect(
        find.byKey(const ValueKey('complete-top-flow')),
      );

      expect(status.bottom, lessThanOrEqualTo(pacing.top));
      expect(pacing.bottom, lessThanOrEqualTo(modules.top));
      expect(modules.right, lessThanOrEqualTo(scanner.left));
      expect(status.overlaps(pacing), isFalse);
      expect(pacing.overlaps(modules), isFalse);
      expect(modules.overlaps(scanner), isFalse);
      expect(flow.left, greaterThanOrEqualTo(0));
      expect(flow.right, lessThanOrEqualTo(360));
      expect(flow.bottom, lessThanOrEqualTo(640));
      for (final finder in [
        find.byTooltip('Pause'),
        find.text('1x'),
        find.text('2x'),
        find.text('3x'),
        find.byTooltip('Auto-start waves'),
        find.byTooltip('Expand next-wave scanner'),
      ]) {
        final rect = tester.getRect(finder.first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.bottom, lessThanOrEqualTo(640));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
