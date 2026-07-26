import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/enemy_logic.dart';

void main() {
  group('EnemyLogic movement', () {
    test(
      'pathProgress includes full completed segments after waypoint crossing',
      () {
        final logic = EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 10,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: [
            const Offset(0, 0),
            const Offset(10, 0),
            const Offset(10, 10),
          ],
        );
        logic.tick(0.6);
        expect(logic.pathProgress, closeTo(6, 0.001));
        logic.tick(0.6);
        expect(logic.position.dx, closeTo(10, 0.001));
        expect(logic.position.dy, closeTo(2, 0.001));
        expect(logic.pathProgress, closeTo(12, 0.001));
      },
    );

    test('reaches base and reports reachedBase when path is exhausted', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 10,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [const Offset(0, 0), const Offset(5, 0)],
      );
      final result = logic.tick(1); // speed 10 * dt 1 = 10 > segment length 5
      expect(result.reachedBase, isTrue);
      expect(logic.isResolved, isTrue);
      expect(logic.position, const Offset(5, 0)); // snapped to waypoints.last
    });

    test('residualWaypointsFromHere starts at current position', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 10,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(10, 10),
        ],
      );
      logic.tick(0.3); // moves 3 units along x
      final residual = logic.residualWaypointsFromHere();
      expect(residual.first, closeToOffset(const Offset(3, 0)));
      expect(residual, hasLength(3)); // current pos + 2 remaining waypoints
    });
  });

  group('EnemyLogic combat', () {
    EnemyLogic make({
      double health = 100,
      double shield = 0,
      double armorReduction = 0,
    }) => EnemyLogic(
      enemyId: 1,
      stats: EnemyStats(
        health: health,
        speed: 10,
        baseDamage: 1,
        goldReward: 1,
        shieldHealth: shield,
        armorReduction: armorReduction,
      ),
      waypoints: const [Offset(0, 0), Offset(1000, 0)],
    );

    test('shield absorbs damage before health', () {
      final logic = make(health: 50, shield: 20);
      final outcome = logic.applyDamage(15);
      expect(logic.health, 50);
      expect(logic.shield, 5);
      expect(outcome.died, isFalse);
      expect(logic.isAlive, isTrue);
    });

    test('lethal damage marks resolved and reports died', () {
      final logic = make(health: 10);
      final outcome = logic.applyDamage(10);
      expect(logic.health, 0);
      expect(outcome.died, isTrue);
      expect(logic.isResolved, isTrue);
      expect(logic.isAlive, isFalse);
    });

    test('applySlow merges and exposes isSlowed', () {
      final logic = make();
      logic.applySlow(multiplier: 0.5, duration: 1);
      expect(logic.isSlowed, isTrue);
      expect(logic.slowMultiplier, closeTo(0.5, 0.001));
    });

    test('applyCorrosion stacks dps/duration/shred and exposes isCorroded', () {
      final logic = make();
      logic.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      expect(logic.isCorroded, isTrue);
      expect(logic.corrosionDamagePerSecond, 5);
      expect(logic.armorShred, closeTo(0.1, 0.001));
    });

    test('armorReduction clamps after shred', () {
      final logic = make(armorReduction: 0.4);
      logic.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      expect(logic.armorReduction, closeTo(0.3, 0.001));
    });
  });

  group('EnemyLogic tick status', () {
    test('regen restores health while corrosion pauses regen', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      logic.applyDamage(30);
      logic.tick(1);
      expect(logic.health, 80);
      logic.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      final r = logic.tick(1);
      expect(logic.health, 75); // corrosion dmg 5, no regen
      expect(logic.isCorroded, isTrue);
      expect(r.overlayDirty, isTrue);
    });

    test('regen stays paused during corrosion expiry tick', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      logic.applyDamage(50);
      logic.applyCorrosion(damagePerSecond: 5, duration: 1, armorShred: 0.1);
      logic.tick(1); // corrosion expires this tick, regen still paused
      expect(logic.isCorroded, isFalse);
      expect(logic.health, closeTo(45, 0.001)); // 50 - 5 corrosion, no regen
    });

    test('slow movement and expiry', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: const [Offset(0, 0), Offset(100, 0)],
      );
      logic.applySlow(multiplier: 0.5, duration: 1);
      logic.tick(1); // moves 5 units
      expect(logic.position.dx, closeTo(5, 0.001));
      expect(logic.isSlowed, isFalse);
    });

    test(
      'overlayDirty is false when only position changes (no status/health)',
      () {
        final logic = EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        );
        final r = logic.tick(1); // pure movement, no status
        expect(r.overlayDirty, isFalse);
      },
    );
  });
}

Matcher closeToOffset(Offset value) => predicate<Offset>(
  (o) => (o.dx - value.dx).abs() < 0.001 && (o.dy - value.dy).abs() < 0.001,
  'is close to $value',
);
