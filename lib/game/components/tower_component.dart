import 'dart:ui';

import 'package:flame/components.dart';

import '../models/game_models.dart';
import 'enemy_component.dart';

typedef TargetAcquirer = EnemyComponent? Function(TowerComponent tower);
typedef ProjectileLauncher =
    void Function(TowerComponent tower, EnemyComponent target);

class TowerComponent extends CircleComponent {
  TowerComponent({
    required PlacedTower tower,
    required Vector2 center,
    required this.acquireTarget,
    required this.launchProjectile,
    double radius = 15,
    super.priority,
  }) : placedTower = tower,
       stats = GameBalance.towerStats(tower.type, level: tower.level),
       super(
         radius: radius,
         anchor: Anchor.center,
         position: center.clone(),
         paint: Paint()..color = _towerColor(tower.type),
       );

  PlacedTower placedTower;
  TowerStats stats;
  final TargetAcquirer acquireTarget;
  final ProjectileLauncher launchProjectile;

  final Paint _strokePaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  double _cooldownRemaining = 0;

  void updateTower(PlacedTower tower) {
    placedTower = tower;
    stats = GameBalance.towerStats(tower.type, level: tower.level);
    paint.color = _towerColor(tower.type);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_cooldownRemaining > 0) {
      _cooldownRemaining -= dt;
      return;
    }

    final target = acquireTarget(this);
    if (target == null || !target.isAlive) {
      return;
    }

    launchProjectile(this, target);
    _cooldownRemaining = stats.fireInterval;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawCircle(Offset(radius, radius), radius - 1, _strokePaint);
  }

  static Color _towerColor(TowerType type) {
    return switch (type) {
      TowerType.laser => const Color(0xFF2FBF71),
      TowerType.rocket => const Color(0xFFE07A2D),
      TowerType.cryo => const Color(0xFF4AA8D8),
    };
  }
}
