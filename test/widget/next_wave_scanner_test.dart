import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/next_wave_scanner.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

import '../support/command_deck_fixtures.dart';

Widget scannerHost(
  WavePreview preview, {
  bool disableAnimations = false,
  bool collapseRequested = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Align(
        alignment: Alignment.topRight,
        child: NextWaveScanner(
          preview: preview,
          modifierTitles: const ['Standard Conditions'],
          collapseRequested: collapseRequested,
        ),
      ),
    ),
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
    await tester.tap(find.byKey(const ValueKey('next-wave-scanner-collapsed')));
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

  testWidgets('Swarm Queen group renders an art-led preview row', (
    tester,
  ) async {
    final bossPreview = commandDeckPreview(
      groups: [
        WavePreviewGroup(
          enemyCount: 1,
          label: 'Swarm Queen',
          traits: {EnemyTrait.swarm, EnemyTrait.regen},
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
      expect(frame.height, lessThanOrEqualTo(168));
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
