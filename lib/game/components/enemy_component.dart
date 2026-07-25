import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_boss_sheet.dart';
import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';
import '../rules/combat_effects.dart';
import '../rules/enemy_overlay_state.dart';
import '../rules/tower_targeting.dart';
import 'enemy_overlay.dart';

typedef EnemyKilledCallback = void Function(EnemyComponent enemy);
typedef EnemyReachedBaseCallback = void Function(EnemyComponent enemy);

class EnemyComponent extends CircleComponent {
  EnemyComponent({
    required this.enemyId,
    required EnemyStats stats,
    required List<Vector2> waypoints,
    required this.onKilled,
    required this.onReachedBase,
    this.spriteSheet,
    this.towerVarietySheet,
    this.bossSheet,
    this.onSummonMinions,
    this.minionOf,
    this.initialCompletedDistance = 0,
    double radius = 11,
    super.priority,
  }) : stats = stats,
       waypoints = List.unmodifiable(waypoints.map((point) => point.clone())),
       health = stats.health,
       _completedDistance = initialCompletedDistance,
       _summonRemaining = _initialSummonDelay(stats),
       assert(
         waypoints.length >= 2,
         'EnemyComponent requires at least two waypoints',
       ),
       super(
         radius: radius,
         anchor: Anchor.center,
         position: waypoints.first.clone(),
         paint: Paint()..color = const Color(0xFFE35D6A),
       );

  final int enemyId;
  final EnemyStats stats;
  final List<Vector2> waypoints;
  final EnemyKilledCallback onKilled;
  final EnemyReachedBaseCallback onReachedBase;
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;
  final GameBossSheet? bossSheet;
  final void Function(EnemyComponent source, int count)? onSummonMinions;
  final int? minionOf;
  final double initialCompletedDistance;

  double health;
  late double shield = stats.shieldHealth;
  late final double maxHealth = stats.health;
  bool _isInspected = false;
  bool _isResolved = false;
  int _targetWaypointIndex = 1;
  double _completedDistance;
  double _segmentProgress = 0;
  double _slowMultiplier = 1;
  double _slowRemaining = 0;
  double _corrosionDamagePerSecond = 0;
  double _corrosionRemaining = 0;
  double _armorShred = 0;
  double _summonRemaining;

  static double _initialSummonDelay(EnemyStats stats) {
    if (stats is BossDefinition) {
      final mechanic = stats.summonMechanic;
      if (mechanic != null) return mechanic.firstDelay;
    }
    return 0;
  }

  EnemyOverlayState? _cachedOverlayState;
  bool _overlayDirty = true;

  static final EnemyOverlayRenderer _overlayRenderer = EnemyOverlayRenderer();

  bool get isAlive => !_isResolved && health > 0;
  bool get isResolved => _isResolved;
  bool get isInspected => _isInspected;
  bool get isCorroded => _corrosionRemaining > 0;
  bool get isSlowed => _slowRemaining > 0 && _slowMultiplier < 1;
  double get armorReduction =>
      (stats.armorReduction - _armorShred).clamp(0, 0.75).toDouble();

  EnemyOverlayState get overlayState {
    final cached = _cachedOverlayState;
    if (cached != null && !_overlayDirty) {
      return cached;
    }
    final state = EnemyOverlayState.fromData(
      EnemyOverlayData(
        isResolved: isResolved,
        isInspected: isInspected,
        health: health,
        maxHealth: maxHealth,
        shield: shield,
        maxShield: stats.shieldHealth,
        traits: stats.traits,
        isSlowed: isSlowed,
        isCorroded: isCorroded,
        isBoss: stats is BossDefinition,
      ),
    );
    _cachedOverlayState = state;
    _overlayDirty = false;
    return state;
  }

  double get pathProgress {
    return _completedDistance + _currentSegmentLength * _segmentProgress;
  }

  List<Vector2> residualWaypointsFromHere() => [
    position.clone(),
    ...waypoints.sublist(_targetWaypointIndex),
  ];

  TargetCandidate get targetCandidate {
    return TargetCandidate(
      id: enemyId,
      x: position.x,
      y: position.y,
      pathProgress: pathProgress,
      isAlive: isAlive,
      currentHealth: health,
      currentShield: shield,
      isShielded: stats.traits.contains(EnemyTrait.shielded),
      isArmored: stats.traits.contains(EnemyTrait.armored),
    );
  }

  void setInspected(bool value) {
    if (_isInspected == value) {
      return;
    }
    _isInspected = value;
    _overlayDirty = true;
  }

  void applyDamage(
    double amount, {
    double shieldDamageMultiplier = 1,
    double armorDamageMultiplier = 1,
    double armorShred = 0,
    bool bypassArmor = false,
  }) {
    if (!isAlive || amount <= 0) {
      return;
    }

    final result = CombatEffects.resolveDamage(
      DamageInput(
        health: health,
        maxHealth: maxHealth,
        shield: shield,
        damage: amount,
        armorReduction: stats.armorReduction,
        armorShred: math.max(_armorShred, armorShred),
        shieldDamageMultiplier: shieldDamageMultiplier,
        armorDamageMultiplier: armorDamageMultiplier,
        bypassArmor: bypassArmor,
      ),
    );
    health = result.health;
    shield = result.shield;
    _overlayDirty = true;
    if (health == 0) {
      _resolve(onKilled);
    }
  }

  void applySlow({required double multiplier, required double duration}) {
    if (!isAlive || multiplier >= 1 || multiplier <= 0 || duration <= 0) {
      return;
    }

    final result = CombatEffects.mergeSlow(
      currentMultiplier: _slowMultiplier,
      currentRemaining: _slowRemaining,
      incomingMultiplier: multiplier,
      incomingDuration: duration,
    );
    _slowMultiplier = result.multiplier;
    _slowRemaining = result.remaining;
    _overlayDirty = true;
  }

  void applyCorrosion({
    required double damagePerSecond,
    required double duration,
    required double armorShred,
  }) {
    if (!isAlive || damagePerSecond <= 0 || duration <= 0) {
      return;
    }

    _corrosionDamagePerSecond = math.max(
      _corrosionDamagePerSecond,
      damagePerSecond,
    );
    _corrosionRemaining = math.max(_corrosionRemaining, duration);
    _armorShred = math.max(_armorShred, armorShred);
    _overlayDirty = true;
  }

  @override
  void render(Canvas canvas) {
    final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
    if (bossDef != null && bossSheet != null) {
      bossSheet!
          .sprite(bossDef.sprite)
          .render(
            canvas,
            position: Vector2(radius, radius),
            size: Vector2.all(radius * 2.4),
            anchor: Anchor.center,
          );
    } else if (spriteSheet != null) {
      spriteSheet!
          .sprite(GameSpriteSheet.spriteForEnemy(stats))
          .render(
            canvas,
            position: Vector2(radius, radius),
            size: Vector2.all(radius * 2.4),
            anchor: Anchor.center,
          );
    } else {
      super.render(canvas);
    }

    _overlayRenderer.render(
      canvas,
      state: overlayState,
      radius: radius,
      towerVarietySheet: towerVarietySheet,
      name: bossDef?.name,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) {
      return;
    }

    final movementSlowMultiplier = isSlowed ? _slowMultiplier : 1.0;
    final wasCorrodedAtTickStart = isCorroded;
    _tickCorrosionAndRegen(dt, wasCorrodedAtTickStart: wasCorrodedAtTickStart);
    if (!isAlive) {
      return;
    }

    _moveAlongPath(dt, movementSlowMultiplier);
    if (!isAlive) {
      // Boss may have reached the base (or been resolved) during movement;
      // do not run the summon timer on the frame it was resolved.
      return;
    }
    _tickSlow(dt);

    final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
    final mechanic = bossDef?.summonMechanic;
    if (mechanic != null && onSummonMinions != null && mechanic.interval > 0) {
      _summonRemaining -= dt;
      // Bound iterations per frame: a zero/negative interval is rejected above
      // (release-safe; the assert in SummonMechanic is stripped in release),
      // and an unusually large dt cannot spin the loop unboundedly.
      const maxSummonsPerFrame = 16;
      var summonsThisFrame = 0;
      while (_summonRemaining <= 0 && summonsThisFrame < maxSummonsPerFrame) {
        _summonRemaining += mechanic.interval;
        onSummonMinions!(this, mechanic.count);
        summonsThisFrame += 1;
      }
      if (_summonRemaining <= 0) {
        // dt was unusually large; shed the accumulated debt instead of
        // carrying it forward into the next frame.
        _summonRemaining = mechanic.interval;
      }
    }
  }

  double get _currentSegmentLength {
    if (_targetWaypointIndex >= waypoints.length) {
      return 0;
    }
    final segmentStart = waypoints[_targetWaypointIndex - 1];
    final segmentEnd = waypoints[_targetWaypointIndex];
    return segmentStart.distanceTo(segmentEnd);
  }

  void _moveAlongPath(double dt, double slowMultiplier) {
    var distanceRemaining = stats.speed * slowMultiplier * dt;
    while (distanceRemaining > 0 && isAlive) {
      if (_targetWaypointIndex >= waypoints.length) {
        _resolve(onReachedBase);
        return;
      }

      final target = waypoints[_targetWaypointIndex];
      final toTarget = target - position;
      final distanceToTarget = toTarget.length;
      final segmentLength = _currentSegmentLength;

      if (distanceToTarget <= distanceRemaining) {
        position.setFrom(target);
        _completedDistance += segmentLength;
        _segmentProgress = 1;
        _targetWaypointIndex += 1;
        distanceRemaining -= distanceToTarget;

        if (_targetWaypointIndex >= waypoints.length) {
          _resolve(onReachedBase);
          return;
        }
        _segmentProgress = 0;
      } else {
        final step = toTarget.normalized()..scale(distanceRemaining);
        position.add(step);
        _segmentProgress =
            1 -
            ((distanceToTarget - distanceRemaining) / _currentSegmentLength);
        distanceRemaining = 0;
      }
    }
  }

  void _tickCorrosionAndRegen(
    double dt, {
    required bool wasCorrodedAtTickStart,
  }) {
    if (_corrosionRemaining > 0) {
      final tick = math.min(math.max(0, dt), _corrosionRemaining);
      _corrosionRemaining = math.max(0, _corrosionRemaining - tick);
      applyDamage(_corrosionDamagePerSecond * tick, bypassArmor: true);
      if (_corrosionRemaining == 0) {
        _corrosionDamagePerSecond = 0;
        _armorShred = 0;
        _overlayDirty = true;
      }
    }

    if (!isAlive) {
      return;
    }

    final previousHealth = health;
    health = CombatEffects.applyRegen(
      health: health,
      maxHealth: maxHealth,
      regenPerSecond: stats.regenPerSecond,
      dt: dt,
      isCorroded: wasCorrodedAtTickStart,
    );
    if (health != previousHealth) {
      _overlayDirty = true;
    }
  }

  void _tickSlow(double dt) {
    if (_slowRemaining > 0) {
      _slowRemaining = math.max(0, _slowRemaining - dt);
      if (_slowRemaining == 0) {
        _slowMultiplier = 1;
        _overlayDirty = true;
      }
    }
  }

  void _resolve(void Function(EnemyComponent enemy) callback) {
    if (_isResolved) {
      return;
    }

    _isResolved = true;
    _overlayDirty = true;
    callback(this);
    removeFromParent();
  }
}
