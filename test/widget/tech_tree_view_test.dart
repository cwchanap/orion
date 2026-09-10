import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/tech_tree_view.dart';

import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

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
        theme: orionThemeData,
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
    // Five independent purchases: no "Requires …" copy implying
    // prerequisites between the nodes.
    expect(find.textContaining('Requires'), findsNothing);
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

  testWidgets('_TechNode label color differs across purchased, affordable and '
      'locked states', (tester) async {
    // Regression coverage for a bug where the muted-label rule
    // ("microLabel cannot be white") was satisfied by deleting the
    // node's purchased/affordable/locked conditional and collapsing the
    // label to a single flat color. Assert the actual resolved
    // TextStyle.color per state so a future collapse back to one color
    // fails here, the way world_map_command_deck_test.dart does for the
    // map's stage-node labels.
    final progress = progressWithRanks(const [3, 3, 1]); // 7 earned
    final techTree = CampaignTechTree(
      purchased: {CampaignTechUpgrade.solarCapacitors}, // spent 3, unspent 4
    );
    await pumpTree(
      tester,
      progress: progress,
      techTree: techTree,
      onPurchase: (_) {},
      onBack: () async {},
    );

    Color nodeLabelColor(CampaignTechUpgrade upgrade) {
      final text = tester.widget<Text>(
        find.descendant(
          of: nodeFinder(upgrade),
          matching: find.text(upgrade.label),
        ),
      );
      return text.style!.color!;
    }

    // Solar Capacitors: purchased -> naniteGreen.
    final purchasedColor = nodeLabelColor(CampaignTechUpgrade.solarCapacitors);
    // Hardened Core: costs 4, unspent is 4 -> affordable but unpurchased
    // -> systemCyan.
    final affordableColor = nodeLabelColor(CampaignTechUpgrade.hardenedCore);
    // Cryo Coolant: costs 5, unspent is 4 -> locked/unaffordable ->
    // textMuted.
    final lockedColor = nodeLabelColor(CampaignTechUpgrade.cryoCoolant);

    const uiTheme = OrionUiTheme.dark;
    expect(purchasedColor, uiTheme.naniteGreen);
    expect(affordableColor, uiTheme.systemCyan);
    expect(lockedColor, uiTheme.textMuted);

    expect(purchasedColor, isNot(equals(affordableColor)));
    expect(affordableColor, isNot(equals(lockedColor)));
    expect(purchasedColor, isNot(equals(lockedColor)));
  });

  testWidgets(
    '_TechDetail heading resolves to systemViolet, never textPrimary',
    (tester) async {
      // Regression coverage for the same muted-label failure mode: the
      // detail panel heading used to be textPrimary before the design-
      // system migration and must now resolve to the panel's own
      // systemViolet border accent, not collapse back to textPrimary.
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      final first = CampaignTechUpgrade.values.first;
      final heading = tester.widget<Text>(
        find.descendant(
          of: detailFinder(first),
          matching: find.text(first.label),
        ),
      );

      const uiTheme = OrionUiTheme.dark;
      expect(heading.style!.color, uiTheme.systemViolet);
      expect(heading.style!.color, isNot(equals(uiTheme.textPrimary)));
    },
  );

  testWidgets('capture scene 1g fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1g state: Solar Capacitors purchased (check badge
    // + "Purchased" detail on the default-selected node), Hardened Core
    // affordable (bright node + enabled Purchase), Cryo Coolant unaffordable
    // (dim node), over the approved R&D-bay backdrop. Real Roboto + Material
    // icons so the evidence shows true text metrics.
    await loadRealFonts();
    // The memo can hold a pending future from an earlier cold-cache test
    // in this process; clear it so this fixture's warmed cache is used.
    OrionArtDescriptor.resetSpriteCache();
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
          // The product app hides this banner; a fixture host must too, or the
          // parity evidence carries a stripe the shipped game never shows.
          debugShowCheckedModeBanner: false,
          theme: orionThemeData,
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
