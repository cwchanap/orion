import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import '../rules/tower_targeting.dart';

typedef EnemyKilledCallback = void Function(EnemyComponent enemy);
typedef EnemyReachedBaseCallback = void Function(EnemyComponent enemy);

class EnemyComponent extends CircleComponent {
  EnemyComponent({
    required this.enemyId,
    required this.stats,
    required List<Vector2> waypoints,
    required this.onKilled,
    required this.onReachedBase,
    double radius = 11,
    super.priority,
  }) : waypoints = List.unmodifiable(waypoints.map((point) => point.clone())),
       health = stats.health,
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

  double health;
  bool _isResolved = false;
  int _targetWaypointIndex = 1;
  double _completedDistance = 0;
  double _segmentProgress = 0;
  double _slowMultiplier = 1;
  double _slowRemaining = 0;

  bool get isAlive => !_isResolved && health > 0;
  bool get isResolved => _isResolved;

  double get pathProgress {
    return _completedDistance + _currentSegmentLength * _segmentProgress;
  }

  TargetCandidate get targetCandidate {
    return TargetCandidate(
      id: enemyId,
      x: position.x,
      y: position.y,
      pathProgress: pathProgress,
      isAlive: isAlive,
    );
  }

  void applyDamage(double amount) {
    if (!isAlive || amount <= 0) {
      return;
    }

    health = math.max(0, health - amount);
    if (health == 0) {
      _resolve(onKilled);
    }
  }

  void applySlow({required double multiplier, required double duration}) {
    if (!isAlive || multiplier >= 1 || multiplier <= 0 || duration <= 0) {
      return;
    }

    _slowMultiplier = math.min(_slowMultiplier, multiplier);
    _slowRemaining = math.max(_slowRemaining, duration);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) {
      return;
    }

    if (_slowRemaining > 0) {
      _slowRemaining = math.max(0, _slowRemaining - dt);
      if (_slowRemaining == 0) {
        _slowMultiplier = 1;
      }
    }

    var distanceRemaining = stats.speed * _slowMultiplier * dt;
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

  double get _currentSegmentLength {
    if (_targetWaypointIndex >= waypoints.length) {
      return 0;
    }
    final segmentStart = waypoints[_targetWaypointIndex - 1];
    final segmentEnd = waypoints[_targetWaypointIndex];
    return segmentStart.distanceTo(segmentEnd);
  }

  void _resolve(void Function(EnemyComponent enemy) callback) {
    if (_isResolved) {
      return;
    }

    _isResolved = true;
    callback(this);
    removeFromParent();
  }
}
