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
          !_appliesToTower(definition.affinity, stats.type)) {
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

  static bool _appliesToTower(
    RunModuleAffinity affinity,
    TowerType towerType,
  ) => switch (affinity) {
    RunModuleAffinity.universal => true,
    RunModuleAffinity.cryo => towerType == TowerType.cryo,
    RunModuleAffinity.rocket => towerType == TowerType.rocket,
  };
}
