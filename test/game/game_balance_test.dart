import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameBalance', () {
    test('matches the approved starting economy and base health', () {
      expect(GameBalance.startingGold, 120);
      expect(GameBalance.initialBaseHealth, 20);
    });

    test('defines the approved wave balance table', () {
      const expectedWaves = [
        _ExpectedWave(
          enemyCount: 8,
          health: 30,
          speed: 72,
          baseDamage: 1,
          goldReward: 8,
          spawnInterval: 0.9,
        ),
        _ExpectedWave(
          enemyCount: 10,
          health: 42,
          speed: 76,
          baseDamage: 1,
          goldReward: 9,
          spawnInterval: 0.9,
        ),
        _ExpectedWave(
          enemyCount: 12,
          health: 58,
          speed: 80,
          baseDamage: 1,
          goldReward: 10,
          spawnInterval: 0.9,
        ),
        _ExpectedWave(
          enemyCount: 14,
          health: 76,
          speed: 84,
          baseDamage: 2,
          goldReward: 11,
          spawnInterval: 0.9,
        ),
        _ExpectedWave(
          enemyCount: 16,
          health: 100,
          speed: 88,
          baseDamage: 2,
          goldReward: 12,
          spawnInterval: 0.9,
        ),
      ];

      expect(GameBalance.waves, hasLength(expectedWaves.length));
      for (final (index, expected) in expectedWaves.indexed) {
        final wave = GameBalance.waves[index];

        expect(wave.enemyCount, expected.enemyCount);
        expect(wave.enemyStats.health, expected.health);
        expect(wave.enemyStats.speed, expected.speed);
        expect(wave.enemyStats.baseDamage, expected.baseDamage);
        expect(wave.enemyStats.goldReward, expected.goldReward);
        expect(wave.spawnInterval, expected.spawnInterval);
      }
    });

    test('defines the approved tower balance table', () {
      const expectedTowerStats = [
        _ExpectedTowerStats(
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
          canUpgrade: true,
        ),
        _ExpectedTowerStats(
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
          canUpgrade: false,
        ),
        _ExpectedTowerStats(
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
          canUpgrade: true,
        ),
        _ExpectedTowerStats(
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
          canUpgrade: false,
        ),
        _ExpectedTowerStats(
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
          canUpgrade: true,
        ),
        _ExpectedTowerStats(
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
          canUpgrade: false,
        ),
      ];

      for (final expected in expectedTowerStats) {
        final stats = GameBalance.towerStats(
          expected.type,
          level: expected.level,
        );

        expect(stats.type, expected.type);
        expect(stats.level, expected.level);
        expect(stats.cost, expected.cost);
        expect(stats.upgradeCost, expected.upgradeCost);
        expect(stats.range, expected.range);
        expect(stats.damage, expected.damage);
        expect(stats.fireInterval, expected.fireInterval);
        expect(stats.projectileSpeed, expected.projectileSpeed);
        expect(stats.splashRadius, expected.splashRadius);
        expect(stats.slowMultiplier, expected.slowMultiplier);
        expect(stats.slowDuration, expected.slowDuration);
        expect(stats.canUpgrade, expected.canUpgrade);
      }
    });

    test('rejects unsupported tower levels', () {
      expect(
        () => GameBalance.towerStats(TowerType.laser, level: 0),
        throwsArgumentError,
      );
      expect(
        () => GameBalance.towerStats(TowerType.laser, level: 3),
        throwsArgumentError,
      );
    });
  });
}

class _ExpectedWave {
  const _ExpectedWave({
    required this.enemyCount,
    required this.health,
    required this.speed,
    required this.baseDamage,
    required this.goldReward,
    required this.spawnInterval,
  });

  final int enemyCount;
  final double health;
  final double speed;
  final int baseDamage;
  final int goldReward;
  final double spawnInterval;
}

class _ExpectedTowerStats {
  const _ExpectedTowerStats({
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
    required this.canUpgrade,
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
  final bool canUpgrade;
}
