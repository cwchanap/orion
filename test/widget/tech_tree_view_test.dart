import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/ui/tech_tree_view.dart';

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

  Future<void> pumpTree(
    WidgetTester tester, {
    required CampaignProgress progress,
    required CampaignTechTree techTree,
    String? feedback,
    bool isSavingProgress = false,
    required void Function(CampaignTechUpgrade) onPurchase,
    required VoidCallback onBack,
  }) async {
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

  testWidgets('renders all five upgrade rows with label and effect', (
    tester,
  ) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    for (final upgrade in CampaignTechUpgrade.values) {
      expect(find.text(upgrade.label), findsOneWidget);
      expect(find.text(upgrade.effectLabel), findsOneWidget);
    }
  });

  testWidgets('header shows three-number bank readout', (tester) async {
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

  testWidgets('purchased upgrade row is disabled', (tester) async {
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
    // The row shows "Purchased" (a Chip, not a button). Tapping the Chip
    // must not fire onPurchase — only the enabled FilledButton rows do.
    expect(find.text('Purchased'), findsOneWidget);
    await tester.tap(find.text('Purchased'));
    await tester.pump();
    expect(tapped, 0);
  });

  testWidgets('affordable upgrade fires onPurchase', (tester) async {
    final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
    CampaignTechUpgrade? purchasedUpgrade;
    await pumpTree(
      tester,
      progress: progress,
      techTree: CampaignTechTree(),
      onPurchase: (u) => purchasedUpgrade = u,
      onBack: () async {},
    );
    // Solar Capacitors is the first row and is affordable (cost 3).
    final purchaseButton = find.widgetWithText(FilledButton, 'Purchase').first;
    await tester.tap(purchaseButton);
    await tester.pump();
    expect(purchasedUpgrade, CampaignTechUpgrade.solarCapacitors);
  });

  testWidgets('locked upgrade shows "Need N more points"', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(), // 0 earned
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    // Cryo Coolant costs 5; with 0 bank, the row should show "Need 5 more points".
    expect(find.textContaining('Need 5 more points'), findsOneWidget);
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

  testWidgets(
    'affordable upgrade Purchase button is disabled while a save is in flight',
    (tester) async {
      // Round-3 review P3: the Purchase button must not present an enabled
      // affordance that silently no-ops when _isSavingProgress is true.
      final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
      var tapped = 0;
      await pumpTree(
        tester,
        progress: progress,
        techTree: CampaignTechTree(),
        isSavingProgress: true,
        onPurchase: (_) => tapped++,
        onBack: () async {},
      );

      // Solar Capacitors is affordable (cost 3, 12 earned) but the button
      // must be disabled because a save is in flight.
      final purchaseButton = find
          .widgetWithText(FilledButton, 'Purchase')
          .first;
      final button = tester.widget<FilledButton>(purchaseButton);
      expect(button.onPressed, isNull);

      await tester.tap(purchaseButton, warnIfMissed: false);
      await tester.pump();
      expect(tapped, 0);
    },
  );
}
