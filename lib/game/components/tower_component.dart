import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
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
    this.spriteSheet,
    this.towerVarietySheet,
    double radius = 15,
    super.priority,
  }) : placedTower = tower,
       stats = GameBalance.towerStats(
         tower.type,
         level: tower.level,
         specialization: tower.specialization,
       ),
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
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;

  final Paint _strokePaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  double _cooldownRemaining = 0;

  void updateTower(PlacedTower tower) {
    placedTower = tower;
    stats = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
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
    final sprite = _towerSprite();
    if (sprite == null) {
      super.render(canvas);
    } else {
      sprite.render(
        canvas,
        position: Vector2(radius, radius),
        size: Vector2.all(radius * 2.4),
        anchor: Anchor.center,
      );
    }
    canvas.drawCircle(Offset(radius, radius), radius - 1, _strokePaint);
  }

  Sprite? _towerSprite() {
    if (GameTowerVarietySheet.hasTowerSprite(placedTower.type)) {
      final towerVarietySheet = this.towerVarietySheet;
      if (towerVarietySheet == null) {
        return null;
      }
      return towerVarietySheet.sprite(
        GameTowerVarietySheet.spriteForTower(placedTower.type),
      );
    }

    final spriteSheet = this.spriteSheet;
    if (spriteSheet == null) {
      return null;
    }
    return spriteSheet.sprite(GameSpriteSheet.spriteForTower(placedTower.type));
  }

  static Color _towerColor(TowerType type) {
    return switch (type) {
      TowerType.laser => const Color(0xFF2FBF71),
      TowerType.rocket => const Color(0xFFE07A2D),
      TowerType.cryo => const Color(0xFF4AA8D8),
      TowerType.railgun => const Color(0xFFC9D6E8),
      TowerType.ionChain => const Color(0xFFB476FF),
      TowerType.nanite => const Color(0xFF67D46E),
      TowerType.gravityWell => const Color(0xFF6E7BFF),
      TowerType.droneBay => const Color(0xFFFFD166),
    };
  }
}
