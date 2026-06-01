import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

typedef EnemiesProvider = Iterable<EnemyComponent> Function();

class ProjectileComponent extends CircleComponent {
  ProjectileComponent({
    required this.stats,
    required this.target,
    required Vector2 startPosition,
    required this.enemiesProvider,
    double radius = 5,
    super.priority,
  }) : super(
         radius: radius,
         anchor: Anchor.center,
         position: startPosition.clone(),
         paint: Paint()..color = _projectileColor(stats.type),
       );

  final TowerStats stats;
  final EnemyComponent target;
  final EnemiesProvider enemiesProvider;

  @override
  void update(double dt) {
    super.update(dt);
    if (!target.isAlive || !target.isMounted) {
      removeFromParent();
      return;
    }

    final toTarget = target.position - position;
    final distanceToTarget = toTarget.length;
    final travelDistance = stats.projectileSpeed * dt;

    if (distanceToTarget <= math.max(travelDistance, target.radius)) {
      _resolveHit();
      removeFromParent();
      return;
    }

    position.add(toTarget.normalized()..scale(travelDistance));
  }

  void _resolveHit() {
    if (!target.isAlive) {
      return;
    }

    if (stats.splashRadius > 0) {
      final impactPosition = target.position.clone();
      final splashCandidates = List<EnemyComponent>.from(enemiesProvider());

      target.applyDamage(stats.damage);
      _applySlowIfNeeded(target);

      for (final enemy in splashCandidates) {
        if (identical(enemy, target) || !enemy.isAlive) {
          continue;
        }
        if (enemy.position.distanceTo(impactPosition) <= stats.splashRadius) {
          enemy.applyDamage(stats.damage);
          _applySlowIfNeeded(enemy);
        }
      }
      return;
    }

    target.applyDamage(stats.damage);
    _applySlowIfNeeded(target);
  }

  void _applySlowIfNeeded(EnemyComponent enemy) {
    if (stats.slowMultiplier < 1 && stats.slowDuration > 0) {
      enemy.applySlow(
        multiplier: stats.slowMultiplier,
        duration: stats.slowDuration,
      );
    }
  }

  static Color _projectileColor(TowerType type) {
    return switch (type) {
      TowerType.laser => const Color(0xFFB7F7D4),
      TowerType.rocket => const Color(0xFFFFB84D),
      TowerType.cryo => const Color(0xFF8AD8FF),
    };
  }
}
