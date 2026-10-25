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

/// The placed tower the specialization tip points at while nothing is
/// selected: the first level-2 unspecialized tower on the board. Shared by
/// the resolver and the page so both agree on the same board-cell target.
PlacedTower? specializationCandidateIn(GameSnapshot snapshot) {
  for (final tower in snapshot.placedTowers) {
    if (tower.canSpecialize) {
      return tower;
    }
  }
  return null;
}

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

  // Tower selected: the specialization tip may point ONLY at this very
  // tower's radial progression surface — a different selected tower must
  // never inherit another tower's Upgrade-button lesson — so otherwise the
  // radial targeting action is the candidate. Both actions live on the
  // mounted radial, which the build-phase gate above keeps enabled.
  final selectedTower = snapshot.selectedTower;
  if (selectedTower != null) {
    if (!seen.contains(ContextualTip.specialization) &&
        selectedTower.canSpecialize) {
      return ContextualTip.specialization;
    }
    if (!seen.contains(ContextualTip.targeting)) {
      return ContextualTip.targeting;
    }
    return null;
  }

  // Any remaining selected cell is a nonbuildable path cell: the collapsed
  // scanner ignores taps while selected, so it is no more a target than a
  // tower selection — silence.
  if (snapshot.selectedCell != null) {
    return null;
  }

  // Nothing selected. Boss first (the collapsed scanner is usable only
  // now), then specialization pointing at a qualifying placed tower's
  // board cell. The modifier tip belongs to the separate stage-briefing
  // route and is never resolved here.
  if (!seen.contains(ContextualTip.bossWave)) {
    final preview = snapshot.nextWavePreview;
    if (preview != null && preview.bossGroups.isNotEmpty) {
      return ContextualTip.bossWave;
    }
  }
  if (!seen.contains(ContextualTip.specialization) &&
      specializationCandidateIn(snapshot) != null) {
    return ContextualTip.specialization;
  }
  return null;
}

/// Tips already taught by the snapshot itself: placing a tower of a tip's
/// family demonstrates the lesson, so the page unions these into the seen
/// set post-frame even if the bubble never showed.
Set<ContextualTip> learnedTipsIn(GameSnapshot snapshot) {
  return {
    for (final entry in contextualTipTowerTypes.entries)
      if (snapshot.placedTowers.any((tower) => tower.type == entry.value))
        entry.key,
    // Specializing any tower or changing any tower off the default
    // targeting mode demonstrates those lessons for the whole run.
    if (snapshot.placedTowers.any((tower) => tower.specialization != null))
      ContextualTip.specialization,
    if (snapshot.placedTowers.any(
      (tower) => tower.targetingMode != TowerTargetingMode.first,
    ))
      ContextualTip.targeting,
  };
}
