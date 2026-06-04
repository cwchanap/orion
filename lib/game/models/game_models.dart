import 'dart:math' as math;

enum GamePhase { build, wave, won, lost }

enum TowerType {
  laser,
  rocket,
  cryo,
  railgun,
  ionChain,
  nanite,
  gravityWell,
  droneBay,
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
}

enum EnemyTrait { armored, shielded, swarm, regen, heavy }

enum EnemyArchetype {
  basicDrone,
  basicEliteDrone,
  armoredDrone,
  shieldedDrone,
  swarmDrone,
  regenDrone,
  heavyDrone,
  armoredHeavyDrone,
  regenHeavyDrone,
}

enum PlacementFailure {
  invalidPhase,
  offBoard,
  pathBlocked,
  occupied,
  insufficientGold,
  lockedTower,
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

  bool get canUpgrade => level == 1;
  bool get canSpecialize => level == 2;
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

class PlacedTower {
  const PlacedTower({
    required this.id,
    required this.type,
    required this.position,
    this.level = 1,
    this.specialization,
  });

  final int id;
  final TowerType type;
  final GridPosition position;
  final int level;
  final TowerSpecialization? specialization;

  bool get canUpgrade => level == 1;
  bool get canSpecialize => level == 2;
  bool get isMaxLevel => level >= 3;

  PlacedTower upgraded() {
    if (!canUpgrade) {
      throw StateError('Tower can only be upgraded from level 1');
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: 2,
      specialization: specialization,
    );
  }

  PlacedTower specialized(TowerSpecialization specialization) {
    if (!canSpecialize) {
      throw StateError('Tower can only be specialized from level 2');
    }
    if (specialization.type != type) {
      throw ArgumentError.value(
        specialization,
        'specialization',
        'Specialization must match tower type',
      );
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: 3,
      specialization: specialization,
    );
  }
}

class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.waveNumber,
    required this.selectedCell,
    required this.selectedTower,
    required this.feedback,
  });

  final GamePhase phase;
  final int gold;
  final int baseHealth;
  final int waveNumber;
  final GridPosition? selectedCell;
  final PlacedTower? selectedTower;
  final String? feedback;

  bool get canStartWave => phase == GamePhase.build;
  bool get isEnded => phase == GamePhase.won || phase == GamePhase.lost;
}

class GameBalance {
  static const int startingGold = 150;
  static const int initialBaseHealth = 20;

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
      ],
      clearBonus: 0,
    ),
  ];

  static int towerUnlockWave(TowerType type) {
    return switch (type) {
      TowerType.laser || TowerType.rocket || TowerType.cryo => 1,
      TowerType.railgun => 2,
      TowerType.ionChain => 3,
      TowerType.nanite => 4,
      TowerType.gravityWell => 5,
      TowerType.droneBay => 6,
    };
  }

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
