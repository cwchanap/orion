import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/onboarding/first_mission_guide_store.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/ui/orion_primary_button.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_title_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/orion_finders.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

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
    testWidgets('title does not present a placeholder app version', (
      tester,
    ) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();
      expect(find.text('v0.0 // COMMAND DECK'), findsNothing);
    });

    testWidgets('title backdrop fills the full width with loaded artwork', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadRealFonts();
      await tester.runAsync(() async {
        await Flame.images.load('reactor_rim_ui/backdrops/command-center.png');
        await Flame.images.load('reactor_rim_ui/stages/outpost-alpha.png');
        await Flame.images.load('orion_sprite_sheet.png');
        await Flame.images.load('orion_tower_variety_sheet.png');
      });
      OrionArtDescriptor.resetSpriteCache();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: titleGamePage()),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(
            'assets/images/reactor_rim_ui/backdrops/command-center.png',
          ),
          tester.element(find.byType(OrionTitleView)),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('title-campaign-card')),
          matching: find.byType(SpriteWidget),
        ),
        findsOneWidget,
        reason: 'The campaign artwork must load before the screenshot.',
      );
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final pixels = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes!;
      });
      var bluePixels = 0;
      for (var y = 30; y < 110; y++) {
        for (var x = 280; x < 380; x++) {
          final offset = (y * 390 + x) * 4;
          final red = pixels!.getUint8(offset);
          final blue = pixels.getUint8(offset + 2);
          if (blue > 30 && blue > red + 5) bluePixels++;
        }
      }
      expect(
        bluePixels,
        greaterThan(100),
        reason: 'The command-center artwork must cover the right-hand side.',
      );
      await tester.runAsync(
        () => captureReactorRimFixture(boundaryKey, 'title-shell-390x844.png'),
      );
      await tester.tap(find.byKey(const ValueKey('title-primary-cta')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/reactor_rim_ui/boards/nebula.png'),
          tester.element(find.byKey(const ValueKey('stage-briefing'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stage-briefing')),
          matching: find.byType(InternalSpriteWidget),
        ),
        findsWidgets,
        reason: 'Briefing artwork must be painted before capture.',
      );
      await tester.runAsync(
        () =>
            captureReactorRimFixture(boundaryKey, 'briefing-live-390x844.png'),
      );
    });

    testWidgets('title places the four shortcuts on one row at 390x844', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();

      final shortcutRects = [
        for (final tooltip in ['Sectors', 'R&D', 'Codex', 'Settings'])
          tester.getRect(
            find.descendant(
              of: find.byTooltip(tooltip),
              matching: find.byType(InkWell),
            ),
          ),
      ];
      for (final rect in shortcutRects) {
        expect(rect.center.dy, closeTo(shortcutRects.first.center.dy, 1));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      final kicker = tester.getRect(find.text('SPACE TOWER DEFENSE'));
      final wordmark = tester.getRect(find.text('ORION').first);
      expect(kicker.bottom, lessThanOrEqualTo(wordmark.top));
      final card = find.byKey(const ValueKey('title-campaign-card'));
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is OrionAtlasSprite &&
                widget.art.fileName ==
                    'reactor_rim_ui/stages/outpost-alpha.png',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the production page boots into the title, not the map', (
      tester,
    ) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();

      expect(find.byType(OrionTitleView), findsOneWidget);
      expect(find.text('SECTOR MAP'), findsNothing);
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
      expect(find.text('SECTOR MAP'), findsOneWidget);
    });

    testWidgets('the Sectors shortcut opens the world map', (tester) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sectors'));
      await tester.pumpAndSettle();
      expect(find.text('SECTOR MAP'), findsOneWidget);
    });

    testWidgets('the R&D shortcut opens the tech tree', (tester) async {
      await tester.pumpWidget(titleGamePage());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('R&D'));
      await tester.pumpAndSettle();
      expect(findOrionTitle('R&D Lab'), findsOneWidget);
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

    testWidgets('an all-gold campaign reads 21 of 21 medals on the title and '
        'on every menu destination', (tester) async {
      final store = await _storeWithResults(
        _resultsFor(OrionCampaign.stages.map((stage) => stage.id)),
      );
      await tester.pumpWidget(titleGamePage(progressStore: store));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      try {
        void expectMedals() {
          expect(find.text('21/21'), findsOneWidget);
          expect(
            find.bySemanticsLabel('21 of 21 campaign medals'),
            findsOneWidget,
          );
        }

        expectMedals();

        await tester.tap(find.byTooltip('Sectors'));
        await tester.pumpAndSettle();
        expect(find.text('SECTOR MAP'), findsOneWidget);
        expectMedals();

        await tester.tap(find.byTooltip('R&D'));
        await tester.pumpAndSettle();
        expect(findOrionTitle('R&D Lab'), findsOneWidget);
        expectMedals();

        await tester.tap(find.byTooltip('Codex'));
        await tester.pumpAndSettle();
        expect(findOrionTitle('Codex'), findsOneWidget);
        expectMedals();
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a partially cleared optional stage counts its medal against '
        'the same all-stage total', (tester) async {
      final results = _resultsFor(
        OrionCampaign.mainStages.map((stage) => stage.id),
      );
      results[OrionCampaign.sideStages.first.id] = const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 12,
      );
      final store = await _storeWithResults(results);
      await tester.pumpWidget(titleGamePage(progressStore: store));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      try {
        expect(find.text('17/21'), findsOneWidget);
        expect(
          find.bySemanticsLabel('17 of 21 campaign medals'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Sectors'));
        await tester.pumpAndSettle();
        expect(find.text('17/21'), findsOneWidget);
        expect(
          find.bySemanticsLabel('17 of 21 campaign medals'),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('every title shortcut keeps a 48dp interaction region', (
      tester,
    ) async {
      await tester.pumpWidget(
        titleGamePage(
          feedbackPreferencesStore: InMemoryFeedbackPreferencesStore(),
        ),
      );
      await tester.pumpAndSettle();

      for (final tooltip in const ['Sectors', 'R&D', 'Codex', 'Settings']) {
        final rect = tester.getRect(
          find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byType(InkWell),
          ),
        );
        expect(
          rect.width >= 48 && rect.height >= 48,
          isTrue,
          reason: '$tooltip interaction region is $rect',
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(800));
      }
    });

    testWidgets('title shortcuts activate from the edge of their interaction '
        'regions', (tester) async {
      await tester.pumpWidget(
        titleGamePage(
          feedbackPreferencesStore: InMemoryFeedbackPreferencesStore(),
        ),
      );
      await tester.pumpAndSettle();

      Rect inkRect(String tooltip) => tester.getRect(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(InkWell),
        ),
      );

      final settingsRect = inkRect('Settings');
      await tester.tapAt(
        Offset(settingsRect.right - 1, settingsRect.center.dy),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SwitchListTile, 'Sound Effects'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(OrionPrimaryButton, 'Done'));
      await tester.pumpAndSettle();

      final sectorsRect = inkRect('Sectors');
      await tester.tapAt(Offset(sectorsRect.center.dx, sectorsRect.top + 1));
      await tester.pumpAndSettle();
      expect(find.text('SECTOR MAP'), findsOneWidget);
    });

    testWidgets('the Settings shortcut does not fire from its edges while a '
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

      final rect = tester.getRect(
        find.descendant(
          of: find.byTooltip('Settings'),
          matching: find.byType(InkWell),
        ),
      );
      await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
      await tester.pump();
      expect(
        find.widgetWithText(SwitchListTile, 'Sound Effects'),
        findsNothing,
      );

      store.saveCompletions.single.complete();
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SwitchListTile, 'Sound Effects'),
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
