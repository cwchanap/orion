# Side-Stage Campaign Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make optional side stages grant persistent campaign rewards (bonus gold, bonus health, challenge badge) that apply to all future missions.

**Architecture:** A `CampaignReward` enum on `StageDefinition` declares each side stage's reward type. A pure `CampaignModifiers` value object derives active bonuses from `CampaignProgress`. `OrionGamePage` computes modifiers when starting a mission and passes them through `OrionDefenseGame` to `GameSession.initial`, which already accepts gold/baseHealth overrides. The medal calculation and UI use a new `startingBaseHealth` field on `GameSession`/`GameSnapshot` to handle bonus health correctly.

**Tech Stack:** Flutter + Flame, Dart SDK ^3.12.0, `shared_preferences` for persistence.

## Global Constraints

- Pure game logic (no Flame imports) lives in `lib/game/rules/` and `lib/game/campaign/` — keep this boundary intact.
- All economy/wave/tower/enemy tuning lives in `GameBalance` in `lib/game/models/game_models.dart`.
- The UI never reads game state directly — only via `GameSnapshot`.
- Campaign progress JSON is version 2; the codec trusts stored values and does not re-derive medals.
- `OrionCampaign` must contain exactly 7 stages: 5 main, 2 side.
- Run `flutter test` to verify all tests pass after each task.
- Run `flutter analyze` to verify no lint errors after each task.

---

### Task 1: CampaignReward enum, StageDefinition.reward field, GameBalance constants

**Files:**
- Modify: `lib/game/campaign/stage_definition.dart`
- Modify: `lib/game/models/game_models.dart:398-404` (GameBalance constants)
- Modify: `test/game/campaign_progress_test.dart:364-383` (`_stage` helper)
- Modify: `test/game/orion_campaign_test.dart:117-134` (`_stage` helper)

**Interfaces:**
- Produces: `CampaignReward` enum (in `stage_definition.dart`), `StageDefinition.reward` field (`CampaignReward?`, defaults null), `GameBalance.salvageRiftGoldBonus` (30), `GameBalance.voidBastionHealthBonus` (5).

- [ ] **Step 1: Add CampaignReward enum and reward field to StageDefinition**

Add the enum above the `StageDefinition` class in `lib/game/campaign/stage_definition.dart`, then add the `reward` parameter to the constructor:

```dart
enum CampaignReward {
  bonusGold,
  bonusHealth,
  challengeBadge,
}

class StageDefinition {
  StageDefinition({
    required this.id,
    required this.name,
    required this.mapLabel,
    required this.description,
    required List<GridPosition> pathCells,
    required List<WaveDefinition> waves,
    List<String> unlockDependencies = const [],
    this.isMainPath = true,
    this.mainPathOrder,
    this.reward,
    required this.mapColumn,
    required this.mapRow,
  }) : pathCells = List.unmodifiable(pathCells),
       waves = List.unmodifiable(waves),
       unlockDependencies = List.unmodifiable(unlockDependencies);

  final String id;
  final String name;
  final String mapLabel;
  final String description;
  final List<GridPosition> pathCells;
  final List<WaveDefinition> waves;
  final List<String> unlockDependencies;
  final bool isMainPath;
  final int? mainPathOrder;
  final CampaignReward? reward;
  final int mapColumn;
  final int mapRow;
}
```

- [ ] **Step 2: Add GameBalance constants**

In `lib/game/models/game_models.dart`, add two constants after `sellRefundPercent` in the `GameBalance` class (around line 404):

```dart
  // Bonus starting gold granted by clearing the Salvage Rift side stage.
  static const int salvageRiftGoldBonus = 30;
  // Bonus starting base health granted by clearing the Void Bastion side stage.
  static const int voidBastionHealthBonus = 5;
```

- [ ] **Step 3: Add GameBalance test assertions**

In `test/game/game_balance_test.dart`, add assertions to the existing `'matches the approved starting economy and base health'` test (around line 6-9):

```dart
    test('matches the approved starting economy and base health', () {
      expect(GameBalance.startingGold, 150);
      expect(GameBalance.initialBaseHealth, 20);
      expect(GameBalance.salvageRiftGoldBonus, 30);
      expect(GameBalance.voidBastionHealthBonus, 5);
    });
```

- [ ] **Step 4: Update _stage helpers to accept reward parameter**

In `test/game/campaign_progress_test.dart`, update the `_stage` helper (line 364) to accept an optional `reward` parameter:

```dart
StageDefinition _stage({
  required String id,
  List<String> dependencies = const [],
  bool isMainPath = true,
  int? mainPathOrder,
  CampaignReward? reward,
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
    reward: reward,
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}
```

In `test/game/orion_campaign_test.dart`, update the `_stage` helper (line 117) similarly:

```dart
StageDefinition _stage({
  required String id,
  bool isMainPath = true,
  int? mainPathOrder,
  CampaignReward? reward,
}) {
  return StageDefinition(
    id: id,
    name: id,
    mapLabel: id,
    description: id,
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: GameBalance.waves,
    isMainPath: isMainPath,
    mainPathOrder: mainPathOrder,
    reward: reward,
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}
```

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test`
Run: `flutter analyze`
Expected: All tests pass, no analyze errors. The new `reward` field defaults to null so existing code is unaffected.

- [ ] **Step 6: Commit**

```bash
git add lib/game/campaign/stage_definition.dart lib/game/models/game_models.dart test/game/game_balance_test.dart test/game/campaign_progress_test.dart test/game/orion_campaign_test.dart
git commit -m "feat: add CampaignReward enum and StageDefinition.reward field (HPA-94)"
```

---

### Task 2: CampaignModifiers value object

**Files:**
- Modify: `lib/game/campaign/campaign_progress.dart` (add `CampaignModifiers` class)
- Modify: `test/game/campaign_progress_test.dart` (add test group)

**Interfaces:**
- Consumes: `CampaignProgress.isCleared(stageId)` (from Task 1's `campaign_progress.dart`), `StageDefinition.reward` / `StageDefinition.isMainPath` (from Task 1), `GameBalance.salvageRiftGoldBonus` / `voidBastionHealthBonus` (from Task 1).
- Produces: `CampaignModifiers` class with `bonusGold`, `bonusHealth`, `hasChallengeBadge`, `adjustedStartingGold`, `adjustedStartingBaseHealth`, `empty`, and `fromProgress(progress, stages)`.

- [ ] **Step 1: Write failing tests for CampaignModifiers**

Add a new test group at the end of `main()` in `test/game/campaign_progress_test.dart`, before the closing `}` of `main()` (after the `StageDefinition` group ending at line 361):

```dart
  group('CampaignModifiers', () {
    final stages = [
      _stage(id: 'stage-1', mainPathOrder: 1),
      _stage(id: 'stage-2', dependencies: ['stage-1'], mainPathOrder: 2),
      _stage(id: 'stage-3', dependencies: ['stage-2'], mainPathOrder: 3),
      _stage(id: 'stage-4', dependencies: ['stage-3'], mainPathOrder: 4),
      _stage(id: 'stage-5', dependencies: ['stage-4'], mainPathOrder: 5),
      _stage(
        id: 'side-a',
        dependencies: ['stage-2'],
        isMainPath: false,
        reward: CampaignReward.bonusGold,
      ),
      _stage(
        id: 'side-b',
        dependencies: ['stage-4'],
        isMainPath: false,
        reward: CampaignReward.bonusHealth,
      ),
    ];

    test('empty progress yields zero modifiers', () {
      const modifiers = CampaignModifiers.empty;

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
      expect(
        modifiers.adjustedStartingGold,
        GameBalance.startingGold,
      );
      expect(
        modifiers.adjustedStartingBaseHealth,
        GameBalance.initialBaseHealth,
      );
    });

    test('fromProgress with no clears returns empty modifiers', () {
      final modifiers = CampaignModifiers.fromProgress(
        CampaignProgress(),
        stages,
      );

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
    });

    test('fromProgress with only bonusGold stage cleared grants gold', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'side-a': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(progress, stages);

      expect(modifiers.bonusGold, GameBalance.salvageRiftGoldBonus);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
      expect(
        modifiers.adjustedStartingGold,
        GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
      );
    });

    test('fromProgress with only bonusHealth stage cleared grants health', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'side-b': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(progress, stages);

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, GameBalance.voidBastionHealthBonus);
      expect(modifiers.hasChallengeBadge, isFalse);
      expect(
        modifiers.adjustedStartingBaseHealth,
        GameBalance.initialBaseHealth + GameBalance.voidBastionHealthBonus,
      );
    });

    test('fromProgress with both side stages cleared grants badge', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'side-a': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
          'side-b': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(progress, stages);

      expect(modifiers.bonusGold, GameBalance.salvageRiftGoldBonus);
      expect(modifiers.bonusHealth, GameBalance.voidBastionHealthBonus);
      expect(modifiers.hasChallengeBadge, isTrue);
    });

    test('fromProgress ignores main stage clears for badge', () {
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
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(progress, stages);

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/campaign_progress_test.dart`
Expected: FAIL — `CampaignModifiers` is not defined.

- [ ] **Step 3: Implement CampaignModifiers**

Add the `CampaignModifiers` class at the end of `lib/game/campaign/campaign_progress.dart` (after the `CampaignProgress` class closing brace, before the end of file):

```dart
class CampaignModifiers {
  const CampaignModifiers({
    this.bonusGold = 0,
    this.bonusHealth = 0,
    this.hasChallengeBadge = false,
  });

  final int bonusGold;
  final int bonusHealth;
  final bool hasChallengeBadge;

  int get adjustedStartingGold => GameBalance.startingGold + bonusGold;
  int get adjustedStartingBaseHealth =>
      GameBalance.initialBaseHealth + bonusHealth;

  static const CampaignModifiers empty = CampaignModifiers();

  static CampaignModifiers fromProgress(
    CampaignProgress progress,
    Iterable<StageDefinition> stages,
  ) {
    var bonusGold = 0;
    var bonusHealth = 0;
    final sideStageIds = <String>[];

    for (final stage in stages) {
      if (!stage.isMainPath) {
        sideStageIds.add(stage.id);
      }

      if (!progress.isCleared(stage.id)) {
        continue;
      }

      switch (stage.reward) {
        case CampaignReward.bonusGold:
          bonusGold += GameBalance.salvageRiftGoldBonus;
        case CampaignReward.bonusHealth:
          bonusHealth += GameBalance.voidBastionHealthBonus;
        case CampaignReward.challengeBadge:
          break;
        case null:
          break;
      }
    }

    final allSideStagesCleared = sideStageIds.isNotEmpty &&
        sideStageIds.every(progress.isCleared);

    return CampaignModifiers(
      bonusGold: bonusGold,
      bonusHealth: bonusHealth,
      hasChallengeBadge: allSideStagesCleared,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/campaign_progress_test.dart`
Expected: PASS

- [ ] **Step 5: Run analyze and commit**

Run: `flutter analyze`
Expected: No issues.

```bash
git add lib/game/campaign/campaign_progress.dart test/game/campaign_progress_test.dart
git commit -m "feat: add CampaignModifiers value object with fromProgress (HPA-94)"
```

---

### Task 3: Assign rewards to side stages and extend validation

**Files:**
- Modify: `lib/game/campaign/orion_campaign.dart:37-88` (salvage-rift and void-bastion StageDefinitions) and `:130-206` (validateStages)
- Modify: `test/game/orion_campaign_test.dart` (add validation tests for rewards)

**Interfaces:**
- Consumes: `CampaignReward` enum, `StageDefinition.reward` field (from Task 1).
- Produces: `salvage-rift` stage with `reward: CampaignReward.bonusGold`, `void-bastion` stage with `reward: CampaignReward.bonusHealth`. Extended `validateStages` that guards reward assignments.

- [ ] **Step 1: Write failing tests for reward validation**

In `test/game/orion_campaign_test.dart`, add tests inside the existing `group('OrionCampaign', ...)`:

```dart
    test('side stages carry campaign rewards and main stages do not', () {
      expect(
        OrionCampaign.stageById('salvage-rift').reward,
        CampaignReward.bonusGold,
      );
      expect(
        OrionCampaign.stageById('void-bastion').reward,
        CampaignReward.bonusHealth,
      );
      for (final stage in OrionCampaign.mainStages) {
        expect(stage.reward, isNull, reason: stage.id);
      }
    });

    test('validation rejects main stage with a reward', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1, reward: CampaignReward.bonusGold),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5),
        _stage(
          id: 'side-a',
          isMainPath: false,
          reward: CampaignReward.bonusGold,
        ),
        _stage(
          id: 'side-b',
          isMainPath: false,
          reward: CampaignReward.bonusHealth,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(
        errors,
        contains('stage-1 main stage must not have a reward.'),
      );
    });

    test('validation rejects side stage without a reward', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5),
        _stage(id: 'side-a', isMainPath: false),
        _stage(
          id: 'side-b',
          isMainPath: false,
          reward: CampaignReward.bonusHealth,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(
        errors,
        contains('side-a side stage must have a reward.'),
      );
    });

    test('validation rejects challengeBadge on an individual stage', () {
      final invalidStages = [
        _stage(id: 'stage-1', mainPathOrder: 1),
        _stage(id: 'stage-2', mainPathOrder: 2),
        _stage(id: 'stage-3', mainPathOrder: 3),
        _stage(id: 'stage-4', mainPathOrder: 4),
        _stage(id: 'stage-5', mainPathOrder: 5),
        _stage(
          id: 'side-a',
          isMainPath: false,
          reward: CampaignReward.bonusGold,
        ),
        _stage(
          id: 'side-b',
          isMainPath: false,
          reward: CampaignReward.challengeBadge,
        ),
      ];

      final errors = OrionCampaign.validateStages(invalidStages);

      expect(
        errors,
        contains(
          'side-b must not carry challengeBadge; it is compound-derived.',
        ),
      );
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/orion_campaign_test.dart`
Expected: FAIL — side stages don't have rewards yet, validation doesn't check rewards.

- [ ] **Step 3: Assign rewards to side stages**

In `lib/game/campaign/orion_campaign.dart`, add `reward: CampaignReward.bonusGold` to the salvage-rift `StageDefinition` (around line 37-49) and `reward: CampaignReward.bonusHealth` to the void-bastion `StageDefinition` (around line 76-88):

For salvage-rift:
```dart
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
    ),
```

For void-bastion:
```dart
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
    ),
```

- [ ] **Step 4: Extend validateStages with reward checks**

In `lib/game/campaign/orion_campaign.dart`, inside `validateStages`, add reward validation after the existing side-stage `mainPathOrder` check (after line 174). Add this block before the `sortedMainPathOrders` line:

```dart
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
        statRewardCounts[reward] =
            (statRewardCounts[reward] ?? 0) + 1;
      }
    }
    for (final entry in statRewardCounts.entries) {
      if (entry.value > 1) {
        errors.add(
          '${entry.key} reward appears on ${entry.value} stages; expected at most one.',
        );
      }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/game/orion_campaign_test.dart`
Expected: PASS

- [ ] **Step 6: Run full suite and commit**

Run: `flutter test`
Expected: All tests pass.

```bash
git add lib/game/campaign/orion_campaign.dart test/game/orion_campaign_test.dart
git commit -m "feat: assign campaign rewards to side stages with validation (HPA-94)"
```

---

### Task 4: GameSession effective starting values, damageBase clamp, restart fix

**Files:**
- Modify: `lib/game/rules/game_session.dart:7-18` (constructor), `:241-251` (damageBase), `:255-262` (restart)
- Modify: `test/game/game_session_test.dart`

**Interfaces:**
- Consumes: `GameBalance.startingGold`, `GameBalance.initialBaseHealth` (existing).
- Produces: `GameSession.startingGold` (int), `GameSession.startingBaseHealth` (int) — public final fields. `damageBase` clamps to `startingBaseHealth`. `restart()` resets to `startingGold`/`startingBaseHealth`.

- [ ] **Step 1: Write failing tests for starting values, clamp, and restart**

Add tests to `test/game/game_session_test.dart` inside the existing `group('GameSession', ...)`:

```dart
    test('stores effective starting gold and base health', () {
      final session = GameSession.initial(gold: 200, baseHealth: 25);

      expect(session.startingGold, 200);
      expect(session.startingBaseHealth, 25);
    });

    test('starting values default to GameBalance when no override', () {
      final session = GameSession.initial();

      expect(session.startingGold, GameBalance.startingGold);
      expect(session.startingBaseHealth, GameBalance.initialBaseHealth);
    });

    test('damageBase does not clamp below startingBaseHealth ceiling', () {
      final session = GameSession.initial(baseHealth: 25);
      session.startWave();

      session.damageBase(1);

      expect(session.baseHealth, 24);
    });

    test('restart restores effective starting values, not GameBalance defaults', () {
      final session = GameSession.initial(gold: 200, baseHealth: 25);
      session.startWave();
      session.damageBase(5);
      session.rewardKill(50);

      session.restart();

      expect(session.gold, 200);
      expect(session.baseHealth, 25);
      expect(session.phase, GamePhase.build);
    });
```

(The `snapshot().startingBaseHealth` test is added in Task 5 alongside the `GameSnapshot` field.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/game_session_test.dart`
Expected: FAIL — `startingGold`, `startingBaseHealth` not defined; `snapshot().startingBaseHealth` not defined.

- [ ] **Step 3: Add startingGold and startingBaseHealth fields**

In `lib/game/rules/game_session.dart`, update the constructor and add the fields (lines 6-18):

```dart
class GameSession {
  GameSession.initial({StageDefinition? stage, int? gold, int? baseHealth})
    : stage = stage ?? OrionCampaign.stageOne,
      startingGold = gold ?? GameBalance.startingGold,
      startingBaseHealth = baseHealth ?? GameBalance.initialBaseHealth,
      _gold = gold ?? GameBalance.startingGold,
      _baseHealth = baseHealth ?? GameBalance.initialBaseHealth {
    if (this.stage.waves.isEmpty) {
      throw ArgumentError.value(
        this.stage.id,
        'stage',
        'Stage must define at least one wave',
      );
    }
  }

  final StageDefinition stage;
  final int startingGold;
  final int startingBaseHealth;
  final Map<GridPosition, PlacedTower> _towersByPosition = {};
  int _nextTowerId = 1;
  int _gold;
  int _baseHealth;
  int _waveIndex = 0;
  GamePhase _phase = GamePhase.build;
```

- [ ] **Step 4: Fix damageBase clamp**

In `lib/game/rules/game_session.dart`, change line 245-247 from:

```dart
    _baseHealth = (_baseHealth - amount)
        .clamp(0, GameBalance.initialBaseHealth)
        .toInt();
```

to:

```dart
    _baseHealth = (_baseHealth - amount)
        .clamp(0, startingBaseHealth)
        .toInt();
```

- [ ] **Step 5: Fix restart to use stored starting values**

In `lib/game/rules/game_session.dart`, change lines 255-262 from:

```dart
  void restart() {
    _towersByPosition.clear();
    _nextTowerId = 1;
    _gold = GameBalance.startingGold;
    _baseHealth = GameBalance.initialBaseHealth;
    _waveIndex = 0;
    _phase = GamePhase.build;
  }
```

to:

```dart
  void restart() {
    _towersByPosition.clear();
    _nextTowerId = 1;
    _gold = startingGold;
    _baseHealth = startingBaseHealth;
    _waveIndex = 0;
    _phase = GamePhase.build;
  }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/game/game_session_test.dart`
Expected: PASS for all tests added in this task.

- [ ] **Step 7: Run full suite and commit**

Run: `flutter test`
Expected: All tests pass.

```bash
git add lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: store effective starting values and fix damageBase/restart clamps (HPA-94)"
```

---

### Task 5: StageResult.fromVictoryBaseHealth signature change and GameSnapshot.startingBaseHealth

This is the breaking-change task. All callers of `StageResult.fromVictoryBaseHealth` and all `GameSnapshot` construction sites must be updated in this task.

**Files:**
- Modify: `lib/game/campaign/campaign_progress.dart:53-64` (StageResult.fromVictoryBaseHealth)
- Modify: `lib/game/models/game_models.dart:355-396` (GameSnapshot)
- Modify: `lib/game/rules/game_session.dart:71-89` (snapshot method)
- Modify: `lib/game/orion_defense_game.dart:697` (_onPhaseChange caller)
- Modify: `lib/game/ui/orion_game_page.dart:942` (_EndStatePanel), `:334-353` (_showCampaignPersistenceFailure)
- Modify: `test/game/campaign_progress_test.dart:8-44` (fromVictoryBaseHealth test calls)
- Modify: `test/game/orion_defense_game_test.dart:152` (result assertion)
- Modify: `test/widget_test.dart` (6 GameSnapshot constructions: lines ~84, ~177, ~668, ~721, ~770, ~824)
- Modify: `test/widget/sell_button_test.dart:145` (GameSnapshot construction)

**Interfaces:**
- Consumes: `GameSession.startingBaseHealth` (from Task 4).
- Produces: `StageResult.fromVictoryBaseHealth(int baseHealth, {required int startingBaseHealth})`, `GameSnapshot.startingBaseHealth` (int field).

- [ ] **Step 1: Write failing medal calculation tests**

In `test/game/campaign_progress_test.dart`, update the existing `'calculates medal thresholds from victory base health'` test (lines 8-30) to pass `startingBaseHealth`. Replace the entire test:

```dart
    test('calculates medal thresholds from victory base health', () {
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.initialBaseHealth,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: GameBalance.initialBaseHealth,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.silverMedalThreshold,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: GameBalance.silverMedalThreshold,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.silverMedalThreshold - 1,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: GameBalance.silverMedalThreshold - 1,
        ),
      );
    });
```

Update the `'clamps victory base health into the supported range'` test (lines 32-44):

```dart
    test('clamps victory base health into the supported range', () {
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.initialBaseHealth + 1,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: GameBalance.initialBaseHealth,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          -1,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 0),
      );
    });

    test('medal thresholds scale with bonus starting health', () {
      const bonusHealth = 25;

      expect(
        StageResult.fromVictoryBaseHealth(
          25,
          startingBaseHealth: bonusHealth,
        ),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 25),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          23,
          startingBaseHealth: bonusHealth,
        ),
        const StageResult(medal: StageMedal.silver, bestBaseHealth: 23),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          9,
          startingBaseHealth: bonusHealth,
        ),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 9),
      );
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/campaign_progress_test.dart`
Expected: FAIL — missing `startingBaseHealth` parameter.

- [ ] **Step 3: Update StageResult.fromVictoryBaseHealth**

In `lib/game/campaign/campaign_progress.dart`, replace the factory (lines 53-64):

```dart
  factory StageResult.fromVictoryBaseHealth(
    int baseHealth, {
    required int startingBaseHealth,
  }) {
    final normalizedBaseHealth = baseHealth
        .clamp(0, startingBaseHealth)
        .toInt();
    final medal = baseHealth >= startingBaseHealth
        ? StageMedal.gold
        : normalizedBaseHealth >= GameBalance.silverMedalThreshold
        ? StageMedal.silver
        : StageMedal.clear;

    return StageResult(medal: medal, bestBaseHealth: normalizedBaseHealth);
  }
```

Note: the medal check uses the raw `baseHealth` for the Gold comparison (so `25 >= 25` is Gold) before clamping. The `bestBaseHealth` is still clamped to `[0, startingBaseHealth]`.

- [ ] **Step 4: Add startingBaseHealth to GameSnapshot**

In `lib/game/models/game_models.dart`, add `required this.startingBaseHealth,` to the `GameSnapshot` constructor (after `required this.baseHealth,` around line 359) and add `final int startingBaseHealth;` to the fields (after `final int baseHealth;` around line 378).

Constructor addition:
```dart
  GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.startingBaseHealth,
    required this.waveNumber,
    // ... rest unchanged
```

Field addition:
```dart
  final int baseHealth;
  final int startingBaseHealth;
  final int waveNumber;
  // ... rest unchanged
```

- [ ] **Step 5: Update GameSession.snapshot() to include startingBaseHealth**

In `lib/game/rules/game_session.dart`, add `startingBaseHealth: startingBaseHealth,` to the `GameSnapshot` constructor call inside `snapshot()` (after `baseHealth: _baseHealth,` around line 74):

```dart
    return GameSnapshot(
      phase: _phase,
      gold: _gold,
      baseHealth: _baseHealth,
      startingBaseHealth: startingBaseHealth,
      waveNumber: waveNumber,
```

- [ ] **Step 6: Update OrionDefenseGame._onPhaseChange caller**

In `lib/game/orion_defense_game.dart`, update the `StageResult.fromVictoryBaseHealth` call at line 697:

```dart
      completion = StageCompletion(
        stage: stage,
        result: StageResult.fromVictoryBaseHealth(
          _session.baseHealth,
          startingBaseHealth: _session.startingBaseHealth,
        ),
      );
```

- [ ] **Step 7: Update _EndStatePanel and _showCampaignPersistenceFailure**

In `lib/game/ui/orion_game_page.dart`, update `_EndStatePanel.build` (line 942) — change the `fromVictoryBaseHealth` call and the display denominator:

```dart
    final result = didWin
        ? StageResult.fromVictoryBaseHealth(
            snapshot.baseHealth,
            startingBaseHealth: snapshot.startingBaseHealth,
          )
        : null;
```

And the display text (line 975), change `${GameBalance.initialBaseHealth}` to `${snapshot.startingBaseHealth}`:

```dart
                  Text(
                    '${result.medal.label} medal - '
                    'Base ${result.bestBaseHealth}/${snapshot.startingBaseHealth}',
```

In the same file, update `_showCampaignPersistenceFailure` (line 334) — add `startingBaseHealth: snapshot.startingBaseHealth,` to the `GameSnapshot` constructor call:

```dart
      game.stateNotifier.value = GameSnapshot(
        phase: snapshot.phase,
        gold: snapshot.gold,
        baseHealth: snapshot.baseHealth,
        startingBaseHealth: snapshot.startingBaseHealth,
        waveNumber: snapshot.waveNumber,
```

- [ ] **Step 8: Update all test GameSnapshot construction sites**

Every `GameSnapshot(...)` in tests must add `startingBaseHealth:`. Use the value from the snapshot being copied, or `GameBalance.initialBaseHealth` for new snapshots.

In `test/widget_test.dart`, for each of the 6 `GameSnapshot(...)` constructions, add `startingBaseHealth: snapshot.startingBaseHealth,` after the `baseHealth:` line. For example, at line 84:

```dart
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.won,
      gold: snapshot.gold,
      baseHealth: 14,
      startingBaseHealth: snapshot.startingBaseHealth,
      waveNumber: snapshot.waveTotal,
```

Repeat for each construction site — each one has a `snapshot` variable in scope whose `.startingBaseHealth` can be copied. For constructions that set a specific `baseHealth` value (like `baseHealth: 14`), still use `snapshot.startingBaseHealth` since that's the session's ceiling.

In `test/widget/sell_button_test.dart`, do the same at line 145 — add `startingBaseHealth: snapshot.startingBaseHealth,` after the `baseHealth:` line.

- [ ] **Step 9: Update orion_defense_game_test result assertion**

In `test/game/orion_defense_game_test.dart`, the test at line 141-153 creates a stage and verifies the completion result. The result is a `StageResult` compared with `==`, which doesn't call `fromVictoryBaseHealth` directly, so no change needed there. But verify it still passes — the `_session.startingBaseHealth` defaults to `GameBalance.initialBaseHealth`, so `fromVictoryBaseHealth` still produces the same result.

- [ ] **Step 10: Run full test suite**

Run: `flutter test`
Expected: All tests pass.

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 11: Commit**

```bash
git add lib/game/campaign/campaign_progress.dart lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart test/game/campaign_progress_test.dart test/widget_test.dart test/widget/sell_button_test.dart
git commit -m "feat: add startingBaseHealth to medal calc and snapshot (HPA-94)"
```

---

### Task 6: OrionDefenseGame modifiers parameter

**Files:**
- Modify: `lib/game/orion_defense_game.dart:36-43` (constructor)
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- Consumes: `CampaignModifiers.adjustedStartingGold` / `adjustedStartingBaseHealth` (from Task 2).
- Produces: `OrionDefenseGame.modifiers` field (`CampaignModifiers?`), constructor accepts optional `modifiers` param and passes adjusted gold/health to `GameSession.initial`.

- [ ] **Step 1: Write failing test**

Add to `test/game/orion_defense_game_test.dart` inside `main()`:

```dart
    test('applies campaign modifiers to session starting values', () {
      final game = OrionDefenseGame(
        stage: _emptyWaveStage(),
        modifiers: const CampaignModifiers(
          bonusGold: 30,
          bonusHealth: 5,
        ),
      );

      expect(game.snapshot.gold, GameBalance.startingGold + 30);
      expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth + 5);
      expect(
        game.snapshot.startingBaseHealth,
        GameBalance.initialBaseHealth + 5,
      );
    });

    test('defaults to no modifiers and baseline economy', () {
      final game = OrionDefenseGame(stage: _emptyWaveStage());

      expect(game.snapshot.gold, GameBalance.startingGold);
      expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth);
    });
```

Add the import at the top of the file:
```dart
import 'package:orion/game/campaign/campaign_progress.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/orion_defense_game_test.dart`
Expected: FAIL — `modifiers` parameter and `CampaignModifiers` import not found.

- [ ] **Step 3: Add modifiers parameter to OrionDefenseGame constructor**

In `lib/game/orion_defense_game.dart`, update the constructor (lines 36-43). The `_session` field is `final` so it must be in the initializer list:

```dart
class OrionDefenseGame extends FlameGame with TapCallbacks, HasTimeScale {
  OrionDefenseGame({
    StageDefinition? stage,
    this.modifiers,
    this.onStageWon,
    this.onReturnToMap,
  }) : stage = stage ?? OrionCampaign.stageOne,
       _session = GameSession.initial(
         stage: stage ?? OrionCampaign.stageOne,
         gold: modifiers?.adjustedStartingGold,
         baseHealth: modifiers?.adjustedStartingBaseHealth,
       ) {
    _resetPacing();
  }

  final StageDefinition stage;
  final CampaignModifiers? modifiers;
  final ValueChanged<StageCompletion>? onStageWon;
  final VoidCallback? onReturnToMap;
  final GameSession _session;
```

Add the import at the top:
```dart
import 'campaign/campaign_progress.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/orion_defense_game_test.dart`
Expected: PASS

- [ ] **Step 5: Run full suite and commit**

Run: `flutter test`
Run: `flutter analyze`
Expected: All pass.

```bash
git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: add CampaignModifiers parameter to OrionDefenseGame (HPA-94)"
```

---

### Task 7: OrionGamePage — wire modifiers in _startStage, optimistic save with rollback

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart:152-170` (_startStage), `:187-237` (_saveStageCompletion)
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `CampaignModifiers.fromProgress` (from Task 2), `OrionDefenseGame(modifiers:)` (from Task 6).
- Produces: `_startStage` computes modifiers and passes to `OrionDefenseGame`. `_saveStageCompletion` optimistically updates `_progress` before save with rollback on failure.

- [ ] **Step 1: Write failing test for modifiers in _startStage**

This requires a widget test. Add to `test/widget_test.dart`:

```dart
  testWidgets(
    'starting a stage after clearing salvage rift applies bonus gold',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
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

      // Tap the salvage-rift stage node (it should be unlocked).
      await tester.tap(find.text('Rift'));
      await tester.pumpAndSettle();

      expect(game, isNotNull);
      expect(
        game!.snapshot.gold,
        GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
      );
    },
  );
```

Add imports at the top of `test/widget_test.dart` if not already present:
```dart
import 'package:orion/game/campaign/campaign_progress_store.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget_test.dart --name "starting a stage after clearing salvage rift"`
Expected: FAIL — `_startStage` doesn't compute modifiers yet.

- [ ] **Step 3: Wire modifiers into _startStage**

In `lib/game/ui/orion_game_page.dart`, update `_startStage` (lines 152-170) to compute and pass modifiers:

```dart
  void _startStage(StageDefinition stage) {
    if (!_progress.isUnlocked(stage)) {
      _showLockedStageFeedback(stage);
      return;
    }

    final modifiers = CampaignModifiers.fromProgress(
      _progress,
      OrionCampaign.stages,
    );
    final game = OrionDefenseGame(
      stage: stage,
      modifiers: modifiers,
      onStageWon: _recordStageCompletion,
      onReturnToMap: _returnToMap,
    );
    widget.onGameCreated?.call(game);

    setState(() {
      _activeStage = stage;
      _mapFeedback = null;
      _game = game;
    });
  }
```

Add the import at the top:
```dart
import '../campaign/campaign_progress.dart';
```
(This import is likely already present from `CampaignProgress` usage — check first.)

- [ ] **Step 4: Implement optimistic save with rollback**

In `lib/game/ui/orion_game_page.dart`, update `_saveStageCompletion` (lines 187-237). Replace the section after the no-op check (line 213) through the end of the method:

```dart
    if (progress.resultFor(completion.stage.id) == priorResult) {
      return;
    }

    final priorProgressState = _progress;
    setState(() {
      _progress = progress;
    });

    try {
      await store.save(progress);
    } catch (_) {
      if (!mounted || saveGeneration != _progressGeneration) {
        return;
      }

      setState(() {
        _progress = priorProgressState;
      });
      _showCampaignPersistenceFailure();
      return;
    }

    if (!mounted) {
      return;
    }

    if (saveGeneration != _progressGeneration) {
      await _resetStoreAfterStaleSave(store);
      return;
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widget_test.dart`
Expected: PASS

- [ ] **Step 6: Run full suite and commit**

Run: `flutter test`
Run: `flutter analyze`
Expected: All pass.

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: wire campaign modifiers into _startStage with optimistic save (HPA-94)"
```

---

### Task 8: WorldMapView reward labels and challenge badge

**Files:**
- Modify: `lib/game/ui/world_map_view.dart` (add modifiers param, reward labels, badge)
- Modify: `lib/game/ui/orion_game_page.dart:96-103` (pass modifiers to WorldMapView)
- Modify: `test/widget_test.dart` (add world map reward display tests)

**Interfaces:**
- Consumes: `CampaignModifiers.hasChallengeBadge` (from Task 2), `StageDefinition.reward` (from Task 1), `CampaignProgress.isCleared` (existing), `GameBalance.salvageRiftGoldBonus` / `voidBastionHealthBonus` (from Task 1).
- Produces: `WorldMapView(modifiers:)` optional parameter, reward labels on side-stage nodes, challenge badge summary line.

- [ ] **Step 1: Write failing tests for reward display**

Add to `test/widget_test.dart`:

```dart
  testWidgets(
    'world map shows reward teaser on uncleared side stage',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(progressStore: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reward: +30 Gold'), findsOneWidget);
      expect(find.text('Reward: +5 HP'), findsOneWidget);
    },
  );

  testWidgets(
    'world map shows earned reward label on cleared side stage',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(progressStore: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+30 Gold'), findsOneWidget);
    },
  );

  testWidgets(
    'world map shows challenge badge when both side stages are cleared',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );
      await store.save(
        CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'asteroid-foundry': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'aurora-gate': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'void-bastion': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(progressStore: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Challenge Badge Earned - All side stages cleared'),
        findsOneWidget,
      );
    },
  );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget_test.dart --name "world map"`
Expected: FAIL — reward labels and badge not implemented.

- [ ] **Step 3: Add modifiers parameter to WorldMapView**

In `lib/game/ui/world_map_view.dart`, add `this.modifiers` to `WorldMapView`:

```dart
class WorldMapView extends StatelessWidget {
  const WorldMapView({
    super.key,
    required this.stages,
    required this.progress,
    this.modifiers,
    this.feedback,
    required this.onStageSelected,
    this.onLockedStageSelected,
    required this.onResetCampaign,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final CampaignModifiers? modifiers;
  final String? feedback;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;
  final VoidCallback onResetCampaign;
```

Pass `modifiers` through to `_StageMap`:

```dart
            Expanded(
              child: _StageMap(
                stages: stages,
                progress: progress,
                modifiers: modifiers,
                onStageSelected: onStageSelected,
                onLockedStageSelected: onLockedStageSelected,
              ),
            ),
```

- [ ] **Step 4: Add challenge badge summary to the map header**

In `WorldMapView.build`, after the campaign-complete banner block (after line 82, before `const SizedBox(height: 16)`), add:

```dart
            if (modifiers?.hasChallengeBadge == true) ...[
              const SizedBox(height: 8),
              Text(
                'Challenge Badge Earned - All side stages cleared',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
```

- [ ] **Step 5: Add reward label to _StageNode**

In `lib/game/ui/world_map_view.dart`, add a reward label widget inside `_StageNode.build`, after the status label `Text` (after line 231). First, add a helper function before the `_StageNode` class:

```dart
String? _rewardLabel(StageDefinition stage, bool isCleared) {
  final reward = stage.reward;
  if (reward == null) {
    return null;
  }

  final amount = switch (reward) {
    CampaignReward.bonusGold => '+${GameBalance.salvageRiftGoldBonus} Gold',
    CampaignReward.bonusHealth => '+${GameBalance.voidBastionHealthBonus} HP',
    CampaignReward.challengeBadge => null,
  };

  if (amount == null) {
    return null;
  }

  return isCleared ? amount : 'Reward: $amount';
}
```

Then in `_StageNode.build`, compute the label before the return and render it after the status text:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final colors = _stageColors(theme.colorScheme, status, result);
    final rewardLabel = _rewardLabel(
      stage,
      status == StageProgressStatus.cleared,
    );

    return Material(
```

Then after the status label `Text` widget (after line 231), add:

```dart
              if (rewardLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  rewardLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.foreground,
                  ),
                ),
              ],
```

Add the `GameBalance` import to `world_map_view.dart`:
```dart
import '../models/game_models.dart';
```

- [ ] **Step 6: Check node height fits the extra line**

The `_StageMap` uses `const nodeHeight = 92.0`. With the additional reward line (~15px), content may be tight. If tests show clipping or the layout looks crowded, bump `nodeHeight` to `104.0`. Run the app or widget tests to verify visually. If bumped, the `Positioned` height also changes.

- [ ] **Step 7: Pass modifiers from OrionGamePage to WorldMapView**

In `lib/game/ui/orion_game_page.dart`, update the `WorldMapView` construction (lines 96-103):

```dart
        body: WorldMapView(
          stages: OrionCampaign.stages,
          progress: _progress,
          modifiers: CampaignModifiers.fromProgress(
            _progress,
            OrionCampaign.stages,
          ),
          feedback: _mapFeedback,
          onStageSelected: _startStage,
          onLockedStageSelected: _showLockedStageFeedback,
          onResetCampaign: _confirmResetCampaign,
        ),
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/widget_test.dart`
Expected: PASS

- [ ] **Step 9: Run full suite and commit**

Run: `flutter test`
Run: `flutter analyze`
Expected: All pass.

```bash
git add lib/game/ui/world_map_view.dart lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: show reward labels and challenge badge on world map (HPA-94)"
```

---

### Task 9: Persistence round-trip and restart-boundary tests

**Files:**
- Modify: `test/game/campaign_progress_test.dart` (persistence round-trip)
- Modify: `test/game/orion_defense_game_test.dart` (restart boundary)
- Modify: `test/game/campaign_progress_store_test.dart` (store round-trip with modifiers)

**Interfaces:**
- Consumes: `InMemoryCampaignProgressStore`, `CampaignModifiers.fromProgress`, `OrionCampaign.stages`, `OrionDefenseGame.restart`.

- [ ] **Step 1: Write persistence round-trip test**

Add to `test/game/campaign_progress_store_test.dart` inside `main()`:

```dart
    test(
      'side-stage results persist and produce correct campaign modifiers',
      () async {
        final store = InMemoryCampaignProgressStore(
          knownStages: OrionCampaign.stages,
        );

        final progress = CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'void-bastion': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        );

        await store.save(progress);

        final loaded = await store.load();
        final modifiers = CampaignModifiers.fromProgress(
          loaded,
          OrionCampaign.stages,
        );

        expect(modifiers.bonusGold, GameBalance.salvageRiftGoldBonus);
        expect(modifiers.bonusHealth, GameBalance.voidBastionHealthBonus);
        expect(modifiers.hasChallengeBadge, isTrue);
      },
    );
```

- [ ] **Step 2: Write restart-boundary test**

Add to `test/game/orion_defense_game_test.dart` inside `main()`:

```dart
    test(
      'restart preserves original starting values, not newly earned bonuses',
      () {
        // Simulate a session created BEFORE the side stage was cleared:
        // no modifiers, so baseline economy.
        final game = OrionDefenseGame(stage: _emptyWaveStage());

        // The session starts with baseline values.
        expect(game.snapshot.gold, GameBalance.startingGold);
        expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth);

        game.restart();

        // After restart, still baseline — restart does not re-evaluate
        // campaign modifiers.
        expect(game.snapshot.gold, GameBalance.startingGold);
        expect(game.snapshot.baseHealth, GameBalance.initialBaseHealth);
        expect(
          game.snapshot.startingBaseHealth,
          GameBalance.initialBaseHealth,
        );
      },
    );
```

- [ ] **Step 3: Write optimistic-update rollback test**

Add to `test/widget_test.dart`:

```dart
  testWidgets(
    'save failure rolls back optimistic progress and shows feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = _FailingSaveStore(knownStages: OrionCampaign.stages);

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

      // Start the first stage.
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      // Simulate a victory.
      final snapshot = game!.stateNotifier.value;
      game!.stateNotifier.value = GameSnapshot(
        phase: GamePhase.won,
        gold: snapshot.gold,
        baseHealth: snapshot.baseHealth,
        startingBaseHealth: snapshot.startingBaseHealth,
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
      await tester.pumpAndSettle();

      // The save fails, so the feedback message should appear.
      expect(find.text('Could not save campaign progress.'), findsOneWidget);
    },
  );
```

Add the failing store helper at the end of the file (after `main()` closes):

```dart
class _FailingSaveStore extends InMemoryCampaignProgressStore {
  _FailingSaveStore({required super.knownStages});

  @override
  Future<void> save(CampaignProgress progress) async {
    throw StateError('Failed to save campaign progress.');
  }
}
```

- [ ] **Step 4: Run full suite and verify**

Run: `flutter test`
Run: `flutter analyze`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add test/game/campaign_progress_store_test.dart test/game/orion_defense_game_test.dart test/widget_test.dart
git commit -m "test: add persistence round-trip and restart-boundary tests (HPA-94)"
```

---

### Task 10: Final verification

- [ ] **Step 1: Run format**

Run: `dart format .`

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Run all tests**

Run: `flutter test`
Expected: All pass.

- [ ] **Step 4: Commit any formatting changes**

```bash
git add -A
git commit -m "style: dart-format campaign rewards (HPA-94)" || true
```

- [ ] **Step 5: Manual smoke test**

Launch the app on a device or emulator. Verify:
- World map shows reward teasers on uncleared side stages ("Reward: +30 Gold", "Reward: +5 HP").
- Clear a side stage, return to map, start another mission — verify bonus gold/health is applied.
- Victory panel shows correct denominator (e.g., "Base 20/20" not "Base 20/20" when no bonus; "Base 25/25" with bonus).
- Clear both side stages — challenge badge appears on map.
- Restart a mission — starting values stay the same as the original session.
