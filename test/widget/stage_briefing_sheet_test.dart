import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/stage_briefing_sheet.dart';

import '../support/orion_finders.dart';
import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

const _productViewport = Size(390, 844);

class _PopRecorder {
  bool? popped;
}

/// Pumps a host that opens [stage]'s briefing through the same modal policy
/// the page uses (scroll-controlled, safe area, transparent background) and
/// records the value the sheet pops with.
Future<_PopRecorder> _pumpBriefing(
  WidgetTester tester, {
  required StageDefinition stage,
  StageResult? result,
  int startingGold = GameBalance.startingGold,
  int startingBaseHealth = GameBalance.initialBaseHealth,
  Size viewport = _productViewport,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final recorder = _PopRecorder();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  sheetAnimationStyle: orionSheetAnimationStyle(context),
                  builder: (_) => StageBriefingSheet(
                    stage: stage,
                    result: result,
                    startingGold: startingGold,
                    startingBaseHealth: startingBaseHealth,
                  ),
                ).then((value) => recorder.popped = value);
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  return recorder;
}

void _expectActionWithinViewport(WidgetTester tester, Size viewport) {
  final action = findOrionTitle('Start Mission');
  expect(action, findsOneWidget);
  tester.ensureVisible(action);
  final rect = tester.getRect(action);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

/// Closes the currently open sheet so a following `_pumpBriefing` replaces
/// the tree with a clean Navigator (identical widget shape would otherwise
/// update in place and keep the old modal route open).
Future<void> _dismissBriefing(WidgetTester tester) async {
  await tester.tap(find.text('Dismiss'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('390x844 primary composition opens with a full-bleed wide hero', (
    tester,
  ) async {
    final stage = OrionCampaign.stageOne;
    await _pumpBriefing(tester, stage: stage);

    expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);

    // The hero consumes the briefingWide descriptor for the stage.
    final hero = find.byType(OrionAtlasSprite);
    expect(hero, findsOneWidget);
    final sprite = tester.widget<OrionAtlasSprite>(hero);
    expect(
      identical(
        sprite.art,
        OrionArt.stage(stage, crop: OrionStageArtCrop.briefingWide),
      ),
      isTrue,
    );

    // Full-bleed: flush with the sheet's left/top edges and full width.
    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('stage-briefing')),
    );
    final heroRect = tester.getRect(hero);
    expect(heroRect.left, sheetRect.left);
    expect(heroRect.top, sheetRect.top);
    expect(heroRect.width, sheetRect.width);

    // No framed inset around the image.
    expect(
      find.ancestor(of: hero, matching: find.byType(OrionSurface)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage name and main/optional identity are shown', (
    tester,
  ) async {
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    expect(findOrionTitle(OrionCampaign.stageOne.name), findsOneWidget);
    expect(find.text('PRIMARY'), findsOneWidget);

    final optional = OrionCampaign.stages.firstWhere(
      (stage) => !stage.isMainPath,
    );
    await _dismissBriefing(tester);
    await _pumpBriefing(tester, stage: optional);
    expect(findOrionTitle(optional.name), findsOneWidget);
    expect(find.text('OPTIONAL'), findsOneWidget);
  });

  testWidgets('waves fact equals the stage wave count', (tester) async {
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);

    final facts = find.byKey(const ValueKey('briefing-facts'));
    expect(facts, findsOneWidget);
    expect(
      find.descendant(of: facts, matching: find.text('WAVES')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: facts,
        matching: find.text('${OrionCampaign.stageOne.waves.length}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hull fact is the supplied effective starting base health', (
    tester,
  ) async {
    // A committed run may supply hardened-core/bonus health beyond the
    // GameBalance default; the sheet must render the supplied value verbatim.
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      startingBaseHealth: 25,
    );

    final facts = find.byKey(const ValueKey('briefing-facts'));
    expect(
      find.descendant(of: facts, matching: find.text('HULL')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('25')),
      findsOneWidget,
    );
  });

  testWidgets('start credits fact is the supplied effective starting gold', (
    tester,
  ) async {
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      startingGold: 180,
    );

    final facts = find.byKey(const ValueKey('briefing-facts'));
    expect(
      find.descendant(of: facts, matching: find.text('START')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('180')),
      findsOneWidget,
    );
  });

  testWidgets('conditions use real stage modifier titles or standard copy', (
    tester,
  ) async {
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    expect(find.text('Standard Conditions'), findsOneWidget);
    expect(find.text('No environmental modifiers'), findsOneWidget);

    final modified = OrionCampaign.stages.firstWhere(
      (stage) => stage.modifiers.isNotEmpty,
    );
    await _dismissBriefing(tester);
    await _pumpBriefing(tester, stage: modified);
    for (final modifier in modified.modifiers) {
      final metadata = StageModifierMetadata.forModifier(modifier);
      expect(find.text(metadata.title), findsOneWidget);
      expect(find.text(metadata.description), findsOneWidget);
    }
  });

  testWidgets('committed prior medal and result appears only when present', (
    tester,
  ) async {
    final bestLine = find.text('Best: Silver • 14 base health');

    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    expect(bestLine, findsNothing);

    await _dismissBriefing(tester);
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
    expect(bestLine, findsOneWidget);
  });

  testWidgets('reward appears only when the stage grants one', (tester) async {
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    expect(find.text('SALVAGE'), findsNothing);

    final rift = OrionCampaign.stages.firstWhere(
      (stage) => stage.id == 'salvage-rift',
    );
    await _dismissBriefing(tester);
    await _pumpBriefing(
      tester,
      stage: rift,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    expect(
      find.text('Reward earned: +${GameBalance.salvageRiftGoldBonus} Gold'),
      findsOneWidget,
    );
  });

  testWidgets('no TOWER CAP tile or copy exists', (tester) async {
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    expect(find.textContaining('TOWER CAP'), findsNothing);
    expect(find.textContaining('Tower Cap'), findsNothing);
  });

  testWidgets('start mission is the single primary action and pops true', (
    tester,
  ) async {
    final recorder = await _pumpBriefing(tester, stage: OrionCampaign.stageOne);

    expect(findOrionTitle('Start Mission'), findsOneWidget);
    expect(findOrionTitle('Replay Mission'), findsNothing);

    await tester.tap(findOrionTitle('Start Mission'));
    await tester.pumpAndSettle();
    expect(recorder.popped, isTrue);
  });

  testWidgets('replay mission when a committed result exists', (tester) async {
    final recorder = await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
    );

    expect(findOrionTitle('Replay Mission'), findsOneWidget);
    expect(findOrionTitle('Start Mission'), findsNothing);

    await tester.tap(findOrionTitle('Replay Mission'));
    await tester.pumpAndSettle();
    expect(recorder.popped, isTrue);
  });

  testWidgets('dismiss path never pops true', (tester) async {
    final recorder = await _pumpBriefing(tester, stage: OrionCampaign.stageOne);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(recorder.popped, isNot(true));
  });

  testWidgets(
    'shared surfaces 375x812 and 844x390 keep the action reachable without overflow',
    (tester) async {
      for (final viewport in const [Size(375, 812), Size(844, 390)]) {
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          viewport: viewport,
        );
        expect(recorder.popped, isNull);
        _expectActionWithinViewport(tester, viewport);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Dismiss'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('3.0x text scale keeps the primary action reachable', (
    tester,
  ) async {
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      textScaler: const TextScaler.linear(3.0),
    );
    _expectActionWithinViewport(tester, _productViewport);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion remains usable', (tester) async {
    final recorder = await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      disableAnimations: true,
    );

    expect(findOrionTitle('Start Mission'), findsOneWidget);
    await tester.tap(findOrionTitle('Start Mission'));
    await tester.pumpAndSettle();
    expect(recorder.popped, isTrue);
  });

  testWidgets('capture scene 1b fixture', (tester) async {
    tester.view.physicalSize = _productViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1b state: Outpost Alpha briefing, fresh run (no
    // committed result), real fonts so the evidence shows true text metrics
    // rather than Ahem blocks.
    await loadRealFonts();
    // The memo can hold a pending future from an earlier cold-cache test
    // in this process; clear it so this fixture's warmed cache is used.
    OrionArtDescriptor.resetSpriteCache();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same key the OrionArt descriptors use) so the hero art renders.
    await tester.runAsync(
      () => Flame.images.load(
        'reactor_rim_ui/stages/${OrionCampaign.stageOne.id}.png',
      ),
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
          home: Scaffold(
            backgroundColor: const Color(0xFF05080D),
            body: StageBriefingSheet(
              stage: OrionCampaign.stageOne,
              result: null,
              startingGold: GameBalance.startingGold,
              startingBaseHealth: GameBalance.initialBaseHealth,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1b.png'),
    );
  });
}
