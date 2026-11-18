import '../models/game_models.dart';

/// The first-time contextual tips, in resolver priority order. Wave-unlock
/// tips went away with the HPA-922 roster pivot: squad membership already
/// tells the player what they field, so the remaining lessons are the boss
/// warning, the fixed-signature step, targeting modes and stage modifiers.
enum ContextualTip { bossWave, signature, targeting, stageModifier }

/// Exact design copy per tip; exhaustive over the enum so adding a tip
/// without copy is a compile error.
String contextualTipCopy(ContextualTip tip) => switch (tip) {
  ContextualTip.bossWave =>
    'Boss ahead. Check the scanner and prepare your defense.',
  ContextualTip.signature =>
    'Signature ready. Upgrade this member to tier 3 to apply it.',
  ContextualTip.targeting =>
    'Targeting modes. Choose which enemies this member attacks first.',
  ContextualTip.stageModifier =>
    'Stage modifier. These conditions change how this mission plays.',
};

/// The placed tower the signature tip points at while nothing is
/// selected: the first tier-2 tower whose fixed signature step (the
/// tier-2→3 upgrade) the player can currently afford. Shared by the
/// resolver and the page so both agree on the same board-cell target.
PlacedTower? signatureCandidateIn(GameSnapshot snapshot) {
  for (final tower in snapshot.placedTowers) {
    if (tower.level == 2 && _canAffordSignature(snapshot, tower)) {
      return tower;
    }
  }
  return null;
}

/// The tier-2→3 signature price comes from [TowerStats.nextUpgradeCost] —
/// the same value the inspector charges — so the tip never guides toward an
/// action the Upgrade button would show at a different price or disabled.
bool _canAffordSignature(GameSnapshot snapshot, PlacedTower tower) {
  final nextCost = GameBalance.towerStats(
    tower.type,
    level: tower.level,
  ).nextUpgradeCost;
  return nextCost != null && snapshot.gold >= nextCost;
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

  // A selected cell — buildable or not — swaps the idle bar for the
  // build rail or silences the collapsed scanner; no tip anchors there.
  if (snapshot.selectedCell != null && snapshot.selectedTower == null) {
    return null;
  }

  // Member selected: the signature tip may point ONLY at this very
  // member's radial progression surface — a different selected member must
  // never inherit another member's Upgrade-button lesson — so otherwise the
  // radial targeting action is the candidate. Both actions live on the
  // mounted radial, which the build-phase gate above keeps enabled. An
  // unaffordable signature step would dead-end on the same surface —
  // silence until gold covers it, exactly like the upgrade tip.
  final selectedTower = snapshot.selectedTower;
  if (selectedTower != null) {
    if (!seen.contains(ContextualTip.signature) &&
        selectedTower.level == 2 &&
        _canAffordSignature(snapshot, selectedTower)) {
      return ContextualTip.signature;
    }
    if (!seen.contains(ContextualTip.targeting)) {
      return ContextualTip.targeting;
    }
    return null;
  }

  // Nothing selected. Boss first (the collapsed scanner is usable only
  // now), then signature pointing at a qualifying placed member's
  // board cell. The modifier tip belongs to the separate stage-briefing
  // route and is never resolved here.
  if (!seen.contains(ContextualTip.bossWave)) {
    final preview = snapshot.nextWavePreview;
    if (preview != null && preview.bossGroups.isNotEmpty) {
      return ContextualTip.bossWave;
    }
  }
  if (!seen.contains(ContextualTip.signature) &&
      signatureCandidateIn(snapshot) != null) {
    return ContextualTip.signature;
  }
  return null;
}

/// Tips already taught by the snapshot itself: reaching tier 3 on any
/// member or moving any member off the default targeting mode demonstrates
/// those lessons for the whole run, so the page unions these into the seen
/// set post-frame even if the bubble never showed.
Set<ContextualTip> learnedTipsIn(GameSnapshot snapshot) {
  return {
    if (snapshot.placedTowers.any((tower) => tower.specialization != null))
      ContextualTip.signature,
    if (snapshot.placedTowers.any(
      (tower) => tower.targetingMode != TowerTargetingMode.first,
    ))
      ContextualTip.targeting,
  };
}
