import 'dart:math' as math;
import 'dart:ui';

import '../models/game_models.dart';
import 'combat_effects.dart';

class EnemyLogic {
  EnemyLogic({
    required this.enemyId,
    required this.stats,
    required List<Offset> waypoints,
    double initialCompletedDistance = 0,
  }) : waypoints = List<Offset>.unmodifiable(waypoints),
       position = waypoints.first,
       health = stats.health,
       maxHealth = stats.health,
       shield = stats.shieldHealth,
       _completedDistance = initialCompletedDistance,
       assert(
         waypoints.length >= 2,
         'EnemyLogic requires at least two waypoints',
       );

  final int enemyId;
  final EnemyStats stats;
  final List<Offset> waypoints;

  Offset position;
  double health;
  final double maxHealth;
  double shield;

  // additional combat state (health/shield/maxHealth/isResolved come from Task 1)
  double armorShred = 0;
  double slowMultiplier = 1;
  double slowRemaining = 0;
  double corrosionDamagePerSecond = 0;
  double corrosionRemaining = 0;

  bool _isResolved = false;
  int _targetWaypointIndex = 1;
  double _completedDistance;
  double _segmentProgress = 0;

  bool get isResolved => _isResolved;
  int get targetWaypointIndex => _targetWaypointIndex;
  bool get isAlive => !_isResolved && health > 0;

  bool get isSlowed => slowRemaining > 0 && slowMultiplier < 1;
  bool get isCorroded => corrosionRemaining > 0;
  double get armorReduction =>
      (stats.armorReduction - armorShred).clamp(0, 0.75).toDouble();

  double get _currentSegmentLength {
    if (_targetWaypointIndex >= waypoints.length) return 0;
    return (waypoints[_targetWaypointIndex - 1] -
            waypoints[_targetWaypointIndex])
        .distance;
  }

  double get pathProgress =>
      _completedDistance + _currentSegmentLength * _segmentProgress;

  List<Offset> residualWaypointsFromHere() => [
    position,
    ...waypoints.sublist(_targetWaypointIndex),
  ];

  DamageOutcome applyDamage(
    double amount, {
    double shieldDamageMultiplier = 1,
    double armorDamageMultiplier = 1,
    double armorShred = 0,
    bool bypassArmor = false,
  }) {
    if (!isAlive || amount <= 0) return const DamageOutcome(died: false);
    final result = CombatEffects.resolveDamage(
      DamageInput(
        health: health,
        maxHealth: maxHealth,
        shield: shield,
        damage: amount,
        armorReduction: stats.armorReduction,
        armorShred: math.max(this.armorShred, armorShred),
        shieldDamageMultiplier: shieldDamageMultiplier,
        armorDamageMultiplier: armorDamageMultiplier,
        bypassArmor: bypassArmor,
      ),
    );
    health = result.health;
    shield = result.shield;
    if (health == 0) {
      _isResolved = true;
      return const DamageOutcome(died: true);
    }
    return const DamageOutcome(died: false);
  }

  void applySlow({required double multiplier, required double duration}) {
    if (!isAlive || multiplier >= 1 || multiplier <= 0 || duration <= 0) return;
    final result = CombatEffects.mergeSlow(
      currentMultiplier: slowMultiplier,
      currentRemaining: slowRemaining,
      incomingMultiplier: multiplier,
      incomingDuration: duration,
    );
    slowMultiplier = result.multiplier;
    slowRemaining = result.remaining;
  }

  void applyCorrosion({
    required double damagePerSecond,
    required double duration,
    required double armorShred,
  }) {
    if (!isAlive || damagePerSecond <= 0 || duration <= 0) return;
    corrosionDamagePerSecond = math.max(
      corrosionDamagePerSecond,
      damagePerSecond,
    );
    corrosionRemaining = math.max(corrosionRemaining, duration);
    this.armorShred = math.max(this.armorShred, armorShred);
  }

  EnemyTickResult tick(double dt) {
    // Task 1: movement only. Combat/summon filled in later tasks.
    final slowMultiplier = 1.0;
    _moveAlongPath(dt, slowMultiplier);
    return EnemyTickResult(
      reachedBase: _isResolved,
      diedByCorrosion: false,
      summonsDue: 0,
      overlayDirty: false,
    );
  }

  void _moveAlongPath(double dt, double slowMultiplier) {
    var distanceRemaining = stats.speed * slowMultiplier * dt;
    while (distanceRemaining > 0 && !_isResolved) {
      if (_targetWaypointIndex >= waypoints.length) {
        _isResolved = true;
        return;
      }
      final target = waypoints[_targetWaypointIndex];
      final toTarget = target - position;
      final distanceToTarget = toTarget.distance;
      final segmentLength = _currentSegmentLength;

      if (distanceToTarget <= distanceRemaining) {
        position = target;
        _completedDistance += segmentLength;
        _segmentProgress = 1;
        _targetWaypointIndex += 1;
        distanceRemaining -= distanceToTarget;
        if (_targetWaypointIndex >= waypoints.length) {
          _isResolved = true;
          return;
        }
        _segmentProgress = 0;
      } else {
        position =
            position +
            Offset(
              (toTarget.dx / distanceToTarget) * distanceRemaining,
              (toTarget.dy / distanceToTarget) * distanceRemaining,
            );
        _segmentProgress =
            1 -
            ((distanceToTarget - distanceRemaining) / _currentSegmentLength);
        distanceRemaining = 0;
      }
    }
  }
}

class EnemyTickResult {
  const EnemyTickResult({
    required this.reachedBase,
    required this.diedByCorrosion,
    required this.summonsDue,
    required this.overlayDirty,
  });
  final bool reachedBase;
  final bool diedByCorrosion;
  final int summonsDue;
  final bool overlayDirty;
}

class DamageOutcome {
  const DamageOutcome({required this.died});
  final bool died;
}
