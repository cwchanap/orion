import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_tower_variety_sheet.dart';
import '../models/game_models.dart';

enum EnemyOverlayBadge {
  corroded,
  slowed,
  shielded,
  armored,
  regen,
  heavy,
  swarm,
}

class EnemyOverlayData {
  factory EnemyOverlayData({
    required bool isResolved,
    bool isInspected = false,
    required double health,
    required double maxHealth,
    required double shield,
    required double maxShield,
    required Set<EnemyTrait> traits,
    required bool isSlowed,
    required bool isCorroded,
  }) {
    return EnemyOverlayData._(
      isResolved: isResolved,
      isInspected: isInspected,
      health: health,
      maxHealth: maxHealth,
      shield: shield,
      maxShield: maxShield,
      traits: Set.unmodifiable(traits),
      isSlowed: isSlowed,
      isCorroded: isCorroded,
    );
  }

  const EnemyOverlayData._({
    required this.isResolved,
    required this.isInspected,
    required this.health,
    required this.maxHealth,
    required this.shield,
    required this.maxShield,
    required this.traits,
    required this.isSlowed,
    required this.isCorroded,
  });

  final bool isResolved;
  final bool isInspected;
  final double health;
  final double maxHealth;
  final double shield;
  final double maxShield;
  final Set<EnemyTrait> traits;
  final bool isSlowed;
  final bool isCorroded;

  EnemyOverlayData copyWith({
    bool? isResolved,
    bool? isInspected,
    double? health,
    double? maxHealth,
    double? shield,
    double? maxShield,
    Set<EnemyTrait>? traits,
    bool? isSlowed,
    bool? isCorroded,
  }) {
    return EnemyOverlayData(
      isResolved: isResolved ?? this.isResolved,
      isInspected: isInspected ?? this.isInspected,
      health: health ?? this.health,
      maxHealth: maxHealth ?? this.maxHealth,
      shield: shield ?? this.shield,
      maxShield: maxShield ?? this.maxShield,
      traits: traits ?? this.traits,
      isSlowed: isSlowed ?? this.isSlowed,
      isCorroded: isCorroded ?? this.isCorroded,
    );
  }
}

class EnemyOverlayState {
  factory EnemyOverlayState({
    required bool shouldRender,
    required bool isExpanded,
    required double healthRatio,
    required double shieldRatio,
    required bool showHealthBar,
    required bool showShieldBar,
    required List<EnemyOverlayBadge> badges,
  }) {
    return EnemyOverlayState._(
      shouldRender: shouldRender,
      isExpanded: isExpanded,
      healthRatio: healthRatio,
      shieldRatio: shieldRatio,
      showHealthBar: showHealthBar,
      showShieldBar: showShieldBar,
      badges: List.unmodifiable(badges),
    );
  }

  const EnemyOverlayState._({
    required this.shouldRender,
    required this.isExpanded,
    required this.healthRatio,
    required this.shieldRatio,
    required this.showHealthBar,
    required this.showShieldBar,
    required this.badges,
  });

  static const int normalBadgeLimit = 2;
  static const int expandedBadgeLimit = 4;

  final bool shouldRender;
  final bool isExpanded;
  final double healthRatio;
  final double shieldRatio;
  final bool showHealthBar;
  final bool showShieldBar;
  final List<EnemyOverlayBadge> badges;

  factory EnemyOverlayState.fromData(EnemyOverlayData data) {
    if (data.isResolved) {
      return const EnemyOverlayState._(
        shouldRender: false,
        isExpanded: false,
        healthRatio: 0,
        shieldRatio: 0,
        showHealthBar: false,
        showShieldBar: false,
        badges: [],
      );
    }

    final healthRatio = _ratio(data.health, data.maxHealth);
    final shieldRatio = _ratio(data.shield, data.maxShield);
    final hasShieldState = data.maxShield > 0 || data.shield > 0;
    final isDamaged = healthRatio < 1;
    final hasHighSignalTrait =
        data.traits.contains(EnemyTrait.armored) ||
        data.traits.contains(EnemyTrait.shielded) ||
        data.traits.contains(EnemyTrait.regen) ||
        data.traits.contains(EnemyTrait.heavy);
    final isNotable =
        isDamaged ||
        hasShieldState ||
        hasHighSignalTrait ||
        data.isSlowed ||
        data.isCorroded;
    final shouldRender = data.isInspected || isNotable;
    final allBadges = shouldRender
        ? _orderedBadges(
            traits: data.traits,
            hasShieldState: hasShieldState,
            isSlowed: data.isSlowed,
            isCorroded: data.isCorroded,
          )
        : const <EnemyOverlayBadge>[];
    final badgeLimit = data.isInspected ? expandedBadgeLimit : normalBadgeLimit;

    return EnemyOverlayState._(
      shouldRender: shouldRender,
      isExpanded: data.isInspected,
      healthRatio: healthRatio,
      shieldRatio: shieldRatio,
      showHealthBar:
          shouldRender && (data.isInspected || isDamaged || hasShieldState),
      showShieldBar: shouldRender && hasShieldState,
      badges: List.unmodifiable(allBadges.take(badgeLimit)),
    );
  }

  static double _ratio(double value, double maxValue) {
    if (maxValue <= 0) {
      return 0;
    }
    return (value / maxValue).clamp(0, 1).toDouble();
  }

  static List<EnemyOverlayBadge> _orderedBadges({
    required Set<EnemyTrait> traits,
    required bool hasShieldState,
    required bool isSlowed,
    required bool isCorroded,
  }) {
    return [
      if (isCorroded) EnemyOverlayBadge.corroded,
      if (isSlowed) EnemyOverlayBadge.slowed,
      if (hasShieldState || traits.contains(EnemyTrait.shielded))
        EnemyOverlayBadge.shielded,
      if (traits.contains(EnemyTrait.armored)) EnemyOverlayBadge.armored,
      if (traits.contains(EnemyTrait.regen)) EnemyOverlayBadge.regen,
      if (traits.contains(EnemyTrait.heavy)) EnemyOverlayBadge.heavy,
      if (traits.contains(EnemyTrait.swarm)) EnemyOverlayBadge.swarm,
    ];
  }
}

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

  void render(
    Canvas canvas, {
    required EnemyOverlayState state,
    required double radius,
    GameTowerVarietySheet? towerVarietySheet,
  }) {
    if (!state.shouldRender) {
      return;
    }

    final centerX = radius;
    var top = -radius * (state.isExpanded ? 0.92 : 0.72);

    if (state.badges.isNotEmpty) {
      _renderBadges(
        canvas,
        badges: state.badges,
        centerX: centerX,
        y: top,
        size: state.isExpanded ? 9 : 7,
        towerVarietySheet: towerVarietySheet,
      );
      top += state.isExpanded ? 11 : 9;
    }

    if (state.showHealthBar) {
      _renderBar(
        canvas,
        centerX: centerX,
        y: top,
        width: radius * (state.isExpanded ? 2.8 : 2.25),
        height: state.isExpanded ? 4 : 3,
        ratio: state.healthRatio,
        fillPaint: _healthPaint,
      );
      top += state.isExpanded ? 5 : 4;
    }

    if (state.showShieldBar) {
      _renderBar(
        canvas,
        centerX: centerX,
        y: top,
        width: radius * (state.isExpanded ? 2.8 : 2.25),
        height: 2.5,
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
    required GameTowerVarietySheet? towerVarietySheet,
  }) {
    const gap = 2.0;
    final totalWidth = (badges.length * size) + ((badges.length - 1) * gap);
    var x = centerX - (totalWidth / 2);

    for (final badge in badges) {
      final rect = Rect.fromLTWH(x, y, size, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        _badgeBackgroundPaint,
      );

      final sprite = _spriteForBadge(towerVarietySheet, badge);
      if (sprite == null) {
        _renderFallbackBadge(canvas, rect, badge);
      } else {
        sprite.render(
          canvas,
          position: Vector2(rect.left, rect.top),
          size: Vector2.all(size),
        );
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
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

  void _renderFallbackBadge(Canvas canvas, Rect rect, EnemyOverlayBadge badge) {
    final paint = Paint()..color = _fallbackColor(badge);
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
          RRect.fromRectAndRadius(insetRect, const Radius.circular(1.5)),
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

  Color _fallbackColor(EnemyOverlayBadge badge) {
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
