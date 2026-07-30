import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/codex_view.dart';
import 'package:orion/game/ui/world_map_view.dart';

void main() {
  testWidgets('renders the four section chips and Towers content by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );

    for (final chip in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
      expect(find.text(chip), findsWidgets);
    }
    // Default section is Towers: the first tower label appears.
    expect(find.text(TowerType.laser.label), findsOneWidget);
  });

  testWidgets('tapping Enemies shows the enemy section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    // Assert the basic drone's role description — authored prose rendered only
    // on the enemy card. The enemy label ('Drones') collides with the Drone
    // Bay stat-row key in the Towers section, so it can't distinguish sections.
    final basicDrone = CodexData.enemies.firstWhere(
      (e) => e.archetype == EnemyArchetype.basicDrone,
    );
    expect(find.text(basicDrone.roleDescription), findsOneWidget);
  });

  testWidgets('tapping Effects shows the effects section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    // 'Armor Shred' (capital S) is unique to the effects glossary; the
    // specialty-line stat key is 'Armor shred' (lowercase).
    expect(find.text('Armor Shred'), findsOneWidget);
  });

  testWidgets('tapping Stages shows the stages section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Stages'));
    await tester.pumpAndSettle();
    // The first stage card title is '<name> (<mapLabel>)'.
    expect(find.textContaining('Outpost Alpha'), findsOneWidget);
  });

  testWidgets('back button invokes onBack', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(
          progress: CampaignProgress(),
          onBack: () => pressed = true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(pressed, isTrue);
  });

  testWidgets('world map shows a Codex button that fires onOpenCodex', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
            onOpenTechTree: () {},
            onOpenCodex: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Codex'), findsOneWidget);
    await tester.tap(find.byTooltip('Codex'));
    expect(pressed, isTrue);
  });

  testWidgets('renders every section without overflow on a narrow surface', (
    tester,
  ) async {
    // 360 x 640 logical surface (spec §10.3).
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );

    for (final chip in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
      await tester.tap(find.text(chip));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });
}
