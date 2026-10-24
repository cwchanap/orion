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

/// Resolves the single current contextual tip from a snapshot alone.
///
/// Pure and stateless, mirroring `firstMissionGuideStepFor`: reads only
/// [GameSnapshot] fields plus the typed seen set. Universal gating — build
/// phase, no module draft open, session not ended — then per-tip
/// eligibility. Returns at most one tip; `null` means silence.
ContextualTip? contextualTipFor(
  GameSnapshot snapshot,
  Set<ContextualTip> seen,
) {
  if (snapshot.phase != GamePhase.build ||
      snapshot.pendingRunModuleOffer != null ||
      snapshot.isEnded) {
    return null;
  }

  // Slice 1 resolves only the boss tip. The collapsed scanner collapses and
  // ignores taps while any cell or tower is selected — require no selection
  // so the anchor points at a usable control. The modifier tip belongs to
  // the separate stage-briefing route and is never resolved here.
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
