import 'dart:ui';

import '../models/game_models.dart';

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

  bool _isResolved = false;
  int _targetWaypointIndex = 1;
  double _completedDistance;
  double _segmentProgress = 0;

  bool get isResolved => _isResolved;
  int get targetWaypointIndex => _targetWaypointIndex;
  bool get isAlive => !_isResolved && health > 0;

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
        final scale = distanceRemaining / distanceToTarget;
        position = position + Offset(toTarget.dx * scale, toTarget.dy * scale);
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
