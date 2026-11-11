import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/campaign_presentation.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
import 'package:orion/game/ui/orion_menu_shell.dart';
import 'package:orion/game/ui/orion_surface.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';
import 'package:orion/game/ui/world_map_view.dart';

import '../support/reactor_rim_visual_capture.dart';
import '../support/real_fonts.dart';

CampaignProgress clearedCampaignProgress() => CampaignProgress(
  bestResultsByStageId: {
    for (final stage in OrionCampaign.stages)
      stage.id: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
  },
);

/// All five main stages cleared plus the supplied side stages, so main
/// completion is unambiguous while optional progress stays parameterizable.
CampaignProgress mainCompleteProgress({
  Set<String> clearedSideStages = const {},
}) => CampaignProgress(
  bestResultsByStageId: {
    for (final stage in OrionCampaign.stages.where((stage) => stage.isMainPath))
      stage.id: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    for (final id in clearedSideStages)
      id: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
  },
);

const shellControlTooltips = ['Map', 'R&D', 'Codex', 'Settings'];

Widget buildMap({
  required CampaignProgress progress,
  List<StageDefinition>? stages,
  CampaignModifiers? campaignModifiers,
  ValueChanged<StageDefinition>? onStageSelected,
  ValueChanged<StageDefinition>? onLockedStageSelected,
  ValueChanged<OrionMenuDestination>? onDestinationSelected,
  VoidCallback? onOpenSettings,
  String? feedback,
  bool isSavingProgress = false,
  bool isResetting = false,
  bool isSavingFeedback = false,
  bool inShell = false,
  TextScaler? textScaler,
}) {
  final resolvedStages = stages ?? OrionCampaign.stages;
  final map = WorldMapView(
    stages: resolvedStages,
    progress: progress,
    embeddedInMenuShell: inShell,
    // Production always derives modifiers from progress; default to the
    // same derivation so fixture headers (e.g. the Challenge Badge) match
    // what players see. Explicit modifiers still override this default.
    campaignModifiers:
        campaignModifiers ??
        CampaignModifiers.fromProgress(
          progress,
          resolvedStages,
          CampaignTechTree(),
        ),
    feedback: feedback,
    isSavingProgress: isSavingProgress,
    isResetting: isResetting,
    onStageSelected: onStageSelected ?? (_) {},
    onLockedStageSelected: onLockedStageSelected,
  );
  return MaterialApp(
    // The product app hides this banner; a fixture host must too, or the
    // parity evidence carries a stripe the shipped game never shows.
    debugShowCheckedModeBanner: false,
    theme: orionThemeData,
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: inShell
        ? OrionMenuShell(
            destination: OrionMenuDestination.sectors,
            medalEarned: CampaignTechTree.totalMedalRank(progress),
            medalTotal: resolvedStages.length * 3,
            researchPoints: CampaignTechTree().unspentPoints(progress),
            navigationEnabled: !(isSavingProgress || isResetting),
            settingsEnabled: !isSavingFeedback,
            onDestinationSelected: onDestinationSelected ?? (_) {},
            onOpenSettings: onOpenSettings ?? () {},
            child: map,
          )
        : Scaffold(body: map),
  );
}

void main() {
  testWidgets('compact map hints at the destination until scrolled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildMap(progress: CampaignProgress(), inShell: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('SWIPE UP FOR MISSION'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('world-map-plot-viewport')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('SWIPE UP FOR MISSION'), findsNothing);
    expect(find.text('Deploy'), findsOneWidget);
  });

  testWidgets('destination displays and announces stage modifiers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(
            bestResultsByStageId: const {
              'outpost-alpha': StageResult(
                medal: StageMedal.gold,
                bestBaseHealth: 20,
              ),
              'nebula-relay': StageResult(
                medal: StageMedal.silver,
                bestBaseHealth: 15,
              ),
            },
          ),
        ),
      );
      expect(find.text('Reinforced Armor'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel('Briefing for Asteroid Foundry'),
            )
            .hint,
        contains('Modifiers: Reinforced Armor'),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'enlarged map title and feedback stay clear of utility controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);
      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(),
          feedback: 'Singularity Core is locked.',
          inShell: true,
          textScaler: const TextScaler.linear(3),
        ),
      );
      await tester.pump();
      final titleRect = tester.getRect(find.text('SECTOR MAP'));
      final codexRect = tester.getRect(find.byTooltip('Codex'));
      final feedbackRect = tester.getRect(
        find.text('Singularity Core is locked.'),
      );
      expect(titleRect.overlaps(codexRect), isFalse);
      expect(feedbackRect.overlaps(codexRect), isFalse);
    },
  );

  testWidgets(
    'common portrait screens fit the whole star chart without scrolling',
    (tester) async {
      // Finding: the chart+footer region is the only scrollable; on a
      // common screen it must report zero scroll extent and ignore a
      // whole-map drag — the old nested scrollables stretched/bounced even
      // when nothing overflowed.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);

      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(),
          feedback: 'Singularity Core is locked.',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Exactly one vertical scrollable exists (the chart+footer region),
      // and it has nothing to scroll.
      final scrollableFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      expect(scrollableFinder, findsOneWidget);
      final scrollable = tester.state<ScrollableState>(scrollableFinder);
      expect(scrollable.position.maxScrollExtent, 0);

      // A real drag on the chart is inert at zero extent — no pull, no
      // bounce, no stretch.
      await tester.drag(
        find.byKey(const ValueKey('sector-route-layer')),
        const Offset(0, -160),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);

      // Every stage node — the top row included — is fully on screen in the
      // first view.
      final viewport = tester.getRect(
        find.byKey(const ValueKey('world-map-plot-viewport')),
      );
      for (final stage in OrionCampaign.stages) {
        final rect = tester.getRect(
          find.byKey(ValueKey('sector-stage-${stage.id}')),
        );
        expect(viewport.contains(rect.topLeft), isTrue, reason: stage.id);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: stage.id);
      }
    },
  );

  testWidgets('transient feedback never moves the stage nodes', (tester) async {
    // Regression: the feedback line used to sit in the layout flow, so a
    // message appearing or clearing resized the header and shifted every
    // node by the line's height. Its slot is now a fixed height.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadRealFonts);

    Rect nodeRect(String stageId) =>
        tester.getRect(find.byKey(ValueKey('sector-stage-$stageId')));

    await tester.pumpWidget(buildMap(progress: CampaignProgress()));
    await tester.pump();
    final settled = nodeRect('nebula-relay');

    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(),
        feedback: 'Singularity Core is locked.',
      ),
    );
    await tester.pump();
    expect(nodeRect('nebula-relay'), settled);

    await tester.pumpWidget(buildMap(progress: CampaignProgress()));
    await tester.pump();
    expect(nodeRect('nebula-relay'), settled);
  });

  for (final size in const [Size(320, 568), Size(568, 320)]) {
    testWidgets(
      'compact ${size.width.toInt()}x${size.height.toInt()} map at 3x '
      'system text keeps header, rail, nodes and footer clear of each '
      'other',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // Real Oxanium/Chakra Petch metrics: the Ahem fallback would hide the
        // actual row heights this regression exists to guard.
        await tester.runAsync(loadRealFonts);

        final selected = <String>[];
        Future<void> pumpCompactMap(
          CampaignProgress progress, {
          String? feedback,
        }) async {
          await tester.pumpWidget(
            buildMap(
              progress: progress,
              feedback: feedback,
              inShell: true,
              textScaler: const TextScaler.linear(3),
              onStageSelected: (stage) => selected.add(stage.id),
            ),
          );
          await tester.pump();
        }

        Future<void> expectCompactLayoutClear() async {
          expect(tester.takeException(), isNull);

          final railControls = <Rect>[
            for (final tooltip in shellControlTooltips)
              tester.getRect(find.byTooltip(tooltip)),
          ];

          // Every header element rendered in the current state: the title,
          // its badges, the completion status line, the feedback line and the
          // Challenge Badge.
          final headerRows = <Rect>[
            tester.getRect(find.text('SECTOR MAP')),
            tester.getRect(find.text('MAIN 5/5')),
            if (find.text('OPTIONAL 1/2').evaluate().isNotEmpty)
              tester.getRect(find.text('OPTIONAL 1/2')),
            if (find.text('CAMPAIGN COMPLETE').evaluate().isNotEmpty)
              tester.getRect(find.text('CAMPAIGN COMPLETE')),
            if (find.text('ALL SECTORS SECURED').evaluate().isNotEmpty)
              tester.getRect(find.text('ALL SECTORS SECURED')),
            if (find.text('Saving campaign progress…').evaluate().isNotEmpty)
              tester.getRect(find.text('Saving campaign progress…')),
            if (find
                .byTooltip('Challenge Badge Earned - All side stages cleared')
                .evaluate()
                .isNotEmpty)
              tester.getRect(
                find.byTooltip(
                  'Challenge Badge Earned - All side stages cleared',
                ),
              ),
          ];

          // Header rows may never sit on the utility controls.
          for (final row in headerRows) {
            for (final control in railControls) {
              expect(
                row.overlaps(control),
                isFalse,
                reason: '$row vs $control',
              );
            }
          }

          // Neither the header rows nor the utility controls may cover a
          // visible stage-node hit target. "Visible" means the portion of the
          // node actually on screen inside the scroll viewport — nodes
          // scrolled out of the viewport keep geometric rects that must not
          // count. ScrollableState survives pumpWidget, so a prior call's
          // footer check may have left the region scrolled to the bottom
          // (where only the footer shows); pin it to the top for a
          // deterministic geometry check.
          final scrollable = tester.state<ScrollableState>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          );
          scrollable.position.jumpTo(0);
          await tester.pump();
          final viewportRect = tester.getRect(
            find.byKey(const ValueKey('world-map-plot-viewport')),
          );
          final visibleNodes = <Rect>[];
          for (final stage in OrionCampaign.stages) {
            final rect = tester.getRect(
              find.byKey(ValueKey('sector-stage-${stage.id}')),
            );
            final visiblePortion = rect.intersect(viewportRect);
            if (!visiblePortion.isEmpty) visibleNodes.add(visiblePortion);
          }
          expect(visibleNodes, isNotEmpty);
          for (final node in visibleNodes) {
            for (final overlay in [...headerRows, ...railControls]) {
              expect(
                node.overlaps(overlay),
                isFalse,
                reason: '$node vs $overlay',
              );
            }
          }

          // The footer starts below the fold at these sizes, and there is
          // only ONE scrollable to reach it: a real upward drag on the chart
          // must carry the destination card on screen (the old nested plot
          // scroll swallowed this gesture).
          expect(scrollable.position.maxScrollExtent, greaterThan(0));

          // Drag from the scroll viewport's own center — unlike a node, it
          // stays on screen as the content scrolls, so every leg lands.
          final plotViewport = find.byKey(
            const ValueKey('world-map-plot-viewport'),
          );
          for (
            var leg = 0;
            leg < 4 &&
                scrollable.position.pixels <
                    scrollable.position.maxScrollExtent;
            leg++
          ) {
            await tester.drag(plotViewport, const Offset(0, -600));
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(
            scrollable.position.pixels,
            scrollable.position.maxScrollExtent,
          );

          // At the bottom extent the footer is on screen and leaves Outpost
          // Alpha's hit target clear; the fixed header controls never moved.
          final destination = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label ?? '').startsWith('Briefing for '),
          );
          final footerRect = tester.getRect(
            find.ancestor(of: destination, matching: find.byType(OrionSurface)),
          );
          expect(viewportRect.overlaps(footerRect), isTrue);
          final alphaRect = tester.getRect(
            find.byKey(const ValueKey('sector-stage-outpost-alpha')),
          );
          expect(footerRect.overlaps(alphaRect), isFalse);
          final screenRect = Offset.zero & size;
          for (final tooltip in shellControlTooltips) {
            final controlRect = tester.getRect(find.byTooltip(tooltip));
            expect(
              screenRect.contains(controlRect.topLeft),
              isTrue,
              reason: '$tooltip must stay on screen while scrolled',
            );
            expect(
              screenRect.contains(controlRect.bottomRight),
              isTrue,
              reason: '$tooltip must stay on screen while scrolled',
            );
          }

          // The reached footer is functional, not merely painted.
          final briefingLabel = tester
              .widget<Semantics>(destination)
              .properties
              .label!;
          final expected = OrionCampaign.stages.firstWhere(
            (candidate) => briefingLabel.endsWith(candidate.name),
          );
          await tester.tap(find.text('Deploy'));
          expect(selected.last, expected.id);

          // find.text only matches the widget's data string, not what the
          // paragraph painted; an ellipsized kicker would still pass. Prove
          // the full 'SECTOR NN / QUALIFIER' fits its maxLines at the
          // rendered width and scale, so the qualifier itself paints.
          final kickerFinder = find.textContaining(' / ');
          final kicker = tester.widget<Text>(kickerFinder);
          final kickerParagraph = tester.renderObject<RenderParagraph>(
            kickerFinder,
          );
          final kickerPainter = TextPainter(
            text: kickerParagraph.text,
            textDirection: TextDirection.ltr,
            textScaler: kicker.textScaler ?? TextScaler.noScaling,
            maxLines: kicker.maxLines,
          )..layout(maxWidth: kickerParagraph.size.width);
          expect(
            kickerPainter.didExceedMaxLines,
            isFalse,
            reason: 'destination kicker must paint its qualifier in full',
          );
        }

        final semantics = tester.ensureSemantics();
        try {
          // State 1 — main 5/5 with optional 1/2: the longest badge row without
          // the Challenge Badge, plus a plain feedback line so all three
          // stacked header rows render (busy mode stays off).
          await pumpCompactMap(
            mainCompleteProgress(clearedSideStages: {'salvage-rift'}),
            feedback: 'Saving campaign progress…',
          );

          expect(find.text('MAIN 5/5'), findsOneWidget);
          expect(find.text('OPTIONAL 1/2'), findsOneWidget);
          expect(find.text('CAMPAIGN COMPLETE'), findsOneWidget);
          expect(find.text('Saving campaign progress…'), findsOneWidget);
          expect(
            find.byTooltip('Challenge Badge Earned - All side stages cleared'),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(
              'Campaign complete. Main 5 of 5 stages, optional 1 of 2 stages.',
            ),
            findsOneWidget,
          );
          // The visible completion line is decorative; it must not echo the
          // summary as a second announcement.
          expect(
            find.bySemanticsLabel(RegExp(r'CAMPAIGN COMPLETE')),
            findsNothing,
          );
          await expectCompactLayoutClear();

          // State 2 — all seven stages cleared: ALL SECTORS SECURED with the
          // Challenge Badge; the redundant visible OPTIONAL badge is absent.
          await pumpCompactMap(clearedCampaignProgress());

          expect(find.text('ALL SECTORS SECURED'), findsOneWidget);
          expect(find.textContaining('OPTIONAL'), findsNothing);
          expect(
            find.byTooltip('Challenge Badge Earned - All side stages cleared'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              'Campaign complete. Main 5 of 5 stages, optional 2 of 2 stages.',
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp(r'ALL SECTORS SECURED')),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(
              'Challenge Badge Earned - All side stages cleared',
            ),
            findsOneWidget,
          );
          await expectCompactLayoutClear();
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'compact map exposes seven art-led stage targets without overlap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selected = <String>[];

      await tester.pumpWidget(
        buildMap(
          progress: clearedCampaignProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );

      expect(find.text('SECTOR MAP'), findsOneWidget);
      // Capture every rect in one frame before any ensureVisible scroll
      // shifts the coordinate frame between captures.
      final rects = <Rect>[];
      for (final stage in OrionCampaign.stages) {
        final finder = find.byKey(ValueKey('sector-stage-${stage.id}'));
        expect(finder, findsOneWidget);
        expect(tester.getSize(finder).width, closeTo(72, 0.001));
        expect(tester.getSize(finder).height, closeTo(94, 0.001));
        rects.add(tester.getRect(finder));
      }
      for (var left = 0; left < rects.length; left += 1) {
        for (var right = left + 1; right < rects.length; right += 1) {
          expect(rects[left].overlaps(rects[right]), isFalse);
        }
      }
      for (final stage in OrionCampaign.stages) {
        final finder = find.byKey(ValueKey('sector-stage-${stage.id}'));
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
      }
      expect(selected, OrionCampaign.stages.map((stage) => stage.id).toList());
    },
  );

  testWidgets('optional missions use smaller circular crests', (tester) async {
    await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));

    final mainCrest = tester.getSize(
      find.byKey(const ValueKey('stage-status-ring-outpost-alpha')),
    );
    final optionalStages = OrionCampaign.stages.where(
      (stage) => !stage.isMainPath,
    );
    for (final stage in optionalStages) {
      final finder = find.byKey(ValueKey('stage-status-ring-${stage.id}'));
      expect(finder, findsOneWidget);
      expect(tester.getSize(finder).width, lessThan(mainCrest.width));
    }
  });

  testWidgets('approved world-map backdrop sits behind the map with a '
      'readability scrim', (tester) async {
    await tester.pumpWidget(buildMap(progress: CampaignProgress()));

    final backdrop = find.byKey(const ValueKey('world-map-backdrop'));
    expect(backdrop, findsOneWidget);
    final art = find.descendant(
      of: backdrop,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is OrionAtlasSprite &&
            widget.art.fileName == 'reactor_rim_ui/backdrops/world-map.png',
      ),
    );
    expect(art, findsOneWidget);
    // The backdrop art is square, cover-fit into the portrait aperture —
    // never stretched to the viewport aspect.
    final sprite = tester.widget<OrionAtlasSprite>(art);
    expect(sprite.size!.width, sprite.size!.height);
    expect(
      tester
          .widget<Opacity>(find.byKey(const ValueKey('world-map-backdrop-art')))
          .opacity,
      1,
      reason: 'The galaxy is the map background, not a faint overlay.',
    );
    final fittedBox = tester.widget<FittedBox>(
      find.ancestor(of: art, matching: find.byType(FittedBox)).first,
    );
    expect(fittedBox.fit, BoxFit.cover);

    // The readability scrim paints above the art, inside the backdrop layer.
    final stack = tester.widget<Stack>(
      find.ancestor(of: art, matching: find.byType(Stack)).first,
    );
    final keys = [
      for (final child in stack.children)
        (child is Positioned ? child.child : child).key,
    ];
    final artIndex = keys.indexOf(const ValueKey('world-map-backdrop-art'));
    final scrimIndex = keys.indexOf(const ValueKey('world-map-scrim'));
    expect(artIndex, greaterThanOrEqualTo(0));
    expect(scrimIndex, greaterThan(artIndex));

    // The backdrop layer sits BEHIND the map plot layers in the outer
    // composition stack, mirroring the inner art/scrim ordering above.
    final outerStack = tester.widget<Stack>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('world-map-backdrop')),
            matching: find.byType(Stack),
          )
          .first,
    );
    final outerKeys = [
      for (final child in outerStack.children)
        (child is Positioned ? child.child : child).key,
    ];
    final backdropLayerIndex = outerKeys.indexOf(
      const ValueKey('world-map-backdrop'),
    );
    final plotLayer = tester.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('world-map-plot-viewport')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    final plotLayerIndex = outerStack.children.indexOf(plotLayer);
    expect(backdropLayerIndex, greaterThanOrEqualTo(0));
    expect(plotLayerIndex, greaterThan(backdropLayerIndex));
  });

  testWidgets('stage nodes use square-cropped map art, never stretched wide '
      'art', (tester) async {
    await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));
    for (final stage in OrionCampaign.stages) {
      final node = find.byKey(ValueKey('sector-stage-${stage.id}'));
      final sprite = tester.widget<OrionAtlasSprite>(
        find.descendant(of: node, matching: find.byType(OrionAtlasSprite)),
      );
      expect(
        sprite.art.fileName,
        'reactor_rim_ui/crests/${stage.id}.png',
        reason: stage.id,
      );
      final source = sprite.art.sourceRectFor(
        imageWidth: 160,
        imageHeight: 160,
      );
      expect(source.width, source.height, reason: stage.id);
      expect(sprite.size!.width, sprite.size!.height, reason: stage.id);
    }
  });

  testWidgets('crest, status ring and medal hierarchy exist on stage nodes', (
    tester,
  ) async {
    await tester.pumpWidget(buildMap(progress: CampaignProgress()));
    for (final stage in OrionCampaign.stages) {
      expect(
        find.byKey(ValueKey('stage-crest-${stage.id}')),
        findsOneWidget,
        reason: stage.id,
      );
      expect(
        find.byKey(ValueKey('stage-status-ring-${stage.id}')),
        findsOneWidget,
        reason: stage.id,
      );
    }
    // The medal indicator only appears once a result exists.
    expect(
      find.byKey(const ValueKey('stage-medal-outpost-alpha')),
      findsNothing,
    );

    await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));
    for (final stage in OrionCampaign.stages) {
      expect(
        find.byKey(ValueKey('stage-medal-${stage.id}')),
        findsOneWidget,
        reason: stage.id,
      );
    }
  });

  testWidgets('locked, available and cleared states are explicit without '
      'color alone', (tester) async {
    // Outpost Alpha cleared with a gold medal -> Nebula Relay available; the
    // rest of the campaign stays locked.
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(
          bestResultsByStageId: const {
            'outpost-alpha': StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
          },
        ),
      ),
    );

    // Cleared: medal badge with the per-tier medal icon on the node.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stage-medal-outpost-alpha')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Icons.emoji_events,
        ),
      ),
      findsOneWidget,
    );
    // Available: an explicit open marker, not just the cyan ring color.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stage-open-nebula-relay')),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
    // Locked: a lock icon on the node.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sector-stage-singularity-core')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Icons.lock_rounded,
        ),
      ),
      findsOneWidget,
    );
    // Available nodes must not carry the lock icon.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sector-stage-nebula-relay')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Icons.lock_rounded,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'stage map label color distinguishes locked, unlocked and cleared '
    'states',
    (tester) async {
      // Regression coverage for a bug where the map label's color was
      // flattened to an unconditional uiTheme.textMuted, making every node
      // (locked, available, and cleared) read identically. Assert on the
      // actual resolved TextStyle.color for each state rather than on
      // widget presence, so a future collapse back to one color fails here.
      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(
            bestResultsByStageId: const {
              'outpost-alpha': StageResult(
                medal: StageMedal.gold,
                bestBaseHealth: 20,
              ),
            },
          ),
        ),
      );

      Color labelColor(String stageId, String label) {
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('sector-stage-$stageId')),
            matching: find.text(label),
          ),
        );
        return text.style!.color!;
      }

      // Outpost Alpha: cleared with a gold medal -> medal color.
      final clearedColor = labelColor('outpost-alpha', 'Alpha');
      // Nebula Relay: unlocked by Outpost Alpha's clear -> systemCyan.
      final unlockedColor = labelColor('nebula-relay', 'Relay');
      // Singularity Core: still locked -> textMuted.
      final lockedColor = labelColor('singularity-core', 'Core');

      const uiTheme = OrionUiTheme.dark;
      expect(lockedColor, uiTheme.textMuted);
      expect(unlockedColor, uiTheme.systemCyan);
      expect(clearedColor, medalColor(uiTheme, StageMedal.gold));

      expect(lockedColor, isNot(equals(unlockedColor)));
      expect(unlockedColor, isNot(equals(clearedColor)));
      expect(lockedColor, isNot(equals(clearedColor)));
    },
  );

  testWidgets('every stage node keeps a >=48dp semantic tap target', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      // A portrait surface large enough for the whole star chart, so every
      // measured semantics rect is the node's full 72x94 target rather than
      // the clipped portion of a scrolled-out node.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));
      for (final stage in OrionCampaign.stages) {
        final data = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^${stage.name}')),
        );
        expect(data.rect.width, greaterThanOrEqualTo(48), reason: stage.id);
        expect(data.rect.height, greaterThanOrEqualTo(48), reason: stage.id);
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('route layer still paints SectorMapLayout routes', (
    tester,
  ) async {
    await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));

    final painter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('sector-route-layer')))
        .painter;
    expect(painter, isA<SectorRoutePainter>());
    final routes = (painter as SectorRoutePainter).routes;
    expect(routes, hasLength(6));
    expect(
      routes.where((route) => route.isOptional).map((route) => route.to.id),
      {'salvage-rift', 'void-bastion'},
    );
  });

  testWidgets('stage tap fires exactly once and introduces no persistent '
      'selection bar', (tester) async {
    var selections = 0;
    await tester.pumpWidget(
      buildMap(
        progress: clearedCampaignProgress(),
        onStageSelected: (stage) => selections++,
      ),
    );
    // Outpost Alpha anchors the bottom of the chart; scroll it into the
    // region's viewport before tapping.
    await tester.ensureVisible(
      find.byKey(const ValueKey('sector-stage-outpost-alpha')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sector-stage-outpost-alpha')));
    expect(selections, 1);
    // No persistent selected-stage detail/launch bar may exist on the map:
    // Stage Briefing is the single detail/launch surface.
    expect(find.byKey(const ValueKey('selected-stage-bar')), findsNothing);
    expect(find.byKey(const ValueKey('stage-launch-bar')), findsNothing);
  });

  testWidgets('medal legend is replaced by node-integrated medal indicators', (
    tester,
  ) async {
    await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));
    expect(find.byTooltip('Clear medal'), findsNothing);
    expect(find.byTooltip('Silver medal'), findsNothing);
    expect(find.byTooltip('Gold medal'), findsNothing);
    expect(
      find.byKey(const ValueKey('stage-medal-outpost-alpha')),
      findsOneWidget,
    );
  });

  testWidgets('header and utility controls shed their command-frame chrome', (
    tester,
  ) async {
    await tester.pumpWidget(buildMap(progress: CampaignProgress()));

    expect(find.text('SECTOR MAP'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WorldMapView),
        matching: find.byType(OrionSurface),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<OrionSurface>(find.byType(OrionSurface)).role,
      OrionSurfaceRole.sheet,
    );
  });

  testWidgets('fresh header shows only a MAIN badge with main-only '
      'progress semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildMap(progress: CampaignProgress()));

      expect(find.text('MAIN 0/5'), findsOneWidget);
      expect(find.textContaining('OPTIONAL'), findsNothing);
      expect(find.text('CAMPAIGN COMPLETE'), findsNothing);
      expect(find.text('ALL SECTORS SECURED'), findsNothing);
      expect(
        find.bySemanticsLabel('Main 0 of 5 stages cleared'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('optional badge waits for main completion even with a '
      'cleared side stage', (tester) async {
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(
          bestResultsByStageId: const {
            'outpost-alpha': StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
            'nebula-relay': StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
            'salvage-rift': StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
          },
        ),
      ),
    );

    expect(find.text('MAIN 2/5'), findsOneWidget);
    expect(find.textContaining('OPTIONAL'), findsNothing);
  });

  testWidgets('main-complete header shows both badges and a visual-only '
      'completion line', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildMap(
          progress: mainCompleteProgress(clearedSideStages: {'salvage-rift'}),
        ),
      );

      expect(find.text('MAIN 5/5'), findsOneWidget);
      expect(find.text('OPTIONAL 1/2'), findsOneWidget);
      expect(find.text('CAMPAIGN COMPLETE'), findsOneWidget);
      expect(find.text('ALL SECTORS SECURED'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Campaign complete. Main 5 of 5 stages, optional 1 of 2 stages.',
        ),
        findsOneWidget,
      );
      // The status line is decorative: its text must not echo the summary.
      expect(find.bySemanticsLabel(RegExp(r'CAMPAIGN COMPLETE')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('full clear reads ALL SECTORS SECURED, hides the redundant '
      'optional badge yet still announces its count', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));

      expect(find.text('MAIN 5/5'), findsOneWidget);
      expect(find.textContaining('OPTIONAL'), findsNothing);
      expect(find.text('ALL SECTORS SECURED'), findsOneWidget);
      expect(find.text('CAMPAIGN COMPLETE'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Campaign complete. Main 5 of 5 stages, optional 2 of 2 stages.',
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('header badges clamp text scale to the 1.3x dense-map '
      'precedent', (tester) async {
    await tester.pumpWidget(
      buildMap(
        progress: clearedCampaignProgress(),
        textScaler: const TextScaler.linear(3),
      ),
    );

    final badge = tester.widget<Text>(find.text('MAIN 5/5'));
    expect(badge.textScaler!.scale(1), closeTo(1.3, 0.001));
  });

  testWidgets('empty campaign preserves the existing empty state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildMap(progress: CampaignProgress(), stages: const []),
      );

      expect(find.text('No stages available'), findsOneWidget);
      expect(find.byKey(const ValueKey('sector-route-layer')), findsNothing);
      // Safe zeros: an empty list never claims completion.
      expect(find.text('CAMPAIGN COMPLETE'), findsNothing);
      expect(find.text('ALL SECTORS SECURED'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'Campaign complete')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a campaign without optional stages reads campaign complete '
      'without inventing optional progress', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final mainStages = OrionCampaign.stages
          .where((stage) => stage.isMainPath)
          .toList();
      await tester.pumpWidget(
        buildMap(
          stages: mainStages,
          progress: CampaignProgress(
            bestResultsByStageId: {
              for (final stage in mainStages)
                stage.id: const StageResult(
                  medal: StageMedal.gold,
                  bestBaseHealth: 20,
                ),
            },
          ),
        ),
      );

      expect(find.text('MAIN 5/5'), findsOneWidget);
      expect(find.text('CAMPAIGN COMPLETE'), findsOneWidget);
      // ALL SECTORS SECURED and any optional count are only meaningful when
      // optional stages exist: "optional 0 of 0" is nonsense copy.
      expect(find.text('ALL SECTORS SECURED'), findsNothing);
      expect(
        find.bySemanticsLabel('Campaign complete. Main 5 of 5 stages.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'optional 0 of 0')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('footer recommends the next main stage', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );

      expect(find.text('SECTOR 01 / NEXT MAIN'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Briefing for Outpost Alpha'))
            .hint,
        startsWith('NEXT MAIN.'),
      );

      await tester.ensureVisible(find.text('SECTOR 01 / NEXT MAIN'));
      await tester.pump();
      await tester.tap(find.text('SECTOR 01 / NEXT MAIN'));
      expect(selected, [OrionCampaign.stageOneId]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('main-route destination number matches its map node', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(
          bestResultsByStageId: const {
            'outpost-alpha': StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
            'nebula-relay': StageResult(
              medal: StageMedal.silver,
              bestBaseHealth: 15,
            ),
          },
        ),
      ),
    );
    final foundry = find.byKey(const ValueKey('sector-stage-asteroid-foundry'));
    expect(
      find.descendant(of: foundry, matching: find.text('03 ·')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: foundry, matching: find.text('Foundry')),
      findsOneWidget,
    );
    expect(find.text('SECTOR 03 / NEXT MAIN'), findsOneWidget);
  });

  testWidgets('destination hull matches campaign and stage modifiers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final cases = [
        (
          progress: CampaignProgress(),
          stage: OrionCampaign.stageOne,
          expected: GameBalance.initialBaseHealth + 3,
        ),
        (
          progress: mainCompleteProgress(clearedSideStages: {'salvage-rift'}),
          stage: OrionCampaign.stageById('void-bastion'),
          expected:
              GameBalance.initialBaseHealth +
              3 -
              GameBalance.reducedStartingHealthPenalty,
        ),
      ];
      for (final scenario in cases) {
        await tester.pumpWidget(
          buildMap(
            progress: scenario.progress,
            campaignModifiers: const CampaignModifiers(bonusHealth: 3),
          ),
        );
        final hull = find.byKey(const ValueKey('destination-starting-hull'));
        expect(tester.widget<Text>(hull).data, '${scenario.expected}');
        final destination = find.bySemanticsLabel(
          'Briefing for ${scenario.stage.name}',
        );
        expect(
          tester.getSemantics(destination).hint,
          contains('${scenario.expected} starting hull'),
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('footer steers to the first open optional stage once the main '
      'route is cleared', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: mainCompleteProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );

      expect(find.text('SECTOR 03 / OPTIONAL'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Briefing for Salvage Rift'))
            .hint,
        startsWith('OPTIONAL.'),
      );

      await tester.ensureVisible(find.text('SECTOR 03 / OPTIONAL'));
      await tester.pump();
      await tester.tap(find.text('SECTOR 03 / OPTIONAL'));
      expect(selected, ['salvage-rift']);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('footer replays the final sector at full clear', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: clearedCampaignProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );

      expect(find.text('SECTOR 05 / REPLAY'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel('Briefing for Singularity Core'),
            )
            .hint,
        startsWith('REPLAY.'),
      );

      await tester.ensureVisible(find.text('SECTOR 05 / REPLAY'));
      await tester.pump();
      await tester.tap(find.text('SECTOR 05 / REPLAY'));
      expect(selected, ['singularity-core']);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('busy footer stays inert while an optional stage is '
      'recommended', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      buildMap(
        progress: mainCompleteProgress(),
        isSavingProgress: true,
        onStageSelected: (_) => selected += 1,
      ),
    );

    await tester.ensureVisible(find.text('SECTOR 03 / OPTIONAL'));
    await tester.pump();
    await tester.tap(find.text('SECTOR 03 / OPTIONAL'));
    expect(selected, 0);
  });

  testWidgets(
    'blueprint semantics follow committed progress on every stage node',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        // Fresh campaign: all seven blueprint-bearing nodes report Locked.
        await tester.pumpWidget(buildMap(progress: CampaignProgress()));
        for (final stage in OrionCampaign.stages) {
          expect(
            find.bySemanticsLabel(RegExp('${stage.name}.*Blueprint • Locked')),
            findsOneWidget,
            reason: stage.id,
          );
        }
        expect(
          find.bySemanticsLabel(RegExp(r'Blueprint • Recovered')),
          findsNothing,
        );

        // A committed clear flips only its own stage's node to Recovered;
        // the other six stay Locked.
        final rift = OrionCampaign.stages.firstWhere(
          (stage) => stage.id == 'salvage-rift',
        );
        await tester.pumpWidget(
          buildMap(
            progress: CampaignProgress(
              bestResultsByStageId: {
                rift.id: const StageResult(
                  medal: StageMedal.gold,
                  bestBaseHealth: 20,
                ),
              },
            ),
          ),
        );
        expect(
          find.bySemanticsLabel(RegExp('${rift.name}.*Blueprint • Recovered')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'Blueprint • Locked')),
          findsNWidgets(6),
        );

        // Full clear: every node Recovered.
        await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));
        for (final stage in OrionCampaign.stages) {
          expect(
            find.bySemanticsLabel(
              RegExp('${stage.name}.*Blueprint • Recovered'),
            ),
            findsOneWidget,
            reason: stage.id,
          );
        }
        expect(
          find.bySemanticsLabel(RegExp(r'Blueprint • Locked')),
          findsNothing,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'optional side-stage nodes expose dual reward and blueprint facts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(buildMap(progress: CampaignProgress()));
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Salvage Rift.*'
              'Reward: \\+${GameBalance.salvageRiftGoldBonus} Gold.*'
              r'Blueprint • Locked',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Void Bastion.*'
              'Reward: \\+${GameBalance.voidBastionHealthBonus} HP.*'
              r'Blueprint • Locked',
            ),
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('dual reward glyphs stay clear of the crest at 360x640', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Cleared optional stages stack the worst glyph crowding: medal,
    // campaign reward, and blueprint on one crest.
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(
          bestResultsByStageId: {
            'salvage-rift': const StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
            'void-bastion': const StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
          },
        ),
      ),
    );

    for (final id in ['salvage-rift', 'void-bastion']) {
      expect(find.byKey(ValueKey('sector-stage-$id')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage semantics tap action selects the stage', (tester) async {
    // excludeSemantics: true on the stage node replaces descendant semantics,
    // so the InkWell's tap action is dropped. The outer Semantics must carry
    // its own onTap or VoiceOver/TalkBack cannot activate the stage.
    final handle = tester.ensureSemantics();
    try {
      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: clearedCampaignProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );
      final data = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'Outpost Alpha')),
      );
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        data.id,
        SemanticsAction.tap,
      );
      expect(selected, [OrionCampaign.stageOneId]);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('locked stage semantics tap action invokes locked callback', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final locked = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(),
          onLockedStageSelected: (stage) => locked.add(stage.id),
        ),
      );
      final data = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'Singularity Core')),
      );
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        data.id,
        SemanticsAction.tap,
      );
      expect(locked, ['singularity-core']);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('locked nodes call only the locked-stage callback', (
    tester,
  ) async {
    final selected = <String>[];
    final locked = <String>[];
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(),
        onStageSelected: (stage) => selected.add(stage.id),
        onLockedStageSelected: (stage) => locked.add(stage.id),
      ),
    );

    // Outpost Alpha anchors the bottom of the chart; scroll it into view.
    await tester.ensureVisible(
      find.byKey(const ValueKey('sector-stage-outpost-alpha')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sector-stage-outpost-alpha')));
    // The fixed header keeps locked nodes out from under it, so scroll the
    // locked node into the viewport before tapping it.
    await tester.ensureVisible(
      find.byKey(const ValueKey('sector-stage-singularity-core')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sector-stage-singularity-core')),
    );

    expect(selected, [OrionCampaign.stageOneId]);
    expect(locked, ['singularity-core']);
  });

  testWidgets('Clear Silver and Gold expose distinct medal semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final progress = CampaignProgress(
        bestResultsByStageId: const {
          'outpost-alpha': StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 4,
          ),
          'nebula-relay': StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 12,
          ),
          'asteroid-foundry': StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
        },
      );

      await tester.pumpWidget(buildMap(progress: progress));

      expect(
        find.bySemanticsLabel(RegExp(r'Outpost Alpha.*Medal • Clear')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Nebula Relay.*Medal • Silver')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Asteroid Foundry.*Medal • Gold')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('feedback remains visible until the harness replaces it', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMap(progress: CampaignProgress(), feedback: 'Relay synchronized.'),
    );
    await tester.pump();
    expect(find.text('Relay synchronized.'), findsOneWidget);

    await tester.pump();
    expect(find.text('Relay synchronized.'), findsOneWidget);

    await tester.pumpWidget(
      buildMap(progress: CampaignProgress(), feedback: 'Route recalculated.'),
    );
    expect(find.text('Relay synchronized.'), findsNothing);
    expect(find.text('Route recalculated.'), findsOneWidget);

    await tester.pumpWidget(buildMap(progress: CampaignProgress()));
    expect(find.text('Route recalculated.'), findsNothing);
  });

  testWidgets('shell chrome invokes navigation and settings callbacks', (
    tester,
  ) async {
    final destinations = <OrionMenuDestination>[];
    var settings = 0;
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(),
        inShell: true,
        onDestinationSelected: destinations.add,
        onOpenSettings: () => settings += 1,
      ),
    );

    await tester.tap(find.byTooltip('Codex'));
    await tester.tap(find.byTooltip('R&D'));
    await tester.tap(find.byTooltip('Settings'));

    expect(destinations, [
      OrionMenuDestination.codex,
      OrionMenuDestination.research,
    ]);
    expect(settings, 1);
    expect(find.byTooltip('Reset Campaign'), findsNothing);
  });

  testWidgets('save and reset busy states disable stage and tab actions', (
    tester,
  ) async {
    for (final busyState in [
      (isSavingProgress: true, isResetting: false),
      (isSavingProgress: false, isResetting: true),
    ]) {
      var actions = 0;
      await tester.pumpWidget(
        buildMap(
          progress: clearedCampaignProgress(),
          inShell: true,
          isSavingProgress: busyState.isSavingProgress,
          isResetting: busyState.isResetting,
          onStageSelected: (_) => actions += 1,
          onLockedStageSelected: (_) => actions += 1,
          onDestinationSelected: (_) => actions += 1,
        ),
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('sector-stage-outpost-alpha')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('sector-stage-outpost-alpha')),
      );
      await tester.tap(find.byTooltip('Codex'));
      await tester.tap(find.byTooltip('R&D'));
      await tester.tap(find.byTooltip('Map'));
      expect(actions, 0);
    }
  });

  testWidgets('feedback save disables Settings only', (tester) async {
    var stage = 0;
    var destinations = 0;
    var settings = 0;
    await tester.pumpWidget(
      buildMap(
        progress: clearedCampaignProgress(),
        inShell: true,
        isSavingFeedback: true,
        onStageSelected: (_) => stage += 1,
        onDestinationSelected: (_) => destinations += 1,
        onOpenSettings: () => settings += 1,
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('sector-stage-outpost-alpha')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sector-stage-outpost-alpha')));
    await tester.tap(find.byTooltip('Codex'));
    await tester.tap(find.byTooltip('R&D'));
    await tester.tap(find.byTooltip('Settings'));

    expect((stage, destinations, settings), (1, 2, 0));
  });

  testWidgets('busy-derived feedback and challenge semantics remain exact', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMap(progress: CampaignProgress(), isSavingProgress: true),
    );
    expect(find.text('Saving campaign progress…'), findsOneWidget);

    await tester.pumpWidget(
      buildMap(progress: CampaignProgress(), isResetting: true),
    );
    expect(find.text('Resetting campaign…'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(),
          campaignModifiers: const CampaignModifiers(hasChallengeBadge: true),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Challenge Badge Earned - All side stages cleared',
        ),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'map node captions clamp text scale so dense layout never overflows',
    (tester) async {
      // The map node captions cap textScaler at 1.15x (see world_map_view.dart).
      // This is a deliberate trade-off for the dense 56x80 node grid: the
      // captions are short labels, and unbounded scaling would overflow the
      // fixed node aperture. This test verifies the clamp prevents overflow at
      // an extreme system scale — it is NOT a claim that the map supports
      // large-text accessibility. Real large-text support for this view is
      // tracked separately.
      await tester.pumpWidget(
        MaterialApp(
          // The product app hides this banner; a fixture host must too, or the
          // parity evidence carries a stripe the shipped game never shows.
          debugShowCheckedModeBanner: false,
          theme: orionThemeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3.0)),
            child: child!,
          ),
          home: Scaffold(
            body: WorldMapView(
              stages: OrionCampaign.stages,
              progress: clearedCampaignProgress(),
              feedback: null,
              onStageSelected: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final stage in OrionCampaign.stages) {
        expect(find.text(stage.mapLabel), findsOneWidget);
      }
    },
  );

  testWidgets(
    'at 320 logical pixels neighboring stage targets do not overlap and '
    'stage selection still works',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: clearedCampaignProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );

      expect(find.text('SECTOR MAP'), findsOneWidget);

      // Every stage node is rendered and sized 56x80.
      final rects = <Rect>[];
      for (final stage in OrionCampaign.stages) {
        final finder = find.byKey(ValueKey('sector-stage-${stage.id}'));
        expect(finder, findsOneWidget);
        expect(tester.getSize(finder).width, closeTo(72, 0.001));
        expect(tester.getSize(finder).height, closeTo(94, 0.001));
        rects.add(tester.getRect(finder));
      }

      // No two nodes overlap at 320px: the column step floors at nodeSize.width
      // so adjacent targets stay tappable.
      for (var i = 0; i < rects.length; i += 1) {
        for (var j = i + 1; j < rects.length; j += 1) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }

      // Tapping each stage still selects it.
      for (final stage in OrionCampaign.stages) {
        final node = find.byKey(ValueKey('sector-stage-${stage.id}'));
        await tester.ensureVisible(node);
        await tester.pump();
        await tester.tap(node);
      }
      expect(selected, OrionCampaign.stages.map((stage) => stage.id).toList());
    },
  );

  testWidgets(
    'at 320x568 with 3x system text the plot scrolls and every stage stays '
    'selectable',
    (tester) async {
      // The chart+footer region is one scrollable under the fixed header;
      // compact viewports scroll it vertically. This guards that scrolling
      // still exposes every stage node as a working tap target at the
      // cramped extreme.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadRealFonts);

      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          // The tallest header (badges + completion + feedback rows) leaves
          // the smallest region, so scrolling is unavoidable.
          progress: mainCompleteProgress(clearedSideStages: {'salvage-rift'}),
          feedback: 'Saving campaign progress…',
          onStageSelected: (stage) => selected.add(stage.id),
          textScaler: const TextScaler.linear(3),
        ),
      );
      await tester.pump();

      // The region below the fixed header is too short for the chart plus
      // footer, so its single vertical scrollable must have real extent.
      final verticalScroll = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(verticalScroll.position.maxScrollExtent, greaterThan(0));

      var scrolled = false;
      for (final stage in OrionCampaign.stages) {
        final node = find.byKey(ValueKey('sector-stage-${stage.id}'));
        final before = verticalScroll.position.pixels;
        await tester.ensureVisible(node);
        await tester.pump();
        scrolled = scrolled || verticalScroll.position.pixels != before;
        await tester.tap(node);
        expect(tester.takeException(), isNull, reason: stage.id);
      }
      // Selection genuinely happened while scrolled, not at offset zero.
      expect(scrolled, isTrue);
      expect(selected, OrionCampaign.stages.map((stage) => stage.id).toList());
    },
  );

  testWidgets('at 320x568 with 3x text a real drag scrolls the region and '
      'taps a revealed stage', (tester) async {
    // ensureVisible alone does not prove the compact region answers a real
    // touch drag. The scroll is top-anchored: an upward drag carries the
    // bottom-most stage (and the footer) into view, where its tap target
    // then works.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadRealFonts);

    final selected = <String>[];
    await tester.pumpWidget(
      buildMap(
        progress: mainCompleteProgress(clearedSideStages: {'salvage-rift'}),
        feedback: 'Saving campaign progress…',
        onStageSelected: (stage) => selected.add(stage.id),
        textScaler: const TextScaler.linear(3),
      ),
    );
    await tester.pump();

    final verticalScroll = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    // The scrollable rests at the top of the chart.
    expect(verticalScroll.position.pixels, 0);

    // Drag with a real held gesture, starting on the top stage so the
    // gesture point is guaranteed on screen; two legs carry the offset to
    // the bottom extent in every geometry this test may run against.
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('sector-stage-singularity-core')),
      ),
    );
    await gesture.moveBy(const Offset(0, -600));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -600));
    await gesture.up();
    await tester.pumpAndSettle();

    // The real gesture moved the region all the way to the bottom extent.
    expect(verticalScroll.position.maxScrollExtent, greaterThan(0));
    expect(
      verticalScroll.position.pixels,
      verticalScroll.position.maxScrollExtent,
    );

    // Outpost Alpha sits at the bottom of the chart, clipped out of the
    // first view; after the drag its tap center is revealed and taps work.
    final alpha = find.byKey(const ValueKey('sector-stage-outpost-alpha'));
    final viewport = tester.getRect(
      find.byKey(const ValueKey('world-map-plot-viewport')),
    );
    expect(viewport.contains(tester.getRect(alpha).center), isTrue);
    await tester.tap(alpha);
    expect(selected, ['outpost-alpha']);
  });

  testWidgets(
    'below the minimum non-overlapping width the plot scrolls horizontally '
    'and stage selection still works',
    (tester) async {
      // 280px is narrower than the plot's minimum content width (304px), so the
      // view wraps the plot in a horizontal scroll. The first stage remains
      // visible at scroll offset zero and is tappable.
      await tester.binding.setSurfaceSize(const Size(280, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final selected = <String>[];
      await tester.pumpWidget(
        buildMap(
          progress: clearedCampaignProgress(),
          onStageSelected: (stage) => selected.add(stage.id),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNWidgets(2));

      // The plot actually scrolls horizontally: dragging the route layer
      // moves the scroll offset away from zero.
      final scrollFinder = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      final scrollable = tester.state<ScrollableState>(scrollFinder);
      expect(scrollable.position.pixels, 0);

      await tester.drag(
        find.byKey(const ValueKey('sector-route-layer')),
        const Offset(-80, 0),
        // The route layer sits behind the stage nodes in the plot Stack, so
        // its center is occluded by a node; the drag still reaches the
        // Scrollable's gesture handler through the hit-test chain.
        warnIfMissed: false,
      );
      await tester.pump();
      expect(scrollable.position.pixels, greaterThan(0));

      // The first stage remains tappable after scrolling and still selects.
      await tester.ensureVisible(
        find.byKey(const ValueKey('sector-stage-outpost-alpha')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('sector-stage-outpost-alpha')),
      );
      expect(selected, [OrionCampaign.stageOneId]);
    },
  );

  testWidgets('capture scene 1f fixture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Representative scene 1f state: Outpost Alpha cleared with a gold medal
    // (medal ring + badge), Nebula Relay available (open marker + cyan ring),
    // the rest locked (lock icons), over the approved world-map backdrop.
    // Real Roboto + Material icons so the evidence shows true text metrics.
    await loadRealFonts();
    // The memo can hold a pending future from an earlier cold-cache test
    // in this process; clear it so this fixture's warmed cache is used.
    OrionArtDescriptor.resetSpriteCache();
    // Image decode is real async engine work that cannot complete under the
    // test FakeAsync zone; pre-warm the Flame cache (keyed by file name, the
    // same keys the OrionArt descriptors use) so the art renders.
    await tester.runAsync(() async {
      await Flame.images.load('reactor_rim_ui/backdrops/world-map.png');
      for (final stage in OrionCampaign.stages) {
        await Flame.images.load('reactor_rim_ui/stages/${stage.id}.png');
        await Flame.images.load('reactor_rim_ui/crests/${stage.id}.png');
      }
    });

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: buildMap(
          progress: CampaignProgress(
            bestResultsByStageId: const {
              'outpost-alpha': StageResult(
                medal: StageMedal.gold,
                bestBaseHealth: 20,
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(
          'assets/images/reactor_rim_ui/backdrops/world-map.png',
        ),
        tester.element(find.byType(WorldMapView)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('world-map-backdrop')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stage-medal-outpost-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stage-open-nebula-relay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stage-status-ring-singularity-core')),
      findsOneWidget,
    );
    // Side-stage nodes render in the capture state so the fixture shows the
    // full route graph, optional legs included.
    expect(
      find.byKey(const ValueKey('sector-stage-salvage-rift')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sector-stage-void-bastion')),
      findsOneWidget,
    );

    // No-op unless ORION_CAPTURE_DIR is set. runAsync: PNG encoding is
    // real async engine work and deadlocks the FakeAsync zone otherwise.
    await tester.runAsync(
      () => captureReactorRimFixture(boundaryKey, 'fixture-1f.png'),
    );
  });

  for (final size in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets('shell map capture loads its artwork at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await loadRealFonts();
      await tester.runAsync(() async {
        await Flame.images.load('reactor_rim_ui/backdrops/world-map.png');
        for (final stage in OrionCampaign.stages) {
          await Flame.images.load('reactor_rim_ui/stages/${stage.id}.png');
          await Flame.images.load('reactor_rim_ui/crests/${stage.id}.png');
        }
      });
      OrionArtDescriptor.resetSpriteCache();
      final progress = CampaignProgress(
        bestResultsByStageId: const {
          'outpost-alpha': StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
          'nebula-relay': StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 15,
          ),
        },
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: buildMap(progress: progress, inShell: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('world-map-backdrop')),
          matching: find.byType(SpriteWidget),
        ),
        findsOneWidget,
      );
      for (final stage in OrionCampaign.stages) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('sector-stage-${stage.id}')),
            matching: find.byType(SpriteWidget),
          ),
          findsOneWidget,
          reason: '${stage.name} must paint its crest in the capture.',
        );
      }
      final destination = progress.recommendedStage(OrionCampaign.stages)!;
      final preview = find.byWidgetPredicate(
        (widget) =>
            widget is OrionAtlasSprite &&
            widget.art.fileName ==
                'reactor_rim_ui/stages/${destination.id}.png',
      );
      expect(
        find.descendant(of: preview, matching: find.byType(SpriteWidget)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.runAsync(
        () => captureReactorRimFixture(
          boundaryKey,
          'world-map-shell-${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    });
  }
}
