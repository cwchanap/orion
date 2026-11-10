import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_title_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/orion_finders.dart';

/// Scene-1a title screen tests. These pump the page through the
/// production-default constructor — no `startOnWorldMap` seam — so the
/// title-first behavior is exercised exactly as shipped. Map-first fixture
/// behavior lives in widget_test's own seam coverage.
Widget titleGamePage({
  CampaignProgressStore? progressStore,
  FeedbackPreferencesStore? feedbackPreferencesStore,
  ValueChanged<OrionDefenseGame>? onGameCreated,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: orionThemeData,
    home: OrionGamePage(
      progressStore: progressStore,
      feedbackPreferencesStore: feedbackPreferencesStore,
      firstMissionGuideStore: InMemoryFirstMissionGuideStore(completed: true),
      onGameCreated: onGameCreated,
      gameFeedback: const NoOpGameFeedback(),
    ),
  );
}

Future<InMemoryCampaignProgressStore> _storeWithResults(
  Map<String, StageResult> results,
) async {
  final store = InMemoryCampaignProgressStore(
    knownStages: OrionCampaign.stages,
  );
  await store.save(
    CampaignSave(
      progress: CampaignProgress(bestResultsByStageId: results),
      techTree: CampaignTechTree(),
    ),
  );
  return store;
}

Map<String, StageResult> _resultsFor(Iterable<String> stageIds) => {
  for (final id in stageIds)
    id: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('title screen', () {
    testWidgets('the production page boots into the title, not the map', (
      tester,
    ) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();

      expect(find.byType(OrionTitleView), findsOneWidget);
      expect(find.text('ORION SECTOR'), findsNothing);
      expect(find.byTooltip('Start Wave'), findsNothing);
    });

    testWidgets('Continue opens the briefing for the fresh-campaign '
        'recommendation without launching', (tester) async {
      OrionDefenseGame? createdGame;
      await tester.pumpWidget(
        titleGamePage(
          progressStore: InMemoryCampaignProgressStore(
            knownStages: OrionCampaign.stages,
          ),
          onGameCreated: (game) => createdGame = game,
        ),
      );
      await tester.pumpAndSettle();

      // A fresh save recommends Outpost Alpha; the campaign card shows it
      // and Continue routes through the briefing, never straight to combat.
      final card = find.byKey(const ValueKey('title-campaign-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('OUTPOST ALPHA')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('title-primary-cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stage-briefing')),
          matching: findOrionTitle('Outpost Alpha'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Start Mission'), findsOneWidget);
      expect(createdGame, isNull);
    });

    testWidgets('Continue steers to the first open optional stage once the '
        'main route clears', (tester) async {
      final store = await _storeWithResults(
        _resultsFor(OrionCampaign.mainStages.map((stage) => stage.id)),
      );
      await tester.pumpWidget(titleGamePage(progressStore: store));
      await tester.pumpAndSettle();

      // recommendedStage now points at Salvage Rift — the same target the
      // map's next-mission card shows.
      await tester.tap(find.byKey(const ValueKey('title-primary-cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stage-briefing')),
          matching: findOrionTitle('Salvage Rift'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a fully cleared campaign replaces Continue with Sectors', (
      tester,
    ) async {
      final store = await _storeWithResults(
        _resultsFor(OrionCampaign.stages.map((stage) => stage.id)),
      );
      await tester.pumpWidget(titleGamePage(progressStore: store));
      await tester.pumpAndSettle();

      // The replay fallback is already cleared, so 'Continue' would be a
      // lie; the primary action reads Sectors and lands on the map.
      expect(find.text('Continue'), findsNothing);
      final cta = find.byKey(const ValueKey('title-primary-cta'));
      expect(
        find.descendant(of: cta, matching: find.text('Sectors')),
        findsOneWidget,
      );
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.text('ORION SECTOR'), findsOneWidget);
    });

    testWidgets('the Sectors shortcut opens the world map', (tester) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sectors'));
      await tester.pumpAndSettle();
      expect(find.text('ORION SECTOR'), findsOneWidget);
    });

    testWidgets('the R&D shortcut opens the tech tree', (tester) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('R&D'));
      await tester.pumpAndSettle();
      expect(findOrionTitle('R & D'), findsOneWidget);
    });

    testWidgets('the Codex shortcut opens the codex', (tester) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Codex'));
      await tester.pumpAndSettle();
      expect(findOrionTitle('Codex'), findsOneWidget);
    });

    testWidgets('the Settings shortcut opens the settings sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        titleGamePage(
          feedbackPreferencesStore: InMemoryFeedbackPreferencesStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SwitchListTile, 'Sound Effects'),
        findsOneWidget,
      );
    });
  });
}
