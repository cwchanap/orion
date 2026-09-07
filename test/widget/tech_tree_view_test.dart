import 'dart:io';

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/ui/tech_tree_view.dart';

import '../support/reactor_rim_visual_capture.dart';

void main() {
  CampaignProgress progressWithRanks(List<int> ranks) {
    final results = <String, StageResult>{};
    for (var i = 0; i < ranks.length; i++) {
      final medal = ranks[i] == 3
          ? StageMedal.gold
          : ranks[i] == 2
          ? StageMedal.silver
          : StageMedal.clear;
      results['s$i'] = StageResult(medal: medal, bestBaseHealth: 10);
    }
    return CampaignProgress(bestResultsByStageId: results);
  }

  /// Pumps the tree on the target 390×844 aperture so the five-node field,
  /// detail surface and bank bar are all on screen without scrolling.
  Future<void> pumpTree(
    WidgetTester tester, {
    required CampaignProgress progress,
    required CampaignTechTree techTree,
    String? feedback,
    bool isSavingProgress = false,
    required void Function(CampaignTechUpgrade) onPurchase,
    required VoidCallback onBack,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TechTreeView(
          progress: progress,
          techTree: techTree,
          feedback: feedback,
          isSavingProgress: isSavingProgress,
          onPurchase: onPurchase,
          onBack: onBack,
        ),
      ),
    );
  }

  Finder nodeFinder(CampaignTechUpgrade upgrade) =>
      find.byKey(ValueKey('tech-node-${upgrade.id}'));

  Finder selectedRingFinder(CampaignTechUpgrade upgrade) =>
      find.byKey(ValueKey('tech-selected-ring-${upgrade.id}'));

  Finder detailFinder(CampaignTechUpgrade upgrade) =>
      find.byKey(ValueKey('tech-detail-${upgrade.id}'));

  Finder purchasedBadgeFinder(CampaignTechUpgrade upgrade) =>
      find.byKey(ValueKey('tech-node-purchased-${upgrade.id}'));

  Future<void> selectNode(
    WidgetTester tester,
    CampaignTechUpgrade upgrade,
  ) async {
    await tester.tap(nodeFinder(upgrade));
    await tester.pump();
  }

  testWidgets('renders the R&D-bay backdrop with a readability scrim', (
    tester,
  ) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    expect(find.byKey(const ValueKey('tech-tree-backdrop')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tech-tree-backdrop-art')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tech-tree-scrim')), findsOneWidget);
  });

  testWidgets(
    'renders exactly five nodes, one per upgrade, with 48dp targets',
    (tester) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      // Enum ids are exhaustive, so these five keys prove exactly five nodes.
      for (final upgrade in CampaignTechUpgrade.values) {
        expect(nodeFinder(upgrade), findsOneWidget);
      }
      for (final upgrade in CampaignTechUpgrade.values) {
        final rect = tester.getRect(nodeFinder(upgrade));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
    },
  );

  testWidgets(
    'detail shows the selected upgrade with real label, description, effect and cost',
    (tester) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      final first = CampaignTechUpgrade.values.first;
      expect(detailFinder(first), findsOneWidget);
      // The selected node's label shows on its node card and in the detail.
      expect(find.text(first.label), findsNWidgets(2));
      expect(find.text(first.description), findsOneWidget);
      expect(find.text(first.effectLabel), findsNWidgets(2));
      expect(find.text('Cost: ${first.cost} pts'), findsOneWidget);
    },
  );

  testWidgets('initial selected node is CampaignTechUpgrade.values.first', (
    tester,
  ) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    expect(
      selectedRingFinder(CampaignTechUpgrade.values.first),
      findsOneWidget,
    );
    expect(selectedRingFinder(CampaignTechUpgrade.values[1]), findsNothing);
  });

  testWidgets('selecting another node changes local detail only', (
    tester,
  ) async {
    var purchases = 0;
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) => purchases++,
      onBack: () async {},
    );
    final cryo = CampaignTechUpgrade.cryoCoolant;
    await selectNode(tester, cryo);

    expect(selectedRingFinder(cryo), findsOneWidget);
    expect(detailFinder(cryo), findsOneWidget);
    expect(find.text(cryo.label), findsNWidgets(2));
    expect(purchases, 0);
  });

  testWidgets('selection survives parent rebuild', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    final cryo = CampaignTechUpgrade.cryoCoolant;
    await selectNode(tester, cryo);

    // Parent republishes a snapshot (new widget config, same tree position):
    // the presentation-only selection must survive.
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      feedback: 'Could not save campaign progress.',
      onPurchase: (_) {},
      onBack: () async {},
    );

    expect(selectedRingFinder(cryo), findsOneWidget);
    expect(detailFinder(cryo), findsOneWidget);
    expect(find.text(cryo.label), findsNWidgets(2));
  });

  testWidgets(
    'selection survives successful purchase and detail flips Purchased',
    (tester) async {
      final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
      final core = CampaignTechUpgrade.hardenedCore;
      var purchases = 0;
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(),
        onPurchase: (_) => purchases++,
        onBack: () async {},
      );
      await selectNode(tester, core);
      await tester.tap(find.widgetWithText(FilledButton, 'Purchase'));
      await tester.pump();
      expect(purchases, 1);

      // Parent applies the optimistic purchase and republishes.
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(purchased: {core}),
        onPurchase: (_) => purchases++,
        onBack: () async {},
      );

      expect(selectedRingFinder(core), findsOneWidget);
      expect(detailFinder(core), findsOneWidget);
      expect(find.text('Purchased'), findsOneWidget);
      expect(purchasedBadgeFinder(core), findsOneWidget);
      expect(purchases, 1);
    },
  );

  testWidgets('selection stays while saving and purchase is disabled', (
    tester,
  ) async {
    final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
    final crew = CampaignTechUpgrade.salvageCrew;
    var purchases = 0;
    await pumpTree(
      tester,
      progress: progress,
      techTree: CampaignTechTree(),
      onPurchase: (_) => purchases++,
      onBack: () async {},
    );
    await selectNode(tester, crew);

    // A save goes in flight; the parent republishes with isSavingProgress.
    await pumpTree(
      tester,
      progress: progress,
      techTree: CampaignTechTree(),
      isSavingProgress: true,
      onPurchase: (_) => purchases++,
      onBack: () async {},
    );

    expect(selectedRingFinder(crew), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Purchase'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Purchase'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(purchases, 0);
  });

  testWidgets(
    'selection survives failed-save rollback; detail reflects rolled-back state + feedback',
    (tester) async {
      final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
      final core = CampaignTechUpgrade.hardenedCore;
      var purchases = 0;
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(),
        onPurchase: (_) => purchases++,
        onBack: () async {},
      );
      await selectNode(tester, core);
      await tester.tap(find.widgetWithText(FilledButton, 'Purchase'));
      await tester.pump();

      // Optimistic purchase lands…
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(purchased: {core}),
        onPurchase: (_) => purchases++,
        onBack: () async {},
      );
      expect(find.text('Purchased'), findsOneWidget);

      // …then the save fails and the parent rolls back + surfaces feedback.
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(),
        feedback: 'Could not save campaign progress.',
        onPurchase: (_) => purchases++,
        onBack: () async {},
      );

      expect(find.text('Could not save campaign progress.'), findsOneWidget);
      expect(find.text('Purchased'), findsNothing);
      expect(purchasedBadgeFinder(core), findsNothing);
      expect(selectedRingFinder(core), findsOneWidget);
      expect(detailFinder(core), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Purchase'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'closing/recreating TechTreeView resets selection to first enum',
    (tester) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      await selectNode(tester, CampaignTechUpgrade.cryoCoolant);
      expect(
        selectedRingFinder(CampaignTechUpgrade.cryoCoolant),
        findsOneWidget,
      );

      // Close the view…
      await tester.pumpWidget(const SizedBox.shrink());
      // …and reopen it: the element tree is brand new, so selection resets.
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );

      expect(
        selectedRingFinder(CampaignTechUpgrade.values.first),
        findsOneWidget,
      );
      expect(selectedRingFinder(CampaignTechUpgrade.cryoCoolant), findsNothing);
    },
  );

  testWidgets('bank still shows real unspent/earned/spent', (tester) async {
    final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
    final techTree = CampaignTechTree(
      purchased: {CampaignTechUpgrade.solarCapacitors},
    ); // spent 3
    await pumpTree(
      tester,
      progress: progress,
      techTree: techTree,
      onPurchase: (_) {},
      onBack: () async {},
    );
    // Unspent: 9 · Earned: 12 · Spent: 3
    expect(find.textContaining('Unspent: 9'), findsOneWidget);
    expect(find.textContaining('Earned: 12'), findsOneWidget);
    expect(find.textContaining('Spent: 3'), findsOneWidget);
  });

  testWidgets('purchased node cannot repurchase', (tester) async {
    final techTree = CampaignTechTree(
      purchased: {CampaignTechUpgrade.solarCapacitors},
    );
    var tapped = 0;
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: techTree,
      onPurchase: (_) => tapped++,
      onBack: () async {},
    );
    // The default-selected node is purchased: the detail shows the
    // non-interactive "Purchased" state and no Purchase button exists.
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Purchase'), findsNothing);
    await tester.tap(find.text('Purchased'));
    await tester.pump();
    expect(tapped, 0);
  });

  testWidgets('affordable node calls onPurchase exactly once', (tester) async {
    final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
    var tapped = 0;
    await pumpTree(
      tester,
      progress: progress,
      techTree: CampaignTechTree(),
      onPurchase: (_) => tapped++,
      onBack: () async {},
    );
    await selectNode(tester, CampaignTechUpgrade.salvageCrew);
    await tester.tap(find.widgetWithText(FilledButton, 'Purchase'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('unaffordable detail exposes real missing-point reason', (
    tester,
  ) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(), // 0 earned
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    // Cryo Coolant costs 5; with a 0 bank the detail must say exactly how
    // many points are missing.
    await selectNode(tester, CampaignTechUpgrade.cryoCoolant);
    expect(find.textContaining('Need 5 more points'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Need 5 more points'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('no prerequisite semantics or dependency edges', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    // Five independent purchases: no "Requires …" copy and no connector
    // layer implying a dependency graph between nodes.
    expect(find.textContaining('Requires'), findsNothing);
    expect(
      find.byKey(const ValueKey('tech-tree-connector-layer')),
      findsNothing,
    );
  });

  testWidgets('shows feedback when present', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      feedback: 'Could not save campaign progress.',
      onPurchase: (_) {},
      onBack: () async {},
    );
    expect(find.text('Could not save campaign progress.'), findsOneWidget);
  });

  testWidgets('tapping back arrow invokes onBack', (tester) async {
    var backInvoked = false;
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {
        backInvoked = true;
      },
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(backInvoked, isTrue);
  });

  testWidgets('capture scene 1g fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1g state: Solar Capacitors purchased (check badge
    // + "Purchased" detail on the default-selected node), Hardened Core
    // affordable (bright node + enabled Purchase), Cryo Coolant unaffordable
    // (dim node), over the approved R&D-bay backdrop. Real Roboto + Material
    // icons so the evidence shows true text metrics.
    await _loadRealFonts();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same key the OrionArt descriptor uses) so the art renders.
    await tester.runAsync(() async {
      await Flame.images.load('reactor_rim_ui/backdrops/tech-tree-rnd-bay.png');
    });

    final progress = progressWithRanks(const [3, 3, 1]); // 7 earned, 4 unspent
    final techTree = CampaignTechTree(
      purchased: {CampaignTechUpgrade.solarCapacitors},
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          home: TechTreeView(
            progress: progress,
            techTree: techTree,
            onPurchase: (_) {},
            onBack: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tech-tree-backdrop')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tech-tree-backdrop-art')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tech-tree-scrim')), findsOneWidget);
    expect(
      purchasedBadgeFinder(CampaignTechUpgrade.solarCapacitors),
      findsOneWidget,
    );
    expect(
      selectedRingFinder(CampaignTechUpgrade.solarCapacitors),
      findsOneWidget,
    );
    expect(find.text('Purchased'), findsOneWidget);
    for (final upgrade in CampaignTechUpgrade.values) {
      expect(nodeFinder(upgrade), findsOneWidget);
    }

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1g.png'),
    );
  });
}

Future<void> _loadRealFonts() async {
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

  final iconFile = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!iconFile.existsSync()) fail('Missing SDK font: ${iconFile.path}');
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
  await iconLoader.load();
}
