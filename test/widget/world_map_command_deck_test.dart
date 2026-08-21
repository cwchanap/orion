import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/ui/world_map_view.dart';

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

  testWidgets('optional missions use diamond aperture frames', (tester) async {
    await tester.pumpWidget(buildMap(progress: clearedCampaignProgress()));

    final optionalStages = OrionCampaign.stages.where(
      (stage) => !stage.isMainPath,
    );
    for (final stage in optionalStages) {
      final finder = find.byKey(
        ValueKey('optional-stage-aperture-${stage.id}'),
      );
      expect(finder, findsOneWidget);
      final rotation = tester.widget<Transform>(finder);
      expect(rotation.transform.entry(0, 0), closeTo(math.sqrt1_2, 0.001));
    }
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
    semantics.dispose();
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
    semantics.dispose();
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
    await tester.pumpWidget(
      buildMap(
        progress: CampaignProgress(),
        campaignModifiers: const CampaignModifiers(hasChallengeBadge: true),
      ),
    );
    expect(
      find.bySemanticsLabel('Challenge Badge Earned - All side stages cleared'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
