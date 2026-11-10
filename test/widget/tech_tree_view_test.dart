import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/tech_tree_view.dart';

import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

void main() {
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
  });
}
