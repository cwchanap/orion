import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/run_module_draft_panel.dart';

import '../support/command_deck_fixtures.dart';

const _productViewport = Size(390, 844);

Widget chromeHost(GameSnapshot snapshot, {VoidCallback? onBackgroundTap}) {
  return MaterialApp(
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

void main() {
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
    expect(find.byType(AcquiredRunModuleStrip), findsOneWidget);
    expect(find.byType(NextWaveScanner), findsOneWidget);

    // The toast band sits above the command dock, never beside or below it.
    final toastBottom = tester
        .getBottomRight(find.byKey(const ValueKey('mission-command-toast')))
        .dy;
    final dockTop = tester.getTopLeft(find.byType(MissionCommandDock)).dy;
    expect(toastBottom, lessThanOrEqualTo(dockTop));

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

  testWidgets('acquired module strip exists only when modules exist', (
    tester,
  ) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(chromeHost(commandDeckSnapshot()));
    await tester.pump();
    expect(find.byType(AcquiredRunModuleStrip), findsNothing);

    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(
          acquiredRunModules: const [RunModuleId.heavyCaliber],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AcquiredRunModuleStrip), findsOneWidget);
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
}
