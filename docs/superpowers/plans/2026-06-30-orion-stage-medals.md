# Orion Stage Medals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Clear, Silver, and Gold best-result medals to Orion campaign stages, persist them locally, and show them after victory and on the world map.

**Architecture:** Keep medal rules in the pure campaign layer. `OrionDefenseGame` creates a stage completion payload when a mission wins, `OrionGamePage` serializes result saves through the existing campaign save queue, and `WorldMapView` renders medal state from `CampaignProgress`.

**Tech Stack:** Dart 3.12, Flutter, Flame, `shared_preferences`, `flutter_test`.

---

## File Structure

- Modify `lib/game/campaign/campaign_progress.dart`
  - Add `StageMedal` and `StageResult`.
  - Replace cleared-id storage with immutable best-result storage.
  - Keep unlock and campaign-complete rules derived from `isCleared`.
- Modify `lib/game/campaign/campaign_progress_store.dart`
  - Encode and decode version 2 `stageResults`.
  - Treat unsupported or malformed saves as empty progress.
- Modify `lib/game/orion_defense_game.dart`
  - Add `StageCompletion`.
  - Change `onStageWon` to carry `StageCompletion`.
  - Store the last completion result for the end-state UI.
- Modify `lib/game/ui/orion_game_page.dart`
  - Record stage completion results through the existing serialized save queue.
  - Show the earned medal and base-health line in the victory panel.
- Modify `lib/game/ui/world_map_view.dart`
  - Pass each completed stage result into `_StageNode`.
  - Render medal labels/icons/colors for completed nodes.
- Modify `test/game/campaign_progress_test.dart`
  - Cover medal thresholds, comparison, progress derivation, replay improvements, and unknown-stage filtering.
- Modify `test/game/campaign_progress_store_test.dart`
  - Cover v2 persistence and invalid-save behavior.
- Modify `test/game/orion_defense_game_test.dart`
  - Cover the win callback payload and stored completion result.
- Modify `test/widget_test.dart`
  - Update progress fixtures to use stage results.
  - Cover victory result text, map medal labels, save failure, and serialized result saves.

## Task 1: Campaign Result Model

**Files:**
- Modify: `lib/game/campaign/campaign_progress.dart`
- Modify: `test/game/campaign_progress_test.dart`

- [ ] **Step 1: Replace campaign progress tests with result-focused cases**

In `test/game/campaign_progress_test.dart`, keep the existing `StageDefinition` group and `_stage()` helper. Replace the `CampaignProgress` group with this group:

```dart
group('StageResult', () {
  test('calculates medal thresholds from victory base health', () {
    expect(
      StageResult.fromVictoryBaseHealth(20),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
    expect(
      StageResult.fromVictoryBaseHealth(10),
      const StageResult(medal: StageMedal.silver, bestBaseHealth: 10),
    );
    expect(
      StageResult.fromVictoryBaseHealth(9),
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 9),
    );
  });

  test('compares by medal first and base health second', () {
    const clearNine = StageResult(
      medal: StageMedal.clear,
      bestBaseHealth: 9,
    );
    const silverTen = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 10,
    );
    const silverFourteen = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    const goldTwenty = StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    );

    expect(clearNine.isBetterThan(null), isTrue);
    expect(silverTen.isBetterThan(clearNine), isTrue);
    expect(silverFourteen.isBetterThan(silverTen), isTrue);
    expect(silverTen.isBetterThan(silverFourteen), isFalse);
    expect(goldTwenty.isBetterThan(silverFourteen), isTrue);
    expect(silverFourteen.isBetterThan(goldTwenty), isFalse);
  });
});

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
    final progress = CampaignProgress();

    expect(progress.isCleared('stage-1'), isFalse);
    expect(progress.resultFor('stage-1'), isNull);
    expect(progress.isUnlocked(stages[0]), isTrue);
    expect(progress.isUnlocked(stages[1]), isFalse);
    expect(progress.statusFor(stages[0]), StageProgressStatus.unlocked);
    expect(progress.statusFor(stages[1]), StageProgressStatus.locked);
  });

  test('unlocks main path and side stages from completed results', () {
    final progress = CampaignProgress(
      bestResultsByStageId: {
        'stage-1': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 5,
        ),
        'stage-2': const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: 12,
        ),
        'stage-3': const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: 20,
        ),
        'stage-4': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 3,
        ),
      },
    );

    expect(progress.isUnlocked(stages[4]), isTrue);
    expect(progress.isUnlocked(stages[5]), isTrue);
    expect(progress.isUnlocked(stages[6]), isTrue);
    expect(progress.statusFor(stages[0]), StageProgressStatus.cleared);
    expect(progress.resultFor('stage-2')!.medal, StageMedal.silver);
  });

  test('completes campaign when all main stages have results', () {
    final progress = CampaignProgress(
      bestResultsByStageId: {
        for (final id in [
          'stage-1',
          'stage-2',
          'stage-3',
          'stage-4',
          'stage-5',
        ])
          id: const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
      },
    );

    expect(progress.isCampaignComplete(stages), isTrue);
    expect(
      progress.isCampaignComplete(stages.where((stage) => stage.isMainPath)),
      isTrue,
    );
  });

  test('incomplete, empty, and side-only collections are not complete', () {
    final progress = CampaignProgress(
      bestResultsByStageId: {
        'stage-1': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
      },
    );
    final sideProgress = CampaignProgress(
      bestResultsByStageId: {
        'side-only': const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: 20,
        ),
      },
    );

    expect(progress.isCampaignComplete(stages), isFalse);
    expect(progress.isCampaignComplete(const <StageDefinition>[]), isFalse);
    expect(
      sideProgress.isCampaignComplete([
        _stage(id: 'side-only', isMainPath: false),
      ]),
      isFalse,
    );
  });

  test('recordResult improves but never downgrades a saved result', () {
    final progress = CampaignProgress(
      bestResultsByStageId: {
        'stage-1': const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: 10,
        ),
      },
    );

    final worse = progress.recordResult(
      'stage-1',
      const StageResult(medal: StageMedal.clear, bestBaseHealth: 9),
    );
    final sameMedalBetter = progress.recordResult(
      'stage-1',
      const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
    final betterMedal = sameMedalBetter.recordResult(
      'stage-1',
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );

    expect(worse.resultFor('stage-1'), progress.resultFor('stage-1'));
    expect(
      sameMedalBetter.resultFor('stage-1'),
      const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
    expect(
      betterMedal.resultFor('stage-1'),
      const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    );
  });

  test('withoutUnknownStages filters unknown results', () {
    final progress = CampaignProgress(
      bestResultsByStageId: {
        'stage-1': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
        'side-a': const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: 11,
        ),
        'unknown-stage': const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: 20,
        ),
      },
    );

    final filtered = progress.withoutUnknownStages(stages.take(2));

    expect(filtered.bestResultsByStageId.keys, {'stage-1'});
    expect(progress.bestResultsByStageId.keys, {
      'stage-1',
      'side-a',
      'unknown-stage',
    });
    expect(
      () => filtered.bestResultsByStageId['stage-2'] = const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 1,
      ),
      throwsUnsupportedError,
    );
  });

  test('constructor defensively copies mutable input', () {
    final results = {
      'stage-1': const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 1,
      ),
    };
    final progress = CampaignProgress(bestResultsByStageId: results);

    results['stage-2'] = const StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    );

    expect(progress.bestResultsByStageId.keys, {'stage-1'});
    expect(progress.isCleared('stage-2'), isFalse);
    expect(
      () => progress.bestResultsByStageId.clear(),
      throwsUnsupportedError,
    );
  });

  test('cleared stage with unmet dependencies is still completed', () {
    final dependentStage = _stage(
      id: 'dependent-stage',
      dependencies: ['missing-stage'],
    );
    final progress = CampaignProgress(
      bestResultsByStageId: {
        'dependent-stage': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
      },
    );

    expect(progress.isUnlocked(dependentStage), isFalse);
    expect(progress.statusFor(dependentStage), StageProgressStatus.cleared);
  });
});
```

- [ ] **Step 2: Run the campaign progress test and confirm it fails**

Run:

```bash
rtk flutter test test/game/campaign_progress_test.dart
```

Expected: FAIL with errors naming missing `StageResult`, `StageMedal`, `bestResultsByStageId`, `resultFor`, and `recordResult`.

- [ ] **Step 3: Replace `campaign_progress.dart` with the result model**

Replace `lib/game/campaign/campaign_progress.dart` with:

```dart
import 'package:orion/game/models/game_models.dart';

import 'stage_definition.dart';

enum StageProgressStatus { locked, unlocked, cleared }

enum StageMedal {
  clear,
  silver,
  gold;

  int get rank {
    return switch (this) {
      StageMedal.clear => 1,
      StageMedal.silver => 2,
      StageMedal.gold => 3,
    };
  }

  String get label {
    return switch (this) {
      StageMedal.clear => 'Clear',
      StageMedal.silver => 'Silver',
      StageMedal.gold => 'Gold',
    };
  }

  String get serializedName {
    return switch (this) {
      StageMedal.clear => 'clear',
      StageMedal.silver => 'silver',
      StageMedal.gold => 'gold',
    };
  }

  static StageMedal? fromSerializedName(String value) {
    return switch (value) {
      'clear' => StageMedal.clear,
      'silver' => StageMedal.silver,
      'gold' => StageMedal.gold,
      _ => null,
    };
  }
}

class StageResult {
  const StageResult({required this.medal, required this.bestBaseHealth});

  final StageMedal medal;
  final int bestBaseHealth;

  factory StageResult.fromVictoryBaseHealth(int baseHealth) {
    final normalizedBaseHealth = baseHealth
        .clamp(0, GameBalance.initialBaseHealth)
        .toInt();
    final medal = switch (normalizedBaseHealth) {
      GameBalance.initialBaseHealth => StageMedal.gold,
      >= 10 => StageMedal.silver,
      _ => StageMedal.clear,
    };

    return StageResult(
      medal: medal,
      bestBaseHealth: normalizedBaseHealth,
    );
  }

  bool isBetterThan(StageResult? other) {
    if (other == null) {
      return true;
    }
    if (medal.rank != other.medal.rank) {
      return medal.rank > other.medal.rank;
    }
    return bestBaseHealth > other.bestBaseHealth;
  }

  Map<String, Object> toJson() {
    return {
      'medal': medal.serializedName,
      'bestBaseHealth': bestBaseHealth,
    };
  }

  static StageResult? fromJson(Object? source) {
    if (source is! Map<String, Object?>) {
      return null;
    }

    final rawMedal = source['medal'];
    final rawBaseHealth = source['bestBaseHealth'];
    if (rawMedal is! String || rawBaseHealth is! int) {
      return null;
    }

    final medal = StageMedal.fromSerializedName(rawMedal);
    if (medal == null ||
        rawBaseHealth < 0 ||
        rawBaseHealth > GameBalance.initialBaseHealth) {
      return null;
    }

    return StageResult(medal: medal, bestBaseHealth: rawBaseHealth);
  }

  @override
  bool operator ==(Object other) {
    return other is StageResult &&
        other.medal == medal &&
        other.bestBaseHealth == bestBaseHealth;
  }

  @override
  int get hashCode => Object.hash(medal, bestBaseHealth);

  @override
  String toString() {
    return 'StageResult(medal: $medal, bestBaseHealth: $bestBaseHealth)';
  }
}

class CampaignProgress {
  CampaignProgress({
    Map<String, StageResult> bestResultsByStageId =
        const <String, StageResult>{},
  }) : _bestResultsByStageId = Map.unmodifiable(bestResultsByStageId);

  final Map<String, StageResult> _bestResultsByStageId;

  Map<String, StageResult> get bestResultsByStageId => _bestResultsByStageId;

  StageResult? resultFor(String stageId) {
    return _bestResultsByStageId[stageId];
  }

  bool isCleared(String stageId) {
    return _bestResultsByStageId.containsKey(stageId);
  }

  bool isUnlocked(StageDefinition stage) {
    return stage.unlockDependencies.every(isCleared);
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

  bool isCampaignComplete(Iterable<StageDefinition> stages) {
    final mainPathStages = stages.where((stage) => stage.isMainPath).toList();

    return mainPathStages.isNotEmpty &&
        mainPathStages.every((stage) => isCleared(stage.id));
  }

  CampaignProgress withoutUnknownStages(Iterable<StageDefinition> stages) {
    final knownStageIds = stages.map((stage) => stage.id).toSet();

    return CampaignProgress(
      bestResultsByStageId: Map.fromEntries(
        _bestResultsByStageId.entries.where(
          (entry) => knownStageIds.contains(entry.key),
        ),
      ),
    );
  }

  CampaignProgress recordResult(String stageId, StageResult result) {
    final savedResult = _bestResultsByStageId[stageId];
    if (!result.isBetterThan(savedResult)) {
      return this;
    }

    return CampaignProgress(
      bestResultsByStageId: {
        ..._bestResultsByStageId,
        stageId: result,
      },
    );
  }
}
```

- [ ] **Step 4: Run the focused test and confirm it passes**

Run:

```bash
rtk flutter test test/game/campaign_progress_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the campaign result model**

Run:

```bash
rtk git add lib/game/campaign/campaign_progress.dart test/game/campaign_progress_test.dart
rtk git commit -m "feat: add Orion stage result model"
```

Expected: commit succeeds.

## Task 2: Version 2 Campaign Progress Codec

**Files:**
- Modify: `lib/game/campaign/campaign_progress_store.dart`
- Modify: `test/game/campaign_progress_store_test.dart`

- [ ] **Step 1: Replace codec tests with version 2 result cases**

In `test/game/campaign_progress_store_test.dart`, replace usages of `CampaignProgress(clearedStageIds: ...)` with `CampaignProgress(bestResultsByStageId: ...)`, and add these tests inside `group('CampaignProgressCodec', ...)`:

```dart
test('encodes and decodes versioned stage results', () {
  final progress = CampaignProgress(
    bestResultsByStageId: {
      'outpost-alpha': const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
      'nebula-relay': const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
    },
  );

  final encoded = CampaignProgressCodec.encode(progress);
  final decoded = CampaignProgressCodec.decode(
    encoded,
    knownStages: OrionCampaign.stages,
  );

  expect(decoded.resultFor('outpost-alpha'), progress.resultFor('outpost-alpha'));
  expect(decoded.resultFor('nebula-relay'), progress.resultFor('nebula-relay'));
});

test('ignores unknown stage ids and invalid result entries', () {
  final decoded = CampaignProgressCodec.decode(
    '''
{
  "version": 2,
  "stageResults": {
    "outpost-alpha": {"medal": "gold", "bestBaseHealth": 20},
    "missing": {"medal": "gold", "bestBaseHealth": 20},
    "nebula-relay": {"medal": "diamond", "bestBaseHealth": 18},
    "asteroid-foundry": {"medal": "silver", "bestBaseHealth": 99}
  }
}
''',
    knownStages: OrionCampaign.stages,
  );

  expect(decoded.bestResultsByStageId.keys, {'outpost-alpha'});
  expect(
    decoded.resultFor('outpost-alpha'),
    const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
  );
});

test('unsupported version one cleared ids decode empty', () {
  final decoded = CampaignProgressCodec.decode(
    '{"version":1,"clearedStageIds":["outpost-alpha"]}',
    knownStages: OrionCampaign.stages,
  );

  expect(decoded.bestResultsByStageId, isEmpty);
});
```

Update existing store assertions to check `bestResultsByStageId` or `resultFor()`:

```dart
await store.save(
  CampaignProgress(
    bestResultsByStageId: {
      'outpost-alpha': const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 4,
      ),
    },
  ),
);
expect(
  (await store.load()).resultFor('outpost-alpha'),
  const StageResult(medal: StageMedal.clear, bestBaseHealth: 4),
);
```

- [ ] **Step 2: Run the codec test and confirm it fails**

Run:

```bash
rtk flutter test test/game/campaign_progress_store_test.dart
```

Expected: FAIL because `CampaignProgressCodec` still writes version 1 `clearedStageIds`.

- [ ] **Step 3: Replace `CampaignProgressCodec` encode and decode**

In `lib/game/campaign/campaign_progress_store.dart`, replace the body of `CampaignProgressCodec` with:

```dart
class CampaignProgressCodec {
  const CampaignProgressCodec._();

  static String encode(CampaignProgress progress) {
    final stageIds = progress.bestResultsByStageId.keys.toList()..sort();
    final stageResults = <String, Object>{};
    for (final stageId in stageIds) {
      stageResults[stageId] = progress.bestResultsByStageId[stageId]!.toJson();
    }

    return jsonEncode({'version': 2, 'stageResults': stageResults});
  }

  static CampaignProgress decode(
    String? source, {
    required Iterable<StageDefinition> knownStages,
  }) {
    if (source == null || source.isEmpty) {
      return CampaignProgress();
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> || decoded['version'] != 2) {
        return CampaignProgress();
      }

      final rawResults = decoded['stageResults'];
      if (rawResults is! Map<String, Object?>) {
        return CampaignProgress();
      }

      final knownIds = knownStages.map((stage) => stage.id).toSet();
      final results = <String, StageResult>{};
      for (final entry in rawResults.entries) {
        if (!knownIds.contains(entry.key)) {
          continue;
        }

        final result = StageResult.fromJson(entry.value);
        if (result == null) {
          continue;
        }

        results[entry.key] = result;
      }

      return CampaignProgress(bestResultsByStageId: results);
    } on FormatException {
      return CampaignProgress();
    } on TypeError {
      return CampaignProgress();
    }
  }
}
```

- [ ] **Step 4: Run the focused codec and progress tests**

Run:

```bash
rtk flutter test test/game/campaign_progress_test.dart test/game/campaign_progress_store_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the version 2 codec**

Run:

```bash
rtk git add lib/game/campaign/campaign_progress_store.dart test/game/campaign_progress_store_test.dart
rtk git commit -m "feat: persist Orion stage medal results"
```

Expected: commit succeeds.

## Task 3: Stage Completion Payload In Game Layer

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/orion_defense_game_test.dart`

- [ ] **Step 1: Update the game win callback test**

In `test/game/orion_defense_game_test.dart`, add the campaign progress import:

```dart
import 'package:orion/game/campaign/campaign_progress.dart';
```

Replace the `calls onStageWon after a wave clear publishes won phase` test with:

```dart
test('calls onStageWon with a completion result after won snapshot', () {
  final stage = StageDefinition(
    id: 'one-wave-stage',
    name: 'One Wave Stage',
    mapLabel: 'One',
    description: 'Stage with one empty wave',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [WaveDefinition(groups: [], clearBonus: 0)],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
  final completions = <StageCompletion>[];
  final game = OrionDefenseGame(stage: stage, onStageWon: completions.add);

  game.startWave();
  game.onGameResize(Vector2(800, 1200));
  game.update(0);

  expect(game.snapshot.phase, GamePhase.won);
  expect(completions, hasLength(1));
  expect(completions.single.stage, stage);
  expect(
    completions.single.result,
    const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
  );
  expect(game.stageCompletion, completions.single);
});
```

- [ ] **Step 2: Run the game test and confirm it fails**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name "calls onStageWon"
```

Expected: FAIL because `StageCompletion` and `stageCompletion` do not exist and `onStageWon` still accepts `StageDefinition`.

- [ ] **Step 3: Add `StageCompletion` and update the callback**

In `lib/game/orion_defense_game.dart`, add this import with the other campaign imports:

```dart
import 'campaign/campaign_progress.dart';
```

Add this class above `class OrionDefenseGame`:

```dart
class StageCompletion {
  const StageCompletion({required this.stage, required this.result});

  final StageDefinition stage;
  final StageResult result;
}
```

Update the callback field and add stored completion state:

```dart
final ValueChanged<StageCompletion>? onStageWon;
final VoidCallback? onReturnToMap;
final GameSession _session;
StageCompletion? _stageCompletion;

StageCompletion? get stageCompletion => _stageCompletion;
```

In `_finishWaveIfComplete()`, replace the final layout, publish, and win-callback block with this exact sequence so `game.stageCompletion` is populated before the victory panel rebuilds:

```dart
StageCompletion? completion;
if (didWin) {
  completion = StageCompletion(
    stage: stage,
    result: StageResult.fromVictoryBaseHealth(_session.baseHealth),
  );
  _stageCompletion = completion;
}
_layoutBoardIfReady();
_publishSnapshot();
if (completion != null) {
  onStageWon?.call(completion);
}
```

In `restart()`, clear the stored completion before publishing:

```dart
_stageCompletion = null;
```

- [ ] **Step 4: Run the focused game test**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name "calls onStageWon"
```

Expected: PASS.

- [ ] **Step 5: Commit the completion payload**

Run:

```bash
rtk git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
rtk git commit -m "feat: report Orion stage completion results"
```

Expected: commit succeeds.

## Task 4: Campaign Shell Result Saving

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Update widget test progress fixtures and direct win callbacks**

In `test/widget_test.dart`, replace every `CampaignProgress(clearedStageIds: {...})` fixture with `CampaignProgress(bestResultsByStageId: {...})`. Use this helper near `_TestCampaignProgressStore`:

```dart
CampaignProgress _progressWithResults(Iterable<String> stageIds) {
  return CampaignProgress(
    bestResultsByStageId: {
      for (final stageId in stageIds)
        stageId: const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
    },
  );
}
```

Update direct callback invocations from:

```dart
game!.onStageWon?.call(OrionCampaign.stageById('nebula-relay'));
```

to:

```dart
game!.onStageWon?.call(
  StageCompletion(
    stage: OrionCampaign.stageById('nebula-relay'),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
  ),
);
```

Update save assertions from `store.progress.clearedStageIds` to result-aware checks:

```dart
expect(store.progress.bestResultsByStageId.keys, {'outpost-alpha'});
expect(
  store.progress.resultFor('nebula-relay'),
  const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
);
```

- [ ] **Step 2: Add a no-downgrade widget save test**

Add this widget test near the save-failure and serialized-save tests:

```dart
testWidgets('stage replay save does not downgrade an existing medal', (
  tester,
) async {
  final store = _TestCampaignProgressStore(
    progress: CampaignProgress(
      bestResultsByStageId: {
        'outpost-alpha': const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: 20,
        ),
      },
    ),
  );
  OrionDefenseGame? game;

  await tester.pumpWidget(
    MaterialApp(
      home: OrionGamePage(
        progressStore: store,
        onGameCreated: (created) => game = created,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();

  game!.onStageWon?.call(
    StageCompletion(
      stage: OrionCampaign.stageById('outpost-alpha'),
      result: const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    store.progress.resultFor('outpost-alpha'),
    const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
  );
});
```

- [ ] **Step 3: Run widget tests and confirm shell failures**

Run:

```bash
rtk flutter test test/widget_test.dart
```

Expected: FAIL because `OrionGamePage` still expects `StageDefinition` in `_markStageCleared` and still calls `markCleared`.

- [ ] **Step 4: Replace clear-save methods with completion-save methods**

In `lib/game/ui/orion_game_page.dart`, update the game creation:

```dart
final game = OrionDefenseGame(
  stage: stage,
  onStageWon: _recordStageCompletion,
  onReturnToMap: _returnToMap,
);
```

Replace `_markStageCleared` and `_saveStageClear` with:

```dart
Future<void> _recordStageCompletion(StageCompletion completion) async {
  final saveGeneration = _progressGeneration;
  final saveTask = _clearSaveQueue.then(
    (_) => _saveStageCompletion(completion, saveGeneration),
  );
  _clearSaveQueue = saveTask.catchError((_) {});
  await saveTask;
}

Future<void> _saveStageCompletion(
  StageCompletion completion,
  int saveGeneration,
) async {
  final store = _store;
  if (store == null) {
    _showCampaignPersistenceFailure();
    return;
  }

  if (saveGeneration != _progressGeneration) {
    return;
  }

  final progress = _progress.recordResult(
    completion.stage.id,
    completion.result,
  );
  try {
    await store.save(progress);
  } catch (_) {
    if (!mounted || saveGeneration != _progressGeneration) {
      return;
    }

    _showCampaignPersistenceFailure();
    return;
  }

  if (!mounted) {
    return;
  }

  if (saveGeneration != _progressGeneration) {
    await _resetStoreAfterStaleClearSave(store);
    return;
  }

  setState(() {
    _progress = progress;
  });
}
```

Keep `_clearSaveQueue` and `_resetStoreAfterStaleClearSave` names for this task to avoid unrelated churn.

- [ ] **Step 5: Run focused widget tests**

Run:

```bash
rtk flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit shell result saving**

Run:

```bash
rtk git add lib/game/ui/orion_game_page.dart test/widget_test.dart
rtk git commit -m "feat: save Orion stage completion results"
```

Expected: commit succeeds.

## Task 5: Victory Medal Text And World Map Medal Nodes

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Add widget tests for victory and map medal display**

In `test/widget_test.dart`, add this test near the mission-screen tests:

```dart
testWidgets('victory panel shows earned medal and base health', (tester) async {
  SharedPreferences.setMockInitialValues({});
  OrionDefenseGame? game;

  await tester.pumpWidget(
    MaterialApp(
      home: OrionGamePage(onGameCreated: (created) => game = created),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();

  final snapshot = game!.stateNotifier.value;
  game!.stateNotifier.value = GameSnapshot(
    phase: GamePhase.won,
    gold: snapshot.gold,
    baseHealth: 14,
    waveNumber: snapshot.waveTotal,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    nextWavePreview: null,
    selectedCell: snapshot.selectedCell,
    selectedTower: snapshot.selectedTower,
    feedback: snapshot.feedback,
    isPaused: snapshot.isPaused,
    speedMultiplier: snapshot.speedMultiplier,
    autoStartEnabled: snapshot.autoStartEnabled,
    autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
  );
  await tester.pump();

  expect(find.text('Victory'), findsOneWidget);
  expect(find.text('Silver medal - Base 14/20'), findsOneWidget);
});
```

Replace the existing `world map shows locked, unlocked, and cleared stages` test fixture with:

```dart
progress: CampaignProgress(
  bestResultsByStageId: {
    'outpost-alpha': const StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    ),
  },
),
```

and replace the generic cleared assertion:

```dart
expect(find.text('Cleared'), findsWidgets);
```

with:

```dart
expect(find.text('Gold'), findsOneWidget);
```

- [ ] **Step 2: Run the widget test and confirm display failures**

Run:

```bash
rtk flutter test test/widget_test.dart --name "victory panel shows earned medal|world map shows"
```

Expected: FAIL because the victory panel has no result line and world-map completed nodes still label as `Cleared`.

- [ ] **Step 3: Add medal text to the victory panel**

In `lib/game/orion_defense_game.dart`, add a helper method below the existing getters:

```dart
StageResult? resultForSnapshot(GameSnapshot snapshot) {
  if (snapshot.phase != GamePhase.won) {
    return null;
  }
  return _stageCompletion?.result ??
      StageResult.fromVictoryBaseHealth(snapshot.baseHealth);
}
```

In `lib/game/ui/orion_game_page.dart`, inside `_EndStatePanel.build`, add:

```dart
final result = game.resultForSnapshot(snapshot);
```

After the `Victory` / `Base Lost` title and before the button spacing, insert:

```dart
if (didWin && result != null) ...[
  const SizedBox(height: 8),
  Text(
    '${result.medal.label} medal - '
    'Base ${result.bestBaseHealth}/${GameBalance.initialBaseHealth}',
    style: theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
    ),
  ),
],
```

Keep the existing `const SizedBox(height: 16)` before the `Wrap`.

- [ ] **Step 4: Update world-map nodes to use stage results**

In `lib/game/ui/world_map_view.dart`, pass results into `_StageNode`:

```dart
child: _StageNode(
  stage: stage,
  status: progress.statusFor(stage),
  result: progress.resultFor(stage.id),
  onStageSelected: onStageSelected,
  onLockedStageSelected: onLockedStageSelected,
),
```

Add the field to `_StageNode`:

```dart
final StageResult? result;
```

Update its constructor:

```dart
const _StageNode({
  required this.stage,
  required this.status,
  required this.result,
  required this.onStageSelected,
  required this.onLockedStageSelected,
});
```

Update color/icon/label calls:

```dart
final colors = _stageColors(theme.colorScheme, status, result);
```

```dart
Icon(_statusIcon(status, result), color: colors.foreground),
```

```dart
_statusLabel(status, result),
```

Replace `_stageColors`, `_statusIcon`, and `_statusLabel` with:

```dart
_StageColors _stageColors(
  ColorScheme colorScheme,
  StageProgressStatus status,
  StageResult? result,
) {
  if (status == StageProgressStatus.cleared && result != null) {
    return switch (result.medal) {
      StageMedal.gold => _StageColors(
        background: colorScheme.primaryContainer,
        border: colorScheme.primary,
        foreground: colorScheme.onPrimaryContainer,
      ),
      StageMedal.silver => _StageColors(
        background: colorScheme.secondaryContainer,
        border: colorScheme.secondary,
        foreground: colorScheme.onSecondaryContainer,
      ),
      StageMedal.clear => _StageColors(
        background: colorScheme.tertiaryContainer,
        border: colorScheme.tertiary,
        foreground: colorScheme.onTertiaryContainer,
      ),
    };
  }

  return switch (status) {
    StageProgressStatus.cleared => _StageColors(
      background: colorScheme.tertiaryContainer,
      border: colorScheme.tertiary,
      foreground: colorScheme.onTertiaryContainer,
    ),
    StageProgressStatus.unlocked => _StageColors(
      background: colorScheme.secondaryContainer,
      border: colorScheme.secondary,
      foreground: colorScheme.onSecondaryContainer,
    ),
    StageProgressStatus.locked => _StageColors(
      background: colorScheme.surface,
      border: colorScheme.outlineVariant,
      foreground: colorScheme.onSurfaceVariant,
    ),
  };
}

IconData _statusIcon(StageProgressStatus status, StageResult? result) {
  if (status == StageProgressStatus.cleared && result != null) {
    return switch (result.medal) {
      StageMedal.gold => Icons.emoji_events,
      StageMedal.silver => Icons.military_tech,
      StageMedal.clear => Icons.check_circle,
    };
  }

  return switch (status) {
    StageProgressStatus.cleared => Icons.check_circle,
    StageProgressStatus.unlocked => Icons.radio_button_checked,
    StageProgressStatus.locked => Icons.lock,
  };
}

String _statusLabel(StageProgressStatus status, StageResult? result) {
  if (status == StageProgressStatus.cleared && result != null) {
    return result.medal.label;
  }

  return switch (status) {
    StageProgressStatus.cleared => 'Cleared',
    StageProgressStatus.unlocked => 'Open',
    StageProgressStatus.locked => 'Locked',
  };
}
```

- [ ] **Step 5: Run widget tests**

Run:

```bash
rtk flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit medal display**

Run:

```bash
rtk git add lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart lib/game/ui/world_map_view.dart test/widget_test.dart
rtk git commit -m "feat: show Orion stage medals"
```

Expected: commit succeeds.

## Task 6: Full Verification And Cleanup

**Files:**
- Verify all modified Dart files.
- Commit any formatting-only changes if `dart format` changes files.

- [ ] **Step 1: Run Dart format**

Run:

```bash
rtk dart format lib/game/campaign/campaign_progress.dart lib/game/campaign/campaign_progress_store.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart lib/game/ui/world_map_view.dart test/game/campaign_progress_test.dart test/game/campaign_progress_store_test.dart test/game/orion_defense_game_test.dart test/widget_test.dart
```

Expected: formatter completes. If it changes files, inspect `rtk git diff --stat`.

- [ ] **Step 2: Run static analysis**

Run:

```bash
rtk flutter analyze
```

Expected: PASS with no issues.

- [ ] **Step 3: Run the full test suite sequentially**

Run:

```bash
rtk flutter test
```

Expected: PASS. Keep this as a single sequential Flutter test run because this repo has had intermittent lock/temp-file issues when Flutter verification overlaps.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
rtk git status --short
rtk git diff --stat
```

Expected: only intended HPA-93 implementation files are changed. If all task commits were already made and the worktree is clean, there is nothing to commit in this step.

- [ ] **Step 5: Commit final formatting or verification cleanup**

If Step 1 produced formatting changes after Task 5, run:

```bash
rtk git add lib/game/campaign/campaign_progress.dart lib/game/campaign/campaign_progress_store.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart lib/game/ui/world_map_view.dart test/game/campaign_progress_test.dart test/game/campaign_progress_store_test.dart test/game/orion_defense_game_test.dart test/widget_test.dart
rtk git commit -m "chore: format Orion stage medals"
```

Expected: commit succeeds only when there are formatting changes to commit.

## Self-Review Notes

- Spec coverage: Task 1 covers medal calculation, comparison, replay improvement, and cleared/unlock derivation. Task 2 covers v2 persistence and invalid-save handling. Task 3 covers the game completion payload. Task 4 covers campaign-shell saving and no-downgrade behavior. Task 5 covers victory and world-map UI. Task 6 covers format, analyze, and full tests.
- Scope check: The plan does not include stars, Platinum, challenge constraints, rewards, or balance changes.
- Type consistency: `StageMedal`, `StageResult`, `CampaignProgress.bestResultsByStageId`, `CampaignProgress.resultFor`, `CampaignProgress.recordResult`, `StageCompletion`, and `OrionDefenseGame.stageCompletion` are introduced before later tasks use them.
