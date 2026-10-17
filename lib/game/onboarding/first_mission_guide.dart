import '../models/game_models.dart';

/// One callout in the first-mission tutorial, in guided order.
enum FirstMissionGuideStep {
  buildCell,
  towerCard,
  startWave,
  upgrade,
  salvageModule,
  scanner,
}

/// Resolves the current first-mission guide step from a snapshot alone.
///
/// Pure and stateless: reads only [GameSnapshot] fields — no mutable
/// progress, timestamps, callbacks, or game reference.
FirstMissionGuideStep? firstMissionGuideStepFor(GameSnapshot snapshot) {
  // A pending module draft overrides everything; selecting a module hands
  // off to the scanner step below.
  if (snapshot.pendingRunModuleOffer != null) {
    return FirstMissionGuideStep.salvageModule;
  }

  if (snapshot.phase != GamePhase.build) {
    return null;
  }

  if (snapshot.waveNumber >= 3 && snapshot.acquiredRunModules.isNotEmpty) {
    return FirstMissionGuideStep.scanner;
  }

  if (snapshot.waveNumber >= 2) {
    // Silence once nothing is left to upgrade (all Level 2+, or the player
    // sold every tower); never guide toward an impossible action.
    if (snapshot.placedTowers.isEmpty ||
        snapshot.placedTowers.any((tower) => tower.level >= 2)) {
      return null;
    }
    return FirstMissionGuideStep.upgrade;
  }

  if (snapshot.placedTowers.isNotEmpty) {
    return FirstMissionGuideStep.startWave;
  }

  if (snapshot.selectedCell != null) {
    return FirstMissionGuideStep.towerCard;
  }

  return FirstMissionGuideStep.buildCell;
}
