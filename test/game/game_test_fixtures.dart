import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

StageDefinition stageWithWaveCount(
  int count, {
  List<StageModifier> modifiers = const [],
}) {
  if (count <= 0) throw ArgumentError.value(count, 'count');
  return StageDefinition(
    id: 'empty-wave-stage-$count',
    name: 'Empty Wave Stage',
    mapLabel: 'Empty',
    description: 'Stage with empty waves for timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      count,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
    modifiers: modifiers,
  );
}

/// Fresh-profile starter squad (Haruto and Mio at level 1) — mirrors
/// `CampaignSave.starterOwnedLevels` without importing the persistence layer.
const Map<Character, int> testStarterSquad = {
  Character.haruto: 1,
  Character.mio: 1,
};

/// Builds a valid squad map from explicit [members] — never more than
/// `GameBalance.squadMaxSize`, which `GameSession` now enforces. Tests that
/// "deploy freely" list the members they actually use; tests needing every
/// roster member run separate valid squads per scenario.
Map<Character, int> testSquadOf(Iterable<Character> members, {int level = 1}) =>
    {for (final member in members) member: level};

/// The first roster member whose combat [style] matches [type] — the
/// canonical character stand-in when a test only cares about the style.
Character testCharacterFor(TowerType type) =>
    Character.values.firstWhere((character) => character.style == type);

/// Builds a [PlacedTower] in the old test style. [character] wins; next a
/// [specialization] picks the member who owns that fixed signature (and
/// forces tier 3); otherwise [type] picks the first member with that style.
/// The signature cannot be chosen freely — it is the member's own.
PlacedTower testTower({
  int id = 1,
  TowerType? type,
  TowerSpecialization? specialization,
  Character? character,
  int characterLevel = 1,
  required GridPosition position,
  int level = 1,
  TowerTargetingMode targetingMode = TowerTargetingMode.first,
}) {
  final resolved =
      character ??
      (specialization != null
          ? Character.values.firstWhere(
              (member) => member.signature == specialization,
            )
          : testCharacterFor(type!));
  if (specialization != null && resolved.signature != specialization) {
    throw ArgumentError.value(
      specialization,
      'specialization',
      'must be the character fixed signature',
    );
  }
  return PlacedTower(
    id: id,
    character: resolved,
    characterLevel: characterLevel,
    position: position,
    level: specialization != null ? 3 : level,
    targetingMode: targetingMode,
  );
}
