import 'package:flame/flame.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/acquired_run_module_control.dart';
import 'package:orion/game/ui/mission_chrome.dart';
import 'package:orion/game/ui/mission_command_dock.dart';
import 'package:orion/game/ui/mission_command_hud.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

const _productViewport = Size(390, 844);

Widget chromeHost(
  GameSnapshot snapshot, {
  VoidCallback? onBackgroundTap,
  VoidCallback? onWorldMap,
  TextScaler textScaler = TextScaler.noScaling,
  Color? backgroundColor,
  ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent,
  ValueChanged<Rect>? onBoardViewportChanged,
  Offset? towerAnchor,
  VoidCallback? onInspectTower,
  VoidCallback? onUpgrade,
  VoidCallback? onSell,
  ValueChanged<TowerTargetingMode>? onTargetingChanged,
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
              onWorldMap: onWorldMap ?? () {},
              onStartWave: () {},
              onTogglePause: () {},
              onSpeedSelected: (_) {},
              onToggleAutoStart: () {},
              onPlaceTower: (_) {},
              onUpgrade: onUpgrade ?? () {},
              onSpecialize: (_) {},
              onTargetingChanged: onTargetingChanged ?? (_) {},
              onSell: onSell ?? () {},
              towerAnchor: towerAnchor,
              onInspectTower: onInspectTower,
              onPlacementPreviewEvent: onPlacementPreviewEvent,
              onBoardViewportChanged: onBoardViewportChanged,
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
  expect(find.byTooltip('Start Wave'), findsNothing);
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

  testWidgets('capture scene 1a band close-up', (tester) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A close-up of the two chrome bands on a flat ground, for reading the
    // band layout without board art behind it. Scene 1a's own fixture is
    // captured from the real game page in test/widget_test.dart -- chrome
    // over a live board is what the artboard actually shows.
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
      () => captureReactorRimFixture(boundaryKey, 'fixture-1a-band.png'),
    );
  });

  for (final viewSize in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('capture boss-intel evidence fixture $viewSize', (
      tester,
    ) async {
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await loadRealFonts();
      OrionArtDescriptor.resetSpriteCache();
      await tester.runAsync(() async {
        await Flame.images.load(GameSpriteSheet.fileName);
        await Flame.images.load(GameTowerVarietySheet.fileName);
        await Flame.images.load('orion_boss_sheet.png');
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: chromeHost(
            commandDeckSnapshot(
              waveNumber: 8,
              wavesCleared: 7,
              nextWavePreview: commandDeckPreview(
                waveNumber: 8,
                groups: [
                  WavePreviewGroup(
                    enemyCount: 18,
                    label: 'Swarm Drones',
                    traits: {EnemyTrait.swarm},
                  ),
                  WavePreviewGroup(
                    enemyCount: 1,
                    label: 'Relay Breaker',
                    traits: {
                      EnemyTrait.armored,
                      EnemyTrait.shielded,
                      EnemyTrait.heavy,
                    },
                  ),
                ],
              ),
            ),
            backgroundColor: OrionUiTheme.dark.hullBlack,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      expect(find.textContaining('BOSS'), findsWidgets);
      await tester.runAsync(
        () => warmSceneImages(tester.element(find.byType(WaveScannerScene)), [
          'reactor_rim_ui/backdrops/command-center.png',
        ]),
      );
      await tester.pump();

      final suffix = viewSize.height < 700 ? '-compact' : '';
      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'fixture-boss-intel$suffix.png',
        ),
      );
      for (final finder in [
        find.bySemanticsLabel('Relay Breaker'),
        find.textContaining('BOSS'),
      ]) {
        final rect = tester.getRect(finder.first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewSize.width));
        expect(rect.bottom, lessThanOrEqualTo(viewSize.height));
      }
    });
  }

  testWidgets('compact expanded scanner lets the last counters scroll clear of '
      'START WAVE', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRealFonts();
    OrionArtDescriptor.resetSpriteCache();
    await tester.runAsync(() async {
      await Flame.images.load(GameSpriteSheet.fileName);
      await Flame.images.load(GameTowerVarietySheet.fileName);
      await Flame.images.load('orion_boss_sheet.png');
    });

    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(
          waveNumber: 8,
          wavesCleared: 7,
          stageModifiers: const [StageModifier.reinforcedArmor],
          nextWavePreview: commandDeckPreview(
            waveNumber: 8,
            groups: [
              WavePreviewGroup(
                enemyCount: 18,
                label: 'Swarm Drones',
                traits: {EnemyTrait.swarm},
              ),
              WavePreviewGroup(
                enemyCount: 1,
                label: 'Relay Breaker',
                traits: {
                  EnemyTrait.armored,
                  EnemyTrait.shielded,
                  EnemyTrait.heavy,
                },
              ),
            ],
            recommendedTowerTypes: const [
              TowerType.laser,
              TowerType.railgun,
              TowerType.ionChain,
              TowerType.gravityWell,
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(WaveScannerScene), findsOneWidget);

    final verticalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.vertical,
    );
    final scrollState = tester.state<ScrollableState>(
      find.descendant(
        of: verticalScroll,
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      ),
    );
    scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
    await tester.pump();
    final cta = tester.getRect(find.text('START WAVE'));
    final lastChip = tester.getRect(find.text('Reinforced Armor'));
    final lastCounter = tester.getRect(find.text('Gravity Well'));
    expect(
      lastChip.bottom,
      lessThanOrEqualTo(cta.top),
      reason:
          'the last scrollable row must clear the START WAVE CTA; '
          'a card left half-hidden is unreadable intel',
    );
    expect(
      lastCounter.bottom,
      lessThanOrEqualTo(cta.top),
      reason:
          'the last recommended counter must scroll fully clear of '
          'the START WAVE CTA at compact height',
    );
    expect(
      lastCounter.bottom,
      greaterThanOrEqualTo(cta.top - 140),
      reason:
          'clearance should be tight: if the counter now sits far '
          'above the CTA the scroll overshot and hid content',
    );
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets(
      'compact build controls keep Start readable at ${scale}x text',
      (tester) async {
        await loadRealFonts(withMaterialIcons: false);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          chromeHost(
            commandDeckSnapshot(nextWavePreview: commandDeckPreview()),
            textScaler: TextScaler.linear(scale),
          ),
        );
        await tester.pumpAndSettle();
        final label = tester.renderObject<RenderParagraph>(find.text('START'));
        expect(
          label.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 5),
          ),
          hasLength(1),
        );
        expect(label.didExceedMaxLines, isFalse);
        final start = tester.getRect(find.byTooltip('Start Wave'));
        expect(
          start.contains(tester.getRect(find.text('START')).topLeft),
          isTrue,
        );
        expect(
          start.contains(tester.getRect(find.text('START')).bottomRight),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('foundry boss wave shows its composition before scanning', (
    tester,
  ) async {
    await loadRealFonts(withMaterialIcons: false);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stage = OrionCampaign.stageById('asteroid-foundry');
    final wave = stage.waves.last;
    final preview = GameBalance.wavePreview(
      wave: wave,
      waveNumber: stage.waves.length,
      missionWaveTotal: stage.waves.length,
      unlockedTowerTypes: TowerType.values,
      effectiveClearBonus: wave.clearBonus,
    );
    await tester.pumpWidget(
      chromeHost(commandDeckSnapshot(nextWavePreview: preview)),
    );
    await tester.pumpAndSettle();

    expect(find.text('BOSS'), findsOneWidget);
    expect(find.text('ARMORED'), findsOneWidget);
    expect(find.text('x1'), findsOneWidget);
    expect(find.text('x10'), findsOneWidget);
    for (final label in ['BOSS', 'ARMORED', 'x1', 'x10']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
  });

  testWidgets(
    'large-text boss composition is visible without horizontal scroll',
    (tester) async {
      await loadRealFonts(withMaterialIcons: false);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final stage = OrionCampaign.stageById('asteroid-foundry');
      final wave = stage.waves.last;
      final preview = GameBalance.wavePreview(
        wave: wave,
        waveNumber: stage.waves.length,
        missionWaveTotal: stage.waves.length,
        unlockedTowerTypes: TowerType.values,
        effectiveClearBonus: wave.clearBonus,
      );
      Rect? board;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(nextWavePreview: preview),
          textScaler: const TextScaler.linear(3),
          onBoardViewportChanged: (rect) => board = rect,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['BOSS', 'ARMORED', 'HEAVY', 'x1', 'x10']) {
        expect(find.text(label), findsOneWidget);
        _expectWithinViewport(tester, find.text(label), const Size(360, 640));
        final text = find.text(label);
        for (final element
            in find
                .ancestor(of: text, matching: find.byType(Scrollable))
                .evaluate()) {
          final viewport = tester.getRect(find.byWidget(element.widget));
          final bounds = tester.getRect(text);
          expect(bounds.top, greaterThanOrEqualTo(viewport.top));
          expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(bounds.left, greaterThanOrEqualTo(viewport.left));
          expect(bounds.right, lessThanOrEqualTo(viewport.right));
        }
      }
      _expectWithinViewport(
        tester,
        find.byTooltip('Start Wave'),
        const Size(360, 640),
      );
      expect(board, isNotNull);
      expect(board!.height, greaterThan(100));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long large-text wave intel preserves the board and can scroll', (
    tester,
  ) async {
    await loadRealFonts(withMaterialIcons: false);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stage = OrionCampaign.stageById('outpost-alpha');
    final wave = stage.waves.last;
    final preview = GameBalance.wavePreview(
      wave: wave,
      waveNumber: stage.waves.length,
      missionWaveTotal: stage.waves.length,
      unlockedTowerTypes: TowerType.values,
      effectiveClearBonus: wave.clearBonus,
    );
    Rect? board;
    await tester.pumpWidget(
      chromeHost(
        commandDeckSnapshot(nextWavePreview: preview),
        textScaler: const TextScaler.linear(3),
        onBoardViewportChanged: (rect) => board = rect,
      ),
    );
    await tester.pumpAndSettle();
    expect(board, isNotNull);
    expect(board!.height, greaterThan(150));
    final intel = find.byKey(
      ValueKey('incoming-composition-${preview.waveNumber}'),
    );
    final scrollable = find.descendant(
      of: intel,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.axisDirection, AxisDirection.down);
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pumpAndSettle();
    final bossCount = tester.getRect(find.text('x1'));
    final viewport = tester.getRect(scrollable);
    expect(bossCount.top, greaterThanOrEqualTo(viewport.top));
    expect(bossCount.bottom, lessThanOrEqualTo(viewport.bottom));
    _expectWithinViewport(
      tester,
      find.byTooltip('Start Wave'),
      const Size(360, 640),
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
      chromeHost(
        commandDeckSnapshot(
          nextWavePreview: commandDeckPreview(),
          // A pending draft gates canStartWave off, so the dock's primary
          // action carries its longest label: 'START WAVE'.
          pendingRunModuleOffer: RunModuleOffer(
            offerId: 1,
            draftNumber: 1,
            draftTotal: 3,
            moduleIds: const [
              RunModuleId.heavyCaliber,
              RunModuleId.cryoReservoir,
              RunModuleId.overclockRelay,
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Roboto is marginally narrower than the device's SF Pro; the regenerated
    // fixture evidence covers the device metrics. The primary action label
    // must fit at 390px width and 1.0x text scale without ellipsis. (World
    // Map is an icon-scale chip now; its label lives in tooltip/semantics.)
    // The pill displays the label in caps, which is wider than the title
    // case it replaced -- so this fit check matters more, not less.
    final paragraph = tester.renderObject<RenderParagraph>(find.text('START'));
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason:
          '"START" ellipsizes at 390px width; the primary mission '
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
      final surfaceRect = tester.getRect(find.byType(IdleCommandBar));
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
        find.byTooltip('Auto-start waves'),
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

  testWidgets(
    'the status readouts spread across the band rather than clustering left',
    (tester) async {
      // Real fonts: the arrangement is measured in laid-out pixels, so
      // placeholder glyph metrics would measure the wrong widths.
      await loadRealFonts(withMaterialIcons: false);
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
      );
      await tester.pump();

      final band = tester.getRect(
        find.byKey(const ValueKey('mission-status-hud')),
      );
      final hull = tester.getRect(
        find.byKey(const ValueKey('mission-status-base')),
      );
      final wave = tester.getRect(
        find.byKey(const ValueKey('mission-status-stage')),
      );
      final credits = tester.getRect(
        find.byKey(const ValueKey('mission-status-credits')),
      );

      // Artboard 1a pins hull left, centres the wave group and pins credits
      // right. Position is how the player finds each reading, so assert the
      // arrangement, not merely that all three are present.
      expect(
        hull.left - band.left,
        lessThan(1),
        reason: 'the hull readout is not pinned to the band\'s left edge',
      );
      expect(
        band.right - credits.right,
        lessThan(1),
        reason: 'the credits readout is not pinned to the band\'s right edge',
      );
      expect(
        (wave.center.dx - band.center.dx).abs(),
        lessThan(band.width * 0.1),
        reason: 'the wave group is not centred in the band',
      );

      // Clustered left, the two gaps would both sit at the Wrap's 10px
      // minimum; spread, each is far wider than that.
      expect(wave.left - hull.right, greaterThan(24));
      expect(credits.left - wave.right, greaterThan(24));
    },
  );

  testWidgets('the status readouts stay on one row', (tester) async {
    // Hero-scale numerals can wrap the credits behind the band buttons.
    // Use the real face because a narrower test font would miss it.
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

    final readouts = [
      'mission-status-base',
      'mission-status-stage',
      'mission-status-credits',
    ].map((key) => tester.getRect(find.byKey(ValueKey(key)))).toList();
    for (final readout in readouts.skip(1)) {
      expect(
        readout.top,
        lessThan(readouts.first.bottom),
        reason: 'a status readout wrapped off the band row',
      );
      expect(
        readout.bottom,
        greaterThan(readouts.first.top),
        reason: 'a status readout wrapped off the band row',
      );
    }

    // And the run must clear the band's trailing actions.
    final credits = tester.getRect(
      find.byKey(const ValueKey('mission-status-credits')),
    );
    final worldMap = tester.getRect(find.byTooltip('World Map'));
    expect(
      credits.bottom,
      lessThanOrEqualTo(worldMap.top),
      reason: 'the utility row must stay below the readouts',
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

    final worldMapTop = tester.getTopLeft(find.byTooltip('World Map')).dy;
    expect(worldMapTop, greaterThanOrEqualTo(dockTop));

    // The idle dock hosts pacing plus the primary action.
    expect(find.byTooltip('Pause'), findsOneWidget);
    // One speed button, showing the current speed and cycling on tap.
    expect(find.byTooltip('Game speed'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byTooltip('Auto-start waves'), findsOneWidget);
    expect(find.byTooltip('Start Wave'), findsOneWidget);

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

  testWidgets(
    'board viewport reserves below the acquired-module control without a scanner',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Rect? viewport;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            phase: GamePhase.wave,
            acquiredRunModules: const [RunModuleId.heavyCaliber],
          ),
          onBoardViewportChanged: (rect) => viewport = rect,
        ),
      );
      await tester.pump();
      await tester.pump();

      // The scanner is gone during a wave; the viewport must still clear the
      // module control, not just the HUD.
      expect(find.byType(NextWaveScanner), findsNothing);
      final modulesBottom = tester
          .getBottomLeft(find.byType(AcquiredRunModuleControl))
          .dy;
      expect(viewport, isNotNull);
      expect(viewport!.top, greaterThanOrEqualTo(modulesBottom));
    },
  );

  testWidgets(
    'board viewport tracks module expansion and recovers on collapse',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Rect? viewport;
      Widget host() => chromeHost(
        commandDeckSnapshot(
          phase: GamePhase.wave,
          acquiredRunModules: const [RunModuleId.heavyCaliber],
        ),
        onBoardViewportChanged: (rect) => viewport = rect,
      );
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();

      final collapsedTop = viewport!.top;
      final collapsedBottom = tester
          .getBottomLeft(find.byType(AcquiredRunModuleControl))
          .dy;
      expect(collapsedTop, greaterThanOrEqualTo(collapsedBottom));

      // Expanding toggles inside the control's own setState — MissionChrome
      // does not rebuild, but the viewport must still re-measure so the
      // board never starts under the expanded panel.
      await tester.tap(
        find.byKey(const ValueKey('acquired-modules-collapsed')),
      );
      await tester.pump();
      await tester.pump();
      final expandedBottom = tester
          .getBottomLeft(find.byType(AcquiredRunModuleControl))
          .dy;
      expect(viewport!.top, greaterThanOrEqualTo(expandedBottom));
      expect(viewport!.top, greaterThan(collapsedTop));

      // An unrelated snapshot rebuild while expanded must not bake the
      // expanded height into the baseline reserve…
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(viewport!.top, greaterThanOrEqualTo(expandedBottom));

      // …so collapsing releases it again.
      await tester.tap(find.byKey(const ValueKey('acquired-modules-expanded')));
      await tester.pump();
      await tester.pump();
      expect(viewport!.top, collapsedTop);
    },
  );

  testWidgets(
    'selecting a cell keeps the board viewport identical and never lets '
    'the relocated scanner overlap it',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final viewports = <Rect>[];
      Widget host(GameSnapshot snapshot) =>
          chromeHost(snapshot, onBoardViewportChanged: viewports.add);

      final idle = commandDeckSnapshot(nextWavePreview: commandDeckPreview());
      await tester.pumpWidget(host(idle));
      await tester.pump();
      await tester.pump();
      final idleViewport = viewports.last;

      var scannerRect = tester.getRect(find.byType(NextWaveScanner));
      expect(
        scannerRect.overlaps(idleViewport),
        isFalse,
        reason: 'the dock-mounted scanner must stay clear of the board',
      );

      await tester.pumpWidget(
        host(
          commandDeckSnapshot(
            nextWavePreview: commandDeckPreview(),
            selectedCell: const GridPosition(4, 5),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        viewports.last,
        idleViewport,
        reason:
            'the board must hold its viewport while the scanner relocates; '
            'a reserve that grows the top edge shrinks the playfield',
      );
      scannerRect = tester.getRect(find.byType(NextWaveScanner));
      expect(
        scannerRect.overlaps(viewports.last),
        isFalse,
        reason:
            'wherever the scanner lands during selection it must not '
            'cover board cells',
      );

      await tester.pumpWidget(host(idle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        viewports.last,
        idleViewport,
        reason:
            'idle → selected → idle must return the exact viewport '
            'rectangle',
      );
      scannerRect = tester.getRect(find.byType(NextWaveScanner));
      expect(
        scannerRect.overlaps(viewports.last),
        isFalse,
        reason:
            'the scanner back in the dock must not cover board cells '
            'either',
      );
    },
  );

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
      await tester.tap(find.text('Modules 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
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
    'a selection disables the collapsed scanner and deselection restores it',
    (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        final viewports = <Rect>[];
        Widget host(GameSnapshot snapshot) =>
            chromeHost(snapshot, onBoardViewportChanged: viewports.add);
        final idle = commandDeckSnapshot(nextWavePreview: commandDeckPreview());
        const scannerSemantics = ValueKey(
          'next-wave-scanner-collapsed-semantics',
        );

        Future<void> expectScannerEnabled(bool enabled) async {
          final node = find.byKey(scannerSemantics);
          expect(node, findsOneWidget);
          expect(
            tester.getSemantics(node),
            matchesSemantics(
              isButton: true,
              hasEnabledState: true,
              isEnabled: enabled,
              hasTapAction: enabled,
            ),
          );
        }

        await tester.pumpWidget(host(idle));
        await tester.pump();
        await tester.pump();
        final idleViewport = viewports.last;
        await expectScannerEnabled(true);

        await tester.tap(find.byTooltip('Expand next-wave scanner'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('next-wave-scanner-expanded')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Collapse next-wave scanner'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('next-wave-scanner-expanded')),
          findsNothing,
        );

        Future<void> expectCollapsedAndDisabled() async {
          expect(
            find.byKey(const ValueKey('next-wave-scanner-collapsed')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('next-wave-scanner-expanded')),
            findsNothing,
          );
          await expectScannerEnabled(false);
          final scanner = find.byType(NextWaveScanner);
          final blocker = find.descendant(
            of: scanner,
            matching: find.byWidgetPredicate(
              (widget) => widget is IgnorePointer && widget.ignoring,
            ),
          );
          expect(
            blocker,
            findsOneWidget,
            reason: 'a selected cell must leave the scanner untappable',
          );
          await tester.tap(
            find.byTooltip('Expand next-wave scanner'),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('next-wave-scanner-expanded')),
            findsNothing,
            reason: 'the disabled scanner must ignore expand taps',
          );
        }

        await tester.pumpWidget(
          host(
            commandDeckSnapshot(
              nextWavePreview: commandDeckPreview(),
              selectedCell: const GridPosition(4, 5),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await expectCollapsedAndDisabled();
        expect(
          viewports.last,
          idleViewport,
          reason: 'selection must not move or resize the board viewport',
        );

        const tower = PlacedTower(
          id: 1,
          type: TowerType.laser,
          position: GridPosition(4, 5),
        );
        await tester.pumpWidget(
          host(
            commandDeckSnapshot(
              nextWavePreview: commandDeckPreview(),
              selectedTower: tower,
              selectedTowerStats: GameBalance.towerStats(
                tower.type,
                level: tower.level,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await expectCollapsedAndDisabled();
        expect(
          viewports.last,
          idleViewport,
          reason: 'tower selection must not move the viewport either',
        );

        await tester.pumpWidget(host(idle));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await expectScannerEnabled(true);
        await tester.tap(find.byTooltip('Expand next-wave scanner'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('next-wave-scanner-expanded')),
          findsOneWidget,
          reason: 'the scanner must expand again once selection clears',
        );
        expect(
          viewports.last,
          idleViewport,
          reason: 'idle → selected → idle must return the same viewport',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('top panels leave the dock World Map action available', (
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
        ),
      ),
    );
    await tester.pump();

    // Idle with no panel expanded: World Map is present.
    expect(find.byTooltip('World Map'), findsOneWidget);

    // Expanding the scanner keeps the dock's World Map action available.
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );
    expect(find.byTooltip('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse next-wave scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modules 2'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('acquired-modules-expanded')),
      findsOneWidget,
    );
    expect(find.byTooltip('World Map'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse acquired modules'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('acquired-modules-expanded')),
      findsNothing,
    );
    expect(find.byTooltip('World Map'), findsOneWidget);
  });

  testWidgets('a scanner-preview reset keeps the modules panel expanded', (
    tester,
  ) async {
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

    await tester.tap(find.text('Modules 2'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('acquired-modules-expanded')),
      findsOneWidget,
    );
    expect(find.byTooltip('World Map'), findsOneWidget);

    // A new scanner preview must not collapse the modules panel.
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
    expect(find.byTooltip('World Map'), findsOneWidget);
  });

  testWidgets('a module-list reset keeps the scanner panel expanded', (
    tester,
  ) async {
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

    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );
    expect(find.byTooltip('World Map'), findsOneWidget);

    // A changed module list must not collapse the scanner.
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
    expect(find.byTooltip('World Map'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
      _expectWithinViewport(
        tester,
        find.byKey(const ValueKey('command-dock-persistent-rail')),
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
      // Scroll until it is actually visible rather than by a fixed distance:
      // a -400 drag was calibrated to the old 64dp card and silently stopped
      // 22px short once the artboard's 70dp card widened the rail.
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('tower-card-${TowerType.values.last.name}')),
        120,
        scrollable: find.byType(Scrollable).first,
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
      expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('command-dock-persistent-rail')),
        findsOneWidget,
      );
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

    final mapRect = tester.getRect(find.byTooltip('World Map'));
    final scannerRect = tester.getRect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
    );
    expect(mapRect.width, inInclusiveRange(48, 60));
    expect(mapRect.height, inInclusiveRange(48, 60));
    expect(
      mapRect.top,
      greaterThan(scannerRect.bottom),
      reason: 'World Map belongs in the dock, clear of the top board cells.',
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

  group('world map reachability (HPA-699)', () {
    Future<void> expectWorldMapEnabled(WidgetTester tester) async {
      expect(find.byTooltip('World Map'), findsOneWidget);
      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('World Map')),
          matchesSemantics(
            label: 'World Map',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    }

    Future<void> expectNoWorldMapExit(WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        final chip = find.bySemanticsLabel('World Map');
        if (chip.evaluate().isEmpty) return;
        expect(
          tester.getSemantics(chip.first),
          matchesSemantics(
            label: 'World Map',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
          reason: 'an active wave must never offer an actionable map exit',
        );
      } finally {
        handle.dispose();
      }
    }

    testWidgets('build phase keeps World Map reachable with nothing selected', (
      tester,
    ) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var mapTaps = 0;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(nextWavePreview: commandDeckPreview()),
          onWorldMap: () => mapTaps += 1,
        ),
      );
      await tester.pump();

      await expectWorldMapEnabled(tester);
      await tester.tap(find.byTooltip('World Map'));
      await tester.pump();
      expect(mapTaps, 1);
    });

    testWidgets(
      'build phase keeps World Map reachable with a build cell selected',
      (tester) async {
        tester.view.physicalSize = _productViewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        var mapTaps = 0;
        await tester.pumpWidget(
          chromeHost(
            commandDeckSnapshot(
              selectedCell: const GridPosition(2, 2),
              nextWavePreview: commandDeckPreview(),
            ),
            onWorldMap: () => mapTaps += 1,
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('command-dock-build')),
          findsOneWidget,
        );
        await expectWorldMapEnabled(tester);
        await tester.tap(find.byTooltip('World Map'));
        await tester.pump();
        expect(mapTaps, 1);
      },
    );

    testWidgets('build phase keeps World Map reachable with a tower selected', (
      tester,
    ) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(1, 1),
      );
      var mapTaps = 0;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(
            selectedTower: tower,
            selectedTowerStats: GameBalance.towerStats(
              tower.type,
              level: tower.level,
            ),
            nextWavePreview: commandDeckPreview(),
          ),
          onWorldMap: () => mapTaps += 1,
        ),
      );
      await tester.pump();

      await expectWorldMapEnabled(tester);
      await tester.tap(find.byTooltip('World Map'));
      await tester.pump();
      expect(mapTaps, 1);
    });

    testWidgets('an active wave never exposes an actionable map exit', (
      tester,
    ) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var mapTaps = 0;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(phase: GamePhase.wave),
          onWorldMap: () => mapTaps += 1,
        ),
      );
      await tester.pump();

      await expectNoWorldMapExit(tester);
      final chip = find.byTooltip('World Map');
      if (chip.evaluate().isNotEmpty) {
        await tester.tap(chip, warnIfMissed: false);
        await tester.pump();
      }
      expect(mapTaps, 0);
    });

    testWidgets('a paused wave never exposes an actionable map exit', (
      tester,
    ) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var mapTaps = 0;
      await tester.pumpWidget(
        chromeHost(
          commandDeckSnapshot(phase: GamePhase.wave, isPaused: true),
          onWorldMap: () => mapTaps += 1,
        ),
      );
      await tester.pump();

      await expectNoWorldMapExit(tester);
      final chip = find.byTooltip('World Map');
      if (chip.evaluate().isNotEmpty) {
        await tester.tap(chip, warnIfMissed: false);
        await tester.pump();
      }
      expect(mapTaps, 0);
    });

    testWidgets('pre-wave intel shares the Start Wave band', (tester) async {
      tester.view.physicalSize = _productViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        chromeHost(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
      );
      await tester.pump();

      final intel = tester.getRect(find.byType(NextWaveScanner));
      final start = tester.getRect(find.byTooltip('Start Wave'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('incoming-wave-summary')),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      expect(
        (intel.center.dy - start.center.dy).abs(),
        lessThan(40),
        reason:
            'the kit rows intel beside the Start action; the scanner still '
            'sits in the top band while Start anchors the dock',
      );
      expect(
        intel.right,
        lessThanOrEqualTo(start.left + 8),
        reason: 'the intel panel reads left of the Start action',
      );
    });
  });

  testWidgets('idle, selected, then idle again never moves the board '
      'viewport while the scanner stays dock-hosted', (tester) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final viewports = <Rect>[];
    Widget host(GameSnapshot snapshot) =>
        chromeHost(snapshot, onBoardViewportChanged: viewports.add);

    await tester.pumpWidget(
      host(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();
    await tester.pump();
    final idleViewport = viewports.last;

    await tester.pumpWidget(
      host(
        commandDeckSnapshot(
          nextWavePreview: commandDeckPreview(),
          selectedCell: const GridPosition(1, 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(NextWaveScanner), findsOneWidget);
    expect(
      viewports.last,
      idleViewport,
      reason:
          'the scanner stays dock-hosted through the selection now — '
          'the board viewport must not move at all',
    );

    await tester.pumpWidget(
      host(commandDeckSnapshot(nextWavePreview: commandDeckPreview())),
    );
    await tester.pump();
    await tester.pump();

    expect(
      viewports.last,
      idleViewport,
      reason:
          'selection moved the scanner back under the HUD but the '
          'top reserve never recovered: the board viewport stayed '
          'compressed after the selection cleared',
    );
  });

  group('tower radial actions (HPA-699 restyle contract)', () {
    GameSnapshot radialSnapshot({GamePhase phase = GamePhase.build}) =>
        commandDeckSnapshot(
          phase: phase,
          selectedTower: const PlacedTower(
            id: 8,
            type: TowerType.laser,
            position: GridPosition(4, 5),
          ),
          selectedTowerStats: GameBalance.towerStats(TowerType.laser, level: 1),
        );

    testWidgets('mounted radial keeps its four actions wired inside the '
        'viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var upgrades = 0;
      var inspects = 0;
      var sells = 0;
      final targeting = <TowerTargetingMode>[];
      await tester.pumpWidget(
        chromeHost(
          radialSnapshot(),
          towerAnchor: const Offset(180, 400),
          onInspectTower: () => inspects++,
          onUpgrade: () => upgrades++,
          onSell: () => sells++,
          onTargetingChanged: targeting.add,
        ),
      );
      await tester.pump();
      await tester.pump();

      final radial = find.byType(TowerRadialActions);
      expect(radial, findsOneWidget);
      final rect = tester.getRect(radial);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(640));

      final upgradeCost = GameBalance.towerStats(
        TowerType.laser,
        level: 1,
      ).upgradeCost;
      await tester.tap(find.byTooltip('Upgrade $upgradeCost'));
      await tester.tap(find.byTooltip('Inspect tower'));
      await tester.tap(find.byTooltip('Targeting: First. Change targeting'));
      expect(upgrades, 1);
      expect(inspects, 1);
      expect(targeting, [TowerTargetingMode.strongest]);

      expect(find.byKey(const ValueKey('radial-salvage-8')), findsOneWidget);
      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-sell'))),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 900));
      await hold.up();
      expect(sells, 1);
    });

    testWidgets('radial mutations disable outside build phase while inspect '
        'stays live', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var sells = 0;
      final targeting = <TowerTargetingMode>[];
      await tester.pumpWidget(
        chromeHost(
          radialSnapshot(phase: GamePhase.wave),
          towerAnchor: const Offset(180, 400),
          onInspectTower: () {},
          onSell: () => sells++,
          onTargetingChanged: targeting.add,
        ),
      );
      await tester.pump();
      await tester.pump();

      IconButton buttonFor(String tooltip) => tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        ),
      );

      final upgradeCost = GameBalance.towerStats(
        TowerType.laser,
        level: 1,
      ).upgradeCost;
      expect(buttonFor('Upgrade $upgradeCost').onPressed, isNull);
      expect(buttonFor('Targeting: First. Change targeting').onPressed, isNull);
      expect(buttonFor('Inspect tower').onPressed, isNotNull);

      final salvage = tester.widget<Semantics>(
        find.byKey(const ValueKey('tower-sell-semantics')),
      );
      expect(salvage.properties.enabled, isFalse);

      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tower-sell'))),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 900));
      await hold.up();
      expect(sells, 0);
      expect(targeting, isEmpty);
    });
  });
}
