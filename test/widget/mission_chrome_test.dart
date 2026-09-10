import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/acquired_run_module_control.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/mission_surface.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

const _productViewport = Size(390, 844);

Widget chromeHost(
  GameSnapshot snapshot, {
  VoidCallback? onBackgroundTap,
  TextScaler textScaler = TextScaler.noScaling,
  Color? backgroundColor,
  ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent,
}) {
  return MaterialApp(
    // The product app hides this banner; a fixture host must too, or the
    // parity evidence carries a stripe the shipped game never shows.
    debugShowCheckedModeBanner: false,
    // The app's real theme: Material components (the pacing segments, the
    // auto-start chip) take their face from it. Without it they render in
    // Roboto, which is narrower than ChakraPetch — and a wrap guard that
    // measures the wrong face cannot see a wrap.
    theme: orionThemeData,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Tappable stand-in for the board beneath the chrome.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBackgroundTap,
            ),
          ),
          Positioned.fill(
            child: MissionChrome(
              snapshot: snapshot,
              onBoardTapIntercept: (_) => false,
              onWorldMap: () {},
              onStartWave: () {},
              onTogglePause: () {},
              onSpeedSelected: (_) {},
              onToggleAutoStart: () {},
              onPlaceTower: (_) {},
              onUpgrade: () {},
              onSpecialize: (_) {},
              onTargetingChanged: (_) {},
              onSell: () {},
              onPlacementPreviewEvent: onPlacementPreviewEvent,
            ),
          ),
        ],
      ),
    ),
  );
}

void _expectWithinViewport(WidgetTester tester, Finder finder, Size viewport) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

void _expectIdlePacingAbsent(WidgetTester tester) {
  // A selection replaces the idle dock entirely: no pacing, no reactor.
  expect(find.byTooltip('Pause'), findsNothing);
  expect(find.byTooltip('Resume'), findsNothing);
  expect(find.byTooltip('Game speed'), findsNothing);
  expect(find.byTooltip('Auto-start waves'), findsNothing);
  expect(find.text('Start Wave'), findsNothing);
}

void main() {
  testWidgets(
    'dock preview events pass through chrome; board taps recover after drag',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final events = <TowerPlacementPreviewEvent>[];
      var backgroundTaps = 0;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(selectedCell: const GridPosition(1, 1)),
          onBackgroundTap: () => backgroundTaps++,
          onPlacementPreviewEvent: events.add,
        ),
      );
      await tester.pump();

      // One long-press drag passes its begin/update/commit family through
      // MissionChrome untouched.
      final start = tester.getCenter(
        find.byKey(const ValueKey('tower-card-laser')),
      );
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(events, hasLength(1));
      expect(events.single, isA<TowerPlacementPreviewBegin>());

      await gesture.moveBy(const Offset(40, -120));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(events.last, isA<TowerPlacementPreviewCommit>());
      expect(
        (events.last as TowerPlacementPreviewCommit).globalPosition,
        start + const Offset(40, -120),
      );

      // The ended drag leaves no arena winner behind: normal board taps pass.
      await tester.tapAt(
        Offset(_productViewport.width / 2, _productViewport.height / 2),
      );
      await tester.pump();
      expect(backgroundTaps, 1);
    },
  );

  testWidgets('capture scene 1a fixture', (tester) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1a state: build-idle, no cell/tower selected,
    // scanner/modules collapsed (no acquired modules). Real Roboto so the
    // evidence shows true text metrics, not Ahem blocks.
    await loadRealFonts();
    // The memo can hold a pending future from an earlier cold-cache test
    // in this process; clear it so this fixture's warmed cache is used.
    OrionArtDescriptor.resetSpriteCache();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: chromeHost(
          commandDeckSnapshot(nextWavePreview: commandDeckPreview()),
          // The scene's ground is the board's hull black; the chrome bands
          // are the parity subject, the dark ground keeps the fixture
          // readable against the mock.
          backgroundColor: OrionUiTheme.dark.hullBlack,
        ),
      ),
    );
    await tester.pump();

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1a.png'),
    );
  });

  testWidgets('mission actions render their labels fully at product width', (
    tester,
  ) async {
    await loadRealFonts(withMaterialIcons: false);
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();

    // Roboto is marginally narrower than the device's SF Pro; the regenerated
    // fixture evidence covers the device metrics. The primary action label
    // must fit at 390px width and 1.0x text scale without ellipsis. (World
    // Map is an icon-scale chip now; its label lives in tooltip/semantics.)
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Start Wave'),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason:
          '"Start Wave" ellipsizes at 390px width; the primary mission '
          'action must render its label without truncation.',
    );
  });

  testWidgets(
    'idle dock keeps pacing and the primary action on one row at product '
    'width with real fonts',
    (tester) async {
      // Placeholder test glyphs are wider than any real font and cannot
      // expose a real-font wrap. chromeHost carries the app's theme, so
      // Material labels here are ChakraPetch, the face the device uses.
      await loadRealFonts(withMaterialIcons: false);
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
      );
      await tester.pump();

      // A wrapped pacing row grows the dock taller, lifting its surface
      // over bottom-row board cells and swallowing their taps. Bound the
      // idle surface to its single-row height: one 48dp control run and
      // the 84px reactor, plus the surface's own 8px padding.
      final surfaceRect = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('command-dock-idle')),
              matching: find.byType(MissionSurface),
            )
            .first,
      );
      expect(
        surfaceRect.height,
        lessThanOrEqualTo(100.5),
        reason:
            'Idle dock surface grew to ${surfaceRect.height}px; the pacing '
            'controls wrapped into a second row at 390px with real fonts.',
      );

      // Every idle control shares the row: equal vertical centers.
      final centers = [
        find.byTooltip('Pause'),
        find.byTooltip('Game speed'),
        find.byType(FilterChip),
        find.byTooltip('Start Wave'),
      ].map(tester.getCenter).toList();
      for (final center in centers) {
        expect(
          (center.dy - centers.first.dy).abs(),
          lessThan(0.5),
          reason:
              'Idle control at $center is not on the same row as the first '
              'control (${centers.first}); the dock wrapped.',
        );
      }
    },
  );

  testWidgets('the unboxed status readouts stay on one row', (tester) async {
    // Unboxing the status band freed width, and hero-scale numerals spend
    // it: at 26 the credits group wrapped to a second row behind the two
    // band buttons. This pins the row at the product viewport with the real
    // face, because Roboto is narrower and would not catch a regression.
    await loadRealFonts(withMaterialIcons: false);
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The same snapshot the 1a fixture uses: a next-wave preview puts the
    // scanner in the band, which is the band's worst case for width.
    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();

    final centres = [
      'mission-status-base',
      'mission-status-stage',
      'mission-status-credits',
    ].map((key) => tester.getCenter(find.byKey(ValueKey(key))).dy).toList();
    for (final centre in centres) {
      expect(
        (centre - centres.first).abs(),
        lessThan(8),
        reason: 'a status readout wrapped off the band row',
      );
    }

    // And the run must clear the band's trailing actions.
    final credits = tester.getRect(
      find.byKey(const ValueKey('mission-status-credits')),
    );
    final worldMap = tester.getRect(find.byTooltip('World Map'));
    expect(
      credits.right,
      lessThanOrEqualTo(worldMap.left),
      reason: 'the credits readout runs under the band actions',
    );
  });

  testWidgets('composes the mission overlay bands at the product viewport', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(
          nextWavePreview: commandDeckPreview(),
          feedback: 'Not enough gold.',
          acquiredRunModules: const [RunModuleId.heavyCaliber],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MissionStatusHud), findsOneWidget);
    expect(find.byTooltip('World Map'), findsOneWidget);
    expect(find.byType(AcquiredRunModuleControl), findsOneWidget);
    expect(find.byType(NextWaveScanner), findsOneWidget);

    // The toast band sits above the command dock, never beside or below it.
    final toastBottom = tester
        .getBottomRight(find.byKey(const ValueKey('mission-command-toast')))
        .dy;
    final dockTop = tester.getTopLeft(find.byType(MissionCommandDock)).dy;
    expect(toastBottom, lessThanOrEqualTo(dockTop));

    // World Map is a compact top-band mission action now, not a bottom-band
    // dock companion.
    final worldMapTop = tester.getTopLeft(find.byTooltip('World Map')).dy;
    expect(worldMapTop, lessThan(dockTop));

    // The idle dock hosts pacing plus the primary action.
    expect(find.byTooltip('Pause'), findsOneWidget);
    // One speed button, showing the current speed and cycling on tap.
    expect(find.byTooltip('Game speed'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);

    // Board-first chrome carries no ORION branding.
    expect(find.textContaining('ORION'), findsNothing);
  });

  testWidgets('acquired module control exists only when modules exist', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(chromeHost(commandDeckSnapshot()));
    await tester.pump();
    expect(find.byType(AcquiredRunModuleControl), findsNothing);

    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(
          acquiredRunModules: const [RunModuleId.heavyCaliber],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AcquiredRunModuleControl), findsOneWidget);
  });

  testWidgets('next wave scanner exists under its visibility condition', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();
    expect(find.byType(NextWaveScanner), findsOneWidget);

    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(phase: GamePhase.wave)),
    );
    await tester.pump();
    expect(find.byType(NextWaveScanner), findsNothing);
  });

  testWidgets('empty chrome space passes taps through; controls absorb them', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backgroundTaps = 0;
    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(nextWavePreview: commandDeckPreview()),
        onBackgroundTap: () => backgroundTaps++,
      ),
    );
    await tester.pump();

    // Screen center: empty chrome/root space outside every compact control,
    // contextual dock, and the root's control bands.
    await tester.tapAt(
      Offset(_productViewport.width / 2, _productViewport.height / 2),
    );
    await tester.pump();
    expect(backgroundTaps, 1);

    // A real control absorbs its tap; the background never sees it.
    await tester.tap(find.text('1x'));
    await tester.pump();
    expect(backgroundTaps, 1);
  });

  testWidgets('compact portrait: expanded overlays stay inside the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(
          nextWavePreview: commandDeckPreview(),
          acquiredRunModules: const [
            RunModuleId.heavyCaliber,
            RunModuleId.cryoReservoir,
          ],
          feedback: 'Not enough gold.',
        ),
      ),
    );
    await tester.pump();

    // Warning toast remains within the viewport.
    expect(find.text('Not enough gold.'), findsOneWidget);
    _expectWithinViewport(
      tester,
      find.byKey(const ValueKey('command-toast')),
      _productViewport,
    );

    // Expanded scanner stays inside the viewport.
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    _expectWithinViewport(
      tester,
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      _productViewport,
    );
    await tester.tap(find.byTooltip('Collapse next-wave scanner'));
    await tester.pumpAndSettle();

    // Expanded acquired-module details stay inside the viewport.
    await tester.tap(find.text('Modules 2'));
    await tester.pumpAndSettle();
    _expectWithinViewport(
      tester,
      find.byKey(const ValueKey('acquired-modules-expanded')),
      _productViewport,
    );
  });

  testWidgets(
    'compact portrait: a selection collapses the scanner and module details',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      GameSnapshot snapshotWith({GridPosition? selectedCell}) {
        return commandDeckSnapshot(
          nextWavePreview: commandDeckPreview(),
          acquiredRunModules: const [
            RunModuleId.heavyCaliber,
            RunModuleId.cryoReservoir,
          ],
          selectedCell: selectedCell,
        );
      }

      await tester.pumpWidget(chromeHost(snapshotWith()));
      await tester.pump();
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modules 2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsOneWidget,
      );

      // Selecting a board cell collapses both expansions.
      await tester.pumpWidget(
        chromeHost(snapshotWith(selectedCell: const GridPosition(1, 1))),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsNothing,
      );

      // …and a tower selection keeps both collapsed.
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(1, 1),
      );
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(),
            acquiredRunModules: const [
              RunModuleId.heavyCaliber,
              RunModuleId.cryoReservoir,
            ],
            selectedTower: tower,
            selectedTowerStats: GameBalance.towerStats(
              tower.type,
              level: tower.level,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'collapsing one of two expanded top panels keeps World Map yielded',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(),
            acquiredRunModules: const [
              RunModuleId.heavyCaliber,
              RunModuleId.cryoReservoir,
            ],
          ),
        ),
      );
      await tester.pump();

      // Idle with no panel expanded: World Map is present.
      expect(find.byTooltip('World Map'), findsOneWidget);

      // Expand both top-band panels.
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modules 2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsOneWidget,
      );
      // World Map yields to the expanded panels.
      expect(find.byTooltip('World Map'), findsNothing);

      // Collapse only the scanner; modules is still expanded, so World Map
      // must stay hidden — not reinserted to steal the modules panel's width.
      await tester.tap(find.byTooltip('Collapse next-wave scanner'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsOneWidget,
      );
      expect(find.byTooltip('World Map'), findsNothing);

      // Collapse the modules panel too; now World Map returns.
      await tester.tap(find.byTooltip('Collapse acquired modules'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsNothing,
      );
      expect(find.byTooltip('World Map'), findsOneWidget);
    },
  );

  testWidgets(
    'a scanner-preview reset keeps the still-expanded modules panel yielded',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Build phase with modules and a wave-1 preview.
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(waveNumber: 1),
            acquiredRunModules: const [
              RunModuleId.heavyCaliber,
              RunModuleId.cryoReservoir,
            ],
          ),
        ),
      );
      await tester.pump();

      // Expand only the modules panel; World Map yields to it.
      await tester.tap(find.text('Modules 2'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsOneWidget,
      );
      expect(find.byTooltip('World Map'), findsNothing);

      // The scanner preview rolls to the next wave while the module list is
      // unchanged. Only the scanner's reset token changed, so only the
      // scanner may collapse — the still-expanded modules panel must keep
      // World Map yielded, not reinsert it to steal the panel's width.
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(waveNumber: 2),
            acquiredRunModules: const [
              RunModuleId.heavyCaliber,
              RunModuleId.cryoReservoir,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('acquired-modules-expanded')),
        findsOneWidget,
      );
      expect(find.byTooltip('World Map'), findsNothing);
    },
  );

  testWidgets(
    'a module-list reset keeps the still-expanded scanner panel yielded',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Build phase with modules and a wave-1 preview.
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(waveNumber: 1),
            acquiredRunModules: const [RunModuleId.heavyCaliber],
          ),
        ),
      );
      await tester.pump();

      // Expand only the scanner; World Map yields to it.
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );
      expect(find.byTooltip('World Map'), findsNothing);

      // The module list changes while the scanner preview is unchanged. Only
      // the modules' reset token changed, so only the modules panel may
      // collapse — the still-expanded scanner must keep World Map yielded.
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(waveNumber: 1),
            acquiredRunModules: const [
              RunModuleId.heavyCaliber,
              RunModuleId.cryoReservoir,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );
      expect(find.byTooltip('World Map'), findsNothing);
    },
  );

  testWidgets('landscape viewports render the same tree without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const tower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(1, 1),
    );
    final idleSnapshot = commandDeckSnapshot(
      nextWavePreview: commandDeckPreview(),
      acquiredRunModules: const [
        RunModuleId.heavyCaliber,
        RunModuleId.cryoReservoir,
      ],
    );
    final cellSnapshot = commandDeckSnapshot(
      selectedCell: const GridPosition(1, 1),
      nextWavePreview: commandDeckPreview(),
    );
    final towerSnapshot = commandDeckSnapshot(
      selectedTower: tower,
      selectedTowerStats: GameBalance.towerStats(
        tower.type,
        level: tower.level,
      ),
      nextWavePreview: commandDeckPreview(),
    );

    for (final size in const [Size(844, 390), Size(932, 430)]) {
      tester.view.physicalSize = size;

      // Build idle: the module trigger and scanner must fit, not overflow.
      await tester.pumpWidget(chromeHost(idleSnapshot));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
      _expectWithinViewport(
        tester,
        find.byKey(const ValueKey('acquired-modules-collapsed')),
        size,
      );
      _expectWithinViewport(tester, find.byType(MissionStatusHud), size);

      // Selected cell: the build rail must fit or scroll, not overflow.
      await tester.pumpWidget(chromeHost(cellSnapshot));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);
      _expectWithinViewport(
        tester,
        find.byKey(const ValueKey('tower-card-laser')),
        size,
      );
      _expectWithinViewport(tester, find.byType(MissionStatusHud), size);

      // Selected tower: the inspector must fit or scroll, not overflow.
      await tester.pumpWidget(chromeHost(towerSnapshot));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('command-dock-tower')), findsOneWidget);
      _expectWithinViewport(
        tester,
        find.byKey(const ValueKey('tower-inspector')),
        size,
      );
      _expectWithinViewport(tester, find.byType(MissionStatusHud), size);
    }
  });

  testWidgets(
    'compact portrait: selected cell keeps the rail reachable and scrollable',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(selectedCell: const GridPosition(1, 1)),
          textScaler: const TextScaler.linear(1.3),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);
      _expectIdlePacingAbsent(tester);

      // The first card is on screen and the rail scrolls horizontally to
      // reveal the last one.
      _expectWithinViewport(
        tester,
        find.byKey(const ValueKey('tower-card-laser')),
        _productViewport,
      );
      await tester.drag(
        find.byKey(const ValueKey('tower-card-laser')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      _expectWithinViewport(
        tester,
        find.byKey(ValueKey('tower-card-${TowerType.values.last.name}')),
        _productViewport,
      );
    },
  );

  testWidgets(
    'compact portrait: selected Level 2 tower scrolls to every control',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(1, 1),
        level: 2,
      );
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            selectedTower: tower,
            selectedTowerStats: GameBalance.towerStats(
              tower.type,
              level: tower.level,
            ),
          ),
          textScaler: const TextScaler.linear(1.3),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('command-dock-tower')), findsOneWidget);
      _expectIdlePacingAbsent(tester);

      // Both specialization actions, targeting, sell, and the final stat row
      // are all reachable through the inspector's internal scroll.
      final reachableKeys = <String>[
        for (final specialization in GameBalance.specializationsFor(tower.type))
          'tower-specialization-${specialization.name}',
        'tower-target-first',
        'tower-sell',
        'tower-stat-range',
      ];
      for (final key in reachableKeys) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        _expectWithinViewport(
          tester,
          find.byKey(ValueKey(key)),
          _productViewport,
        );
      }
    },
  );

  testWidgets('World Map shell matches the scanner utility scale', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();

    // World Map is a compact top-band utility now, not the largest control:
    // it matches the scanner's ~48dp shell (keeping the touch minimum) and
    // shares its top alignment in the utility row.
    final mapRect = tester.getRect(find.byTooltip('World Map'));
    final scannerRect = tester.getRect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
    );
    expect(mapRect.width, inInclusiveRange(48, 60));
    expect(mapRect.height, inInclusiveRange(48, 60));
    expect(
      (mapRect.top - scannerRect.top).abs(),
      lessThan(0.5),
      reason: 'World Map must align with the scanner in the top utility row.',
    );
    // The shell is icon-scale: no label text beside the map glyph.
    expect(find.text('World Map'), findsNothing);
  });

  // Semantic contracts migrated from the deleted ReactorButton: the World
  // Map action chip is the production control implementing the same
  // Tooltip + explicit-Semantics pattern (per the HPA-14 migration rule).
  group(
    'World Map action chip semantics (migrated ReactorButton contracts)',
    () {
      testWidgets(
        'chip is at least 48dp and its tooltip merges into one label',
        (tester) async {
          var opens = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: WorldMapAction(
                    enabled: true,
                    onWorldMap: () => opens++,
                  ),
                ),
              ),
            ),
          );

          final rect = tester.getRect(find.byTooltip('World Map'));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          await tester.tap(find.byTooltip('World Map'));
          expect(opens, 1);

          // The Tooltip must not duplicate the explicit Semantics label, or
          // VoiceOver/TalkBack will announce "World Map" twice (once as the
          // label, once as the tooltip). With excludeFromSemantics on the
          // Tooltip, exactly one semantics node carries the label and its
          // tooltip is empty.
          final handle = tester.ensureSemantics();
          try {
            await tester.pump();
            expect(find.bySemanticsLabel('World Map'), findsOneWidget);
            expect(
              tester.getSemantics(find.bySemanticsLabel('World Map')),
              matchesSemantics(
                label: 'World Map',
                tooltip: '',
                isButton: true,
                hasEnabledState: true,
                isEnabled: true,
                hasTapAction: true,
              ),
            );
          } finally {
            handle.dispose();
          }
        },
      );

      testWidgets('semantics tap action fires the World Map callback', (
        tester,
      ) async {
        // excludeSemantics: true on the chip replaces the gesture surface's
        // tap action, so the outer Semantics must carry its own onTap or
        // screen readers cannot activate it via the accessibility double-tap.
        var opens = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: WorldMapAction(enabled: true, onWorldMap: () => opens++),
              ),
            ),
          ),
        );

        final handle = tester.ensureSemantics();
        try {
          await tester.pump();
          final data = tester.getSemantics(find.bySemanticsLabel('World Map'));
          // ignore: deprecated_member_use
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            data.id,
            SemanticsAction.tap,
          );
          expect(opens, 1);
        } finally {
          handle.dispose();
        }
      });

      testWidgets('disabled chip carries no tap action', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: WorldMapAction(enabled: false, onWorldMap: () {}),
              ),
            ),
          ),
        );

        final handle = tester.ensureSemantics();
        try {
          await tester.pump();
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
      });
    },
  );
}
