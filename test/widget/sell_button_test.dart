import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Sell button shows the refund for a level-1 laser', (
    tester,
  ) async {
    final game = await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    expect(game!.snapshot.phase, GamePhase.build);
    expect(find.text('Sell +35'), findsOneWidget);
  });

  testWidgets('Sell button is enabled during build phase', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    final sellButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Sell +35'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(sellButton.onPressed, isNotNull);
  });

  testWidgets('Sell button is disabled during an active wave', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
      phase: GamePhase.wave,
    );

    final sellButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Sell +35'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(sellButton.onPressed, isNull);
  });

  testWidgets('tapping Sell invokes game.sellSelectedTower', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    await tester.tap(find.text('Sell +35'));
    await tester.pump();

    // The faked snapshot has a selectedTower but the real session has none, so
    // sellSelectedTower reports the no-selection feedback — proving the tap ran.
    expect(find.text('Select a tower first.'), findsOneWidget);
  });

  testWidgets('Sell button renders without overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    expect(find.text('Sell +35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sell button renders without overflow on a narrow screen with specialization chips',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpStageWithSelectedTower(
        tester,
        const PlacedTower(
          id: 1,
          type: TowerType.laser,
          position: GridPosition(0, 0),
          level: 2,
        ),
      );

      expect(find.text('Sell +84'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Pumps [OrionGamePage], enters the first stage, and drives the panel with a
/// faked snapshot carrying [selectedTower]. Returns the captured game.
Future<OrionDefenseGame?> _pumpStageWithSelectedTower(
  WidgetTester tester,
  PlacedTower selectedTower, {
  GamePhase phase = GamePhase.build,
}) async {
  OrionDefenseGame? game;

  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: OrionGamePage(onGameCreated: (created) => game = created),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();

  final snapshot = game!.stateNotifier.value;
  game!.stateNotifier.value = GameSnapshot(
    phase: phase,
    gold: snapshot.gold,
    baseHealth: snapshot.baseHealth,
    waveNumber: snapshot.waveNumber,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    nextWavePreview: snapshot.nextWavePreview,
    selectedCell: snapshot.selectedCell,
    selectedTower: selectedTower,
    feedback: snapshot.feedback,
    isPaused: snapshot.isPaused,
    speedMultiplier: snapshot.speedMultiplier,
    autoStartEnabled: snapshot.autoStartEnabled,
    autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
  );
  await tester.pump();

  return game;
}
