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
  const EnemyOverlayData({
    required this.isResolved,
    this.isInspected = false,
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
  const EnemyOverlayState({
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
      return const EnemyOverlayState(
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

    return EnemyOverlayState(
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
