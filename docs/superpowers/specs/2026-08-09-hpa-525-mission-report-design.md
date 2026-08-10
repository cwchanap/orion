# HPA-525 Mission Report Design

## Context

HPA-527 has shipped the minimum Salvage Module vertical slice, so HPA-525 is Orion's next actionable reward-loop task. It is unblocked by HPA-527 and directly blocks HPA-528, the one-blueprint reward proof.

The current end-of-run path has two mismatched responsibilities:

- `OrionDefenseGame` publishes a terminal `GameSnapshot` and calls `onStageWon` after a victory.
- `OrionGamePage` persists the stage result through the generic optimistic `_persistSave` path.
- `_EndStatePanel` derives its own victory/loss copy directly from `GameSnapshot` and exposes `game.restart` / `game.returnToMap` immediately.
- `_BottomControls` also exposes `game.returnToMap` for every non-wave phase, including terminal `won` / `lost` states.

The report therefore cannot distinguish saving, saved, and failed progress, and the callback graph can still leave the mission while a result write is unresolved.

HPA-100 also established a repository-wide persistence invariant that remains relevant here: campaign writes share `_saveQueue`, use `_progressGeneration` to reject stale work, and compose payloads from committed state. HPA-525 must remove optimistic stage-result semantics without creating a second independent `store.save` writer.

## Goal

Replace the minimal end panel with a compact Mission Report that answers four questions in a few seconds:

1. Did I win or lose?
2. Did this run improve the committed stage result?
3. Which Salvage Modules defined the run?
4. What can I do next?

For an improving victory, the report appears in `Saving…`, becomes `Saved` only after the queued write succeeds, and becomes `Save failed` without optimistic campaign mutation if the write fails.

## Review resolution

The design review found several valid gaps. This revision makes these explicit changes:

1. **Keep one campaign writer.** Mission saves do not call `_persistSave`, because its optimistic mutation/rollback contract is wrong for the report, but they do enqueue on the existing `_saveQueue`, capture `_progressGeneration`, and build the payload from `_committedProgress` / `_committedTechTree`.
2. **Close every terminal exit path.** Report buttons, the underlying terminal World Map control, `game.returnToMap()` callback routing, and `_returnToMap()` itself all respect the Mission Report saving guard.
3. **Freeze the authoritative victory result.** `_handleStageWon` stores `completion.result`; report projection uses that same `StageResult` that persistence writes. A won snapshot alone is not treated as an implicit forever-`saving` report.
4. **Reuse `StageResult.isBetterThan`.** The projection uses the existing improvement rule, then only inspects medal rank to distinguish medal improvement from base-health improvement.
5. **Own empty-module copy in the projection.** Pure tests cover victory and loss with no acquired modules.
6. **Name the residual durability risk.** If the process is killed while `Saving…`, the result can be lost. HPA-525 intentionally adds no mid-write recovery or optimistic map state.
7. **Keep the presentation DTO breadth.** Raw result/wave fields and `MissionModuleFact.id` remain because they are cheap and useful for focused tests and HPA-528. No extra abstraction is added.
8. **Add the missing regressions.** Tests explicitly call `game.returnToMap()` during saving and verify mission-save-then-tech-purchase preserves both pieces of committed state.

## Scope decisions

### Recommended approach: page-owned report state + pure projection + shared serial writer

Keep terminal gameplay state in the existing game/session layer, but move report presentation and persistence truth into `OrionGamePage`:

- add one pure report projection that converts the terminal snapshot, frozen victory result, prior committed result, and explicit save state into immutable display content;
- render that content in one dedicated Mission Report widget;
- replace `_saveStageCompletion` with a dedicated non-optimistic stage-result save path;
- serialize that path through the existing `_saveQueue` rather than creating a parallel writer;
- keep the tech-tree/reset persistence behavior unchanged;
- keep HPA-528's future reward integration as one optional typed fact on the report content.

This preserves the single-writer invariant while deleting the optimistic stage-result rollback behavior that makes the current terminal UI dishonest.

### Alternative A: keep using `_persistSave` for stage results

This would preserve optimistic progress, committed-shadow rollback, and generic failure feedback while trying to layer Mission Report state on top. `Saving…` would still coexist with an in-memory world map that already contains uncommitted progress.

Rejected.

### Alternative B: direct `store.save` outside `_saveQueue`

This keeps non-optimistic report semantics but creates a second campaign writer. It can race queued tech-tree/reset work and violates the persistence convention established by HPA-100.

Rejected.

### Alternative C: move Mission Report state into `GameSession`

Persistence and campaign navigation are Flutter shell concerns, not mission rules. This would force a framework-free rules object to model external storage state and future reward presentation.

Rejected.

## Non-goals

This ticket does not add:

- general RunStats, analytics, coaching, or evidence export;
- persistent run history or mid-run resume;
- durable recovery for a process kill during `Saving…`;
- a generic reward registry or reward-surface framework;
- boss-blueprint ownership or Codex module pages;
- sound, haptics, animation sequencing, or screen shake;
- changes to Salvage Module selection/effect rules;
- a new campaign save schema;
- new packages;
- a new persistence controller or second save queue;
- broad cleanup of tech-tree persistence, reset serialization, or unrelated campaign save code.

The save codec is not touched. Therefore existing v1/v2 decoder cleanup is not part of HPA-525. If implementation unexpectedly requires editing `campaign_progress_store.dart`, remove obsolete development-save decoder branches in that same change rather than extending them.

## Report presentation model

Create `lib/game/ui/mission_report_content.dart` as a Flutter-free presentation model and projection.

```dart
enum MissionSaveState { saving, saved, failed }

enum MissionResultComparison {
  firstClear,
  medalImproved,
  baseHealthImproved,
  retained,
}

final class MissionModuleFact {
  const MissionModuleFact({required this.id, required this.title});

  final RunModuleId id;
  final String title;
}

final class MissionRewardFact {
  const MissionRewardFact({required this.title, required this.detail});

  final String title;
  final String detail;
}

final class MissionReportContent {
  MissionReportContent({
    required this.stageId,
    required this.stageName,
    required this.didWin,
    required this.waveNumber,
    required this.waveTotal,
    required this.remainingBaseHealth,
    required this.startingBaseHealth,
    this.result,
    this.priorSavedResult,
    this.comparison,
    required this.outcomeText,
    this.comparisonText,
    required List<MissionModuleFact> modules,
    this.emptyModulesText,
    this.saveState,
    this.saveText,
    this.reward,
    required this.nextOpportunityText,
  }) : modules = List.unmodifiable(modules);

  final String stageId;
  final String stageName;
  final bool didWin;
  final int waveNumber;
  final int waveTotal;
  final int remainingBaseHealth;
  final int startingBaseHealth;
  final StageResult? result;
  final StageResult? priorSavedResult;
  final MissionResultComparison? comparison;
  final String outcomeText;
  final String? comparisonText;
  final List<MissionModuleFact> modules;
  final String? emptyModulesText;
  final MissionSaveState? saveState;
  final String? saveText;
  final MissionRewardFact? reward;
  final String nextOpportunityText;
}
```

`MissionRewardFact` remains only two strings. It gives HPA-528 a typed optional section without creating ownership, reward selection, or a reward state machine.

`emptyModulesText` is `No Salvage Modules acquired` only when the projected module list is empty. The widget never owns a duplicate empty-state string.

## Pure projection

Expose one function:

```dart
MissionReportContent projectMissionReport({
  required GameSnapshot snapshot,
  required StageResult? victoryResult,
  required StageResult? priorSavedResult,
  required MissionSaveState? saveState,
  MissionRewardFact? reward,
});
```

The terminal snapshot remains the source of stage identity, waves, base health display, and acquired module IDs. `victoryResult` is the frozen `StageCompletion.result` supplied by `_handleStageWon`; it is also the value the save path commits.

The projection never re-derives a second victory `StageResult` from the snapshot.

### Victory projection

Victory requires both `victoryResult` and `saveState`.

Comparison reuses the existing improvement rule:

```dart
MissionResultComparison compareMissionResult(
  StageResult result,
  StageResult? prior,
) {
  if (prior == null) {
    return MissionResultComparison.firstClear;
  }
  if (!result.isBetterThan(prior)) {
    return MissionResultComparison.retained;
  }
  if (result.medal.rank > prior.medal.rank) {
    return MissionResultComparison.medalImproved;
  }
  return MissionResultComparison.baseHealthImproved;
}
```

This keeps `StageResult.isBetterThan` as the source of truth for whether a run improved. Medal rank is inspected only after improvement is established so the report can choose the right sentence.

Suggested comparison copy:

- first clear: `New first-clear result`;
- medal improvement: `Medal improved: Silver → Gold`;
- base-health improvement: `Base health improved: 14 → 18`;
- retained: `Saved best retained: Gold • 20 base health`.

Victory `outcomeText`:

```text
<Medal> medal • Base <remaining>/<starting>
```

Save copy:

- `saving` → `Saving result…`;
- `saved` + retained → `Best result already saved.`;
- `saved` + improved/new → `Saved.`;
- `failed` → `Save failed — progress unchanged.`.

Next-opportunity copy is exactly one sentence:

- saving → `Saving must finish before you replay or leave.`;
- saved → `Replay for a better result or continue on the World Map.`;
- failed → `Retry saving, or return without keeping this result.`.

The comparison sentence describes the run relative to the previous best. Only `saveText` claims persistence state.

### Loss projection

Losses do not write campaign progress, so `victoryResult`, `saveState`, `saveText`, `comparison`, and `priorSavedResult` are absent from the visible report.

Use:

```text
Reached Wave <waveNumber>/<waveTotal>
```

and:

```text
Adjust your build and retry when ready.
```

Do not infer a cause of failure.

### Salvage Module facts

Map `snapshot.acquiredRunModules` through `runModuleDefinition(id).title` inside the projection.

When the list is empty, set:

```text
No Salvage Modules acquired
```

for both victory and loss. The widget renders `content.emptyModulesText` rather than defining its own fallback copy.

## Mission Report widget

Create `lib/game/ui/mission_report_panel.dart`.

```dart
class MissionReportPanel extends StatelessWidget {
  const MissionReportPanel({
    super.key,
    required this.content,
    this.onReplay,
    this.onReturnToMap,
    this.onRetrySave,
  });

  final MissionReportContent content;
  final VoidCallback? onReplay;
  final VoidCallback? onReturnToMap;
  final VoidCallback? onRetrySave;
}
```

The panel renders immutable content and invokes callbacks. It never compares results, reads Flame components, infers save success, or writes campaign state.

### Layout

Use the existing full-screen overlay pattern with a scrollable body and fixed action area:

```text
SafeArea
└── Padding
    └── Column
        ├── Expanded
        │   └── SingleChildScrollView
        │       └── report card/content
        └── action area
```

This keeps primary actions reachable at 360×640.

Content order:

1. outcome icon + `Victory` / `Mission Failed`;
2. stage name;
3. result or reached-wave line;
4. comparison line when victorious;
5. `Salvage Modules` rows/chips or `emptyModulesText`;
6. save row when victorious;
7. optional reward fact;
8. one next-opportunity sentence.

Save meaning uses icon + text and does not rely on color.

### Actions

Victory, saving:

- `Replay Mission` disabled;
- `World Map` disabled.

Victory, saved:

- `Replay Mission`;
- `World Map`.

Victory, failed:

- `Retry Save`;
- `World Map (Unsaved)`;
- no Replay button.

Loss:

- `Retry`;
- `World Map`.

No animated multi-step reveal is required.

## Page-owned mission result state

`_OrionGamePageState` owns only the active report state:

```dart
StageResult? _missionPriorResult;
StageResult? _missionVictoryResult;
CampaignProgress? _pendingMissionProgress;
MissionSaveState? _missionSaveState;
bool _missionExitStarted = false;
```

`_pendingMissionProgress` is the proposed in-memory value used to recognize a no-op result and make the intended commit explicit. It is **not** written directly as a whole stale payload; the queued writer rebuilds from current committed state.

### Stage start

When `_startStage(stage)` succeeds, freeze the committed baseline and clear prior report state before creating the game:

```dart
_missionPriorResult = _progress.resultFor(stage.id);
_missionVictoryResult = null;
_pendingMissionProgress = null;
_missionSaveState = null;
_missionExitStarted = false;
```

`_startStage` already rejects launches while `_isSavingProgress` or `_isResetting` is true, so a new mission starts from a stable committed campaign state.

Construct the game with:

```dart
onStageWon: _handleStageWon,
onReturnToMap: _handleGameReturnToMap,
```

The second callback closes the old direct bypass around report exit guards.

### Victory callback and authoritative result

`_handleStageWon` freezes the exact `StageCompletion.result` that persistence and projection will share:

```dart
Future<void> _handleStageWon(StageCompletion completion) {
  if (_missionVictoryResult != null || _missionSaveState != null) {
    return Future<void>.value();
  }

  _missionVictoryResult = completion.result;
  final proposed = _progress.recordResult(
    completion.stage.id,
    completion.result,
  );
  _pendingMissionProgress = proposed;

  if (proposed.resultFor(completion.stage.id) == _missionPriorResult) {
    _setMissionSaveState(MissionSaveState.saved);
    return Future<void>.value();
  }

  return _saveMissionResult();
}
```

A non-improving replay performs no storage write and is immediately `saved` because its best result is already committed.

The real game publishes the terminal snapshot before invoking `onStageWon`, but both happen in the same completion call stack. `_handleStageWon` sets `_missionVictoryResult` and `_missionSaveState` synchronously before its first await, so the next Flutter frame can render a complete victory report.

Do not keep a fallback that interprets `snapshot.phase == won && _missionSaveState == null` as `saving`. A won snapshot without `_handleStageWon` is incomplete terminal input, not an endless save operation.

### Shared serial, non-optimistic mission save

`_saveMissionResult` must reuse the existing writer chain but not `_persistSave`'s optimistic mutation/rollback behavior.

Required invariants:

- enqueue on `_saveQueue`;
- capture `_progressGeneration` before enqueueing;
- increment `_pendingSaves` and set `_isSavingProgress` so the shell still has one global writer/busy signal;
- build the payload from `_committedProgress` and `_committedTechTree` inside the queued task;
- apply `recordResult(stageId, _missionVictoryResult!)` to the committed progress at execution time;
- never assign `_progress` before `store.save` succeeds;
- on success advance `_committedProgress`, `_committedTechTree`, and visible `_progress` from the successful payload;
- on failure leave `_progress` unchanged and set only `MissionSaveState.failed`;
- use `_decrementPendingSaves()` in `finally`;
- keep `_saveQueue = saveTask.catchError((_) {})` so later writers are not poisoned by a failed mission save;
- do not introduce a second queue or a rollback callback tree.

Shape:

```dart
Future<void> _saveMissionResult() async {
  if (_missionSaveState == MissionSaveState.saving ||
      _missionSaveState == MissionSaveState.saved) {
    return;
  }

  final store = _store;
  final game = _game;
  final result = _missionVictoryResult;
  if (store == null || game == null || result == null) {
    _setMissionSaveState(MissionSaveState.failed);
    return;
  }

  final stageId = game.stage.id;
  final saveGeneration = _progressGeneration;
  _setMissionSaveState(MissionSaveState.saving);
  _pendingSaves++;
  _setSavingProgress(true);

  final saveTask = _saveQueue.then((_) async {
    try {
      if (saveGeneration != _progressGeneration) {
        _setMissionSaveState(MissionSaveState.failed);
        return;
      }

      final payload = CampaignSave(
        progress: _committedProgress.recordResult(stageId, result),
        techTree: _committedTechTree,
      );
      await store.save(payload);

      if (saveGeneration == _progressGeneration) {
        _committedProgress = payload.progress;
        _committedTechTree = payload.techTree;
        _progress = payload.progress;
        _setMissionSaveState(MissionSaveState.saved);
      } else {
        _setMissionSaveState(MissionSaveState.failed);
      }
    } catch (_) {
      _setMissionSaveState(MissionSaveState.failed);
    } finally {
      _decrementPendingSaves();
    }
  });

  _saveQueue = saveTask.catchError((_) {});
  await saveTask;
}
```

This duplicates only the minimal queue plumbing needed to give the stage-result path different commit semantics. Do not extract a new persistence controller in HPA-525.

Retry calls the same method. Because `saving` and `saved` are rejected before enqueueing, repeated Retry taps cannot create duplicate writes.

### Report visibility

Loss can project immediately from a lost snapshot.

Victory renders only when all three conditions are true:

```text
snapshot.phase == won
&& _missionVictoryResult != null
&& _missionSaveState != null
```

Projection receives `_missionVictoryResult`, not a result re-derived from snapshot base health.

Existing tests that inject a synthetic won `GameSnapshot` must also invoke `onStageWon` with a matching `StageCompletion`, preferably through one shared helper. A snapshot-only win is no longer a valid complete Mission Report fixture.

## Closing the exit graph

Report button gating alone is insufficient because `game.returnToMap()` can be invoked by the underlying bottom control or programmatically.

HPA-525 closes all terminal routes.

### Underlying bottom control

The World Map button in `_BottomControls` is enabled only in ordinary build state. It is disabled for wave, won, and lost phases:

```dart
onPressed: snapshot.phase == GamePhase.build ? game.returnToMap : null,
```

The terminal report owns terminal navigation.

### Game callback routing

Use one page callback:

```dart
void _handleGameReturnToMap() {
  final snapshot = _game?.snapshot;
  if (snapshot?.isEnded == true) {
    _returnFromMissionReport();
    return;
  }
  _returnToMap();
}
```

This means programmatic `game.returnToMap()` during a terminal report reaches the same guard as report buttons.

### Defensive page guard

`_returnToMap()` itself refuses while a mission save is active:

```dart
void _returnToMap() {
  if (_missionSaveState == MissionSaveState.saving) {
    return;
  }
  setState(() {
    _game = null;
    _activeView = _ShellView.worldMap;
  });
}
```

This is intentionally redundant with report-button disabling because leaving while `Saving…` is the core product failure HPA-525 fixes.

### Report return action

```dart
void _returnFromMissionReport() {
  if (_missionExitStarted || _missionSaveState == MissionSaveState.saving) {
    return;
  }
  _missionExitStarted = true;

  if (_missionSaveState == MissionSaveState.failed) {
    _mapFeedback = 'Mission result was not saved.';
  }

  _returnToMap();
}
```

Loss has no save state and can return normally. Failed victory explicitly abandons the unsaved run and leaves the previous committed campaign state visible.

## Replay / retry

The panel does not call `game.restart` directly.

`_restartFromMissionReport`:

- refuses a winning report unless `_missionSaveState == saved`;
- allows loss retry immediately;
- refreshes `_missionPriorResult` from `_progress` after a successful save;
- clears `_missionVictoryResult`, `_pendingMissionProgress`, `_missionSaveState`, and `_missionExitStarted`;
- calls `game.restart()`.

This prevents an unsaved failed victory from being silently discarded through a hidden/programmatic Replay path. The failed report instead offers `Retry Save` or `World Map (Unsaved)`.

## Coexistence with existing campaign persistence

Do not route mission completion through `_persistSave`.

Do not create a free-floating `store.save` path either.

The existing `_saveQueue`, `_progressGeneration`, `_pendingSaves`, `_isSavingProgress`, committed state fields, and reset serialization remain the single writer infrastructure. Mission saving only changes **when visible progress is mutated**: unlike tech-tree `_persistSave`, the mission result is not optimistic and has no rollback branch.

On successful mission save, `_committedProgress` and visible `_progress` advance together. This ensures a later tech-tree purchase builds on the just-committed mission result rather than overwriting it.

## HPA-528 integration seam

HPA-525 always calls the projection with `reward: null`.

HPA-528 may later build exactly one `MissionRewardFact` from its one-blueprint rule and pass it into the same projection. HPA-525 does not add ownership, reward selection, pending-blueprint rules, or a generic reward framework.

```text
HPA-528 blueprint rule
→ optional MissionRewardFact
→ HPA-525 pure report projection
→ MissionReportPanel
```

## Testing

### Pure projection

Cover:

- first clear;
- medal improvement;
- same-medal base-health improvement;
- retained best;
- `StageResult.isBetterThan` governs improved vs retained classification;
- loss reached-wave copy;
- saving, saved, and failed copy;
- acquired module IDs/titles;
- victory with zero modules → empty list + `No Salvage Modules acquired`;
- loss with zero modules → same empty-state contract;
- optional reward fact passthrough.

### Widget

At 360×640:

- body scrolls without overflow;
- primary actions remain reachable;
- saving disables Replay/World Map;
- saved victory exposes Replay/World Map;
- failed victory exposes Retry Save + World Map (Unsaved);
- loss exposes Retry + World Map;
- module empty-state copy renders from content;
- save state has visible text/icon, not color-only meaning.

### Page integration

Use the existing delayed/failing `_TestCampaignProgressStore` and a helper that publishes a terminal won snapshot **and** invokes `onStageWon` with the same `StageResult`.

Cover:

- improving victory enters `Saving result…` before the queued write completes;
- `_progress` and stored progress remain unchanged while saving;
- direct `game.returnToMap()` during saving remains on the Mission Report;
- terminal bottom World Map control is disabled;
- save success changes the report to `Saved.` and updates committed/in-memory progress;
- save failure changes the report to `Save failed — progress unchanged.` with no rollback needed;
- Retry Save starts exactly one additional queued write and can succeed;
- rapid repeated Retry Save does not duplicate writes;
- repeated report World Map actions navigate once;
- `World Map (Unsaved)` after failure shows `Mission result was not saved.` and the prior committed map state;
- retained replay result performs no write and shows `Best result already saved.`;
- loss never attempts a campaign save;
- acquired Salvage Module titles appear;
- **mission save then tech purchase:** after a mission result successfully commits, return to the map, purchase one affordable tech upgrade, then assert the store contains both the new stage result and the purchased upgrade.

The last regression proves the mission path shares the existing committed baseline/writer contract instead of racing or overwriting the tech-tree path.

### Replacing obsolete optimistic-stage tests

Remove or rewrite tests whose contract HPA-525 intentionally deletes:

- optimistic clear visible on map before write resolves;
- multiple sibling stage-completion writes queued from one active mission;
- optimistic rollback across concurrent stage-result callbacks;
- stage-result-specific queued-after-disposal cases whose purpose was preserving an optimistic aggregate.

Keep generic tech-tree save queue/reset tests unchanged.

Do not replace removed tests with durable process-death recovery. The explicit residual contract is: if the app process dies before the save future commits, the run result may be lost and the prior committed campaign remains authoritative.

## Acceptance criteria

- Victory and loss reports are understandable within a few seconds.
- Stage result, comparison, selected modules, save truth, and next action come from one pure projection.
- The report and persistence path use the same frozen `StageCompletion.result` for victory.
- `StageResult.isBetterThan` remains the source of truth for whether a result improved.
- An improving victory does not update campaign progress before persistence succeeds.
- Mission writes share `_saveQueue` / generation / committed-state composition with existing campaign persistence.
- Saving, saved, and failed states are visually and semantically distinct.
- No terminal callback can leave the mission while saving is in flight.
- Save failure leaves prior campaign progress untouched and provides Retry Save plus World Map (Unsaved).
- A retained replay result performs no storage write.
- Rebuilds/repeated taps do not duplicate result saves or world-map navigation.
- HPA-528 can supply one optional typed reward fact without changing report architecture.
- The layout works at 360×640 with primary actions reachable.
- A mission save followed by a tech-tree purchase persists both changes.
- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and the full `flutter test` suite pass.

## Self-review

- One campaign writer remains: the mission path shares `_saveQueue`; it does not create a parallel chain.
- The stage-result path is non-optimistic: no stage-result rollback tree is required.
- All terminal navigation reaches a saving guard.
- Victory display and persistence share one frozen `StageResult`.
- Empty-module copy has one owner in the pure projection.
- No new schema, package, controller, event system, or reward framework is introduced.
- Unrelated tech-tree/reset behavior remains in place.
- Process death during `Saving…` is explicitly accepted as a residual risk rather than hidden by optimistic state.
- No placeholders or deferred design decisions remain.