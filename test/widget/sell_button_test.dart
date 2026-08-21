import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_game_page.dart';
import 'package:orion/game/util/format.dart';
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

  testWidgets('selected drone bay shows resolved drone damage', (tester) async {
    final stats = GameBalance.towerStats(TowerType.droneBay, level: 1);
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.droneBay,
        position: GridPosition(0, 0),
      ),
      selectedTowerStats: stats,
    );

    expect(find.text('Drone dmg ${number(stats.droneDamage)}'), findsOneWidget);
  });

  testWidgets('selected laser shows resolved damage, fire, and range', (
    tester,
  ) async {
    final stats = GameBalance.towerStats(TowerType.laser, level: 1);
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
      selectedTowerStats: stats,
    );

    expect(
      find.text(
        'Damage ${number(stats.damage)} • '
        'Fire ${cadence(stats.fireInterval)}s • '
        'Range ${number(stats.range)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('selected cryo shows slow duration secondary stat', (
    tester,
  ) async {
    final stats = GameBalance.towerStats(TowerType.cryo, level: 1);
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.cryo,
        position: GridPosition(0, 0),
      ),
      selectedTowerStats: stats,
    );

    expect(find.text('Slow ${number(stats.slowDuration)}s'), findsOneWidget);
  });

  testWidgets('selected rocket shows splash radius secondary stat', (
    tester,
  ) async {
    final stats = GameBalance.towerStats(TowerType.rocket, level: 1);
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.rocket,
        position: GridPosition(0, 0),
      ),
      selectedTowerStats: stats,
    );

    expect(find.text('Splash ${number(stats.splashRadius)}'), findsOneWidget);
  });

  testWidgets('selected nanite shows corrosion secondary stat', (tester) async {
    final stats = GameBalance.towerStats(TowerType.nanite, level: 1);
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.nanite,
        position: GridPosition(0, 0),
      ),
      selectedTowerStats: stats,
    );

    expect(
      find.text('Corrosion ${number(stats.corrosionDamagePerSecond)}/s'),
      findsOneWidget,
    );
  });

  testWidgets('acquired run modules strip renders in the HUD', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
      acquiredRunModules: const [RunModuleId.heavyCaliber],
    );

    final definition = runModuleDefinition(RunModuleId.heavyCaliber);
    expect(find.textContaining(definition.title), findsWidgets);
  });

  testWidgets('pending module offer shows the draft panel overlay', (
    tester,
  ) async {
    final offer = RunModuleOffer(
      offerId: 1,
      draftNumber: 1,
      draftTotal: GameBalance.moduleDraftWaves.length,
      moduleIds: const [
        RunModuleId.heavyCaliber,
        RunModuleId.overclockRelay,
        RunModuleId.longSight,
      ],
    );
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
      pendingRunModuleOffer: offer,
    );

    expect(find.text('Salvage Module 1 of 3'), findsOneWidget);
    for (final id in offer.moduleIds) {
      expect(find.text(runModuleDefinition(id).title), findsOneWidget);
    }

    await tester.tap(find.text('Heavy Caliber'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

/// Pumps [OrionGamePage], enters the first stage, and drives the panel with a
/// faked snapshot carrying [selectedTower]. Returns the captured game.
Future<OrionDefenseGame?> _pumpStageWithSelectedTower(
  WidgetTester tester,
  PlacedTower selectedTower, {
  GamePhase phase = GamePhase.build,
  TowerStats? selectedTowerStats,
  RunModuleOffer? pendingRunModuleOffer,
  List<RunModuleId> acquiredRunModules = const [],
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
  expect(find.text('Launch Mission'), findsOneWidget);
  await tester.tap(find.text('Launch Mission'));
  await tester.pump();

  final snapshot = game!.stateNotifier.value;
  game!.stateNotifier.value = GameSnapshot(
    phase: phase,
    gold: snapshot.gold,
    baseHealth: snapshot.baseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
    waveNumber: snapshot.waveNumber,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    stageModifiers: const [],
    nextWavePreview: snapshot.nextWavePreview,
    selectedCell: snapshot.selectedCell,
    selectedTower: selectedTower,
    feedback: snapshot.feedback,
    isPaused: snapshot.isPaused,
    speedMultiplier: snapshot.speedMultiplier,
    autoStartEnabled: snapshot.autoStartEnabled,
    autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
    pendingRunModuleOffer: pendingRunModuleOffer,
    acquiredRunModules: acquiredRunModules,
    selectedTowerStats: selectedTowerStats,
  );
  await tester.pump();

  return game;
}
