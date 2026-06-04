import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';
import '../rules/combat_effects.dart';
import '../rules/tower_targeting.dart';
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
  }) : _origin = startPosition.clone(),
       super(
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
  final Vector2 _origin;

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

    if (stats.chainCount > 0) {
      _resolveChainHit();
      return;
    }

    if (stats.pierceCount > 0) {
      _resolvePierceHit();
      return;
    }

    if (stats.corrosionDuration > 0) {
      _resolveCorrosionHit();
      return;
    }

    if (stats.fieldRadius > 0 && stats.fieldDuration > 0) {
      target.applyDamage(stats.damage);
      _applySlowIfNeeded(target);
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

      if (stats.clusterBurstCount > 0) {
        _resolveClusterBursts(impactPosition);
      }
      return;
    }

    final damage = CombatEffects.damageAgainstSlowState(
      baseDamage: stats.damage,
      slowedDamageMultiplier: stats.slowedDamageMultiplier,
      isSlowed: target.isSlowed,
    );
    target.applyDamage(damage);
    _applySlowIfNeeded(target);

    if (stats.prismSplitDamageMultiplier > 0 && stats.prismSplitRange > 0) {
      _resolvePrismSplit();
    }
  }

  void _resolveChainHit() {
    final enemies = List<EnemyComponent>.from(enemiesProvider());
    final candidates = enemies
        .where((enemy) => enemy.isAlive)
        .map((enemy) => enemy.targetCandidate)
        .toList(growable: false);
    final chain = CombatEffects.selectChainTargets(
      firstTarget: target.targetCandidate,
      candidates: candidates,
      chainCount: stats.chainCount,
      chainRange: stats.chainRange,
    );
    final enemyById = {for (final enemy in enemies) enemy.enemyId: enemy};

    for (final (index, candidate) in chain.indexed) {
      final enemy = enemyById[candidate.id];
      if (enemy == null || !enemy.isAlive) {
        continue;
      }

      enemy.applyDamage(
        CombatEffects.damageForChainJump(
          baseDamage: stats.damage,
          chainFalloff: stats.chainFalloff,
          jumpIndex: index,
        ),
        shieldDamageMultiplier: stats.shieldDamageMultiplier,
      );
    }
  }

  void _resolvePierceHit() {
    final enemies = List<EnemyComponent>.from(enemiesProvider());
    final candidates = enemies
        .where((enemy) => enemy.isAlive)
        .map((enemy) => enemy.targetCandidate)
        .toList(growable: false);
    final pierced = CombatEffects.selectPierceTargets(
      tower: TargetPoint(x: _origin.x, y: _origin.y),
      primaryTarget: target.targetCandidate,
      candidates: candidates,
      pierceCount: stats.pierceCount,
      pierceWidth: stats.pierceWidth,
    );
    final enemyById = {for (final enemy in enemies) enemy.enemyId: enemy};

    for (final candidate in pierced) {
      enemyById[candidate.id]?.applyDamage(
        stats.damage,
        armorDamageMultiplier: stats.armorDamageMultiplier,
      );
    }
  }

  void _resolveCorrosionHit() {
    target.applyDamage(stats.damage);
    target.applyCorrosion(
      damagePerSecond: stats.corrosionDamagePerSecond,
      duration: stats.corrosionDuration,
      armorShred: stats.armorShred,
    );
  }

  void _resolvePrismSplit() {
    EnemyComponent? selected;
    var selectedDistance = double.infinity;

    for (final enemy in enemiesProvider()) {
      if (identical(enemy, target) || !enemy.isAlive) {
        continue;
      }

      final distance = enemy.position.distanceTo(target.position);
      if (distance <= stats.prismSplitRange && distance < selectedDistance) {
        selected = enemy;
        selectedDistance = distance;
      }
    }

    selected?.applyDamage(stats.damage * stats.prismSplitDamageMultiplier);
  }

  void _resolveClusterBursts(Vector2 impactPosition) {
    for (var burst = 0; burst < stats.clusterBurstCount; burst += 1) {
      for (final enemy in enemiesProvider()) {
        if (!enemy.isAlive) {
          continue;
        }

        if (enemy.position.distanceTo(impactPosition) <=
            stats.clusterBurstRadius) {
          enemy.applyDamage(stats.damage * stats.clusterBurstDamageMultiplier);
        }
      }
    }
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
