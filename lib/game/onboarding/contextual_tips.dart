import '../models/game_models.dart';

/// The nine first-time contextual tips, in resolver priority order.
enum ContextualTip {
  bossWave,
  railgun,
  ionChain,
  nanite,
  gravityWell,
  droneBay,
  specialization,
  targeting,
  stageModifier,
}

/// Exact design copy per tip; exhaustive over the enum so adding a tip
/// without copy is a compile error.
const Map<ContextualTip, String> contextualTipCopy = {
  ContextualTip.bossWave:
      'Boss ahead. Check the scanner and prepare your defense.',
  ContextualTip.railgun: 'Railgun unlocked. Pierces enemies in a line.',
  ContextualTip.ionChain:
      'Ion Chain unlocked. Lightning jumps between targets.',
  ContextualTip.nanite: 'Nanite unlocked. Corrodes armor to help other towers.',
  ContextualTip.gravityWell:
      'Gravity Well unlocked. Damages enemies within its field.',
  ContextualTip.droneBay:
      'Drone Bay unlocked. Launches autonomous interceptors.',
  ContextualTip.specialization:
      'Specialization ready. Choose one of two ways to evolve this tower.',
  ContextualTip.targeting:
      'Targeting modes. Choose which enemies this tower attacks first.',
  ContextualTip.stageModifier:
      'Stage modifier. These conditions change how this mission plays.',
};

/// The tower-unlock tips, each mapped to the build-rail card it anchors on.
/// Insertion order is the unlock order and doubles as resolver priority;
/// wave-1 families (Laser/Rocket/Cryo) are covered by HPA-412 and absent.
const Map<ContextualTip, TowerType> contextualTipTowerTypes = {
  ContextualTip.railgun: TowerType.railgun,
  ContextualTip.ionChain: TowerType.ionChain,
  ContextualTip.nanite: TowerType.nanite,
  ContextualTip.gravityWell: TowerType.gravityWell,
  ContextualTip.droneBay: TowerType.droneBay,
};

/// Resolves the single current contextual tip from a snapshot alone.
///
/// Pure and stateless, mirroring `firstMissionGuideStepFor`: reads only
/// [GameSnapshot] fields plus the typed seen set. Universal gating — build
/// phase, no module draft open, session not ended — then selection-dependent
/// candidates. Returns at most one tip; `null` means silence.
ContextualTip? contextualTipFor(
  GameSnapshot snapshot,
  Set<ContextualTip> seen,
) {
  if (snapshot.phase != GamePhase.build ||
      snapshot.pendingRunModuleOffer != null ||
      snapshot.isEnded) {
    return null;
  }

  // A buildable selected cell swaps the idle bar for the selected-cell
  // build rail, so the unlock cards are the candidates there — in unlock
  // (enum) order, first unseen-and-unlocked wins. Locked cards wait for
  // their unlock wave.
  if (snapshot.selectedCell != null &&
      snapshot.selectedCellBuildable &&
      snapshot.selectedTower == null) {
    for (final entry in contextualTipTowerTypes.entries) {
      if (!seen.contains(entry.key) &&
          snapshot.unlockedTowerTypes.contains(entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  // Boss tip: the collapsed scanner collapses and ignores taps while any
  // cell or tower is selected — require no selection so the anchor points
  // at a usable control. The modifier tip belongs to the separate
  // stage-briefing route and is never resolved here.
  if (seen.contains(ContextualTip.bossWave)) {
    return null;
  }
  if (snapshot.selectedCell != null || snapshot.selectedTower != null) {
    return null;
  }
  final preview = snapshot.nextWavePreview;
  if (preview == null || preview.bossGroups.isEmpty) {
    return null;
  }
  return ContextualTip.bossWave;
}

/// Tips already taught by the snapshot itself: placing a tower of a tip's
/// family demonstrates the lesson, so the page unions these into the seen
/// set post-frame even if the bubble never showed.
Set<ContextualTip> learnedTipsIn(GameSnapshot snapshot) {
  return {
    for (final entry in contextualTipTowerTypes.entries)
      if (snapshot.placedTowers.any((tower) => tower.type == entry.value))
        entry.key,
  };
}
