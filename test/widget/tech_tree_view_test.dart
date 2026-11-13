import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_menu_shell.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/tech_tree_view.dart';

import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

void main() {
  testWidgets('embedded research exposes or signals the points breakdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadRealFonts);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        home: OrionMenuShell(
          destination: OrionMenuDestination.research,
          medalEarned: 0,
          medalTotal: 21,
          researchPoints: 0,
          onDestinationSelected: (_) {},
          onOpenSettings: () {},
          child: TechTreeView(
            progress: CampaignProgress(),
            techTree: CampaignTechTree(),
            onPurchase: (_) {},
            embeddedInMenuShell: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tech-node-hardened-core')));
    await tester.pumpAndSettle();
    final bank = find.byKey(const ValueKey('tech-bank-bar'));
    final fieldScroll = find
        .ancestor(of: bank, matching: find.byType(Scrollable))
        .first;
    final viewport = tester.getRect(fieldScroll);
    if (tester.getRect(bank).bottom > viewport.bottom) {
      final scrollbar = find.ancestor(
        of: fieldScroll,
        matching: find.byType(Scrollbar),
      );
      expect(scrollbar, findsOneWidget);
      expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isTrue);
    }
    await tester.ensureVisible(bank);
    await tester.pumpAndSettle();
    expect(tester.getRect(bank).bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('node effects name their gameplay benefit without clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadRealFonts);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: TechTreeView(
          progress: CampaignProgress(),
          techTree: CampaignTechTree(),
          onPurchase: (_) {},
        ),
      ),
    );
    for (final label in [
      '+${GameBalance.solarCapacitorsGoldBonus} GOLD',
      '+${GameBalance.hardenedCoreHealthBonus} HULL',
      '+${(GameBalance.salvageCrewClearBonusFraction * 100).round()}% CLEAR GOLD',
      '+${(GameBalance.laserTuningDamageFraction * 100).round()}% DAMAGE',
      '+${GameBalance.cryoCoolantSlowDurationBonus.toStringAsFixed(1)}s SLOW',
    ]) {
      final text = find.text(label);
      expect(text, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
  });

  testWidgets('research header identifies the campaign upgrades lab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TechTreeView(
          progress: CampaignProgress(),
          techTree: CampaignTechTree(),
          onPurchase: (_) {},
        ),
      ),
    );
    expect(find.text('CAMPAIGN UPGRADES'), findsOneWidget);
    expect(find.text('R & D'), findsOneWidget);
  });

  testWidgets('large-text research detail shows price and disabled reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRealFonts();
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: OrionMenuShell(
          destination: OrionMenuDestination.research,
          medalEarned: 0,
          medalTotal: 21,
          researchPoints: 0,
          onDestinationSelected: (_) {},
          onOpenSettings: () {},
          child: TechTreeView(
            progress: CampaignProgress(),
            techTree: CampaignTechTree(),
            onPurchase: (_) {},
            embeddedInMenuShell: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tech-node-solar-capacitors')));
    await tester.pumpAndSettle();
    final detail = find.byKey(const ValueKey('tech-detail-solar-capacitors'));
    final action = find.byWidgetPredicate(
      (widget) => widget is OrionPrimaryButton && widget.label == 'Research',
    );
    for (final label in ['Cost: 3 pts', 'Need 3 more points']) {
      final text = find.descendant(of: detail, matching: find.text(label));
      expect(text, findsOneWidget);
      final bounds = tester.getRect(text);
      expect(bounds.top, greaterThanOrEqualTo(tester.getRect(detail).top));
      expect(bounds.bottom, lessThanOrEqualTo(tester.getRect(action).top));
      for (final scrollable
          in find
              .ancestor(of: text, matching: find.byType(Scrollable))
              .evaluate()) {
        final viewport = tester.getRect(find.byWidget(scrollable.widget));
        expect(bounds.top, greaterThanOrEqualTo(viewport.top));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
      }
    }
    final scrollable = find.descendant(
      of: detail,
      matching: find.byType(Scrollable),
    );
    if (tester.state<ScrollableState>(scrollable).position.maxScrollExtent >
        0) {
      final scrollbar = find.descendant(
        of: detail,
        matching: find.byType(Scrollbar),
      );
      expect(scrollbar, findsOneWidget);
      expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isTrue);
    }
  });

  for (final upgrade in [
    CampaignTechUpgrade.hardenedCore,
    CampaignTechUpgrade.salvageCrew,
    CampaignTechUpgrade.laserTuning,
  ]) {
    testWidgets('${upgrade.label} shows its disabled reason at 3x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadRealFonts();
      await tester.pumpWidget(
        MaterialApp(
          theme: orionThemeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: OrionMenuShell(
            destination: OrionMenuDestination.research,
            medalEarned: 0,
            medalTotal: 21,
            researchPoints: 0,
            onDestinationSelected: (_) {},
            onOpenSettings: () {},
            child: TechTreeView(
              progress: CampaignProgress(),
              techTree: CampaignTechTree(),
              onPurchase: (_) {},
              embeddedInMenuShell: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final node = find.byKey(ValueKey('tech-node-${upgrade.id}'));
      await tester.ensureVisible(node);
      await tester.pumpAndSettle();
      await tester.tap(node);
      await tester.pumpAndSettle();
      final detail = find.byKey(ValueKey('tech-detail-${upgrade.id}'));
      final viewport = find.descendant(
        of: detail,
        matching: find.byType(Scrollable),
      );
      final reason = find.descendant(
        of: detail,
        matching: find.text('Need ${upgrade.cost} more points'),
      );
      expect(
        tester.getRect(reason).bottom,
        lessThanOrEqualTo(tester.getRect(viewport).bottom + 0.5),
      );
    });
  }

  testWidgets('compact R&D details fit at 3x text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRealFonts();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: orionThemeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(3)),
            child: child!,
          ),
          home: TechTreeView(
            progress: CampaignProgress(),
            techTree: CampaignTechTree(),
            onPurchase: (_) {},
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tech-node-solar-capacitors')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => warmSceneImages(tester.element(find.byType(TechTreeView)), [
        'reactor_rim_ui/backdrops/tech-tree-rnd-bay.png',
      ]),
    );
    await tester.pump();
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1g-large-text.png'),
    );
    final action = find.byWidgetPredicate(
      (widget) =>
          widget is OrionPrimaryButton && widget.label.startsWith('Research'),
    );
    expect(
      action,
      findsOneWidget,
      reason: 'the selected node pins a bottom detail action',
    );
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(action).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('tech-bank-bar'))).top,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => captureReactorRimFixture(
        boundaryKey,
        'fixture-1g-large-text-action.png',
      ),
    );
  });
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
    Size size = const Size(390, 844),
    TextScaler? textScaler,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: orionThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: textScaler ?? TextScaler.noScaling),
          child: child!,
        ),
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

  final conduitsFinder = find.byKey(const ValueKey('tech-tree-conduits'));

  Finder researchActionFinder(CampaignTechUpgrade upgrade) => find.descendant(
    of: detailFinder(upgrade),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is OrionPrimaryButton && widget.label.startsWith('Research'),
    ),
  );

  Finder detailActionFinder(CampaignTechUpgrade upgrade) => find.descendant(
    of: detailFinder(upgrade),
    matching: find.byType(OrionPrimaryButton),
  );

  Future<void> selectNode(
    WidgetTester tester,
    CampaignTechUpgrade upgrade,
  ) async {
    await tester.ensureVisible(nodeFinder(upgrade));
    await tester.tap(nodeFinder(upgrade));
    await tester.pump();
  }

  void expectDetailActionPinned(Finder actionFinder) {
    expect(
      actionFinder,
      findsOneWidget,
      reason: 'the selected node pins a bottom detail action',
    );
  }

  OrionPrimaryButton detailAction(WidgetTester tester, Finder actionFinder) {
    expectDetailActionPinned(actionFinder);
    return tester.widget<OrionPrimaryButton>(actionFinder);
  }

  Future<void> tapDetailAction(WidgetTester tester, Finder actionFinder) async {
    expectDetailActionPinned(actionFinder);
    await tester.tap(actionFinder);
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
      await selectNode(tester, first);
      expect(detailFinder(first), findsOneWidget);
      // The selected node's label shows on its node card and in the detail.
      expect(find.text(first.label), findsNWidgets(2));
      expect(find.text(first.description), findsOneWidget);
      expect(find.text(first.effectLabel), findsOneWidget);
      expect(find.text('Cost: ${first.cost} pts'), findsOneWidget);
    },
  );

  testWidgets('resting tree leaves node details closed', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    expect(selectedRingFinder(CampaignTechUpgrade.values.first), findsNothing);
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
      await tapDetailAction(tester, researchActionFinder(core));
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
    final button = detailAction(tester, researchActionFinder(crew));
    expect(button.onPressed, isNull);
    await tester.tap(researchActionFinder(crew), warnIfMissed: false);
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
      await tapDetailAction(tester, researchActionFinder(core));

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
      final button = detailAction(tester, researchActionFinder(core));
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('closing/recreating TechTreeView clears detail selection', (
    tester,
  ) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    await selectNode(tester, CampaignTechUpgrade.cryoCoolant);
    expect(selectedRingFinder(CampaignTechUpgrade.cryoCoolant), findsOneWidget);

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

    expect(selectedRingFinder(CampaignTechUpgrade.values.first), findsNothing);
    expect(selectedRingFinder(CampaignTechUpgrade.cryoCoolant), findsNothing);
  });

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
    expect(find.bySemanticsLabel('Unspent: 9'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Earned: 12')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Spent: 3')), findsOneWidget);
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
    await selectNode(tester, CampaignTechUpgrade.solarCapacitors);
    expect(find.text('Purchased'), findsOneWidget);
    expect(
      detailActionFinder(CampaignTechUpgrade.solarCapacitors),
      findsNothing,
    );
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
    await tapDetailAction(
      tester,
      researchActionFinder(CampaignTechUpgrade.salvageCrew),
    );
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
    final button = detailAction(
      tester,
      detailActionFinder(CampaignTechUpgrade.cryoCoolant),
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
      await selectNode(tester, first);
      final heading = tester.widget<Text>(
        find.descendant(
          of: detailFinder(first),
          matching: find.text(first.label),
        ),
      );

      const uiTheme = OrionUiTheme.dark;
      await selectNode(tester, CampaignTechUpgrade.solarCapacitors);
      expect(heading.style!.color, uiTheme.systemViolet);
      expect(heading.style!.color, isNot(equals(uiTheme.textPrimary)));
    },
  );

  group('command-deck hex field and conduits (HPA-699)', () {
    testWidgets('the five nodes sit in a fixed 1-2-2 hex field at 390x844', (
      tester,
    ) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );

      Rect rect(CampaignTechUpgrade u) => tester.getRect(nodeFinder(u));
      final solar = rect(CampaignTechUpgrade.solarCapacitors);
      final core = rect(CampaignTechUpgrade.hardenedCore);
      final crew = rect(CampaignTechUpgrade.salvageCrew);
      final laser = rect(CampaignTechUpgrade.laserTuning);
      final cryo = rect(CampaignTechUpgrade.cryoCoolant);
      final centerX = tester.getSize(find.byType(TechTreeView)).width / 2;

      expect(solar.center.dx, closeTo(centerX, 40));
      expect(core.center.dx, lessThan(centerX));
      expect(crew.center.dx, greaterThan(centerX));
      expect(laser.center.dx, lessThan(centerX));
      expect(cryo.center.dx, greaterThan(centerX));

      expect(core.top, closeTo(crew.top, 8));
      expect(laser.top, closeTo(cryo.top, 8));
      expect(core.top, greaterThan(solar.top));
      expect(laser.top, greaterThan(core.top));

      expect(laser.center.dx, closeTo(core.center.dx, 40));
      expect(cryo.center.dx, closeTo(crew.center.dx, 40));
    });

    testWidgets('every node presents a clipped hex silhouette', (tester) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      final hexClip = find.byWidgetPredicate(
        (widget) => widget is ClipPath || widget is PhysicalShape,
      );
      for (final upgrade in CampaignTechUpgrade.values) {
        expect(
          find.descendant(of: nodeFinder(upgrade), matching: hexClip),
          findsWidgets,
          reason: '${upgrade.id} must render inside a hex silhouette',
        );
      }
    });

    testWidgets(
      'decorative conduits add no hit targets and no semantics nodes',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await pumpTree(
            tester,
            progress: CampaignProgress(),
            techTree: CampaignTechTree(),
            onPurchase: (_) {},
            onBack: () async {},
          );

          expect(conduitsFinder, findsOneWidget);
          expect(
            find.descendant(
              of: conduitsFinder,
              matching: find.byType(CustomPaint),
            ),
            findsWidgets,
          );

          final pointerGuard = tester.widget<IgnorePointer>(
            find
                .ancestor(
                  of: conduitsFinder,
                  matching: find.byType(IgnorePointer),
                )
                .first,
          );
          expect(pointerGuard.ignoring, isTrue);
          for (final interactive in [
            GestureDetector,
            InkWell,
            InkResponse,
            TextButton,
            IconButton,
          ]) {
            expect(
              find.descendant(
                of: conduitsFinder,
                matching: find.byType(interactive),
              ),
              findsNothing,
            );
          }

          expect(
            find.ancestor(
              of: conduitsFinder,
              matching: find.byType(ExcludeSemantics),
            ),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: conduitsFinder,
              matching: find.byType(Semantics),
            ),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(
              RegExp('conduit|connector', caseSensitive: false),
            ),
            findsNothing,
          );

          for (final pattern in [
            'Requires',
            'requires',
            'Unlock',
            'unlock',
            'Prerequisite',
            'first purchase',
          ]) {
            expect(find.textContaining(pattern), findsNothing);
            expect(
              find.bySemanticsLabel(RegExp(pattern, caseSensitive: false)),
              findsNothing,
            );
          }
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('the conduit layer paints behind the node field', (
      tester,
    ) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      expect(conduitsFinder, findsOneWidget);

      final stacks = find
          .ancestor(of: conduitsFinder, matching: find.byType(Stack))
          .evaluate()
          .toList();
      stacks.sort((a, b) => b.depth.compareTo(a.depth));
      final stack = stacks.first.widget as Stack;

      int? layerIndex(Finder target) {
        final targets = target.evaluate().map((e) => e.widget).toSet();
        for (var i = 0; i < stack.children.length; i++) {
          final child = stack.children[i];
          if (targets.contains(child)) return i;
          final hit = find
              .descendant(of: find.byWidget(child), matching: target)
              .evaluate();
          if (hit.isNotEmpty) return i;
        }
        return null;
      }

      final conduitIndex = layerIndex(conduitsFinder);
      final nodeIndex = layerIndex(
        nodeFinder(CampaignTechUpgrade.solarCapacitors),
      );
      expect(conduitIndex, isNotNull);
      expect(nodeIndex, isNotNull);
      expect(
        conduitIndex!,
        lessThanOrEqualTo(nodeIndex!),
        reason: 'conduits are decoration behind the interactive nodes',
      );
    });

    testWidgets('tapping empty conduit space opens no detail', (tester) async {
      await pumpTree(
        tester,
        progress: CampaignProgress(),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      final solar = tester.getRect(
        nodeFinder(CampaignTechUpgrade.solarCapacitors),
      );
      final core = tester.getRect(nodeFinder(CampaignTechUpgrade.hardenedCore));
      final point = Offset(solar.center.dx, (solar.bottom + core.top) / 2);
      for (final upgrade in CampaignTechUpgrade.values) {
        expect(
          tester.getRect(nodeFinder(upgrade)).contains(point),
          isFalse,
          reason: 'test point must be clear of every node hit region',
        );
      }
      await tester.tapAt(point);
      await tester.pump();
      for (final upgrade in CampaignTechUpgrade.values) {
        expect(detailFinder(upgrade), findsNothing);
        expect(selectedRingFinder(upgrade), findsNothing);
      }
    });

    testWidgets(
      'the selected node pins a bottom detail panel with a Research action',
      (tester) async {
        var purchases = 0;
        await pumpTree(
          tester,
          progress: progressWithRanks(const [3, 3, 3, 3]),
          techTree: CampaignTechTree(),
          onPurchase: (_) => purchases++,
          onBack: () async {},
        );
        final core = CampaignTechUpgrade.hardenedCore;
        await selectNode(tester, core);

        final viewportHeight = tester.getSize(find.byType(TechTreeView)).height;
        final detailRect = tester.getRect(detailFinder(core));
        expect(detailRect.top, greaterThan(viewportHeight / 2));
        for (final upgrade in CampaignTechUpgrade.values) {
          expect(
            detailRect.top,
            greaterThanOrEqualTo(
              tester.getRect(nodeFinder(upgrade)).bottom - 0.01,
            ),
            reason: 'the detail panel belongs below the node field',
          );
        }
        expect(
          detailRect.bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('tech-bank-bar'))).top,
          ),
        );

        final action = detailAction(tester, researchActionFinder(core));
        expect(action.variant, OrionButtonVariant.secondary);
        expect(action.onPressed, isNotNull);
        expect(
          find.text('${core.cost}'),
          findsWidgets,
          reason: 'the detail shows the real current cost',
        );
        await tapDetailAction(tester, researchActionFinder(core));
        expect(purchases, 1);
      },
    );

    testWidgets('each of the five upgrades is an independent purchase', (
      tester,
    ) async {
      final progress = progressWithRanks(const [3, 3, 3, 3, 3, 3, 3]);
      final bought = <CampaignTechUpgrade>[];
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(),
        onPurchase: bought.add,
        onBack: () async {},
      );
      for (final upgrade in CampaignTechUpgrade.values) {
        await selectNode(tester, upgrade);
        final action = detailAction(tester, researchActionFinder(upgrade));
        expect(
          action.onPressed,
          isNotNull,
          reason:
              '${upgrade.id} must be purchasable on its own — no other '
              'upgrade may gate it',
        );
        await tapDetailAction(tester, researchActionFinder(upgrade));
      }
      expect(bought, CampaignTechUpgrade.values);
    });
  });

  group('command-deck fix round 1 (HPA-699)', () {
    bool breaksInsideWord(
      WidgetTester tester,
      Finder textFinder,
      TextScaler scaler,
    ) {
      final widget = tester.widget<Text>(textFinder);
      final painter = TextPainter(
        text: TextSpan(text: widget.data ?? '', style: widget.style),
        textAlign: widget.textAlign ?? TextAlign.start,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: widget.maxLines,
        ellipsis: widget.overflow == TextOverflow.ellipsis ? '\u2026' : null,
        locale: widget.locale,
        strutStyle: widget.strutStyle,
        textHeightBehavior: widget.textHeightBehavior,
        textWidthBasis: widget.textWidthBasis ?? TextWidthBasis.parent,
      )..layout(maxWidth: tester.getSize(textFinder).width);
      final text = painter.text!.toPlainText();
      var offset = 0;
      while (offset < text.length) {
        final line = painter.getLineBoundary(TextPosition(offset: offset));
        if (line.isCollapsed || line.end >= text.length) {
          return false;
        }
        final endsCleanly = text[line.end - 1] == ' ' || text[line.end] == ' ';
        if (!endsCleanly) {
          return true;
        }
        offset = line.end;
      }
      return false;
    }

    testWidgets('semantics activation selects every node independently', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpTree(
          tester,
          progress: progressWithRanks(const [3, 3, 3, 3]),
          techTree: CampaignTechTree(),
          onPurchase: (_) {},
          onBack: () async {},
        );
        for (final upgrade in CampaignTechUpgrade.values) {
          final target = find.bySemanticsLabel(
            RegExp(RegExp.escape(upgrade.label)),
          );
          expect(
            target,
            findsOneWidget,
            reason: '${upgrade.id} must expose a named control',
          );
          final node = tester.getSemantics(target);
          final data = node.getSemanticsData();
          expect(
            data.flagsCollection.isButton,
            isTrue,
            reason: '${upgrade.id} must announce as a button',
          );
          expect(
            data.actions & SemanticsAction.tap.index,
            isNot(0),
            reason:
                '${upgrade.id} must offer a semantics tap action — a label '
                'without onTap is not activatable',
          );
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(
            detailFinder(upgrade),
            findsOneWidget,
            reason: 'semantics tap must select ${upgrade.id}',
          );
        }
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
      'the Research action and missing-points copy paint in full at tall text',
      (tester) async {
        final progress = progressWithRanks(const [3]);
        await pumpTree(
          tester,
          progress: progress,
          techTree: CampaignTechTree(),
          onPurchase: (_) {},
          onBack: () async {},
          size: const Size(360, 640),
          textScaler: const TextScaler.linear(3),
        );

        const affordable = CampaignTechUpgrade.solarCapacitors;
        await selectNode(tester, affordable);
        await tester.pump();
        final research = find.text('Research');
        expect(research, findsOneWidget);
        final researchParagraph = tester.renderObject<RenderParagraph>(
          research,
        );
        expect(
          researchParagraph.didExceedMaxLines,
          isFalse,
          reason: "'Research' truncates inside its action at 360x640, 3x",
        );
        expect(
          breaksInsideWord(tester, research, const TextScaler.linear(3)),
          isFalse,
          reason:
              "'Research' breaks mid-word ('Researc'/'h') — the label must "
              'reflow or stay one line',
        );
        expect(tester.takeException(), isNull);

        const unaffordable = CampaignTechUpgrade.cryoCoolant;
        await selectNode(tester, unaffordable);
        await tester.pump();
        final short =
            unaffordable.cost - CampaignTechTree().unspentPoints(progress);
        final need = find.text('Need $short more points');
        expect(need, findsOneWidget);
        final needParagraph = tester.renderObject<RenderParagraph>(need);
        expect(
          needParagraph.didExceedMaxLines,
          isFalse,
          reason:
              'the missing-points hint truncates — the full affordance '
              'explanation must render',
        );
        expect(
          breaksInsideWord(tester, need, const TextScaler.linear(3)),
          isFalse,
          reason: 'the missing-points hint breaks mid-word at 3x text',
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final size in const [Size(390, 844), Size(360, 640)]) {
      testWidgets('scrolling the node field keeps the detail pinned at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await pumpTree(
          tester,
          progress: progressWithRanks(const [3, 3, 3, 3]),
          techTree: CampaignTechTree(),
          onPurchase: (_) {},
          onBack: () async {},
          size: size,
        );
        const upgrade = CampaignTechUpgrade.hardenedCore;
        await selectNode(tester, upgrade);
        await tester.pump();
        final bankTop = tester
            .getRect(find.byKey(const ValueKey('tech-bank-bar')))
            .top;
        final detailBefore = tester.getRect(detailFinder(upgrade));
        final actionBefore = tester.getRect(researchActionFinder(upgrade));
        final fieldScroll = find.ancestor(
          of: nodeFinder(upgrade),
          matching: find.byType(Scrollable),
        );
        expect(fieldScroll, findsWidgets);
        final position = tester
            .state<ScrollableState>(fieldScroll.first)
            .position;
        if (position.maxScrollExtent > 0) {
          final nodeTopBefore = tester
              .getRect(nodeFinder(CampaignTechUpgrade.solarCapacitors))
              .top;
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
          expect(
            tester.getRect(nodeFinder(CampaignTechUpgrade.solarCapacitors)).top,
            isNot(closeTo(nodeTopBefore, 0.5)),
            reason:
                'the scroll must actually move the node field for this '
                'check to mean anything',
          );
          expect(
            tester.getRect(detailFinder(upgrade)),
            detailBefore,
            reason:
                'the selected detail must be pinned outside the field '
                'scroll — scrolling the field displaced it at $size',
          );
          expect(
            tester.getRect(researchActionFinder(upgrade)),
            actionBefore,
            reason: 'the Research action must stay put while the field scrolls',
          );
        }
        expect(
          tester.getRect(detailFinder(upgrade)).bottom,
          lessThanOrEqualTo(bankTop + 0.5),
          reason: 'the detail must stay above the bank bar at $size',
        );
        expect(
          tester.getRect(researchActionFinder(upgrade)).bottom,
          lessThanOrEqualTo(bankTop + 0.5),
          reason: 'the Research action must stay above the bank bar',
        );
      });
    }

    testWidgets(
      'a detail taller than the pinned band scrolls inside the band',
      (tester) async {
        await pumpTree(
          tester,
          progress: progressWithRanks(const [3, 3, 3, 3]),
          techTree: CampaignTechTree(),
          onPurchase: (_) {},
          onBack: () async {},
          size: const Size(360, 640),
          textScaler: const TextScaler.linear(3),
        );
        const upgrade = CampaignTechUpgrade.hardenedCore;
        await selectNode(tester, upgrade);
        await tester.pump();
        final bankTop = tester
            .getRect(find.byKey(const ValueKey('tech-bank-bar')))
            .top;
        final detailRect = tester.getRect(detailFinder(upgrade));
        expect(
          detailRect.bottom,
          lessThanOrEqualTo(bankTop + 0.5),
          reason:
              'the detail band must end above the bank bar, not overflow '
              'into it',
        );
        final innerScroll = find.descendant(
          of: detailFinder(upgrade),
          matching: find.byType(Scrollable),
        );
        expect(
          innerScroll,
          findsWidgets,
          reason:
              'a detail taller than its pinned band must scroll inside the '
              'band — there is no Scrollable inside the detail',
        );
        await tester.drag(innerScroll.first, const Offset(0, -300));
        await tester.pump();
        final actionRect = tester.getRect(researchActionFinder(upgrade));
        expect(
          actionRect.bottom,
          lessThanOrEqualTo(bankTop + 0.5),
          reason: 'the action must stay above the bank bar after scrolling',
        );
        expect(
          actionRect.bottom,
          lessThanOrEqualTo(detailRect.bottom + 0.5),
          reason: 'the action must remain inside the pinned detail band',
        );
      },
    );

    testWidgets('conduit strokes paint only in the gaps between nodes', (
      tester,
    ) async {
      await pumpTree(
        tester,
        progress: progressWithRanks(const [3, 3, 3, 3]),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      final conduits = find.byKey(const ValueKey('tech-tree-conduits'));
      final conduitRect = tester.getRect(conduits);
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(of: conduits, matching: find.byType(CustomPaint)),
          )
          .painter!;
      final nodeRects = [
        for (final upgrade in CampaignTechUpgrade.values)
          tester
              .getRect(nodeFinder(upgrade))
              .translate(-conduitRect.left, -conduitRect.top),
      ];
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), conduitRect.size);
        final width = conduitRect.width.ceil();
        final height = conduitRect.height.ceil();
        final image = await recorder.endRecording().toImage(width, height);
        final data = await image.toByteData();
        image.dispose();
        expect(
          data,
          isNotNull,
          reason: 'the conduit layer must rasterize for inspection',
        );
        final bytes = data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        var painted = 0;
        var insideNodes = 0;
        for (var y = 0; y < height; y += 1) {
          for (var x = 0; x < width; x += 1) {
            if (bytes[(y * width + x) * 4 + 3] <= 24) {
              continue;
            }
            painted += 1;
            final point = Offset(x + 0.5, y + 0.5);
            for (final rect in nodeRects) {
              if (rect.contains(point)) {
                insideNodes += 1;
                break;
              }
            }
          }
        }
        expect(
          painted,
          greaterThan(0),
          reason: 'the decorative conduit layer must still paint strokes',
        );
        expect(
          insideNodes,
          0,
          reason:
              'conduit strokes must terminate at node edges — strokes '
              'reaching inside a node read as prerequisite edges, which '
              'this flat 1-2-2 field does not have',
        );
      });
    });

    testWidgets('conduit strokes keep a visible gap from every node edge', (
      tester,
    ) async {
      await pumpTree(
        tester,
        progress: progressWithRanks(const [3, 3, 3, 3]),
        techTree: CampaignTechTree(),
        onPurchase: (_) {},
        onBack: () async {},
      );
      const clearance = 8.0;
      final conduits = find.byKey(const ValueKey('tech-tree-conduits'));
      final conduitRect = tester.getRect(conduits);
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(of: conduits, matching: find.byType(CustomPaint)),
          )
          .painter!;
      final nodeRects = [
        for (final upgrade in CampaignTechUpgrade.values)
          tester
              .getRect(nodeFinder(upgrade))
              .inflate(clearance)
              .translate(-conduitRect.left, -conduitRect.top),
      ];
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), conduitRect.size);
        final width = conduitRect.width.ceil();
        final height = conduitRect.height.ceil();
        final image = await recorder.endRecording().toImage(width, height);
        final data = await image.toByteData();
        image.dispose();
        expect(
          data,
          isNotNull,
          reason: 'the conduit layer must rasterize for inspection',
        );
        final bytes = data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        var painted = 0;
        var nearNodes = 0;
        for (var y = 0; y < height; y += 1) {
          for (var x = 0; x < width; x += 1) {
            if (bytes[(y * width + x) * 4 + 3] <= 24) {
              continue;
            }
            painted += 1;
            final point = Offset(x + 0.5, y + 0.5);
            for (final rect in nodeRects) {
              if (rect.contains(point)) {
                nearNodes += 1;
                break;
              }
            }
          }
        }
        expect(
          painted,
          greaterThan(0),
          reason: 'the decorative conduit layer must still paint strokes',
        );
        expect(
          nearNodes,
          0,
          reason:
              'strokes that touch a node edge draw a physical connection — '
              'the five upgrades are independent purchases, so conduits '
              'must stop visibly short of every node (>= ${clearance}px of '
              'clear air) instead of linking parent to child',
        );
      });
    });

    testWidgets('a semantics-activated node purchases through its detail', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        final bought = <CampaignTechUpgrade>[];
        await pumpTree(
          tester,
          progress: progressWithRanks(const [3, 3, 3, 3]),
          techTree: CampaignTechTree(),
          onPurchase: bought.add,
          onBack: () async {},
        );
        for (final upgrade in CampaignTechUpgrade.values) {
          final node = tester.getSemantics(
            find.bySemanticsLabel(RegExp(RegExp.escape(upgrade.label))),
          );
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(
            detailFinder(upgrade),
            findsOneWidget,
            reason:
                'semantics-activating the ${upgrade.label} node must open '
                'its detail — a label without an onTap action swallows '
                'the activation',
          );
          await tapDetailAction(tester, researchActionFinder(upgrade));
        }
        expect(
          bought,
          CampaignTechUpgrade.values,
          reason:
              'a screen-reader activation must open the same detail whose '
              'Research action completes the purchase',
        );
      } finally {
        handle.dispose();
      }
    });

    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets('the detail keeps a usable scroll viewport at '
          '${size.width.toInt()}x${size.height.toInt()} text x3', (
        tester,
      ) async {
        final progress = CampaignProgress();
        final tree = CampaignTechTree();
        await pumpTree(
          tester,
          progress: progress,
          techTree: tree,
          onPurchase: (_) {},
          onBack: () async {},
          size: size,
          textScaler: const TextScaler.linear(3),
        );
        const upgrade = CampaignTechUpgrade.solarCapacitors;
        await selectNode(tester, upgrade);
        await tester.pump();
        final detailRect = tester.getRect(detailFinder(upgrade));
        final innerScroll = find.descendant(
          of: detailFinder(upgrade),
          matching: find.byType(Scrollable),
        );
        expect(
          innerScroll,
          findsWidgets,
          reason: 'tall detail copy needs a band-local scroll viewport',
        );
        final viewportRect = tester.getRect(innerScroll.first);
        final titleRect = tester.getRect(
          find.descendant(
            of: detailFinder(upgrade),
            matching: find.text(upgrade.label),
          ),
        );
        expect(
          titleRect.bottom,
          lessThanOrEqualTo(viewportRect.bottom + 0.5),
          reason:
              'the selected title must be fully readable in the '
              'initial detail viewport at $size',
        );
        final closeRect = tester.getRect(
          find.descendant(
            of: detailFinder(upgrade),
            matching: find.byTooltip('Close upgrade details'),
          ),
        );
        expect(
          closeRect.height,
          greaterThanOrEqualTo(48),
          reason: 'Close must keep a 48dp target',
        );
        expect(
          closeRect.bottom,
          lessThanOrEqualTo(detailRect.bottom + 0.5),
          reason:
              'the Close action must stay painted inside the detail '
              'band at $size',
        );
        final researchRect = tester.getRect(researchActionFinder(upgrade));
        expect(
          researchRect.height,
          greaterThanOrEqualTo(48),
          reason: 'Research must keep a 48dp target',
        );
        expect(
          researchRect.bottom,
          lessThanOrEqualTo(detailRect.bottom + 0.5),
          reason: 'Research must be painted inside the detail band',
        );
        expect(
          viewportRect.height,
          greaterThanOrEqualTo(96),
          reason:
              'the scroll body needs a useful viewport at $size — a '
              'sliver cannot present readable copy',
        );
        final position = tester
            .state<ScrollableState>(innerScroll.first)
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final short = upgrade.cost - tree.unspentPoints(progress);
        final lastCopy =
            find
                .descendant(
                  of: detailFinder(upgrade),
                  matching: find.text('Need $short more points'),
                )
                .evaluate()
                .isNotEmpty
            ? find.text('Need $short more points')
            : find.text('Cost: ${upgrade.cost} pts');
        expect(
          tester
              .getRect(
                find.descendant(of: detailFinder(upgrade), matching: lastCopy),
              )
              .bottom,
          lessThanOrEqualTo(viewportRect.bottom + 0.5),
          reason:
              'all detail copy must be reachable inside the scroll '
              'viewport at $size',
        );
        expect(
          tester.getRect(researchActionFinder(upgrade)).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('tech-bank-bar'))).top +
                0.5,
          ),
          reason: 'Research must remain reachable after scrolling copy',
        );
      });
    }
  });

  for (final size in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('embedded research stays usable at $size with 3x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final progress = progressWithRanks(const [3, 3, 1]);
      final tree = CampaignTechTree(
        purchased: {CampaignTechUpgrade.solarCapacitors},
      );
      final purchases = <CampaignTechUpgrade>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: orionThemeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: OrionMenuShell(
            destination: OrionMenuDestination.research,
            medalEarned: 7,
            medalTotal: 21,
            researchPoints: 4,
            onDestinationSelected: (_) {},
            onOpenSettings: () {},
            child: TechTreeView(
              progress: progress,
              techTree: tree,
              onPurchase: purchases.add,
              embeddedInMenuShell: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectNode(tester, CampaignTechUpgrade.hardenedCore);
      await tester.pumpAndSettle();
      final bank = find.byKey(const ValueKey('tech-bank-bar'));
      await tester.ensureVisible(bank);
      await tester.pumpAndSettle();
      expect(find.text('Unspent: 4 · Earned: 7 · Spent: 3'), findsOneWidget);
      expect(
        tester.getRect(bank).bottom,
        lessThanOrEqualTo(
          tester.getRect(detailFinder(CampaignTechUpgrade.hardenedCore)).top,
        ),
      );
      final action = researchActionFinder(CampaignTechUpgrade.hardenedCore);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      expect(purchases, [CampaignTechUpgrade.hardenedCore]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capture scene 1g fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1g state: Solar Capacitors purchased (check badge
    // + "Purchased" detail once its node is selected below), Hardened Core
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
      await Flame.images.load('orion_sprite_sheet.png');
      await Flame.images.load('orion_tower_variety_sheet.png');
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
          home: OrionMenuShell(
            destination: OrionMenuDestination.research,
            medalEarned: 7,
            medalTotal: 21,
            researchPoints: 4,
            onDestinationSelected: (_) {},
            onOpenSettings: () {},
            child: TechTreeView(
              progress: progress,
              techTree: techTree,
              onPurchase: (_) {},
              embeddedInMenuShell: true,
            ),
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
    for (final upgrade in CampaignTechUpgrade.values) {
      expect(nodeFinder(upgrade), findsOneWidget);
    }

    await tester.runAsync(() async {
      await Flame.images.load('orion_sprite_sheet.png');
      await warmSceneImages(tester.element(find.byType(TechTreeView)), [
        'reactor_rim_ui/backdrops/tech-tree-rnd-bay.png',
      ]);
    });
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: nodeFinder(CampaignTechUpgrade.laserTuning),
        matching: find.byType(SpriteWidget),
      ),
      findsOneWidget,
      reason: 'Tower artwork must load before the R&D capture.',
    );

    // Scene 1g's subject is the purchased detail; the resting tree keeps
    // details closed, so select the purchased node before capturing.
    await selectNode(tester, CampaignTechUpgrade.solarCapacitors);
    await tester.pumpAndSettle();
    expect(detailFinder(CampaignTechUpgrade.solarCapacitors), findsOneWidget);

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1g.png'),
    );
    await selectNode(tester, CampaignTechUpgrade.hardenedCore);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(nodeFinder(CampaignTechUpgrade.laserTuning)).bottom,
      lessThanOrEqualTo(
        tester.getRect(detailFinder(CampaignTechUpgrade.hardenedCore)).top,
      ),
      reason: 'The full upgrade field should remain visible above the detail.',
    );
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'rnd-shell-390x844.png'),
    );
    final bank = find.byKey(const ValueKey('tech-bank-bar'));
    await tester.ensureVisible(bank);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(bank).bottom,
      lessThanOrEqualTo(
        tester.getRect(detailFinder(CampaignTechUpgrade.hardenedCore)).top,
      ),
    );
    expect(find.text('Unspent: 4 · Earned: 7 · Spent: 3'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    await selectNode(tester, CampaignTechUpgrade.hardenedCore);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'rnd-shell-360x640.png'),
    );
  });
}
