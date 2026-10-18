import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/onboarding/first_mission_guide.dart';

GameSnapshot _snapshot({
  GamePhase phase = GamePhase.build,
  int waveNumber = 1,
  List<PlacedTower> placedTowers = const [],
  GridPosition? selectedCell,
  RunModuleOffer? pendingRunModuleOffer,
  List<RunModuleId> acquiredRunModules = const [],
}) {
  return GameSnapshot(
    phase: phase,
    gold: 150,
    baseHealth: 20,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    waveTotal: 8,
    stageId: 'nebula-relay',
    stageName: 'Nebula Relay',
    stageLabel: 'NR',
    unlockedTowerTypes: const [TowerType.laser],
    stageModifiers: const [],
    selectedCell: selectedCell,
    selectedTower: null,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    pendingRunModuleOffer: pendingRunModuleOffer,
    acquiredRunModules: acquiredRunModules,
    placedTowers: placedTowers,
  );
}

PlacedTower _tower({int level = 1}) {
  return PlacedTower(
    id: 1,
    type: TowerType.laser,
    position: const GridPosition(2, 2),
    level: level,
  );
}

RunModuleOffer _offer({int draftNumber = 1}) {
  return RunModuleOffer(
    offerId: draftNumber,
    draftNumber: draftNumber,
    draftTotal: 3,
    moduleIds: const [RunModuleId.heavyCaliber, RunModuleId.longSight],
  );
}

void main() {
  group('firstMissionGuideStepFor', () {
    test('guides cell selection in the initial Wave-1 build phase', () {
      expect(
        firstMissionGuideStepFor(_snapshot()),
        FirstMissionGuideStep.buildCell,
      );
    });

    test('guides the tower card once a cell is selected', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(selectedCell: const GridPosition(2, 2)),
        ),
        FirstMissionGuideStep.towerCard,
      );
    });

    test('guides starting Wave 1 once a tower is placed', () {
      expect(
        firstMissionGuideStepFor(_snapshot(placedTowers: [_tower()])),
        FirstMissionGuideStep.startWave,
      );
    });

    test('stays silent during an active Wave 1', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(phase: GamePhase.wave, placedTowers: [_tower()]),
        ),
        isNull,
      );
    });

    test('guides an upgrade in the Wave-2 build with only Level-1 towers', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(waveNumber: 2, placedTowers: [_tower()]),
        ),
        FirstMissionGuideStep.upgrade,
      );
    });

    test('stays silent in Wave-2 build once any tower is Level 2+', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(waveNumber: 2, placedTowers: [_tower(level: 2)]),
        ),
        isNull,
      );
    });

    test('stays silent in a Wave-2+ build with no towers left', () {
      // Sell-all path: nothing left to upgrade, so no callout.
      expect(firstMissionGuideStepFor(_snapshot(waveNumber: 2)), isNull);
    });

    test('guides salvage while the first module offer is pending', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(
            waveNumber: 3,
            placedTowers: [_tower()],
            pendingRunModuleOffer: _offer(),
          ),
        ),
        FirstMissionGuideStep.salvageModule,
      );
    });

    test('a later module draft does not repeat the salvage lesson', () {
      // The player already picked a module (acquired is non-empty), so this
      // pending offer is a subsequent draft: it falls through to the normal
      // scanner rule instead of re-showing the salvage callout.
      expect(
        firstMissionGuideStepFor(
          _snapshot(
            waveNumber: 5,
            placedTowers: [_tower()],
            pendingRunModuleOffer: _offer(draftNumber: 2),
            acquiredRunModules: const [RunModuleId.heavyCaliber],
          ),
        ),
        FirstMissionGuideStep.scanner,
      );
    });

    test('guides the scanner in Wave-3+ build after the first module', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(
            waveNumber: 3,
            placedTowers: [_tower()],
            acquiredRunModules: const [RunModuleId.heavyCaliber],
          ),
        ),
        FirstMissionGuideStep.scanner,
      );
    });

    test('stays silent during active Wave 3+', () {
      expect(
        firstMissionGuideStepFor(
          _snapshot(
            phase: GamePhase.wave,
            waveNumber: 3,
            placedTowers: [_tower()],
            acquiredRunModules: const [RunModuleId.heavyCaliber],
          ),
        ),
        isNull,
      );
    });

    test('drag placement skips the tower card and guides start wave', () {
      // Drag placement creates a tower without ever selecting a cell.
      final dragPlacement = _snapshot(placedTowers: [_tower()]);
      expect(dragPlacement.selectedCell, isNull);
      expect(
        firstMissionGuideStepFor(dragPlacement),
        FirstMissionGuideStep.startWave,
      );
    });
  });
}
