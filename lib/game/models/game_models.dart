import 'dart:math' as math;

import '../util/format.dart';

enum GamePhase { build, wave, won, lost }

enum RunMode { mission, endless }

enum TowerType {
  laser('Laser'),
  rocket('Rocket'),
  cryo('Cryo'),
  railgun('Railgun'),
  ionChain('Ion Chain'),
  nanite('Nanite'),
  gravityWell('Gravity Well'),
  droneBay('Drone Bay');

  const TowerType(this.label);
  final String label;
}

enum TowerSpecialization {
  pulseLaser(TowerType.laser, 'Pulse Laser'),
  prismLaser(TowerType.laser, 'Prism Laser'),
  siegeRocket(TowerType.rocket, 'Siege Rocket'),
  clusterRocket(TowerType.rocket, 'Cluster Rocket'),
  deepFreeze(TowerType.cryo, 'Deep Freeze'),
  frostbite(TowerType.cryo, 'Frostbite'),
  lanceRailgun(TowerType.railgun, 'Lance Railgun'),
  magneticRailgun(TowerType.railgun, 'Magnetic Railgun'),
  stormRelay(TowerType.ionChain, 'Storm Relay'),
  overloadRelay(TowerType.ionChain, 'Overload Relay'),
  dissolverNanites(TowerType.nanite, 'Dissolver Nanites'),
  replicatorNanites(TowerType.nanite, 'Replicator Nanites'),
  singularityWell(TowerType.gravityWell, 'Singularity Well'),
  crushWell(TowerType.gravityWell, 'Crush Well'),
  interceptorBay(TowerType.droneBay, 'Interceptor Bay'),
  hunterBay(TowerType.droneBay, 'Hunter Bay');

  const TowerSpecialization(this.type, this.label);

  final TowerType type;
  final String label;

  /// One-sentence gameplay role shared by the Codex and the tower inspector.
  String get role => switch (this) {
    TowerSpecialization.pulseLaser =>
      'Maximized fire rate for concentrated single-target damage.',
    TowerSpecialization.prismLaser =>
      'Each shot splits to one nearby target at reduced damage.',
    TowerSpecialization.siegeRocket =>
      'Heaviest single hit with the largest splash radius.',
    TowerSpecialization.clusterRocket =>
      'Detonates into clustered sub-explosions across the impact area.',
    TowerSpecialization.deepFreeze =>
      'The strongest, longest slow; locks enemies down at the cost of raw damage.',
    TowerSpecialization.frostbite =>
      'Balanced slow that deals bonus damage to already-slowed enemies.',
    TowerSpecialization.lanceRailgun =>
      'Maximum pierce — punches through the most targets in a line.',
    TowerSpecialization.magneticRailgun =>
      'Trades pierce for bonus damage versus armored enemies.',
    TowerSpecialization.stormRelay =>
      'The longest chain lightning, jumping to the most targets.',
    TowerSpecialization.overloadRelay =>
      'Trades chain count for bonus damage versus shielded enemies.',
    TowerSpecialization.dissolverNanites =>
      'Peak corrosion and armor shred to strip the heaviest plating.',
    TowerSpecialization.replicatorNanites =>
      'Balanced corrosion stream with sustained damage and lighter shred.',
    TowerSpecialization.singularityWell =>
      'The largest, longest-lasting field — also slows enemies caught inside.',
    TowerSpecialization.crushWell =>
      'A tighter, concentrated field for a focused kill zone.',
    TowerSpecialization.interceptorBay =>
      'More, faster-firing drones for broad interception.',
    TowerSpecialization.hunterBay =>
      'Fewer, harder-hitting drones that persist longer.',
  };
}

/// Persistent roster rank, ordered weakest to strongest. The damage-channel
/// multiplier for each rank lives in [GameBalance.characterRankMultipliers].
enum CharacterRank {
  e('E'),
  d('D'),
  c('C'),
  b('B'),
  a('A'),
  s('S');

  const CharacterRank(this.label);
  final String label;
}

/// One of the twelve Last Hearth roster members (HPA-922). Each character is
/// bound to a fixed [signature] specialization; its combat [style] is derived
/// from `signature.type` so a character can never carry a mismatched style.
/// [Character.values] is the Camp display order; [Character.name] is the
/// stable lowercase save key and per-character art folder.
enum Character {
  hikari(
    rank: CharacterRank.s,
    fullName: 'Hikari Amatsu, Dawnbringer',
    role: 'Prism laser vanguard',
    bio:
        'First light of the Last Hearth. Her split-beam volleys break the '
        'front of every assault.',
    signature: TowerSpecialization.prismLaser,
    signatureName: 'Dawnbreak',
  ),
  jin(
    rank: CharacterRank.s,
    fullName: 'Jin Kamishiro, the Thawed One',
    role: 'Deep-freeze controller',
    bio:
        'Pulled from the ice and still half-frozen, Jin locks whole columns '
        'in place so the Hearth can breathe.',
    signature: TowerSpecialization.deepFreeze,
    signatureName: 'Absolute Zero',
  ),
  akane(
    rank: CharacterRank.a,
    fullName: 'Akane Hinomori',
    role: 'Siege rocket bombardier',
    bio:
        "Keeper of the Hearth's biggest guns, Akane answers every armored "
        'push with one overwhelming barrage.',
    signature: TowerSpecialization.siegeRocket,
    signatureName: 'Hearthfire',
  ),
  ren(
    rank: CharacterRank.a,
    fullName: 'Ren Kurosawa',
    role: 'Gravity field anchor',
    bio:
        'A quiet tactician who bends the field itself, dragging attackers '
        'into singularities they cannot escape.',
    signature: TowerSpecialization.singularityWell,
    signatureName: 'Crushing Field',
  ),
  elena(
    rank: CharacterRank.b,
    fullName: 'Elena Volkova',
    role: 'Anti-armor railgunner',
    bio:
        'A marksman who reads plating like scripture; her magnetized rounds '
        'find the seam in every hull.',
    signature: TowerSpecialization.magneticRailgun,
    signatureName: 'Heat Sight',
  ),
  shiori(
    rank: CharacterRank.b,
    fullName: 'Dr. Shiori Kusanagi',
    role: 'Nanite corrosion specialist',
    bio:
        "The Hearth's resident chemist. Her dissolver swarms strip armor "
        'molecule by molecule.',
    signature: TowerSpecialization.dissolverNanites,
    signatureName: 'Dissolving Serum',
  ),
  rin(
    rank: CharacterRank.c,
    fullName: 'Rin Fuyutsuki',
    role: 'Frostbite skirmisher',
    bio:
        'Quick, cold and relentless — Rin punishes anything already slowed '
        'by the winter line.',
    signature: TowerSpecialization.frostbite,
    signatureName: 'Frostbite',
  ),
  kaito(
    rank: CharacterRank.c,
    fullName: 'Kaito Narumi',
    role: 'Storm chain gunner',
    bio:
        'A self-taught engineer whose relay coils arc lightning across '
        'whole packs of drones.',
    signature: TowerSpecialization.stormRelay,
    signatureName: 'Live Wire',
  ),
  sayo(
    rank: CharacterRank.d,
    fullName: 'Sayo Kitami',
    role: 'Piercing railgunner',
    bio:
        'Patient and precise, Sayo lines up shots that skewer an entire '
        'column in one discharge.',
    signature: TowerSpecialization.lanceRailgun,
    signatureName: 'Through Shot',
  ),
  tetsuo(
    rank: CharacterRank.d,
    fullName: 'Tetsuo Kanda',
    role: 'Drone bay handler',
    bio:
        'A salvage-yard tinkerer whose patched-together interceptors swarm '
        'anything that slips the line.',
    signature: TowerSpecialization.interceptorBay,
    signatureName: 'Scrap Swarm',
  ),
  haruto(
    rank: CharacterRank.e,
    fullName: 'Haruto Sakaki',
    role: 'Pulse laser gunner',
    bio:
        "One of the Hearth's newest defenders. Nothing fancy — a steady "
        'volley that never misses twice.',
    signature: TowerSpecialization.pulseLaser,
    signatureName: 'Steady Volley',
  ),
  mio(
    rank: CharacterRank.e,
    fullName: 'Mio Tachibana',
    role: 'Cluster rocket rocketeer',
    bio:
        "The Hearth's cook turned rocketeer; her cluster shells burst over "
        'attackers like a kitchen flare.',
    signature: TowerSpecialization.clusterRocket,
    signatureName: 'Kitchen Fire',
  );

  const Character({
    required this.rank,
    required this.fullName,
    required this.role,
    required this.bio,
    required this.signature,
    required this.signatureName,
  });

  final CharacterRank rank;

  /// Full roster name with epithet, used on the character sheet.
  final String fullName;

  /// One-line combat role shared by the Camp roster and character sheet.
  final String role;
  final String bio;

  /// The fixed tier-3 specialization this character always deploys.
  final TowerSpecialization signature;

  /// Working skill name shown for [signature] in the UI.
  final String signatureName;

  /// The internal combat style backing this character's stats, modules and
  /// effects — derived from the signature so it can never drift.
  TowerType get style => signature.type;

  /// Short given-name label for rosters and docks, derived from the stable
  /// lowercase [name] key ('hikari' → 'Hikari').
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

enum EnemyTrait {
  armored('Armored'),
  shielded('Shielded'),
  swarm('Swarm'),
  regen('Regen'),
  heavy('Heavy');

  const EnemyTrait(this.label);
  final String label;
}

enum StageModifier {
  shieldRecharge,
  swarmBounty,
  reinforcedArmor,
  regenPressurePulses,
  reducedStartingHealth,
  enhancedClearBonus,
  enemySpeedSurge,
  amplifiedGravityWells,
}

enum EnemyArchetype {
  basicDrone('Drones'),
  basicEliteDrone('Elite Drones'),
  armoredDrone('Armored Drones'),
  shieldedDrone('Shielded Drones'),
  swarmDrone('Swarm Drones'),
  regenDrone('Regen Drones'),
  heavyDrone('Heavy Drones'),
  armoredHeavyDrone('Armored Heavy Drones'),
  regenHeavyDrone('Regen Heavy Drones');

  const EnemyArchetype(this.label);
  final String label;
}

enum PlacementFailure {
  invalidPhase,
  pendingModuleDraft,
  offBoard,
  pathBlocked,
  occupied,
  insufficientGold,
  notInSquad,
  alreadyDeployed,
}

enum TowerTargetingMode {
  first('First'),
  strongest('Strongest'),
  weakest('Weakest'),
  closest('Closest'),
  shielded('Shielded'),
  armored('Armored');

  const TowerTargetingMode(this.label);
  final String label;
}

enum RunModuleId {
  heavyCaliber,
  overclockRelay,
  longSight,
  emergencySalvage,
  cryoReservoir,
  rocketFusing,
  relayCalibration,
  relayArc,
  salvagedDrones,
  foundryNanites,
  auroraFocus,
  siegeRounds,
  gravityEcho,
}

class GridPosition {
  const GridPosition(this.column, this.row);

  final int column;
  final int row;

  double distanceTo(GridPosition other) {
    final dx = column - other.column;
    final dy = row - other.row;
    return math.sqrt((dx * dx) + (dy * dy));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GridPosition &&
            runtimeType == other.runtimeType &&
            column == other.column &&
            row == other.row;
  }

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => 'GridPosition(column: $column, row: $row)';
}

class PlacementResult {
  const PlacementResult._({required this.isAllowed, this.failure});

  const PlacementResult.allowed() : this._(isAllowed: true);

  const PlacementResult.denied(PlacementFailure failure)
    : this._(isAllowed: false, failure: failure);

  final bool isAllowed;
  final PlacementFailure? failure;
}

class TowerStats {
  const TowerStats({
    required this.type,
    required this.level,
    this.specialization,
    required this.cost,
    required this.upgradeCost,
    required this.specializationCost,
    required this.range,
    required this.damage,
    required this.fireInterval,
    required this.projectileSpeed,
    required this.splashRadius,
    required this.slowMultiplier,
    required this.slowDuration,
    this.pierceCount = 0,
    this.pierceWidth = 0,
    this.chainCount = 0,
    this.chainRange = 0,
    this.chainFalloff = 1,
    this.corrosionDamagePerSecond = 0,
    this.corrosionDuration = 0,
    this.armorShred = 0,
    this.fieldRadius = 0,
    this.fieldDuration = 0,
    this.fieldTickInterval = 0,
    this.droneCount = 0,
    this.droneLifetime = 0,
    this.droneDamage = 0,
    this.droneAttackInterval = 0,
    this.maxActiveDrones = 0,
    this.shieldDamageMultiplier = 1,
    this.armorDamageMultiplier = 1,
    this.slowedDamageMultiplier = 1,
    this.prismSplitDamageMultiplier = 0,
    this.prismSplitRange = 0,
    this.clusterBurstCount = 0,
    this.clusterBurstDamageMultiplier = 0,
    this.clusterBurstRadius = 0,
  });

  final TowerType type;
  final int level;
  final TowerSpecialization? specialization;
  final int cost;
  final int upgradeCost;
  final int specializationCost;
  final double range;
  final double damage;
  final double fireInterval;
  final double projectileSpeed;
  final double splashRadius;
  final double slowMultiplier;
  final double slowDuration;
  final int pierceCount;
  final double pierceWidth;
  final int chainCount;
  final double chainRange;
  final double chainFalloff;
  final double corrosionDamagePerSecond;
  final double corrosionDuration;
  final double armorShred;
  final double fieldRadius;
  final double fieldDuration;
  final double fieldTickInterval;
  final int droneCount;
  final double droneLifetime;
  final double droneDamage;
  final double droneAttackInterval;
  final int maxActiveDrones;
  final double shieldDamageMultiplier;
  final double armorDamageMultiplier;
  final double slowedDamageMultiplier;
  final double prismSplitDamageMultiplier;
  final double prismSplitRange;
  final int clusterBurstCount;
  final double clusterBurstDamageMultiplier;
  final double clusterBurstRadius;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TowerStats &&
          type == other.type &&
          level == other.level &&
          specialization == other.specialization &&
          cost == other.cost &&
          upgradeCost == other.upgradeCost &&
          specializationCost == other.specializationCost &&
          range == other.range &&
          damage == other.damage &&
          fireInterval == other.fireInterval &&
          projectileSpeed == other.projectileSpeed &&
          splashRadius == other.splashRadius &&
          slowMultiplier == other.slowMultiplier &&
          slowDuration == other.slowDuration &&
          pierceCount == other.pierceCount &&
          pierceWidth == other.pierceWidth &&
          chainCount == other.chainCount &&
          chainRange == other.chainRange &&
          chainFalloff == other.chainFalloff &&
          corrosionDamagePerSecond == other.corrosionDamagePerSecond &&
          corrosionDuration == other.corrosionDuration &&
          armorShred == other.armorShred &&
          fieldRadius == other.fieldRadius &&
          fieldDuration == other.fieldDuration &&
          fieldTickInterval == other.fieldTickInterval &&
          droneCount == other.droneCount &&
          droneLifetime == other.droneLifetime &&
          droneDamage == other.droneDamage &&
          droneAttackInterval == other.droneAttackInterval &&
          maxActiveDrones == other.maxActiveDrones &&
          shieldDamageMultiplier == other.shieldDamageMultiplier &&
          armorDamageMultiplier == other.armorDamageMultiplier &&
          slowedDamageMultiplier == other.slowedDamageMultiplier &&
          prismSplitDamageMultiplier == other.prismSplitDamageMultiplier &&
          prismSplitRange == other.prismSplitRange &&
          clusterBurstCount == other.clusterBurstCount &&
          clusterBurstDamageMultiplier == other.clusterBurstDamageMultiplier &&
          clusterBurstRadius == other.clusterBurstRadius;

  @override
  int get hashCode => Object.hashAll([
    type,
    level,
    specialization,
    cost,
    upgradeCost,
    specializationCost,
    range,
    damage,
    fireInterval,
    projectileSpeed,
    splashRadius,
    slowMultiplier,
    slowDuration,
    pierceCount,
    pierceWidth,
    chainCount,
    chainRange,
    chainFalloff,
    corrosionDamagePerSecond,
    corrosionDuration,
    armorShred,
    fieldRadius,
    fieldDuration,
    fieldTickInterval,
    droneCount,
    droneLifetime,
    droneDamage,
    droneAttackInterval,
    maxActiveDrones,
    shieldDamageMultiplier,
    armorDamageMultiplier,
    slowedDamageMultiplier,
    prismSplitDamageMultiplier,
    prismSplitRange,
    clusterBurstCount,
    clusterBurstDamageMultiplier,
    clusterBurstRadius,
  ]);

  bool get canUpgrade => level < 3;

  /// The one authoritative price of the next battle-tier transition: tier 1→2
  /// costs [upgradeCost], tier 2→3 (signature) costs [specializationCost], and
  /// a maxed tier 3 has no next cost. Callers must never read [upgradeCost]
  /// when [level] is 2.
  int? get nextUpgradeCost => switch (level) {
    1 => upgradeCost,
    2 => specializationCost,
    _ => null,
  };

  /// Returns a copy with the three damage channels — [damage],
  /// [corrosionDamagePerSecond] and [droneDamage] — multiplied by [factor].
  /// Shared by character rank/level scaling and run-module damage effects so
  /// every channel always scales together; all other fields are untouched.
  TowerStats scaleDamageChannels(double factor) {
    return copyWith(
      damage: damage * factor,
      corrosionDamagePerSecond: corrosionDamagePerSecond * factor,
      droneDamage: droneDamage * factor,
    );
  }

  /// Returns a copy with overridden fields. Exposes the fields runtime stat
  /// resolvers need to mutate: `fieldRadius` and `fieldDuration` for stage
  /// environmental modifiers (e.g. amplified gravity wells), and `damage`,
  /// `slowDuration`, `range`, `fireInterval`, `splashRadius`,
  /// `corrosionDamagePerSecond`, `droneDamage`, `chainCount`, and
  /// `pierceCount` for run modules and character scaling. Everything else
  /// copies from `this`. Kept narrow on purpose — extend only if another
  /// feature needs it.
  TowerStats copyWith({
    double? damage,
    double? slowDuration,
    double? fieldRadius,
    double? fieldDuration,
    double? range,
    double? fireInterval,
    double? splashRadius,
    double? corrosionDamagePerSecond,
    double? droneDamage,
    int? chainCount,
    int? pierceCount,
  }) {
    return TowerStats(
      type: type,
      level: level,
      specialization: specialization,
      cost: cost,
      upgradeCost: upgradeCost,
      specializationCost: specializationCost,
      range: range ?? this.range,
      damage: damage ?? this.damage,
      fireInterval: fireInterval ?? this.fireInterval,
      projectileSpeed: projectileSpeed,
      splashRadius: splashRadius ?? this.splashRadius,
      slowMultiplier: slowMultiplier,
      slowDuration: slowDuration ?? this.slowDuration,
      pierceCount: pierceCount ?? this.pierceCount,
      pierceWidth: pierceWidth,
      chainCount: chainCount ?? this.chainCount,
      chainRange: chainRange,
      chainFalloff: chainFalloff,
      corrosionDamagePerSecond:
          corrosionDamagePerSecond ?? this.corrosionDamagePerSecond,
      corrosionDuration: corrosionDuration,
      armorShred: armorShred,
      fieldRadius: fieldRadius ?? this.fieldRadius,
      fieldDuration: fieldDuration ?? this.fieldDuration,
      fieldTickInterval: fieldTickInterval,
      droneCount: droneCount,
      droneLifetime: droneLifetime,
      droneDamage: droneDamage ?? this.droneDamage,
      droneAttackInterval: droneAttackInterval,
      maxActiveDrones: maxActiveDrones,
      shieldDamageMultiplier: shieldDamageMultiplier,
      armorDamageMultiplier: armorDamageMultiplier,
      slowedDamageMultiplier: slowedDamageMultiplier,
      prismSplitDamageMultiplier: prismSplitDamageMultiplier,
      prismSplitRange: prismSplitRange,
      clusterBurstCount: clusterBurstCount,
      clusterBurstDamageMultiplier: clusterBurstDamageMultiplier,
      clusterBurstRadius: clusterBurstRadius,
    );
  }

  bool get isMaxLevel => level >= 3;
}

class EnemyStats {
  const EnemyStats({
    required this.health,
    required this.speed,
    required this.baseDamage,
    required this.goldReward,
    this.traits = const <EnemyTrait>{},
    this.shieldHealth = 0,
    this.armorReduction = 0,
    this.regenPerSecond = 0,
  });

  final double health;
  final double speed;
  final int baseDamage;
  final int goldReward;
  final Set<EnemyTrait> traits;
  final double shieldHealth;
  final double armorReduction;
  final double regenPerSecond;

  bool hasTrait(EnemyTrait trait) => traits.contains(trait);
}

enum BossSprite {
  relayBreaker,
  shieldMatriarch,
  swarmQueen,
  armoredExcavator,
  regenWarden,
  siegeCarrier,
  singularityCore,
}

class BossDefinition extends EnemyStats {
  const BossDefinition({
    required super.health,
    required super.speed,
    required super.baseDamage,
    required super.goldReward,
    super.traits,
    super.shieldHealth,
    super.armorReduction,
    super.regenPerSecond,
    required this.sprite,
    required this.name,
    this.summonMechanic,
  });

  final BossSprite sprite;
  final String name;
  final SummonMechanic? summonMechanic;
}

class SummonMechanic {
  const SummonMechanic({
    required this.interval,
    required this.minionStats,
    this.firstDelay = 3.0,
    this.count = 3,
    this.maxActive = 9,
  }) : assert(interval > 0, 'interval must be positive'),
       assert(firstDelay >= 0, 'firstDelay must be non-negative'),
       assert(count > 0, 'count must be positive'),
       assert(maxActive >= 0, 'maxActive must be non-negative');

  final double interval;
  final EnemyStats minionStats;
  final double firstDelay;
  final int count;
  final int maxActive;
}

class WaveGroup {
  const WaveGroup({
    required this.enemyCount,
    required this.enemyStats,
    this.spawnInterval = 0.85,
    this.initialDelay = 0,
  });

  final int enemyCount;
  final EnemyStats enemyStats;
  final double spawnInterval;
  final double initialDelay;
}

class WaveDefinition {
  const WaveDefinition({required this.groups, required this.clearBonus});

  final List<WaveGroup> groups;
  final int clearBonus;

  int get enemyCount {
    var total = 0;
    for (final group in groups) {
      total += group.enemyCount;
    }
    return total;
  }

  EnemyStats get enemyStats => groups.first.enemyStats;
  double get spawnInterval => groups.first.spawnInterval;
}

class WavePreviewGroup {
  WavePreviewGroup({
    required this.enemyCount,
    required this.label,
    required Set<EnemyTrait> traits,
  }) : traits = Set.unmodifiable(traits);

  final int enemyCount;
  final String label;
  final Set<EnemyTrait> traits;
}

class WavePreview {
  WavePreview({
    required this.waveNumber,
    required this.missionWaveTotal,
    required List<WavePreviewGroup> groups,
    required Set<EnemyTrait> traits,
    required this.clearBonus,
    required List<TowerType> recommendedTowerTypes,
    this.enemyHealthMultiplier = 1,
  }) : groups = List.unmodifiable(groups),
       traits = Set.unmodifiable(traits),
       recommendedTowerTypes = List.unmodifiable(recommendedTowerTypes);

  final int waveNumber;
  final int? missionWaveTotal;
  final List<WavePreviewGroup> groups;
  final Set<EnemyTrait> traits;
  final int clearBonus;
  final List<TowerType> recommendedTowerTypes;
  final double enemyHealthMultiplier;

  /// Groups whose label matches a [GameBalance.bosses] entry. The one shared
  /// boss predicate: the scanner's boss cards and the contextual boss-tip
  /// resolution both read this getter, so they can never drift apart.
  Iterable<WavePreviewGroup> get bossGroups =>
      groups.where((g) => GameBalance.bosses.any((b) => b.name == g.label));
}

/// A deployed squad member (HPA-922). Identity is the [Character] plus its
/// persistent [characterLevel]; the battle-tier progression lives in [level]
/// (1–3), where tier 3 is always the character's fixed [Character.signature].
class PlacedTower {
  const PlacedTower({
    required this.id,
    required this.character,
    required this.position,
    this.characterLevel = 1,
    this.level = 1,
    this.targetingMode = TowerTargetingMode.first,
  });

  final int id;

  /// The deployed squad member — one deployment per character per battle.
  final Character character;

  /// The character's persistent profile level, scaling damage channels.
  final int characterLevel;
  final GridPosition position;

  /// Battle tier: 1 base, 2 upgraded, 3 signature. Distinct from
  /// [characterLevel], which is the persistent profile progression.
  final int level;
  final TowerTargetingMode targetingMode;

  /// The combat style backing stats, modules and effects — derived from the
  /// character so two squad members may share it while staying distinct.
  TowerType get type => character.style;

  /// The fixed tier-3 signature; null below tier 3 by construction.
  TowerSpecialization? get specialization =>
      level == 3 ? character.signature : null;

  bool get canUpgrade => level < 3;
  bool get isMaxLevel => level >= 3;

  /// One merged progression step: tier 1→2, then tier 2→3 which applies the
  /// character's fixed signature automatically.
  PlacedTower upgraded() {
    if (!canUpgrade) {
      throw StateError('Tower can only be upgraded below level 3');
    }
    return PlacedTower(
      id: id,
      character: character,
      characterLevel: characterLevel,
      position: position,
      level: level + 1,
      targetingMode: targetingMode,
    );
  }

  PlacedTower copyWith({TowerTargetingMode? targetingMode}) {
    return PlacedTower(
      id: id,
      character: character,
      characterLevel: characterLevel,
      position: position,
      level: level,
      targetingMode: targetingMode ?? this.targetingMode,
    );
  }
}

class GameSnapshot {
  GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.startingBaseHealth,
    required this.waveNumber,
    required this.missionWaveTotal,
    required this.wavesCleared,
    this.waveHostilesTotal,
    this.waveHostilesRemaining,
    this.waveClearBonus,
    required this.stageId,
    required this.stageName,
    required this.stageLabel,
    required List<TowerType> unlockedTowerTypes,
    required List<Character> squad,
    required Map<Character, int> squadLevels,
    required List<StageModifier> stageModifiers,
    this.nextWavePreview,
    required this.selectedCell,
    required this.selectedTower,
    this.selectedCellBuildable = true,
    required this.feedback,
    required this.isPaused,
    this.bossActive = false,
    required this.speedMultiplier,
    required this.autoStartEnabled,
    required this.autoStartCountdownRemaining,
    this.pendingRunModuleOffer,
    List<RunModuleId> acquiredRunModules = const [],
    List<PlacedTower> placedTowers = const [],
    this.selectedTowerStats,
    this.selectedTowerUpgradeStats,
    Map<RunModuleId, int> pendingRunModuleBeneficiaries = const {},
  }) : unlockedTowerTypes = List.unmodifiable(unlockedTowerTypes),
       squad = List.unmodifiable(squad),
       squadLevels = Map.unmodifiable(squadLevels),
       stageModifiers = List.unmodifiable(stageModifiers),
       acquiredRunModules = List.unmodifiable(acquiredRunModules),
       placedTowers = List.unmodifiable(placedTowers),
       pendingRunModuleBeneficiaries = Map.unmodifiable(
         pendingRunModuleBeneficiaries,
       );

  final GamePhase phase;
  final int gold;
  final int baseHealth;
  final int startingBaseHealth;
  final int waveNumber;
  final int? missionWaveTotal;
  final int wavesCleared;
  final int? waveHostilesTotal;
  final int? waveHostilesRemaining;
  final int? waveClearBonus;
  final String stageId;
  final String stageName;
  final String stageLabel;
  final List<TowerType> unlockedTowerTypes;

  /// The ordered squad roster launched with this battle (HPA-922) — one
  /// entry per member, preserved separately from the deduplicated
  /// [unlockedTowerTypes] style list that scanner/module systems consume.
  final List<Character> squad;

  /// Persistent profile level per [squad] member, keyed by character.
  final Map<Character, int> squadLevels;
  final List<StageModifier> stageModifiers;
  final WavePreview? nextWavePreview;
  final GridPosition? selectedCell;
  final PlacedTower? selectedTower;

  /// Whether [selectedCell] is a legal build site; false when the session
  /// reports a path cell (or out-of-bounds position) as selected. Meaningful
  /// only while [selectedCell] is non-null — the default keeps fixtures that
  /// select a cell without declaring buildability on the old assume-buildable
  /// behavior.
  final bool selectedCellBuildable;
  final String? feedback;
  final bool isPaused;
  final bool bossActive;
  final double speedMultiplier;
  final bool autoStartEnabled;
  final double? autoStartCountdownRemaining;
  final RunModuleOffer? pendingRunModuleOffer;
  final List<RunModuleId> acquiredRunModules;

  /// Neutral read-only projection of every placed tower at snapshot time;
  /// not a live view of later session mutations.
  final List<PlacedTower> placedTowers;
  final TowerStats? selectedTowerStats;

  /// Resolved stats for [selectedTower]'s next battle tier — Level 2 for a
  /// tier-1 tower, or the fixed signature stats at tier 2→3. Non-null only
  /// while the tower can still upgrade.
  final TowerStats? selectedTowerUpgradeStats;

  /// Placed towers each offered Salvage Module would affect; non-empty only
  /// while a module draft is pending.
  final Map<RunModuleId, int> pendingRunModuleBeneficiaries;

  /// Squad members currently on the field — the dock greys these out since
  /// each character deploys at most once.
  Set<Character> get deployedCharacters => {
    for (final tower in placedTowers) tower.character,
  };

  bool get canStartWave =>
      phase == GamePhase.build && pendingRunModuleOffer == null;
  bool get isEnded => phase == GamePhase.won || phase == GamePhase.lost;
  bool get isEndless => missionWaveTotal == null;
}

final class RunModuleDefinition {
  const RunModuleDefinition({
    required this.id,
    required this.title,
    this.tower,
    this.damageMultiplier = 1,
    this.fireIntervalMultiplier = 1,
    this.rangeMultiplier = 1,
    this.splashRadiusMultiplier = 1,
    this.slowDurationBonus = 0,
    this.chainCountBonus = 0,
    this.pierceCountBonus = 0,
    this.fieldRadiusMultiplier = 1,
    this.immediateGold = 0,
  });

  final RunModuleId id;
  final String title;

  /// Tower family this module affects; null applies to every tower.
  final TowerType? tower;
  final double damageMultiplier;
  final double fireIntervalMultiplier;
  final double rangeMultiplier;
  final double splashRadiusMultiplier;
  final double slowDurationBonus;
  final int chainCountBonus;
  final int pierceCountBonus;
  final double fieldRadiusMultiplier;
  final int immediateGold;

  String get affinityLabel => tower?.label ?? 'Universal';

  /// Whether this module changes resolved tower stats (as opposed to a pure
  /// economy effect such as [immediateGold]).
  bool get affectsTowerStats =>
      damageMultiplier != 1 ||
      fireIntervalMultiplier != 1 ||
      rangeMultiplier != 1 ||
      splashRadiusMultiplier != 1 ||
      slowDurationBonus != 0 ||
      chainCountBonus != 0 ||
      pierceCountBonus != 0 ||
      fieldRadiusMultiplier != 1;

  String get effectText => switch (id) {
    RunModuleId.heavyCaliber =>
      'All member damage rises ${percent(damageMultiplier - 1)}; '
          'attack interval rises ${percent(fireIntervalMultiplier - 1)}.',
    RunModuleId.overclockRelay =>
      'Attack interval drops ${percent(1 - fireIntervalMultiplier)}; '
          'all member damage drops ${percent(1 - damageMultiplier)}.',
    RunModuleId.longSight =>
      'All members gain ${percent(rangeMultiplier - 1)} range.',
    RunModuleId.emergencySalvage => 'Gain $immediateGold gold immediately.',
    RunModuleId.cryoReservoir =>
      'Cryo slows last ${number(slowDurationBonus)} seconds longer.',
    RunModuleId.rocketFusing =>
      'Rocket splash grows ${percent(splashRadiusMultiplier - 1)}; '
          'damage drops ${percent(1 - damageMultiplier)}.',
    RunModuleId.relayCalibration =>
      'All members gain ${percent(rangeMultiplier - 1)} range; '
          'attack interval drops ${percent(1 - fireIntervalMultiplier)}.',
    RunModuleId.relayArc => 'Ion Chain arcs to $chainCountBonus more target.',
    RunModuleId.salvagedDrones =>
      'Drone attacks deal ${percent(damageMultiplier - 1)} more damage.',
    RunModuleId.foundryNanites =>
      'Nanite impact and corrosion damage rise '
          '${percent(damageMultiplier - 1)}.',
    RunModuleId.auroraFocus =>
      'Laser attack interval drops ${percent(1 - fireIntervalMultiplier)}.',
    RunModuleId.siegeRounds =>
      'Railgun shots pierce $pierceCountBonus more target.',
    RunModuleId.gravityEcho =>
      'Gravity Well field radius grows ${percent(fieldRadiusMultiplier - 1)}.',
  };
}

const runModuleCatalog = <RunModuleDefinition>[
  RunModuleDefinition(
    id: RunModuleId.heavyCaliber,
    title: 'Heavy Caliber',
    damageMultiplier: 1.20,
    fireIntervalMultiplier: 1.10,
  ),
  RunModuleDefinition(
    id: RunModuleId.overclockRelay,
    title: 'Overclock Relay',
    fireIntervalMultiplier: 0.85,
    damageMultiplier: 0.92,
  ),
  RunModuleDefinition(
    id: RunModuleId.longSight,
    title: 'Long Sight',
    rangeMultiplier: 1.15,
  ),
  RunModuleDefinition(
    id: RunModuleId.emergencySalvage,
    title: 'Emergency Salvage',
    immediateGold: 90,
  ),
  RunModuleDefinition(
    id: RunModuleId.cryoReservoir,
    title: 'Cryo Reservoir',
    tower: TowerType.cryo,
    slowDurationBonus: 0.60,
  ),
  RunModuleDefinition(
    id: RunModuleId.rocketFusing,
    title: 'Rocket Fusing',
    tower: TowerType.rocket,
    splashRadiusMultiplier: 1.25,
    damageMultiplier: 0.90,
  ),
  RunModuleDefinition(
    id: RunModuleId.relayCalibration,
    title: 'Relay Calibration',
    rangeMultiplier: 1.08,
    fireIntervalMultiplier: 0.92,
  ),
  RunModuleDefinition(
    id: RunModuleId.relayArc,
    title: 'Relay Arc',
    tower: TowerType.ionChain,
    chainCountBonus: 1,
  ),
  RunModuleDefinition(
    id: RunModuleId.salvagedDrones,
    title: 'Salvaged Drones',
    tower: TowerType.droneBay,
    damageMultiplier: 1.20,
  ),
  RunModuleDefinition(
    id: RunModuleId.foundryNanites,
    title: 'Foundry Nanites',
    tower: TowerType.nanite,
    damageMultiplier: 1.20,
  ),
  RunModuleDefinition(
    id: RunModuleId.auroraFocus,
    title: 'Aurora Focus',
    tower: TowerType.laser,
    fireIntervalMultiplier: 0.88,
  ),
  RunModuleDefinition(
    id: RunModuleId.siegeRounds,
    title: 'Siege Rounds',
    tower: TowerType.railgun,
    pierceCountBonus: 1,
  ),
  RunModuleDefinition(
    id: RunModuleId.gravityEcho,
    title: 'Gravity Echo',
    tower: TowerType.gravityWell,
    fieldRadiusMultiplier: 1.15,
  ),
];

RunModuleDefinition runModuleDefinition(RunModuleId id) =>
    runModuleCatalog.firstWhere((definition) => definition.id == id);

final class RunModuleOffer {
  RunModuleOffer({
    required this.offerId,
    required this.draftNumber,
    required this.draftTotal,
    required List<RunModuleId> moduleIds,
  }) : moduleIds = List.unmodifiable(moduleIds);

  final int offerId;
  final int draftNumber;
  final int draftTotal;
  final List<RunModuleId> moduleIds;
}

class GameBalance {
  static const int startingGold = 150;
  static const int initialBaseHealth = 20;
  // Wave indices (1-based, after completion) that open a salvage module draft.
  // The count of entries is the total number of drafts per run and drives the
  // `RunModuleOffer.draftTotal` shown in the draft panel header.
  static const List<int> moduleDraftWaves = [2, 4, 6];
  // Minimum base health (inclusive) to earn the silver stage medal on a win.
  static const int silverMedalThreshold = 10;
  // Fraction of invested gold refunded when a tower is sold, as a percent.
  static const int sellRefundPercent = 70;
  // Bonus starting gold granted by clearing the Salvage Rift side stage.
  static const int salvageRiftGoldBonus = 30;
  // Bonus starting base health granted by clearing the Void Bastion side stage.
  static const int voidBastionHealthBonus = 5;

  static const double shieldRechargeDelay = 3.0;
  static const double shieldRechargeRatePerSecond = 0.10;
  static const double swarmBountyMultiplier = 1.50;
  static const double reinforcedArmorBonus = 0.10;
  static const int regenPulseBurstSize = 3;
  static const double regenPulseInterval = 0.20;
  static const double regenPulseGap = 2.0;
  static const int reducedStartingHealthPenalty = 5;
  static const double enhancedClearBonusMultiplier = 1.50;
  static const double enemySpeedSurgeMultiplier = 1.15;
  static const double amplifiedGravityWellRadiusMultiplier = 1.20;
  static const double amplifiedGravityWellDurationMultiplier = 1.25;

  // Per-loop endless health/shield/regen multiplier on enemy stats.
  static const double endlessLoopHealthGrowth = 1.6;

  // Character rank → damage-channel multipliers (HPA-922). Initial shared
  // values; Task 4's headless balance pass may tune them.
  static const Map<CharacterRank, double> characterRankMultipliers = {
    CharacterRank.e: 1.0,
    CharacterRank.d: 1.2,
    CharacterRank.c: 1.4,
    CharacterRank.b: 1.6,
    CharacterRank.a: 1.8,
    CharacterRank.s: 2.0,
  };

  // Damage-channel growth per persistent character level above 1.
  static const double characterLevelGrowthPerLevel = 0.025;
  static const int characterMaxLevel = 40;

  // Maximum squad size (HPA-922): the saved roster validates against this
  // cap, and Task 6's squad picker enforces it in the UI.
  static const int squadMaxSize = 6;

  /// Fresh-profile starters (HPA-922): every new or discarded profile owns
  /// Haruto and Mio at level 1, with both selected for the squad. Single
  /// source of truth shared by `CampaignSave` and `GameSession`.
  static const Map<Character, int> starterOwnedLevels = {
    Character.haruto: 1,
    Character.mio: 1,
  };
  static const List<Character> starterSquad = [Character.haruto, Character.mio];

  /// Combined rank+level multiplier applied to a character's damage channels
  /// (via [TowerStats.scaleDamageChannels]) before stage modifiers and run
  /// modules: `rank * (1 + (level - 1) * growth)`. [level] is clamped to the
  /// 1–[characterMaxLevel] persistent band.
  static double characterScalingFactor(CharacterRank rank, int level) {
    final clampedLevel = level.clamp(1, characterMaxLevel);
    return characterRankMultipliers[rank]! *
        (1 + (clampedLevel - 1) * characterLevelGrowthPerLevel);
  }

  static const EnemyStats _basicDrone = EnemyStats(
    health: 36,
    speed: 74,
    baseDamage: 1,
    goldReward: 8,
  );
  static const EnemyStats _basicEliteDrone = EnemyStats(
    health: 90,
    speed: 86,
    baseDamage: 1,
    goldReward: 13,
  );
  static const EnemyStats _armoredDrone = EnemyStats(
    health: 70,
    speed: 66,
    baseDamage: 1,
    goldReward: 12,
    traits: {EnemyTrait.armored},
    armorReduction: 0.30,
  );
  static const EnemyStats _shieldedDrone = EnemyStats(
    health: 48,
    speed: 78,
    baseDamage: 1,
    goldReward: 12,
    traits: {EnemyTrait.shielded},
    shieldHealth: 35,
  );
  static const EnemyStats _swarmDrone = EnemyStats(
    health: 22,
    speed: 100,
    baseDamage: 1,
    goldReward: 5,
    traits: {EnemyTrait.swarm},
  );
  static const EnemyStats _regenDrone = EnemyStats(
    health: 78,
    speed: 72,
    baseDamage: 1,
    goldReward: 14,
    traits: {EnemyTrait.regen},
    regenPerSecond: 2.5,
  );
  static const EnemyStats _heavyDrone = EnemyStats(
    health: 150,
    speed: 58,
    baseDamage: 2,
    goldReward: 18,
    traits: {EnemyTrait.heavy},
  );
  static const EnemyStats _armoredHeavyDrone = EnemyStats(
    health: 175,
    speed: 54,
    baseDamage: 2,
    goldReward: 22,
    traits: {EnemyTrait.armored, EnemyTrait.heavy},
    armorReduction: 0.35,
  );
  static const EnemyStats _regenHeavyDrone = EnemyStats(
    health: 190,
    speed: 54,
    baseDamage: 3,
    goldReward: 25,
    traits: {EnemyTrait.regen, EnemyTrait.heavy},
    regenPerSecond: 3.0,
  );

  static const BossDefinition relayBreaker = BossDefinition(
    name: 'Relay Breaker',
    sprite: BossSprite.relayBreaker,
    health: 640,
    speed: 46,
    baseDamage: 4,
    goldReward: 120,
    traits: {EnemyTrait.armored, EnemyTrait.shielded, EnemyTrait.heavy},
    armorReduction: 0.40,
    shieldHealth: 100,
    summonMechanic: SummonMechanic(
      interval: 8.0,
      firstDelay: 4.0,
      count: 3,
      maxActive: 9,
      minionStats: _basicDrone,
    ),
  );
  static const BossDefinition shieldMatriarch = BossDefinition(
    name: 'Shield Matriarch',
    sprite: BossSprite.shieldMatriarch,
    health: 520,
    speed: 50,
    baseDamage: 4,
    goldReward: 120,
    traits: {EnemyTrait.shielded, EnemyTrait.heavy},
    shieldHealth: 200,
  );
  static const BossDefinition swarmQueen = BossDefinition(
    name: 'Swarm Queen',
    sprite: BossSprite.swarmQueen,
    health: 480,
    speed: 52,
    baseDamage: 3,
    goldReward: 110,
    traits: {EnemyTrait.swarm, EnemyTrait.regen},
    regenPerSecond: 4.0,
  );
  static const BossDefinition armoredExcavator = BossDefinition(
    name: 'Armored Excavator',
    sprite: BossSprite.armoredExcavator,
    health: 700,
    speed: 44,
    baseDamage: 4,
    goldReward: 130,
    traits: {EnemyTrait.armored, EnemyTrait.heavy},
    armorReduction: 0.45,
  );
  static const BossDefinition regenWarden = BossDefinition(
    name: 'Regen Warden',
    sprite: BossSprite.regenWarden,
    health: 560,
    speed: 48,
    baseDamage: 4,
    goldReward: 120,
    traits: {EnemyTrait.regen, EnemyTrait.heavy},
    regenPerSecond: 6.0,
  );
  static const BossDefinition siegeCarrier = BossDefinition(
    name: 'Siege Carrier',
    sprite: BossSprite.siegeCarrier,
    health: 800,
    speed: 42,
    baseDamage: 5,
    goldReward: 140,
    traits: {EnemyTrait.armored, EnemyTrait.heavy},
    armorReduction: 0.35,
  );
  static const BossDefinition singularityCore = BossDefinition(
    name: 'Singularity Core',
    sprite: BossSprite.singularityCore,
    health: 900,
    speed: 40,
    baseDamage: 5,
    goldReward: 150,
    traits: {
      EnemyTrait.armored,
      EnemyTrait.shielded,
      EnemyTrait.regen,
      EnemyTrait.heavy,
    },
    armorReduction: 0.40,
    shieldHealth: 150,
    regenPerSecond: 5.0,
  );

  static const List<WaveDefinition> waves = [
    WaveDefinition(
      groups: [
        WaveGroup(enemyCount: 8, enemyStats: _basicDrone, spawnInterval: 0.85),
      ],
      clearBonus: 30,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(enemyCount: 8, enemyStats: _basicDrone, spawnInterval: 0.85),
        WaveGroup(
          enemyCount: 2,
          enemyStats: _armoredDrone,
          spawnInterval: 1.00,
        ),
      ],
      clearBonus: 40,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(enemyCount: 10, enemyStats: _basicDrone, spawnInterval: 0.85),
        WaveGroup(
          enemyCount: 4,
          enemyStats: _shieldedDrone,
          spawnInterval: 0.90,
        ),
      ],
      clearBonus: 50,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(enemyCount: 8, enemyStats: _basicDrone, spawnInterval: 0.85),
        WaveGroup(
          enemyCount: 4,
          enemyStats: _armoredDrone,
          spawnInterval: 1.00,
        ),
        WaveGroup(
          enemyCount: 4,
          enemyStats: _shieldedDrone,
          spawnInterval: 0.90,
        ),
      ],
      clearBonus: 65,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(enemyCount: 20, enemyStats: _swarmDrone, spawnInterval: 0.35),
        WaveGroup(enemyCount: 4, enemyStats: _heavyDrone, spawnInterval: 1.20),
      ],
      clearBonus: 80,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(
          enemyCount: 10,
          enemyStats: _shieldedDrone,
          spawnInterval: 0.90,
        ),
        WaveGroup(enemyCount: 6, enemyStats: _regenDrone, spawnInterval: 1.00),
        WaveGroup(enemyCount: 6, enemyStats: _swarmDrone, spawnInterval: 0.35),
      ],
      clearBonus: 95,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(
          enemyCount: 8,
          enemyStats: _armoredHeavyDrone,
          spawnInterval: 1.25,
        ),
        WaveGroup(
          enemyCount: 8,
          enemyStats: _shieldedDrone,
          spawnInterval: 0.90,
        ),
        WaveGroup(enemyCount: 12, enemyStats: _swarmDrone, spawnInterval: 0.35),
      ],
      clearBonus: 115,
    ),
    WaveDefinition(
      groups: [
        WaveGroup(
          enemyCount: 8,
          enemyStats: _basicEliteDrone,
          spawnInterval: 0.75,
        ),
        WaveGroup(
          enemyCount: 8,
          enemyStats: _shieldedDrone,
          spawnInterval: 0.90,
        ),
        WaveGroup(
          enemyCount: 8,
          enemyStats: _armoredDrone,
          spawnInterval: 1.00,
        ),
        WaveGroup(enemyCount: 18, enemyStats: _swarmDrone, spawnInterval: 0.35),
        WaveGroup(
          enemyCount: 4,
          enemyStats: _regenHeavyDrone,
          spawnInterval: 1.30,
        ),
        WaveGroup(enemyCount: 1, enemyStats: relayBreaker, initialDelay: 2.5),
      ],
      clearBonus: 0,
    ),
  ];

  static List<TowerSpecialization> specializationsFor(TowerType type) {
    return switch (type) {
      TowerType.laser => const [
        TowerSpecialization.pulseLaser,
        TowerSpecialization.prismLaser,
      ],
      TowerType.rocket => const [
        TowerSpecialization.siegeRocket,
        TowerSpecialization.clusterRocket,
      ],
      TowerType.cryo => const [
        TowerSpecialization.deepFreeze,
        TowerSpecialization.frostbite,
      ],
      TowerType.railgun => const [
        TowerSpecialization.lanceRailgun,
        TowerSpecialization.magneticRailgun,
      ],
      TowerType.ionChain => const [
        TowerSpecialization.stormRelay,
        TowerSpecialization.overloadRelay,
      ],
      TowerType.nanite => const [
        TowerSpecialization.dissolverNanites,
        TowerSpecialization.replicatorNanites,
      ],
      TowerType.gravityWell => const [
        TowerSpecialization.singularityWell,
        TowerSpecialization.crushWell,
      ],
      TowerType.droneBay => const [
        TowerSpecialization.interceptorBay,
        TowerSpecialization.hunterBay,
      ],
    };
  }

  static EnemyStats enemyArchetype(EnemyArchetype archetype) {
    return switch (archetype) {
      EnemyArchetype.basicDrone => _basicDrone,
      EnemyArchetype.basicEliteDrone => _basicEliteDrone,
      EnemyArchetype.armoredDrone => _armoredDrone,
      EnemyArchetype.shieldedDrone => _shieldedDrone,
      EnemyArchetype.swarmDrone => _swarmDrone,
      EnemyArchetype.regenDrone => _regenDrone,
      EnemyArchetype.heavyDrone => _heavyDrone,
      EnemyArchetype.armoredHeavyDrone => _armoredHeavyDrone,
      EnemyArchetype.regenHeavyDrone => _regenHeavyDrone,
    };
  }

  static List<BossDefinition> get bosses => const [
    relayBreaker,
    shieldMatriarch,
    swarmQueen,
    armoredExcavator,
    regenWarden,
    siegeCarrier,
    singularityCore,
  ];

  static WavePreview wavePreview({
    required WaveDefinition wave,
    required int waveNumber,
    required int? missionWaveTotal,
    required List<TowerType> unlockedTowerTypes,
    required int effectiveClearBonus,
    double enemyHealthMultiplier = 1,
  }) {
    final groups = [
      for (final group in wave.groups)
        WavePreviewGroup(
          enemyCount: group.enemyCount,
          label: _enemyLabelForStats(group.enemyStats),
          traits: _orderedTraitsForStats(group.enemyStats),
        ),
    ];
    final traits = _orderedTraitsForWave(wave);

    return WavePreview(
      waveNumber: waveNumber,
      missionWaveTotal: missionWaveTotal,
      groups: groups,
      traits: traits,
      clearBonus: effectiveClearBonus,
      recommendedTowerTypes: _recommendedTowerTypes(wave, unlockedTowerTypes),
      enemyHealthMultiplier: enemyHealthMultiplier,
    );
  }

  static Set<EnemyTrait> _orderedTraitsForWave(WaveDefinition wave) {
    final traits = <EnemyTrait>{};
    for (final trait in EnemyTrait.values) {
      final isPresent = wave.groups.any(
        (group) => group.enemyStats.hasTrait(trait),
      );
      if (isPresent) {
        traits.add(trait);
      }
    }
    return traits;
  }

  static Set<EnemyTrait> _orderedTraitsForStats(EnemyStats stats) {
    final traits = <EnemyTrait>{};
    for (final trait in EnemyTrait.values) {
      if (stats.hasTrait(trait)) {
        traits.add(trait);
      }
    }
    return traits;
  }

  static String _enemyLabelForStats(EnemyStats stats) {
    if (stats is BossDefinition) return stats.name;
    if (identical(stats, _basicDrone)) {
      return EnemyArchetype.basicDrone.label;
    }
    if (identical(stats, _basicEliteDrone)) {
      return EnemyArchetype.basicEliteDrone.label;
    }
    if (identical(stats, _armoredDrone)) {
      return EnemyArchetype.armoredDrone.label;
    }
    if (identical(stats, _shieldedDrone)) {
      return EnemyArchetype.shieldedDrone.label;
    }
    if (identical(stats, _swarmDrone)) {
      return EnemyArchetype.swarmDrone.label;
    }
    if (identical(stats, _regenDrone)) {
      return EnemyArchetype.regenDrone.label;
    }
    if (identical(stats, _heavyDrone)) {
      return EnemyArchetype.heavyDrone.label;
    }
    if (identical(stats, _armoredHeavyDrone)) {
      return EnemyArchetype.armoredHeavyDrone.label;
    }
    if (identical(stats, _regenHeavyDrone)) {
      return EnemyArchetype.regenHeavyDrone.label;
    }

    final adjectives = [
      for (final trait in EnemyTrait.values)
        if (stats.hasTrait(trait)) _traitAdjective(trait),
    ];
    if (adjectives.isEmpty) {
      return 'Drones';
    }
    return '${adjectives.join(' ')} Drones';
  }

  static String _traitAdjective(EnemyTrait trait) {
    return trait.label;
  }

  static List<TowerType> _recommendedTowerTypes(
    WaveDefinition wave,
    List<TowerType> unlockedTowerTypes,
  ) {
    final recommendations = <TowerType>[];
    for (final group in wave.groups) {
      for (final trait in EnemyTrait.values) {
        if (!group.enemyStats.hasTrait(trait)) {
          continue;
        }
        for (final towerType in _counterTowersForTrait(trait)) {
          if (!unlockedTowerTypes.contains(towerType)) {
            continue;
          }
          if (recommendations.contains(towerType)) {
            continue;
          }
          recommendations.add(towerType);
          if (recommendations.length == 3) {
            return List.unmodifiable(recommendations);
          }
        }
      }
    }
    return List.unmodifiable(recommendations);
  }

  static List<TowerType> _counterTowersForTrait(EnemyTrait trait) {
    return switch (trait) {
      EnemyTrait.shielded => const [TowerType.ionChain],
      EnemyTrait.armored ||
      EnemyTrait.heavy => const [TowerType.rocket, TowerType.railgun],
      EnemyTrait.swarm => const [
        TowerType.rocket,
        TowerType.cryo,
        TowerType.gravityWell,
      ],
      EnemyTrait.regen => const [
        TowerType.laser,
        TowerType.ionChain,
        TowerType.nanite,
      ],
    };
  }

  static TowerStats towerStats(
    TowerType type, {
    required int level,
    TowerSpecialization? specialization,
  }) {
    if (level < 1 || level > 3) {
      throw ArgumentError.value(
        level,
        'level',
        'Tower level must be 1, 2, or 3',
      );
    }
    if (level < 3 && specialization != null) {
      throw ArgumentError.value(
        specialization,
        'specialization',
        'Only level 3 tower stats can specify a specialization',
      );
    }
    if (level == 3) {
      if (specialization == null) {
        throw ArgumentError.notNull('specialization');
      }
      if (specialization.type != type) {
        throw ArgumentError.value(
          specialization,
          'specialization',
          'Specialization must match tower type',
        );
      }
    }

    final costs = _towerCosts(type);
    return switch ((type, level, specialization)) {
      (TowerType.laser, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 145,
        damage: 12,
        fireInterval: 0.42,
        projectileSpeed: 420,
      ),
      (TowerType.laser, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 160,
        damage: 18,
        fireInterval: 0.34,
        projectileSpeed: 460,
      ),
      (TowerType.laser, 3, TowerSpecialization.pulseLaser) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 165,
        damage: 18,
        fireInterval: 0.24,
        projectileSpeed: 480,
      ),
      (TowerType.laser, 3, TowerSpecialization.prismLaser) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 170,
        damage: 20,
        fireInterval: 0.34,
        projectileSpeed: 470,
        prismSplitDamageMultiplier: 0.35,
        prismSplitRange: 55,
      ),
      (TowerType.rocket, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 165,
        damage: 26,
        fireInterval: 1.15,
        projectileSpeed: 300,
        splashRadius: 58,
      ),
      (TowerType.rocket, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 180,
        damage: 40,
        fireInterval: 1.00,
        projectileSpeed: 330,
        splashRadius: 72,
      ),
      (TowerType.rocket, 3, TowerSpecialization.siegeRocket) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 190,
        damage: 54,
        fireInterval: 1.05,
        projectileSpeed: 330,
        splashRadius: 96,
      ),
      (TowerType.rocket, 3, TowerSpecialization.clusterRocket) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 180,
        damage: 42,
        fireInterval: 1.00,
        projectileSpeed: 340,
        splashRadius: 72,
        clusterBurstCount: 2,
        clusterBurstDamageMultiplier: 0.45,
        clusterBurstRadius: 42,
      ),
      (TowerType.cryo, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 135,
        damage: 5,
        fireInterval: 0.85,
        projectileSpeed: 360,
        slowMultiplier: 0.62,
        slowDuration: 1.4,
      ),
      (TowerType.cryo, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 150,
        damage: 8,
        fireInterval: 0.72,
        projectileSpeed: 390,
        slowMultiplier: 0.48,
        slowDuration: 2.0,
      ),
      (TowerType.cryo, 3, TowerSpecialization.deepFreeze) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 160,
        damage: 8,
        fireInterval: 0.70,
        projectileSpeed: 400,
        slowMultiplier: 0.38,
        slowDuration: 2.8,
      ),
      (TowerType.cryo, 3, TowerSpecialization.frostbite) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 155,
        damage: 14,
        fireInterval: 0.68,
        projectileSpeed: 410,
        slowMultiplier: 0.50,
        slowDuration: 1.8,
        slowedDamageMultiplier: 1.6,
      ),
      (TowerType.railgun, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 210,
        damage: 42,
        fireInterval: 1.45,
        projectileSpeed: 620,
        pierceCount: 2,
        pierceWidth: 22,
      ),
      (TowerType.railgun, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 230,
        damage: 62,
        fireInterval: 1.30,
        projectileSpeed: 680,
        pierceCount: 3,
        pierceWidth: 24,
      ),
      (TowerType.railgun, 3, TowerSpecialization.lanceRailgun) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 255,
        damage: 70,
        fireInterval: 1.25,
        projectileSpeed: 720,
        pierceCount: 5,
        pierceWidth: 28,
      ),
      (TowerType.railgun, 3, TowerSpecialization.magneticRailgun) =>
        _towerStats(
          type: type,
          level: level,
          specialization: specialization,
          costs: costs,
          range: 235,
          damage: 68,
          fireInterval: 1.28,
          projectileSpeed: 700,
          pierceCount: 3,
          pierceWidth: 24,
          armorDamageMultiplier: 1.55,
        ),
      (TowerType.ionChain, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 150,
        damage: 16,
        fireInterval: 0.95,
        projectileSpeed: 500,
        chainCount: 3,
        chainRange: 85,
        chainFalloff: 0.72,
      ),
      (TowerType.ionChain, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 165,
        damage: 22,
        fireInterval: 0.82,
        projectileSpeed: 540,
        chainCount: 4,
        chainRange: 95,
        chainFalloff: 0.76,
      ),
      (TowerType.ionChain, 3, TowerSpecialization.stormRelay) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 175,
        damage: 24,
        fireInterval: 0.78,
        projectileSpeed: 560,
        chainCount: 6,
        chainRange: 110,
        chainFalloff: 0.78,
      ),
      (TowerType.ionChain, 3, TowerSpecialization.overloadRelay) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 168,
        damage: 24,
        fireInterval: 0.82,
        projectileSpeed: 550,
        chainCount: 4,
        chainRange: 100,
        chainFalloff: 0.76,
        shieldDamageMultiplier: 1.65,
      ),
      (TowerType.nanite, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 140,
        damage: 6,
        fireInterval: 0.90,
        projectileSpeed: 360,
        corrosionDamagePerSecond: 6,
        corrosionDuration: 2.5,
        armorShred: 0.12,
      ),
      (TowerType.nanite, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 155,
        damage: 8,
        fireInterval: 0.80,
        projectileSpeed: 390,
        corrosionDamagePerSecond: 9,
        corrosionDuration: 3.2,
        armorShred: 0.18,
      ),
      (TowerType.nanite, 3, TowerSpecialization.dissolverNanites) =>
        _towerStats(
          type: type,
          level: level,
          specialization: specialization,
          costs: costs,
          range: 165,
          damage: 9,
          fireInterval: 0.78,
          projectileSpeed: 400,
          corrosionDamagePerSecond: 11,
          corrosionDuration: 3.6,
          armorShred: 0.32,
        ),
      (TowerType.nanite, 3, TowerSpecialization.replicatorNanites) =>
        _towerStats(
          type: type,
          level: level,
          specialization: specialization,
          costs: costs,
          range: 160,
          damage: 8,
          fireInterval: 0.76,
          projectileSpeed: 410,
          corrosionDamagePerSecond: 10,
          corrosionDuration: 3.2,
          armorShred: 0.20,
        ),
      (TowerType.gravityWell, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 155,
        damage: 4,
        fireInterval: 1.25,
        projectileSpeed: 300,
        fieldRadius: 72,
        fieldDuration: 2.0,
        fieldTickInterval: 0.5,
      ),
      (TowerType.gravityWell, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 170,
        damage: 6,
        fireInterval: 1.12,
        projectileSpeed: 320,
        fieldRadius: 86,
        fieldDuration: 2.5,
        fieldTickInterval: 0.5,
      ),
      (TowerType.gravityWell, 3, TowerSpecialization.singularityWell) =>
        _towerStats(
          type: type,
          level: level,
          specialization: specialization,
          costs: costs,
          range: 185,
          damage: 6,
          fireInterval: 1.05,
          projectileSpeed: 330,
          slowMultiplier: 0.42,
          slowDuration: 0.7,
          fieldRadius: 104,
          fieldDuration: 3.1,
          fieldTickInterval: 0.45,
        ),
      (TowerType.gravityWell, 3, TowerSpecialization.crushWell) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 175,
        damage: 14,
        fireInterval: 1.10,
        projectileSpeed: 330,
        slowMultiplier: 0.55,
        slowDuration: 0.6,
        fieldRadius: 88,
        fieldDuration: 2.8,
        fieldTickInterval: 0.45,
      ),
      (TowerType.droneBay, 1, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 150,
        damage: 0,
        fireInterval: 2.50,
        projectileSpeed: 0,
        droneCount: 2,
        droneLifetime: 4.0,
        droneDamage: 8,
        droneAttackInterval: 0.65,
        maxActiveDrones: 4,
      ),
      (TowerType.droneBay, 2, null) => _towerStats(
        type: type,
        level: level,
        costs: costs,
        range: 165,
        damage: 0,
        fireInterval: 2.25,
        projectileSpeed: 0,
        droneCount: 3,
        droneLifetime: 4.5,
        droneDamage: 10,
        droneAttackInterval: 0.58,
        maxActiveDrones: 6,
      ),
      (TowerType.droneBay, 3, TowerSpecialization.interceptorBay) =>
        _towerStats(
          type: type,
          level: level,
          specialization: specialization,
          costs: costs,
          range: 175,
          damage: 0,
          fireInterval: 2.05,
          projectileSpeed: 0,
          droneCount: 4,
          droneLifetime: 4.0,
          droneDamage: 9,
          droneAttackInterval: 0.50,
          maxActiveDrones: 8,
        ),
      (TowerType.droneBay, 3, TowerSpecialization.hunterBay) => _towerStats(
        type: type,
        level: level,
        specialization: specialization,
        costs: costs,
        range: 175,
        damage: 0,
        fireInterval: 2.30,
        projectileSpeed: 0,
        droneCount: 2,
        droneLifetime: 5.4,
        droneDamage: 18,
        droneAttackInterval: 0.72,
        maxActiveDrones: 4,
      ),
      _ => throw StateError('Unsupported tower stats: $type level $level'),
    };
  }

  /// Gold refunded when selling [tower]: 70% of everything invested, truncated.
  static int refundValue(PlacedTower tower) {
    final base = towerStats(tower.type, level: 1);
    var invested = base.cost;
    if (tower.level >= 2) {
      invested += base.upgradeCost;
    }
    if (tower.level == 3) {
      invested += base.specializationCost;
    }
    return invested * sellRefundPercent ~/ 100;
  }

  static _TowerCosts _towerCosts(TowerType type) {
    return switch (type) {
      TowerType.laser => const _TowerCosts(
        cost: 50,
        upgradeCost: 70,
        specializationCost: 120,
      ),
      TowerType.rocket => const _TowerCosts(
        cost: 80,
        upgradeCost: 100,
        specializationCost: 150,
      ),
      TowerType.cryo => const _TowerCosts(
        cost: 70,
        upgradeCost: 90,
        specializationCost: 140,
      ),
      TowerType.railgun => const _TowerCosts(
        cost: 110,
        upgradeCost: 150,
        specializationCost: 210,
      ),
      TowerType.ionChain => const _TowerCosts(
        cost: 95,
        upgradeCost: 130,
        specializationCost: 190,
      ),
      TowerType.nanite => const _TowerCosts(
        cost: 90,
        upgradeCost: 125,
        specializationCost: 180,
      ),
      TowerType.gravityWell => const _TowerCosts(
        cost: 120,
        upgradeCost: 160,
        specializationCost: 220,
      ),
      TowerType.droneBay => const _TowerCosts(
        cost: 130,
        upgradeCost: 170,
        specializationCost: 240,
      ),
    };
  }

  static TowerStats _towerStats({
    required TowerType type,
    required int level,
    TowerSpecialization? specialization,
    required _TowerCosts costs,
    required double range,
    required double damage,
    required double fireInterval,
    required double projectileSpeed,
    double splashRadius = 0,
    double slowMultiplier = 1,
    double slowDuration = 0,
    int pierceCount = 0,
    double pierceWidth = 0,
    int chainCount = 0,
    double chainRange = 0,
    double chainFalloff = 1,
    double corrosionDamagePerSecond = 0,
    double corrosionDuration = 0,
    double armorShred = 0,
    double fieldRadius = 0,
    double fieldDuration = 0,
    double fieldTickInterval = 0,
    int droneCount = 0,
    double droneLifetime = 0,
    double droneDamage = 0,
    double droneAttackInterval = 0,
    int maxActiveDrones = 0,
    double shieldDamageMultiplier = 1,
    double armorDamageMultiplier = 1,
    double slowedDamageMultiplier = 1,
    double prismSplitDamageMultiplier = 0,
    double prismSplitRange = 0,
    int clusterBurstCount = 0,
    double clusterBurstDamageMultiplier = 0,
    double clusterBurstRadius = 0,
  }) {
    return TowerStats(
      type: type,
      level: level,
      specialization: specialization,
      cost: costs.cost,
      upgradeCost: costs.upgradeCost,
      specializationCost: costs.specializationCost,
      range: range,
      damage: damage,
      fireInterval: fireInterval,
      projectileSpeed: projectileSpeed,
      splashRadius: splashRadius,
      slowMultiplier: slowMultiplier,
      slowDuration: slowDuration,
      pierceCount: pierceCount,
      pierceWidth: pierceWidth,
      chainCount: chainCount,
      chainRange: chainRange,
      chainFalloff: chainFalloff,
      corrosionDamagePerSecond: corrosionDamagePerSecond,
      corrosionDuration: corrosionDuration,
      armorShred: armorShred,
      fieldRadius: fieldRadius,
      fieldDuration: fieldDuration,
      fieldTickInterval: fieldTickInterval,
      droneCount: droneCount,
      droneLifetime: droneLifetime,
      droneDamage: droneDamage,
      droneAttackInterval: droneAttackInterval,
      maxActiveDrones: maxActiveDrones,
      shieldDamageMultiplier: shieldDamageMultiplier,
      armorDamageMultiplier: armorDamageMultiplier,
      slowedDamageMultiplier: slowedDamageMultiplier,
      prismSplitDamageMultiplier: prismSplitDamageMultiplier,
      prismSplitRange: prismSplitRange,
      clusterBurstCount: clusterBurstCount,
      clusterBurstDamageMultiplier: clusterBurstDamageMultiplier,
      clusterBurstRadius: clusterBurstRadius,
    );
  }
}

class _TowerCosts {
  const _TowerCosts({
    required this.cost,
    required this.upgradeCost,
    required this.specializationCost,
  });

  final int cost;
  final int upgradeCost;
  final int specializationCost;
}
