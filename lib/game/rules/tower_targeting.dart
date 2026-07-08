import '../models/game_models.dart';

class TargetPoint {
  const TargetPoint({required this.x, required this.y});

  final double x;
  final double y;
}

class TargetCandidate {
  const TargetCandidate({
    required this.id,
    required this.x,
    required this.y,
    required this.pathProgress,
    required this.isAlive,
    this.currentHealth = 0,
    this.currentShield = 0,
    this.isShielded = false,
    this.isArmored = false,
  });

  final int id;
  final double x;
  final double y;
  final double pathProgress;
  final bool isAlive;
  final double currentHealth;
  final double currentShield;
  final bool isShielded;
  final bool isArmored;

  double get effectiveHealth => currentHealth + currentShield;
}

class TowerTargeting {
  static TargetCandidate? selectTarget({
    required TargetPoint tower,
    required double range,
    required Iterable<TargetCandidate> candidates,
    TowerTargetingMode mode = TowerTargetingMode.first,
  }) {
    final rangeSquared = range * range;
    final inRange = <TargetCandidate>[];
    for (final candidate in candidates) {
      if (!candidate.isAlive) {
        continue;
      }
      if (_distanceSquaredTo(candidate, tower) > rangeSquared) {
        continue;
      }
      inRange.add(candidate);
    }
    if (inRange.isEmpty) {
      return null;
    }

    final pool = _modePool(inRange, mode);
    if (pool.isEmpty) {
      return null;
    }

    TargetCandidate? best;
    for (final candidate in pool) {
      if (best == null || _prefers(candidate, best, tower, mode)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Shrinks the in-range pool for trait modes. Returns the full pool for
  /// non-trait modes and when the trait subset is empty (graceful fallback).
  static List<TargetCandidate> _modePool(
    List<TargetCandidate> inRange,
    TowerTargetingMode mode,
  ) {
    switch (mode) {
      case TowerTargetingMode.shielded:
        final subset = inRange.where((c) => c.isShielded).toList();
        return subset.isEmpty ? inRange : subset;
      case TowerTargetingMode.armored:
        final subset = inRange.where((c) => c.isArmored).toList();
        return subset.isEmpty ? inRange : subset;
      default:
        return inRange;
    }
  }

  /// True when [a] should be selected over [b] under [mode]. Primary key first;
  /// falls through to the universal tie-break (pathProgress desc, then id asc).
  static bool _prefers(
    TargetCandidate a,
    TargetCandidate b,
    TargetPoint tower,
    TowerTargetingMode mode,
  ) {
    switch (mode) {
      case TowerTargetingMode.strongest:
        final byHealth = a.effectiveHealth.compareTo(b.effectiveHealth);
        if (byHealth != 0) {
          return byHealth > 0;
        }
        break;
      case TowerTargetingMode.weakest:
        final byHealth = a.effectiveHealth.compareTo(b.effectiveHealth);
        if (byHealth != 0) {
          return byHealth < 0;
        }
        break;
      case TowerTargetingMode.closest:
        final byDistance = _distanceSquaredTo(
          a,
          tower,
        ).compareTo(_distanceSquaredTo(b, tower));
        if (byDistance != 0) {
          return byDistance < 0;
        }
        break;
      case TowerTargetingMode.first:
      case TowerTargetingMode.shielded:
      case TowerTargetingMode.armored:
        // pathProgress IS the ranking key; resolved by the universal tie-break.
        break;
    }
    final byProgress = a.pathProgress.compareTo(b.pathProgress);
    if (byProgress != 0) {
      return byProgress > 0;
    }
    return a.id < b.id;
  }

  static double _distanceSquaredTo(
    TargetCandidate candidate,
    TargetPoint tower,
  ) {
    final dx = candidate.x - tower.x;
    final dy = candidate.y - tower.y;
    return (dx * dx) + (dy * dy);
  }
}
