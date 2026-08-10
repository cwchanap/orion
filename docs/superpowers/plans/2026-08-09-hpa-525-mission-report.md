# HPA-525 Mission Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Orion's minimal terminal panel with a compact Mission Report whose result comparison, Salvage Module summary, save truth, and next actions stay honest through queued save success, failure, retry, and navigation.

**Architecture:** Keep `GameSession` and `OrionDefenseGame` as the source of terminal mission facts, add one Flutter-free report projection plus one report widget, and let `OrionGamePage` own explicit Mission Report state. Stage-result persistence becomes non-optimistic but still uses the existing `_saveQueue`, generation, busy counter, and committed campaign baseline so Orion keeps one serial campaign writer.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- HPA-527 is the gameplay baseline; do not change Salvage Module offer/effect rules.
- Do not add a new `GamePhase` or report phase to `GameSession`.
- Do not add RunStats, analytics, coaching, evidence export, run history, mid-run persistence, or a generic reward framework.
- Do not route stage completion through the optimistic mutation/rollback behavior of `_persistSave`.
- Do not call `store.save` on an independent chain; mission writes must enqueue on the existing `_saveQueue`.
- Build mission-save payloads from `_committedProgress` / `_committedTechTree` inside the queued task.
- Capture `_progressGeneration`, reuse `_pendingSaves` / `_isSavingProgress`, and call `_decrementPendingSaves()` in `finally`.
- Do not optimistically update `_progress` for an improving victory.
- A retained replay result performs no storage write and is immediately treated as already saved.
- Victory save states are exactly `saving`, `saved`, and `failed`; loss has no save state.
- Freeze the victory `StageCompletion.result`; projection and persistence use that same `StageResult`.
- Do not use `snapshot.phase == won && _missionSaveState == null` as an implicit forever-`saving` fallback.
- Save failure leaves campaign progress unchanged; no stage-result rollback callback/tree is needed.
- While victory saving is in flight, every terminal exit route is blocked: report buttons, bottom World Map control, `game.returnToMap()`, and `_returnToMap()`.
- Failed victory exposes `Retry Save` and `World Map (Unsaved)`; do not expose Replay until the result is saved or explicitly abandoned.
- Use one `_missionExitStarted` one-shot guard for terminal world-map navigation.
- Use `StageResult.isBetterThan` as the source of truth for whether a result improved.
- Projection owns `No Salvage Modules acquired`; widgets do not duplicate that string.
- Keep HPA-528 integration to one optional `MissionRewardFact`; HPA-525 always supplies `null`.
- Keep existing tech-tree/reset persistence behavior unchanged except for sharing the same queue/committed baseline with the new mission writer.
- Do not edit the save codec for this ticket. If implementation unexpectedly must edit it, remove obsolete v1/v2 development-save decoder branches rather than extending them.
- Target 360×640 logical pixels; the report body may scroll but primary actions remain reachable.
- Save meaning must use text/icon and cannot rely on color alone.
- Process kill during `Saving…` may lose the run result; do not hide that residual risk by reintroducing optimistic campaign progress or durable recovery scope.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and full `flutter test`.

## File Map

### Create

- `lib/game/ui/mission_report_content.dart` — immutable report presentation model and pure projection.
- `lib/game/ui/mission_report_panel.dart` — compact scrollable Mission Report overlay with fixed reachable actions.
- `test/game/mission_report_content_test.dart` — pure projection coverage.
- `test/widget/mission_report_panel_test.dart` — 360×640 presentation/action coverage.

### Modify

- `lib/game/ui/orion_game_page.dart` — freeze prior/result state, render Mission Report, queue a non-optimistic result save on the existing writer, close terminal exit paths, and remove `_EndStatePanel`.
- `test/widget_test.dart` — page-level save success/failure/retry/no-op/loss/exit/writer-coexistence coverage and removal of obsolete optimistic stage-save tests.

No production change is required in `GameSession`, `OrionDefenseGame`, `CampaignProgress`, or `CampaignProgressStore` for the intended design.

---

### Task 1: Add the pure Mission Report presentation model

**Files:**
- Create: `lib/game/ui/mission_report_content.dart`
- Create: `test/game/mission_report_content_test.dart`

**Interfaces:**
- Consumes: `GameSnapshot`, frozen victory `StageResult`, prior saved `StageResult`, `RunModuleId`, `runModuleDefinition`.
- Produces: `MissionSaveState`, `MissionResultComparison`, `MissionModuleFact`, `MissionRewardFact`, `MissionReportContent`, `projectMissionReport(...)`.
- Later tasks render only `MissionReportContent`; they do not derive comparison/module/save copy.

- [ ] **Step 1: Write the failing projection tests**

Create `test/game/mission_report_content_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_report_content.dart';

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

void main() {
  test('projects first clear without claiming commitment', () {
    const result = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    final content = projectMissionReport(
      snapshot: terminalSnapshot(
        phase: GamePhase.won,
        modules: const [
          RunModuleId.heavyCaliber,
          RunModuleId.emergencySalvage,
        ],
      ),
      victoryResult: result,
      priorSavedResult: null,
      saveState: MissionSaveState.saving,
    );

    expect(content.didWin, isTrue);
    expect(content.result, result);
    expect(content.outcomeText, 'Silver medal • Base 14/20');
    expect(content.comparison, MissionResultComparison.firstClear);
    expect(content.comparisonText, 'New first-clear result');
    expect(content.saveText, 'Saving result…');
    expect(
      content.modules.map((module) => module.title),
      ['Heavy Caliber', 'Emergency Salvage'],
    );
    expect(content.emptyModulesText, isNull);
  });

  test('uses existing improvement rule before choosing improvement copy', () {
    const prior = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    const medalImproved = StageResult(
      medal: StageMedal.gold,
      bestBaseHealth: 20,
    );
    const healthImproved = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 17,
    );
    const retained = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 12,
    );

    expect(medalImproved.isBetterThan(prior), isTrue);
    expect(healthImproved.isBetterThan(prior), isTrue);
    expect(retained.isBetterThan(prior), isFalse);

    expect(
      projectMissionReport(
        snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 20),
        victoryResult: medalImproved,
        priorSavedResult: prior,
        saveState: MissionSaveState.saved,
      ).comparison,
      MissionResultComparison.medalImproved,
    );
    expect(
      projectMissionReport(
        snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 17),
        victoryResult: healthImproved,
        priorSavedResult: prior,
        saveState: MissionSaveState.saved,
      ).comparison,
      MissionResultComparison.baseHealthImproved,
    );
    expect(
      projectMissionReport(
        snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 12),
        victoryResult: retained,
        priorSavedResult: prior,
        saveState: MissionSaveState.saved,
      ).comparison,
      MissionResultComparison.retained,
    );
  });

  test('projects failed save without changing the run result', () {
    const result = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      victoryResult: result,
      priorSavedResult: null,
      saveState: MissionSaveState.failed,
    );

    expect(content.result, result);
    expect(content.comparisonText, 'New first-clear result');
    expect(content.saveText, 'Save failed — progress unchanged.');
    expect(
      content.nextOpportunityText,
      'Retry saving, or return without keeping this result.',
    );
  });

  test('projects loss with reached wave and no save state', () {
    final content = projectMissionReport(
      snapshot: terminalSnapshot(
        phase: GamePhase.lost,
        baseHealth: 0,
        waveNumber: 5,
      ),
      victoryResult: null,
      priorSavedResult: null,
      saveState: null,
    );

    expect(content.didWin, isFalse);
    expect(content.outcomeText, 'Reached Wave 5/8');
    expect(content.result, isNull);
    expect(content.comparison, isNull);
    expect(content.saveState, isNull);
    expect(content.saveText, isNull);
  });

  test('projection owns empty module copy for victory and loss', () {
    const result = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    final victory = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      victoryResult: result,
      priorSavedResult: null,
      saveState: MissionSaveState.saved,
    );
    final loss = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.lost, baseHealth: 0),
      victoryResult: null,
      priorSavedResult: null,
      saveState: null,
    );

    expect(victory.modules, isEmpty);
    expect(victory.emptyModulesText, 'No Salvage Modules acquired');
    expect(loss.modules, isEmpty);
    expect(loss.emptyModulesText, 'No Salvage Modules acquired');
  });

  test('passes one optional typed reward fact through unchanged', () {
    const reward = MissionRewardFact(
      title: 'Blueprint recovered',
      detail: 'Heavy Caliber Mk II',
    );
    const result = StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    );
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      victoryResult: result,
      priorSavedResult: null,
      saveState: MissionSaveState.saved,
      reward: reward,
    );

    expect(content.reward, same(reward));
  });
}
```

- [ ] **Step 2: Run the new projection test and verify red**

Run:

```bash
flutter test test/game/mission_report_content_test.dart
```

Expected: compile failure because `mission_report_content.dart` and its types do not exist.

- [ ] **Step 3: Implement the immutable types and projection**

Create `lib/game/ui/mission_report_content.dart`:

```dart
import '../campaign/campaign_progress.dart';
import '../models/game_models.dart';

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

MissionReportContent projectMissionReport({
  required GameSnapshot snapshot,
  required StageResult? victoryResult,
  required StageResult? priorSavedResult,
  required MissionSaveState? saveState,
  MissionRewardFact? reward,
}) {
  final modules = snapshot.acquiredRunModules
      .map(
        (id) => MissionModuleFact(
          id: id,
          title: runModuleDefinition(id).title,
        ),
      )
      .toList(growable: false);
  final emptyModulesText = modules.isEmpty
      ? 'No Salvage Modules acquired'
      : null;

  if (snapshot.phase != GamePhase.won) {
    return MissionReportContent(
      stageId: snapshot.stageId,
      stageName: snapshot.stageName,
      didWin: false,
      waveNumber: snapshot.waveNumber,
      waveTotal: snapshot.waveTotal,
      remainingBaseHealth: snapshot.baseHealth,
      startingBaseHealth: snapshot.startingBaseHealth,
      outcomeText: 'Reached Wave ${snapshot.waveNumber}/${snapshot.waveTotal}',
      modules: modules,
      emptyModulesText: emptyModulesText,
      reward: reward,
      nextOpportunityText: 'Adjust your build and retry when ready.',
    );
  }

  assert(victoryResult != null, 'Victory report requires StageCompletion.result.');
  assert(saveState != null, 'Victory report requires an explicit save state.');
  final result = victoryResult!;
  final comparison = _comparison(result, priorSavedResult);

  return MissionReportContent(
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    didWin: true,
    waveNumber: snapshot.waveNumber,
    waveTotal: snapshot.waveTotal,
    remainingBaseHealth: result.bestBaseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
    result: result,
    priorSavedResult: priorSavedResult,
    comparison: comparison,
    outcomeText:
        '${result.medal.label} medal • Base ${result.bestBaseHealth}/${snapshot.startingBaseHealth}',
    comparisonText: _comparisonText(
      comparison,
      result: result,
      priorSavedResult: priorSavedResult,
    ),
    modules: modules,
    emptyModulesText: emptyModulesText,
    saveState: saveState,
    saveText: _saveText(saveState!, comparison),
    reward: reward,
    nextOpportunityText: _nextOpportunityText(saveState),
  );
}

MissionResultComparison _comparison(
  StageResult result,
  StageResult? priorSavedResult,
) {
  if (priorSavedResult == null) {
    return MissionResultComparison.firstClear;
  }
  if (!result.isBetterThan(priorSavedResult)) {
    return MissionResultComparison.retained;
  }
  if (result.medal.rank > priorSavedResult.medal.rank) {
    return MissionResultComparison.medalImproved;
  }
  return MissionResultComparison.baseHealthImproved;
}

String _comparisonText(
  MissionResultComparison comparison, {
  required StageResult result,
  required StageResult? priorSavedResult,
}) {
  return switch (comparison) {
    MissionResultComparison.firstClear => 'New first-clear result',
    MissionResultComparison.medalImproved =>
      'Medal improved: ${priorSavedResult!.medal.label} → ${result.medal.label}',
    MissionResultComparison.baseHealthImproved =>
      'Base health improved: ${priorSavedResult!.bestBaseHealth} → ${result.bestBaseHealth}',
    MissionResultComparison.retained =>
      'Saved best retained: ${priorSavedResult!.medal.label} • '
          '${priorSavedResult.bestBaseHealth} base health',
  };
}

String _saveText(
  MissionSaveState state,
  MissionResultComparison comparison,
) {
  return switch (state) {
    MissionSaveState.saving => 'Saving result…',
    MissionSaveState.saved
        when comparison == MissionResultComparison.retained =>
      'Best result already saved.',
    MissionSaveState.saved => 'Saved.',
    MissionSaveState.failed => 'Save failed — progress unchanged.',
  };
}

String _nextOpportunityText(MissionSaveState state) {
  return switch (state) {
    MissionSaveState.saving =>
      'Saving must finish before you replay or leave.',
    MissionSaveState.saved =>
      'Replay for a better result or continue on the World Map.',
    MissionSaveState.failed =>
      'Retry saving, or return without keeping this result.',
  };
}
```

- [ ] **Step 4: Run the projection tests and verify green**

Run:

```bash
flutter test test/game/mission_report_content_test.dart
```

Expected: all Mission Report projection tests pass.

- [ ] **Step 5: Commit the pure projection**

```bash
git add lib/game/ui/mission_report_content.dart test/game/mission_report_content_test.dart
git commit -m "feat: add mission report projection"
```

---

### Task 2: Add the compact Mission Report panel

**Files:**
- Create: `lib/game/ui/mission_report_panel.dart`
- Create: `test/widget/mission_report_panel_test.dart`

**Interfaces:**
- Consumes: `MissionReportContent`, `MissionSaveState` from Task 1.
- Produces: `MissionReportPanel(content:, onReplay:, onReturnToMap:, onRetrySave:)`.
- The panel owns layout/action labels only; it does not derive persistence truth or comparison copy.

- [ ] **Step 1: Write failing 360×640 widget tests**

Create `test/widget/mission_report_panel_test.dart` with a helper:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import 'package:orion/game/ui/mission_report_panel.dart';

MissionReportContent victoryContent(MissionSaveState state) {
  return MissionReportContent(
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    didWin: true,
    waveNumber: 8,
    waveTotal: 8,
    remainingBaseHealth: 14,
    startingBaseHealth: 20,
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
    comparison: MissionResultComparison.firstClear,
    outcomeText: 'Silver medal • Base 14/20',
    comparisonText: 'New first-clear result',
    modules: const [],
    emptyModulesText: 'No Salvage Modules acquired',
    saveState: state,
    saveText: switch (state) {
      MissionSaveState.saving => 'Saving result…',
      MissionSaveState.saved => 'Saved.',
      MissionSaveState.failed => 'Save failed — progress unchanged.',
    },
    nextOpportunityText: switch (state) {
      MissionSaveState.saving =>
        'Saving must finish before you replay or leave.',
      MissionSaveState.saved =>
        'Replay for a better result or continue on the World Map.',
      MissionSaveState.failed =>
        'Retry saving, or return without keeping this result.',
    },
  );
}

Future<void> pumpReport(
  WidgetTester tester,
  MissionReportContent content, {
  VoidCallback? onReplay,
  VoidCallback? onMap,
  VoidCallback? onRetrySave,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MissionReportPanel(
          content: content,
          onReplay: onReplay,
          onReturnToMap: onMap,
          onRetrySave: onRetrySave,
        ),
      ),
    ),
  );
}
```

Add tests that assert:

```dart
testWidgets('saving victory disables replay and map at 360x640', (tester) async {
  await pumpReport(tester, victoryContent(MissionSaveState.saving));

  expect(find.text('Victory'), findsOneWidget);
  expect(find.text('Saving result…'), findsOneWidget);
  expect(find.text('No Salvage Modules acquired'), findsOneWidget);
  expect(tester.takeException(), isNull);

  final replay = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Replay Mission'),
  );
  final map = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'World Map'),
  );
  expect(replay.onPressed, isNull);
  expect(map.onPressed, isNull);
});

testWidgets('failed victory exposes retry save and unsaved map', (tester) async {
  var retries = 0;
  var exits = 0;
  await pumpReport(
    tester,
    victoryContent(MissionSaveState.failed),
    onRetrySave: () => retries++,
    onMap: () => exits++,
  );

  await tester.tap(find.text('Retry Save'));
  await tester.tap(find.text('World Map (Unsaved)'));
  expect(retries, 1);
  expect(exits, 1);
});
```

Also add saved-victory and loss action tests. Build loss content directly with `didWin: false`, `outcomeText: 'Reached Wave 5/8'`, no save fields, and assert `Retry` + `World Map` are enabled.

- [ ] **Step 2: Run the widget test and verify red**

Run:

```bash
flutter test test/widget/mission_report_panel_test.dart
```

Expected: compile failure because `MissionReportPanel` does not exist.

- [ ] **Step 3: Implement the panel**

Create `lib/game/ui/mission_report_panel.dart`:

```dart
import 'package:flutter/material.dart';

import 'mission_report_content.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.scrim.withValues(alpha: 0.72),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            content.didWin
                                ? Icons.emoji_events
                                : Icons.warning_amber,
                            size: 40,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            content.didWin ? 'Victory' : 'Mission Failed',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            content.stageName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(content.outcomeText),
                          if (content.comparisonText case final comparison?) ...[
                            const SizedBox(height: 6),
                            Text(comparison),
                          ],
                          const SizedBox(height: 16),
                          Text('Salvage Modules', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          if (content.modules.isEmpty)
                            Text(content.emptyModulesText!)
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final module in content.modules)
                                  Chip(label: Text(module.title)),
                              ],
                            ),
                          if (content.saveText case final saveText?) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(_saveIcon(content.saveState!)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(saveText)),
                              ],
                            ),
                          ],
                          if (content.reward case final reward?) ...[
                            const SizedBox(height: 16),
                            Text(reward.title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(reward.detail),
                          ],
                          const SizedBox(height: 16),
                          Text(content.nextOpportunityText),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    if (!content.didWin) {
      return Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: onReplay,
              child: const Text('Retry'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              onPressed: onReturnToMap,
              child: const Text('World Map'),
            ),
          ),
        ],
      );
    }

    if (content.saveState == MissionSaveState.failed) {
      return Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: onRetrySave,
              child: const Text('Retry Save'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              onPressed: onReturnToMap,
              child: const Text('World Map (Unsaved)'),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: onReplay,
            child: const Text('Replay Mission'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonal(
            onPressed: onReturnToMap,
            child: const Text('World Map'),
          ),
        ),
      ],
    );
  }
}

IconData _saveIcon(MissionSaveState state) => switch (state) {
  MissionSaveState.saving => Icons.sync,
  MissionSaveState.saved => Icons.check_circle_outline,
  MissionSaveState.failed => Icons.error_outline,
};
```

The page passes null callbacks while saving, so the standard victory action row renders disabled buttons.

- [ ] **Step 4: Run the widget tests and verify green**

```bash
flutter test test/widget/mission_report_panel_test.dart
```

Expected: all Mission Report widget tests pass at 360×640 with no overflow.

- [ ] **Step 5: Commit the panel**

```bash
git add lib/game/ui/mission_report_panel.dart test/widget/mission_report_panel_test.dart
git commit -m "feat: add mission report panel"
```

---

### Task 3: Integrate terminal result state, the shared writer, and closed exits

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 1 `projectMissionReport`, `MissionSaveState`; Task 2 `MissionReportPanel`.
- Produces: `_handleStageWon`, `_saveMissionResult`, `_restartFromMissionReport`, `_returnFromMissionReport`, `_handleGameReturnToMap`, `_setMissionSaveState`.
- Reuses: `_saveQueue`, `_progressGeneration`, `_pendingSaves`, `_setSavingProgress`, `_decrementPendingSaves`, `_committedProgress`, `_committedTechTree`.
- Keeps: `_persistSave` for existing tech-tree behavior; does not route mission result through its optimistic mutation/rollback API.

- [ ] **Step 1: Add a shared terminal-victory test helper**

Near `startStageFromBriefing` in `test/widget_test.dart`, add:

```dart
Future<void> publishVictory(
  WidgetTester tester,
  OrionDefenseGame game, {
  StageResult result = const StageResult(
    medal: StageMedal.silver,
    bestBaseHealth: 14,
  ),
  List<RunModuleId> modules = const [],
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
    acquiredRunModules: modules,
  );
  game.onStageWon?.call(StageCompletion(stage: game.stage, result: result));
  await tester.pump();
}
```

This replaces snapshot-only victory fixtures. A valid synthetic victory now supplies the same `StageResult` to the report and persistence callback.

- [ ] **Step 2: Write failing tests for saving truth and the programmatic exit bypass**

Add:

```dart
testWidgets(
  'improving victory is non-optimistic and game return is blocked while saving',
  (tester) async {
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

    await publishVictory(tester, game!);
    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);

    expect(find.text('Saving result…'), findsOneWidget);
    expect(store.progress.resultFor('outpost-alpha'), isNull);

    final bottomMap = tester.widget<IconButton>(find.byTooltip('World Map'));
    expect(bottomMap.onPressed, isNull);

    game!.returnToMap();
    await tester.pump();
    expect(find.text('Saving result…'), findsOneWidget);
    expect(find.text('Orion Sector Map'), findsNothing);
    expect(store.progress.resultFor('outpost-alpha'), isNull);

    store.saveCompletions.single.complete();
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(
      store.progress.resultFor('outpost-alpha'),
      const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
    );
  },
);
```

Run:

```bash
flutter test test/widget_test.dart --plain-name "improving victory is non-optimistic and game return is blocked while saving"
```

Expected: fail because the current end panel has no Mission Report state and `game.returnToMap()` still exits.

- [ ] **Step 3: Add page imports and Mission Report fields**

In `orion_game_page.dart`, import:

```dart
import 'mission_report_content.dart';
import 'mission_report_panel.dart';
```

Add to `_OrionGamePageState`:

```dart
StageResult? _missionPriorResult;
StageResult? _missionVictoryResult;
CampaignProgress? _pendingMissionProgress;
MissionSaveState? _missionSaveState;
bool _missionExitStarted = false;
```

Add:

```dart
void _setMissionSaveState(MissionSaveState value) {
  _missionSaveState = value;
  if (mounted) {
    setState(() {});
  }
}
```

- [ ] **Step 4: Freeze stage baseline and route callbacks through the page**

In `_startStage(stage)`, after the existing save/reset/unlock guards and before `OrionDefenseGame(...)`:

```dart
_missionPriorResult = _progress.resultFor(stage.id);
_missionVictoryResult = null;
_pendingMissionProgress = null;
_missionSaveState = null;
_missionExitStarted = false;
```

Change game callbacks to:

```dart
onStageWon: _handleStageWon,
onReturnToMap: _handleGameReturnToMap,
```

- [ ] **Step 5: Replace `_saveStageCompletion` with frozen result handling**

Delete `_saveStageCompletion` and add:

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

Do not derive another `StageResult` from `GameSnapshot` in the page or report projection.

- [ ] **Step 6: Implement the non-optimistic save on the existing writer chain**

Add:

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

      if (saveGeneration != _progressGeneration) {
        _setMissionSaveState(MissionSaveState.failed);
        return;
      }

      _committedProgress = payload.progress;
      _committedTechTree = payload.techTree;
      _progress = payload.progress;
      _setMissionSaveState(MissionSaveState.saved);
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

Important details:

- `_pendingMissionProgress` is not assigned to `_progress` before saving.
- The payload is rebuilt from `_committedProgress` inside the queued task, not written from a stale captured aggregate.
- There is no stage-result rollback callback.
- Failure updates only `_missionSaveState` plus the normal busy counter in `finally`.

- [ ] **Step 7: Render the report only from complete terminal inputs**

Inside `_buildStageScaffold`'s `ValueListenableBuilder`, compute:

```dart
final MissionReportContent? reportContent;
if (snapshot.phase == GamePhase.lost) {
  reportContent = projectMissionReport(
    snapshot: snapshot,
    victoryResult: null,
    priorSavedResult: null,
    saveState: null,
  );
} else if (snapshot.phase == GamePhase.won &&
    _missionVictoryResult != null &&
    _missionSaveState != null) {
  reportContent = projectMissionReport(
    snapshot: snapshot,
    victoryResult: _missionVictoryResult,
    priorSavedResult: _missionPriorResult,
    saveState: _missionSaveState,
  );
} else {
  reportContent = null;
}
```

Replace `_EndStatePanel` rendering with:

```dart
if (reportContent != null)
  Positioned.fill(
    child: MissionReportPanel(
      content: reportContent,
      onReplay: _missionSaveState == MissionSaveState.saving
          ? null
          : _restartFromMissionReport,
      onReturnToMap: _missionSaveState == MissionSaveState.saving
          ? null
          : _returnFromMissionReport,
      onRetrySave: _missionSaveState == MissionSaveState.failed
          ? _saveMissionResult
          : null,
    ),
  ),
```

For loss, `_missionSaveState` is null, so Retry and World Map remain enabled.

Delete `_EndStatePanel` after the Mission Report is wired.

- [ ] **Step 8: Close the terminal exit graph**

In `_BottomControls`, change the map button from “anything except wave” to build-only:

```dart
onPressed: snapshot.phase == GamePhase.build ? game.returnToMap : null,
```

Add:

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

Defensively guard `_returnToMap`:

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

Add report return:

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

Add report restart:

```dart
void _restartFromMissionReport() {
  final game = _game;
  if (game == null) {
    return;
  }
  final snapshot = game.snapshot;
  if (snapshot.phase == GamePhase.won &&
      _missionSaveState != MissionSaveState.saved) {
    return;
  }

  _missionPriorResult = _progress.resultFor(game.stage.id);
  _missionVictoryResult = null;
  _pendingMissionProgress = null;
  _missionSaveState = null;
  _missionExitStarted = false;
  game.restart();
}
```

- [ ] **Step 9: Add failing-save retry single-flight coverage**

Add:

```dart
testWidgets('failed mission save retries once and can succeed', (tester) async {
  final store = _TestCampaignProgressStore(
    delaySaves: true,
    failOnSaveIndices: {0},
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
  await startStageFromBriefing(tester);
  await publishVictory(tester, game!);

  await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
  store.saveCompletions[0].complete();
  await tester.pumpAndSettle();

  expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
  expect(store.progress.resultFor('outpost-alpha'), isNull);

  await tester.tap(find.text('Retry Save'));
  await tester.tap(find.text('Retry Save'));
  await tester.pump();
  await _pumpUntil(tester, () => store.saveCompletions.length == 2);

  expect(store.saveCalls, 2);
  store.saveCompletions[1].complete();
  await tester.pumpAndSettle();

  expect(find.text('Saved.'), findsOneWidget);
  expect(store.saveCalls, 2);
  expect(
    store.progress.resultFor('outpost-alpha'),
    const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
  );
});
```

- [ ] **Step 10: Run focused page tests**

```bash
flutter test test/widget_test.dart --plain-name "improving victory is non-optimistic and game return is blocked while saving"
flutter test test/widget_test.dart --plain-name "failed mission save retries once and can succeed"
```

Expected: both pass.

- [ ] **Step 11: Commit the page integration**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: integrate mission report save flow"
```

---

### Task 4: Replace obsolete stage-save contracts and verify writer coexistence

**Files:**
- Modify: `test/widget_test.dart`
- Modify only if needed for test-driven compile fixes: `lib/game/ui/orion_game_page.dart`

**Interfaces:**
- Consumes all Task 1–3 behavior.
- Produces final regression coverage for retained results, losses, unsaved abandonment, one-shot exit, and mission-save → tech-purchase persistence.

- [ ] **Step 1: Replace snapshot-only terminal tests with complete terminal fixtures**

The old tests `victory panel shows earned medal and base health` and `loss panel hides the environment reminder` target `_EndStatePanel`.

Replace the victory test with `publishVictory(...)` so the won snapshot and `onStageWon` callback are always paired. Assert:

```dart
expect(find.text('Victory'), findsOneWidget);
expect(find.text('Silver medal • Base 14/20'), findsOneWidget);
expect(find.text('New first-clear result'), findsOneWidget);
```

For loss, keep snapshot-only injection because loss has no persistence callback, then assert:

```dart
expect(find.text('Mission Failed'), findsOneWidget);
expect(find.textContaining('Reached Wave'), findsOneWidget);
expect(find.textContaining('Environment:'), findsNothing);
```

Do not add a `won => saving` fallback merely to preserve old snapshot-only test style.

- [ ] **Step 2: Replace obsolete optimistic stage-save tests**

Delete or rewrite tests whose contracts no longer apply:

- `optimistic stage clear is visible on map before save fails, then reverts`;
- `blocks stage launch while a stage-completion save is in flight` in its old “return to map during save” form;
- `serializes sibling stage clear saves without losing progress`;
- stage-result-specific queued-save-after-disposal tests;
- same-stage optimistic rollback tests;
- earlier/later optimistic stage save rollback composition tests.

Keep the generic tech-tree/reset writer tests. They still validate `_persistSave`, `_saveQueue`, committed payload composition, and reset serialization for the paths that retain optimistic behavior.

- [ ] **Step 3: Add retained-best no-write regression**

```dart
testWidgets('retained mission best is immediately saved without a write', (
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
  await startStageFromBriefing(tester, actionLabel: 'Replay Mission');

  await publishVictory(
    tester,
    game!,
    result: const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Best result already saved.'), findsOneWidget);
  expect(store.saveCalls, 0);
  expect(
    store.progress.resultFor('outpost-alpha'),
    const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
  );
});
```

- [ ] **Step 4: Add loss/no-save regression**

Start a mission, inject a `GameSnapshot(phase: GamePhase.lost, ...)`, pump, and assert:

```dart
expect(find.text('Mission Failed'), findsOneWidget);
expect(find.text('Retry'), findsOneWidget);
expect(find.text('World Map'), findsOneWidget);
expect(store.saveCalls, 0);
```

Tap `Retry`, then verify the game returns to build phase and no campaign save occurred.

- [ ] **Step 5: Add failed-save abandonment breadcrumb + one-shot exit regression**

Use `_TestCampaignProgressStore(saveError: StateError('fail'))`, publish an improving victory, and wait for `Save failed — progress unchanged.`.

Tap `World Map (Unsaved)` twice before pumping, then pump and assert:

```dart
expect(find.text('Orion Sector Map'), findsOneWidget);
expect(find.text('Mission result was not saved.'), findsOneWidget);
expect(store.progress.resultFor('outpost-alpha'), isNull);
```

The second tap must not trigger a second navigation mutation because `_missionExitStarted` is already true.

- [ ] **Step 6: Add mission-save then tech-purchase writer regression**

Seed enough committed medal points while leaving Alpha improvable:

```dart
final store = _TestCampaignProgressStore(
  progress: CampaignProgress(
    bestResultsByStageId: {
      'outpost-alpha': const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
      'nebula-relay': const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
      'salvage-rift': const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
      'asteroid-foundry': const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      ),
    },
  ),
);
```

Run the flow:

```dart
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

await publishVictory(
  tester,
  game!,
  result: const StageResult(
    medal: StageMedal.gold,
    bestBaseHealth: 20,
  ),
);
await tester.pumpAndSettle();
expect(find.text('Saved.'), findsOneWidget);

await tester.tap(find.text('World Map'));
await tester.pumpAndSettle();
await tester.tap(find.byTooltip('Tech Tree'));
await tester.pumpAndSettle();

final solarCard = find.ancestor(
  of: find.text('Solar Capacitors'),
  matching: find.byType(Card),
);
final purchase = find.descendant(
  of: solarCard,
  matching: find.widgetWithText(FilledButton, 'Purchase'),
);
await tester.tap(purchase);
await tester.pumpAndSettle();

expect(
  store.progress.resultFor('outpost-alpha'),
  const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
);
expect(
  store.techTree.isPurchased(CampaignTechUpgrade.solarCapacitors),
  isTrue,
);
```

This is the regression that proves the mission save advances `_committedProgress` and the later `_persistSave` tech purchase composes on that committed result instead of overwriting it.

- [ ] **Step 7: Run all focused Mission Report tests**

```bash
flutter test test/game/mission_report_content_test.dart
flutter test test/widget/mission_report_panel_test.dart
flutter test test/widget_test.dart
```

Expected: all focused and page/widget regression tests pass.

- [ ] **Step 8: Run formatting and static analysis**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
```

Expected: no formatting diff and no analyzer issues.

- [ ] **Step 9: Run the full suite**

```bash
flutter test
```

Expected: full suite passes.

- [ ] **Step 10: Perform the compact human check**

At 360×640 logical pixels, verify one victory and one loss:

Victory:

1. Complete a run with at least one Salvage Module.
2. Confirm the report appears in `Saving…` before commitment when the save can be observed.
3. Confirm report actions are unavailable while saving.
4. Confirm `Saved.` appears after success and Replay/World Map become reachable.
5. Confirm module titles are readable without scrolling the action row away.

Loss:

1. Lose before or after a module draft.
2. Confirm `Reached Wave N/8` is understandable.
3. Confirm the module section shows acquired titles or `No Salvage Modules acquired`.
4. Confirm Retry and World Map remain reachable.

Residual durability check: no additional implementation is required for process death during `Saving…`. The accepted behavior is that an uncommitted result may be lost and the prior committed campaign remains authoritative.

- [ ] **Step 11: Commit regression cleanup**

```bash
git add test/widget_test.dart lib/game/ui/orion_game_page.dart
git commit -m "test: cover mission report persistence flow"
```

---

## Final Self-Review Checklist

Before implementation is called complete, verify:

- Pure projection owns all comparison, save, module-title, and empty-module copy.
- Victory projection receives the frozen `StageCompletion.result`; it never re-derives another result from snapshot base health.
- `StageResult.isBetterThan` decides improved vs retained.
- No won-snapshot fallback can display `Saving…` without an actual save state.
- Mission save is non-optimistic and has no stage-result rollback branch.
- Mission save enqueues on the existing `_saveQueue`; there is no parallel `store.save` chain.
- Mission payload is composed from `_committedProgress` / `_committedTechTree` inside the queued task.
- `_pendingSaves`, `_isSavingProgress`, `_progressGeneration`, and `_decrementPendingSaves()` remain part of the shared writer contract.
- `game.returnToMap()` during saving cannot escape the report.
- Bottom World Map control is disabled for won/lost terminal states.
- `_returnToMap()` has a defensive saving guard.
- Failed result can only Retry Save or explicitly abandon via World Map (Unsaved).
- Retained best performs zero writes.
- Loss performs zero writes.
- Mission-save → tech-purchase regression preserves both state changes.
- No codec/schema change, controller, event bus, reward framework, RunStats, analytics, or durable mid-write recovery was added.
- Process kill during `Saving…` is documented as an accepted residual risk.
- `dart format`, `flutter analyze`, focused tests, and full `flutter test` pass.