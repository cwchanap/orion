import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/acquired_run_module_control.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/mission_surface.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';

import '../support/command_deck_fixtures.dart';

const _productViewport = Size(390, 844);

Widget chromeHost(
  GameSnapshot snapshot, {
  VoidCallback? onBackgroundTap,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(
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
  expect(find.text('1x'), findsNothing);
  expect(find.text('2x'), findsNothing);
  expect(find.text('3x'), findsNothing);
  expect(find.byTooltip('Auto-start waves'), findsNothing);
  expect(find.text('Start Wave'), findsNothing);
}

/// Loads the Flutter SDK's real Roboto so text measurements in this suite
/// use proportional metrics. The host test harness otherwise falls back to
/// 1em-per-glyph placeholder glyphs, which cannot expose real truncation.
Future<void> _loadRealRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is not set; cannot load real Roboto metrics.');
  }
  final loader = FontLoader('Roboto');
  for (final file in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final fontFile = File('$root/bin/cache/artifacts/material_fonts/$file');
    if (!fontFile.existsSync()) fail('Missing SDK font: ${fontFile.path}');
    final bytes = fontFile.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('mission actions render their labels fully at product width', (
    tester,
  ) async {
    await _loadRealRoboto();
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();

    // Roboto is marginally narrower than the device's SF Pro; the regenerated
    // fixture evidence covers the device metrics. Both mission actions must
    // fit their labels at 390px width and 1.0x text scale without ellipsis.
    for (final label in const ['Start Wave', 'World Map']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason:
            '"$label" ellipsizes at 390px width; the mission actions '
            'must render their labels without truncation.',
      );
    }
  });

  testWidgets(
    'idle dock keeps pacing and the primary action on one row at product '
    'width with real fonts',
    (tester) async {
      // Placeholder test glyphs are wider than any real font and cannot
      // expose a real-font wrap; Roboto approximates the device metrics.
      await _loadRealRoboto();
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
        find.text('1x'),
        find.text('2x'),
        find.text('3x'),
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
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
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
}
