# HPA-528 Boss Blueprint Reward Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove Orion's permanent reward loop by making one Relay Breaker blueprint unlock Relay Calibration after the first committed Outpost Alpha clear, then make that seventh Salvage Module eligible on the next run.

**Architecture:** Keep campaign ownership derived from committed `CampaignProgress` and keep module effects in the existing run-module stat pipeline. A focused `RunModuleUnlocks` rule converts progress into eligible module IDs; `GameSession` receives that eligibility at run boundaries, while HPA-525's existing Mission Report reward slot and save writer provide pending/saved/failed truth without new persistence state.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- Exactly one blueprint ships: Outpost Alpha / Relay Breaker → `Relay Calibration`.
- `Relay Calibration` effect is exactly: +8% range and -8% attack interval for all towers.
- Use existing `rangeMultiplier` and `fireIntervalMultiplier`; do not add a new combat stat or event path.
- The original six modules remain the default pool until Outpost Alpha is present in **committed** campaign progress.
- The completed first-clear attempt never receives the blueprint retroactively.
- A Replay/Retry restart is a new run boundary and refreshes eligible module IDs from committed progress.
- Ownership is derived from `CampaignProgress.isCleared(OrionCampaign.stageOneId)`; do not add blueprint ownership to `CampaignSave`.
- Do not change the save schema or codec for this feature.
- Reuse HPA-525's `_persistSave`, `_committedProgress`, `MissionSaveState`, and `MissionRewardFact`; do not add a second writer or reward state machine.
- First-clear report copy is `pending` while saving, `recovered` after commit, and `not recovered` after failure.
- A replay of an already-cleared Outpost Alpha never repeats blueprint recovery copy.
- World map presentation is limited to one compact locked/recovered line on Outpost Alpha.
- Stage briefing presentation is limited to one recovered line after ownership exists.
- Full effect copy remains on the Salvage Module draft card.
- Campaign reset removes the derived unlock naturally through empty progress.
- Preserve the existing three-distinct-card picker, affinity preference, acquired-module exclusion, and ordinary production randomness.
- Do not add a blueprint registry, generalized unlock graph, Codex Modules section, telemetry, deterministic seed protocol, sound/haptics, or broader catalog tuning.
- Target the existing 360×640 logical-pixel mobile baseline.
- The automated suite must explicitly prove the page → game Replay wiring after a committed first clear; a human check alone is not sufficient for that lifecycle invariant.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`, and one human first-clear → next-run flow.

## File Map

### Create

- `lib/game/rules/run_module_unlocks.dart` — pure committed-progress → eligible-module rule for the one blueprint.
- `test/game/run_module_unlocks_test.dart` — ownership/availability/reset derivation coverage.

### Modify

- `lib/game/models/game_models.dart` — add `relayCalibration`, its definition/effect copy, and the explicit original-six ID list.
- `lib/game/rules/game_session.dart` — accept/store eligible IDs, filter candidates, expose testable availability, and refresh eligibility only at restart boundaries.
- `lib/game/orion_defense_game.dart` — thread eligible IDs into session construction/restart and expose the current eligible IDs under `@visibleForTesting`.
- `lib/game/ui/orion_game_page.dart` — derive eligibility from `_committedProgress`, feed new/restarted runs, and project first-clear reward copy.
- `lib/game/ui/world_map_view.dart` — show one Outpost Alpha blueprint locked/recovered line; adjust node height in this task if compact-layout verification needs it.
- `test/game/run_module_rules_test.dart` — verify Relay Calibration uses existing stat seams.
- `test/game/module_offer_picker_test.dart` — migrate the hard catalog-size guard from six to seven and verify catalog/base-pool separation.
- `test/game/game_session_test.dart` — verify locked/unlocked candidate pools, attempt freeze, and restart refresh.
- `test/game/orion_defense_game_test.dart` — retain restart/run-state regression coverage with the new optional eligibility input.
- `test/widget_test.dart` — Mission Report persistence states, the committed first-clear → Replay wiring assertion, campaign surfaces, no-duplicate reward, and reset integration.

No intended changes to `CampaignProgress`, `CampaignSave`, `CampaignProgressStore`, save codecs, `MissionReportContent`, or `MissionReportPanel`.

---

## Task 1: Define Relay Calibration and derive one blueprint from campaign progress

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Create: `lib/game/rules/run_module_unlocks.dart`
- Create: `test/game/run_module_unlocks_test.dart`
- Modify: `test/game/run_module_rules_test.dart`
- Modify: `test/game/module_offer_picker_test.dart`

**Interfaces:**
- Produces `RunModuleId.relayCalibration`.
- Produces `const initialRunModuleIds` containing exactly the six HPA-527 modules.
- Produces `RunModuleUnlocks.firstBlueprintModuleId`, `RunModuleUnlocks.hasFirstBlueprint(...)`, and `RunModuleUnlocks.availableFor(...)`.
- Keeps `runModuleCatalog` as the single definition catalog with seven entries.
- Does not change `RunModuleRules.applyTowerStats(...)` or `ModuleOfferPicker` signatures.

- [ ] **Step 1: Write failing unlock derivation tests**

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
  test('fresh progress exposes exactly the original six modules', () {
    expect(
      RunModuleUnlocks.availableFor(CampaignProgress()),
      unorderedEquals(initialRunModuleIds),
    );
    expect(initialRunModuleIds, hasLength(6));
    expect(initialRunModuleIds, isNot(contains(RunModuleId.relayCalibration)));
  });

  test('committed Outpost Alpha clear adds Relay Calibration', () {
    final progress = CampaignProgress().recordResult(
      OrionCampaign.stageOneId,
      clearedResult,
    );

    final available = RunModuleUnlocks.availableFor(progress);

    expect(available, hasLength(7));
    expect(available, containsAll(initialRunModuleIds));
    expect(available, contains(RunModuleId.relayCalibration));
  });

  test('unrelated clear does not unlock the blueprint', () {
    final progress = CampaignProgress().recordResult(
      'nebula-relay',
      clearedResult,
    );

    expect(
      RunModuleUnlocks.availableFor(progress),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });

  test('empty progress removes the derived blueprint after reset', () {
    final cleared = CampaignProgress().recordResult(
      OrionCampaign.stageOneId,
      clearedResult,
    );
    expect(
      RunModuleUnlocks.availableFor(cleared),
      contains(RunModuleId.relayCalibration),
    );

    expect(
      RunModuleUnlocks.availableFor(CampaignProgress()),
      isNot(contains(RunModuleId.relayCalibration)),
    );
  });
}
```

- [ ] **Step 2: Run the unlock test and verify red**

```bash
flutter test test/game/run_module_unlocks_test.dart
```

Expected: compile failure because `relayCalibration`, `initialRunModuleIds`, and `RunModuleUnlocks` do not exist.

- [ ] **Step 3: Add the seventh definition without widening the stat model**

In `lib/game/models/game_models.dart`, extend the ID enum:

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

Add the explicit base-pool constant next to the run-module model:

```dart
const initialRunModuleIds = <RunModuleId>[
  RunModuleId.heavyCaliber,
  RunModuleId.overclockRelay,
  RunModuleId.longSight,
  RunModuleId.emergencySalvage,
  RunModuleId.cryoReservoir,
  RunModuleId.rocketFusing,
];
```

Extend `RunModuleDefinition.effectText`:

```dart
RunModuleId.relayCalibration =>
  'All towers gain ${percent(rangeMultiplier - 1)} range; '
      'attack interval drops ${percent(1 - fireIntervalMultiplier)}.',
```

Append the catalog definition:

```dart
RunModuleDefinition(
  id: RunModuleId.relayCalibration,
  title: 'Relay Calibration',
  affinity: RunModuleAffinity.universal,
  rangeMultiplier: 1.08,
  fireIntervalMultiplier: 0.92,
),
```

Do not add a `TowerStats` field, affinity value, or combat branch.

- [ ] **Step 4: Implement the focused unlock rule**

Create `lib/game/rules/run_module_unlocks.dart`:

```dart
import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../models/game_models.dart';

abstract final class RunModuleUnlocks {
  static const RunModuleId firstBlueprintModuleId =
      RunModuleId.relayCalibration;

  static bool hasFirstBlueprint(CampaignProgress progress) =>
      progress.isCleared(OrionCampaign.stageOneId);

  static Set<RunModuleId> availableFor(CampaignProgress progress) =>
      Set<RunModuleId>.unmodifiable({
        ...initialRunModuleIds,
        if (hasFirstBlueprint(progress)) firstBlueprintModuleId,
      });
}
```

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

No production change in `run_module_rules.dart` should be required: its existing generic multiplier application is the intended implementation.

- [ ] **Step 6: Migrate the existing hard catalog-length guard before running focused tests**

`test/game/module_offer_picker_test.dart` currently asserts six catalog entries. Replace that assertion with an explicit seven-definition/base-pool separation test:

```dart
test('catalog exposes seven definitions while the base pool remains six', () {
  final catalogIds = runModuleCatalog
      .map((definition) => definition.id)
      .toSet();

  expect(runModuleCatalog, hasLength(7));
  expect(catalogIds, hasLength(7));
  expect(catalogIds, equals(RunModuleId.values.toSet()));
  expect(initialRunModuleIds, hasLength(6));
  expect(catalogIds, containsAll(initialRunModuleIds));
  expect(catalogIds.difference(initialRunModuleIds.toSet()), {
    RunModuleId.relayCalibration,
  });

  final relay = runModuleDefinition(RunModuleId.relayCalibration);
  expect(relay.rangeMultiplier, 1.08);
  expect(relay.fireIntervalMultiplier, 0.92);
});
```

Keep the existing picker behavior tests. Do not teach `RandomModuleOfferPicker` about locked/unlocked modules; it still receives an already-filtered candidate list.

- [ ] **Step 7: Run all Task 1 focused tests**

```bash
flutter test \
  test/game/run_module_unlocks_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/module_offer_picker_test.dart
```

Expected: PASS. This task must not leave the known catalog-length failure for the final suite.

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

## Task 2: Freeze eligible modules per attempt and refresh them on restart

**Files:**
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- `GameSession.initial({ ..., Iterable<RunModuleId> availableRunModules = initialRunModuleIds })`
- `GameSession.restart({Iterable<RunModuleId>? availableRunModules})`
- `Set<RunModuleId> get GameSession.availableRunModules`
- `OrionDefenseGame({ ..., Iterable<RunModuleId> availableRunModules = initialRunModuleIds })`
- `OrionDefenseGame.restart({Iterable<RunModuleId>? availableRunModules})`
- `@visibleForTesting Set<RunModuleId> get OrionDefenseGame.availableRunModules`
- Eligibility may change only at construction/restart boundaries; it never changes during an active attempt.

- [ ] **Step 1: Add a recording offer picker to session tests**

In `test/game/game_session_test.dart`, add a helper that records every candidate set it receives:

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

- [ ] **Step 2: Write the locked/unlocked candidate tests**

```dart
test('default session keeps Relay Calibration out of the draft pool', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(offerPicker: picker);

  clearTwoWaves(session);

  expect(picker.candidateHistory.single, hasLength(6));
  expect(
    picker.candidateHistory.single,
    isNot(contains(RunModuleId.relayCalibration)),
  );
  expect(session.pendingRunModuleOffer!.moduleIds.toSet(), hasLength(3));
});

test('unlocked session includes Relay Calibration as a valid candidate', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(
    offerPicker: picker,
    availableRunModules: const [
      ...initialRunModuleIds,
      RunModuleId.relayCalibration,
    ],
  );

  clearTwoWaves(session);

  expect(
    picker.candidateHistory.single,
    contains(RunModuleId.relayCalibration),
  );
  expect(session.pendingRunModuleOffer!.moduleIds.toSet(), hasLength(3));
});
```

- [ ] **Step 3: Add an explicit attempt-freeze regression**

The seventh definition exists globally after Task 1, so verify a six-ID attempt remains six-ID across multiple draft boundaries until restart:

```dart
test('eligible module set stays frozen for the active attempt', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(
    offerPicker: picker,
    availableRunModules: initialRunModuleIds,
  );

  clearTwoWaves(session);
  final firstOffer = session.pendingRunModuleOffer!;
  expect(
    session.selectRunModule(
      offerId: firstOffer.offerId,
      moduleId: firstOffer.moduleIds.first,
    ),
    isTrue,
  );

  expect(session.startWave(), isTrue);
  session.finishActiveWave();
  expect(session.startWave(), isTrue);
  session.finishActiveWave();

  expect(picker.candidateHistory, hasLength(2));
  for (final candidates in picker.candidateHistory) {
    expect(candidates, isNot(contains(RunModuleId.relayCalibration)));
  }
  expect(
    session.availableRunModules,
    unorderedEquals(initialRunModuleIds),
  );
});
```

This test documents the product promise that adding/owning a catalog entry elsewhere cannot mutate the current attempt; only `restart(...)` changes the stored eligibility.

- [ ] **Step 4: Add the restart-refresh regression**

```dart
test('restart refreshes availability for the next run', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(offerPicker: picker);

  clearTwoWaves(session);
  expect(
    picker.candidateHistory.last,
    isNot(contains(RunModuleId.relayCalibration)),
  );

  session.restart(
    availableRunModules: const [
      ...initialRunModuleIds,
      RunModuleId.relayCalibration,
    ],
  );

  expect(session.acquiredRunModules, isEmpty);
  expect(session.pendingRunModuleOffer, isNull);
  expect(
    session.availableRunModules,
    contains(RunModuleId.relayCalibration),
  );

  clearTwoWaves(session);
  expect(
    picker.candidateHistory.last,
    contains(RunModuleId.relayCalibration),
  );
});
```

- [ ] **Step 5: Run the session tests and verify red**

```bash
flutter test test/game/game_session_test.dart
```

Expected: compile failure because the availability inputs/getter do not exist.

- [ ] **Step 6: Store and filter the eligible set in `GameSession`**

Add the factory parameter:

```dart
Iterable<RunModuleId> availableRunModules = initialRunModuleIds,
```

Store an immutable copy:

```dart
Set<RunModuleId> _availableRunModules;

Set<RunModuleId> get availableRunModules =>
    Set<RunModuleId>.unmodifiable(_availableRunModules);
```

Initialize `_availableRunModules` from the factory/private constructor input.

Filter `_moduleCandidates()` before the existing affinity preference logic:

```dart
final remaining = runModuleCatalog
    .where(
      (definition) =>
          _availableRunModules.contains(definition.id) &&
          !acquired.contains(definition.id),
    )
    .toList(growable: false);
```

Change restart to refresh only when the caller supplies a new run-boundary value:

```dart
void restart({Iterable<RunModuleId>? availableRunModules}) {
  if (availableRunModules != null) {
    _availableRunModules =
        Set<RunModuleId>.unmodifiable(availableRunModules);
  }

  _towersByPosition.clear();
  _nextTowerId = 1;
  _gold = startingGold;
  _baseHealth = startingBaseHealth;
  _waveIndex = 0;
  _phase = GamePhase.build;
  _acquiredRunModules.clear();
  _pendingRunModuleOffer = null;
}
```

Do not otherwise change candidate preference/fallback or picker behavior.

- [ ] **Step 7: Thread the same boundary through `OrionDefenseGame`**

Constructor:

```dart
OrionDefenseGame({
  StageDefinition? stage,
  this.campaignModifiers = CampaignModifiers.empty,
  Iterable<RunModuleId> availableRunModules = initialRunModuleIds,
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
```

Restart:

```dart
void restart({Iterable<RunModuleId>? availableRunModules}) {
  _clearCombatComponents(removeTowers: true);
  _resetWaveSpawnState();
  _nextEnemyId = 1;
  _clearSelection();
  _session.restart(availableRunModules: availableRunModules);
  _resetPacing();
  _layoutBoardIfReady();
  _publishSnapshot();
}
```

Expose only the narrow test observation needed by Task 3:

```dart
@visibleForTesting
Set<RunModuleId> get availableRunModules => _session.availableRunModules;
```

`orion_defense_game.dart` already imports `package:flutter/foundation.dart`, so do not add another testing package or controller.

- [ ] **Step 8: Add/adjust game-level restart coverage**

In `test/game/orion_defense_game_test.dart`, construct a game with the base six, call:

```dart
game.restart(
  availableRunModules: const [
    ...initialRunModuleIds,
    RunModuleId.relayCalibration,
  ],
);
```

Then assert:

```dart
expect(game.availableRunModules, contains(RunModuleId.relayCalibration));
expect(game.snapshot.acquiredRunModules, isEmpty);
expect(game.snapshot.pendingRunModuleOffer, isNull);
expect(game.snapshot.phase, GamePhase.build);
```

Keep existing restart pacing/component cleanup assertions intact.

- [ ] **Step 9: Run focused Task 2 tests**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add \
  lib/game/rules/game_session.dart \
  lib/game/orion_defense_game.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart
git commit -m "feat: gate run modules by campaign eligibility"
```

---

## Task 3: Wire committed progress through launch, Replay, and Mission Report reward copy

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes `RunModuleUnlocks.availableFor(_committedProgress)` for both normal stage launch and Mission Report restart.
- Reuses the existing `MissionRewardFact` parameter on `projectVictoryReport(...)`.
- Uses `OrionDefenseGame.availableRunModules` only as an `@visibleForTesting` observation to prove page → game Replay wiring.
- Does not change `_persistSave(...)`, `CampaignSave`, or Mission Report DTO/widget APIs.

- [ ] **Step 1: Write a failing launch-availability widget test**

Add `run_module_unlocks.dart` to `test/widget_test.dart` imports. Use the existing `storeWithResults(...)`, `startStageFromBriefing(...)`, and `onGameCreated` seam:

```dart
testWidgets('stage launch derives run modules from committed progress', (
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

This proves `_startStage` uses committed progress rather than the fixed base list.

- [ ] **Step 2: Write the critical committed first-clear → Replay wiring regression**

Extend the existing Mission Report save/replay integration pattern in `test/widget_test.dart` (it already captures `OrionDefenseGame`, waits for a controlled save completion, taps the `Replay Mission` tooltip, and verifies the report closes).

For a fresh store:

1. start Outpost Alpha;
2. assert `game.availableRunModules` does **not** contain Relay Calibration;
3. publish a first-clear victory with the existing `publishVictory(...)` helper;
4. while the controlled save is unresolved, assert the report says `Blueprint recovery pending` and the game still has six eligible IDs;
5. complete the store save and pump;
6. assert `Blueprint recovered: Relay Calibration`;
7. tap the Mission Report `Replay Mission` action;
8. assert the **same game object** now reports Relay Calibration as eligible.

Core assertions:

```dart
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

expect(find.text('Blueprint recovery pending'), findsOneWidget);
expect(
  firstAttemptGame.availableRunModules,
  isNot(contains(RunModuleId.relayCalibration)),
);

await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
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

Use the existing controlled/failing campaign-store test helper already used by Mission Report persistence tests rather than adding another persistence fake.

This is the required automated proof for the riskiest lifecycle. Do not defer it to Task 5's human check.

- [ ] **Step 3: Write reward-state tests before production wiring**

Add focused widget assertions for the existing first-clear save states:

```text
fresh first clear + saving  → Blueprint recovery pending
fresh first clear + failed  → Blueprint not recovered
failed Retry Save + success → Blueprint recovered: Relay Calibration
already-cleared replay      → no blueprint recovery reward section
```

For the replay/no-duplicate case, start from `storeWithResults({OrionCampaign.stageOneId: ...})`, publish an improved or retained result, and assert:

```dart
expect(find.textContaining('Blueprint recover'), findsNothing);
expect(find.text('Blueprint recovery pending'), findsNothing);
expect(find.text('Blueprint not recovered'), findsNothing);
```

- [ ] **Step 4: Verify Task 3 tests are red**

```bash
flutter test test/widget_test.dart
```

Expected: the new launch/replay availability and reward-copy assertions fail because `OrionGamePage` still constructs/restarts with the default six and passes `reward: null`.

- [ ] **Step 5: Derive availability from committed progress on normal launch**

Import `run_module_unlocks.dart` in `orion_game_page.dart` and change `_startStage(...)`:

```dart
final game = OrionDefenseGame(
  stage: stage,
  campaignModifiers: campaignModifiers,
  availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
  onStageWon: _handleStageWon,
  onReturnToMap: _returnFromMissionReport,
);
```

Keep `_progress` for visible result/briefing state, but use `_committedProgress` for ownership-derived availability.

- [ ] **Step 6: Refresh availability on Mission Report Replay**

Replace the current bare call:

```dart
game.restart();
```

with:

```dart
game.restart(
  availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
);
```

Do not create a new game object. HPA-525 intentionally reuses the same game/session; the restart parameter is the run-boundary refresh.

- [ ] **Step 7: Add one private reward projector**

In `_OrionGamePageState`, add:

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

Then replace the current `reward: null` in the victory report with:

```dart
reward: _missionRewardFact(),
```

Do not add a reward enum/registry. `_missionPriorResult == null` is the already-captured first-clear fact; after Replay, `_restartFromMissionReport` refreshes `_missionPriorResult` from saved progress, preventing duplicate recovery copy.

- [ ] **Step 8: Run Task 3 tests**

```bash
flutter test test/widget_test.dart
```

Expected: PASS, including the explicit save commit → Replay → same-game eligible-ID assertion.

- [ ] **Step 9: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: connect blueprint reward to mission saves"
```

---

## Task 4: Add the compact Outpost Alpha campaign surfaces and reset regression

**Files:**
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- World map derives blueprint status directly from `progress.isCleared(OrionCampaign.stageOneId)`.
- Stage briefing receives the same existing `StageResult? result`; no new reward model is required.
- No use of `stageRewardLabel` or `CampaignReward` for this main-stage blueprint.

- [ ] **Step 1: Add map/briefing widget assertions**

For fresh progress:

```dart
expect(find.text('Blueprint • Locked'), findsOneWidget);
```

For `storeWithResults({OrionCampaign.stageOneId: ...})`:

```dart
expect(find.text('Blueprint • Recovered'), findsOneWidget);
await tester.tap(find.text('Alpha'));
await tester.pumpAndSettle();
expect(find.text('Blueprint recovered: Relay Calibration'), findsOneWidget);
```

Also assert no other stage node gets a blueprint line. Use the existing seven-stage map fixture and expect exactly one blueprint status string across the map.

- [ ] **Step 2: Add a compact-layout regression before changing layout constants**

At 360×640:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
```

Pump the world map with Outpost Alpha recovered and assert:

```dart
expect(find.text('Blueprint • Recovered'), findsOneWidget);
expect(tester.takeException(), isNull);
```

This test must run in Task 4, not only in the final human pass.

- [ ] **Step 3: Render one blueprint line on the Alpha node**

In `_StageNode`, derive only the Outpost Alpha copy. Either pass a small optional `blueprintLabel` from `_StageMap` or derive it from `stage.id` + `status`; do not introduce a generalized reward surface.

The displayed text is exactly:

```text
Blueprint • Locked
```

before clear and:

```text
Blueprint • Recovered
```

after clear.

Reuse the existing `FittedBox`/small-label treatment used by `rewardLabel` so the narrow node remains readable.

- [ ] **Step 4: Treat node-height adjustment as in-scope if the 360×640 test overflows**

The current map uses:

```dart
const nodeHeight = 124.0;
```

Adding a fourth text row may make that too tight. First run the compact test after adding the line. If `tester.takeException()` reports a `RenderFlex` overflow, change the constant in this same task to:

```dart
const nodeHeight = 132.0;
```

and rerun the compact map tests. Because `_StageMap` already computes `availableHeight` from `nodeHeight`, no coordinate-system redesign is needed.

If 132 still overflows, keep 132 and reduce only the node's vertical gaps/padding by the smallest amount needed; do not add scrolling, variable-height nodes, or a new layout system.

This contingency is explicitly in scope and must not be deferred as a separate UI issue.

- [ ] **Step 5: Add the recovered briefing line**

In `_StageBriefingSheet`, when:

```dart
stage.id == OrionCampaign.stageOneId && result != null
```

render:

```text
Blueprint recovered: Relay Calibration
```

Do not render the full effect sentence here. The draft card remains the detailed description surface.

- [ ] **Step 6: Extend the existing campaign-reset integration test**

After reset succeeds, assert:

```dart
expect(find.text('Blueprint • Locked'), findsOneWidget);
expect(find.text('Blueprint • Recovered'), findsNothing);
```

Start Outpost Alpha after reset, capture the game, and assert:

```dart
expect(
  game!.availableRunModules,
  isNot(contains(RunModuleId.relayCalibration)),
);
```

This proves reset removes both presentation and actual eligibility through the same empty `CampaignProgress`, with no ownership cleanup path.

- [ ] **Step 7: Run Task 4 focused tests**

```bash
flutter test test/widget_test.dart
```

Expected: PASS at the normal fixture size and 360×640 without overflow.

- [ ] **Step 8: Commit**

```bash
git add \
  lib/game/ui/world_map_view.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget_test.dart
git commit -m "feat: show first recovered blueprint"
```

---

## Task 5: Run final verification and the one product proof

**Files:**
- No intended production changes; fix only defects exposed by these gates.

- [ ] **Step 1: Run formatting**

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exit 0 with no formatting changes required.

If it reports files needing format, run `dart format .`, inspect the diff, then rerun the strict command.

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Re-run the focused blueprint tests together**

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

Expected: all current tests pass. There should be no surprise catalog-length failure because `module_offer_picker_test.dart` was migrated in Task 1.

- [ ] **Step 5: Perform one human first-clear → next-run proof**

Use a fresh campaign and perform:

```text
Fresh save
→ start Outpost Alpha
→ confirm the first run uses only the original six-module pool
→ clear the stage
→ while saving, observe "Blueprint recovery pending"
→ after save success, observe "Blueprint recovered: Relay Calibration"
→ tap Replay Mission
→ reach the first Salvage Module draft
→ confirm Relay Calibration is eligible/can appear and its card copy is understandable
→ return to the map and confirm Alpha shows "Blueprint • Recovered"
```

The automated Task 3 regression already proves the Replay wiring. This human pass answers only the product question: is the reward noticeable and understandable?

- [ ] **Step 6: Commit any verification-only correction if required**

If the gates expose a real defect, make the smallest scoped correction, rerun the failing focused test plus the full relevant gate, and commit only that correction. If no correction is required, do not create an empty verification commit.

---

## Acceptance Checklist

Before marking HPA-528 implementation complete, verify all of the following:

- [ ] Fresh campaign availability is exactly `initialRunModuleIds` (six IDs).
- [ ] `runModuleCatalog` contains exactly seven unique definitions and the only catalog entry outside the base pool is `relayCalibration`.
- [ ] A committed Outpost Alpha clear derives Relay Calibration without a save-schema field.
- [ ] Relay Calibration changes only range (+8%) and fire interval (-8%) through existing run-module rules.
- [ ] Candidate generation filters by the per-attempt eligible set before existing affinity preference/fallback.
- [ ] Eligibility is frozen across an attempt and changes only at construction/restart.
- [ ] The completed first-clear attempt remains on six eligible IDs while its save is pending.
- [ ] Save failure leaves the blueprint unavailable and shows `Blueprint not recovered`.
- [ ] Retry Save success changes the report to recovered and makes the next run eligible.
- [ ] Automated widget coverage proves `_restartFromMissionReport` refreshes the **same** `OrionDefenseGame` from `_committedProgress` after save success.
- [ ] Replay of an already-cleared stage does not repeat blueprint recovery copy.
- [ ] Outpost Alpha alone shows the compact locked/recovered campaign line.
- [ ] Recovered Outpost Alpha briefing shows one short blueprint line.
- [ ] 360×640 map/report surfaces have no overflow; the node-height contingency is resolved in Task 4 if needed.
- [ ] Campaign reset removes both the recovered UI and actual module availability.
- [ ] No blueprint registry, ownership collection, save migration, new combat stat, Codex section, or event bus was added.
- [ ] `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and full `flutter test` pass.
- [ ] One human first-clear → next-run product flow confirms the reward is noticeable and understandable.
