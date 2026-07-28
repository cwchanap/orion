import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

class OrionCampaign {
  const OrionCampaign._();

  static const String stageOneId = 'outpost-alpha';

  static final List<StageDefinition> stages = List.unmodifiable([
    StageDefinition(
      id: stageOneId,
      name: 'Outpost Alpha',
      mapLabel: 'Alpha',
      description: 'Baseline defense grid near the outer relay.',
      pathCells: BoardLayout.pathCells,
      waves: GameBalance.waves,
      unlockDependencies: const [],
      isMainPath: true,
      mainPathOrder: 1,
      mapColumn: 0,
      mapRow: 1,
    ),
    StageDefinition(
      id: 'nebula-relay',
      name: 'Nebula Relay',
      mapLabel: 'Relay',
      description: 'A curved approach through shield-heavy drone lanes.',
      pathCells: _nebulaRelayPath,
      waves: _nebulaRelayWaves,
      unlockDependencies: const [stageOneId],
      isMainPath: true,
      mainPathOrder: 2,
      mapColumn: 1,
      mapRow: 1,
      modifiers: const [StageModifier.shieldRecharge],
    ),
    StageDefinition(
      id: 'salvage-rift',
      name: 'Salvage Rift',
      mapLabel: 'Rift',
      description: 'Optional side route with fast salvage swarms.',
      pathCells: _salvageRiftPath,
      waves: _salvageRiftWaves,
      unlockDependencies: const ['nebula-relay'],
      isMainPath: false,
      mainPathOrder: null,
      reward: CampaignReward.bonusGold,
      mapColumn: 2,
      mapRow: 0,
      modifiers: const [StageModifier.swarmBounty],
    ),
    StageDefinition(
      id: 'asteroid-foundry',
      name: 'Asteroid Foundry',
      mapLabel: 'Foundry',
      description: 'Armored traffic crosses a long industrial lane.',
      pathCells: _asteroidFoundryPath,
      waves: _asteroidFoundryWaves,
      unlockDependencies: const ['nebula-relay'],
      isMainPath: true,
      mainPathOrder: 3,
      mapColumn: 2,
      mapRow: 1,
      modifiers: const [StageModifier.reinforcedArmor],
    ),
    StageDefinition(
      id: 'aurora-gate',
      name: 'Aurora Gate',
      mapLabel: 'Gate',
      description: 'Mixed shield and regen enemies split pressure windows.',
      pathCells: _auroraGatePath,
      waves: _auroraGateWaves,
      unlockDependencies: const ['asteroid-foundry'],
      isMainPath: true,
      mainPathOrder: 4,
      mapColumn: 3,
      mapRow: 1,
      modifiers: const [StageModifier.regenPressurePulses],
    ),
    StageDefinition(
      id: 'void-bastion',
      name: 'Void Bastion',
      mapLabel: 'Bastion',
      description: 'Optional fortress stage with heavy enemy groups.',
      pathCells: _voidBastionPath,
      waves: _voidBastionWaves,
      unlockDependencies: const ['aurora-gate'],
      isMainPath: false,
      mainPathOrder: null,
      reward: CampaignReward.bonusHealth,
      mapColumn: 4,
      mapRow: 2,
      modifiers: const [
        StageModifier.reducedStartingHealth,
        StageModifier.enhancedClearBonus,
      ],
    ),
    StageDefinition(
      id: 'singularity-core',
      name: 'Singularity Core',
      mapLabel: 'Core',
      description: 'Final main assault with every enemy counter in play.',
      pathCells: _singularityCorePath,
      waves: _singularityCoreWaves,
      unlockDependencies: const ['aurora-gate'],
      isMainPath: true,
      mainPathOrder: 5,
      mapColumn: 4,
      mapRow: 1,
      modifiers: const [
        StageModifier.enemySpeedSurge,
        StageModifier.amplifiedGravityWells,
      ],
    ),
  ]);

  static StageDefinition get stageOne => stageById(stageOneId);

  static List<StageDefinition> get mainStages {
    final sorted = stages
        .where((stage) => stage.isMainPath)
        .toList(growable: false);
    sorted.sort((a, b) => a.mainPathOrder!.compareTo(b.mainPathOrder!));
    return List.unmodifiable(sorted);
  }

  static List<StageDefinition> get sideStages {
    return List.unmodifiable(stages.where((stage) => !stage.isMainPath));
  }

  static StageDefinition stageById(String id) {
    try {
      return stages.firstWhere((stage) => stage.id == id);
    } on StateError {
      throw ArgumentError.value(id, 'id', 'Unknown stage id');
    }
  }

  static List<String> validate() {
    return validateStages(stages);
  }

  static List<String> validateStages(Iterable<StageDefinition> definitions) {
    final stageList = definitions.toList(growable: false);
    final mainStageList = stageList
        .where((stage) => stage.isMainPath)
        .toList(growable: false);
    final sideStageList = stageList
        .where((stage) => !stage.isMainPath)
        .toList(growable: false);
    final errors = <String>[];
    final ids = <String>{};

    for (final stage in stageList) {
      if (!ids.add(stage.id)) {
        errors.add('Duplicate stage id: ${stage.id}');
      }
    }

    if (stageList.length != 7) {
      errors.add('Campaign must contain exactly 7 stages.');
    }
    if (mainStageList.length != 5) {
      errors.add('Campaign must contain exactly 5 main stages.');
    }
    if (sideStageList.length != 2) {
      errors.add('Campaign must contain exactly 2 side stages.');
    }

    final mainPathOrders = <int>[];
    final seenMainPathOrders = <int>{};
    for (final stage in mainStageList) {
      final order = stage.mainPathOrder;
      if (order == null) {
        errors.add('${stage.id} main stage must have an order.');
        continue;
      }
      mainPathOrders.add(order);
      if (!seenMainPathOrders.add(order)) {
        errors.add('Duplicate main path order: $order.');
      }
    }
    for (final stage in sideStageList) {
      if (stage.mainPathOrder != null) {
        errors.add('${stage.id} side stage must not have an order.');
      }
    }
    errors.addAll(_validateRewards(mainStageList, sideStageList));
    final sortedMainPathOrders = mainPathOrders.toList(growable: false)..sort();
    if (!_listEquals(sortedMainPathOrders, const [1, 2, 3, 4, 5])) {
      errors.add('Main path orders must be exactly [1, 2, 3, 4, 5].');
    }

    for (final stage in stageList) {
      final seenModifiers = <StageModifier>{};
      for (final modifier in stage.modifiers) {
        if (!seenModifiers.add(modifier)) {
          errors.add(
            '${stage.id} contains duplicate modifier: ${modifier.name}.',
          );
        }
      }
      for (final dependency in stage.unlockDependencies) {
        if (!ids.contains(dependency)) {
          errors.add('${stage.id} depends on unknown stage $dependency.');
        }
      }
      if (stage.waves.length != 8) {
        errors.add('${stage.id} must define exactly 8 waves.');
      }
      if (stage.pathCells.length < 2) {
        errors.add('${stage.id} must define at least 2 path cells.');
      }
      for (final position in stage.pathCells) {
        if (!BoardLayout.isInBounds(position)) {
          errors.add('${stage.id} has out-of-bounds path cell $position.');
        }
      }
      for (var index = 1; index < stage.pathCells.length; index += 1) {
        if (stage.pathCells[index - 1].distanceTo(stage.pathCells[index]) !=
            1) {
          errors.add('${stage.id} path is not continuous at index $index.');
        }
      }
      final bossGroups = <int>[];
      for (var w = 0; w < stage.waves.length; w++) {
        for (final g in stage.waves[w].groups) {
          if (g.enemyStats is BossDefinition) bossGroups.add(w);
        }
      }
      if (bossGroups.length != 1) {
        errors.add(
          '${stage.id} must have exactly one boss group; found ${bossGroups.length}.',
        );
      } else if (bossGroups.single != stage.waves.length - 1) {
        errors.add('${stage.id} boss must be in the final wave.');
      } else {
        final lastGroup = stage.waves.last.groups.last;
        if (lastGroup.enemyStats is! BossDefinition) {
          errors.add(
            '${stage.id} boss must be the final group of the final wave.',
          );
        } else if (lastGroup.enemyCount != 1) {
          errors.add('${stage.id} boss group must have enemyCount 1.');
        }
      }
    }

    return List.unmodifiable(errors);
  }

  static List<String> _validateRewards(
    List<StageDefinition> mainStageList,
    List<StageDefinition> sideStageList,
  ) {
    final errors = <String>[];
    for (final stage in mainStageList) {
      if (stage.reward != null) {
        errors.add('${stage.id} main stage must not have a reward.');
      }
    }
    final statRewardCounts = <CampaignReward, int>{};
    for (final stage in sideStageList) {
      final reward = stage.reward;
      if (reward == null) {
        errors.add('${stage.id} side stage must have a reward.');
      } else if (reward == CampaignReward.challengeBadge) {
        errors.add(
          '${stage.id} must not carry challengeBadge; it is compound-derived.',
        );
      } else {
        statRewardCounts[reward] = (statRewardCounts[reward] ?? 0) + 1;
      }
    }
    for (final entry in statRewardCounts.entries) {
      if (entry.value > 1) {
        errors.add(
          '${entry.key} reward appears on ${entry.value} stages; expected at most one.',
        );
      }
    }
    return errors;
  }
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

const _nebulaRelayPath = [
  GridPosition(0, 2),
  GridPosition(1, 2),
  GridPosition(2, 2),
  GridPosition(2, 3),
  GridPosition(2, 4),
  GridPosition(3, 4),
  GridPosition(4, 4),
  GridPosition(4, 5),
  GridPosition(4, 6),
  GridPosition(5, 6),
  GridPosition(6, 6),
  GridPosition(6, 7),
  GridPosition(6, 8),
  GridPosition(5, 8),
  GridPosition(4, 8),
  GridPosition(3, 8),
  GridPosition(3, 9),
  GridPosition(3, 10),
  GridPosition(4, 10),
  GridPosition(5, 10),
  GridPosition(6, 10),
  GridPosition(7, 10),
];

const _asteroidFoundryPath = [
  GridPosition(0, 0),
  GridPosition(1, 0),
  GridPosition(1, 1),
  GridPosition(1, 2),
  GridPosition(2, 2),
  GridPosition(3, 2),
  GridPosition(4, 2),
  GridPosition(4, 3),
  GridPosition(4, 4),
  GridPosition(3, 4),
  GridPosition(2, 4),
  GridPosition(1, 4),
  GridPosition(1, 5),
  GridPosition(1, 6),
  GridPosition(2, 6),
  GridPosition(3, 6),
  GridPosition(4, 6),
  GridPosition(5, 6),
  GridPosition(5, 7),
  GridPosition(5, 8),
  GridPosition(6, 8),
  GridPosition(7, 8),
  GridPosition(7, 9),
];

const _auroraGatePath = [
  GridPosition(0, 3),
  GridPosition(1, 3),
  GridPosition(2, 3),
  GridPosition(3, 3),
  GridPosition(4, 3),
  GridPosition(5, 3),
  GridPosition(5, 4),
  GridPosition(5, 5),
  GridPosition(4, 5),
  GridPosition(3, 5),
  GridPosition(2, 5),
  GridPosition(2, 6),
  GridPosition(2, 7),
  GridPosition(3, 7),
  GridPosition(4, 7),
  GridPosition(5, 7),
  GridPosition(6, 7),
  GridPosition(6, 8),
  GridPosition(6, 9),
  GridPosition(5, 9),
  GridPosition(4, 9),
  GridPosition(4, 10),
  GridPosition(5, 10),
  GridPosition(6, 10),
  GridPosition(7, 10),
];

const _singularityCorePath = [
  GridPosition(0, 1),
  GridPosition(0, 2),
  GridPosition(1, 2),
  GridPosition(2, 2),
  GridPosition(3, 2),
  GridPosition(4, 2),
  GridPosition(4, 3),
  GridPosition(4, 4),
  GridPosition(5, 4),
  GridPosition(6, 4),
  GridPosition(7, 4),
  GridPosition(7, 5),
  GridPosition(6, 5),
  GridPosition(5, 5),
  GridPosition(4, 5),
  GridPosition(3, 5),
  GridPosition(2, 5),
  GridPosition(1, 5),
  GridPosition(1, 6),
  GridPosition(1, 7),
  GridPosition(2, 7),
  GridPosition(3, 7),
  GridPosition(4, 7),
  GridPosition(5, 7),
  GridPosition(5, 8),
  GridPosition(5, 9),
  GridPosition(6, 9),
  GridPosition(7, 9),
];

const _salvageRiftPath = [
  GridPosition(0, 10),
  GridPosition(1, 10),
  GridPosition(1, 9),
  GridPosition(1, 8),
  GridPosition(2, 8),
  GridPosition(3, 8),
  GridPosition(3, 7),
  GridPosition(3, 6),
  GridPosition(4, 6),
  GridPosition(5, 6),
  GridPosition(5, 5),
  GridPosition(5, 4),
  GridPosition(6, 4),
  GridPosition(7, 4),
];

const _voidBastionPath = [
  GridPosition(0, 5),
  GridPosition(1, 5),
  GridPosition(2, 5),
  GridPosition(2, 4),
  GridPosition(2, 3),
  GridPosition(3, 3),
  GridPosition(4, 3),
  GridPosition(4, 4),
  GridPosition(4, 5),
  GridPosition(5, 5),
  GridPosition(6, 5),
  GridPosition(6, 6),
  GridPosition(6, 7),
  GridPosition(5, 7),
  GridPosition(4, 7),
  GridPosition(4, 8),
  GridPosition(4, 9),
  GridPosition(5, 9),
  GridPosition(6, 9),
  GridPosition(7, 9),
];

final _nebulaRelayWaves = _waves([
  _group(10, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.basicDrone),
  _group(8, EnemyArchetype.shieldedDrone),
  _group(18, EnemyArchetype.swarmDrone),
  _group(10, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
], finaleBoss: GameBalance.shieldMatriarch);

final _asteroidFoundryWaves = _waves([
  _group(8, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.armoredDrone),
  _group(8, EnemyArchetype.armoredDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.heavyDrone),
  _group(10, EnemyArchetype.armoredDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(10, EnemyArchetype.armoredHeavyDrone),
], finaleBoss: GameBalance.armoredExcavator);

final _auroraGateWaves = _waves([
  _group(8, EnemyArchetype.basicDrone),
  _group(4, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.regenDrone),
  _group(6, EnemyArchetype.armoredDrone),
  _group(10, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
], finaleBoss: GameBalance.regenWarden);

final _singularityCoreWaves = _waves([
  _group(10, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.armoredDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(20, EnemyArchetype.swarmDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(10, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
], finaleBoss: GameBalance.singularityCore);

final _salvageRiftWaves = _waves([
  _group(14, EnemyArchetype.swarmDrone),
  _group(18, EnemyArchetype.swarmDrone),
  _group(8, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(24, EnemyArchetype.swarmDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(10, EnemyArchetype.swarmDrone),
  _group(6, EnemyArchetype.heavyDrone),
], finaleBoss: GameBalance.swarmQueen);

final _voidBastionWaves = _waves([
  _group(6, EnemyArchetype.armoredDrone),
  _group(8, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.heavyDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
  _group(10, EnemyArchetype.armoredHeavyDrone),
  _group(8, EnemyArchetype.regenHeavyDrone),
], finaleBoss: GameBalance.siegeCarrier);

List<WaveDefinition> _waves(
  List<WaveGroup> singleGroups, {
  BossDefinition? finaleBoss,
  double bossInitialDelay = 2.5,
}) {
  const clearBonuses = [30, 40, 50, 65, 80, 95, 115, 0];
  return List.unmodifiable([
    for (var index = 0; index < singleGroups.length; index += 1)
      WaveDefinition(
        groups: List.unmodifiable(
          index == singleGroups.length - 1 && finaleBoss != null
              ? [
                  singleGroups[index],
                  WaveGroup(
                    enemyCount: 1,
                    enemyStats: finaleBoss,
                    initialDelay: bossInitialDelay,
                  ),
                ]
              : [singleGroups[index]],
        ),
        clearBonus: clearBonuses[index],
      ),
  ]);
}

WaveGroup _group(int count, EnemyArchetype archetype) {
  return WaveGroup(
    enemyCount: count,
    enemyStats: GameBalance.enemyArchetype(archetype),
    spawnInterval: switch (archetype) {
      EnemyArchetype.swarmDrone => 0.35,
      EnemyArchetype.armoredHeavyDrone ||
      EnemyArchetype.regenHeavyDrone ||
      EnemyArchetype.heavyDrone => 1.20,
      EnemyArchetype.shieldedDrone => 0.90,
      EnemyArchetype.armoredDrone || EnemyArchetype.regenDrone => 1.00,
      EnemyArchetype.basicEliteDrone => 0.75,
      EnemyArchetype.basicDrone => 0.85,
    },
  );
}
