# HPA-525 Mission Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Orion's minimal terminal panel with a compact Mission Report whose result comparison, Salvage Module summary, save truth, and actions stay honest through save success, failure, retry, and navigation.

**Architecture:** Keep `GameSession` / `OrionDefenseGame` as the source of terminal gameplay facts. Add one Flutter-free report projection module with typed victory/loss entry points and one dumb report widget. `OrionGamePage` owns Mission Report state and reuses the existing `_persistSave` queue/generation/committed-state protocol with opt-in non-optimistic completion/failure hooks rather than copying the writer.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- HPA-527 is the gameplay baseline; do not change Salvage Module offer/effect rules.
- Do not add a report phase to `GameSession` or a new `GamePhase`.
- Do not add RunStats, analytics, coaching, run history, mid-run persistence, or a generic reward framework.
- Reuse `_persistSave`; do not duplicate `_saveQueue`, `_progressGeneration`, `_pendingSaves`, `_isSavingProgress`, or committed-payload logic.
- Keep optimistic mutation optional: mission saves pass no `nextProgress` / `nextTechTree`.
- Make `rollback` optional and add only `onCommitted` / `onFailed` hooks needed by the mission path.
- Existing tech-tree/reset behavior must remain unchanged.
- Freeze `completion.stage.id` and `completion.result`; report and persistence use those same values.
- Delete `_pendingMissionProgress`; use `StageResult.isBetterThan` directly for the no-op decision.
- Do not use a won-snapshot `null => Saving…` fallback.
- Victory save states are exactly `saving`, `saved`, `failed`; loss has no save state.
- Save failure leaves visible campaign progress unchanged.
- Retained replay performs no storage write.
- While saving, report actions and all map exit paths are blocked.
- No `_missionExitStarted`; returning to the map is synchronous/idempotent.
- Reuse `AcquiredRunModuleStrip` in the report.
- Projection owns `No Salvage Modules acquired`.
- Keep one optional typed `MissionRewardFact` because HPA-528 explicitly depends on the report reward slot; HPA-525 always supplies `null`.
- Do not edit the save codec unless mechanically required; if touched, remove obsolete v1/v2 development-save decoding rather than extending it.
- Target 360×640 logical pixels; body may scroll, actions stay reachable.
- Save meaning uses icon + text, not color alone.
- Process death during `Saving…` may lose the run result; do not add durable recovery.
- Every task that modifies production behavior ends with the relevant focused tests; Task 3 must also end with the full existing suite green because it migrates old persistence tests.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`.

## File Map

### Create

- `lib/game/ui/mission_report_content.dart` — DTO + pure victory/loss projection.
- `lib/game/ui/mission_report_panel.dart` — compact full-screen report overlay.
- `test/game/mission_report_content_test.dart` — pure projection coverage.
- `test/widget/mission_report_panel_test.dart` — report layout/action coverage.

### Modify

- `lib/game/ui/orion_game_page.dart` — extend `_persistSave`, own mission report state, render panel, save non-optimistically, guard exits, remove `_EndStatePanel`.
- `test/widget_test.dart` — migrate old stage-save tests and add mission integration coverage.

No intended production changes in `GameSession`, `OrionDefenseGame`, `CampaignProgress`, or `CampaignProgressStore`.

---

## Task 1: Add typed Mission Report projection

**Files:**
- Create: `lib/game/ui/mission_report_content.dart`
- Create: `test/game/mission_report_content_test.dart`

**Interfaces:**
- Produces `MissionSaveState`, `MissionResultComparison`, `MissionRewardFact`, `MissionReportContent`.
- Produces `projectVictoryReport(...)` and `projectLossReport(...)`.
- Carries raw `List<RunModuleId>` so Task 2 can reuse `AcquiredRunModuleStrip`.

- [ ] **Step 1: Write failing projection tests**

Create `test/game/mission_report_content_test.dart` with a compact snapshot helper:

```dart
GameSnapshot terminalSnapshot({
  required GamePhase phase,
  int baseHealth = 14,
  int waveNumber = 8,
  List<RunModuleId> modules = const [],
}) {
  return GameSnapshot(
    phase: phase,
    gold: 120,
    baseHealth: baseHealth,
    startingBaseHealth: 20,
    waveNumber: waveNumber,
    waveTotal: 8,
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    stageLabel: 'Alpha',
    unlockedTowerTypes: const [TowerType.laser, TowerType.cryo],
    stageModifiers: const [],
    nextWavePreview: null,
    selectedCell: null,
    selectedTower: null,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    acquiredRunModules: modules,
  );
}
```

Add explicit tests:

```dart
test('projects first clear while saving', () {
  final content = projectVictoryReport(
    snapshot: terminalSnapshot(
      phase: GamePhase.won,
      modules: const [RunModuleId.heavyCaliber],
    ),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    priorSavedResult: null,
    saveState: MissionSaveState.saving,
  );

  expect(content.outcomeText, 'Silver medal • Base 14/20');
  expect(content.comparison, MissionResultComparison.firstClear);
  expect(content.comparisonText, 'New first-clear result');
  expect(content.saveText, 'Saving result…');
  expect(content.moduleIds, [RunModuleId.heavyCaliber]);
  expect(content.emptyModulesText, isNull);
});

test('projects medal improvement from isBetterThan result', () {
  final content = projectVictoryReport(
    snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 20),
    result: const StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    ),
    priorSavedResult: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    saveState: MissionSaveState.saved,
  );

  expect(content.comparison, MissionResultComparison.medalImproved);
  expect(content.comparisonText, 'Medal improved: Silver → Gold');
  expect(content.saveText, 'Saved.');
});

test('projects same-medal base-health improvement', () {
  final content = projectVictoryReport(
    snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 17),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 17,
    ),
    priorSavedResult: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    saveState: MissionSaveState.saved,
  );

  expect(content.comparison, MissionResultComparison.baseHealthImproved);
  expect(content.comparisonText, 'Base health improved: 14 → 17');
});

test('projects retained best without implying a new write', () {
  final content = projectVictoryReport(
    snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 14),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    priorSavedResult: const StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    ),
    saveState: MissionSaveState.saved,
  );

  expect(content.comparison, MissionResultComparison.retained);
  expect(content.comparisonText, 'Saved best retained: Gold • 20 base health');
  expect(content.saveText, 'Best result already saved.');
});

test('projects failed save copy', () {
  final content = projectVictoryReport(
    snapshot: terminalSnapshot(phase: GamePhase.won),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    priorSavedResult: null,
    saveState: MissionSaveState.failed,
  );

  expect(content.saveText, 'Save failed — progress unchanged.');
  expect(
    content.nextOpportunityText,
    'Retry saving, or return without keeping this result.',
  );
});

test('projects loss without save state', () {
  final content = projectLossReport(
    snapshot: terminalSnapshot(
      phase: GamePhase.lost,
      baseHealth: 0,
      waveNumber: 5,
    ),
  );

  expect(content.didWin, isFalse);
  expect(content.outcomeText, 'Reached Wave 5/8');
  expect(content.saveState, isNull);
  expect(content.comparison, isNull);
});

test('projects empty module copy for victory and loss', () {
  final victory = projectVictoryReport(
    snapshot: terminalSnapshot(phase: GamePhase.won),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    priorSavedResult: null,
    saveState: MissionSaveState.saving,
  );
  final loss = projectLossReport(
    snapshot: terminalSnapshot(phase: GamePhase.lost, baseHealth: 0),
  );

  expect(victory.moduleIds, isEmpty);
  expect(loss.moduleIds, isEmpty);
  expect(victory.emptyModulesText, 'No Salvage Modules acquired');
  expect(loss.emptyModulesText, 'No Salvage Modules acquired');
});

test('passes optional reward fact through unchanged', () {
  const reward = MissionRewardFact(
    title: 'Blueprint recovered',
    detail: 'Heavy Caliber Mk II',
  );
  final content = projectVictoryReport(
    snapshot: terminalSnapshot(phase: GamePhase.won),
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    priorSavedResult: null,
    saveState: MissionSaveState.saved,
    reward: reward,
  );

  expect(content.reward, same(reward));
});
```

- [ ] **Step 2: Verify red**

```bash
flutter test test/game/mission_report_content_test.dart
```

Expected: compile failure because the projection types/functions do not exist.

- [ ] **Step 3: Implement the DTO and typed projections**

Create `lib/game/ui/mission_report_content.dart` with the exact model from the design spec. Implement comparison as:

```dart
MissionResultComparison _compareResult(
  StageResult result,
  StageResult? prior,
) {
  if (prior == null) return MissionResultComparison.firstClear;
  if (!result.isBetterThan(prior)) return MissionResultComparison.retained;
  if (result.medal.rank > prior.medal.rank) {
    return MissionResultComparison.medalImproved;
  }
  return MissionResultComparison.baseHealthImproved;
}
```

Do not duplicate `isBetterThan` with manual medal/base-health conditions.

Map modules by copying IDs only:

```dart
final moduleIds = List<RunModuleId>.unmodifiable(
  snapshot.acquiredRunModules,
);
final emptyModulesText = moduleIds.isEmpty
    ? 'No Salvage Modules acquired'
    : null;
```

Do not call `runModuleDefinition` in this projection.

- [ ] **Step 4: Verify green**

```bash
flutter test test/game/mission_report_content_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/mission_report_content.dart test/game/mission_report_content_test.dart
git commit -m "feat: add mission report projection"
```

---

## Task 2: Add the compact Mission Report panel

**Files:**
- Create: `lib/game/ui/mission_report_panel.dart`
- Create: `test/widget/mission_report_panel_test.dart`

**Interfaces:**
- Consumes `MissionReportContent` from Task 1.
- Reuses `AcquiredRunModuleStrip` from `lib/game/ui/run_module_draft_panel.dart`.
- Produces disabled/enabled action callbacks only; no gameplay/persistence logic.

- [ ] **Step 1: Write failing widget tests**

At minimum cover these states at 360×640:

```dart
setUp(() {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
});
```

Use `MissionReportPanel` fixtures for:

1. saving victory — visible `Saving result…`; Replay/World Map disabled;
2. saved victory — Replay/World Map enabled;
3. failed victory — Retry Save + World Map (Unsaved), no Replay;
4. loss — Retry + World Map;
5. module IDs — `AcquiredRunModuleStrip` renders `Heavy Caliber` plus its existing effect text;
6. empty modules — `No Salvage Modules acquired`;
7. optional reward fact — title/detail visible;
8. no overflow at 360×640 with three module IDs.

For disabled button inspection, do not cast `find.byTooltip` directly. Use the repository's established descendant pattern:

```dart
final mapButton = tester.widget<IconButton>(
  find.descendant(
    of: find.byTooltip('World Map'),
    matching: find.byType(IconButton),
  ),
);
expect(mapButton.onPressed, isNull);
```

- [ ] **Step 2: Verify red**

```bash
flutter test test/widget/mission_report_panel_test.dart
```

Expected: compile failure because `MissionReportPanel` does not exist.

- [ ] **Step 3: Implement the panel**

Create the full-screen overlay with:

```text
SafeArea
└── Padding
    └── Column
        ├── Expanded(SingleChildScrollView(report body))
        └── fixed action area
```

Module section:

```dart
if (content.moduleIds.isNotEmpty)
  AcquiredRunModuleStrip(moduleIds: content.moduleIds)
else
  Text(content.emptyModulesText!);
```

Do not create a second module chip/label renderer.

Action matrix must exactly match the design spec.

- [ ] **Step 4: Verify green**

```bash
flutter test test/widget/mission_report_panel_test.dart
```

Expected: PASS and no layout exceptions.

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/mission_report_panel.dart test/widget/mission_report_panel_test.dart
git commit -m "feat: add mission report panel"
```

---

## Task 3: Integrate the report and migrate the persistence tests in one green change

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Extends `_persistSave(...)` with optional `rollback`, `onCommitted`, `onFailed`.
- Adds `_missionPriorResult`, `_missionVictoryResult`, `_missionStageId`, `_missionSaveState`.
- Adds `_handleStageWon`, `_saveMissionResult`, `_restartFromMissionReport`, `_returnFromMissionReport`, `_setMissionSaveState`.
- Removes `_saveStageCompletion` and `_EndStatePanel`.

### Task 3A: Extend `_persistSave` instead of cloning it

- [ ] **Step 1: Add focused persistence-hook tests before changing production code**

Use existing `_TestCampaignProgressStore` to prove:

- a caller with no optimistic `nextProgress` leaves visible progress unchanged until commit;
- `onCommitted` receives the committed payload;
- `onFailed` fires on save failure without generic stage feedback;
- existing tech-tree purchase rollback/breadcrumb tests remain unchanged and green.

- [ ] **Step 2: Update `_persistSave` signature**

```dart
Future<void> _persistSave({
  CampaignProgress? nextProgress,
  CampaignTechTree? nextTechTree,
  required CampaignSave Function(CampaignSave committed) buildSave,
  VoidCallback? rollback,
  ValueChanged<CampaignSave>? onCommitted,
  VoidCallback? onFailed,
}) async {
```

Required behavior:

```dart
final store = _store;
if (store == null) {
  if (onFailed != null) {
    onFailed();
  } else {
    _showCampaignPersistenceFailure();
  }
  return;
}
```

Inside queued task after successful save and generation check:

```dart
_committedProgress = payload.progress;
_committedTechTree = payload.techTree;
onCommitted?.call(payload);
```

On caught failure while generation still matches:

```dart
rollback?.call();
if (onFailed != null) {
  onFailed();
} else if (mounted) {
  _showCampaignPersistenceFailure();
}
```

For stale generation, preserve current generic behavior when no callback is supplied; when mission `onFailed` is supplied, invoke it so the report does not stay `Saving…`.

Do not add a second helper/queue/controller.

### Task 3B: Add page-owned Mission Report state

- [ ] **Step 3: Add/reset four fields at stage start**

```dart
StageResult? _missionPriorResult;
StageResult? _missionVictoryResult;
String? _missionStageId;
MissionSaveState? _missionSaveState;
```

At `_startStage(stage)`:

```dart
_missionPriorResult = _progress.resultFor(stage.id);
_missionVictoryResult = null;
_missionStageId = stage.id;
_missionSaveState = null;
```

`_missionStageId` is mission-scoped: it identifies the currently running stage and stays valid across `restart()` of the same stage. It is set once here and re-confirmed in `_handleStageWon`; it is NOT cleared on replay. Clearing it crashed loss → Retry → loss → Retry because a loss never invokes `_handleStageWon` (the only other re-setter besides `_startStage`), so the second retry hit the `_missionStageId!` null check in `_restartFromMissionReport`.

Construct game with:

```dart
onStageWon: _handleStageWon,
onReturnToMap: _returnFromMissionReport,
```

Do not add `_pendingMissionProgress` or `_missionExitStarted`.

- [ ] **Step 4: Add `_handleStageWon` using the frozen stage ID/result**

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

Do not derive the saved stage ID from `_game.stage.id` later.

- [ ] **Step 5: Add non-optimistic `_saveMissionResult` through `_persistSave`**

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

`_persistSave` still owns queue/generation/pending counters. Mission code owns only the report state transition and visible commit publication.

- [ ] **Step 6: Add disposal-safe state helper**

```dart
void _setMissionSaveState(MissionSaveState state) {
  _missionSaveState = state;
  if (mounted) {
    setState(() {});
  }
}
```

No `setState` after dispose.

### Task 3C: Render only complete terminal inputs and close exits

- [ ] **Step 7: Replace `_EndStatePanel` in the stage Stack**

For loss:

```dart
if (snapshot.phase == GamePhase.lost)
  MissionReportPanel(
    content: projectLossReport(snapshot: snapshot),
    onReplay: _restartFromMissionReport,
    onReturnToMap: _returnFromMissionReport,
  );
```

For victory, only render once both frozen values exist:

```dart
if (snapshot.phase == GamePhase.won &&
    _missionVictoryResult != null &&
    _missionSaveState != null)
  MissionReportPanel(
    content: projectVictoryReport(
      snapshot: snapshot,
      result: _missionVictoryResult!,
      priorSavedResult: _missionPriorResult,
      saveState: _missionSaveState!,
      reward: null,
    ),
    onReplay: _missionSaveState == MissionSaveState.saved
        ? _restartFromMissionReport
        : null,
    onReturnToMap: _missionSaveState == MissionSaveState.saving
        ? null
        : _returnFromMissionReport,
    onRetrySave: _missionSaveState == MissionSaveState.failed
        ? _saveMissionResult
        : null,
  );
```

No snapshot-only saving fallback.

- [ ] **Step 8: Make the underlying World Map control build-only**

Change `_BottomControls`:

```dart
onPressed: snapshot.phase == GamePhase.build ? game.returnToMap : null,
```

- [ ] **Step 9: Centralize return guard**

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

No one-shot flag.

- [ ] **Step 10: Add replay guard/reset**

Victory retry is allowed only after saved; loss retry is immediate. Refresh the prior result from committed `_progress` before restarting:

```dart
void _restartFromMissionReport() {
  final game = _game;
  if (game == null) return;

  final snapshot = game.snapshot;
  if (snapshot.phase == GamePhase.won &&
      _missionSaveState != MissionSaveState.saved) {
    return;
  }

  _missionPriorResult = _progress.resultFor(_missionStageId!);
  _missionVictoryResult = null;
  // _missionStageId is mission-scoped, not per-attempt. Do NOT clear it here.
  // Clearing it broke loss → Retry → loss → Retry: a loss never calls
  // _handleStageWon (the only other re-setter besides _startStage), so the
  // second retry hit the `_missionStageId!` null check above.
  _missionSaveState = null;
  game.restart();
}
```

### Task 3D: Migrate every old stage-save fixture before committing

- [ ] **Step 11: Enumerate all old synthetic stage-completion calls**

Run:

```bash
grep -n "onStageWon.*call" test/widget_test.dart
```

Classify every result. Do not rely on the previous plan's partial list.

Delete/rewrite tests whose only behavior is intentionally removed:

- optimistic stage clear visible before commit;
- multiple sibling stage completions emitted from one active mission;
- two same-stage completions from one active mission;
- optimistic stage-result rollback interactions.

Preserve the underlying generic writer invariants by re-plumbing them through tech-tree purchase saves where appropriate:

- `blocks stage launch while a stage-completion save is in flight` → delay a tech-tree purchase save and assert stage launch is blocked;
- `persists queued stage save even if page is disposed before it runs` → queue tech-tree persistence and dispose;
- `queued save after disposal keeps earlier queued result in store` → use two affordable tech-tree purchases from a fixture with sufficient medal points;
- `failed queued save after disposal does not call setState on a defunct State` → delayed failing tech-tree save;
- `failed reset retains progress after a pending save drains` → pending tech-tree save then reset failure;
- `successful reset after a pending save drains wipes the store` → pending tech-tree save then successful reset.

Keep Mission Report-specific replacements:

- null store → victory report becomes `failed`, no throw;
- retained replay → zero save calls;
- improving victory → one save call;
- direct `game.returnToMap()` while saving → still on report.

- [ ] **Step 12: Add shared synthetic-victory helper**

Any page test that manually injects `GamePhase.won` must also emit a matching completion through one helper so tests cannot recreate the removed stuck-saving fixture:

```dart
Future<void> publishVictory(
  WidgetTester tester,
  OrionDefenseGame game, {
  required StageResult result,
}) async {
  final snapshot = game.stateNotifier.value;
  game.stateNotifier.value = GameSnapshot(
    phase: GamePhase.won,
    gold: snapshot.gold,
    baseHealth: result.bestBaseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
    waveNumber: snapshot.waveTotal,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    stageModifiers: snapshot.stageModifiers,
    nextWavePreview: null,
    selectedCell: null,
    selectedTower: null,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    acquiredRunModules: snapshot.acquiredRunModules,
  );
  game.onStageWon?.call(StageCompletion(stage: game.stage, result: result));
  await tester.pump();
}
```

- [ ] **Step 13: Add/replace Mission Report integration tests**

Cover at minimum:

1. improving victory immediately shows `Saving result…` and store progress is unchanged while delayed;
2. save success shows `Saved.` and commits progress;
3. save failure shows `Save failed — progress unchanged.`;
4. Retry Save creates one new save and can succeed;
5. retained replay result uses zero writes and shows `Best result already saved.`;
6. loss uses zero writes;
7. null store becomes failed without throwing;
8. `game.returnToMap()` during saving does not leave the report;
9. failed report World Map sets `Mission result was not saved.` and committed progress is unchanged;
10. delayed failure after page disposal produces no `setState()` exception.

Use the corrected World Map button finder from Task 2 when inspecting disabled state.

- [ ] **Step 14: Run focused tests**

```bash
flutter test test/game/mission_report_content_test.dart
flutter test test/widget/mission_report_panel_test.dart
flutter test test/widget_test.dart --plain-name "Mission"
flutter test test/widget_test.dart --plain-name "save"
```

Expected: PASS.

- [ ] **Step 15: Run the full suite before the Task 3 commit**

```bash
flutter test
```

Expected: PASS. Do not commit Task 3 with the known old `onStageWon` fixtures still red.

- [ ] **Step 16: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: integrate mission report save flow"
```

---

## Task 4: Add cross-writer regression and final verification

**Files:**
- Modify: `test/widget_test.dart`
- Modify only if needed for discovered compile/test issues: files already touched in Tasks 1–3.

- [ ] **Step 1: Add mission-save → tech-tree-purchase regression**

Use a progress fixture that has enough medal rank to purchase an affordable tech upgrade after the mission save.

Flow:

1. start a stage;
2. publish an improving victory and complete its delayed save;
3. return to the map;
4. open Tech Tree;
5. purchase one upgrade and complete that save;
6. assert the store contains both the new stage result and purchased upgrade.

The final assertions must check both fields from the store:

```dart
expect(store.progress.resultFor('outpost-alpha'), expectedResult);
expect(
  store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
  isTrue,
);
```

This proves `_persistSave` remains one writer and the later tech-tree payload composes from the mission-advanced committed baseline.

- [ ] **Step 2: Add rapid Retry Save single-flight regression**

After first failure, tap `Retry Save` twice before the delayed retry completes. Assert only one additional save was queued:

```dart
expect(store.saveCalls, 2); // original attempt + one retry
```

- [ ] **Step 3: Verify no obsolete synthetic multi-completion fixtures remain**

```bash
grep -n "onStageWon.*call" test/widget_test.dart
```

Every remaining call must be either the shared victory helper or an intentional single completion for the currently running stage. Remove any leftover impossible sibling/same-run multi-completion fixture.

- [ ] **Step 4: Format**

```bash
dart format .
dart format --output=none --set-exit-if-changed .
```

Expected: second command exits 0 with no changes.

- [ ] **Step 5: Analyze**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 6: Run focused tests**

```bash
flutter test test/game/mission_report_content_test.dart
flutter test test/widget/mission_report_panel_test.dart
flutter test test/widget_test.dart --plain-name "mission save"
flutter test test/widget_test.dart --plain-name "Mission"
```

Expected: PASS.

- [ ] **Step 7: Run full suite**

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 8: Human 360×640 check**

At logical 360×640 verify:

- Victory Saving: result/module/save copy readable; Replay/World Map disabled.
- Victory Saved: actions reachable without hidden overflow.
- Victory Failed: Retry Save and World Map (Unsaved) visible.
- Loss: Retry and World Map visible.
- Three acquired modules reuse the same title + effect presentation as the in-run strip.

- [ ] **Step 9: Commit final test/verification adjustments**

```bash
git add test/widget_test.dart lib/game/ui/mission_report_content.dart lib/game/ui/mission_report_panel.dart lib/game/ui/orion_game_page.dart
git commit -m "test: verify mission report persistence flow"
```

---

## Self-review checklist

Before implementation starts, confirm the plan still satisfies:

- one writer implementation: `_persistSave` owns queue/generation/pending/committed mechanics;
- mission persistence is non-optimistic and has no rollback tree;
- frozen stage ID/result are shared by report and persistence;
- typed victory/loss projections have no release-only assertion contract;
- `StageResult.isBetterThan` is the improvement source of truth;
- existing `AcquiredRunModuleStrip` renders module details;
- no `_pendingMissionProgress` / `_missionExitStarted`;
- `MissionRewardFact` stays optional/null for HPA-525 and exists only because HPA-528 already depends on the slot;
- all old `onStageWon` test fixtures are explicitly classified before Task 3 commits;
- Task 3 full suite is green before commit;
- process-kill-during-save risk remains documented, not 'fixed' with optimistic state or durable recovery;
- no new package/schema/controller/event bus/reward framework is introduced.
