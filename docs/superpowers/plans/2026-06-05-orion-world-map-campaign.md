# Orion World Map Campaign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a locally persisted seven-stage branching world map where each unlocked node launches a fresh eight-wave Orion TD mission with stage-specific paths and waves.

**Architecture:** Add pure campaign and stage-definition files that sit over the existing mission rules. Thread a selected `StageDefinition` through `GameSession`, `BoardLayout`, `BoardComponent`, and `OrionDefenseGame`, then wrap the mission in a map-first Flutter shell that persists cleared stage ids with `shared_preferences`.

**Tech Stack:** Flutter, Flame, Dart 3.12, `flutter_test`, `shared_preferences`.

---

## File Structure

- Create `lib/game/campaign/stage_definition.dart`: pure `StageDefinition` data model.
- Create `lib/game/campaign/campaign_progress.dart`: pure progress/unlock/complete logic.
- Create `lib/game/campaign/orion_campaign.dart`: static seven-stage campaign graph, path data, stage wave data, and validation.
- Create `lib/game/campaign/campaign_progress_store.dart`: JSON codec plus `shared_preferences` storage adapter.
- Create `lib/game/ui/world_map_view.dart`: map-first campaign UI widget.
- Modify `pubspec.yaml`: add `shared_preferences`.
- Modify `lib/game/models/game_models.dart`: add stage label/name and wave total to `GameSnapshot`.
- Modify `lib/game/rules/board_layout.dart`: keep current default path, add optional path-aware helpers.
- Modify `lib/game/rules/game_session.dart`: accept a `StageDefinition`, use stage waves/path for mission rules.
- Modify `lib/game/components/board_component.dart`: render the selected stage path instead of the global default.
- Modify `lib/game/orion_defense_game.dart`: accept a selected stage and callbacks for stage clear / map return.
- Modify `lib/game/ui/orion_game_page.dart`: become the campaign shell that loads progress, shows map first, launches missions, saves clears, and resets.
- Modify tests under `test/game/` and `test/widget_test.dart`; create focused campaign tests.

---

### Task 1: Add Pure Stage And Campaign Progress Models

**Files:**
- Create: `lib/game/campaign/stage_definition.dart`
- Create: `lib/game/campaign/campaign_progress.dart`
- Test: `test/game/campaign_progress_test.dart`

- [ ] **Step 1: Write the failing campaign progress tests**

Create `test/game/campaign_progress_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('CampaignProgress', () {
    final stages = [
      _stage(id: 'stage-1', mainPathOrder: 1),
      _stage(id: 'stage-2', dependencies: ['stage-1'], mainPathOrder: 2),
      _stage(id: 'stage-3', dependencies: ['stage-2'], mainPathOrder: 3),
      _stage(id: 'stage-4', dependencies: ['stage-3'], mainPathOrder: 4),
      _stage(id: 'stage-5', dependencies: ['stage-4'], mainPathOrder: 5),
      _stage(id: 'side-a', dependencies: ['stage-2'], isMainPath: false),
      _stage(id: 'side-b', dependencies: ['stage-4'], isMainPath: false),
    ];

    test('unlocks stage one by default and derives locked stages', () {
      const progress = CampaignProgress();

      expect(progress.isCleared('stage-1'), isFalse);
      expect(progress.isUnlocked(stages[0]), isTrue);
      expect(progress.isUnlocked(stages[1]), isFalse);
      expect(progress.statusFor(stages[0]), StageProgressStatus.unlocked);
      expect(progress.statusFor(stages[1]), StageProgressStatus.locked);
    });

    test('unlocks main path and side stages from cleared milestones', () {
      const progress = CampaignProgress(
        clearedStageIds: {'stage-1', 'stage-2', 'stage-3', 'stage-4'},
      );

      expect(progress.isUnlocked(stages[4]), isTrue);
      expect(progress.isUnlocked(stages[5]), isTrue);
      expect(progress.isUnlocked(stages[6]), isTrue);
      expect(progress.statusFor(stages[0]), StageProgressStatus.cleared);
    });

    test('completes campaign when all main stages are cleared', () {
      const withoutSideStages = CampaignProgress(
        clearedStageIds: {
          'stage-1',
          'stage-2',
          'stage-3',
          'stage-4',
          'stage-5',
        },
      );

      expect(withoutSideStages.isCampaignComplete(stages), isTrue);
    });

    test('markCleared returns normalized immutable progress', () {
      const progress = CampaignProgress(clearedStageIds: {'stage-1'});

      final updated = progress.markCleared('stage-2');

      expect(updated.clearedStageIds, {'stage-1', 'stage-2'});
      expect(progress.clearedStageIds, {'stage-1'});
      expect(
        () => updated.clearedStageIds.add('stage-3'),
        throwsUnsupportedError,
      );
    });
  });
}

StageDefinition _stage({
  required String id,
  List<String> dependencies = const [],
  bool isMainPath = true,
  int? mainPathOrder,
}) {
  return StageDefinition(
    id: id,
    name: id,
    mapLabel: id,
    description: id,
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: GameBalance.waves,
    unlockDependencies: dependencies,
    isMainPath: isMainPath,
    mainPathOrder: mainPathOrder,
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/game/campaign_progress_test.dart
```

Expected: FAIL because `orion/game/campaign/campaign_progress.dart` and `stage_definition.dart` do not exist.

- [ ] **Step 3: Add `StageDefinition`**

Create `lib/game/campaign/stage_definition.dart`:

```dart
import '../models/game_models.dart';

class StageDefinition {
  const StageDefinition({
    required this.id,
    required this.name,
    required this.mapLabel,
    required this.description,
    required this.pathCells,
    required this.waves,
    required this.unlockDependencies,
    required this.isMainPath,
    required this.mainPathOrder,
    required this.mapColumn,
    required this.mapRow,
  });

  final String id;
  final String name;
  final String mapLabel;
  final String description;
  final List<GridPosition> pathCells;
  final List<WaveDefinition> waves;
  final List<String> unlockDependencies;
  final bool isMainPath;
  final int? mainPathOrder;
  final int mapColumn;
  final int mapRow;
}
```

- [ ] **Step 4: Add `CampaignProgress`**

Create `lib/game/campaign/campaign_progress.dart`:

```dart
import 'stage_definition.dart';

enum StageProgressStatus { locked, unlocked, cleared }

class CampaignProgress {
  const CampaignProgress({Set<String> clearedStageIds = const {}})
    : _clearedStageIds = clearedStageIds;

  final Set<String> _clearedStageIds;

  Set<String> get clearedStageIds => Set.unmodifiable(_clearedStageIds);

  bool isCleared(String stageId) => _clearedStageIds.contains(stageId);

  bool isUnlocked(StageDefinition stage) {
    if (stage.unlockDependencies.isEmpty) {
      return true;
    }
    return stage.unlockDependencies.every(_clearedStageIds.contains);
  }

  StageProgressStatus statusFor(StageDefinition stage) {
    if (isCleared(stage.id)) {
      return StageProgressStatus.cleared;
    }
    if (isUnlocked(stage)) {
      return StageProgressStatus.unlocked;
    }
    return StageProgressStatus.locked;
  }

  CampaignProgress markCleared(String stageId) {
    return CampaignProgress(
      clearedStageIds: {..._clearedStageIds, stageId},
    );
  }

  CampaignProgress withoutUnknownStages(Iterable<StageDefinition> stages) {
    final knownIds = stages.map((stage) => stage.id).toSet();
    return CampaignProgress(
      clearedStageIds: _clearedStageIds.intersection(knownIds),
    );
  }

  bool isCampaignComplete(Iterable<StageDefinition> stages) {
    final mainStageIds = stages
        .where((stage) => stage.isMainPath)
        .map((stage) => stage.id);
    return mainStageIds.every(_clearedStageIds.contains);
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
flutter test test/game/campaign_progress_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/game/campaign/stage_definition.dart lib/game/campaign/campaign_progress.dart test/game/campaign_progress_test.dart
git commit -m "feat: add Orion campaign progress models"
```

---

### Task 2: Add Static Orion Campaign Definition And Validation

**Files:**
- Create: `lib/game/campaign/orion_campaign.dart`
- Test: `test/game/orion_campaign_test.dart`

- [ ] **Step 1: Write failing campaign definition tests**

Create `test/game/orion_campaign_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  group('OrionCampaign', () {
    test('defines seven stages with five main and two side stages', () {
      expect(OrionCampaign.stages, hasLength(7));
      expect(OrionCampaign.mainStages, hasLength(5));
      expect(OrionCampaign.sideStages, hasLength(2));
      expect(OrionCampaign.stageOne.id, 'outpost-alpha');
    });

    test('defines approved unlock graph', () {
      expect(OrionCampaign.stageById('outpost-alpha').unlockDependencies, []);
      expect(OrionCampaign.stageById('nebula-relay').unlockDependencies, [
        'outpost-alpha',
      ]);
      expect(OrionCampaign.stageById('salvage-rift').unlockDependencies, [
        'nebula-relay',
      ]);
      expect(OrionCampaign.stageById('void-bastion').unlockDependencies, [
        'aurora-gate',
      ]);
    });

    test('each stage has eight waves and in-bounds continuous path cells', () {
      for (final stage in OrionCampaign.stages) {
        expect(stage.waves, hasLength(8), reason: stage.id);
        expect(stage.pathCells.length, greaterThanOrEqualTo(2));
        for (final position in stage.pathCells) {
          expect(BoardLayout.isInBounds(position), isTrue, reason: stage.id);
        }
        for (var index = 1; index < stage.pathCells.length; index += 1) {
          expect(
            stage.pathCells[index - 1].distanceTo(stage.pathCells[index]),
            1,
            reason: stage.id,
          );
        }
      }
    });

    test('stage one keeps the current baseline path and waves', () {
      final stage = OrionCampaign.stageOne;

      expect(stage.pathCells, BoardLayout.pathCells);
      expect(stage.waves, GameBalance.waves);
    });

    test('validation returns no errors for shipped campaign data', () {
      expect(OrionCampaign.validate(), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/game/orion_campaign_test.dart
```

Expected: FAIL because `orion_campaign.dart` does not exist.

- [ ] **Step 3: Add static campaign data**

Create `lib/game/campaign/orion_campaign.dart`:

```dart
import '../models/game_models.dart';
import '../rules/board_layout.dart';
import 'stage_definition.dart';

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
      mapColumn: 2,
      mapRow: 0,
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
      mapColumn: 4,
      mapRow: 2,
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
    ),
  ]);

  static StageDefinition get stageOne => stages.first;

  static List<StageDefinition> get mainStages => stages
      .where((stage) => stage.isMainPath)
      .toList(growable: false)
    ..sort((a, b) => a.mainPathOrder!.compareTo(b.mainPathOrder!));

  static List<StageDefinition> get sideStages => stages
      .where((stage) => !stage.isMainPath)
      .toList(growable: false);

  static StageDefinition stageById(String id) {
    return stages.firstWhere((stage) => stage.id == id);
  }

  static List<String> validate() {
    final errors = <String>[];
    final ids = <String>{};
    for (final stage in stages) {
      if (!ids.add(stage.id)) {
        errors.add('Duplicate stage id: ${stage.id}');
      }
    }

    if (stages.length != 7) {
      errors.add('Campaign must contain exactly 7 stages.');
    }
    if (mainStages.length != 5) {
      errors.add('Campaign must contain exactly 5 main stages.');
    }
    if (sideStages.length != 2) {
      errors.add('Campaign must contain exactly 2 side stages.');
    }

    for (final stage in stages) {
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
    }

    return errors;
  }
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
]);

final _asteroidFoundryWaves = _waves([
  _group(8, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.armoredDrone),
  _group(8, EnemyArchetype.armoredDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.heavyDrone),
  _group(10, EnemyArchetype.armoredDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(10, EnemyArchetype.armoredHeavyDrone),
]);

final _auroraGateWaves = _waves([
  _group(8, EnemyArchetype.basicDrone),
  _group(4, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.regenDrone),
  _group(6, EnemyArchetype.armoredDrone),
  _group(10, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
]);

final _singularityCoreWaves = _waves([
  _group(10, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.armoredDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(20, EnemyArchetype.swarmDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(10, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
]);

final _salvageRiftWaves = _waves([
  _group(14, EnemyArchetype.swarmDrone),
  _group(18, EnemyArchetype.swarmDrone),
  _group(8, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(24, EnemyArchetype.swarmDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(10, EnemyArchetype.swarmDrone),
  _group(6, EnemyArchetype.heavyDrone),
]);

final _voidBastionWaves = _waves([
  _group(6, EnemyArchetype.armoredDrone),
  _group(8, EnemyArchetype.shieldedDrone),
  _group(6, EnemyArchetype.heavyDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(8, EnemyArchetype.armoredHeavyDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
  _group(10, EnemyArchetype.armoredHeavyDrone),
  _group(8, EnemyArchetype.regenHeavyDrone),
]);

List<WaveDefinition> _waves(List<WaveGroup> singleGroups) {
  const clearBonuses = [30, 40, 50, 65, 80, 95, 115, 0];
  return List.unmodifiable([
    for (var index = 0; index < singleGroups.length; index += 1)
      WaveDefinition(groups: [singleGroups[index]], clearBonus: clearBonuses[index]),
  ]);
}

WaveGroup _group(int count, EnemyArchetype archetype) {
  final stats = GameBalance.enemyArchetype(archetype);
  return WaveGroup(
    enemyCount: count,
    enemyStats: stats,
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
```

- [ ] **Step 4: Run tests and format**

Run:

```bash
dart format lib/game/campaign test/game/orion_campaign_test.dart
flutter test test/game/orion_campaign_test.dart test/game/campaign_progress_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/game/campaign/orion_campaign.dart test/game/orion_campaign_test.dart
git commit -m "feat: define Orion campaign stages"
```

---

### Task 3: Make Board Layout And GameSession Stage-Aware

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/board_layout.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `test/game/board_layout_test.dart`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Add failing tests for selected stage data**

Append these tests to `test/game/game_session_test.dart` inside the `GameSession` group:

```dart
    test('uses selected stage waves for mission progress', () {
      final stage = StageDefinition(
        id: 'test-stage',
        name: 'Test Stage',
        mapLabel: 'Test',
        description: 'Test stage',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: GameBalance.waves.take(2).toList(growable: false),
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );
      final session = GameSession.initial(stage: stage);

      expect(session.stage, stage);
      expect(session.snapshot().stageName, 'Test Stage');
      expect(session.snapshot().stageLabel, 'Test');
      expect(session.snapshot().waveTotal, 2);

      expect(session.startWave(), isTrue);
      session.finishActiveWave();
      expect(session.phase, GamePhase.build);

      expect(session.startWave(), isTrue);
      session.finishActiveWave();
      expect(session.phase, GamePhase.won);
      expect(session.waveIndex, 2);
    });

    test('uses selected stage path for placement blocking', () {
      final stage = StageDefinition(
        id: 'path-stage',
        name: 'Path Stage',
        mapLabel: 'Path',
        description: 'Test stage',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: GameBalance.waves,
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );
      final session = GameSession.initial(stage: stage);

      expect(
        session.validatePlacement(const GridPosition(0, 0), TowerType.laser).failure,
        PlacementFailure.pathBlocked,
      );
      expect(
        session.validatePlacement(const GridPosition(0, 1), TowerType.laser).isAllowed,
        isTrue,
      );
    });
```

Add imports to the top of `test/game/game_session_test.dart`:

```dart
import 'package:orion/game/campaign/stage_definition.dart';
```

Update `test/widget_test.dart` expectations for the new snapshot fields:

```dart
  test('snapshot exposes stage identity and wave total', () {
    final snapshot = GameSession.initial().snapshot();

    expect(snapshot.stageName, 'Outpost Alpha');
    expect(snapshot.stageLabel, 'Alpha');
    expect(snapshot.waveTotal, 8);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/game/game_session_test.dart test/widget_test.dart
```

Expected: FAIL because `GameSession.initial` has no `stage` parameter and `GameSnapshot` has no stage fields.

- [ ] **Step 3: Extend `GameSnapshot`**

Modify `GameSnapshot` in `lib/game/models/game_models.dart`:

```dart
class GameSnapshot {
  GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.waveNumber,
    required this.waveTotal,
    required this.stageName,
    required this.stageLabel,
    required List<TowerType> unlockedTowerTypes,
    required this.selectedCell,
    required this.selectedTower,
    required this.feedback,
  }) : unlockedTowerTypes = List.unmodifiable(unlockedTowerTypes);

  final GamePhase phase;
  final int gold;
  final int baseHealth;
  final int waveNumber;
  final int waveTotal;
  final String stageName;
  final String stageLabel;
  final List<TowerType> unlockedTowerTypes;
  final GridPosition? selectedCell;
  final PlacedTower? selectedTower;
  final String? feedback;

  bool get canStartWave => phase == GamePhase.build;
  bool get isEnded => phase == GamePhase.won || phase == GamePhase.lost;
}
```

- [ ] **Step 4: Update `BoardLayout` with path-aware helpers**

Modify `lib/game/rules/board_layout.dart`:

```dart
  static bool isPathCell(
    GridPosition position, {
    List<GridPosition>? pathCells,
  }) {
    return (pathCells ?? BoardLayout.pathCells).contains(position);
  }

  static bool isBuildableCell(
    GridPosition position, {
    List<GridPosition>? pathCells,
  }) {
    return isInBounds(position) &&
        !isPathCell(position, pathCells: pathCells);
  }
```

Keep the existing `pathCells` constant unchanged.

- [ ] **Step 5: Update `GameSession` to own a selected stage**

Modify `lib/game/rules/game_session.dart`:

```dart
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
```

Replace the constructor and add the stage field:

```dart
class GameSession {
  GameSession.initial({StageDefinition? stage, int? gold, int? baseHealth})
    : stage = stage ?? OrionCampaign.stageOne,
      _gold = gold ?? GameBalance.startingGold,
      _baseHealth = baseHealth ?? GameBalance.initialBaseHealth;

  final StageDefinition stage;
```

Update `activeWave`:

```dart
  WaveDefinition? get activeWave {
    if (_waveIndex >= stage.waves.length) {
      return null;
    }
    return stage.waves[_waveIndex];
  }
```

Update `snapshot()`:

```dart
    return GameSnapshot(
      phase: _phase,
      gold: _gold,
      baseHealth: _baseHealth,
      waveNumber: (_waveIndex + 1).clamp(1, stage.waves.length).toInt(),
      waveTotal: stage.waves.length,
      stageName: stage.name,
      stageLabel: stage.mapLabel,
      unlockedTowerTypes: unlockedTowerTypes,
      selectedCell: selectedCell,
      selectedTower: selectedTower,
      feedback: feedback,
    );
```

Update path placement validation:

```dart
    if (BoardLayout.isPathCell(position, pathCells: stage.pathCells)) {
      return const PlacementResult.denied(PlacementFailure.pathBlocked);
    }
```

Replace `startWave()`:

```dart
  bool startWave() {
    if (_phase != GamePhase.build || _waveIndex >= stage.waves.length) {
      return false;
    }
    _phase = GamePhase.wave;
    return true;
  }
```

Replace `finishActiveWave()`:

```dart
  void finishActiveWave() {
    if (_phase != GamePhase.wave) {
      return;
    }

    final completedWave = activeWave;
    _waveIndex += 1;
    if (_waveIndex >= stage.waves.length) {
      _phase = GamePhase.won;
      return;
    }

    _gold += completedWave?.clearBonus ?? 0;
    _phase = GamePhase.build;
  }
```

- [ ] **Step 6: Update tests that loop over wave count**

In `test/game/game_session_test.dart`, replace loops over `GameBalance.waves.length` when they are asserting session completion with `session.stage.waves.length`.

Example:

```dart
      for (var wave = 0; wave < session.stage.waves.length; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }
```

Leave the existing `boots into the Orion tower defense shell` widget test unchanged in this task. Task 7 replaces that test when the app becomes map-first.

- [ ] **Step 7: Run focused tests**

Run:

```bash
dart format lib/game/models/game_models.dart lib/game/rules/board_layout.dart lib/game/rules/game_session.dart test/game/game_session_test.dart test/widget_test.dart
flutter test test/game/game_session_test.dart test/game/board_layout_test.dart test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/game/models/game_models.dart lib/game/rules/board_layout.dart lib/game/rules/game_session.dart test/game/game_session_test.dart test/widget_test.dart
git commit -m "feat: make Orion sessions stage-aware"
```

---

### Task 4: Thread Stage Paths Through Board Rendering And Flame Runtime

**Files:**
- Modify: `lib/game/components/board_component.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/board_layout_test.dart`
- Test: `test/game/orion_defense_game_test.dart`

- [ ] **Step 1: Add focused tests for stage path selection**

Create `test/game/orion_defense_game_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/orion_defense_game.dart';

void main() {
  group('OrionDefenseGame', () {
    test('defaults to campaign stage one', () {
      final game = OrionDefenseGame();

      expect(game.stage, OrionCampaign.stageOne);
      expect(game.snapshot.stageName, 'Outpost Alpha');
    });

    test('can be constructed for another stage', () {
      final stage = OrionCampaign.stageById('nebula-relay');
      final game = OrionDefenseGame(stage: stage);

      expect(game.stage, stage);
      expect(game.snapshot.stageName, 'Nebula Relay');
      expect(game.snapshot.waveTotal, 8);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/game/orion_defense_game_test.dart
```

Expected: FAIL because `OrionDefenseGame` has no `stage` constructor parameter.

- [ ] **Step 3: Update `BoardComponent` to accept selected path cells**

Modify constructor fields in `lib/game/components/board_component.dart`:

```dart
  BoardComponent({
    required this.cellSize,
    required this.pathCells,
    this.selectedCell,
    this.spriteSheet,
    this.terrainImage,
    this.pathTiles,
    super.position,
    super.priority,
  }) : super(
         size: Vector2(
           BoardLayout.columns * cellSize,
           BoardLayout.rows * cellSize,
         ),
       );

  final double cellSize;
  final List<GridPosition> pathCells;
```

Replace every `BoardLayout.pathCells` usage inside `render()` with `pathCells`, and update buildable selection:

```dart
      final paint = BoardLayout.isBuildableCell(
        activeSelection,
        pathCells: pathCells,
      )
          ? _buildableSelectionPaint
          : _blockedSelectionPaint;
```

- [ ] **Step 4: Update `OrionDefenseGame` constructor and path usage**

Modify imports in `lib/game/orion_defense_game.dart`:

```dart
import 'campaign/orion_campaign.dart';
import 'campaign/stage_definition.dart';
```

Replace the class field initialization:

```dart
class OrionDefenseGame extends FlameGame with TapCallbacks {
  OrionDefenseGame({
    StageDefinition? stage,
    this.onStageWon,
    this.onReturnToMap,
  }) : stage = stage ?? OrionCampaign.stageOne,
       _session = GameSession.initial(stage: stage ?? OrionCampaign.stageOne);

  final StageDefinition stage;
  final ValueChanged<StageDefinition>? onStageWon;
  final VoidCallback? onReturnToMap;
  final GameSession _session;
```

Update `_layoutBoard()`:

```dart
    _board = BoardComponent(
      cellSize: _cellSize,
      pathCells: stage.pathCells,
      selectedCell: _selectedTower?.position ?? _selectedCell,
      spriteSheet: _spriteSheet,
      terrainImage: _terrainImage,
      pathTiles: _pathTiles,
      position: Vector2(_boardOrigin.dx, _boardOrigin.dy),
      priority: 0,
    );
```

Update `_pathWaypoints()`:

```dart
  List<Vector2> _pathWaypoints() {
    return stage.pathCells.map(_cellCenter).toList(growable: false);
  }
```

Add a map-return method:

```dart
  void returnToMap() {
    if (_session.phase == GamePhase.wave) {
      _publishSnapshot(feedback: 'Finish the active wave before returning.');
      return;
    }
    onReturnToMap?.call();
  }
```

Update `_finishWaveIfComplete()` after `_session.finishActiveWave();`:

```dart
    final didWin = _session.phase == GamePhase.won;
```

After `_publishSnapshot();` in the same method:

```dart
    if (didWin) {
      onStageWon?.call(stage);
    }
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
dart format lib/game/components/board_component.dart lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
flutter test test/game/orion_defense_game_test.dart test/game/board_layout_test.dart test/game/game_session_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/game/components/board_component.dart lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: run Orion missions from selected stages"
```

---

### Task 5: Add Local Campaign Progress Persistence

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/game/campaign/campaign_progress_store.dart`
- Test: `test/game/campaign_progress_store_test.dart`

- [ ] **Step 1: Add `shared_preferences` dependency**

Run:

```bash
flutter pub add shared_preferences
```

Expected: `pubspec.yaml` and `pubspec.lock` update with `shared_preferences`.

- [ ] **Step 2: Write failing persistence tests**

Create `test/game/campaign_progress_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';

void main() {
  group('CampaignProgressCodec', () {
    test('encodes and decodes versioned progress', () {
      const progress = CampaignProgress(
        clearedStageIds: {'outpost-alpha', 'nebula-relay'},
      );

      final encoded = CampaignProgressCodec.encode(progress);
      final decoded = CampaignProgressCodec.decode(
        encoded,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.clearedStageIds, {'outpost-alpha', 'nebula-relay'});
    });

    test('ignores unknown and duplicate stage ids', () {
      final decoded = CampaignProgressCodec.decode(
        '{"version":1,"clearedStageIds":["outpost-alpha","missing","outpost-alpha"]}',
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.clearedStageIds, {'outpost-alpha'});
    });

    test('falls back to empty progress for corrupt data', () {
      final decoded = CampaignProgressCodec.decode(
        'not-json',
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.clearedStageIds, isEmpty);
    });

    test('in-memory store saves, loads, and resets progress', () async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );

      await store.save(
        const CampaignProgress(clearedStageIds: {'outpost-alpha'}),
      );
      expect((await store.load()).clearedStageIds, {'outpost-alpha'});

      await store.reset();
      expect((await store.load()).clearedStageIds, isEmpty);
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
flutter test test/game/campaign_progress_store_test.dart
```

Expected: FAIL because `campaign_progress_store.dart` does not exist.

- [ ] **Step 4: Add persistence adapter and codec**

Create `lib/game/campaign/campaign_progress_store.dart`:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_progress.dart';
import 'stage_definition.dart';

abstract class CampaignProgressStore {
  Future<CampaignProgress> load();
  Future<void> save(CampaignProgress progress);
  Future<void> reset();
}

class CampaignProgressCodec {
  const CampaignProgressCodec._();

  static String encode(CampaignProgress progress) {
    final ids = progress.clearedStageIds.toList()..sort();
    return jsonEncode({'version': 1, 'clearedStageIds': ids});
  }

  static CampaignProgress decode(
    String? source, {
    required Iterable<StageDefinition> knownStages,
  }) {
    if (source == null || source.isEmpty) {
      return const CampaignProgress();
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
        return const CampaignProgress();
      }

      final rawIds = decoded['clearedStageIds'];
      if (rawIds is! List) {
        return const CampaignProgress();
      }

      final knownIds = knownStages.map((stage) => stage.id).toSet();
      final ids = rawIds.whereType<String>().where(knownIds.contains).toSet();
      return CampaignProgress(clearedStageIds: ids);
    } on FormatException {
      return const CampaignProgress();
    } on TypeError {
      return const CampaignProgress();
    }
  }
}

class SharedPreferencesCampaignProgressStore
    implements CampaignProgressStore {
  SharedPreferencesCampaignProgressStore({
    required SharedPreferences preferences,
    required Iterable<StageDefinition> knownStages,
    this.key = 'orion.campaign.progress',
  }) : _preferences = preferences,
       _knownStages = List.unmodifiable(knownStages);

  final SharedPreferences _preferences;
  final List<StageDefinition> _knownStages;
  final String key;

  @override
  Future<CampaignProgress> load() async {
    return CampaignProgressCodec.decode(
      _preferences.getString(key),
      knownStages: _knownStages,
    );
  }

  @override
  Future<void> save(CampaignProgress progress) async {
    await _preferences.setString(key, CampaignProgressCodec.encode(progress));
  }

  @override
  Future<void> reset() async {
    await _preferences.remove(key);
  }
}

class InMemoryCampaignProgressStore implements CampaignProgressStore {
  InMemoryCampaignProgressStore({required Iterable<StageDefinition> knownStages})
    : _knownStages = List.unmodifiable(knownStages);

  final List<StageDefinition> _knownStages;
  String? _source;

  @override
  Future<CampaignProgress> load() async {
    return CampaignProgressCodec.decode(
      _source,
      knownStages: _knownStages,
    );
  }

  @override
  Future<void> save(CampaignProgress progress) async {
    _source = CampaignProgressCodec.encode(progress);
  }

  @override
  Future<void> reset() async {
    _source = null;
  }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
dart format lib/game/campaign/campaign_progress_store.dart test/game/campaign_progress_store_test.dart
flutter test test/game/campaign_progress_store_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/game/campaign/campaign_progress_store.dart test/game/campaign_progress_store_test.dart
git commit -m "feat: persist Orion campaign progress"
```

---

### Task 6: Build The World Map View Widget

**Files:**
- Create: `lib/game/ui/world_map_view.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Add widget tests for the map view**

Append to `test/widget_test.dart`:

```dart
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/ui/world_map_view.dart';
```

Add tests:

```dart
  testWidgets('world map shows locked, unlocked, and cleared stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: const CampaignProgress(
              clearedStageIds: {'outpost-alpha'},
            ),
            feedback: null,
            onStageSelected: (_) {},
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Cleared'), findsWidgets);
    expect(find.text('Locked'), findsWidgets);
  });

  testWidgets('locked stage tap shows feedback through callback only when unlocked', (
    tester,
  ) async {
    final selected = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldMapView(
            stages: OrionCampaign.stages,
            progress: const CampaignProgress(),
            feedback: null,
            onStageSelected: (stage) => selected.add(stage.id),
            onResetCampaign: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Core'));
    expect(selected, isEmpty);

    await tester.tap(find.text('Alpha'));
    expect(selected, ['outpost-alpha']);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/widget_test.dart
```

Expected: FAIL because `world_map_view.dart` does not exist.

- [ ] **Step 3: Implement `WorldMapView`**

Create `lib/game/ui/world_map_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';

class WorldMapView extends StatelessWidget {
  const WorldMapView({
    super.key,
    required this.stages,
    required this.progress,
    required this.feedback,
    required this.onStageSelected,
    required this.onResetCampaign,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final String? feedback;
  final ValueChanged<StageDefinition> onStageSelected;
  final VoidCallback onResetCampaign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxColumn = stages
        .map((stage) => stage.mapColumn)
        .fold(0, (max, column) => column > max ? column : max);
    final maxRow = stages
        .map((stage) => stage.mapRow)
        .fold(0, (max, row) => row > max ? row : max);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orion Sector Map',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Reset Campaign',
                  onPressed: onResetCampaign,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (feedback != null) ...[
              Text(
                feedback!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = maxColumn + 1;
                  final rows = maxRow + 1;
                  final cellWidth = constraints.maxWidth / columns;
                  final cellHeight = constraints.maxHeight / rows;

                  return Stack(
                    children: [
                      for (final stage in stages)
                        Positioned(
                          left: stage.mapColumn * cellWidth + 4,
                          top: stage.mapRow * cellHeight + 4,
                          width: cellWidth - 8,
                          height: cellHeight - 8,
                          child: _StageNode(
                            stage: stage,
                            status: progress.statusFor(stage),
                            onPressed: () {
                              if (progress.isUnlocked(stage)) {
                                onStageSelected(stage);
                              }
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (progress.isCampaignComplete(stages)) ...[
              const SizedBox(height: 12),
              _CampaignCompleteBanner(progress: progress, stages: stages),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.stage,
    required this.status,
    required this.onPressed,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final isCleared = status == StageProgressStatus.cleared;

    return FilledButton.tonal(
      onPressed: isLocked ? null : onPressed,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: isCleared
            ? theme.colorScheme.primaryContainer
            : isLocked
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.secondaryContainer,
        foregroundColor: isCleared
            ? theme.colorScheme.onPrimaryContainer
            : isLocked
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSecondaryContainer,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCleared
                ? Icons.check_circle
                : isLocked
                    ? Icons.lock
                    : Icons.radio_button_unchecked,
          ),
          const SizedBox(height: 6),
          Text(stage.mapLabel, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            switch (status) {
              StageProgressStatus.cleared => 'Cleared',
              StageProgressStatus.unlocked => 'Open',
              StageProgressStatus.locked => 'Locked',
            },
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _CampaignCompleteBanner extends StatelessWidget {
  const _CampaignCompleteBanner({required this.progress, required this.stages});

  final CampaignProgress progress;
  final List<StageDefinition> stages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleared = stages.where((stage) => progress.isCleared(stage.id)).length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Campaign Complete • $cleared/${stages.length} stages cleared',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
dart format lib/game/ui/world_map_view.dart test/widget_test.dart
flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/world_map_view.dart test/widget_test.dart
git commit -m "feat: add Orion world map view"
```

---

### Task 7: Make App Launch Map-First And Save Stage Clears

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Replace the old app-boot widget test**

In `test/widget_test.dart`, replace `boots into the Orion tower defense shell` with:

```dart
  testWidgets('boots into the Orion world map first', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    expect(find.text('Orion Sector Map'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start Wave'), findsNothing);
  });

  testWidgets('starts an unlocked stage from the world map', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const OrionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Gold 150'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/8'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });
```

Add import:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/widget_test.dart
```

Expected: FAIL because `OrionGamePage` still opens directly to `GameWidget`.

- [ ] **Step 3: Refactor `OrionGamePage` into a campaign shell**

Modify `_OrionGamePageState` in `lib/game/ui/orion_game_page.dart`:

```dart
class _OrionGamePageState extends State<OrionGamePage> {
  OrionDefenseGame? _game;
  CampaignProgress _progress = const CampaignProgress();
  CampaignProgressStore? _store;
  StageDefinition? _activeStage;
  String? _mapFeedback;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesCampaignProgressStore(
      preferences: preferences,
      knownStages: OrionCampaign.stages,
    );
    final progress = await store.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _store = store;
      _progress = progress;
      _isLoading = false;
    });
  }

  void _startStage(StageDefinition stage) {
    if (!_progress.isUnlocked(stage)) {
      setState(() {
        _mapFeedback = '${stage.name} is locked.';
      });
      return;
    }

    setState(() {
      _activeStage = stage;
      _mapFeedback = null;
      _game = OrionDefenseGame(
        stage: stage,
        onStageWon: _markStageCleared,
        onReturnToMap: _returnToMap,
      );
    });
  }

  Future<void> _markStageCleared(StageDefinition stage) async {
    final updated = _progress.markCleared(stage.id);
    setState(() {
      _progress = updated;
    });
    await _store?.save(updated);
  }

  void _returnToMap() {
    setState(() {
      _activeStage = null;
      _game = null;
    });
  }

  Future<void> _confirmResetCampaign() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Campaign'),
        content: const Text('Clear all campaign progress?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (shouldReset != true) {
      return;
    }

    await _store?.reset();
    if (!mounted) {
      return;
    }
    setState(() {
      _progress = const CampaignProgress();
      _activeStage = null;
      _game = null;
      _mapFeedback = 'Campaign reset.';
    });
  }
```

Update `build()` before mission UI:

```dart
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final game = _game;
    if (_activeStage == null || game == null) {
      return Scaffold(
        body: WorldMapView(
          stages: OrionCampaign.stages,
          progress: _progress,
          feedback: _mapFeedback,
          onStageSelected: _startStage,
          onResetCampaign: _confirmResetCampaign,
        ),
      );
    }
```

Keep the existing `Scaffold(body: SafeArea(... GameWidget ...))` as the mission branch, using `game` instead of `_game`.

Add imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/campaign_progress_store.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import 'world_map_view.dart';
```

- [ ] **Step 4: Add mission HUD stage identity and map-return actions**

In `_Hud`, show stage name:

```dart
                Expanded(
                  child: Text(
                    snapshot.stageName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
```

Update wave chip:

```dart
                _StatusChip(
                  label: 'Wave ${snapshot.waveNumber}/${snapshot.waveTotal}',
                ),
```

In `_BottomControls._content`, add a map button when no cell/tower is selected and not in active wave:

```dart
    return Row(
      key: const ValueKey('start-wave'),
      children: [
        IconButton(
          tooltip: 'World Map',
          onPressed: snapshot.phase == GamePhase.wave ? null : game.returnToMap,
          icon: const Icon(Icons.map),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: snapshot.canStartWave ? game.startWave : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Wave'),
          ),
        ),
      ],
    );
```

In `_EndStatePanel`, add return-to-map next to restart:

```dart
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: game.restart,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Restart'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: game.returnToMap,
                      icon: const Icon(Icons.map),
                      label: const Text('World Map'),
                    ),
                  ],
                ),
```

- [ ] **Step 5: Run focused widget tests**

Run:

```bash
dart format lib/game/ui/orion_game_page.dart test/widget_test.dart
flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: launch Orion from campaign map"
```

---

### Task 8: Verify Campaign Integration And Regression Coverage

**Files:**
- Modify: `test/game/game_path_tiles_test.dart`

- [ ] **Step 1: Run full automated verification**

Run:

```bash
dart format .
flutter analyze
flutter test
```

Expected: all three commands pass.

- [ ] **Step 2: Add default-path regression assertion**

Append this test to `test/game/game_path_tiles_test.dart` so path-tile coverage remains tied to the Stage 1 default path:

```dart
    test('default path remains stage one compatible', () {
      expect(OrionCampaign.stageOne.pathCells, BoardLayout.pathCells);
    });
```

Add this import to `test/game/game_path_tiles_test.dart`:

```dart
import 'package:orion/game/campaign/orion_campaign.dart';
```

- [ ] **Step 3: Run full automated verification again**

Run:

```bash
dart format .
flutter analyze
flutter test
```

Expected: PASS.

- [ ] **Step 4: Manual smoke test on web server**

Run:

```bash
flutter run -d web-server
```

Expected: server prints a local URL.

Open the URL and verify:

- World map appears first.
- `Alpha` starts Stage 1.
- Mission HUD shows `Outpost Alpha`, `Gold 150`, `Base 20`, and `Wave 1/8`.
- World Map button returns from build phase.
- Reset campaign shows confirmation.
- No runtime asset-load errors appear in the terminal.

- [ ] **Step 5: Commit the integration regression test**

Commit the default-path regression test:

```bash
git add test/game test/widget_test.dart
git commit -m "test: cover Orion campaign integration"
```

---

## Plan Self-Review Checklist

- Spec coverage: Tasks cover pure campaign rules, seven static stages, stage-specific paths and waves, mission-local progression, map-first UI, local persistence, reset, and tests.
- Placeholder scan: No `TBD`, `TODO`, or implementation-free "add tests" steps remain.
- Type consistency: `StageDefinition`, `CampaignProgress`, `OrionCampaign`, `CampaignProgressStore`, `WorldMapView`, and `OrionDefenseGame(stage:)` are introduced before later tasks depend on them.
