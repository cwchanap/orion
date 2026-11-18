import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';
import 'enemy_component.dart';

typedef TargetAcquirer = EnemyComponent? Function(TowerComponent tower);
typedef ProjectileLauncher =
    void Function(TowerComponent tower, EnemyComponent target);
typedef TowerStatsProvider = TowerStats Function(PlacedTower tower);

class TowerComponent extends CircleComponent {
  TowerComponent({
    required PlacedTower tower,
    required Vector2 center,
    required this.resolveStats,
    required this.acquireTarget,
    required this.launchProjectile,
    this.spriteSheet,
    this.towerVarietySheet,
    this.chibiSprite,
    double radius = 15,
    super.priority,
  }) : placedTower = tower,
       stats = resolveStats(tower),
       super(
         radius: radius,
         anchor: Anchor.center,
         position: center.clone(),
         paint: Paint()..color = _towerColor(tower.type),
       ) {
    _ringPaint.color = _rankColor(tower.character.rank);
  }

  PlacedTower placedTower;
  TowerStats stats;
  final TowerStatsProvider resolveStats;
  final TargetAcquirer acquireTarget;
  final ProjectileLauncher launchProjectile;
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;

  /// The member's approved HPA-924 full-body chibi, preloaded for the active
  /// squad at game onLoad. `null` keeps the legacy socket/sheet rendering.
  /// Mutable: a placement committed while the chibi was still in flight is
  /// backfilled by the game once the sprite resolves.
  Sprite? chibiSprite;

  final Paint _strokePaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  /// Rank-colored deployment ring under the chibi's feet.
  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2;

  final Paint _ringGlowPaint = Paint()..style = PaintingStyle.fill;

  /// The chibi ships 512px; it renders at `radius * 4.2`, so keep a filtered
  /// downsample rather than aliasing the approved art.
  final Paint _chibiPaint = Paint()..filterQuality = FilterQuality.medium;

  double _cooldownRemaining = 0;

  void updateTower(PlacedTower tower) {
    placedTower = tower;
    stats = resolveStats(tower);
    paint.color = _towerColor(tower.type);
    _ringPaint.color = _rankColor(tower.character.rank);
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
    final chibi = chibiSprite;
    if (chibi != null) {
      // The member stands centered on a squashed platform ring; its feet sit
      // on the socket point so the ring's lower arc reads as ground.
      final ring = Rect.fromCenter(
        center: Offset(radius, radius),
        width: radius * 2.6,
        height: radius * 1.3,
      );
      _ringGlowPaint.color = _ringPaint.color.withValues(alpha: 0.22);
      canvas.drawOval(ring, _ringGlowPaint);
      canvas.drawOval(ring, _ringPaint);
      chibi.render(
        canvas,
        position: Vector2(radius, radius),
        // Art can overhang the socket; targeting and placement keep their original geometry.
        size: Vector2.all(radius * 4.2),
        anchor: Anchor.bottomCenter,
        overridePaint: _chibiPaint,
      );
      return;
    }

    final sprite = _towerSprite();
    if (sprite == null) {
      super.render(canvas);
    } else {
      sprite.render(
        canvas,
        position: Vector2(radius, radius),
        // Art can overhang the socket; targeting and placement keep their original geometry.
        size: Vector2.all(radius * 4.2),
        anchor: Anchor.center,
      );
    }
    if (sprite == null) {
      canvas.drawCircle(Offset(radius, radius), radius - 1, _strokePaint);
    }
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

  /// Rank ring colors mirror the Camp roster mapping
  /// (`camp_view.dart` / `OrionUiTheme.dark`) so a member reads at the same
  /// tier in battle as on the roster screen.
  static Color _rankColor(CharacterRank rank) {
    return switch (rank) {
      CharacterRank.s => const Color(0xFFFFC857),
      CharacterRank.a => const Color(0xFFFF8A3D),
      CharacterRank.b => const Color(0xFFA98BFF),
      CharacterRank.c => const Color(0xFF46E6FF),
      CharacterRank.d => const Color(0xFF7BE495),
      CharacterRank.e => const Color(0xFFCFDBE6),
    };
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
