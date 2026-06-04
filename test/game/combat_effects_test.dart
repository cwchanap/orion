import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/rules/combat_effects.dart';
import 'package:orion/game/rules/tower_targeting.dart';

void main() {
  group('CombatEffects.resolveDamage', () {
    test('shield absorbs damage before health', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(health: 100, maxHealth: 100, shield: 30, damage: 20),
      );

      expect(result.health, 100);
      expect(result.shield, 10);
      expect(result.healthDamage, 0);
      expect(result.shieldDamage, 20);
    });

    test('overflow shield damage reaches health through armor', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 10,
          damage: 30,
          armorReduction: 0.25,
        ),
      );

      expect(result.health, 85);
      expect(result.shield, 0);
      expect(result.healthDamage, 15);
      expect(result.shieldDamage, 10);
    });

    test('armor reduction clamps at 0.75 and armorShred reduces penalty', () {
      final clamped = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 0,
          damage: 40,
          armorReduction: 1.2,
          armorShred: 0.3,
        ),
      );
      final shredded = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 0,
          damage: 40,
          armorReduction: 0.5,
          armorShred: 0.2,
        ),
      );

      expect(clamped.healthDamage, 10);
      expect(clamped.health, 90);
      expect(shredded.healthDamage, 28);
      expect(shredded.health, 72);
    });

    test('bypass-armor damage applies full health damage', () {
      final result = CombatEffects.resolveDamage(
        const DamageInput(
          health: 100,
          maxHealth: 100,
          shield: 0,
          damage: 40,
          armorReduction: 0.75,
          bypassArmor: true,
        ),
      );

      expect(result.health, 60);
      expect(result.healthDamage, 40);
    });
  });

  group('CombatEffects.applyRegen', () {
    test('regen never exceeds max health and stops while corroded', () {
      expect(
        CombatEffects.applyRegen(
          health: 95,
          maxHealth: 100,
          regenPerSecond: 10,
          dt: 1,
          isCorroded: false,
        ),
        100,
      );

      expect(
        CombatEffects.applyRegen(
          health: 60,
          maxHealth: 100,
          regenPerSecond: 10,
          dt: 1,
          isCorroded: true,
        ),
        60,
      );
    });
  });

  group('CombatEffects.mergeSlow', () {
    test('slow stacking keeps strongest multiplier and longest duration', () {
      final result = CombatEffects.mergeSlow(
        currentMultiplier: 0.7,
        currentRemaining: 2,
        incomingMultiplier: 0.5,
        incomingDuration: 4,
      );

      expect(result.multiplier, 0.5);
      expect(result.remaining, 4);
    });

    test('slow multiplier clamps to 0.25 minimum', () {
      final result = CombatEffects.mergeSlow(
        currentMultiplier: 1,
        currentRemaining: 0,
        incomingMultiplier: 0.1,
        incomingDuration: 3,
      );

      expect(result.multiplier, 0.25);
      expect(result.remaining, 3);
    });
  });

  group('CombatEffects.selectChainTargets', () {
    test(
      'starts with first target and chains to nearest alive unrepeated targets',
      () {
        const firstTarget = TargetCandidate(
          id: 1,
          x: 0,
          y: 0,
          pathProgress: 0.7,
          isAlive: true,
        );
        const candidates = [
          firstTarget,
          TargetCandidate(id: 2, x: 10, y: 0, pathProgress: 0.4, isAlive: true),
          TargetCandidate(id: 3, x: 16, y: 0, pathProgress: 0.3, isAlive: true),
          TargetCandidate(id: 4, x: 8, y: 0, pathProgress: 0.2, isAlive: false),
          TargetCandidate(id: 5, x: 60, y: 0, pathProgress: 0.1, isAlive: true),
        ];

        final targets = CombatEffects.selectChainTargets(
          firstTarget: firstTarget,
          candidates: candidates,
          chainCount: 3,
          chainRange: 12,
        );

        expect(targets.map((target) => target.id), [1, 2, 3]);
        expect(targets.toSet(), hasLength(3));
      },
    );
  });

  group('CombatEffects.selectPierceTargets', () {
    test(
      'returns alive targets near tower-primary line ordered by projection',
      () {
        const tower = TargetPoint(x: 0, y: 0);
        const primaryTarget = TargetCandidate(
          id: 1,
          x: 10,
          y: 0,
          pathProgress: 0.8,
          isAlive: true,
        );
        const candidates = [
          TargetCandidate(id: 4, x: 18, y: 2, pathProgress: 0.5, isAlive: true),
          TargetCandidate(id: 2, x: 8, y: 1, pathProgress: 0.7, isAlive: true),
          primaryTarget,
          TargetCandidate(id: 3, x: 12, y: 0, pathProgress: 0.6, isAlive: true),
          TargetCandidate(id: 5, x: 11, y: 4, pathProgress: 0.4, isAlive: true),
          TargetCandidate(
            id: 6,
            x: 14,
            y: 1,
            pathProgress: 0.3,
            isAlive: false,
          ),
          TargetCandidate(id: 7, x: -4, y: 0, pathProgress: 0.2, isAlive: true),
        ];

        final targets = CombatEffects.selectPierceTargets(
          tower: tower,
          primaryTarget: primaryTarget,
          candidates: candidates,
          pierceCount: 3,
          pierceWidth: 2,
        );

        expect(targets.map((target) => target.id), [2, 1, 3]);
      },
    );
  });

  group('CombatEffects.allowedDroneLaunches', () {
    test('drone launch cap returns remaining capacity', () {
      expect(
        CombatEffects.allowedDroneLaunches(
          requested: 4,
          active: 2,
          maxActive: 5,
        ),
        3,
      );
      expect(
        CombatEffects.allowedDroneLaunches(
          requested: 2,
          active: 5,
          maxActive: 5,
        ),
        0,
      );
    });
  });
}
