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
          !appliesToTower(definition, stats.type)) {
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
        chainCount: stats.chainCount + definition.chainCountBonus,
        pierceCount: stats.pierceCount + definition.pierceCountBonus,
        fieldRadius: stats.fieldRadius * definition.fieldRadiusMultiplier,
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
        .where((tower) => appliesToTower(definition, tower.type))
        .length;
  }

  static bool appliesToTower(
    RunModuleDefinition definition,
    TowerType towerType,
  ) => definition.tower == null || definition.tower == towerType;
}
