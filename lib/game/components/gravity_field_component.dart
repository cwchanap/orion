import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

typedef GravityEnemiesProvider = Iterable<EnemyComponent> Function();

class GravityFieldComponent extends CircleComponent {
  GravityFieldComponent({
    required this.stats,
    required Vector2 center,
    required this.enemiesProvider,
    super.priority,
  }) : _remaining = stats.fieldDuration,
       _tickRemaining = 0,
       super(
         radius: stats.fieldRadius,
         anchor: Anchor.center,
         position: center.clone(),
         paint: Paint()..color = const Color(0x446E7BFF),
       );

  final TowerStats stats;
  final GravityEnemiesProvider enemiesProvider;
  double _remaining;
  double _tickRemaining;

  @override
  void update(double dt) {
    super.update(dt);
    _remaining -= dt;
    _tickRemaining -= dt;

    if (_remaining <= 0) {
      removeFromParent();
      return;
    }

    if (_tickRemaining > 0) {
      return;
    }

    _tickRemaining = stats.fieldTickInterval;
    for (final enemy in enemiesProvider()) {
      if (!enemy.isAlive || enemy.position.distanceTo(position) > radius) {
        continue;
      }

      if (stats.damage > 0) {
        enemy.applyDamage(stats.damage);
      }

      if (stats.slowMultiplier < 1 && stats.slowDuration > 0) {
        enemy.applySlow(
          multiplier: stats.slowMultiplier,
          duration: stats.slowDuration,
        );
      }
    }
  }
}
