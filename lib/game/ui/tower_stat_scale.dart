import 'dart:math' as math;

import '../models/game_models.dart';

enum TowerSecondaryMetric {
  slowDuration,
  splashRadius,
  corrosionDamagePerSecond,
  droneDamage,
}

extension TowerSecondaryMetricValue on TowerSecondaryMetric {
  double valueOf(TowerStats stats) => switch (this) {
    TowerSecondaryMetric.slowDuration => stats.slowDuration,
    TowerSecondaryMetric.splashRadius => stats.splashRadius,
    TowerSecondaryMetric.corrosionDamagePerSecond =>
      stats.corrosionDamagePerSecond,
    TowerSecondaryMetric.droneDamage => stats.droneDamage,
  };
}

final class TowerStatScale {
  const TowerStatScale({
    required this.damageMax,
    required this.shotsPerSecondMax,
    required this.rangeMax,
    required this.secondaryMetric,
    required this.secondaryMax,
  });

  final double damageMax;
  final double shotsPerSecondMax;
  final double rangeMax;
  final TowerSecondaryMetric? secondaryMetric;
  final double? secondaryMax;

  static final Map<TowerType, TowerStatScale> _byType = {
    for (final type in TowerType.values) type: _build(type),
  };

  static TowerStatScale forType(TowerType type) => _byType[type]!;

  static TowerStatScale _build(TowerType type) {
    final candidates = [
      GameBalance.towerStats(type, level: 1),
      GameBalance.towerStats(type, level: 2),
      for (final specialization in GameBalance.specializationsFor(type))
        GameBalance.towerStats(type, level: 3, specialization: specialization),
    ];
    final secondaryMetric = switch (type) {
      TowerType.cryo => TowerSecondaryMetric.slowDuration,
      TowerType.rocket => TowerSecondaryMetric.splashRadius,
      TowerType.nanite => TowerSecondaryMetric.corrosionDamagePerSecond,
      TowerType.droneBay => TowerSecondaryMetric.droneDamage,
      TowerType.laser ||
      TowerType.railgun ||
      TowerType.ionChain ||
      TowerType.gravityWell => null,
    };
    return TowerStatScale(
      damageMax: candidates.map((stats) => stats.damage).reduce(math.max),
      shotsPerSecondMax: candidates
          .map((stats) => 1 / stats.fireInterval)
          .reduce(math.max),
      rangeMax: candidates.map((stats) => stats.range).reduce(math.max),
      secondaryMetric: secondaryMetric,
      secondaryMax: secondaryMetric == null
          ? null
          : candidates
                .map((stats) => secondaryMetric.valueOf(stats))
                .reduce(math.max),
    );
  }

  double damageFill(TowerStats stats) => _fill(stats.damage, damageMax);

  double fireFill(TowerStats stats) =>
      _fill(1 / stats.fireInterval, shotsPerSecondMax);

  double rangeFill(TowerStats stats) => _fill(stats.range, rangeMax);

  double? secondaryFill(TowerStats stats) {
    final metric = secondaryMetric;
    final maximum = secondaryMax;
    return metric == null || maximum == null
        ? null
        : _fill(metric.valueOf(stats), maximum);
  }

  static double _fill(double value, double maximum) =>
      maximum <= 0 ? 0 : (value / maximum).clamp(0, 1).toDouble();
}
