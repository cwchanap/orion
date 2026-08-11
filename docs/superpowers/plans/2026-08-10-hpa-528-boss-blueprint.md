# HPA-528 Boss Blueprint Reward Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove Orion's permanent reward loop by making one Relay Breaker blueprint unlock Relay Calibration after the first committed Outpost Alpha clear, then make the reward eligible on the next attempt without adding persistence or combat infrastructure.

**Architecture:** Keep `runModuleCatalog` as the module-definition source and add one focused unlock map that marks only modules gated by stage clears. `OrionGamePage` derives both existing `CampaignModifiers` and module eligibility from the same committed state; a same-object Replay refreshes both inputs together through `OrionDefenseGame.restart(...)`. HPA-525's existing Mission Report reward slot communicates pending/saved/failed truth.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- Exactly one blueprint ships: Outpost Alpha / Relay Breaker → `Relay Calibration`.
- Relay Calibration is exactly +8% range and -8% attack interval for all towers.
- Reuse existing `rangeMultiplier` / `fireIntervalMultiplier`; no new combat stat or attack path.
- Ownership is derived from committed `CampaignProgress`; no `CampaignSave` ownership field or schema migration.
- `runModuleCatalog` remains the definition catalog; do not add a second hand-maintained base-module list.
- Locked-module metadata lives only in `run_module_unlocks.dart` as module → unlock-stage rows.
- Active attempts freeze their campaign modifiers and eligible module set.
- Replay/Retry is a new attempt boundary and refreshes **both** progress-derived inputs from the same committed snapshot.
- The completed first-clear attempt never gains Relay Calibration retroactively.
- Reuse HPA-525 `_persistSave`, `_committedProgress`, `_committedTechTree`, `MissionSaveState`, and `MissionRewardFact`.
- Capture prior saved mission result from `_committedProgress`, not optimistic `_progress`.
- A replay of already-cleared Outpost Alpha never repeats blueprint recovery copy.
- Keep the map/briefing presentation specific to Outpost Alpha; no reward registry or Codex section.
- Keep `ModuleOfferPicker` ignorant of unlocks; it receives an already-filtered candidate list.
- Do not add pity, forced offers, weighting, rerolls, or unlock-aware picker behavior.
- Keep `nodeHeight = 124`; the existing side-stage reward rows already prove four-row nodes fit. Fix the new row treatment, not global map geometry, if a regression appears.
- Target the existing 360×640 logical-pixel baseline.
- Final gates: strict format, `flutter analyze`, focused tests, full `flutter test`, and one human first-clear → next-attempt product check.

## File Map

### Create

- `lib/game/rules/run_module_unlocks.dart` — pure catalog + committed progress → eligible module IDs.
- `test/game/run_module_unlocks_test.dart` — unlock/base-pool derivation tests.

### Modify

- `lib/game/models/game_models.dart` — add `RunModuleId.relayCalibration` and its catalog definition/copy.
- `lib/game/rules/game_session.dart` — filter candidates by eligible IDs; refresh eligible IDs and existing campaign modifiers on restart.
- `lib/game/orion_defense_game.dart` — thread construction/restart inputs and expose narrow test observation.
- `lib/game/ui/orion_game_page.dart` — derive run inputs from committed state, refresh both on Replay, and populate `MissionRewardFact`.
- `lib/game/ui/world_map_view.dart` — add one Alpha blueprint status row using the existing reward-row treatment.
- `test/game/run_module_rules_test.dart` — verify Relay Calibration uses existing stat seams.
- `test/game/module_offer_picker_test.dart` — replace the hard six-entry catalog guard with catalog completeness + locked/base separation.
- `test/game/game_session_test.dart` — candidate eligibility, attempt freeze guardrail, and restart refresh coverage.
- `test/game/orion_defense_game_test.dart` — game-level restart forwarding.
- `test/widget_test.dart` — committed first-clear → Replay wiring, reward copy, side-stage reward refresh, map/briefing, and reset integration.

No intended changes to `CampaignProgress`, `CampaignSave`, `CampaignProgressStore`, save codecs, `MissionReportContent`, `MissionReportPanel`, or `ModuleOfferPicker`.

---

## Task 1: Define Relay Calibration and single-source unlock metadata

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Create: `lib/game/rules/run_module_unlocks.dart`
- Create: `test/game/run_module_unlocks_test.dart`
- Modify: `test/game/run_module_rules_test.dart`
- Modify: `test/game/module_offer_picker_test.dart`

**Interfaces:**
- Produces `RunModuleId.relayCalibration`.
- Produces `RunModuleUnlocks.availableFor(CampaignProgress)` and `RunModuleUnlocks.baseModules`.
- Keeps `runModuleCatalog` as the complete definition catalog.
- Does not change `RunModuleRules.applyTowerStats(...)` or `ModuleOfferPicker`.

- [ ] **Step 1: Write unlock-rule tests first**

Create `test/game/run_module_unlocks_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/run_module_unlocks.dart';

const clearedResult = StageResult(
  medal: StageMedal.clear,
  bestBaseHealth: 5,
);

void main() {
  test('base modules contain every ungated catalog module', () {
    final catalogIds = runModuleCatalog
        .map((definition) => definition.id)
        .toSet();

    expect(RunModuleUnlocks.baseModules, isSubsetOf(catalogIds));
    expect(
      RunModuleUnlocks.baseModules,
      isNot(contains(RunModuleId.relayCalibration)),
    );
    expect(
      catalogIds.difference(RunModuleUnlocks.baseModules),
      {RunModuleId.relayCalibration},
    );
  });

  test('committed Outpost Alpha clear unlocks Relay Calibration', () {
    final progress = CampaignProgress().recordResult(
      OrionCampaign.stageOneId,
      clearedResult,
    );

    expect(
      RunModuleUnlocks.availableFor(progress),
      contains(RunModuleId.relayCalibration),
    );
  });

  test('unrelated clear does not unlock Relay Calibration', () {
    final progress = CampaignProgress().recordResult(
      'nebula-relay',
      clearedResult,
    );

    expect(
      RunModuleUnlocks.availableFor(progress),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });

  test('empty progress removes the derived unlock', () {
    expect(
      RunModuleUnlocks.availableFor(CampaignProgress()),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });
}
```

- [ ] **Step 2: Verify the unlock tests are red**

```bash
flutter test test/game/run_module_unlocks_test.dart
```

Expected: compile failure because `relayCalibration` and `RunModuleUnlocks` do not exist.

- [ ] **Step 3: Add the seventh module definition only**

In `lib/game/models/game_models.dart`:

```dart
enum RunModuleId {
  heavyCaliber,
  overclockRelay,
  longSight,
  emergencySalvage,
  cryoReservoir,
  rocketFusing,
  relayCalibration,
}
```

Extend `RunModuleDefinition.effectText`:

```dart
RunModuleId.relayCalibration =>
  'All towers gain ${percent(rangeMultiplier - 1)} range; '
      'attack interval drops ${percent(1 - fireIntervalMultiplier)}.',
```

Append the catalog entry:

```dart
RunModuleDefinition(
  id: RunModuleId.relayCalibration,
  title: 'Relay Calibration',
  affinity: RunModuleAffinity.universal,
  rangeMultiplier: 1.08,
  fireIntervalMultiplier: 0.92,
),
```

Do not add an `initialRunModuleIds` constant, new affinity, or `TowerStats` field.

- [ ] **Step 4: Implement the focused unlock map**

Create `lib/game/rules/run_module_unlocks.dart`:

```dart
import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../models/game_models.dart';

const _unlockStageByModule = <RunModuleId, String>{
  RunModuleId.relayCalibration: OrionCampaign.stageOneId,
};

abstract final class RunModuleUnlocks {
  static bool hasFirstBlueprint(CampaignProgress progress) =>
      progress.isCleared(OrionCampaign.stageOneId);

  static Set<RunModuleId> availableFor(CampaignProgress progress) =>
      Set<RunModuleId>.unmodifiable(
        runModuleCatalog
            .map((definition) => definition.id)
            .where((id) {
              final unlockStageId = _unlockStageByModule[id];
              return unlockStageId == null ||
                  progress.isCleared(unlockStageId);
            }),
      );

  static final Set<RunModuleId> baseModules =
      availableFor(CampaignProgress());
}
```

Future ordinary catalog modules require no unlock row. A future blueprint adds one row here.

- [ ] **Step 5: Add the stat-seam regression**

In `test/game/run_module_rules_test.dart`:

```dart
test('Relay Calibration reuses range and fire-interval multipliers', () {
  final base = GameBalance.towerStats(TowerType.laser, level: 1);

  final resolved = RunModuleRules.applyTowerStats(
    base,
    const [RunModuleId.relayCalibration],
  );

  expect(resolved.range, closeTo(base.range * 1.08, 0.0001));
  expect(resolved.fireInterval, closeTo(base.fireInterval * 0.92, 0.0001));
  expect(resolved.damage, base.damage);
  expect(resolved.splashRadius, base.splashRadius);
});
```

No production edit to `run_module_rules.dart` should be required.

- [ ] **Step 6: Replace the hard catalog-length guard**

`test/game/module_offer_picker_test.dart` currently asserts `hasLength(6)`. Replace that brittle count with catalog completeness and unlock separation:

```dart
test('catalog covers every RunModuleId exactly once', () {
  final catalogIds = runModuleCatalog
      .map((definition) => definition.id)
      .toList(growable: false);

  expect(catalogIds.toSet(), RunModuleId.values.toSet());
  expect(catalogIds.toSet(), hasLength(catalogIds.length));
  expect(
    catalogIds.toSet().difference(RunModuleUnlocks.baseModules),
    {RunModuleId.relayCalibration},
  );

  final relay = runModuleDefinition(RunModuleId.relayCalibration);
  expect(relay.rangeMultiplier, 1.08);
  expect(relay.fireIntervalMultiplier, 0.92);
});
```

Import `run_module_unlocks.dart` in that test. Keep existing picker-distinctness/misuse tests unchanged.

- [ ] **Step 7: Run all Task 1 tests**

```bash
flutter test \
  test/game/run_module_unlocks_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/module_offer_picker_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add \
  lib/game/models/game_models.dart \
  lib/game/rules/run_module_unlocks.dart \
  test/game/run_module_unlocks_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/module_offer_picker_test.dart
git commit -m "feat: define first boss blueprint module"
```

---

## Task 2: Make Replay refresh all committed run inputs consistently

**Files:**
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- `GameSession.initial({..., Iterable<RunModuleId>? availableRunModules})`
- `GameSession.restart({CampaignModifiers? campaignModifiers, Iterable<RunModuleId>? availableRunModules})`
- `Set<RunModuleId> get GameSession.availableRunModules`
- `OrionDefenseGame({..., Iterable<RunModuleId>? availableRunModules})`
- `OrionDefenseGame.restart({CampaignModifiers? campaignModifiers, Iterable<RunModuleId>? availableRunModules})`
- `@visibleForTesting Set<RunModuleId> get OrionDefenseGame.availableRunModules`
- Existing `OrionDefenseGame.campaignModifiers` remains readable as a getter backed by the session.

- [ ] **Step 1: Write default/unlocked candidate tests**

In `test/game/game_session_test.dart`, use a recording picker:

```dart
final class _RecordingOfferPicker implements ModuleOfferPicker {
  final List<List<RunModuleId>> candidateHistory = [];

  @override
  List<RunModuleId> pick(
    List<RunModuleId> candidates, {
    required int count,
  }) {
    candidateHistory.add(List<RunModuleId>.unmodifiable(candidates));
    return List<RunModuleId>.unmodifiable(candidates.take(count));
  }
}

void clearTwoWaves(GameSession session) {
  expect(session.startWave(), isTrue);
  session.finishActiveWave();
  expect(session.startWave(), isTrue);
  session.finishActiveWave();
}
```

Tests:

```dart
test('default session excludes the locked blueprint', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(offerPicker: picker);

  clearTwoWaves(session);

  expect(
    picker.candidateHistory.single,
    isNot(contains(RunModuleId.relayCalibration)),
  );
});

test('explicit unlocked eligibility can offer Relay Calibration', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(
    offerPicker: picker,
    availableRunModules: {
      ...RunModuleUnlocks.baseModules,
      RunModuleId.relayCalibration,
    },
  );

  clearTwoWaves(session);

  expect(
    picker.candidateHistory.single,
    contains(RunModuleId.relayCalibration),
  );
  expect(session.pendingRunModuleOffer!.moduleIds.toSet(), hasLength(3));
});
```

- [ ] **Step 2: Add the attempt-freeze guardrail**

This is a guardrail, not the primary lifecycle proof:

```dart
test('eligible module set stays frozen during one attempt', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(
    offerPicker: picker,
    availableRunModules: RunModuleUnlocks.baseModules,
  );

  clearTwoWaves(session);
  final firstOffer = session.pendingRunModuleOffer!;
  expect(session.selectRunModule(
    offerId: firstOffer.offerId,
    moduleId: firstOffer.moduleIds.first,
  ), isTrue);

  clearTwoWaves(session);

  expect(
    picker.candidateHistory.every(
      (ids) => !ids.contains(RunModuleId.relayCalibration),
    ),
    isTrue,
  );
});
```

- [ ] **Step 3: Add the campaign-modifier restart regression**

```dart
test('restart refreshes starting resources from new campaign modifiers', () {
  final session = GameSession.initial();

  expect(session.gold, GameBalance.startingGold);
  expect(session.startingBaseHealth, GameBalance.initialBaseHealth);

  const refreshed = CampaignModifiers(
    bonusGold: 40,
    bonusHealth: 3,
  );
  session.restart(campaignModifiers: refreshed);

  expect(session.campaignModifiers, refreshed);
  expect(session.startingGold, GameBalance.startingGold + 40);
  expect(session.gold, GameBalance.startingGold + 40);
  expect(
    session.startingBaseHealth,
    GameBalance.initialBaseHealth + 3,
  );
  expect(session.baseHealth, GameBalance.initialBaseHealth + 3);
});
```

Outpost Alpha has no starting-health stage modifier, so the expected health is direct here.

- [ ] **Step 4: Verify Task 2 tests are red**

```bash
flutter test test/game/game_session_test.dart
```

Expected: compile/test failures because eligibility and modifier-refresh inputs do not exist.

- [ ] **Step 5: Make attempt configuration refreshable in `GameSession`**

Import `run_module_unlocks.dart`.

Replace final attempt fields with private mutable fields + getters:

```dart
int _startingGold;
int _startingBaseHealth;
CampaignModifiers _campaignModifiers;
Set<RunModuleId> _availableRunModules;

int get startingGold => _startingGold;
int get startingBaseHealth => _startingBaseHealth;
CampaignModifiers get campaignModifiers => _campaignModifiers;
Set<RunModuleId> get availableRunModules =>
    Set<RunModuleId>.unmodifiable(_availableRunModules);
```

Add nullable construction input:

```dart
Iterable<RunModuleId>? availableRunModules,
```

Resolve it during construction:

```dart
_availableRunModules = Set<RunModuleId>.unmodifiable(
  availableRunModules ?? RunModuleUnlocks.baseModules,
),
```

Keep the existing `gold` / `baseHealth` overrides for initial direct construction exactly as they work today.

- [ ] **Step 6: Filter `_moduleCandidates()` by eligibility**

Change only the `remaining` query:

```dart
final remaining = runModuleCatalog
    .where(
      (definition) =>
          _availableRunModules.contains(definition.id) &&
          !acquired.contains(definition.id),
    )
    .toList(growable: false);
```

Do not change affinity preference, fallback order, or picker behavior.

- [ ] **Step 7: Refresh both run inputs on explicit restart**

Replace `void restart()` with:

```dart
void restart({
  CampaignModifiers? campaignModifiers,
  Iterable<RunModuleId>? availableRunModules,
}) {
  if (campaignModifiers != null) {
    _campaignModifiers = campaignModifiers;
    _startingGold = campaignModifiers.adjustedStartingGold;
    _startingBaseHealth = StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth:
          campaignModifiers.adjustedStartingBaseHealth,
      stageModifiers: stage.modifiers,
    );
  }

  if (availableRunModules != null) {
    _availableRunModules =
        Set<RunModuleId>.unmodifiable(availableRunModules);
  }

  _towersByPosition.clear();
  _nextTowerId = 1;
  _gold = _startingGold;
  _baseHealth = _startingBaseHealth;
  _waveIndex = 0;
  _phase = GamePhase.build;
  _acquiredRunModules.clear();
  _pendingRunModuleOffer = null;
}
```

Update `resolveTowerStats` and `_effectiveClearBonus` to read `_campaignModifiers`.

When restart inputs are null, lower-level tests/callers retain their current attempt configuration.

- [ ] **Step 8: Thread the same inputs through `OrionDefenseGame`**

Use a constructor parameter rather than a final duplicate campaign field:

```dart
OrionDefenseGame({
  StageDefinition? stage,
  CampaignModifiers campaignModifiers = CampaignModifiers.empty,
  Iterable<RunModuleId>? availableRunModules,
  ModuleOfferPicker? moduleOfferPicker,
  this.onStageWon,
  this.onReturnToMap,
}) : stage = stage ?? OrionCampaign.stageOne,
     _session = GameSession.initial(
       stage: stage ?? OrionCampaign.stageOne,
       campaignModifiers: campaignModifiers,
       availableRunModules: availableRunModules,
       offerPicker: moduleOfferPicker,
     ) {
  _resetPacing();
}

CampaignModifiers get campaignModifiers => _session.campaignModifiers;

@visibleForTesting
Set<RunModuleId> get availableRunModules =>
    _session.availableRunModules;
```

Update restart:

```dart
void restart({
  CampaignModifiers? campaignModifiers,
  Iterable<RunModuleId>? availableRunModules,
}) {
  _clearCombatComponents(removeTowers: true);
  _resetWaveSpawnState();
  _nextEnemyId = 1;
  _clearSelection();
  _session.restart(
    campaignModifiers: campaignModifiers,
    availableRunModules: availableRunModules,
  );
  _resetPacing();
  _layoutBoardIfReady();
  _publishSnapshot();
}
```

- [ ] **Step 9: Add game-level forwarding coverage**

In `test/game/orion_defense_game_test.dart`:

```dart
test('restart forwards refreshed run inputs to the same game session', () {
  final game = OrionDefenseGame();
  const refreshed = CampaignModifiers(bonusGold: 25);

  game.restart(
    campaignModifiers: refreshed,
    availableRunModules: {
      ...RunModuleUnlocks.baseModules,
      RunModuleId.relayCalibration,
    },
  );

  expect(game.campaignModifiers, refreshed);
  expect(game.snapshot.gold, GameBalance.startingGold + 25);
  expect(
    game.availableRunModules,
    contains(RunModuleId.relayCalibration),
  );
  expect(game.snapshot.acquiredRunModules, isEmpty);
  expect(game.snapshot.pendingRunModuleOffer, isNull);
  expect(game.snapshot.phase, GamePhase.build);
});
```

- [ ] **Step 10: Run Task 2 tests**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart
```

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add \
  lib/game/rules/game_session.dart \
  lib/game/orion_defense_game.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart
git commit -m "fix: refresh committed run inputs on replay"
```

---

## Task 3: Wire committed state to launch, Replay, and Mission Report truth

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Both normal launch and Replay derive campaign modifiers + module eligibility from `_committedProgress` / `_committedTechTree`.
- `_missionPriorResult` is captured from `_committedProgress.resultFor(stage.id)`.
- Reuses `MissionRewardFact` with no new reward state type.
- Uses `OrionDefenseGame.availableRunModules` only as a test observation.

- [ ] **Step 1: Add one helper for committed campaign modifiers**

Plan production helper:

```dart
CampaignModifiers _committedCampaignModifiers() =>
    CampaignModifiers.fromProgress(
      _committedProgress,
      OrionCampaign.stages,
      _committedTechTree,
    );
```

This avoids re-spelling the same derivation at launch and Replay.

- [ ] **Step 2: Write a normal-launch committed-eligibility test**

In `test/widget_test.dart`:

```dart
testWidgets('stage launch derives module eligibility from committed progress', (
  tester,
) async {
  final store = await storeWithResults({
    OrionCampaign.stageOneId: const StageResult(
      medal: StageMedal.clear,
      bestBaseHealth: 5,
    ),
  });
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
  await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

  expect(
    game!.availableRunModules,
    contains(RunModuleId.relayCalibration),
  );
});
```

- [ ] **Step 3: Write the critical first-clear → commit → same-game Replay regression**

Use the existing `_TestCampaignProgressStore(delaySaves: true)`, `publishVictory`, `_pumpUntil`, and `saveCompletions` seams.

Core flow:

```dart
final store = _TestCampaignProgressStore(delaySaves: true);
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
await startStageFromBriefing(tester);

final firstAttemptGame = game!;
expect(
  firstAttemptGame.availableRunModules,
  isNot(contains(RunModuleId.relayCalibration)),
);

await publishVictory(
  tester,
  firstAttemptGame,
  result: const StageResult(
    medal: StageMedal.silver,
    bestBaseHealth: 14,
  ),
);
await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

expect(find.text('Blueprint recovery pending'), findsOneWidget);
expect(
  firstAttemptGame.availableRunModules,
  isNot(contains(RunModuleId.relayCalibration)),
);

store.saveCompletions.single.complete();
await tester.pumpAndSettle();
expect(find.text('Blueprint recovered: Relay Calibration'), findsOneWidget);

await tester.tap(find.byTooltip('Replay Mission'));
await tester.pumpAndSettle();

expect(identical(game, firstAttemptGame), isTrue);
expect(
  firstAttemptGame.availableRunModules,
  contains(RunModuleId.relayCalibration),
);
expect(find.text('Start Wave'), findsOneWidget);
```

This is the primary lifecycle proof. Do not count Task 2's freeze guardrail as a substitute.

- [ ] **Step 4: Add the existing side-stage reward Replay regression**

Start from progress that unlocks but has not cleared Salvage Rift:

```dart
final store = _TestCampaignProgressStore(
  progress: _progressWithResults({
    'outpost-alpha',
    'nebula-relay',
  }),
  delaySaves: true,
);
OrionDefenseGame? game;
```

Launch Rift with:

```dart
await startStageFromBriefing(
  tester,
  mapLabel: 'Rift',
  actionLabel: 'Start Mission',
);
```

Before clear:

```dart
expect(game!.snapshot.gold, GameBalance.startingGold);
```

Publish victory, complete the controlled save, then tap `Replay Mission` and assert:

```dart
expect(
  game!.snapshot.gold,
  GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
);
```

This proves the new run-boundary rule fixes the pre-existing stale reward-on-replay behavior rather than refreshing only blueprints.

- [ ] **Step 5: Add reward-copy state tests**

Cover:

```text
fresh first clear + saving  → Blueprint recovery pending
fresh first clear + failed  → Blueprint not recovered
failed Retry Save + success → Blueprint recovered: Relay Calibration
already-cleared replay      → no recovery reward copy
```

For already-cleared Outpost Alpha:

```dart
expect(find.text('Blueprint recovery pending'), findsNothing);
expect(find.text('Blueprint not recovered'), findsNothing);
expect(
  find.text('Blueprint recovered: Relay Calibration'),
  findsNothing,
);
```

- [ ] **Step 6: Verify Task 3 tests are red**

```bash
flutter test test/widget_test.dart
```

Expected: the new availability, Replay refresh, side-reward refresh, and reward-copy assertions fail before production wiring.

- [ ] **Step 7: Use committed state on stage launch**

Import `run_module_unlocks.dart`.

In `_startStage(...)`, replace the current `_progress`-based run inputs with:

```dart
final campaignModifiers = _committedCampaignModifiers();
_missionPriorResult = _committedProgress.resultFor(stage.id);
_missionVictoryResult = null;
_missionStageId = stage.id;
_missionSaveState = null;

final game = OrionDefenseGame(
  stage: stage,
  campaignModifiers: campaignModifiers,
  availableRunModules:
      RunModuleUnlocks.availableFor(_committedProgress),
  onStageWon: _handleStageWon,
  onReturnToMap: _returnFromMissionReport,
);
```

`_progress` remains the visible campaign projection; committed state owns run/reward truth.

- [ ] **Step 8: Refresh both inputs on Mission Report Replay/Retry**

In `_restartFromMissionReport()` recapture the prior committed result:

```dart
_missionPriorResult =
    _committedProgress.resultFor(_missionStageId!);
_missionVictoryResult = null;
_missionSaveState = null;
```

Then restart the same game with both values from the same committed snapshot:

```dart
game.restart(
  campaignModifiers: _committedCampaignModifiers(),
  availableRunModules:
      RunModuleUnlocks.availableFor(_committedProgress),
);
```

Do not reconstruct `OrionDefenseGame`.

- [ ] **Step 9: Populate the existing Mission Report reward slot**

Add:

```dart
MissionRewardFact? _missionRewardFact() {
  if (_missionStageId != OrionCampaign.stageOneId ||
      _missionPriorResult != null) {
    return null;
  }

  return switch (_missionSaveState) {
    MissionSaveState.saving => const MissionRewardFact(
      title: 'Blueprint recovery pending',
      detail: 'Relay Calibration unlocks after this result is saved.',
    ),
    MissionSaveState.saved => const MissionRewardFact(
      title: 'Blueprint recovered: Relay Calibration',
      detail: 'Available in Salvage Module drafts on future runs.',
    ),
    MissionSaveState.failed => const MissionRewardFact(
      title: 'Blueprint not recovered',
      detail: 'Retry Save to keep this first-clear reward.',
    ),
    null => null,
  };
}
```

Replace the current victory `reward: null` with:

```dart
reward: _missionRewardFact(),
```

Because `_missionPriorResult` was captured from committed progress at attempt start, save success can advance `_committedProgress` without changing the first-clear fact for the completed attempt. Replay recaptures it and suppresses duplicate celebration.

- [ ] **Step 10: Run Task 3 tests**

```bash
flutter test test/widget_test.dart
```

Expected: PASS, including both the blueprint Replay wiring and Salvage Rift reward refresh.

- [ ] **Step 11: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: connect blueprint reward to committed replay state"
```

---

## Task 4: Add the compact Alpha map/briefing surfaces and reset proof

**Files:**
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Alpha map status derives from `progress.isCleared(OrionCampaign.stageOneId)`.
- Briefing uses the existing `StageResult? result` as the committed-clear signal.
- No `CampaignReward` or `stageRewardLabel` extension for the blueprint.
- Keep `nodeHeight = 124`.

- [ ] **Step 1: Write locked/recovered map tests**

Fresh progress:

```dart
expect(find.text('Blueprint • Locked'), findsOneWidget);
expect(find.text('Blueprint • Recovered'), findsNothing);
```

Committed Alpha clear:

```dart
expect(find.text('Blueprint • Recovered'), findsOneWidget);
expect(find.text('Blueprint • Locked'), findsNothing);
```

Assert exactly one blueprint status row exists across all seven nodes.

- [ ] **Step 2: Add the recovered briefing assertion**

With committed Alpha progress:

```dart
await tester.tap(find.text('Alpha'));
await tester.pumpAndSettle();
expect(
  find.text('Blueprint recovered: Relay Calibration'),
  findsOneWidget,
);
```

Fresh Alpha briefing does not show the recovered line.

- [ ] **Step 3: Add the 360×640 map regression**

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
```

Pump recovered Alpha and assert:

```dart
expect(find.text('Blueprint • Recovered'), findsOneWidget);
expect(tester.takeException(), isNull);
```

Do not change `nodeHeight` preemptively.

- [ ] **Step 4: Render the Alpha row with the existing four-row treatment**

In `_StageNode`, derive one optional blueprint label for Outpost Alpha and render it using the same spacing + `FittedBox(fit: BoxFit.scaleDown)` pattern used by `rewardLabel`.

Copy:

```text
Blueprint • Locked
```

or:

```text
Blueprint • Recovered
```

The existing Salvage Rift/Void Bastion nodes already render icon + label + status + reward in `nodeHeight = 124`; Alpha should match that structure.

If the compact test fails, compare the new row with the existing reward-row widget tree and correct the local row treatment. Do **not** bump the global node height as part of HPA-528.

- [ ] **Step 5: Add the briefing line**

In `_StageBriefingSheet`, when:

```dart
stage.id == OrionCampaign.stageOneId && result != null
```

render:

```text
Blueprint recovered: Relay Calibration
```

Do not repeat the full effect sentence here.

- [ ] **Step 6: Extend the reset regression**

After campaign reset succeeds:

```dart
expect(find.text('Blueprint • Locked'), findsOneWidget);
expect(find.text('Blueprint • Recovered'), findsNothing);
```

Start Alpha, capture the game, and assert:

```dart
expect(
  game!.availableRunModules,
  isNot(contains(RunModuleId.relayCalibration)),
);
```

- [ ] **Step 7: Run Task 4 tests**

```bash
flutter test test/widget_test.dart
```

Expected: PASS at normal size and 360×640 with `nodeHeight = 124` unchanged.

- [ ] **Step 8: Commit**

```bash
git add \
  lib/game/ui/world_map_view.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget_test.dart
git commit -m "feat: show first recovered blueprint"
```

---

## Task 5: Final verification and product proof

**Files:**
- No intended production changes; fix only defects exposed by these gates.

### Risks to watch

**Random visibility:** Relay Calibration is one card in a random eligible pool, so the next run may not offer it. The report/map/briefing are intentionally the cheap ownership proof. If the human check says the reward still feels invisible, improve copy/placement on those existing surfaces or stop blueprint expansion; do not bias `ModuleOfferPicker` in this ticket.

**Replay behavior change:** Replay now refreshes existing campaign modifiers as well as blueprint eligibility. This intentionally fixes stale side-stage rewards on same-game Replay. The automated Salvage Rift regression is the acceptance gate for that behavior.

- [ ] **Step 1: Run strict formatting**

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exit 0. If formatting is needed, run `dart format .`, inspect the diff, then rerun the strict command.

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Run focused blueprint/replay tests together**

```bash
flutter test \
  test/game/run_module_unlocks_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/module_offer_picker_test.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart \
  test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run the complete suite**

```bash
flutter test
```

Expected: all current tests pass. There is no hard catalog-size assertion left to surprise-fail when ordinary modules are added later.

- [ ] **Step 5: Perform one human first-clear → next-attempt proof**

Use a fresh campaign:

```text
Fresh save
→ start Outpost Alpha
→ clear the stage
→ while saving, observe "Blueprint recovery pending"
→ after save success, observe "Blueprint recovered: Relay Calibration"
→ tap Replay Mission
→ confirm the replay is a fresh build-phase attempt on the same game object
→ observe the recovered blueprint ownership on the existing report/map/briefing surfaces
→ when Relay Calibration appears in a draft, confirm its one-sentence effect is understandable
```

A particular random draft not containing Relay Calibration is **not** a picker defect. Do not reroute the picker to force it for this proof.

- [ ] **Step 6: Apply the product decision gate**

Record one of these outcomes in the implementation PR/Linear result:

```text
Proceed — reward ownership is clear and the new option feels worthwhile.
Narrow — gameplay is promising, but improve copy on the existing surfaces before expansion.
Stop — the blueprint loop does not add enough value; do not expand to more blueprints yet.
```

None of these outcomes authorizes pity/priority mechanics, a reward registry, or broader catalog work inside HPA-528.

- [ ] **Step 7: Commit any verification-only corrections**

Only if the gates exposed a real defect:

```bash
git add <the files actually corrected>
git commit -m "fix: address HPA-528 verification findings"
```

Do not create a cleanup commit when no source changes are needed.

## Acceptance Checklist

- [ ] Relay Calibration uses only existing range/fire-interval stat seams.
- [ ] Unlock ownership is derived from committed Outpost Alpha progress with no save field.
- [ ] Locked-module metadata has one source; no `initialRunModuleIds` duplicate list exists.
- [ ] Ordinary future catalog modules are base-eligible unless explicitly mapped to an unlock stage.
- [ ] Active attempts freeze run inputs.
- [ ] Replay refreshes campaign modifiers and module eligibility together from committed state.
- [ ] Salvage Rift's newly committed starting-gold reward applies on immediate Replay.
- [ ] First-clear pending/saved/failed copy matches committed ownership truth.
- [ ] Commit → Replay → same-game eligibility refresh is automated.
- [ ] Already-cleared replay does not duplicate the recovery message.
- [ ] Campaign reset removes the derived unlock.
- [ ] Alpha's four-row node fits the existing 124px map-node height at 360×640.
- [ ] Picker behavior remains generic/random and unaware of unlocks.
- [ ] Focused tests, full suite, and the human product check pass.
