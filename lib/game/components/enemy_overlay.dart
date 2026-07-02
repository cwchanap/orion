import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_tower_variety_sheet.dart';
import '../rules/enemy_overlay_state.dart';

class EnemyOverlayRenderer {
  EnemyOverlayRenderer();

  final Paint _barBackgroundPaint = Paint()..color = const Color(0xCC101624);
  final Paint _healthPaint = Paint()..color = const Color(0xFFE35D6A);
  final Paint _shieldPaint = Paint()..color = const Color(0xFF6EC6FF);
  final Paint _badgeBackgroundPaint = Paint()..color = const Color(0xD9141B2B);
  final Paint _badgeStrokePaint = Paint()
    ..color = const Color(0xCCFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static final Map<EnemyOverlayBadge, Paint> _fallbackPaints = {
    for (final badge in EnemyOverlayBadge.values)
      badge: Paint()..color = _fallbackColor(badge),
  };

  void render(
    Canvas canvas, {
    required EnemyOverlayState state,
    required double radius,
    GameTowerVarietySheet? towerVarietySheet,
  }) {
    if (!state.shouldRender) {
      return;
    }

    final layout = EnemyOverlayLayout.compute(state, radius);
    final centerX = radius;

    final badgesY = layout.badgesY;
    if (badgesY != null && state.badges.isNotEmpty) {
      _renderBadges(
        canvas,
        badges: state.badges,
        centerX: centerX,
        y: badgesY,
        size: layout.badgeSize,
        gap: layout.badgeGap,
        cornerRadius: layout.badgeCornerRadius,
        heavyCornerRadius: layout.heavyBadgeCornerRadius,
        towerVarietySheet: towerVarietySheet,
      );
    }

    final healthBarY = layout.healthBarY;
    if (healthBarY != null) {
      _renderBar(
        canvas,
        centerX: centerX,
        y: healthBarY,
        width: layout.healthBarWidth,
        height: layout.healthBarHeight,
        ratio: state.healthRatio,
        fillPaint: _healthPaint,
      );
    }

    final shieldBarY = layout.shieldBarY;
    if (shieldBarY != null) {
      _renderBar(
        canvas,
        centerX: centerX,
        y: shieldBarY,
        width: layout.shieldBarWidth,
        height: layout.shieldBarHeight,
        ratio: state.shieldRatio,
        fillPaint: _shieldPaint,
      );
    }
  }

  void _renderBar(
    Canvas canvas, {
    required double centerX,
    required double y,
    required double width,
    required double height,
    required double ratio,
    required Paint fillPaint,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - (width / 2), y, width, height),
      Radius.circular(height / 2),
    );
    canvas.drawRRect(rect, _barBackgroundPaint);

    if (ratio <= 0) {
      return;
    }

    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - (width / 2), y, width * ratio, height),
      Radius.circular(height / 2),
    );
    canvas.drawRRect(fillRect, fillPaint);
  }

  void _renderBadges(
    Canvas canvas, {
    required List<EnemyOverlayBadge> badges,
    required double centerX,
    required double y,
    required double size,
    required double gap,
    required double cornerRadius,
    required double heavyCornerRadius,
    required GameTowerVarietySheet? towerVarietySheet,
  }) {
    final totalWidth = (badges.length * size) + ((badges.length - 1) * gap);
    var x = centerX - (totalWidth / 2);

    for (final badge in badges) {
      final rect = Rect.fromLTWH(x, y, size, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)),
        _badgeBackgroundPaint,
      );

      final sprite = _spriteForBadge(towerVarietySheet, badge);
      if (sprite == null) {
        _renderFallbackBadge(
          canvas,
          rect,
          badge,
          heavyCornerRadius: heavyCornerRadius,
        );
      } else {
        sprite.render(
          canvas,
          position: Vector2(rect.left, rect.top),
          size: Vector2.all(size),
        );
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)),
        _badgeStrokePaint,
      );
      x += size + gap;
    }
  }

  Sprite? _spriteForBadge(
    GameTowerVarietySheet? towerVarietySheet,
    EnemyOverlayBadge badge,
  ) {
    if (towerVarietySheet == null) {
      return null;
    }

    final sprite = switch (badge) {
      EnemyOverlayBadge.shielded => GameTowerVarietySprite.shieldIndicator,
      EnemyOverlayBadge.armored => GameTowerVarietySprite.armorIndicator,
      EnemyOverlayBadge.regen => GameTowerVarietySprite.regenIndicator,
      EnemyOverlayBadge.corroded => GameTowerVarietySprite.corrosionIndicator,
      EnemyOverlayBadge.slowed => null,
      EnemyOverlayBadge.heavy => null,
      EnemyOverlayBadge.swarm => null,
    };

    if (sprite == null) {
      return null;
    }
    return towerVarietySheet.sprite(sprite);
  }

  void _renderFallbackBadge(
    Canvas canvas,
    Rect rect,
    EnemyOverlayBadge badge, {
    required double heavyCornerRadius,
  }) {
    final paint = _fallbackPaints[badge]!;
    final center = rect.center;
    final insetRect = rect.deflate(rect.width * 0.22);

    switch (badge) {
      case EnemyOverlayBadge.slowed:
        canvas.drawCircle(center, insetRect.width / 2, paint);
        canvas.drawLine(
          Offset(insetRect.left, insetRect.bottom),
          Offset(insetRect.right, insetRect.top),
          _badgeStrokePaint,
        );
        return;
      case EnemyOverlayBadge.heavy:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            insetRect,
            Radius.circular(heavyCornerRadius),
          ),
          paint,
        );
        return;
      case EnemyOverlayBadge.swarm:
        canvas.drawCircle(
          Offset(center.dx - rect.width * 0.16, center.dy),
          rect.width * 0.13,
          paint,
        );
        canvas.drawCircle(center, rect.width * 0.13, paint);
        canvas.drawCircle(
          Offset(center.dx + rect.width * 0.16, center.dy),
          rect.width * 0.13,
          paint,
        );
        return;
      case EnemyOverlayBadge.corroded:
      case EnemyOverlayBadge.shielded:
      case EnemyOverlayBadge.armored:
      case EnemyOverlayBadge.regen:
        canvas.drawCircle(center, insetRect.width / 2, paint);
        return;
    }
  }

  static Color _fallbackColor(EnemyOverlayBadge badge) {
    return switch (badge) {
      EnemyOverlayBadge.corroded => const Color(0xFF67D46E),
      EnemyOverlayBadge.slowed => const Color(0xFF78D8FF),
      EnemyOverlayBadge.shielded => const Color(0xFF6EC6FF),
      EnemyOverlayBadge.armored => const Color(0xFFC9D6E8),
      EnemyOverlayBadge.regen => const Color(0xFF67D46E),
      EnemyOverlayBadge.heavy => const Color(0xFFFFB84D),
      EnemyOverlayBadge.swarm => const Color(0xFFFFD166),
    };
  }
}
