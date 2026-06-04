import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('EnemyComponent', () {
    test(
      'pathProgress includes full completed segments after waypoint crossing',
      () {
        final enemy = EnemyComponent(
          enemyId: 1,
          stats: const EnemyStats(
            health: 10,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)],
          onKilled: (_) {},
          onReachedBase: (_) {},
        );

        enemy.update(0.6);
        expect(enemy.pathProgress, closeTo(6, 0.001));

        enemy.update(0.6);
        expect(enemy.position.x, closeTo(10, 0.001));
        expect(enemy.position.y, closeTo(2, 0.001));
        expect(enemy.pathProgress, closeTo(12, 0.001));
      },
    );

    test('shield absorbs damage before health in runtime component', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 50,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          shieldHealth: 20,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(15);

      expect(enemy.health, 50);
      expect(enemy.shield, 5);
      expect(enemy.isAlive, isTrue);
    });

    test('regen restores health while corrosion pauses regen', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(30);
      enemy.update(1);
      expect(enemy.health, 80);

      enemy.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      enemy.update(1);

      expect(enemy.health, 75);
      expect(enemy.isCorroded, isTrue);
    });

    test('slow applies to movement through its expiry tick', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [Vector2(0, 0), Vector2(100, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applySlow(multiplier: 0.5, duration: 1);
      enemy.update(1);

      expect(enemy.position.x, closeTo(5, 0.001));
      expect(enemy.isSlowed, isFalse);
    });

    test('regen stays paused during corrosion expiry tick', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(30);
      enemy.applyCorrosion(damagePerSecond: 5, duration: 1, armorShred: 0.1);
      enemy.update(1);

      expect(enemy.health, 65);
      expect(enemy.isCorroded, isFalse);

      enemy.update(1);
      expect(enemy.health, 75);
    });

    test('armor reduces health damage and corrosion damage bypasses armor', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.armored},
          armorReduction: 0.50,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(20);
      expect(enemy.health, 90);

      enemy.applyCorrosion(damagePerSecond: 10, duration: 1, armorShred: 0.2);
      enemy.update(1);

      expect(enemy.health, 80);
    });
  });
}
