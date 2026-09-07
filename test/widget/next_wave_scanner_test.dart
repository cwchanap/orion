import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/mission_surface.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

import '../support/command_deck_fixtures.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

Widget scannerHost(
  WavePreview preview, {
  bool disableAnimations = false,
  bool collapseRequested = false,
  List<String> modifierTitles = const ['Standard Conditions'],
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Align(
        alignment: Alignment.topRight,
        child: NextWaveScanner(
          preview: preview,
          modifierTitles: modifierTitles,
          collapseRequested: collapseRequested,
        ),
      ),
    ),
  );
}

/// Representative scene 1c preview: a multi-group convoy with traits, a
/// clear bonus, tower recommendations, and a stage modifier.
WavePreview representativePreview() {
  return WavePreview(
    waveNumber: 4,
    waveTotal: 8,
    groups: [
      WavePreviewGroup(
        enemyCount: 12,
        label: 'Armored Drones',
        traits: {EnemyTrait.armored, EnemyTrait.shielded},
      ),
      WavePreviewGroup(
        enemyCount: 4,
        label: 'Heavy Drones',
        traits: {EnemyTrait.heavy},
      ),
      WavePreviewGroup(enemyCount: 6, label: 'Drones', traits: const {}),
    ],
    traits: {EnemyTrait.armored, EnemyTrait.shielded, EnemyTrait.heavy},
    clearBonus: 45,
    recommendedTowerTypes: const [TowerType.railgun, TowerType.cryo],
  );
}

void main() {
  testWidgets(
    'scanner starts collapsed and a new preview resets it to collapsed',
    (tester) async {
      final first = commandDeckPreview(waveNumber: 1);
      await tester.pumpWidget(scannerHost(first));
      expect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        ),
        const Size(48, 48),
      );
      expect(
        find.bySemanticsLabel(RegExp('New wave preview available')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );

      await tester.pumpWidget(scannerHost(first));
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );

      await tester.pumpWidget(scannerHost(commandDeckPreview(waveNumber: 2)));
      expect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'collapsed radar center expands even when the intercept hook claims',
    (tester) async {
      var interceptedPositions = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topRight,
            child: NextWaveScanner(
              preview: commandDeckPreview(),
              modifierTitles: const ['Standard Conditions'],
              collapseRequested: false,
              onCollapsedTapIntercept: (position) {
                interceptedPositions.add(position);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      expect(interceptedPositions, isEmpty);
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsOneWidget,
      );
    },
  );

  testWidgets('collapsed tap expands when the intercept hook declines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topRight,
          child: NextWaveScanner(
            preview: commandDeckPreview(),
            modifierTitles: const ['Standard Conditions'],
            collapseRequested: false,
            onCollapsedTapIntercept: (_) => false,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );
  });

  testWidgets(
    'collapsed control answers taps across its full bounds, not just the icon',
    (tester) async {
      var intercepted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topRight,
            child: NextWaveScanner(
              preview: commandDeckPreview(),
              modifierTitles: const ['Standard Conditions'],
              collapseRequested: false,
              onCollapsedTapIntercept: (_) {
                intercepted += 1;
                return true;
              },
            ),
          ),
        ),
      );

      // The bottom border band sits inside the 48dp control but outside the
      // painted radar icon; before the opaque gesture surface it joined no
      // gesture arena and silently blocked the board cell underneath.
      final rect = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      );
      await tester.tapAt(Offset(rect.left + rect.width / 2, rect.bottom - 2));
      await tester.pumpAndSettle();

      expect(intercepted, 1);
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsNothing,
      );
    },
  );

  testWidgets('selection request collapses an explicitly opened scanner', (
    tester,
  ) async {
    final preview = commandDeckPreview();
    await tester.pumpWidget(scannerHost(preview));
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );

    await tester.pumpWidget(scannerHost(preview, collapseRequested: true));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
  });

  testWidgets(
    'selection collapse releases the former expanded hit area immediately',
    (tester) async {
      var backgroundTaps = 0;
      final preview = commandDeckPreview();
      Widget host({required bool collapseRequested}) {
        return MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => backgroundTaps += 1,
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: NextWaveScanner(
                  preview: preview,
                  modifierTitles: const ['Standard Conditions'],
                  collapseRequested: collapseRequested,
                ),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(host(collapseRequested: false));
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();
      final formerExpandedRect = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
      );

      await tester.pumpWidget(host(collapseRequested: true));
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('next-wave-scanner-collapsed')),
        findsOneWidget,
      );

      await tester.tapAt(formerExpandedRect.center);
      expect(backgroundTaps, 1);
    },
  );

  testWidgets('selection collapse releases the collapsed scanner hit area', (
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
            Align(
              alignment: Alignment.topRight,
              child: NextWaveScanner(
                preview: commandDeckPreview(),
                modifierTitles: const ['Standard Conditions'],
                collapseRequested: true,
              ),
            ),
          ],
        ),
      ),
    );

    final collapsedRect = tester.getRect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
    );
    await tester.tapAt(collapsedRect.center);

    expect(backgroundTaps, 1);
  });

  testWidgets('Swarm Queen group renders an art-led preview row', (
    tester,
  ) async {
    final bossPreview = commandDeckPreview(
      groups: [
        WavePreviewGroup(
          enemyCount: 1,
          label: 'Swarm Queen',
          traits: {EnemyTrait.swarm},
        ),
      ],
    );
    await tester.pumpWidget(scannerHost(bossPreview));
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Swarm Queen'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('preview-group-0')),
        matching: find.byType(OrionAtlasSprite),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('preview-group-0')),
        matching: find.byIcon(Icons.change_history),
      ),
      findsOneWidget,
    );
  });

  testWidgets('mapped trait badges render their atlas descriptors', (
    tester,
  ) async {
    final armoredPreview = commandDeckPreview(
      groups: [
        WavePreviewGroup(
          enemyCount: 4,
          label: 'Armored Drones',
          traits: {EnemyTrait.armored},
        ),
      ],
    );
    await tester.pumpWidget(scannerHost(armoredPreview));
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();

    final mappedTrait = find.bySemanticsLabel('Armored trait');
    expect(mappedTrait, findsOneWidget);
    expect(
      find.descendant(of: mappedTrait, matching: find.byType(OrionAtlasSprite)),
      findsOneWidget,
    );
  });

  testWidgets('expanded preview exposes its details within the scanner frame', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final preview = commandDeckPreview(
        waveNumber: 3,
        groups: [
          WavePreviewGroup(
            enemyCount: 8,
            label: 'Armored Drones',
            traits: {
              EnemyTrait.armored,
              EnemyTrait.shielded,
              EnemyTrait.regen,
              EnemyTrait.heavy,
              EnemyTrait.swarm,
            },
          ),
          WavePreviewGroup(enemyCount: 2, label: 'Drones', traits: const {}),
        ],
        traits: {
          EnemyTrait.armored,
          EnemyTrait.shielded,
          EnemyTrait.regen,
          EnemyTrait.heavy,
          EnemyTrait.swarm,
        },
        clearBonus: 45,
        recommendedTowerTypes: const [TowerType.laser, TowerType.rocket],
      );
      await tester.pumpWidget(scannerHost(preview));
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();

      final frame = tester.getRect(
        find.byKey(const ValueKey('next-wave-scanner-expanded')),
      );
      expect(frame.width, lessThanOrEqualTo(212));
      expect(frame.height, lessThanOrEqualTo(320));
      expect(find.bySemanticsLabel('8 Armored Drones'), findsOneWidget);
      expect(find.bySemanticsLabel('2 Drones'), findsOneWidget);
      expect(find.bySemanticsLabel('Armored trait'), findsOneWidget);
      expect(find.bySemanticsLabel('Shielded trait'), findsOneWidget);
      expect(find.bySemanticsLabel('Regeneration trait'), findsOneWidget);
      expect(find.bySemanticsLabel('Swarm trait'), findsOneWidget);
      expect(find.bySemanticsLabel('Heavy trait'), findsOneWidget);
      expect(find.bySemanticsLabel('Clear bonus 45 credits'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Recommended towers: Laser, Rocket'),
        findsOneWidget,
      );
      expect(find.text('Standard Conditions'), findsOneWidget);
      expect(find.bySemanticsLabel('Laser tower'), findsOneWidget);
      expect(find.bySemanticsLabel('Rocket tower'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'convoy preview keeps identifiable group rows, adjacent counts, prominent art',
    (tester) async {
      await tester.pumpWidget(
        scannerHost(
          representativePreview(),
          modifierTitles: const ['Ion Storm'],
        ),
      );
      await tester.tap(find.byTooltip('Expand next-wave scanner'));
      await tester.pumpAndSettle();

      // Group rows stay individually identifiable.
      for (var index = 0; index < 3; index++) {
        expect(find.byKey(ValueKey('preview-group-$index')), findsOneWidget);
      }

      // The count stays adjacent to its own group row.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-group-0')),
          matching: find.text('12x'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-group-1')),
          matching: find.text('4x'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-group-2')),
          matching: find.text('6x'),
        ),
        findsOneWidget,
      );

      // Enemy art leads each row prominently.
      final groupArt = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('preview-group-0')),
              matching: find.byType(OrionAtlasSprite),
            )
            .first,
      );
      expect(groupArt.shortestSide, greaterThanOrEqualTo(40));

      // Recommendation/modifier sections stay discoverable by label.
      expect(find.text('RECOMMENDED COUNTERS'), findsOneWidget);
      expect(find.text('MODIFIERS'), findsOneWidget);

      // Recommended counters stay art-led with an affirmative mark each.
      final counters = find.bySemanticsLabel(
        'Recommended towers: Railgun, Cryo',
      );
      expect(counters, findsOneWidget);
      final counterArt = tester.getSize(
        find
            .descendant(of: counters, matching: find.byType(OrionAtlasSprite))
            .first,
      );
      expect(counterArt.shortestSide, greaterThanOrEqualTo(24));
      expect(
        find.descendant(
          of: counters,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNWidgets(2),
      );
    },
  );

  testWidgets('group trait badges render as readable chips', (tester) async {
    final armoredPreview = commandDeckPreview(
      groups: [
        WavePreviewGroup(
          enemyCount: 4,
          label: 'Armored Drones',
          traits: {EnemyTrait.armored},
        ),
      ],
    );
    await tester.pumpWidget(scannerHost(armoredPreview));
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();

    final badge = find.bySemanticsLabel('Armored trait');
    expect(badge, findsOneWidget);
    expect(tester.getSize(badge).height, greaterThanOrEqualTo(20));
  });

  testWidgets('capture scene 1c fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1c state: expanded scanner over a multi-group
    // convoy with traits, clear bonus, recommendations, and a modifier.
    // Real Roboto so the evidence shows true text metrics.
    await loadRealFonts();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same keys the OrionArt descriptors use) so enemy/tower art renders.
    await tester.runAsync(() async {
      await Flame.images.load(GameSpriteSheet.fileName);
      await Flame.images.load(GameTowerVarietySheet.fileName);
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: scannerHost(
          representativePreview(),
          modifierTitles: const ['Ion Storm'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1c.png'),
    );
  });

  testWidgets('collapsed semantics include next wave and total enemy count', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        scannerHost(commandDeckPreview(waveNumber: 3, waveTotal: 8)),
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Next wave 3 of 8.*8 enemies', caseSensitive: false),
        ),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('collapsed and expanded shells use MissionSurface', (
    tester,
  ) async {
    await tester.pumpWidget(scannerHost(commandDeckPreview()));

    Finder scannerSurfaces() => find.descendant(
      of: find.byType(NextWaveScanner),
      matching: find.byType(MissionSurface),
    );
    Finder scannerFrames() => find.descendant(
      of: find.byType(NextWaveScanner),
      matching: find.byType(CommandFrame),
    );

    expect(scannerSurfaces(), findsWidgets);
    expect(scannerFrames(), findsNothing);

    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pumpAndSettle();
    expect(scannerSurfaces(), findsWidgets);
    expect(scannerFrames(), findsNothing);
  });

  testWidgets('reduced motion expands and collapses after one pump', (
    tester,
  ) async {
    await tester.pumpWidget(
      scannerHost(commandDeckPreview(), disableAnimations: true),
    );
    await tester.tap(find.byTooltip('Expand next-wave scanner'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-expanded')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Collapse next-wave scanner'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
  });
}
