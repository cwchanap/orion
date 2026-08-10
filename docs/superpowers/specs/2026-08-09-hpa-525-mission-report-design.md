# HPA-525 Mission Report Design

## Context

HPA-527 has shipped the minimum Salvage Module vertical slice, so HPA-525 is now Orion's next actionable reward-loop task. It is unblocked by HPA-527 and directly blocks HPA-528, the one-blueprint reward proof.

The current end-of-run path is intentionally small but has two mismatched responsibilities:

- `OrionDefenseGame` publishes a terminal `GameSnapshot` and calls `onStageWon` after a victory.
- `OrionGamePage` persists the stage result through the generic optimistic `_persistSave` queue.
- `_EndStatePanel` derives its own victory/loss copy directly from `GameSnapshot` and exposes `game.restart` / `game.returnToMap` immediately.
- the report therefore cannot distinguish saving, saved, and failed progress, and the player can leave while an optimistic result is still unresolved.

HPA-525 should replace that path without introducing a run analytics system, persistence redesign, report controller, event bus, or generic reward framework.

## Goal

Replace the minimal end panel with a compact Mission Report that answers four questions in a few seconds:

1. Did I win or lose?
2. Did this run improve the committed stage result?
3. Which Salvage Modules defined the run?
4. What can I do next?

For a victory that improves campaign progress, the report appears immediately in `Saving…`, becomes `Saved` only after the write succeeds, and becomes `Save failed` without optimistic campaign mutation if the write fails.

## Scope decisions

### Recommended approach: page-owned result save + pure report projection

Keep the terminal gameplay snapshot in the existing game/session layer, but move end-of-run presentation and persistence truth into `OrionGamePage`:

- add one pure report projection that converts the terminal snapshot + prior committed result + explicit save state into immutable display content;
- render that content in one dedicated Mission Report widget;
- replace `_saveStageCompletion` with a dedicated single-result save path that does not use `_persistSave`;
- keep the tech-tree/reset persistence machinery unchanged;
- keep HPA-528's future reward integration as one optional typed fact on the report content.

This is the smallest change that makes save meaning honest and gives HPA-528 a clean reward slot.

### Alternative A: keep using `_persistSave`

This would add report state around the existing queued optimistic writer. It changes fewer lines initially, but preserves the exact complexity HPA-525 is meant to remove from the stage-result path: optimistic progress, committed shadows, rollback branches, generation checks, and queued mutation semantics. It also makes `Saving…` harder to reason about because the world-map model can already contain uncommitted data.

Rejected.

### Alternative B: move Mission Report state into `GameSession`

`GameSession` could own report/save phases, but persistence and campaign navigation are Flutter shell concerns, not mission rules. That would force a framework-free rules object to model external storage state and future blueprint presentation.

Rejected.

## Non-goals

This ticket does not add:

- general RunStats, analytics, coaching, or evidence export;
- persistent run history or mid-run resume;
- a generic reward registry or reward-surface framework;
- boss-blueprint ownership or Codex module pages;
- sound, haptics, animation sequencing, or screen shake;
- changes to Salvage Module selection/effect rules;
- a new campaign save schema;
- new packages;
- broad cleanup of tech-tree persistence, reset serialization, or unrelated campaign save code.

The save codec is not touched. Therefore the existing v1/v2 decoder cleanup is not part of HPA-525. If implementation unexpectedly requires editing `campaign_progress_store.dart`, remove obsolete development-save decoder branches in that same change rather than extending them.

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
  final MissionSaveState? saveState;
  final String? saveText;
  final MissionRewardFact? reward;
  final String nextOpportunityText;
}
```

`MissionRewardFact` is intentionally only two strings. It gives HPA-528 a typed optional section without creating a reward protocol, ownership model, or state machine.

## Pure projection

Expose one function:

```dart
MissionReportContent projectMissionReport({
  required GameSnapshot snapshot,
  required StageResult? priorSavedResult,
  required MissionSaveState? saveState,
  MissionRewardFact? reward,
});
```

The projection is the only place that converts raw game/campaign facts into report copy. The widget does not inspect Flame components, derive medals, compare results, or infer persistence success.

### Victory projection

Derive the run result with the existing rule:

```dart
final result = StageResult.fromVictoryBaseHealth(
  snapshot.baseHealth,
  startingBaseHealth: snapshot.startingBaseHealth,
);
```

Comparison is deterministic:

1. no prior result → `firstClear`;
2. higher medal rank → `medalImproved`;
3. same medal and higher base health → `baseHealthImproved`;
4. otherwise → `retained`.

Suggested copy:

- first clear: `New first-clear result`;
- medal improvement: `Medal improved: Silver → Gold`;
- base-health improvement: `Base health improved: 14 → 18`;
- retained: `Saved best retained: Gold • 20 base health`.

The first three lines describe the run result, not a committed save. Commitment is communicated only by `saveText`.

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

### Loss projection

Losses do not write campaign progress, so `saveState`, `saveText`, `comparison`, and `priorSavedResult` are absent from the visible report.

Use:

```text
Reached Wave <waveNumber>/<waveTotal>
```

and one neutral next-opportunity sentence:

```text
Adjust your build and retry when ready.
```

Do not infer a cause of failure.

### Salvage Module facts

Map `snapshot.acquiredRunModules` through `runModuleDefinition(id).title` inside the projection.

The report stores both the typed `RunModuleId` and title through `MissionModuleFact`. If the player loses before the first draft, render an explicit `No Salvage Modules acquired` row rather than hiding the section.

## Mission Report widget

Create `lib/game/ui/mission_report_panel.dart`.

`MissionReportPanel` receives immutable content and explicit callbacks only:

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

The panel may use `content.saveState` to choose labels/sections, but it never decides whether a save succeeded. Null callbacks are disabled buttons.

### Layout

Use the existing full-screen overlay pattern, but make actions persistently reachable:

```text
SafeArea
└── Padding
    └── Column
        ├── Expanded
        │   └── SingleChildScrollView
        │       └── report card/content
        └── action area
```

This keeps the body scrollable while actions stay reachable at 360×640.

Content order:

1. outcome icon + `Victory` / `Mission Failed`;
2. stage name;
3. result or reached-wave line;
4. comparison line when victorious;
5. `Salvage Modules` chips/rows;
6. save row when victorious;
7. optional reward fact;
8. one next-opportunity sentence.

Save meaning must not rely on color. Use icon + text for `Saving`, `Saved`, and `Save failed`.

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
- no Replay button, because retrying or explicitly abandoning the unsaved result is the only useful choice.

Loss:

- `Retry`;
- `World Map`.

No animated multi-step reveal is required.

## Page-owned mission result state

`_OrionGamePageState` owns only the state needed for the active terminal report:

```dart
StageResult? _missionPriorResult;
CampaignProgress? _pendingMissionProgress;
MissionSaveState? _missionSaveState;
bool _missionExitStarted = false;
```

### Stage start

When `_startStage(stage)` succeeds, freeze the currently committed baseline before creating the game:

```dart
_missionPriorResult = _progress.resultFor(stage.id);
_pendingMissionProgress = null;
_missionSaveState = null;
_missionExitStarted = false;
```

`_startStage` already rejects launches while the generic campaign writer/reset path is active, so the baseline is not competing with a pending tech-tree save.

### Victory callback

Replace `_saveStageCompletion` with `_handleStageWon` plus `_saveMissionResult`.

`_handleStageWon` computes one proposed immutable progress value:

```dart
void _handleStageWon(StageCompletion completion) {
  if (_missionSaveState != null) {
    return;
  }

  final proposed = _progress.recordResult(
    completion.stage.id,
    completion.result,
  );
  _pendingMissionProgress = proposed;

  if (proposed.resultFor(completion.stage.id) == _missionPriorResult) {
    setState(() {
      _missionSaveState = MissionSaveState.saved;
    });
    return;
  }

  _saveMissionResult();
}
```

A replay that cannot improve the committed result does not manufacture a no-op storage write. It is immediately `saved` because the best result already exists on disk. This avoids presenting a meaningless failure for a result that requires no persistence.

### Save attempt

`_saveMissionResult` is single-flight and does not mutate `_progress` optimistically:

```dart
Future<void> _saveMissionResult() async {
  if (_missionSaveState == MissionSaveState.saving ||
      _missionSaveState == MissionSaveState.saved) {
    return;
  }

  final store = _store;
  final proposed = _pendingMissionProgress;
  if (store == null || proposed == null) {
    if (mounted) {
      setState(() {
        _missionSaveState = MissionSaveState.failed;
      });
    } else {
      _missionSaveState = MissionSaveState.failed;
    }
    return;
  }

  if (mounted) {
    setState(() {
      _missionSaveState = MissionSaveState.saving;
    });
  } else {
    _missionSaveState = MissionSaveState.saving;
  }

  try {
    await store.save(
      CampaignSave(
        progress: proposed,
        techTree: _committedTechTree,
      ),
    );
    _progress = proposed;
    _committedProgress = proposed;
    if (mounted) {
      setState(() {
        _missionSaveState = MissionSaveState.saved;
      });
    } else {
      _missionSaveState = MissionSaveState.saved;
    }
  } catch (_) {
    if (mounted) {
      setState(() {
        _missionSaveState = MissionSaveState.failed;
      });
    } else {
      _missionSaveState = MissionSaveState.failed;
    }
  }
}
```

The implementation can factor the mounted assignment into a tiny helper to avoid duplication, but it should not introduce a controller or queue.

On failure, `_progress` remains the prior committed value, so there is no rollback branch.

Retry calls the same `_saveMissionResult` using the same `_pendingMissionProgress`.

### Coexistence with existing campaign persistence

Do not route mission completion through `_persistSave`.

Do not remove the existing `_saveQueue`, `_committedTechTree`, generation counter, or reset logic in HPA-525 because the tech-tree/reset path still uses them. The stage launch guard already prevents entering a mission while those paths are active, and Mission Report disables leaving while its own result write is active, so the two paths do not overlap in normal UI flow.

On successful mission save, assign `_committedProgress = proposed` so the existing tech-tree writer's committed baseline remains correct after returning to the map.

## Replay and world-map actions

The panel must not call `game.restart` / `game.returnToMap` directly.

### Replay

Page callback:

1. reject while `saveState == saving`;
2. refresh `_missionPriorResult` from the now-current `_progress`;
3. clear `_pendingMissionProgress` and `_missionSaveState`;
4. call `game.restart()`.

The next run therefore compares against the result that is actually committed after a successful save.

### Return to map

Use `_missionExitStarted` as a one-shot guard:

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

`_startStage` resets the guard for the next mission.

On failure, returning to the map naturally shows the previous committed campaign state because no optimistic progress was applied.

## HPA-528 integration seam

HPA-525 always calls the projection with `reward: null`.

HPA-528 may later build exactly one `MissionRewardFact` from its one-blueprint rule and pass it into the same projection. HPA-525 does not add ownership, reward selection, or pending-blueprint logic.

That keeps the dependency direction simple:

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
- loss reached-wave copy;
- saving, saved, and failed copy;
- acquired module IDs/titles;
- no-module loss;
- optional reward fact passthrough.

### Widget

At 360×640:

- body can scroll without overflow;
- primary actions remain reachable;
- saving disables Replay/World Map;
- saved victory exposes Replay/World Map;
- failed victory exposes Retry Save + World Map (Unsaved);
- loss exposes Retry + World Map;
- save state has visible text/icon, not color-only meaning.

### Page integration

Use the existing delayed/failing test campaign store to cover:

- victory enters `Saving result…` before the write completes;
- campaign progress is not optimistic while saving;
- success changes the report to `Saved.` and updates persisted/in-memory progress;
- failure changes the report to `Save failed — progress unchanged.` and leaves campaign progress unchanged;
- Retry Save starts exactly one new write and can succeed;
- buttons cannot leave or replay while saving;
- rapid repeated Retry Save does not duplicate writes;
- repeated World Map taps do not duplicate navigation;
- retained replay result performs no write and shows `Best result already saved.`;
- loss never attempts a campaign save;
- acquired Salvage Module titles appear in the report.

Remove or rewrite stage-completion tests whose contract is intentionally deleted:

- optimistic clear visible on map before write resolves;
- multiple sibling stage-completion writes queued from one active mission;
- queued stage-result saves after page disposal;
- rollback of optimistic stage progress.

Keep tech-tree save queue/reset tests unchanged.

## Acceptance criteria

- Victory and loss reports are understandable within a few seconds.
- Stage result, comparison, selected modules, save truth, and next action come from one pure projection.
- An improving victory does not update campaign progress before persistence succeeds.
- Saving, saved, and failed states are visually and semantically distinct.
- Save failure leaves the prior campaign progress untouched and provides Retry Save plus World Map (Unsaved).
- A retained replay result does not perform a meaningless storage write.
- Rebuilds/repeated taps do not duplicate result saves or world-map navigation.
- HPA-528 can supply one optional typed reward fact without changing the report architecture.
- The layout works at 360×640 with primary actions reachable.
- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and the full `flutter test` suite pass.

## Self-review

- No new persistence schema, package, controller, queue, or event system is introduced.
- The stage-result path gets simpler: one prior result, one proposed progress value, one explicit save state, no optimistic rollback.
- Unrelated tech-tree/reset persistence remains in place.
- HPA-528 gets only the minimum typed seam it needs.
- No placeholders or deferred design decisions remain in this spec.
