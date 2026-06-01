import 'dart:math' as math;

enum GamePhase { build, wave, won, lost }

enum TowerType { laser, rocket, cryo }

enum PlacementFailure { offBoard, pathBlocked, occupied, insufficientGold }

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
    required this.cost,
    required this.upgradeCost,
    required this.range,
    required this.damage,
    required this.fireInterval,
    required this.projectileSpeed,
    required this.splashRadius,
    required this.slowMultiplier,
    required this.slowDuration,
  });

  final TowerType type;
  final int level;
  final int cost;
  final int upgradeCost;
  final double range;
  final double damage;
  final double fireInterval;
  final double projectileSpeed;
  final double splashRadius;
  final double slowMultiplier;
  final double slowDuration;

  bool get canUpgrade => level == 1;
}

class EnemyStats {
  const EnemyStats({
    required this.health,
    required this.speed,
    required this.baseDamage,
    required this.goldReward,
  });

  final double health;
  final double speed;
  final int baseDamage;
  final int goldReward;
}

class WaveDefinition {
  const WaveDefinition({
    required this.enemyCount,
    required this.enemyStats,
    this.spawnInterval = 0.9,
  });

  final int enemyCount;
  final EnemyStats enemyStats;
  final double spawnInterval;
}

class PlacedTower {
  const PlacedTower({
    required this.id,
    required this.type,
    required this.position,
    this.level = 1,
  });

  final int id;
  final TowerType type;
  final GridPosition position;
  final int level;

  PlacedTower upgraded() {
    if (level >= 2) {
      throw StateError('Tower is already upgraded');
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: level + 1,
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
  static const int startingGold = 120;
  static const int initialBaseHealth = 20;

  static const List<WaveDefinition> waves = [
    WaveDefinition(
      enemyCount: 8,
      enemyStats: EnemyStats(
        health: 30,
        speed: 72,
        baseDamage: 1,
        goldReward: 8,
      ),
    ),
    WaveDefinition(
      enemyCount: 10,
      enemyStats: EnemyStats(
        health: 42,
        speed: 76,
        baseDamage: 1,
        goldReward: 9,
      ),
    ),
    WaveDefinition(
      enemyCount: 12,
      enemyStats: EnemyStats(
        health: 58,
        speed: 80,
        baseDamage: 1,
        goldReward: 10,
      ),
    ),
    WaveDefinition(
      enemyCount: 14,
      enemyStats: EnemyStats(
        health: 76,
        speed: 84,
        baseDamage: 2,
        goldReward: 11,
      ),
    ),
    WaveDefinition(
      enemyCount: 16,
      enemyStats: EnemyStats(
        health: 100,
        speed: 88,
        baseDamage: 2,
        goldReward: 12,
      ),
    ),
  ];

  static TowerStats towerStats(TowerType type, {required int level}) {
    if (level != 1 && level != 2) {
      throw ArgumentError.value(level, 'level', 'Tower level must be 1 or 2');
    }

    return switch ((type, level)) {
      (TowerType.laser, 1) => const TowerStats(
        type: TowerType.laser,
        level: 1,
        cost: 50,
        upgradeCost: 70,
        range: 145,
        damage: 12,
        fireInterval: 0.42,
        projectileSpeed: 420,
        splashRadius: 0,
        slowMultiplier: 1,
        slowDuration: 0,
      ),
      (TowerType.laser, 2) => const TowerStats(
        type: TowerType.laser,
        level: 2,
        cost: 50,
        upgradeCost: 70,
        range: 160,
        damage: 18,
        fireInterval: 0.34,
        projectileSpeed: 460,
        splashRadius: 0,
        slowMultiplier: 1,
        slowDuration: 0,
      ),
      (TowerType.rocket, 1) => const TowerStats(
        type: TowerType.rocket,
        level: 1,
        cost: 80,
        upgradeCost: 100,
        range: 165,
        damage: 26,
        fireInterval: 1.15,
        projectileSpeed: 300,
        splashRadius: 58,
        slowMultiplier: 1,
        slowDuration: 0,
      ),
      (TowerType.rocket, 2) => const TowerStats(
        type: TowerType.rocket,
        level: 2,
        cost: 80,
        upgradeCost: 100,
        range: 180,
        damage: 40,
        fireInterval: 1.0,
        projectileSpeed: 330,
        splashRadius: 72,
        slowMultiplier: 1,
        slowDuration: 0,
      ),
      (TowerType.cryo, 1) => const TowerStats(
        type: TowerType.cryo,
        level: 1,
        cost: 70,
        upgradeCost: 90,
        range: 135,
        damage: 5,
        fireInterval: 0.85,
        projectileSpeed: 360,
        splashRadius: 0,
        slowMultiplier: 0.62,
        slowDuration: 1.4,
      ),
      (TowerType.cryo, 2) => const TowerStats(
        type: TowerType.cryo,
        level: 2,
        cost: 70,
        upgradeCost: 90,
        range: 150,
        damage: 8,
        fireInterval: 0.72,
        projectileSpeed: 390,
        splashRadius: 0,
        slowMultiplier: 0.48,
        slowDuration: 2.0,
      ),
      _ => throw StateError('Unsupported tower stats: $type level $level'),
    };
  }
}
