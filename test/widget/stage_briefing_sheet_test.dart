import 'dart:async';

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
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
  RunMode? popped;

  /// Every (mode, draft) handed to `onLaunch`, in call order.
  final launches = <(RunMode, List<Character>)>[];
}

/// Pumps a host that opens [stage]'s briefing through the same modal policy
/// the page uses (scroll-controlled, safe area, transparent background) and
/// records the value the sheet pops with plus every launch invocation.
Future<_PopRecorder> _pumpBriefing(
  WidgetTester tester, {
  required StageDefinition stage,
  StageResult? result,
  int? endlessBest,
  int startingGold = GameBalance.startingGold,
  int startingBaseHealth = GameBalance.initialBaseHealth,
  List<Character> squad = CampaignSave.starterSquad,
  Map<Character, int> ownedLevels = CampaignSave.starterOwnedLevels,
  Future<bool> Function(RunMode mode, List<Character> draft)? onLaunch,
  Size viewport = _productViewport,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  // Production always opens scroll-controlled, which stretches the sheet to
  // full height and leaves zero barrier area: tests that must reach the
  // barrier's real dismiss inputs opt into the half-height layout here.
  bool isScrollControlled = true,
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
                showModalBottomSheet<RunMode>(
                  context: context,
                  isScrollControlled: isScrollControlled,
                  useSafeArea: true,
                  // Same policy as the page: sheet drags pop imperatively
                  // and cannot consult the launch-save veto.
                  enableDrag: false,
                  backgroundColor: Colors.transparent,
                  sheetAnimationStyle: orionSheetAnimationStyle(context),
                  builder: (_) => StageBriefingSheet(
                    stage: stage,
                    result: result,
                    endlessBest: endlessBest,
                    startingGold: startingGold,
                    startingBaseHealth: startingBaseHealth,
                    squad: squad,
                    ownedLevels: ownedLevels,
                    onLaunch: (mode, draft) async {
                      recorder.launches.add((mode, List.of(draft)));
                      return onLaunch?.call(mode, draft) ?? true;
                    },
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

Future<void> _expectActionWithinViewport(
  WidgetTester tester,
  Size viewport, {
  String actionTooltip = 'Start Mission',
}) async {
  final action = find.byTooltip(actionTooltip);
  expect(action, findsOneWidget);
  // ensureVisible performs a zero-duration jump whose geometry only lands on
  // the next frame; measuring without the pump reads the pre-scroll rect.
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
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
  await tester.tap(find.byTooltip('Dismiss'));
  await tester.pumpAndSettle();
}

/// Scrolls the squad section into view and opens its owned-member picker.
Future<void> _openSquadPicker(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('briefing-squad-edit')));
  await tester.tap(find.byKey(const ValueKey('briefing-squad-edit')));
  await tester.pumpAndSettle();
}

InkWell _launchInkWell(WidgetTester tester, String tooltip) =>
    tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(InkWell),
      ),
    );

/// Fires the modal barrier's own dismiss affordance — the
/// [SemanticsAction.dismiss] the platform dispatches for a11y scrim
/// dismissal — through the real semantics pipeline instead of replaying the
/// `Navigator.maybePop` call the barrier would make. Requires an active
/// [WidgetTester.ensureSemantics] handle so the tree is built.
Future<void> _dismissBarrierViaSemantics(WidgetTester tester) async {
  final barrierSemantics = find.descendant(
    of: find.byType(ModalBarrier),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.onDismiss != null,
    ),
  );
  expect(barrierSemantics, findsOneWidget);
  final node = tester.getSemantics(barrierSemantics);
  expect(node.getSemanticsData().hasAction(SemanticsAction.dismiss), isTrue);
  // Dispatch through the SemanticsOwner that actually owns the app's render
  // view — the same entry point a11y action events use.
  tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.dismiss,
  );
  await tester.pump();
}

/// A route whose push and pop both finish synchronously — its whole
/// lifecycle can land between two builds, which is exactly what lets an
/// inherited `isCurrent` notification coalesce away (true → true).
PageRouteBuilder<void> _instantCover() => PageRouteBuilder<void>(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (_, _, _) =>
      const SizedBox.expand(child: ColoredBox(color: Color(0xFF000000))),
);

void main() {
  testWidgets('390x844 primary composition opens with a full-bleed wide hero', (
    tester,
  ) async {
    final stage = OrionCampaign.stageOne;
    await _pumpBriefing(tester, stage: stage);

    expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);

    // The hero consumes the briefingWide descriptor for the stage.
    final hero = find.byWidgetPredicate(
      (widget) =>
          widget is OrionAtlasSprite &&
          identical(
            widget.art,
            OrionArt.stage(stage, crop: OrionStageArtCrop.briefingWide),
          ),
    );
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
    final heroRect = tester.getRect(
      find.ancestor(of: hero, matching: find.byType(ClipRect)).first,
    );
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
    // The lead modifier's name now sits in the fact-row tile, which shows
    // caps and keeps the real copy as its semantics label; its effect sits
    // under the row. Both must still be reachable.
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('Standard Conditions'), findsOneWidget);
      expect(find.text('No environmental modifiers'), findsOneWidget);

      final modified = OrionCampaign.stages.firstWhere(
        (stage) => stage.modifiers.isNotEmpty,
      );
      await _dismissBriefing(tester);
      await _pumpBriefing(tester, stage: modified);
      for (final modifier in modified.modifiers) {
        final metadata = StageModifierMetadata.forModifier(modifier);
        expect(
          find.bySemanticsLabel(metadata.title),
          findsOneWidget,
          reason: '${metadata.title} is not announced anywhere in the briefing',
        );
        expect(find.text(metadata.description), findsOneWidget);
      }
    } finally {
      semanticsHandle.dispose();
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

  testWidgets(
    'locked blueprint teaser shows the module name and exact effect',
    (tester) async {
      await _pumpBriefing(tester, stage: OrionCampaign.stageOne);

      final module = runModuleDefinition(OrionCampaign.stageOne.blueprint!);
      expect(
        find.text('Blueprint locked: ${module.title} • ${module.effectText}'),
        findsOneWidget,
      );
      expect(find.textContaining('Blueprint recovered'), findsNothing);
      expect(find.text('BLUEPRINT'), findsOneWidget);
    },
  );

  testWidgets(
    'committed result flips the briefing row to Blueprint recovered',
    (tester) async {
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
      );

      final module = runModuleDefinition(OrionCampaign.stageOne.blueprint!);
      expect(
        find.text(
          'Blueprint recovered: ${module.title} • ${module.effectText}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Blueprint locked'), findsNothing);
    },
  );

  testWidgets('side-stage briefing keeps SALVAGE and BLUEPRINT rows separate', (
    tester,
  ) async {
    final rift = OrionCampaign.stages.firstWhere(
      (stage) => stage.id == 'salvage-rift',
    );
    final module = runModuleDefinition(rift.blueprint!);

    await _pumpBriefing(tester, stage: rift);
    expect(
      find.text('Blueprint locked: ${module.title} • ${module.effectText}'),
      findsOneWidget,
    );

    await _dismissBriefing(tester);
    await _pumpBriefing(
      tester,
      stage: rift,
      result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    expect(
      find.text('Blueprint recovered: ${module.title} • ${module.effectText}'),
      findsOneWidget,
    );
    // The independent campaign reward keeps its own row.
    expect(find.text('SALVAGE'), findsOneWidget);
    expect(
      find.text('Reward earned: +${GameBalance.salvageRiftGoldBonus} Gold'),
      findsOneWidget,
    );
    expect(find.text('BLUEPRINT'), findsOneWidget);
  });

  testWidgets('every blueprint stage briefs its module name and exact effect', (
    tester,
  ) async {
    for (final stage in OrionCampaign.stages) {
      final module = runModuleDefinition(stage.blueprint!);
      await _pumpBriefing(tester, stage: stage);
      expect(
        find.text('Blueprint locked: ${module.title} • ${module.effectText}'),
        findsOneWidget,
        reason: stage.id,
      );
      await _dismissBriefing(tester);
    }
  });

  testWidgets(
    'fully loaded side-stage briefing keeps the action reachable at 360x640',
    (tester) async {
      const viewport = Size(360, 640);
      final rift = OrionCampaign.stages.firstWhere(
        (stage) => stage.id == 'salvage-rift',
      );
      await _pumpBriefing(
        tester,
        stage: rift,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        viewport: viewport,
      );
      await _expectActionWithinViewport(
        tester,
        viewport,
        actionTooltip: 'Replay Mission',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no TOWER CAP tile or copy exists', (tester) async {
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    expect(find.textContaining('TOWER CAP'), findsNothing);
    expect(find.textContaining('Tower Cap'), findsNothing);
  });

  testWidgets(
    'start mission is the single primary action and pops RunMode.mission',
    (tester) async {
      final recorder = await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
      );

      expect(find.byTooltip('Start Mission'), findsOneWidget);
      expect(find.byTooltip('Replay Mission'), findsNothing);
      expect(find.byTooltip('Endless'), findsNothing);

      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();
      expect(recorder.popped, RunMode.mission);
    },
  );

  testWidgets('replay mission when a committed result exists', (tester) async {
    final recorder = await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
    );

    expect(find.byTooltip('Replay Mission'), findsOneWidget);
    expect(find.byTooltip('Start Mission'), findsNothing);

    await tester.tap(find.byTooltip('Replay Mission'));
    await tester.pumpAndSettle();
    expect(recorder.popped, RunMode.mission);
  });

  testWidgets('dismiss pops null without a cast error', (tester) async {
    final recorder = await _pumpBriefing(tester, stage: OrionCampaign.stageOne);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    // The modal is typed RunMode: a bool pop would throw a runtime cast
    // error and leave the recorder unset.
    expect(recorder.popped, isNull);
    expect(tester.takeException(), isNull);
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
        await _expectActionWithinViewport(tester, viewport);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Dismiss'));
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
    await _expectActionWithinViewport(tester, _productViewport);
    expect(tester.takeException(), isNull);
  });

  for (final (viewport, scale) in [
    (const Size(320, 568), 2.0),
    (const Size(320, 568), 3.0),
    (const Size(320, 568), 4.0),
    (const Size(360, 640), 3.0),
  ]) {
    testWidgets(
      'briefing facts and threats remain readable at $viewport and ${scale}x',
      (tester) async {
        await loadRealFonts();
        await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          viewport: viewport,
          textScaler: TextScaler.linear(scale),
        );

        for (final label in [
          'WAVES',
          'HULL',
          'START',
          'HOSTILES',
          'ARMORED',
          'SHIELDED',
        ]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$label is truncated',
          );
          expect(
            paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            ),
            hasLength(1),
            reason: '$label must not split mid-word',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('large-text briefing content does not scroll behind dismiss', (
    tester,
  ) async {
    await loadRealFonts();
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      viewport: const Size(360, 640),
      textScaler: const TextScaler.linear(3),
    );
    final heading = find.text('THREAT PROFILE');
    await tester.ensureVisible(heading);
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(heading)
          .overlaps(tester.getRect(find.byTooltip('Dismiss'))),
      isFalse,
    );
  });

  for (final scale in [3.0, 4.0]) {
    testWidgets('medal criteria keep whole words at 320 and ${scale}x', (
      tester,
    ) async {
      await loadRealFonts();
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        viewport: const Size(320, 568),
        textScaler: TextScaler.linear(scale),
      );
      for (final (text, word) in [
        ('GOLD · NO LEAKS', 'LEAKS'),
        ('SILVER', 'SILVER'),
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        final start = text.indexOf(word);
        expect(
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + word.length),
          ),
          hasLength(1),
          reason: '$word must not split across lines',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('blueprint heading stays in one piece at 320 and 4x', (
    tester,
  ) async {
    await loadRealFonts();
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      viewport: const Size(320, 568),
      textScaler: const TextScaler.linear(4),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('BLUEPRINT'),
    );
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 9),
      ),
      hasLength(1),
    );
  });

  testWidgets('replay and endless actions scale on a narrow display', (
    tester,
  ) async {
    await loadRealFonts();
    const viewport = Size(320, 568);
    const result = StageResult(medal: StageMedal.silver, bestBaseHealth: 14);
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: result,
      viewport: viewport,
    );
    final initial = tester
        .getRect(
          find.descendant(
            of: find.byTooltip('Endless'),
            matching: find.text('ENDLESS'),
          ),
        )
        .height;
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: result,
      viewport: viewport,
      textScaler: const TextScaler.linear(1.2),
    );
    final intermediate = find.descendant(
      of: find.byTooltip('Endless'),
      matching: find.text('ENDLESS'),
    );
    expect(tester.getRect(intermediate).height, greaterThan(initial * 1.1));
    for (final tooltip in ['Replay Mission', 'Endless']) {
      expect(
        tester.getRect(find.byTooltip(tooltip)).height,
        greaterThanOrEqualTo(48),
      );
    }
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: result,
      viewport: viewport,
      textScaler: const TextScaler.linear(3),
    );
    final action = find.byTooltip('Endless');
    final label = find.descendant(of: action, matching: find.text('ENDLESS'));
    expect(tester.getRect(label).height, greaterThan(initial * 2.3));
    final scroll = find.descendant(
      of: find.byType(StageBriefingSheet),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.getRect(scroll).height,
      greaterThanOrEqualTo(300),
      reason: 'Large launch actions must leave room to read the briefing.',
    );
    await _expectActionWithinViewport(
      tester,
      viewport,
      actionTooltip: 'Endless',
    );
    await _expectActionWithinViewport(
      tester,
      viewport,
      actionTooltip: 'Replay Mission',
    );
  });

  for (final (tooltip, expected) in [
    ('Replay Mission', RunMode.mission),
    ('Endless', RunMode.endless),
  ]) {
    testWidgets('large-text $tooltip launches the correct mode', (
      tester,
    ) async {
      await loadRealFonts();
      final recorder = await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
        viewport: const Size(320, 568),
        textScaler: const TextScaler.linear(3),
      );
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(recorder.popped, expected);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide landscape briefing keeps room for its content at 3x', (
    tester,
  ) async {
    await loadRealFonts();
    const viewport = Size(568, 320);
    await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      result: const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      viewport: viewport,
      textScaler: const TextScaler.linear(3),
    );
    final scroll = find.descendant(
      of: find.byType(StageBriefingSheet),
      matching: find.byType(Scrollable),
    );
    expect(tester.getRect(scroll).height, greaterThanOrEqualTo(100));
    await _expectActionWithinViewport(
      tester,
      viewport,
      actionTooltip: 'Replay Mission',
    );
    await _expectActionWithinViewport(
      tester,
      viewport,
      actionTooltip: 'Endless',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('briefing shows a scroll cue for the hidden blueprint', (
    tester,
  ) async {
    await loadRealFonts();
    await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
    final briefing = find.byType(StageBriefingSheet);
    final scroll = find.descendant(
      of: briefing,
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scroll);
    expect(state.position.maxScrollExtent, greaterThan(0));
    final scrollbar = find.descendant(
      of: briefing,
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollbar && widget.thumbVisibility == true,
      ),
    );
    expect(scrollbar, findsOneWidget);
    final blueprint = find.textContaining(
      'Blueprint locked: Relay Calibration',
    );
    await tester.drag(scroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
    final viewport = tester.getRect(scroll);
    final blueprintRect = tester.getRect(blueprint);
    expect(blueprintRect.top, greaterThanOrEqualTo(viewport.top));
    expect(blueprintRect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion remains usable', (tester) async {
    final recorder = await _pumpBriefing(
      tester,
      stage: OrionCampaign.stageOne,
      disableAnimations: true,
    );

    expect(find.byTooltip('Start Mission'), findsOneWidget);
    await tester.tap(find.byTooltip('Start Mission'));
    await tester.pumpAndSettle();
    expect(recorder.popped, RunMode.mission);
  });

  group('endless launch action', () {
    testWidgets('uncleared stage offers no Endless action and no best line', (
      tester,
    ) async {
      await _pumpBriefing(tester, stage: OrionCampaign.stageOne);

      expect(find.byTooltip('Endless'), findsNothing);
      expect(find.text('ENDLESS'), findsNothing);
      expect(find.text('No endless run yet'), findsNothing);
      expect(find.textContaining('Endless best:'), findsNothing);
    });

    testWidgets(
      'cleared stage without a run shows "No endless run yet" and Endless pops RunMode.endless',
      (tester) async {
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
        );

        expect(find.text('No endless run yet'), findsOneWidget);
        expect(find.byTooltip('Endless'), findsOneWidget);

        await tester.tap(find.byTooltip('Endless'));
        await tester.pumpAndSettle();
        expect(recorder.popped, RunMode.endless);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cleared stage shows the saved best and Endless pops RunMode.endless',
      (tester) async {
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
          endlessBest: 17,
        );

        expect(find.text('Endless best: 17 waves'), findsOneWidget);
        expect(find.text('No endless run yet'), findsNothing);

        await tester.tap(find.byTooltip('Endless'));
        await tester.pumpAndSettle();
        expect(recorder.popped, RunMode.endless);
      },
    );

    testWidgets('cleared stage shows singular wave for endless best of 1', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        result: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        endlessBest: 1,
      );

      expect(find.text('Endless best: 1 wave'), findsOneWidget);
    });

    testWidgets('launch kickers render DEPLOY, REPLAY, and ENDLESS', (
      tester,
    ) async {
      await _pumpBriefing(tester, stage: OrionCampaign.stageOne);
      expect(
        find.descendant(
          of: find.byTooltip('Start Mission'),
          matching: find.text('DEPLOY'),
        ),
        findsOneWidget,
      );

      await _dismissBriefing(tester);
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
      );
      expect(
        find.descendant(
          of: find.byTooltip('Replay Mission'),
          matching: find.text('REPLAY'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byTooltip('Endless'),
          matching: find.text('ENDLESS'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'cleared stage keeps both launch actions reachable at 360x640',
      (tester) async {
        const viewport = Size(360, 640);
        await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          result: const StageResult(medal: StageMedal.clear, bestBaseHealth: 5),
          endlessBest: 9,
          viewport: viewport,
        );

        await _expectActionWithinViewport(
          tester,
          viewport,
          actionTooltip: 'Replay Mission',
        );
        await _expectActionWithinViewport(
          tester,
          viewport,
          actionTooltip: 'Endless',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cleared stage keeps both launch actions reachable and tappable at 360x640 and 2x text scale',
      (tester) async {
        const viewport = Size(360, 640);
        const result = StageResult(medal: StageMedal.clear, bestBaseHealth: 5);

        final firstRecorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          result: result,
          endlessBest: 9,
          viewport: viewport,
          textScaler: const TextScaler.linear(2),
        );
        await _expectActionWithinViewport(
          tester,
          viewport,
          actionTooltip: 'Replay Mission',
        );
        await _expectActionWithinViewport(
          tester,
          viewport,
          actionTooltip: 'Endless',
        );
        await tester.tap(find.byTooltip('Replay Mission'));
        await tester.pumpAndSettle();
        expect(firstRecorder.popped, RunMode.mission);

        final secondRecorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          result: result,
          endlessBest: 9,
          viewport: viewport,
          textScaler: const TextScaler.linear(2),
        );
        await _expectActionWithinViewport(
          tester,
          viewport,
          actionTooltip: 'Replay Mission',
        );
        await _expectActionWithinViewport(
          tester,
          viewport,
          actionTooltip: 'Endless',
        );
        await tester.tap(find.byTooltip('Endless'));
        await tester.pumpAndSettle();
        expect(secondRecorder.popped, RunMode.endless);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('artboard 1b fact row', () {
    testWidgets('is four tiles: waves, hull, start, and the modifier', (
      tester,
    ) async {
      await _pumpBriefing(tester, stage: OrionCampaign.stages.first);

      final row = find.byKey(const ValueKey('briefing-facts'));
      expect(row, findsOneWidget);
      for (final label in ['WAVES', 'HULL', 'START', 'MODIFIER']) {
        expect(
          find.descendant(of: row, matching: find.text(label)),
          findsOneWidget,
          reason: 'the fact row is missing its $label tile',
        );
      }
      expect(find.byKey(const ValueKey('briefing-modifier')), findsOneWidget);
    });

    testWidgets('renders the START figure in credit gold', (tester) async {
      // The tile took a `color` and never read it, so START arrived as
      // creditGold and rendered white with the rest. Assert the figure, not
      // the argument.
      await _pumpBriefing(tester, stage: OrionCampaign.stages.first);

      final figure = tester.widget<Text>(
        find.text('${GameBalance.startingGold}'),
      );

      expect(
        figure.style!.color!.toARGB32(),
        OrionUiTheme.dark.creditGold.toARGB32(),
      );
    });

    testWidgets('the modifier tile paints its full title at 390 and 360', (
      tester,
    ) async {
      for (final viewport in const [Size(390, 844), Size(360, 640)]) {
        await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          viewport: viewport,
        );

        expect(tester.takeException(), isNull);
        final tile = find.byKey(const ValueKey('briefing-modifier'));
        final title = find.descendant(
          of: tile,
          matching: find.text('STANDARD CONDITIONS'),
        );
        expect(
          title,
          findsOneWidget,
          reason: 'the modifier name must stay complete at $viewport',
        );

        final text = tester.widget<Text>(title);
        expect(
          text.style!.fontSize,
          greaterThanOrEqualTo(10),
          reason: 'modifier copy dropped below the kit label floor',
        );
        expect(
          find.descendant(
            of: tile,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'Standard Conditions',
            ),
          ),
          findsOneWidget,
        );

        final paragraph = tester.renderObject<RenderParagraph>(title);
        final span = 'STANDARD CONDITIONS';
        final lastWord = TextPainter(
          text: TextSpan(text: 'CONDITIONS', style: paragraph.text.style),
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout();
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: span.indexOf('CONDITIONS'),
            extentOffset: span.length,
          ),
        );
        final painted = boxes.fold<double>(
          0,
          (width, box) => width + (box.right - box.left),
        );
        expect(
          painted,
          greaterThanOrEqualTo(lastWord.width - 1),
          reason:
              'CONDITIONS painted ${painted}px of ${lastWord.width}px at '
              '$viewport — the name is being ellipsized',
        );

        await _dismissBriefing(tester);
      }
    });

    testWidgets('fits four tiles at product width and 2x text scale', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stages.first,
        textScaler: const TextScaler.linear(2),
      );

      final row = tester.getRect(find.byKey(const ValueKey('briefing-facts')));
      expect(row.left, greaterThanOrEqualTo(0));
      expect(row.right, lessThanOrEqualTo(_productViewport.width));
      expect(tester.takeException(), isNull);
    });
  });

  group('squad draft (HPA-922 task 6)', () {
    const owned = {
      Character.haruto: 1,
      Character.mio: 2,
      Character.sayo: 3,
      Character.rin: 2,
      Character.elena: 1,
      Character.kaito: 4,
      Character.tetsuo: 2,
    };

    testWidgets('squad tokens render the saved roster in order', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        ownedLevels: owned,
        squad: const [Character.mio, Character.haruto, Character.sayo],
      );

      expect(find.text('YOUR SQUAD'), findsOneWidget);
      expect(find.textContaining('3 / 6'), findsWidgets);
      final positions = <double>[];
      for (final member in const [
        Character.mio,
        Character.haruto,
        Character.sayo,
      ]) {
        final token = find.byKey(
          ValueKey('briefing-squad-token-${member.name}'),
        );
        await tester.ensureVisible(token);
        positions.add(tester.getRect(token).left);
      }
      expect(positions[0], lessThan(positions[1]));
      expect(positions[1], lessThan(positions[2]));
    });

    testWidgets(
      'draft edits stay local and Cancel discards them without a launch',
      (tester) async {
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          squad: const [Character.haruto, Character.mio],
        );

        await _openSquadPicker(tester);
        await tester.tap(
          find.byKey(const ValueKey('briefing-squad-pick-sayo')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('briefing-squad-token-sayo')),
          findsOneWidget,
        );

        // Removing from the token row mutates only the local draft.
        await tester.tap(
          find.byKey(const ValueKey('briefing-squad-token-haruto')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('briefing-squad-token-haruto')),
          findsNothing,
        );
        expect(recorder.launches, isEmpty);

        // Cancel pops null and performs no write at all.
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pumpAndSettle();
        expect(recorder.popped, isNull);
        expect(recorder.launches, isEmpty);
      },
    );

    testWidgets(
      'a v4-filtered empty draft disables launch until a member is picked',
      (tester) async {
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          squad: const [],
        );

        expect(
          find.text('Select at least one squad member to deploy.'),
          findsOneWidget,
        );
        expect(_launchInkWell(tester, 'Start Mission').onTap, isNull);
        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pumpAndSettle();
        expect(recorder.launches, isEmpty);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);

        await _openSquadPicker(tester);
        await tester.tap(
          find.byKey(const ValueKey('briefing-squad-pick-haruto')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Select at least one squad member to deploy.'),
          findsNothing,
        );
        expect(_launchInkWell(tester, 'Start Mission').onTap, isNotNull);
      },
    );

    testWidgets('the six-member cap rejects a seventh with feedback', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        ownedLevels: owned,
        squad: const [
          Character.haruto,
          Character.mio,
          Character.sayo,
          Character.rin,
          Character.elena,
          Character.kaito,
        ],
      );

      await _openSquadPicker(tester);
      await tester.tap(
        find.byKey(const ValueKey('briefing-squad-pick-tetsuo')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Squad is full — remove a member first.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-squad-token-tetsuo')),
        findsNothing,
      );
    });

    testWidgets('launch passes the draft order and pops once on commit', (
      tester,
    ) async {
      final recorder = await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        ownedLevels: owned,
        squad: const [Character.haruto, Character.mio],
      );

      // Reorder: drop Haruto, re-add it — the explicit draft order places the
      // re-added member last.
      await _openSquadPicker(tester);
      await tester.tap(
        find.byKey(const ValueKey('briefing-squad-pick-haruto')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('briefing-squad-pick-haruto')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('briefing-squad-pick-sayo')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();

      expect(recorder.launches, hasLength(1));
      expect(recorder.launches.single.$1, RunMode.mission);
      expect(recorder.launches.single.$2, [
        Character.mio,
        Character.haruto,
        Character.sayo,
      ]);
      expect(recorder.popped, RunMode.mission);
    });

    testWidgets(
      'a pending launch disables launch and dismiss, keeps the sheet mounted',
      (tester) async {
        final gate = Completer<bool>();
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) => gate.future,
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();
        expect(recorder.launches, hasLength(1));
        expect(find.text('Saving squad…'), findsOneWidget);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(_launchInkWell(tester, 'Start Mission').onTap, isNull);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
              )
              .onPressed,
          isNull,
        );

        // A second tap while saving must not queue a second write, and the
        // route must not be poppable while the save is in flight.
        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();
        expect(recorder.launches, hasLength(1));
        final sheetContext = tester.element(find.byType(StageBriefingSheet));
        expect(
          ModalRoute.of(sheetContext)!.popDisposition,
          RoutePopDisposition.doNotPop,
        );

        gate.complete(true);
        await tester.pumpAndSettle();
        expect(recorder.popped, RunMode.mission);
      },
    );

    testWidgets(
      'a launch in flight vetoes same-frame dismiss, back and barrier '
      'dismissal, and the failure restores dismissal',
      (tester) async {
        // Disposed explicitly at the end — the binding's handle check runs
        // before addTearDown callbacks.
        final semantics = tester.ensureSemantics();
        final gate = Completer<bool>();
        // Half-height leaves real scrim above the sheet, so the barrier's
        // dismiss affordances — the scrim-tap gesture and the a11y dismiss
        // action — are genuine inputs a user could make, not replays of the
        // maybePop call the barrier would issue internally.
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) => gate.future,
          isScrollControlled: false,
        );
        final sheetRect = tester.getRect(
          find.byKey(const ValueKey('stage-briefing')),
        );
        expect(sheetRect.top, greaterThan(0));
        final scrimTap = Offset(sheetRect.center.dx, sheetRect.top / 2);

        await tester.ensureVisible(find.byTooltip('Start Mission'));
        await tester.tap(find.byTooltip('Start Mission'));
        // No pump: the save is already in flight but the sheet has not
        // rebuilt once, so every dismissal surface still holds its pre-launch
        // wiring — the IconButton's stale callback, the system back path and
        // the barrier's real dismiss inputs must all be vetoed synchronously.
        await tester.tap(find.byTooltip('Dismiss'));
        await tester.binding.handlePopRoute();
        await tester.tapAt(scrimTap);
        await _dismissBarrierViaSemantics(tester);
        await tester.pump();

        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(recorder.launches, hasLength(1));
        expect(recorder.popped, isNull);

        // The veto lifts with the failure: the same real barrier dismiss
        // action now pops the route.
        gate.complete(false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );

        await _dismissBarrierViaSemantics(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets(
      'a save that commits while a pushed route covers the sheet finishes '
      'once uncovered — the cover stays and no second launch runs',
      (tester) async {
        final gate = Completer<bool>();
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) => gate.future,
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();

        // Cover the briefing with a pushed route while the save is in
        // flight: the sheet route stays active but is no longer current.
        final sheetContext = tester.element(find.byType(StageBriefingSheet));
        final route = ModalRoute.of(sheetContext)!;
        unawaited(
          showDialog<void>(
            context: sheetContext,
            builder: (_) => const AlertDialog(content: Text('covering')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('covering'), findsOneWidget);
        expect(route.isCurrent, isFalse);
        expect(route.isActive, isTrue);

        // The save commits while covered: the write stands, but the
        // covering route must not be popped and the sheet must not wedge
        // behind it on a permanent "Saving squad…".
        gate.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('covering'), findsOneWidget);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(recorder.popped, isNull);
        expect(recorder.launches, hasLength(1));

        // Lifting the cover finishes the pending launch: the sheet pops
        // once with the mode and no second save is written.
        Navigator.of(tester.element(find.text('covering'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('covering'), findsNothing);
        expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
        expect(recorder.popped, RunMode.mission);
        expect(recorder.launches, hasLength(1));
      },
    );

    testWidgets(
      'a deferred launch finishes after a cover pushed and popped inside '
      'one frame — no isCurrent notification is ever built',
      (tester) async {
        final gate = Completer<bool>();
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) => gate.future,
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();

        final sheetContext = tester.element(find.byType(StageBriefingSheet));
        final navigator = Navigator.of(sheetContext);
        unawaited(navigator.push(_instantCover()));
        expect(ModalRoute.of(sheetContext)!.isCurrent, isFalse);

        // The save commits while covered, then the cover is popped — all
        // before a single build, so _ModalScopeStatus never observes
        // isCurrent:false and no dependency notification can refire. idle()
        // runs microtasks without a frame so _launch still sees the cover.
        gate.complete(true);
        await tester.idle();
        navigator.pop();
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
        expect(recorder.popped, RunMode.mission);
        expect(recorder.launches, hasLength(1));
      },
    );

    testWidgets(
      'a deferred launch survives a re-cover that lands before the deferred '
      'post-frame callback and lifts before the next build',
      (tester) async {
        final gate = Completer<bool>();
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) => gate.future,
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();

        final sheetContext = tester.element(find.byType(StageBriefingSheet));
        final navigator = Navigator.of(sheetContext);
        unawaited(
          showDialog<void>(
            context: sheetContext,
            builder: (_) => const AlertDialog(content: Text('covering')),
          ),
        );
        await tester.pumpAndSettle();

        // The save commits while covered; the finish waits for the sheet
        // to become current again.
        gate.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('covering'), findsOneWidget);
        expect(recorder.popped, isNull);

        // Pop the cover, then queue a callback that re-covers the sheet
        // inside the same post-frame window the deferred finish is
        // scheduled into — FIFO order puts the re-cover first — and a
        // microtask that removes it before the next inherited-status build.
        Navigator.of(sheetContext).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(navigator.push(_instantCover()));
          scheduleMicrotask(() => navigator.pop());
        });
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('stage-briefing')), findsNothing);
        expect(recorder.popped, RunMode.mission);
        expect(recorder.launches, hasLength(1));
      },
    );

    testWidgets(
      'a downward swipe during a pending save cannot dismiss the sheet '
      'before a commit',
      (tester) async {
        final gate = Completer<bool>();
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) => gate.future,
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();
        expect(find.text('Saving squad…'), findsOneWidget);

        // The bottom-sheet drag path pops the route directly — a fling on
        // the launch chrome must not strand the save or the retry surface.
        await tester.fling(
          find.byTooltip('Start Mission'),
          const Offset(0, 300),
          1200,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(recorder.popped, isNull);

        gate.complete(true);
        await tester.pumpAndSettle();
        expect(recorder.popped, RunMode.mission);
      },
    );

    testWidgets(
      'a downward swipe during a pending save keeps the failure retry '
      'surface',
      (tester) async {
        var attempts = 0;
        final gate = Completer<bool>();
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          onLaunch: (mode, draft) {
            attempts++;
            return attempts == 1 ? gate.future : Future<bool>.value(true);
          },
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pump();
        await tester.fling(
          find.byTooltip('Start Mission'),
          const Offset(0, 300),
          1200,
        );
        await tester.pump();

        gate.complete(false);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );
        expect(recorder.popped, isNull);

        // The surviving retry surface launches on the second attempt.
        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(recorder.popped, RunMode.mission);
      },
    );

    testWidgets('a synchronously throwing launch callback keeps the draft and '
        'restores the retry surface', (tester) async {
      var attempts = 0;
      final recorder = await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        ownedLevels: owned,
        squad: const [Character.haruto, Character.mio],
        onLaunch: (mode, draft) {
          attempts++;
          if (attempts == 1) {
            throw StateError('synchronous launch failure');
          }
          return Future<bool>.value(true);
        },
      );

      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();

      // The throw lands on the same failure path as a clean `false`: the
      // sheet stays up, the draft survives and controls unlock.
      expect(attempts, 1);
      expect(recorder.popped, isNull);
      expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
      expect(
        find.text(
          'Could not save squad changes — tap a launch action to retry.',
        ),
        findsOneWidget,
      );
      expect(find.text('Saving squad…'), findsNothing);
      expect(_launchInkWell(tester, 'Start Mission').onTap, isNotNull);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byTooltip('Start Mission'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(recorder.popped, RunMode.mission);
    });

    testWidgets(
      'a rejected launch future keeps the draft and restores the retry '
      'surface',
      (tester) async {
        var attempts = 0;
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          squad: const [Character.haruto, Character.mio],
          onLaunch: (mode, draft) {
            attempts++;
            return attempts == 1
                ? Future<bool>.error(StateError('rejected save'))
                : Future<bool>.value(true);
          },
        );

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pumpAndSettle();

        expect(attempts, 1);
        expect(recorder.popped, isNull);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );
        expect(_launchInkWell(tester, 'Start Mission').onTap, isNotNull);

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(recorder.popped, RunMode.mission);
      },
    );

    testWidgets('squad controls meet the 48px touch-target floor in both '
        'dimensions', (tester) async {
      // Real ChakraPetch metrics — placeholder glyphs would fake the EDIT
      // width that the floor must constrain.
      await loadRealFonts();
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        ownedLevels: owned,
        squad: const [Character.haruto, Character.mio],
      );

      final edit = find.byKey(const ValueKey('briefing-squad-edit'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      var editRect = tester.getRect(edit);
      expect(editRect.width, greaterThanOrEqualTo(48));
      expect(editRect.height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('briefing-squad-token-haruto')))
            .height,
        greaterThanOrEqualTo(48),
      );

      await _openSquadPicker(tester);
      // DONE replaces EDIT while the picker is open — same floor both ways.
      editRect = tester.getRect(edit);
      expect(editRect.width, greaterThanOrEqualTo(48));
      expect(editRect.height, greaterThanOrEqualTo(48));
      final pick = find.byKey(const ValueKey('briefing-squad-pick-sayo'));
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      expect(tester.getRect(pick).height, greaterThanOrEqualTo(48));
    });

    testWidgets(
      'a failed launch keeps the sheet open with retryable feedback and the '
      'draft intact',
      (tester) async {
        var attempts = 0;
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          ownedLevels: owned,
          squad: const [Character.haruto, Character.mio],
          onLaunch: (mode, draft) async => ++attempts > 1,
        );

        // Token removal is a draft edit — the squad section sits below the
        // fold at product size, so reveal it before tapping.
        await tester.ensureVisible(
          find.byKey(const ValueKey('briefing-squad-token-mio')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('briefing-squad-token-mio')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pumpAndSettle();
        expect(attempts, 1);
        expect(recorder.popped, isNull);
        expect(find.byKey(const ValueKey('stage-briefing')), findsOneWidget);
        expect(
          find.text(
            'Could not save squad changes — tap a launch action to retry.',
          ),
          findsOneWidget,
        );
        // The draft survived the failed write and the action stays retryable.
        expect(
          find.byKey(const ValueKey('briefing-squad-token-mio')),
          findsNothing,
        );
        expect(_launchInkWell(tester, 'Start Mission').onTap, isNotNull);

        await tester.tap(find.byTooltip('Start Mission'));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(recorder.launches, hasLength(2));
        expect(recorder.launches.last.$2, [Character.haruto]);
        expect(recorder.popped, RunMode.mission);
      },
    );

    for (final (tooltip, expected) in [
      ('Replay Mission', RunMode.mission),
      ('Endless', RunMode.endless),
    ]) {
      testWidgets('$tooltip goes through onLaunch with the draft', (
        tester,
      ) async {
        final recorder = await _pumpBriefing(
          tester,
          stage: OrionCampaign.stageOne,
          result: const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
          ownedLevels: owned,
          squad: const [Character.mio, Character.haruto],
        );

        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();

        expect(recorder.launches, hasLength(1));
        expect(recorder.launches.single.$1, expected);
        expect(recorder.launches.single.$2, [Character.mio, Character.haruto]);
        expect(recorder.popped, expected);
      });
    }

    testWidgets('squad section stays readable at 320x568 and 2x text', (
      tester,
    ) async {
      await loadRealFonts();
      await _pumpBriefing(
        tester,
        stage: OrionCampaign.stageOne,
        ownedLevels: owned,
        squad: const [Character.haruto],
        viewport: const Size(320, 568),
        textScaler: const TextScaler.linear(2),
      );
      await _openSquadPicker(tester);
      expect(find.text('YOUR SQUAD'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The last owned member in picker order must still be reachable on the
      // smallest viewport: scroll it in and confirm the tap edits the draft.
      final lastPick = find.byKey(const ValueKey('briefing-squad-pick-mio'));
      await tester.ensureVisible(lastPick);
      await tester.pumpAndSettle();
      await tester.tap(lastPick);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('briefing-squad-token-mio')),
        findsOneWidget,
      );
      expect(find.textContaining('2 / 6'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
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
    await tester.runAsync(() async {
      await Flame.images.load(
        'reactor_rim_ui/stages/${OrionCampaign.stageOne.id}.png',
      );
      await Flame.images.load('orion_sprite_sheet.png');
      await Flame.images.load('orion_tower_variety_sheet.png');
    });
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
              squad: CampaignSave.starterSquad,
              ownedLevels: CampaignSave.starterOwnedLevels,
              onLaunch: (mode, draft) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/reactor_rim_ui/boards/nebula.png'),
        tester.element(find.byType(StageBriefingSheet)),
      ),
    );
    await tester.pump();

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1b.png'),
    );
  });
}
