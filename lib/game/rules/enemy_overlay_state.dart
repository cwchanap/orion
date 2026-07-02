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
    final ratio = value / maxValue;
    if (ratio.isNaN) {
      return 0;
    }
    return ratio.clamp(0, 1).toDouble();
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

/// Pure layout computation for [EnemyOverlayRenderer].
///
/// Computes the vertical positions and sizes of every overlay element from the
/// [EnemyOverlayState] and an enemy `radius`. The renderer consumes this layout
/// directly so the painting layer holds no derivation logic, and tests can
/// assert on computed geometry without rasterizing pixels.
class EnemyOverlayLayout {
  const EnemyOverlayLayout._({
    required this.originY,
    required this.badgesY,
    required this.badgeSize,
    required this.badgeGap,
    required this.badgeCornerRadius,
    required this.heavyBadgeCornerRadius,
    required this.healthBarY,
    required this.healthBarWidth,
    required this.healthBarHeight,
    required this.shieldBarY,
    required this.shieldBarWidth,
    required this.shieldBarHeight,
    required this.height,
  });

  static const double _normalBadgeSizeFactor = 0.6363636364;
  static const double _expandedBadgeSizeFactor = 0.8181818182;
  static const double _badgeGapFactor = 0.1818181818;
  static const double _normalBadgeAdvanceFactor = 0.8181818182;
  static const double _expandedBadgeAdvanceFactor = 1;
  static const double _normalHealthBarHeightFactor = 0.2727272727;
  static const double _expandedHealthBarHeightFactor = 0.3636363636;
  static const double _normalHealthBarAdvanceFactor = 0.3636363636;
  static const double _expandedHealthBarAdvanceFactor = 0.4545454545;
  static const double _shieldBarHeightFactor = 0.2272727273;
  static const double _badgeCornerRadiusFactor = 0.1818181818;
  static const double _heavyBadgeCornerRadiusFactor = 0.1363636364;
  static const double _normalBarWidthFactor = 2.25;
  static const double _expandedBarWidthFactor = 2.8;
  static const double _normalOriginFactor = 0.72;
  static const double _expandedOriginFactor = 0.92;

  /// Top of the overlay region, measured relative to the enemy center.
  final double originY;

  /// Top of the badge row, or `null` when no badges are drawn.
  final double? badgesY;
  final double badgeSize;
  final double badgeGap;
  final double badgeCornerRadius;
  final double heavyBadgeCornerRadius;

  /// Top of the health bar, or `null` when it is not drawn.
  final double? healthBarY;
  final double healthBarWidth;
  final double healthBarHeight;

  /// Top of the shield bar, or `null` when it is not drawn.
  final double? shieldBarY;
  final double shieldBarWidth;
  final double shieldBarHeight;

  /// Bounding height of all drawn elements, measured from the top of the first
  /// element to the bottom of the last. `0` when nothing is drawn.
  final double height;

  factory EnemyOverlayLayout.compute(EnemyOverlayState state, double radius) {
    if (!state.shouldRender) {
      return const EnemyOverlayLayout._(
        originY: 0,
        badgesY: null,
        badgeSize: 0,
        badgeGap: 0,
        badgeCornerRadius: 0,
        heavyBadgeCornerRadius: 0,
        healthBarY: null,
        healthBarWidth: 0,
        healthBarHeight: 0,
        shieldBarY: null,
        shieldBarWidth: 0,
        shieldBarHeight: 0,
        height: 0,
      );
    }

    final isExpanded = state.isExpanded;
    final originY =
        -radius * (isExpanded ? _expandedOriginFactor : _normalOriginFactor);
    var cursor = originY;
    double? firstTop;
    double lastBottom = originY;

    double? badgesY;
    double badgeSize = 0;
    double badgeGap = 0;
    double badgeCornerRadius = 0;
    double heavyBadgeCornerRadius = 0;
    if (state.badges.isNotEmpty) {
      badgesY = cursor;
      firstTop ??= cursor;
      badgeSize =
          radius *
          (isExpanded ? _expandedBadgeSizeFactor : _normalBadgeSizeFactor);
      badgeGap = radius * _badgeGapFactor;
      badgeCornerRadius = radius * _badgeCornerRadiusFactor;
      heavyBadgeCornerRadius = radius * _heavyBadgeCornerRadiusFactor;
      lastBottom = cursor + badgeSize;
      cursor +=
          radius *
          (isExpanded
              ? _expandedBadgeAdvanceFactor
              : _normalBadgeAdvanceFactor);
    }

    double? healthBarY;
    double healthBarWidth = 0;
    double healthBarHeight = 0;
    if (state.showHealthBar) {
      healthBarY = cursor;
      firstTop ??= cursor;
      healthBarWidth =
          radius *
          (isExpanded ? _expandedBarWidthFactor : _normalBarWidthFactor);
      healthBarHeight =
          radius *
          (isExpanded
              ? _expandedHealthBarHeightFactor
              : _normalHealthBarHeightFactor);
      lastBottom = cursor + healthBarHeight;
      cursor +=
          radius *
          (isExpanded
              ? _expandedHealthBarAdvanceFactor
              : _normalHealthBarAdvanceFactor);
    }

    double? shieldBarY;
    double shieldBarWidth = 0;
    double shieldBarHeight = 0;
    if (state.showShieldBar) {
      shieldBarY = cursor;
      firstTop ??= cursor;
      shieldBarWidth =
          radius *
          (isExpanded ? _expandedBarWidthFactor : _normalBarWidthFactor);
      shieldBarHeight = radius * _shieldBarHeightFactor;
      lastBottom = cursor + shieldBarHeight;
    }

    return EnemyOverlayLayout._(
      originY: originY,
      badgesY: badgesY,
      badgeSize: badgeSize,
      badgeGap: badgeGap,
      badgeCornerRadius: badgeCornerRadius,
      heavyBadgeCornerRadius: heavyBadgeCornerRadius,
      healthBarY: healthBarY,
      healthBarWidth: healthBarWidth,
      healthBarHeight: healthBarHeight,
      shieldBarY: shieldBarY,
      shieldBarWidth: shieldBarWidth,
      shieldBarHeight: shieldBarHeight,
      height: firstTop == null ? 0 : lastBottom - firstTop,
    );
  }
}
