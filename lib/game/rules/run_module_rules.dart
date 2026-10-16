import '../models/game_models.dart';

abstract final class RunModuleRules {
  static TowerStats applyTowerStats(
    TowerStats resolvedStats,
    Iterable<RunModuleId> acquiredModules,
  ) {
    final acquired = acquiredModules.toSet();
    var stats = resolvedStats;

    for (final definition in runModuleCatalog) {
      if (!acquired.contains(definition.id) ||
          !appliesToTower(definition.affinity, stats.type)) {
        continue;
      }

      stats = stats.copyWith(
        damage: stats.damage * definition.damageMultiplier,
        corrosionDamagePerSecond:
            stats.corrosionDamagePerSecond * definition.damageMultiplier,
        droneDamage: stats.droneDamage * definition.damageMultiplier,
        fireInterval: stats.fireInterval * definition.fireIntervalMultiplier,
        range: stats.range * definition.rangeMultiplier,
        splashRadius: stats.splashRadius * definition.splashRadiusMultiplier,
        slowDuration: stats.slowDuration + definition.slowDurationBonus,
      );
    }

    return stats;
  }

  /// Number of [towers] whose stats [definition] changes. Economy-only
  /// modules affect no towers.
  static int beneficiaryCount(
    RunModuleDefinition definition,
    Iterable<PlacedTower> towers,
  ) {
    if (!definition.affectsTowerStats) return 0;
    return towers
        .where((tower) => appliesToTower(definition.affinity, tower.type))
        .length;
  }

  static bool appliesToTower(RunModuleAffinity affinity, TowerType towerType) =>
      switch (affinity) {
        RunModuleAffinity.universal => true,
        RunModuleAffinity.cryo => towerType == TowerType.cryo,
        RunModuleAffinity.rocket => towerType == TowerType.rocket,
      };
}
