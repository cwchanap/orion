import 'dart:ui' show SemanticsAction;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/ui/orion_theme_data.dart';
import 'package:orion/game/ui/campaign_presentation.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';
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

Widget buildMap({
  required CampaignProgress progress,
  List<StageDefinition>? stages,
  CampaignModifiers? campaignModifiers,
  ValueChanged<StageDefinition>? onStageSelected,
  ValueChanged<StageDefinition>? onLockedStageSelected,
  VoidCallback? onResetCampaign,
  VoidCallback? onOpenTechTree,
  VoidCallback? onOpenCodex,
  VoidCallback? onOpenSettings,
  String? feedback,
  bool isSavingProgress = false,
  bool isResetting = false,
  bool isSavingFeedback = false,
}) {
  return MaterialApp(
    // The product app hides this banner; a fixture host must too, or the
    // parity evidence carries a stripe the shipped game never shows.
    debugShowCheckedModeBanner: false,
    theme: orionThemeData,
    home: Scaffold(
      body: WorldMapView(
        stages: stages ?? OrionCampaign.stages,
        progress: progress,
        campaignModifiers: campaignModifiers,
        feedback: feedback,
        isSavingProgress: isSavingProgress,
        isResetting: isResetting,
        isSavingFeedback: isSavingFeedback,
        onStageSelected: onStageSelected ?? (_) {},
        onLockedStageSelected: onLockedStageSelected,
        onResetCampaign: onResetCampaign ?? () {},
        onOpenTechTree: onOpenTechTree ?? () {},
        onOpenCodex: onOpenCodex ?? () {},
        onOpenSettings: onOpenSettings ?? () {},
      ),
    ),
  );
}

void main() {
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

      expect(find.text('ORION SECTOR'), findsOneWidget);
      final rects = <Rect>[];
      for (final stage in OrionCampaign.stages) {
        final finder = find.byKey(ValueKey('sector-stage-${stage.id}'));
        expect(finder, findsOneWidget);
        expect(tester.getSize(finder), const Size(56, 80));
        rects.add(tester.getRect(finder));
        await tester.tap(finder);
      }
      for (var left = 0; left < rects.length; left += 1) {
        for (var right = left + 1; right < rects.length; right += 1) {
          expect(rects[left].overlaps(rects[right]), isFalse);
        }
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
    final plotLayerIndex = outerKeys.indexOf(const ValueKey('world-map-plot'));
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
        'reactor_rim_ui/stages/${stage.id}.png',
        reason: stage.id,
      );
      final source = sprite.art.sourceRectFor(
        imageWidth: 1600,
        imageHeight: 900,
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

    expect(find.text('ORION SECTOR'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WorldMapView),
        matching: find.byType(OrionSurface),
      ),
      findsNothing,
    );
  });

  testWidgets('empty campaign preserves the existing empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildMap(progress: CampaignProgress(), stages: const []),
    );

    expect(find.text('No stages available'), findsOneWidget);
    expect(find.byKey(const ValueKey('sector-route-layer')), findsNothing);
  });

  testWidgets('Alpha blueprint semantics follow committed progress', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildMap(progress: CampaignProgress()));
      expect(
        find.bySemanticsLabel(RegExp(r'Outpost Alpha.*Blueprint • Locked')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        buildMap(
          progress: CampaignProgress(
            bestResultsByStageId: {
              OrionCampaign.stageOneId: const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 6,
              ),
            },
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Outpost Alpha.*Blueprint • Recovered')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
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

    await tester.tap(find.byKey(const ValueKey('sector-stage-outpost-alpha')));
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

  testWidgets('utility rail invokes every existing callback', (tester) async {
    var codex = 0;
    var techTree = 0;
    var settings = 0;
    var reset = 0;
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(),
        onOpenCodex: () => codex += 1,
        onOpenTechTree: () => techTree += 1,
        onOpenSettings: () => settings += 1,
        onResetCampaign: () => reset += 1,
      ),
    );

    await tester.tap(find.byTooltip('Codex'));
    await tester.tap(find.byTooltip('Tech Tree'));
    await tester.tap(find.byTooltip('Settings'));
    await tester.tap(find.byTooltip('Reset Campaign'));

    expect((codex, techTree, settings, reset), (1, 1, 1, 1));
  });

  testWidgets('save and reset busy states disable stage and utility actions', (
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
          isSavingProgress: busyState.isSavingProgress,
          isResetting: busyState.isResetting,
          onStageSelected: (_) => actions += 1,
          onLockedStageSelected: (_) => actions += 1,
          onOpenCodex: () => actions += 1,
          onOpenTechTree: () => actions += 1,
          onOpenSettings: () => actions += 1,
          onResetCampaign: () => actions += 1,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('sector-stage-outpost-alpha')),
      );
      await tester.tap(find.byTooltip('Codex'));
      await tester.tap(find.byTooltip('Tech Tree'));
      await tester.tap(find.byTooltip('Settings'));
      await tester.tap(find.byTooltip('Reset Campaign'));
      expect(actions, 0);
    }
  });

  testWidgets('feedback save disables Settings only', (tester) async {
    var stage = 0;
    var codex = 0;
    var techTree = 0;
    var settings = 0;
    var reset = 0;
    await tester.pumpWidget(
      buildMap(
        progress: clearedCampaignProgress(),
        isSavingFeedback: true,
        onStageSelected: (_) => stage += 1,
        onOpenCodex: () => codex += 1,
        onOpenTechTree: () => techTree += 1,
        onOpenSettings: () => settings += 1,
        onResetCampaign: () => reset += 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('sector-stage-outpost-alpha')));
    await tester.tap(find.byTooltip('Codex'));
    await tester.tap(find.byTooltip('Tech Tree'));
    await tester.tap(find.byTooltip('Settings'));
    await tester.tap(find.byTooltip('Reset Campaign'));

    expect((stage, codex, techTree, settings, reset), (1, 1, 1, 0, 1));
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
              onResetCampaign: () {},
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

      expect(find.text('ORION SECTOR'), findsOneWidget);

      // Every stage node is rendered and sized 56x80.
      final rects = <Rect>[];
      for (final stage in OrionCampaign.stages) {
        final finder = find.byKey(ValueKey('sector-stage-${stage.id}'));
        expect(finder, findsOneWidget);
        expect(tester.getSize(finder), const Size(56, 80));
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
        await tester.tap(find.byKey(ValueKey('sector-stage-${stage.id}')));
      }
      expect(selected, OrionCampaign.stages.map((stage) => stage.id).toList());
    },
  );

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

      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // The plot actually scrolls horizontally: dragging the route layer
      // moves the scroll offset away from zero.
      final scrollFinder = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
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
}
