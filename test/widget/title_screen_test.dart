import 'dart:async';

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
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_title_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/orion_finders.dart';

Widget titleGamePage({
  CampaignProgressStore? progressStore,
  FeedbackPreferencesStore? feedbackPreferencesStore,
  ValueChanged<OrionDefenseGame>? onGameCreated,
  TextScaler? textScaler,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: orionThemeData,
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
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

class _DelayedTitleFeedbackStore implements FeedbackPreferencesStore {
  FeedbackPreferences value = const FeedbackPreferences();
  final List<Completer<void>> saveCompletions = [];

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    final completer = Completer<void>();
    saveCompletions.add(completer);
    await completer.future;
    value = preferences;
  }
}

InkWell _settingsInkWell(WidgetTester tester) {
  return tester.widget<InkWell>(
    find.descendant(
      of: find.byTooltip('Settings'),
      matching: find.byType(InkWell),
    ),
  );
}

void _expectWithinHorizontalBounds(WidgetTester tester, double width) {
  for (final element
      in find
          .descendant(
            of: find.byType(OrionTitleView),
            matching: find.byType(Text),
          )
          .evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    expect(
      rect.left >= -0.5 && rect.right <= width + 0.5,
      isTrue,
      reason:
          '${element.widget} painted at $rect, outside the ${width}px '
          'viewport',
    );
  }
}

void _expectWordmarkIntact(WidgetTester tester) {
  final wordmark = find.descendant(
    of: find.byType(OrionTitleView),
    matching: find.text('ORION'),
  );
  expect(wordmark, findsNWidgets(2));
  for (final element in wordmark.evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    expect(
      rect.height,
      lessThan(160),
      reason:
          'the wordmark must scale as a lockup, not letter-stack into '
          '${rect.height}px of vertical glyphs',
    );
  }
}

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

    testWidgets('the production title lays out 360x640 at 3x text without '
        'overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        titleGamePage(textScaler: const TextScaler.linear(3)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(OrionTitleView), findsOneWidget);
      _expectWithinHorizontalBounds(tester, 360);
      _expectWordmarkIntact(tester);
    });

    testWidgets('the production title lays out 640x360 landscape at 3x '
        'text without overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        titleGamePage(textScaler: const TextScaler.linear(3)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(OrionTitleView), findsOneWidget);
      _expectWithinHorizontalBounds(tester, 640);
      _expectWordmarkIntact(tester);
    });

    testWidgets('a cleared main route shows campaign-complete copy while '
        'Continue still steers to the open optional stage', (tester) async {
      final store = await _storeWithResults(
        _resultsFor(OrionCampaign.mainStages.map((stage) => stage.id)),
      );
      await tester.pumpWidget(titleGamePage(progressStore: store));
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('title-campaign-card'));
      expect(
        find.descendant(of: card, matching: find.text('CAMPAIGN COMPLETE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('SALVAGE RIFT')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('title-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
    });

    testWidgets('a fully cleared campaign shows campaign-complete copy', (
      tester,
    ) async {
      final store = await _storeWithResults(
        _resultsFor(OrionCampaign.stages.map((stage) => stage.id)),
      );
      await tester.pumpWidget(titleGamePage(progressStore: store));
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('title-campaign-card'));
      expect(
        find.descendant(of: card, matching: find.text('CAMPAIGN COMPLETE')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: findOrionTitle('All sectors cleared'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Settings shortcut is disabled while a feedback '
        'preference save is in flight', (tester) async {
      final store = _DelayedTitleFeedbackStore();
      await tester.pumpWidget(titleGamePage(feedbackPreferencesStore: store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OrionPrimaryButton, 'Done'));
      await tester.pumpAndSettle();
      expect(store.saveCompletions, hasLength(1));

      expect(_settingsInkWell(tester).onTap, isNull);

      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();
      expect(_settingsInkWell(tester).onTap, isNotNull);
    });
  });
}
