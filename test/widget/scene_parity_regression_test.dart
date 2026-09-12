import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';
import '../widget_test.dart' as fixtures;
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/tower_inspector.dart';
import 'package:orion/game/ui/world_map_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<OrionDefenseGame> _startRadialMission(
  WidgetTester tester,
  GlobalKey boundary,
  double scale, {
  Size viewport = const Size(360, 640),
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await loadRealFonts();
  await tester.runAsync(() async {
    for (final name in [
      'reactor_rim_ui/boards/nebula.png',
      'orion_path_tiles.png',
      'orion_sprite_sheet.png',
      'orion_tower_variety_sheet.png',
      'orion_boss_sheet.png',
    ]) {
      await Flame.images.load(name);
    }
  });
  OrionArtDescriptor.resetSpriteCache();
  OrionDefenseGame? game;
  final host =
      fixtures.testGamePage(onGameCreated: (g) => game = g) as MaterialApp;
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: host.theme!.copyWith(platform: platform),
        home: host.home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await fixtures.startStageFromBriefing(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(game!.isMounted, isTrue);
  game!.handleBoardTap(game!.boardCellCenter(const GridPosition(4, 5)));
  game!.placeTower(TowerType.laser);
  game!.handleBoardTap(game!.boardCellCenter(const GridPosition(4, 5)));
  await tester.pump();
  await tester.pump();
  return game!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    testWidgets('radial upgrade at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadRealFonts();
      final boundary = GlobalKey();
      final tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(4, 5),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: orionThemeData,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: TowerRadialActions(
                  snapshot: commandDeckSnapshot(
                    selectedTower: tower,
                    selectedTowerStats: GameBalance.towerStats(
                      TowerType.laser,
                      level: 1,
                    ),
                  ),
                  onUpgrade: () {},
                  onInspect: () {},
                  onSell: () {},
                  onTargetingChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final error = tester.takeException();
      await tester.runAsync(
        () => captureReactorRimFixture(boundary, 'radial-text-$scale.png'),
      );
      expect(
        error,
        isNull,
        reason: 'Upgrade cost must fit at the requested text scale.',
      );
    });
  }
  testWidgets('retry clears the old inspector identity', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRealFonts();
    await tester.runAsync(() async {
      for (final name in [
        'reactor_rim_ui/boards/nebula.png',
        'orion_path_tiles.png',
        'orion_sprite_sheet.png',
        'orion_tower_variety_sheet.png',
        'orion_boss_sheet.png',
      ]) {
        await Flame.images.load(name);
      }
    });
    OrionArtDescriptor.resetSpriteCache();
    OrionDefenseGame? game;
    await tester.pumpWidget(
      fixtures.testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await fixtures.startStageFromBriefing(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(game!.isMounted, isTrue);
    void placeAndSelect() {
      game!.handleBoardTap(game!.boardCellCenter(const GridPosition(4, 5)));
      game!.placeTower(TowerType.laser);
      game!.handleBoardTap(game!.boardCellCenter(const GridPosition(4, 5)));
    }

    placeAndSelect();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Inspect tower'));
    await tester.pump();
    expect(find.byType(TowerInspector), findsOneWidget);
    game!.stateNotifier.value = commandDeckSnapshot(
      phase: GamePhase.lost,
      baseHealth: 0,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(game!.snapshot.phase, GamePhase.build);
    placeAndSelect();
    await tester.pump();
    await tester.pump();
    final openInspectors = find.byType(TowerInspector).evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    Flame.images.clearCache();
    expect(
      openInspectors,
      0,
      reason:
          'Selecting a new-attempt tower must show its radial, not reopen the old inspector.',
    );
  });

  for (final scene in ['scanner', 'map']) {
    for (final scale in [1.0, 3.0]) {
      testWidgets('$scene at 360x640 and text $scale', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadRealFonts();
        OrionArtDescriptor.resetSpriteCache();
        await tester.runAsync(() async {
          for (final path in [
            'orion_sprite_sheet.png',
            'orion_tower_variety_sheet.png',
            'orion_boss_sheet.png',
          ]) {
            await Flame.images.load(path);
          }
          if (scene == 'map') {
            await Flame.images.load('reactor_rim_ui/backdrops/world-map.png');
            for (final stage in OrionCampaign.stages) {
              await Flame.images.load('reactor_rim_ui/stages/${stage.id}.png');
              await Flame.images.load('reactor_rim_ui/crests/${stage.id}.png');
            }
          }
        });
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previous);
        final boundary = GlobalKey();
        final Widget content;
        switch (scene) {
          case 'scanner':
            content = WaveScannerScene(
              preview: commandDeckPreview(),
              modifierTitles: const ['Standard Conditions'],
              stageId: 'outpost-alpha',
              onClose: () {},
              onStartWave: () {},
            );
          case 'map':
            content = WorldMapView(
              stages: OrionCampaign.stages,
              progress: CampaignProgress(),
              feedback: null,
              onStageSelected: (_) {},
              onResetCampaign: () {},
              onOpenTechTree: () {},
              onOpenCodex: () {},
              onOpenSettings: () {},
            );
          default:
            throw StateError('Unknown review scene: $scene');
        }
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: orionThemeData,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(body: content),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await warmSceneImages(tester.element(find.byType(Scaffold)), [
            if (scene == 'scanner')
              'reactor_rim_ui/backdrops/command-center.png',
            if (scene == 'map') 'reactor_rim_ui/backdrops/map-room.png',
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => captureReactorRimFixture(boundary, '$scene-text-$scale.png'),
        );
        bool? obscuresAlpha;
        if (scene == 'map') {
          final destination = find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Briefing for Outpost Alpha',
          );
          final panel = find.ancestor(
            of: destination,
            matching: find.byType(OrionSurface),
          );
          final footer = tester.getRect(panel);
          final alpha = tester.getRect(
            find.byKey(const ValueKey('sector-stage-outpost-alpha')),
          );
          obscuresAlpha = footer.overlaps(alpha);
        }
        FlutterError.onError = previous;
        expect(
          errors.map((e) => e.exceptionAsString()).toList(),
          isEmpty,
          reason: 'Scene must render without layout errors.',
        );
        if (obscuresAlpha != null) {
          expect(
            obscuresAlpha,
            isFalse,
            reason:
                'The destination panel must not cover the first playable map node.',
          );
        }
      });
    }
  }

  testWidgets('expanded scanner blocks the real underlying Auto control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var autoToggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: Scaffold(
          body: MissionChrome(
            snapshot: commandDeckSnapshot(
              nextWavePreview: commandDeckPreview(),
            ),
            onBoardTapIntercept: (_) => false,
            onWorldMap: () {},
            onStartWave: () {},
            onTogglePause: () {},
            onSpeedSelected: (_) {},
            onToggleAutoStart: () => autoToggles++,
            onPlaceTower: (_) {},
            onUpgrade: () {},
            onSpecialize: (_) {},
            onTargetingChanged: (_) {},
            onSell: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final autoFocus = Focus.of(tester.element(find.text('Auto')));
    autoFocus.requestFocus();
    await tester.pump();
    expect(autoFocus.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(WaveScannerScene), findsOneWidget);
    expect(autoFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      autoToggles,
      0,
      reason:
          'The full-screen scanner must prevent activation of the obscured Auto control.',
    );
    await tester.pumpAndSettle();
    expect(find.byType(WaveScannerScene), findsNothing);
    expect(autoFocus.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        autoFocus.hasFocus,
        isFalse,
        reason: 'Traversal must stay in the scanner.',
      );
    }
    await tester.tap(find.byTooltip('Collapse next-wave scanner'));
    await tester.pumpAndSettle();
    expect(autoFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(autoToggles, 1, reason: 'Closing restores keyboard use of Auto.');
  });

  testWidgets('radial cycles all targeting modes only during build', (
    tester,
  ) async {
    await loadRealFonts();
    for (final phase in [GamePhase.build, GamePhase.wave]) {
      for (final mode in TowerTargetingMode.values) {
        final calls = <TowerTargetingMode>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: orionThemeData,
            home: Scaffold(
              body: Center(
                child: TowerRadialActions(
                  snapshot: commandDeckSnapshot(
                    phase: phase,
                    selectedTower: PlacedTower(
                      id: 1,
                      type: TowerType.laser,
                      position: const GridPosition(4, 5),
                      targetingMode: mode,
                    ),
                    selectedTowerStats: GameBalance.towerStats(
                      TowerType.laser,
                      level: 1,
                    ),
                  ),
                  onUpgrade: () {},
                  onInspect: () {},
                  onSell: () {},
                  onTargetingChanged: calls.add,
                ),
              ),
            ),
          ),
        );
        expect(find.text(mode.label.toUpperCase()), findsOneWidget);
        await tester.tap(
          find.byTooltip('Targeting: ${mode.label}. Change targeting'),
        );
        expect(
          calls,
          phase == GamePhase.build
              ? [
                  TowerTargetingMode.values[(mode.index + 1) %
                      TowerTargetingMode.values.length],
                ]
              : isEmpty,
        );
      }
    }
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    for (final action in ['gap tap', 'selected tower long press']) {
      testWidgets('mounted radial preserves $action with ${kind.name}', (
        tester,
      ) async {
        final boundary = GlobalKey();
        final game = await _startRadialMission(
          tester,
          boundary,
          1,
          platform: kind == PointerDeviceKind.mouse
              ? TargetPlatform.macOS
              : TargetPlatform.android,
        );
        final radial = find.byType(TowerRadialActions);
        final rect = tester.getRect(radial);
        await tester.runAsync(
          () => captureReactorRimFixture(boundary, 'mounted-radial.png'),
        );
        if (action == 'gap tap') {
          const cell = GridPosition(2, 2);
          final point = game.boardCellCenter(cell);
          expect(rect.contains(point), isTrue);
          for (final element
              in find
                  .descendant(of: radial, matching: find.byType(IconButton))
                  .evaluate()) {
            final control = tester.getRect(find.byWidget(element.widget));
            expect(control.contains(point), isFalse);
          }
          await tester.tapAt(point, kind: kind);
          // Flame's multi-tap tracker keeps a 40 ms gesture timer.
          await tester.pump(const Duration(milliseconds: 50));
          final actual = game.snapshot.selectedCell;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(
            actual,
            cell,
            reason: 'A transparent radial gap must pass the board tap through.',
          );
        } else {
          await tester.longPressAt(
            game.boardCellCenter(const GridPosition(4, 5)),
            kind: kind,
          );
          await tester.pump();
          final count = find.byType(TowerInspector).evaluate().length;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(
            count,
            1,
            reason:
                'Long pressing the selected tower must still open its inspector.',
          );
        }
      });
    }
  }
  testWidgets('board input works outside the radial rectangle', (tester) async {
    final game = await _startRadialMission(tester, GlobalKey(), 1);
    const outside = GridPosition(0, 0);
    final point = game.boardCellCenter(outside);
    expect(
      tester.getRect(find.byType(TowerRadialActions)).contains(point),
      isFalse,
    );
    await tester.tapAt(point);
    await tester.pump();
    expect(game.snapshot.selectedCell, outside);
    await tester.longPressAt(game.boardCellCenter(const GridPosition(4, 5)));
    await tester.pump();
    expect(find.byType(TowerInspector), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    testWidgets('mounted radial stays above actual dock at text $scale', (
      tester,
    ) async {
      final boundary = GlobalKey();
      final game = await _startRadialMission(tester, boundary, scale);
      // Move the selected tower near the bottom to exercise the radial clamp.
      game.handleBoardTap(game.boardCellCenter(const GridPosition(4, 10)));
      game.placeTower(TowerType.laser);
      game.handleBoardTap(game.boardCellCenter(const GridPosition(4, 10)));
      await tester.pump();
      await tester.pump();
      final dock = tester.getRect(find.byType(MissionCommandDock));
      final target = find.byTooltip('Targeting: First. Change targeting');
      final targetRect = tester.getRect(target);
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundary,
          'mounted-bottom-radial-$scale.png',
        ),
      );
      await tester.tap(target);
      await tester.pump();
      final mode = game.snapshot.selectedTower?.targetingMode;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        targetRect.overlaps(dock),
        isFalse,
        reason: 'The targeting control must stay above the measured dock.',
      );
      expect(mode, TowerTargetingMode.strongest);
    });
  }

  testWidgets(
    'constrained radial scrolls to targeting without covering the dock',
    (tester) async {
      final boundary = GlobalKey();
      final game = await _startRadialMission(
        tester,
        boundary,
        3,
        viewport: const Size(320, 568),
      );
      final target = find.byTooltip('Targeting: First. Change targeting');
      await tester.drag(find.byTooltip('Upgrade 70'), const Offset(0, -140));
      await tester.pump();
      final targetRect = tester.getRect(target);
      final dock = tester.getRect(find.byType(MissionCommandDock));
      expect(targetRect.bottom, lessThanOrEqualTo(dock.top));
      await tester.tap(target);
      await tester.pump();
      expect(
        game.snapshot.selectedTower?.targetingMode,
        TowerTargetingMode.strongest,
      );
      final changedTarget = tester.getRect(
        find.byTooltip('Targeting: Strongest. Change targeting'),
      );
      expect(changedTarget.bottom, lessThanOrEqualTo(dock.top));
      expect(changedTarget.left, greaterThanOrEqualTo(8));
      expect(changedTarget.right, lessThanOrEqualTo(312));
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundary,
          'mounted-radial-scrolled-320.png',
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('inspector keyboard focus enters the open modal', (tester) async {
    final boundary = GlobalKey();
    final game = await _startRadialMission(
      tester,
      boundary,
      1,
      platform: TargetPlatform.macOS,
    );
    final previousFocus = FocusManager.instance.primaryFocus;
    await tester.longPressAt(
      game.boardCellCenter(const GridPosition(4, 5)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(find.byType(TowerInspector), findsOneWidget);
    final inspector = tester.element(find.byType(TowerInspector));
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final context = FocusManager.instance.primaryFocus?.context;
      var inside = context == inspector;
      context?.visitAncestorElements((element) {
        if (element == inspector) inside = true;
        return !inside;
      });
      expect(
        inside,
        isTrue,
        reason: 'Traversal must stay inside the inspector.',
      );
    }
    await tester.tap(find.byTooltip('Close tower inspector'));
    await tester.pump();
    expect(find.byType(TowerInspector), findsNothing);
    expect(FocusManager.instance.primaryFocus, same(previousFocus));
    await tester.longPressAt(
      game.boardCellCenter(const GridPosition(4, 5)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(TowerInspector), findsNothing);
    expect(FocusManager.instance.primaryFocus, same(previousFocus));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  for (final scale in [1.0, 3.0]) {
    testWidgets('specialized radial salvage amount fits at text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadRealFonts();
      final boundary = GlobalKey();
      final tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: const GridPosition(4, 5),
        level: 3,
        specialization: GameBalance.specializationsFor(TowerType.laser).first,
      );
      final errors = <FlutterErrorDetails>[];
      final prior = FlutterError.onError;
      FlutterError.onError = errors.add;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: orionThemeData,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: TowerRadialActions(
                  snapshot: commandDeckSnapshot(
                    selectedTower: tower,
                    selectedTowerStats: GameBalance.towerStats(
                      TowerType.laser,
                      level: 3,
                      specialization: tower.specialization,
                    ),
                  ),
                  onUpgrade: () {},
                  onInspect: () {},
                  onSell: () {},
                  onTargetingChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => captureReactorRimFixture(boundary, 'review5-salvage-$scale.png'),
      );
      FlutterError.onError = prior;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        errors.map((e) => e.exceptionAsString()).toList(),
        isEmpty,
        reason: 'The full real salvage refund must fit the radial control.',
      );
    });
  }
}
