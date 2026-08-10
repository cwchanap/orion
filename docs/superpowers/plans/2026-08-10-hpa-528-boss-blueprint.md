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
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`, and one human first-clear → next-run flow.

## File Map

### Create

- `lib/game/rules/run_module_unlocks.dart` — pure committed-progress → eligible-module rule for the one blueprint.
- `test/game/run_module_unlocks_test.dart` — ownership/availability/reset derivation coverage.

### Modify

- `lib/game/models/game_models.dart` — add `relayCalibration`, its definition/effect copy, and the explicit original-six ID list.
- `lib/game/rules/run_module_rules.dart` — no new branch expected; existing multipliers must support the new definition unchanged.
- `lib/game/rules/game_session.dart` — accept/store eligible IDs, filter candidates, and refresh eligibility only at restart boundaries.
- `lib/game/orion_defense_game.dart` — thread eligible IDs into session construction and restart.
- `lib/game/ui/orion_game_page.dart` — derive eligibility from `_committedProgress`, feed run boundaries, and project first-clear reward copy.
- `lib/game/ui/world_map_view.dart` — show one Outpost Alpha blueprint locked/recovered line.
- `test/game/run_module_rules_test.dart` — verify Relay Calibration uses existing stat seams.
- `test/game/game_session_test.dart` — verify locked/unlocked candidate pools and restart refresh.
- `test/game/orion_defense_game_test.dart` — retain restart/run-state regression coverage with the new optional eligibility input.
- `test/widget_test.dart` — Mission Report persistence states, campaign surfaces, replay/no-duplicate, and reset integration.

No intended changes to `CampaignProgress`, `CampaignSave`, `CampaignProgressStore`, save codecs, `MissionReportContent`, or `MissionReportPanel`.

---

### Task 1: Define Relay Calibration and derive one blueprint from campaign progress

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Create: `lib/game/rules/run_module_unlocks.dart`
- Create: `test/game/run_module_unlocks_test.dart`
- Modify: `test/game/run_module_rules_test.dart`

**Interfaces:**
- Produces `RunModuleId.relayCalibration`.
- Produces `const initialRunModuleIds` containing exactly the six HPA-527 modules.
- Produces `RunModuleUnlocks.firstBlueprintModuleId` and `RunModuleUnlocks.availableFor(CampaignProgress)`.
- Does not change `RunModuleRules.applyTowerStats(...)` signature.

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

  test('reset progress removes the derived blueprint', () {
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

- [ ] **Step 2: Run the unlock tests and verify red**

```bash
flutter test test/game/run_module_unlocks_test.dart
```

Expected: compile failure because `relayCalibration`, `initialRunModuleIds`, and `RunModuleUnlocks` do not exist.

- [ ] **Step 3: Add the seventh definition without widening the stat model**

In `lib/game/models/game_models.dart`, extend the enum and add an explicit base pool:

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

const initialRunModuleIds = <RunModuleId>[
  RunModuleId.heavyCaliber,
  RunModuleId.overclockRelay,
  RunModuleId.longSight,
  RunModuleId.emergencySalvage,
  RunModuleId.cryoReservoir,
  RunModuleId.rocketFusing,
];
```

Extend `effectText`:

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

Do not add any `TowerStats` fields or new affinity values.

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

- [ ] **Step 5: Add the failing/passing stat seam test**

In `test/game/run_module_rules_test.dart`, add:

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

No production change in `run_module_rules.dart` should be necessary because its existing generic multipliers already cover both fields.

- [ ] **Step 6: Run focused tests**

```bash
flutter test test/game/run_module_unlocks_test.dart test/game/run_module_rules_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add \
  lib/game/models/game_models.dart \
  lib/game/rules/run_module_unlocks.dart \
  test/game/run_module_unlocks_test.dart \
  test/game/run_module_rules_test.dart
git commit -m "feat: define first boss blueprint module"
```

---

### Task 2: Freeze eligible modules per attempt and refresh them on restart

**Files:**
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- `GameSession.initial({ ..., Iterable<RunModuleId> availableRunModules = initialRunModuleIds })`
- `GameSession.restart({Iterable<RunModuleId>? availableRunModules})`
- `OrionDefenseGame({ ..., Iterable<RunModuleId> availableRunModules = initialRunModuleIds })`
- `OrionDefenseGame.restart({Iterable<RunModuleId>? availableRunModules})`
- Eligibility may change only at construction/restart boundaries; it never changes during an active attempt.

- [ ] **Step 1: Add a recording offer picker to the session tests**

In `test/game/game_session_test.dart`, add a test helper next to the existing picker fakes:

```dart
final class _RecordingOfferPicker implements ModuleOfferPicker {
  List<RunModuleId> lastCandidates = const [];

  @override
  List<RunModuleId> pick(
    List<RunModuleId> candidates, {
    required int count,
  }) {
    lastCandidates = List<RunModuleId>.unmodifiable(candidates);
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

- [ ] **Step 2: Write failing eligibility tests**

Add these tests:

```dart
test('default session keeps Relay Calibration out of the draft pool', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(offerPicker: picker);

  clearTwoWaves(session);

  expect(picker.lastCandidates, hasLength(6));
  expect(picker.lastCandidates, isNot(contains(RunModuleId.relayCalibration)));
  expect(session.pendingRunModuleOffer!.moduleIds, hasLength(3));
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

  expect(picker.lastCandidates, contains(RunModuleId.relayCalibration));
  expect(session.pendingRunModuleOffer!.moduleIds.toSet(), hasLength(3));
});

test('restart can refresh availability for the next run', () {
  final picker = _RecordingOfferPicker();
  final session = GameSession.initial(offerPicker: picker);

  clearTwoWaves(session);
  expect(picker.lastCandidates, isNot(contains(RunModuleId.relayCalibration)));

  session.restart(
    availableRunModules: const [
      ...initialRunModuleIds,
      RunModuleId.relayCalibration,
    ],
  );
  clearTwoWaves(session);

  expect(picker.lastCandidates, contains(RunModuleId.relayCalibration));
  expect(session.acquiredRunModules, isEmpty);
});
```

- [ ] **Step 3: Run the session tests and verify red**

```bash
flutter test test/game/game_session_test.dart
```

Expected: compile failure because the availability inputs do not exist.

- [ ] **Step 4: Store and filter the eligible set in `GameSession`**

Add the factory parameter:

```dart
Iterable<RunModuleId> availableRunModules = initialRunModuleIds,
```

Pass it to the private constructor, then store:

```dart
Set<RunModuleId> _availableRunModules;
```

Initialize it as an immutable copy:

```dart
_availableRunModules = Set<RunModuleId>.unmodifiable(availableRunModules),
```

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

Keep the current offer picker and affinity fallback code otherwise unchanged.

- [ ] **Step 5: Thread the same boundary through `OrionDefenseGame`**

Constructor:

```dart
OrionDefenseGame({
  StageDefinition? stage,
  this.campaignModifiers = CampaignModifiers.empty,
  Iterable<RunModuleId> availableRunModules = initialRunModuleIds,
  ModuleOfferPicker? moduleOfferPicker,
  this.onStageWon,
  this.onReturnToMap,
}) : ...,
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

Do not add blueprint ownership logic to Flame.

- [ ] **Step 6: Preserve game restart regressions**

In `test/game/orion_defense_game_test.dart`, extend an existing restart test or add one that constructs the game with a deterministic `ModuleOfferPicker`, calls `restart(availableRunModules: ...)`, and verifies the ordinary restart invariants still hold: phase returns to build, acquired modules/pending offer are cleared, gold/base health reset, and pacing resets.

The candidate membership itself is already proven at the `GameSession` boundary; do not add a test-only public getter to `OrionDefenseGame`.

- [ ] **Step 7: Run focused tests**

```bash
flutter test test/game/game_session_test.dart test/game/orion_defense_game_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add \
  lib/game/rules/game_session.dart \
  lib/game/orion_defense_game.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart
git commit -m "feat: gate salvage modules by run availability"
```

---

### Task 3: Connect committed progress to run boundaries and Mission Report reward truth

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes `RunModuleUnlocks.availableFor(_committedProgress)`.
- Reuses the existing `_missionPriorResult`, `_missionStageId`, `_missionSaveState`, and `MissionRewardFact`.
- Adds one private `_missionBlueprintReward()` helper; no new public DTO or state field.

- [ ] **Step 1: Add first-clear reward-state widget tests**

Use the existing controllable campaign store in `test/widget_test.dart` and cover these observable states:

```text
fresh Outpost Alpha clear + pending store write
  → Blueprint recovery pending
  → Relay Calibration unlocks after this result is saved.

successful write
  → Blueprint recovered: Relay Calibration
  → Available in Salvage Module drafts on future runs.

failed write
  → Blueprint not recovered
  → Retry Save to keep this first-clear reward.

Retry Save succeeds
  → recovered copy replaces failed copy

already-cleared Outpost Alpha replay
  → no pending/recovered/not-recovered blueprint reward block
```

Also keep the existing HPA-525 save-state assertions so blueprint copy cannot replace or obscure `Saving result…`, `Saved.`, or `Save failed — progress unchanged.`.

- [ ] **Step 2: Verify the report tests fail before integration**

```bash
flutter test test/widget_test.dart --plain-name "blueprint"
```

Expected: the new blueprint assertions fail because the report still passes `reward: null`.

- [ ] **Step 3: Derive launch availability from committed progress**

Import `run_module_unlocks.dart` in `orion_game_page.dart`.

In `_startStage`, pass:

```dart
final game = OrionDefenseGame(
  stage: stage,
  campaignModifiers: campaignModifiers,
  availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
  onStageWon: _handleStageWon,
  onReturnToMap: _returnFromMissionReport,
);
```

Use `_committedProgress`, not `_progress`, for the availability input.

- [ ] **Step 4: Refresh the pool on every Mission Report restart boundary**

In `_restartFromMissionReport`, keep the current mission-state reset logic, but replace the bare restart call with:

```dart
game.restart(
  availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
);
```

This is required for the immediate first-clear → Replay Mission flow because HPA-525 reuses the same game object.

- [ ] **Step 5: Project the reward fact from existing mission state**

Add this private helper:

```dart
MissionRewardFact? _missionBlueprintReward() {
  if (_missionStageId != OrionCampaign.stageOneId ||
      _missionPriorResult != null) {
    return null;
  }

  final module = runModuleDefinition(
    RunModuleUnlocks.firstBlueprintModuleId,
  );

  return switch (_missionSaveState) {
    MissionSaveState.saving => MissionRewardFact(
      title: 'Blueprint recovery pending',
      detail: '${module.title} unlocks after this result is saved.',
    ),
    MissionSaveState.saved => MissionRewardFact(
      title: 'Blueprint recovered: ${module.title}',
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

Change the existing victory projection call from:

```dart
reward: null,
```

to:

```dart
reward: _missionBlueprintReward(),
```

Do not modify `MissionReportContent` or `MissionReportPanel`.

- [ ] **Step 6: Run Mission Report integration tests**

```bash
flutter test test/widget_test.dart --plain-name "blueprint"
flutter test test/game/mission_report_content_test.dart test/widget/mission_report_panel_test.dart
```

Expected: PASS, including existing report projection/panel behavior.

- [ ] **Step 7: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: surface first blueprint recovery"
```

---

### Task 4: Add the compact campaign surfaces and reset regression

**Files:**
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- World map derives the Outpost Alpha blueprint status from the `CampaignProgress` it already receives.
- `_StageBriefingSheet` derives the recovered line from its existing `stage` + `result` inputs.
- No new campaign-surface abstraction is introduced.

- [ ] **Step 1: Write campaign-surface tests**

Add widget coverage for:

```text
fresh progress:
  Outpost Alpha node shows "Blueprint • Locked"

committed Outpost Alpha result:
  Outpost Alpha node shows "Blueprint • Recovered"
  opening Outpost Alpha briefing shows "Blueprint recovered: Relay Calibration"

campaign reset after a recovered blueprint:
  Outpost Alpha returns to "Blueprint • Locked"
  recovered briefing copy disappears
```

Use the existing 360×640 test surface for at least the recovered map/briefing case and assert no overflow exceptions.

- [ ] **Step 2: Verify red**

```bash
flutter test test/widget_test.dart --plain-name "Blueprint •"
```

Expected: the new map/briefing copy is absent.

- [ ] **Step 3: Add the one-stage world-map status**

In `_StageNode.build`, derive an optional blueprint label only for Outpost Alpha:

```dart
final blueprintLabel = stage.id == OrionCampaign.stageOneId
    ? status == StageProgressStatus.cleared
          ? 'Blueprint • Recovered'
          : 'Blueprint • Locked'
    : null;
```

Render it with the same compact `FittedBox` pattern already used for stage reward labels:

```dart
if (blueprintLabel != null) ...[
  const SizedBox(height: 2),
  FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      blueprintLabel,
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.foreground,
      ),
    ),
  ),
],
```

Import `orion_campaign.dart`. Do not add blueprint labels to other stages.

- [ ] **Step 4: Add the recovered briefing line**

Inside `_StageBriefingSheet`, compute:

```dart
final hasRecoveredBlueprint =
    stage.id == OrionCampaign.stageOneId && result != null;
```

When true, render exactly:

```dart
Text(
  'Blueprint recovered: ${runModuleDefinition(RunModuleUnlocks.firstBlueprintModuleId).title}',
),
```

Do not render the effect sentence here; the draft card remains the detailed explanation surface.

- [ ] **Step 5: Run campaign-surface and reset tests**

```bash
flutter test test/widget_test.dart --plain-name "blueprint"
```

Expected: PASS, with no layout exceptions at 360×640.

- [ ] **Step 6: Run the full focused HPA-528 set**

```bash
flutter test \
  test/game/run_module_unlocks_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart \
  test/game/mission_report_content_test.dart \
  test/widget/mission_report_panel_test.dart \
  test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add \
  lib/game/ui/world_map_view.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget_test.dart
git commit -m "feat: show blueprint status on campaign surfaces"
```

---

### Task 5: Final verification and one human reward-loop check

**Files:**
- No planned production files beyond Tasks 1–4.
- Update implementation only if verification exposes a concrete defect in HPA-528 behavior.

**Interfaces:**
- Validates the complete first-clear → committed reward → next-run option loop.

- [ ] **Step 1: Format check**

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exit 0, no files changed.

- [ ] **Step 2: Static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Human mobile flow**

On a fresh campaign at the normal 1× speed:

```text
1. Confirm Outpost Alpha shows Blueprint • Locked.
2. Start Outpost Alpha and confirm ordinary drafts use only the original six modules.
3. Clear the Relay Breaker.
4. While the result is saving, confirm Blueprint recovery pending.
5. After save success, confirm Blueprint recovered: Relay Calibration.
6. Tap Replay Mission.
7. Reach the next Salvage Module draft and confirm Relay Calibration can appear,
   reads "All towers gain 8% range; attack interval drops 8%.", and is easy to understand.
8. Return to the map and confirm Blueprint • Recovered / briefing copy.
9. Reset the campaign and confirm the blueprint returns to Locked.
```

This is one product proof, not a balance matrix. If Relay Calibration feels unnoticeable, adjust only its two tuning constants before expanding architecture.

- [ ] **Step 5: Commit verification-only fixes if any**

If no fixes were required, do not create an empty commit. If a concrete HPA-528 defect was fixed during verification, stage only that fix and its regression test, then commit with a specific message describing the defect.
