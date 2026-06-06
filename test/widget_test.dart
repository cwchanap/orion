import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/game/ui/world_map_view.dart';
import 'package:orion/main.dart';

void main() {
  testWidgets('boots into the Orion tower defense shell', (tester) async {
    await tester.pumpWidget(const OrionApp());
    await tester.pump();

    expect(find.text('Orion'), findsOneWidget);
    expect(find.text('Gold 150'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/8'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
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
    expect(find.text('Locked'), findsWidgets);
  });

  testWidgets(
    'locked stage tap shows feedback through callback only when unlocked',
    (tester) async {
      final selected = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldMapView(
              stages: OrionCampaign.stages,
              progress: CampaignProgress(),
              feedback: null,
              onStageSelected: (stage) => selected.add(stage.id),
              onResetCampaign: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Core'));
      expect(selected, isEmpty);

      await tester.tap(find.text('Alpha'));
      expect(selected, ['outpost-alpha']);
    },
  );
}
