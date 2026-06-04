import 'dart:math' as math;

import 'tower_targeting.dart';

class DamageInput {
  const DamageInput({
    required this.health,
    required this.maxHealth,
    required this.shield,
    required this.damage,
    this.armorReduction = 0,
    this.armorShred = 0,
    this.shieldDamageMultiplier = 1,
    this.armorDamageMultiplier = 1,
    this.bypassArmor = false,
  });

  final double health;
  final double maxHealth;
  final double shield;
  final double damage;
  final double armorReduction;
  final double armorShred;
  final double shieldDamageMultiplier;
  final double armorDamageMultiplier;
  final bool bypassArmor;
}

class DamageResult {
  const DamageResult({
    required this.health,
    required this.shield,
    required this.healthDamage,
    required this.shieldDamage,
  });

  final double health;
  final double shield;
  final double healthDamage;
  final double shieldDamage;
}

class SlowMergeResult {
  const SlowMergeResult({required this.multiplier, required this.remaining});

  final double multiplier;
  final double remaining;
}

class CombatEffects {
  const CombatEffects._();

  static DamageResult resolveDamage(DamageInput input) {
    final maxHealth = math.max(0, input.maxHealth).toDouble();
    final startingHealth = input.health.clamp(0, maxHealth).toDouble();
    final startingShield = math.max(0, input.shield).toDouble();
    var remainingDamage = math.max(0, input.damage);
    var shieldDamage = 0.0;

    if (startingShield > 0 && remainingDamage > 0) {
      final shieldMultiplier = input.shieldDamageMultiplier > 0
          ? input.shieldDamageMultiplier
          : 1.0;
      final effectiveShieldDamage = math
          .min(startingShield, remainingDamage * shieldMultiplier)
          .toDouble();
      shieldDamage = effectiveShieldDamage;
      remainingDamage -= effectiveShieldDamage / shieldMultiplier;
    }

    final effectiveArmor = input.bypassArmor
        ? 0.0
        : (input.armorReduction - input.armorShred).clamp(0, 0.75).toDouble();
    final armorMultiplier = effectiveArmor > 0
        ? math.max(0, input.armorDamageMultiplier)
        : 1.0;
    final potentialHealthDamage =
        remainingDamage * (1 - effectiveArmor) * armorMultiplier;
    final healthDamage = math.min(startingHealth, potentialHealthDamage);
    final health = (startingHealth - healthDamage)
        .clamp(0, maxHealth)
        .toDouble();
    final shield = math.max(0, startingShield - shieldDamage).toDouble();

    return DamageResult(
      health: health,
      shield: shield,
      healthDamage: healthDamage,
      shieldDamage: shieldDamage,
    );
  }

  static double applyRegen({
    required double health,
    required double maxHealth,
    required double regenPerSecond,
    required double dt,
    required bool isCorroded,
  }) {
    if (isCorroded || regenPerSecond <= 0 || dt <= 0) {
      return health;
    }

    return math.min(maxHealth, health + (regenPerSecond * dt));
  }

  static SlowMergeResult mergeSlow({
    required double currentMultiplier,
    required double currentRemaining,
    required double incomingMultiplier,
    required double incomingDuration,
  }) {
    if (incomingMultiplier <= 0 || incomingDuration <= 0) {
      return SlowMergeResult(
        multiplier: currentMultiplier,
        remaining: currentRemaining,
      );
    }

    final clampedIncoming = incomingMultiplier.clamp(0.25, 1).toDouble();
    final currentActive = currentRemaining > 0;
    final activeCurrentMultiplier = currentActive ? currentMultiplier : 1.0;

    return SlowMergeResult(
      multiplier: math.min(activeCurrentMultiplier, clampedIncoming),
      remaining: math.max(math.max(0, currentRemaining), incomingDuration),
    );
  }

  static List<TargetCandidate> selectChainTargets({
    required TargetCandidate firstTarget,
    required Iterable<TargetCandidate> candidates,
    required int chainCount,
    required double chainRange,
  }) {
    if (chainCount <= 0 || chainRange < 0 || !firstTarget.isAlive) {
      return const [];
    }

    final selected = <TargetCandidate>[firstTarget];
    final selectedIds = <int>{firstTarget.id};
    var current = firstTarget;

    while (selected.length < chainCount) {
      TargetCandidate? nearest;
      var nearestDistanceSquared = double.infinity;
      final rangeSquared = chainRange * chainRange;

      for (final candidate in candidates) {
        if (!candidate.isAlive || selectedIds.contains(candidate.id)) {
          continue;
        }

        final distanceSquared = _distanceSquared(current, candidate);
        if (distanceSquared > rangeSquared) {
          continue;
        }

        if (distanceSquared < nearestDistanceSquared) {
          nearest = candidate;
          nearestDistanceSquared = distanceSquared;
        }
      }

      if (nearest == null) {
        break;
      }

      selected.add(nearest);
      selectedIds.add(nearest.id);
      current = nearest;
    }

    return selected;
  }

  static List<TargetCandidate> selectPierceTargets({
    required TargetPoint tower,
    required TargetCandidate primaryTarget,
    required Iterable<TargetCandidate> candidates,
    required int pierceCount,
    required double pierceWidth,
  }) {
    if (pierceCount <= 0 || pierceWidth < 0 || !primaryTarget.isAlive) {
      return const [];
    }

    final directionX = primaryTarget.x - tower.x;
    final directionY = primaryTarget.y - tower.y;
    final lineLengthSquared =
        (directionX * directionX) + (directionY * directionY);
    if (lineLengthSquared <= 0) {
      return const [];
    }

    final lineLength = math.sqrt(lineLengthSquared);
    final hits = <_PierceHit>[];

    for (final candidate in candidates) {
      if (!candidate.isAlive) {
        continue;
      }

      final offsetX = candidate.x - tower.x;
      final offsetY = candidate.y - tower.y;
      final projection =
          ((offsetX * directionX) + (offsetY * directionY)) / lineLength;
      if (projection < 0) {
        continue;
      }

      final cross = (offsetX * directionY) - (offsetY * directionX);
      final distanceToLine = cross.abs() / lineLength;
      if (distanceToLine > pierceWidth) {
        continue;
      }

      hits.add(_PierceHit(candidate: candidate, projection: projection));
    }

    hits.sort((a, b) => a.projection.compareTo(b.projection));

    return [for (final hit in hits.take(pierceCount)) hit.candidate];
  }

  static int allowedDroneLaunches({
    required int requested,
    required int active,
    required int maxActive,
  }) {
    if (requested <= 0 || maxActive <= 0 || active >= maxActive) {
      return 0;
    }

    return math.min(requested, maxActive - math.max(0, active));
  }

  static double damageForChainJump({
    required double baseDamage,
    required double chainFalloff,
    required int jumpIndex,
  }) {
    if (jumpIndex <= 0) {
      return baseDamage;
    }

    return (baseDamage * math.pow(chainFalloff, jumpIndex)).toDouble();
  }

  static double damageAgainstSlowState({
    required double baseDamage,
    required double slowedDamageMultiplier,
    required bool isSlowed,
  }) {
    return isSlowed ? baseDamage * slowedDamageMultiplier : baseDamage;
  }

  static double _distanceSquared(TargetCandidate from, TargetCandidate to) {
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    return (dx * dx) + (dy * dy);
  }
}

class _PierceHit {
  const _PierceHit({required this.candidate, required this.projection});

  final TargetCandidate candidate;
  final double projection;
}
