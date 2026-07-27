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
       _summonRemaining = _initialSummonDelay(stats),
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
  double _summonRemaining;

  static double _initialSummonDelay(EnemyStats stats) {
    if (stats is BossDefinition) {
      final mechanic = stats.summonMechanic;
      if (mechanic != null) return mechanic.firstDelay;
    }
    return 0;
  }

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
    // Terminal-state invariant: a resolved enemy (killed or reached base) must
    // not be reclassified by a later tick. Without this guard, regen could
    // push health back above zero on a lethally-damaged regen enemy, the
    // movement loop would skip (_isResolved stays true), and the post-movement
    // `if (_isResolved) return reachedBase: true` would misclassify the kill as
    // a base-reach. Return a neutral no-op so the original resolution stands.
    if (!isAlive) {
      return const EnemyTickResult(
        reachedBase: false,
        diedByCorrosion: false,
        summonsDue: 0,
        overlayDirty: false,
      );
    }
    var overlayDirty = false;
    final movementSlowMultiplier = isSlowed ? slowMultiplier : 1.0;
    final wasCorrodedAtTickStart = isCorroded;

    // 1. Corrosion + regen
    if (corrosionRemaining > 0) {
      final tick = math.min(math.max(0, dt), corrosionRemaining);
      corrosionRemaining = math.max(0, corrosionRemaining - tick);
      final healthBeforeCorrosion = health;
      final shieldBeforeCorrosion = shield;
      final dmg = applyDamage(
        corrosionDamagePerSecond * tick,
        bypassArmor: true,
      );
      if (health != healthBeforeCorrosion || shield != shieldBeforeCorrosion) {
        overlayDirty = true;
      }
      if (corrosionRemaining == 0) {
        corrosionDamagePerSecond = 0;
        armorShred = 0;
        overlayDirty = true;
      }
      if (dmg.died) {
        return EnemyTickResult(
          reachedBase: false,
          diedByCorrosion: true,
          summonsDue: 0,
          overlayDirty: true,
        );
      }
    }
    final previousHealth = health;
    health = CombatEffects.applyRegen(
      health: health,
      maxHealth: maxHealth,
      regenPerSecond: stats.regenPerSecond,
      dt: dt,
      isCorroded: wasCorrodedAtTickStart,
    );
    if (health != previousHealth) overlayDirty = true;

    // 2. Movement
    _moveAlongPath(dt, movementSlowMultiplier);
    if (_isResolved) {
      return EnemyTickResult(
        reachedBase: true,
        diedByCorrosion: false,
        summonsDue: 0,
        overlayDirty: true,
      );
    }

    // 3. Slow decay
    if (slowRemaining > 0) {
      slowRemaining = math.max(0, slowRemaining - dt);
      if (slowRemaining == 0) {
        slowMultiplier = 1;
        overlayDirty = true;
      }
    }

    // 4. Summon.
    final summonsDue = _tickSummon(dt);

    return EnemyTickResult(
      reachedBase: false,
      diedByCorrosion: false,
      summonsDue: summonsDue,
      overlayDirty: overlayDirty,
    );
  }

  int _tickSummon(double dt) {
    final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
    final mechanic = bossDef?.summonMechanic;
    if (mechanic == null || mechanic.interval <= 0) return 0;
    _summonRemaining -= dt;
    const maxSummonsPerFrame = 16;
    var summons = 0;
    while (_summonRemaining <= 0 && summons < maxSummonsPerFrame) {
      _summonRemaining += mechanic.interval;
      summons += 1;
    }
    if (_summonRemaining <= 0) {
      // Unusually large dt: shed the debt instead of carrying it forward.
      _summonRemaining = mechanic.interval;
    }
    return summons;
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
