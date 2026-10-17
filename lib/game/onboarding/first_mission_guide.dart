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
  // Only the FIRST module draft gets the salvage lesson (drafts require a
  // pick — there is no decline — so an empty acquired list means this is
  // the first offer). Later drafts fall through to the scanner/upgrade
  // rules like any other snapshot; selecting a module hands off to the
  // scanner step below.
  if (snapshot.pendingRunModuleOffer != null &&
      snapshot.acquiredRunModules.isEmpty) {
    return FirstMissionGuideStep.salvageModule;
  }

  if (snapshot.phase != GamePhase.build) {
    return null;
  }

  if (snapshot.waveNumber >= 3 && snapshot.acquiredRunModules.isNotEmpty) {
    return FirstMissionGuideStep.scanner;
  }

  if (snapshot.waveNumber >= 2) {
    // The upgrade lesson is satisfied once ANY placed tower is Level 2+ —
    // one completed upgrade means the player already learned the action —
    // and the guide silences entirely when no tower exists to upgrade
    // (sold every tower); never guide toward an impossible action.
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
