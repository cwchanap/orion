# HPA-525 Mission Report Design

## Context

HPA-527 shipped Orion's minimum Salvage Module vertical slice. HPA-525 is now the next M1 reward-loop task and directly blocks HPA-528.

The current end-of-run path mixes three concerns:

- `OrionDefenseGame` publishes a terminal `GameSnapshot` and emits `StageCompletion` on victory.
- `OrionGamePage` persists victory through `_persistSave`, which currently applies stage progress optimistically and rolls it back on failure.
- `_EndStatePanel` independently derives result copy from the snapshot and exposes immediate restart/map actions.

That creates two player-facing problems: save truth is invisible, and the stage can be left before persistence is resolved.

HPA-100 also established an important repository invariant: campaign writes share one serialized `_saveQueue`, use `_progressGeneration` for stale-work protection, and compose writes from `_committedProgress` / `_committedTechTree`. HPA-525 must preserve that writer rather than copy it.

## Goal

Replace the minimal terminal panel with a compact Mission Report that answers:

1. Did I win or lose?
2. Did this run improve my committed best result?
3. Which Salvage Modules defined the run?
4. What can I do next?

An improving victory must appear as `Saving…`, become `Saved` only after persistence succeeds, and become `Save failed` without ever exposing uncommitted campaign progress.

## Review resolution

The accepted design after two review passes is:

1. **Reuse `_persistSave` instead of copying its writer protocol.** Optimistic mutation is already optional because `nextProgress` / `nextTechTree` are nullable. HPA-525 only needs small optional completion/failure hooks and an optional rollback callback.
2. **Freeze the authoritative victory facts.** `_handleStageWon` stores both `completion.stage.id` and `completion.result`. The report and the persisted result use those same values.
3. **Use typed projection entry points.** `projectVictoryReport(...)` and `projectLossReport(...)` share one DTO but avoid nullable victory-only arguments and release-mode `assert` contracts.
4. **Reuse module rendering.** `MissionReportContent` carries `List<RunModuleId>` and `MissionReportPanel` reuses `AcquiredRunModuleStrip`, keeping title/effect copy identical to the in-run HUD.
5. **Delete proposed progress state.** The page uses `StageResult.isBetterThan(_missionPriorResult)` for the no-op decision; the committed payload is rebuilt inside `_persistSave`.
6. **Close terminal exits centrally.** Report buttons are disabled while saving, the underlying map control is build-only, and `_returnToMap()` itself refuses while the Mission Report is saving.
7. **No one-shot navigation flag.** Returning to the map is a synchronous idempotent state assignment; a separate `_missionExitStarted` flag has no observable effect and is removed.
8. **Keep the typed HPA-528 reward seam.** `MissionRewardFact` remains because HPA-528 already explicitly depends on HPA-525's optional Mission Report reward slot. HPA-525 always passes `null`.
9. **Migrate the old stage-save tests in the same implementation task.** No implementation commit may knowingly leave the full suite red.
10. **Accept process-kill loss during `Saving…`.** No optimistic workaround, mid-write resume, or durable transaction recovery is added.

## Non-goals

- RunStats, analytics, coaching, or evidence export
- persistent run history or mid-run resume
- durable recovery from process death during `Saving…`
- a new report controller or persistence controller
- a new save queue or save schema
- a generic reward registry/framework
- boss-blueprint ownership or Codex module pages
- sound, haptics, animation sequencing, or screen shake
- Salvage Module rule/tuning changes
- broad tech-tree/reset persistence redesign
- new packages

The save codec is not touched. If implementation unexpectedly must edit it, remove obsolete v1/v2 development-save decoding rather than extending it.

## Report model

Create `lib/game/ui/mission_report_content.dart` as a Flutter-free presentation model.

```dart
enum MissionSaveState { saving, saved, failed }

enum MissionResultComparison {
  firstClear,
  medalImproved,
  baseHealthImproved,
  retained,
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
    required this.outcomeText,
    this.result,
    this.comparison,
    this.comparisonText,
    required List<RunModuleId> moduleIds,
    this.emptyModulesText,
    this.saveState,
    this.saveText,
    this.reward,
    required this.nextOpportunityText,
  }) : moduleIds = List.unmodifiable(moduleIds);

  final String stageId;
  final String stageName;
  final bool didWin;
  final String outcomeText;
  final StageResult? result;
  final MissionResultComparison? comparison;
  final String? comparisonText;
  final List<RunModuleId> moduleIds;
  final String? emptyModulesText;
  final MissionSaveState? saveState;
  final String? saveText;
  final MissionRewardFact? reward;
  final String nextOpportunityText;
}
```

The DTO intentionally carries only values the report renders or HPA-528 immediately consumes. It does not retain raw wave/base-health fields once those are projected into copy.

`MissionRewardFact` is intentionally tiny. HPA-528 already specifies pending/saved/failed blueprint copy in this report; retaining one typed optional slot is cheaper than inventing an untyped special case later.

## Pure projection

Use two explicit entry points in the same projection module.

### Victory

```dart
MissionReportContent projectVictoryReport({
  required GameSnapshot snapshot,
  required StageResult result,
  required StageResult? priorSavedResult,
  required MissionSaveState saveState,
  MissionRewardFact? reward,
});
```

Improvement truth reuses the domain rule:

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

Copy:

- first clear: `New first-clear result`
- medal improvement: `Medal improved: Silver → Gold`
- base-health improvement: `Base health improved: 14 → 18`
- retained: `Saved best retained: Gold • 20 base health`
- outcome: `<Medal> medal • Base <bestBaseHealth>/<startingBaseHealth>`

Save copy:

- saving: `Saving result…`
- saved + retained: `Best result already saved.`
- saved + improved/new: `Saved.`
- failed: `Save failed — progress unchanged.`

Next opportunity:

- saving: `Saving must finish before you replay or leave.`
- saved: `Replay for a better result or continue on the World Map.`
- failed: `Retry saving, or return without keeping this result.`

Only `saveText` claims persistence state. Comparison text describes the run relative to the prior committed best.

### Loss

```dart
MissionReportContent projectLossReport({
  required GameSnapshot snapshot,
});
```

Loss copy:

- outcome: `Reached Wave <waveNumber>/<waveTotal>`
- next opportunity: `Adjust your build and retry when ready.`
- no result comparison or save state

Do not infer a cause of failure.

### Salvage Modules

Both projections copy `snapshot.acquiredRunModules` into `moduleIds`.

If empty, set:

```text
No Salvage Modules acquired
```

The widget owns no duplicate empty-state string.

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

The widget renders immutable content only.

Layout:

```text
SafeArea
└── Padding
    └── Column
        ├── Expanded
        │   └── SingleChildScrollView
        │       └── report content
        └── fixed action area
```

Content order:

1. outcome icon + `Victory` / `Mission Failed`
2. stage name
3. outcome text
4. comparison text for victory
5. `Salvage Modules`
6. `AcquiredRunModuleStrip(moduleIds: content.moduleIds)` or `emptyModulesText`
7. save row for victory
8. optional `MissionRewardFact`
9. one next-opportunity sentence

Save meaning uses icon + text, not color alone.

Action matrix:

| State | Actions |
| --- | --- |
| victory + saving | disabled Replay Mission, disabled World Map |
| victory + saved | Replay Mission, World Map |
| victory + failed | Retry Save, World Map (Unsaved) |
| loss | Retry, World Map |

No animated reveal is required.

## Page-owned state

`_OrionGamePageState` owns only:

```dart
StageResult? _missionPriorResult;
StageResult? _missionVictoryResult;
String? _missionStageId;
MissionSaveState? _missionSaveState;
```

No `_pendingMissionProgress` and no `_missionExitStarted`.

### Stage start

Before creating the game:

```dart
_missionPriorResult = _progress.resultFor(stage.id);
_missionVictoryResult = null;
_missionStageId = null;
_missionSaveState = null;
```

Stage launch already refuses while `_isSavingProgress` / `_isResetting` is true, so the baseline is committed and stable.

Keep the game's map callback routed through the page:

```dart
onStageWon: _handleStageWon,
onReturnToMap: _returnFromMissionReport,
```

`_returnFromMissionReport` also works during ordinary build state because `saveState == null`.

### Victory callback

Preserve the existing defensive reset guard even though reset is normally reachable only from the world map:

```dart
void _handleStageWon(StageCompletion completion) {
  if (_isResetting ||
      _missionVictoryResult != null ||
      _missionSaveState != null) {
    return;
  }

  _missionStageId = completion.stage.id;
  _missionVictoryResult = completion.result;

  if (!completion.result.isBetterThan(_missionPriorResult)) {
    _setMissionSaveState(MissionSaveState.saved);
    return;
  }

  _saveMissionResult();
}
```

The production game publishes its terminal snapshot immediately before invoking `onStageWon` in the same call stack. `_handleStageWon` sets the frozen result and save state before the next Flutter frame.

A synthetic won snapshot without the matching completion callback is incomplete test input. There is no `null => Saving…` fallback.

## Reuse `_persistSave` as the one writer

Do not copy `_saveQueue`, generation, pending-count, committed-payload, or error-isolation logic into `_saveMissionResult`.

Extend `_persistSave` narrowly:

```dart
Future<void> _persistSave({
  CampaignProgress? nextProgress,
  CampaignTechTree? nextTechTree,
  required CampaignSave Function(CampaignSave committed) buildSave,
  VoidCallback? rollback,
  ValueChanged<CampaignSave>? onCommitted,
  VoidCallback? onFailed,
}) async {
  ...
}
```

Existing tech-tree behavior remains the default:

- `nextTechTree` is applied optimistically;
- `rollback` restores it on failure;
- when `onFailed` is absent, existing campaign-persistence feedback is shown;
- committed state advances exactly as today.

New callback rules:

- `onCommitted(payload)` runs only after `store.save(payload)` succeeds and the generation still matches, after `_committedProgress` / `_committedTechTree` advance;
- `onFailed()` runs for store-unavailable, write failure, or a stale-generation mission attempt;
- when `onFailed` is supplied, do not also show the generic campaign-persistence breadcrumb;
- `rollback` is optional because the Mission Report path applies no optimistic mutation;
- `_pendingSaves`, `_isSavingProgress`, `_saveQueue.catchError`, and `finally { _decrementPendingSaves(); }` remain one implementation.

HPA-525 does not add a second persistence helper/controller.

### Mission save

```dart
Future<void> _saveMissionResult() async {
  if (_missionSaveState == MissionSaveState.saving ||
      _missionSaveState == MissionSaveState.saved) {
    return;
  }

  final stageId = _missionStageId;
  final result = _missionVictoryResult;
  if (stageId == null || result == null) {
    _setMissionSaveState(MissionSaveState.failed);
    return;
  }

  _setMissionSaveState(MissionSaveState.saving);

  await _persistSave(
    buildSave: (committed) => CampaignSave(
      progress: committed.progress.recordResult(stageId, result),
      techTree: committed.techTree,
    ),
    onCommitted: (payload) {
      _progress = payload.progress;
      _setMissionSaveState(MissionSaveState.saved);
    },
    onFailed: () => _setMissionSaveState(MissionSaveState.failed),
  );
}
```

The callback's returned future is not used as a second transaction boundary: `_persistSave` retains its existing enqueue semantics. Mission state transitions come from `onCommitted` / `onFailed`.

No visible `_progress` mutation occurs before commit, and no rollback branch exists for mission progress.

Retry calls the same method. `saving` / `saved` guards prevent duplicate queued writes.

## Report visibility

Loss can render directly from a lost snapshot.

Victory renders only when:

```text
snapshot.phase == won
&& _missionVictoryResult != null
&& _missionSaveState != null
```

Then call `projectVictoryReport(...)` with the frozen result.

Tests that synthesize victory must set the won snapshot and invoke `onStageWon` with matching stage/result data through a shared helper.

## Closing the exit graph

### Underlying bottom control

The stage-level World Map button is build-only:

```dart
onPressed: snapshot.phase == GamePhase.build ? game.returnToMap : null,
```

Terminal navigation belongs to the report.

### Central page guard

All game/report map callbacks ultimately call:

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

This is the authoritative guard.

### Report/game return callback

```dart
void _returnFromMissionReport() {
  if (_missionSaveState == MissionSaveState.saving) {
    return;
  }

  if (_missionSaveState == MissionSaveState.failed) {
    _mapFeedback = 'Mission result was not saved.';
  }

  _returnToMap();
}
```

During normal build state `_missionSaveState == null`, so the same callback returns to the map normally.

Repeated calls are idempotent: they assign the same map state and do not initiate an external navigation transaction. No one-shot flag is needed.

## Replay

`_restartFromMissionReport`:

- victory: allow only when `saveState == saved`
- loss: allow immediately
- refresh `_missionPriorResult = _progress.resultFor(game.stage.id)` after successful save
- clear `_missionVictoryResult`, `_missionStageId`, `_missionSaveState`
- call `game.restart()`

A failed victory cannot be silently discarded through Replay; it offers Retry Save or World Map (Unsaved).

## HPA-528 seam

HPA-528 already defines Mission Report behavior for one blueprint:

- pending during save
- recovered after save success
- not recovered after save failure
- no duplicate reward on replay

HPA-525 therefore keeps:

```dart
MissionRewardFact? reward
```

but always supplies `null`. HPA-528 can populate this one field without changing report structure. No ownership model or reward registry is introduced here.

## Testing

### Pure projection

Cover:

- first clear
- medal improvement
- base-health improvement
- retained best
- saving/saved/failed copy
- loss reached-wave copy
- module IDs passed through
- empty modules for victory and loss
- optional reward passthrough

### Widget

At 360×640:

- no overflow; body scrolls
- primary action area remains reachable
- saving actions disabled
- saved victory has Replay + World Map
- failed victory has Retry Save + World Map (Unsaved)
- loss has Retry + World Map
- module rendering reuses `AcquiredRunModuleStrip`
- empty-module sentence is visible
- save state uses icon + text

### Page/integration

The existing stage-save tests contain many synthetic multi-completion scenarios that cease to model production after `_handleStageWon` becomes single-result. Migrate/delete them in the same task as the page implementation; do not knowingly commit a red suite.

Keep equivalent coverage for the invariants HPA-525 still relies on:

- improving victory is `Saving…` before commit and `_progress` remains unchanged
- success updates report + committed/in-memory progress
- failure leaves progress unchanged
- Retry Save queues exactly one new attempt and can succeed
- retained replay performs no write
- loss performs no write
- `game.returnToMap()` during saving is blocked
- null store produces `MissionSaveState.failed` without throwing
- page disposal during a delayed failure never calls `setState` on a defunct State
- stage launch remains blocked while the shared writer is busy
- reset still serializes correctly with queued writes
- mission save followed by a tech-tree purchase preserves both committed changes

Old tests whose only contract is optimistic stage progress, multiple synthetic stage completions from one run, or stage-result rollback are removed rather than rewritten.

Where a queue/reset/disposal invariant belongs to generic persistence rather than Mission Report behavior, re-plumb it through tech-tree purchases so `_persistSave` retains direct regression coverage.

## Acceptance criteria

- Victory/loss reports are understandable in seconds.
- Report and persistence use the same frozen stage ID/result for victory.
- Projection uses typed victory/loss entry points with no release-only assertion contract.
- Salvage Module rendering is consistent with the existing in-run strip.
- Improving victory does not change visible campaign progress before persistence succeeds.
- Retained replay performs no storage write.
- Saving, saved, and failed states are explicit and honest.
- Save failure leaves prior progress untouched and provides Retry Save + World Map (Unsaved).
- All terminal exits are blocked while saving.
- One `_persistSave` implementation owns queue/generation/pending/committed-state protocol.
- HPA-528 retains one typed optional reward slot without a generic reward framework.
- 360×640 layout keeps actions reachable.
- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and full `flutter test` pass.

## Residual risk

If the app process dies while the report says `Saving…`, the run result may be lost because HPA-525 intentionally does not persist optimistically or implement durable transaction recovery. This is acceptable for the current pre-release hobby-project scope.
