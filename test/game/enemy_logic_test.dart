import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/enemy_logic.dart';
import 'package:orion/game/rules/stage_modifier_rules.dart';

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

    test(
      'tick on a lethally-damaged regen enemy stays resolved and does not reach base',
      () {
        // Reproduces the terminal-state invariant: applyDamage(lethal) sets
        // _isResolved, then a subsequent tick() must NOT regenerate health,
        // move, or reclassify the enemy as having reached the base.
        final logic = EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
            traits: {EnemyTrait.regen},
            regenPerSecond: 50,
          ),
          // Short path so an unguarded tick would overrun and report
          // reachedBase via the post-movement _isResolved branch.
          waypoints: const [Offset(0, 0), Offset(5, 0)],
        );
        final outcome = logic.applyDamage(100);
        expect(outcome.died, isTrue);
        expect(logic.isAlive, isFalse);
        expect(logic.isResolved, isTrue);

        final result = logic.tick(1);
        expect(
          result.reachedBase,
          isFalse,
          reason: 'killed enemy must not be reclassified as reach-base',
        );
        expect(result.diedByCorrosion, isFalse);
        expect(result.summonsDue, 0);
        // Health must not regen back above zero on a resolved enemy.
        expect(logic.health, 0);
        expect(logic.isAlive, isFalse);
        expect(logic.isResolved, isTrue);
      },
    );

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

    test('reinforced armor getter and damage input agree after shred', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 1,
          baseDamage: 1,
          goldReward: 1,
          armorReduction: 0.7,
          traits: {EnemyTrait.armored},
        ),
        modifierProfile: const EnemyModifierProfile(armorReductionBonus: 0.1),
        waypoints: const [Offset(0, 0), Offset(100, 0)],
      );

      expect(logic.armorReduction, 0.75);
      logic.applyCorrosion(damagePerSecond: 1, duration: 5, armorShred: 0.2);
      expect(logic.armorReduction, closeTo(0.6, 0.001));
      logic.applyDamage(100);
      expect(logic.health, closeTo(60, 0.001));
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

    test('speed surge composes with slow state', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 10,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        modifierProfile: const EnemyModifierProfile(speedMultiplier: 1.15),
        waypoints: const [Offset(0, 0), Offset(100, 0)],
      );
      logic.applySlow(multiplier: 0.5, duration: 2);
      logic.tick(1);
      expect(logic.position.dx, closeTo(5.75, 0.001));
    });

    test('shield recharge applies only after crossed delay portion', () {
      final logic = shieldLogic(maxShield: 200);
      logic.applyDamage(100);
      expect(logic.shield, 100);

      expect(logic.tick(2.5).overlayDirty, isFalse);
      final result = logic.tick(1);

      expect(logic.shield, closeTo(110, 0.001));
      expect(result.overlayDirty, isTrue);
    });

    test('successful direct damage restarts the recharge delay', () {
      final logic = shieldLogic(maxShield: 200);
      logic.applyDamage(50);
      logic.tick(2.9);
      logic.applyDamage(10);
      logic.tick(0.2);
      expect(logic.shield, 140);
    });

    test('corrosion damage cannot recharge shield in the same tick', () {
      final logic = shieldLogic(maxShield: 200);
      logic.applyDamage(100);
      logic.applyCorrosion(damagePerSecond: 10, duration: 5, armorShred: 0.1);
      logic.tick(4);
      expect(logic.shield, 60);
    });

    test('Shield Matriarch profile recharges 20 per second and clamps', () {
      final profile = StageModifierRules.enemyProfile(
        stats: GameBalance.shieldMatriarch,
        stageModifiers: const [StageModifier.shieldRecharge],
      );
      final logic = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.shieldMatriarch,
        modifierProfile: profile,
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      logic.applyDamage(100);
      logic.tick(4);
      expect(logic.shield, 120);
      logic.tick(10);
      expect(logic.shield, GameBalance.shieldMatriarch.shieldHealth);
    });

    test('full-shield and resolved enemies do not over-recharge', () {
      final full = shieldLogic(maxShield: 100);
      expect(full.tick(10).overlayDirty, isFalse);
      expect(full.shield, 100);

      final resolved = EnemyLogic(
        enemyId: 2,
        stats: const EnemyStats(
          health: 10,
          speed: 1,
          baseDamage: 1,
          goldReward: 1,
        ),
        modifierProfile: const EnemyModifierProfile(
          shieldRecharge: ShieldRechargePolicy(delay: 3, ratePerSecond: 0.10),
        ),
        waypoints: const [Offset(0, 0), Offset(100, 0)],
      );
      resolved.applyDamage(10);
      expect(resolved.tick(10).overlayDirty, isFalse);
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

  group('EnemyLogic summon', () {
    test('summonsDue fires after firstDelay then every interval', () {
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.relayBreaker, // firstDelay 4, interval 8, count 3
        waypoints: const [Offset(0, 0), Offset(10000, 0)],
      );
      expect(boss.tick(4.0).summonsDue, 1);
      expect(boss.tick(8.0).summonsDue, 1);
      expect(boss.tick(7.9).summonsDue, 0);
    });

    test('data-slot boss never summons', () {
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.shieldMatriarch, // no summonMechanic
        waypoints: const [Offset(0, 0), Offset(10000, 0)],
      );
      expect(boss.tick(100).summonsDue, 0);
    });

    test('summon loop is bounded when dt is unusually large', () {
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.relayBreaker,
        waypoints: const [Offset(0, 0), Offset(100000, 0)],
      );
      // Huge dt must not spin unboundedly; result is bounded and debt is shed.
      final due = boss.tick(1000).summonsDue;
      expect(due, lessThanOrEqualTo(16));
      expect(due, greaterThan(0));
    });

    test('reach-base frame produces no summons', () {
      // relayBreaker speed 46; path length 46*4 so it reaches base at t=4
      // (same frame firstDelay would fire).
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.relayBreaker,
        waypoints: const [Offset(0, 0), Offset(46 * 4, 0)],
      );
      final r = boss.tick(4.0);
      expect(r.reachedBase, isTrue);
      expect(r.summonsDue, 0);
    });
  });
}

EnemyLogic shieldLogic({required double maxShield}) {
  return EnemyLogic(
    enemyId: 1,
    stats: EnemyStats(
      health: 100,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
      shieldHealth: maxShield,
      traits: const {EnemyTrait.shielded},
    ),
    modifierProfile: const EnemyModifierProfile(
      shieldRecharge: ShieldRechargePolicy(delay: 3, ratePerSecond: 0.10),
    ),
    waypoints: const [Offset(0, 0), Offset(100, 0)],
  );
}

Matcher closeToOffset(Offset value) => predicate<Offset>(
  (o) => (o.dx - value.dx).abs() < 0.001 && (o.dy - value.dy).abs() < 0.001,
  'is close to $value',
);
