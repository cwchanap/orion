import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

typedef DroneTargetProvider = EnemyComponent? Function(Vector2 position);
typedef DroneExpiredCallback = void Function(DroneComponent drone);

class DroneComponent extends CircleComponent {
  DroneComponent({
    required this.ownerTowerId,
    required this.stats,
    required Vector2 startPosition,
    required this.acquireTarget,
    required this.onExpired,
    super.priority,
  }) : _remaining = stats.droneLifetime,
       _attackRemaining = 0,
       super(
         radius: 6,
         anchor: Anchor.center,
         position: startPosition.clone(),
         paint: Paint()..color = const Color(0xFFFFD166),
       );

  final int ownerTowerId;
  final TowerStats stats;
  final DroneTargetProvider acquireTarget;
  final DroneExpiredCallback onExpired;
  double _remaining;
  double _attackRemaining;
  bool _expired = false;

  @override
  void update(double dt) {
    super.update(dt);
    _remaining -= dt;
    _attackRemaining -= dt;

    if (_remaining <= 0) {
      _expire();
      return;
    }

    final target = acquireTarget(position);
    if (target == null || !target.isAlive) {
      return;
    }

    final toTarget = target.position - position;
    final distance = toTarget.length;
    final travel = 180 * dt;
    if (distance > 2) {
      position.add(toTarget.normalized()..scale(math.min(travel, distance)));
    }

    final attackDistance = target.position.distanceTo(position);
    if (attackDistance <= 24 && _attackRemaining <= 0) {
      target.applyDamage(stats.droneDamage);
      _attackRemaining = stats.droneAttackInterval;
    }
  }

  void _expire() {
    if (_expired) {
      return;
    }

    _expired = true;
    onExpired(this);
    removeFromParent();
  }
}
