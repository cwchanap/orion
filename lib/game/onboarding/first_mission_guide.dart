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

  // The scanner control collapses and ignores taps while any cell or tower
  // is selected — point at it only when it can actually open. With a
  // selection held the lesson falls through to the upgrade rule when that
  // milestone is still pending, else stays silent until the deselect.
  if (snapshot.waveNumber >= 3 &&
      snapshot.acquiredRunModules.isNotEmpty &&
      snapshot.selectedCell == null &&
      snapshot.selectedTower == null) {
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

  // A selected path cell can't take a tower — stay on the cell lesson
  // rather than send the player at a card whose placement always fails.
  if (snapshot.selectedCell != null && snapshot.selectedCellBuildable) {
    return FirstMissionGuideStep.towerCard;
  }

  return FirstMissionGuideStep.buildCell;
}
