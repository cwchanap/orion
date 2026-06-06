import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/game/ui/world_map_view.dart';
import 'package:orion/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('boots into the Orion world map first', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('starts an unlocked stage from the world map', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Gold 150'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/8'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });

  testWidgets('locked stage tap shows feedback and stays on map', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();

    expect(find.text('Singularity Core is locked.'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('reset confirmation clears campaign progress', (tester) async {
    SharedPreferences.setMockInitialValues({
      'orion.campaign.progress': CampaignProgressCodec.encode(
        CampaignProgress(
          clearedStageIds: {
            'outpost-alpha',
            'nebula-relay',
            'asteroid-foundry',
            'aurora-gate',
          },
        ),
      ),
    });

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);

    await tester.tap(find.byTooltip('Reset Campaign'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Campaign'), findsOneWidget);
    expect(find.text('Clear all campaign progress?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Campaign reset.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);
    expect(find.text('Start Wave'), findsNothing);
  });

  test('snapshot exposes the current tower unlocks', () {
    final session = GameSession.initial();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
    ]);

    expect(session.startWave(), isTrue);
    session.finishActiveWave();

    expect(session.snapshot().unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
      TowerType.railgun,
    ]);
  });

  test('snapshot exposes stage identity and wave total', () {
    final snapshot = GameSession.initial().snapshot();

    expect(snapshot.stageId, 'outpost-alpha');
    expect(snapshot.stageName, 'Outpost Alpha');
    expect(snapshot.stageLabel, 'Alpha');
    expect(snapshot.waveTotal, 8);
  });

  test('snapshot tower unlocks cannot be mutated after capture', () {
    final snapshot = GameSession.initial().snapshot();

    expect(
      () => snapshot.unlockedTowerTypes[0] = TowerType.droneBay,
      throwsUnsupportedError,
    );
    expect(snapshot.unlockedTowerTypes, [
      TowerType.laser,
      TowerType.rocket,
      TowerType.cryo,
    ]);
  });

  testWidgets('world map shows locked, unlocked, and cleared stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(clearedStageIds: {'outpost-alpha'}),
            feedback: null,
            onStageSelected: (_) {},
            onLockedStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Cleared'), findsWidgets);
    expect(find.text('Open'), findsWidgets);
    expect(find.text('Locked'), findsWidgets);
  });

  testWidgets('locked stage tap uses locked callback only when locked', (
    tester,
  ) async {
    final selected = <String>[];
    final locked = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: CampaignProgress(),
            feedback: null,
            onStageSelected: (stage) => selected.add(stage.id),
            onLockedStageSelected: (stage) => locked.add(stage.id),
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Core'));
    expect(selected, isEmpty);
    expect(locked, ['singularity-core']);

    await tester.tap(find.text('Alpha'));
    expect(selected, ['outpost-alpha']);
    expect(locked, ['singularity-core']);
  });
}
