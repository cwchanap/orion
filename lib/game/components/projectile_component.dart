import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';
import 'enemy_component.dart';

typedef EnemiesProvider = Iterable<EnemyComponent> Function();

class ProjectileComponent extends CircleComponent {
  ProjectileComponent({
    required this.stats,
    required this.target,
    required Vector2 startPosition,
    required this.enemiesProvider,
    this.spriteSheet,
    this.towerVarietySheet,
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
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;

  @override
  void render(Canvas canvas) {
    final sprite = _projectileSprite();
    if (sprite == null) {
      super.render(canvas);
      return;
    }

    sprite.render(
      canvas,
      position: Vector2(radius, radius),
      size: Vector2.all(radius * 3),
      anchor: Anchor.center,
    );
  }

  Sprite? _projectileSprite() {
    if (GameTowerVarietySheet.hasTowerSprite(stats.type)) {
      final towerVarietySheet = this.towerVarietySheet;
      if (towerVarietySheet == null) {
        return null;
      }
      return towerVarietySheet.sprite(
        GameTowerVarietySheet.spriteForProjectile(stats.type),
      );
    }

    final spriteSheet = this.spriteSheet;
    if (spriteSheet == null) {
      return null;
    }
    return spriteSheet.sprite(GameSpriteSheet.spriteForProjectile(stats.type));
  }

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
      TowerType.railgun => const Color(0xFFE8F1FF),
      TowerType.ionChain => const Color(0xFFD7B2FF),
      TowerType.nanite => const Color(0xFF9EF59A),
      TowerType.gravityWell => const Color(0xFFA9B0FF),
      TowerType.droneBay => const Color(0xFFFFE08A),
    };
  }
}
