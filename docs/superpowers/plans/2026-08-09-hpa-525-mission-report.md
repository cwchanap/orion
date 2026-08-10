# HPA-525 Mission Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Orion's minimal terminal panel with a compact Mission Report whose result comparison, Salvage Module summary, save truth, and next actions stay honest through save success, failure, and retry.

**Architecture:** Keep `GameSession` and `OrionDefenseGame` as the source of terminal mission facts, add one Flutter-free report projection plus one report widget, and let `OrionGamePage` own a single stage-result save attempt. Improving results are persisted directly without optimistic campaign mutation; the existing queued persistence machinery remains available only to its current tech-tree/reset responsibilities.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- HPA-527 is the gameplay baseline; do not change Salvage Module offer/effect rules.
- Do not add a new `GamePhase` or report phase to `GameSession`.
- Do not add RunStats, analytics, coaching, evidence export, run history, mid-run persistence, or a generic reward framework.
- Do not route stage completion through the optimistic `_persistSave` queue.
- Do not optimistically update `_progress` for an improving victory.
- Keep the existing tech-tree/reset persistence path unchanged except where a compile fix is mechanically required.
- A retained replay result performs no storage write and is immediately treated as already saved.
- Victory save states are exactly `saving`, `saved`, and `failed`; loss has no save state.
- Save failure leaves campaign progress unchanged.
- While victory saving is in flight, Replay and World Map actions are disabled.
- Failed victory exposes `Retry Save` and `World Map (Unsaved)`; do not expose Replay until the result is saved or explicitly abandoned.
- Use one `_missionExitStarted` one-shot guard for world-map navigation.
- Keep HPA-528 integration to one optional `MissionRewardFact`; HPA-525 always supplies `null`.
- Do not edit the save codec for this ticket. If implementation unexpectedly must edit it, remove obsolete v1/v2 development-save decoder branches rather than extending them.
- Target 360×640 logical pixels; the report body may scroll but primary actions remain reachable.
- Save meaning must use text/icon and cannot rely on color alone.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and full `flutter test`.

## File Map

### Create

- `lib/game/ui/mission_report_content.dart` — immutable report presentation model and pure projection.
- `lib/game/ui/mission_report_panel.dart` — compact scrollable Mission Report overlay with fixed reachable actions.
- `test/game/mission_report_content_test.dart` — pure projection coverage.
- `test/widget/mission_report_panel_test.dart` — 360×640 presentation/action coverage.

### Modify

- `lib/game/ui/orion_game_page.dart` — freeze prior result at stage start, own the single-flight result save, render Mission Report, guard replay/exit, and remove `_EndStatePanel`.
- `test/widget_test.dart` — page-level save success/failure/retry/no-op/loss/repeated-action integration coverage and removal of obsolete optimistic stage-save tests.

No production change is required in `GameSession`, `OrionDefenseGame`, `CampaignProgress`, or `CampaignProgressStore` for the intended design.

---

### Task 1: Add the pure Mission Report presentation model

**Files:**
- Create: `lib/game/ui/mission_report_content.dart`
- Create: `test/game/mission_report_content_test.dart`

**Interfaces:**
- Consumes: `GameSnapshot`, `StageResult`, `RunModuleId`, `runModuleDefinition`.
- Produces: `MissionSaveState`, `MissionResultComparison`, `MissionModuleFact`, `MissionRewardFact`, `MissionReportContent`, and `projectMissionReport(...)`.
- Later tasks render only `MissionReportContent`; they do not re-derive result copy.

- [ ] **Step 1: Write the failing projection tests**

Create `test/game/mission_report_content_test.dart` with a compact terminal-snapshot helper and explicit expected copy:

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
  test('projects first clear without claiming it is already committed', () {
    final content = projectMissionReport(
      snapshot: terminalSnapshot(
        phase: GamePhase.won,
        modules: const [
          RunModuleId.heavyCaliber,
          RunModuleId.emergencySalvage,
        ],
      ),
      priorSavedResult: null,
      saveState: MissionSaveState.saving,
    );

    expect(content.didWin, isTrue);
    expect(content.outcomeText, 'Silver medal • Base 14/20');
    expect(content.comparison, MissionResultComparison.firstClear);
    expect(content.comparisonText, 'New first-clear result');
    expect(content.saveText, 'Saving result…');
    expect(
      content.modules.map((module) => module.title),
      ['Heavy Caliber', 'Emergency Salvage'],
    );
    expect(
      content.nextOpportunityText,
      'Saving must finish before you replay or leave.',
    );
  });

  test('projects medal improvement', () {
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 20),
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
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 17),
      priorSavedResult: const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
      saveState: MissionSaveState.saved,
    );

    expect(content.comparison, MissionResultComparison.baseHealthImproved);
    expect(content.comparisonText, 'Base health improved: 14 → 17');
  });

  test('projects retained best as already saved', () {
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won, baseHealth: 14),
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

  test('projects failed save without changing result copy', () {
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
      priorSavedResult: null,
      saveState: MissionSaveState.failed,
    );

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
      priorSavedResult: const StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      ),
      saveState: null,
    );

    expect(content.didWin, isFalse);
    expect(content.outcomeText, 'Reached Wave 5/8');
    expect(content.comparison, isNull);
    expect(content.saveState, isNull);
    expect(content.saveText, isNull);
    expect(content.nextOpportunityText, 'Adjust your build and retry when ready.');
  });

  test('passes one optional typed reward fact through unchanged', () {
    const reward = MissionRewardFact(
      title: 'Blueprint recovered',
      detail: 'Heavy Caliber Mk II',
    );
    final content = projectMissionReport(
      snapshot: terminalSnapshot(phase: GamePhase.won),
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

MissionReportContent projectMissionReport({
  required GameSnapshot snapshot,
  required StageResult? priorSavedResult,
  required MissionSaveState? saveState,
  MissionRewardFact? reward,
}) {
  final didWin = snapshot.phase == GamePhase.won;
  final modules = snapshot.acquiredRunModules
      .map(
        (id) => MissionModuleFact(
          id: id,
          title: runModuleDefinition(id).title,
        ),
      )
      .toList(growable: false);

  if (!didWin) {
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
      reward: reward,
      nextOpportunityText: 'Adjust your build and retry when ready.',
    );
  }

  assert(saveState != null, 'Victory report requires an explicit save state.');
  final result = StageResult.fromVictoryBaseHealth(
    snapshot.baseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
  );
  final comparison = _comparison(result, priorSavedResult);
  final comparisonText = _comparisonText(
    comparison,
    result: result,
    priorSavedResult: priorSavedResult,
  );

  return MissionReportContent(
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    didWin: true,
    waveNumber: snapshot.waveNumber,
    waveTotal: snapshot.waveTotal,
    remainingBaseHealth: snapshot.baseHealth,
    startingBaseHealth: snapshot.startingBaseHealth,
    result: result,
    priorSavedResult: priorSavedResult,
    comparison: comparison,
    outcomeText:
        '${result.medal.label} medal • Base ${result.bestBaseHealth}/${snapshot.startingBaseHealth}',
    comparisonText: comparisonText,
    modules: modules,
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
  if (result.medal.rank > priorSavedResult.medal.rank) {
    return MissionResultComparison.medalImproved;
  }
  if (result.medal == priorSavedResult.medal &&
      result.bestBaseHealth > priorSavedResult.bestBaseHealth) {
    return MissionResultComparison.baseHealthImproved;
  }
  return MissionResultComparison.retained;
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
    MissionSaveState.saved when comparison == MissionResultComparison.retained =>
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

Expected: all tests pass.

- [ ] **Step 5: Commit the pure report model**

```bash
git add lib/game/ui/mission_report_content.dart test/game/mission_report_content_test.dart
git commit -m "feat: add mission report projection"
```

---

### Task 2: Add the 360×640 Mission Report panel

**Files:**
- Create: `lib/game/ui/mission_report_panel.dart`
- Create: `test/widget/mission_report_panel_test.dart`

**Interfaces:**
- Consumes: `MissionReportContent` from Task 1 and three nullable callbacks.
- Produces: `MissionReportPanel`.
- The panel does not call game/session APIs and does not infer persistence success.

- [ ] **Step 1: Write failing widget tests for states and compact layout**

Create `test/widget/mission_report_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/mission_report_content.dart';
import 'package:orion/game/ui/mission_report_panel.dart';

MissionReportContent victoryContent(MissionSaveState saveState) {
  final snapshot = GameSnapshot(
    phase: GamePhase.won,
    gold: 80,
    baseHealth: 14,
    startingBaseHealth: 20,
    waveNumber: 8,
    waveTotal: 8,
    stageId: 'outpost-alpha',
    stageName: 'Outpost Alpha',
    stageLabel: 'Alpha',
    unlockedTowerTypes: const [TowerType.laser],
    stageModifiers: const [],
    nextWavePreview: null,
    selectedCell: null,
    selectedTower: null,
    feedback: null,
    isPaused: false,
    speedMultiplier: 1,
    autoStartEnabled: false,
    autoStartCountdownRemaining: null,
    acquiredRunModules: const [
      RunModuleId.heavyCaliber,
      RunModuleId.longSight,
      RunModuleId.emergencySalvage,
    ],
  );
  return projectMissionReport(
    snapshot: snapshot,
    priorSavedResult: null,
    saveState: saveState,
  );
}

Future<void> pumpReport(
  WidgetTester tester,
  MissionReportContent content, {
  VoidCallback? onReplay,
  VoidCallback? onReturnToMap,
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
          onReturnToMap: onReturnToMap,
          onRetrySave: onRetrySave,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('saving victory keeps actions reachable but disabled', (tester) async {
    await pumpReport(tester, victoryContent(MissionSaveState.saving));

    expect(find.text('Victory'), findsOneWidget);
    expect(find.text('Saving result…'), findsOneWidget);
    expect(find.text('Heavy Caliber'), findsOneWidget);
    expect(find.text('Long Sight'), findsOneWidget);
    expect(find.text('Emergency Salvage'), findsOneWidget);
    expect(find.text('Replay Mission'), findsOneWidget);
    expect(find.text('World Map'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Replay Mission'),
      ).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved victory exposes replay and world map', (tester) async {
    var replays = 0;
    var exits = 0;
    await pumpReport(
      tester,
      victoryContent(MissionSaveState.saved),
      onReplay: () => replays++,
      onReturnToMap: () => exits++,
    );

    await tester.tap(find.text('Replay Mission'));
    await tester.tap(find.text('World Map'));

    expect(replays, 1);
    expect(exits, 1);
  });

  testWidgets('failed victory exposes retry save and unsaved exit', (tester) async {
    var retries = 0;
    var exits = 0;
    await pumpReport(
      tester,
      victoryContent(MissionSaveState.failed),
      onRetrySave: () => retries++,
      onReturnToMap: () => exits++,
    );

    expect(find.text('Retry Save'), findsOneWidget);
    expect(find.text('World Map (Unsaved)'), findsOneWidget);
    expect(find.text('Replay Mission'), findsNothing);

    await tester.tap(find.text('Retry Save'));
    await tester.tap(find.text('World Map (Unsaved)'));
    expect(retries, 1);
    expect(exits, 1);
  });
}
```

Add one loss test using `projectMissionReport(... phase: GamePhase.lost, saveState: null)` and assert `Retry`, `World Map`, `Reached Wave`, and `No Salvage Modules acquired` are visible without overflow.

- [ ] **Step 2: Run widget tests and verify red**

```bash
flutter test test/widget/mission_report_panel_test.dart
```

Expected: compile failure because `MissionReportPanel` does not exist.

- [ ] **Step 3: Implement the panel with scrollable body and fixed action area**

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
      color: Colors.black.withValues(alpha: 0.62),
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
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            content.didWin
                                ? Icons.emoji_events
                                : Icons.warning_amber,
                            size: 44,
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
                          Text(
                            'Salvage Modules',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          if (content.modules.isEmpty)
                            const Text('No Salvage Modules acquired')
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
                            _SaveStatus(
                              state: content.saveState!,
                              text: saveText,
                            ),
                          ],
                          if (content.reward case final reward?) ...[
                            const SizedBox(height: 16),
                            Text(
                              reward.title,
                              style: theme.textTheme.titleSmall,
                            ),
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
              _MissionActions(
                content: content,
                onReplay: onReplay,
                onReturnToMap: onReturnToMap,
                onRetrySave: onRetrySave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Implement `_SaveStatus` with icon + text:

```dart
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.state, required this.text});

  final MissionSaveState state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      MissionSaveState.saving => Icons.sync,
      MissionSaveState.saved => Icons.check_circle_outline,
      MissionSaveState.failed => Icons.error_outline,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
```

Implement `_MissionActions` with the exact state matrix from the design:

```dart
class _MissionActions extends StatelessWidget {
  const _MissionActions({
    required this.content,
    required this.onReplay,
    required this.onReturnToMap,
    required this.onRetrySave,
  });

  final MissionReportContent content;
  final VoidCallback? onReplay;
  final VoidCallback? onReturnToMap;
  final VoidCallback? onRetrySave;

  @override
  Widget build(BuildContext context) {
    if (!content.didWin) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: onReplay,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Retry'),
          ),
          FilledButton.tonalIcon(
            onPressed: onReturnToMap,
            icon: const Icon(Icons.map),
            label: const Text('World Map'),
          ),
        ],
      );
    }

    return switch (content.saveState!) {
      MissionSaveState.saving => Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Replay Mission'),
            ),
            FilledButton.tonalIcon(
              onPressed: null,
              icon: const Icon(Icons.map),
              label: const Text('World Map'),
            ),
          ],
        ),
      MissionSaveState.saved => Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Replay Mission'),
            ),
            FilledButton.tonalIcon(
              onPressed: onReturnToMap,
              icon: const Icon(Icons.map),
              label: const Text('World Map'),
            ),
          ],
        ),
      MissionSaveState.failed => Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onRetrySave,
              icon: const Icon(Icons.sync),
              label: const Text('Retry Save'),
            ),
            FilledButton.tonalIcon(
              onPressed: onReturnToMap,
              icon: const Icon(Icons.map),
              label: const Text('World Map (Unsaved)'),
            ),
          ],
        ),
    };
  }
}
```

- [ ] **Step 4: Run the compact widget tests**

```bash
flutter test test/widget/mission_report_panel_test.dart
```

Expected: all tests pass with no overflow exception at 360×640.

- [ ] **Step 5: Commit the report panel**

```bash
git add lib/game/ui/mission_report_panel.dart test/widget/mission_report_panel_test.dart
git commit -m "feat: add mission report panel"
```

---

### Task 3: Replace optimistic stage-result persistence with one report-owned save

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 1 `projectMissionReport`, `MissionSaveState`; Task 2 `MissionReportPanel`.
- Produces: `_handleStageWon`, `_saveMissionResult`, `_restartFromMissionReport`, `_returnFromMissionReport`.
- Keeps: `_persistSave`, `_saveQueue`, `_committedTechTree`, generation/reset logic for existing non-stage paths.

- [ ] **Step 1: Add a failing page test for explicit saving and no optimistic progress**

In `test/widget_test.dart`, use the existing `_TestCampaignProgressStore(delaySaves: true)` helper. Start Outpost Alpha from a fresh campaign, then trigger the normal `onStageWon` callback and wait until the delayed store records its first save attempt:

```dart
testWidgets(
  'victory report stays saving and does not optimistically update progress',
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

    final createdGame = game!;
    createdGame.onStageWon?.call(
      StageCompletion(
        stage: OrionCampaign.stageOne,
        result: const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: 14,
        ),
      ),
    );
    createdGame.stateNotifier.value = GameSnapshot(
      phase: GamePhase.won,
      gold: createdGame.snapshot.gold,
      baseHealth: 14,
      startingBaseHealth: createdGame.snapshot.startingBaseHealth,
      waveNumber: 8,
      waveTotal: 8,
      stageId: createdGame.snapshot.stageId,
      stageName: createdGame.snapshot.stageName,
      stageLabel: createdGame.snapshot.stageLabel,
      unlockedTowerTypes: createdGame.snapshot.unlockedTowerTypes,
      stageModifiers: createdGame.snapshot.stageModifiers,
      nextWavePreview: null,
      selectedCell: null,
      selectedTower: null,
      feedback: null,
      isPaused: false,
      speedMultiplier: 1,
      autoStartEnabled: false,
      autoStartCountdownRemaining: null,
      acquiredRunModules: const [RunModuleId.heavyCaliber],
    );

    await _pumpUntil(tester, () => store.saveCompletions.isNotEmpty);
    await tester.pump();

    expect(find.text('Saving result…'), findsOneWidget);
    expect(find.text('Heavy Caliber'), findsOneWidget);
    expect(store.progress.resultFor('outpost-alpha'), isNull);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Replay Mission'),
      ).onPressed,
      isNull,
    );
  },
);
```

The implementation may replace the direct terminal snapshot injection with an existing test helper if one already exists after Task 2, but keep the assertion contract unchanged.

- [ ] **Step 2: Run the focused page test and verify red**

```bash
flutter test test/widget_test.dart --plain-name "victory report stays saving and does not optimistically update progress"
```

Expected: failure because the old `_EndStatePanel` is still rendered and `_saveStageCompletion` still mutates `_progress` optimistically.

- [ ] **Step 3: Add Mission Report imports and page state fields**

In `lib/game/ui/orion_game_page.dart` add:

```dart
import 'mission_report_content.dart';
import 'mission_report_panel.dart';
```

Add fields beside the existing page persistence state:

```dart
StageResult? _missionPriorResult;
CampaignProgress? _pendingMissionProgress;
MissionSaveState? _missionSaveState;
bool _missionExitStarted = false;
```

- [ ] **Step 4: Freeze the comparison baseline when a stage starts**

In `_startStage(StageDefinition stage)`, after all launch guards and before creating `OrionDefenseGame`, assign:

```dart
_missionPriorResult = _progress.resultFor(stage.id);
_pendingMissionProgress = null;
_missionSaveState = null;
_missionExitStarted = false;
```

Change the game callback from:

```dart
onStageWon: _saveStageCompletion,
```

to:

```dart
onStageWon: _handleStageWon,
```

- [ ] **Step 5: Replace `_saveStageCompletion` with single-flight mission save methods**

Delete `_saveStageCompletion` and add:

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
    _setMissionSaveState(MissionSaveState.saved);
    return;
  }

  _saveMissionResult();
}

void _setMissionSaveState(MissionSaveState state) {
  _missionSaveState = state;
  if (mounted) {
    setState(() {});
  }
}

Future<void> _saveMissionResult() async {
  if (_missionSaveState == MissionSaveState.saving ||
      _missionSaveState == MissionSaveState.saved) {
    return;
  }

  final store = _store;
  final proposed = _pendingMissionProgress;
  if (store == null || proposed == null) {
    _setMissionSaveState(MissionSaveState.failed);
    return;
  }

  _setMissionSaveState(MissionSaveState.saving);
  try {
    await store.save(
      CampaignSave(
        progress: proposed,
        techTree: _committedTechTree,
      ),
    );
    _progress = proposed;
    _committedProgress = proposed;
    _setMissionSaveState(MissionSaveState.saved);
  } catch (_) {
    _setMissionSaveState(MissionSaveState.failed);
  }
}
```

Do not call `_persistSave`, `_showCampaignPersistenceFailure`, or a rollback callback from this path.

- [ ] **Step 6: Add guarded replay and world-map callbacks**

Add:

```dart
void _restartFromMissionReport() {
  if (_missionSaveState == MissionSaveState.saving) {
    return;
  }
  final game = _game;
  if (game == null) {
    return;
  }

  _missionPriorResult = _progress.resultFor(game.stage.id);
  _pendingMissionProgress = null;
  _missionSaveState = null;
  _missionExitStarted = false;
  game.restart();
  if (mounted) {
    setState(() {});
  }
}

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

Loss has `_missionSaveState == null`, so both callbacks remain available.

- [ ] **Step 7: Replace `_EndStatePanel` with `MissionReportPanel`**

Inside the `ValueListenableBuilder` stage `Stack`, replace:

```dart
if (snapshot.isEnded)
  Positioned.fill(
    child: _EndStatePanel(game: game, snapshot: snapshot),
  ),
```

with:

```dart
if (snapshot.isEnded)
  Positioned.fill(
    child: MissionReportPanel(
      content: projectMissionReport(
        snapshot: snapshot,
        priorSavedResult: _missionPriorResult,
        saveState: snapshot.phase == GamePhase.won
            ? (_missionSaveState ?? MissionSaveState.saving)
            : null,
        reward: null,
      ),
      onReplay: snapshot.phase == GamePhase.won &&
              _missionSaveState == MissionSaveState.saving
          ? null
          : _restartFromMissionReport,
      onReturnToMap: snapshot.phase == GamePhase.won &&
              _missionSaveState == MissionSaveState.saving
          ? null
          : _returnFromMissionReport,
      onRetrySave: _missionSaveState == MissionSaveState.failed
          ? _saveMissionResult
          : null,
    ),
  ),
```

Then delete the private `_EndStatePanel` class from the bottom of `orion_game_page.dart`.

The `MissionSaveState.saving` fallback covers the narrow frame between terminal snapshot publication and the synchronous start of `_handleStageWon`; it never marks progress committed.

- [ ] **Step 8: Run the focused saving test**

```bash
flutter test test/widget_test.dart --plain-name "victory report stays saving and does not optimistically update progress"
```

Expected: pass.

- [ ] **Step 9: Add success, failure, retry, retained-result, and loss integration tests**

Add these contracts to `test/widget_test.dart` using the existing delayed/failing test store:

```dart
expect(find.text('Saved.'), findsOneWidget);
expect(store.progress.resultFor('outpost-alpha'), completion.result);
```

after completing a successful delayed save.

For failure:

```dart
expect(find.text('Save failed — progress unchanged.'), findsOneWidget);
expect(find.text('Retry Save'), findsOneWidget);
expect(find.text('World Map (Unsaved)'), findsOneWidget);
expect(store.progress.resultFor('outpost-alpha'), isNull);
```

For retry, configure the test store to fail only the first save index, tap `Retry Save` twice before pumping, and assert exactly one second save attempt starts:

```dart
await tester.tap(find.text('Retry Save'));
await tester.tap(find.text('Retry Save'));
await tester.pump();
expect(store.saveCalls, 2);
```

Complete the retry and assert `Saved.` plus persisted progress.

For a retained result, seed a stronger result before stage launch, trigger a weaker victory, and assert:

```dart
expect(find.text('Best result already saved.'), findsOneWidget);
expect(store.saveCalls, 0);
```

For loss, inject a lost terminal snapshot and assert:

```dart
expect(find.text('Mission Failed'), findsOneWidget);
expect(find.text('Retry'), findsOneWidget);
expect(find.text('World Map'), findsOneWidget);
expect(store.saveCalls, 0);
```

- [ ] **Step 10: Run all report/page-focused tests**

```bash
flutter test \
  test/game/mission_report_content_test.dart \
  test/widget/mission_report_panel_test.dart \
  test/widget_test.dart
```

Expected: all report and page tests pass.

- [ ] **Step 11: Commit the page-owned save flow**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: wire mission report save flow"
```

---

### Task 4: Remove obsolete optimistic stage-save contracts and finish regression coverage

**Files:**
- Modify: `test/widget_test.dart`
- Modify only if formatting/analyze exposes a mechanical issue: files already touched in Tasks 1–3.

**Interfaces:**
- Removes tests for behavior HPA-525 intentionally deletes.
- Keeps all tech-tree/reset persistence tests and production code unchanged.

- [ ] **Step 1: Delete tests whose behavior is no longer valid**

Remove the page tests with these old stage-result contracts:

```text
optimistic stage clear is visible on map before save fails, then reverts
blocks stage launch while a stage-completion save is in flight
serializes sibling stage clear saves without losing progress
persists queued stage save even if page is disposed before it runs
queued save after disposal keeps earlier queued result in store
failed queued save after disposal does not call setState on a defunct State
```

Also remove any later stage-completion-specific queue/rollback tests with the same premise. Do not remove tech purchase queue, reset, or load-failure coverage.

- [ ] **Step 2: Update the existing victory/loss panel assertions to Mission Report copy**

Change the old terminal-panel tests to assert the new surface:

```dart
expect(find.text('Victory'), findsOneWidget);
expect(find.text('Silver medal • Base 14/20'), findsOneWidget);
```

and:

```dart
expect(find.text('Mission Failed'), findsOneWidget);
expect(find.textContaining('Reached Wave'), findsOneWidget);
```

Preserve the existing assertion that environment reminders are hidden after termination.

- [ ] **Step 3: Add one unsaved world-map breadcrumb test**

After a failed save, tap `World Map (Unsaved)` and assert:

```dart
expect(find.text('Orion Sector Map'), findsOneWidget);
expect(find.text('Mission result was not saved.'), findsOneWidget);
expect(find.text('Silver'), findsNothing);
```

for a fresh first-clear failure.

- [ ] **Step 4: Add a repeated world-map tap guard test**

Call the report exit callback twice through two rapid taps before settling and assert the page returns to the world map without exceptions or duplicate game creation/navigation side effects. Use the existing `onGameCreated` counter if needed:

```dart
var gameCreations = 0;
// increment from onGameCreated
...
expect(gameCreations, 1);
expect(find.text('Orion Sector Map'), findsOneWidget);
expect(tester.takeException(), isNull);
```

- [ ] **Step 5: Run formatting and static analysis**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
```

Expected: both exit 0.

If formatting reports changes, run:

```bash
dart format .
```

then rerun the no-change format gate and `flutter analyze`.

- [ ] **Step 6: Run focused tests**

```bash
flutter test \
  test/game/mission_report_content_test.dart \
  test/widget/mission_report_panel_test.dart \
  test/widget_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```

Expected: full suite passes.

- [ ] **Step 8: Perform one human 360×640-equivalent check**

Verify one victory and one loss on a compact portrait surface:

```text
Victory:
- report appears immediately;
- Salvage Module chips are readable;
- save status is understandable without color;
- action buttons remain reachable;
- leaving is blocked while saving.

Loss:
- reached wave is obvious;
- no save status is shown;
- Retry and World Map remain reachable.
```

- [ ] **Step 9: Commit regression cleanup**

```bash
git add test/widget_test.dart
git commit -m "test: cover mission report persistence states"
```

## Final self-review

Before implementation is declared complete, verify each design requirement maps to code/tests:

- one pure projection → Task 1;
- typed optional reward fact → Task 1;
- 360×640 scrollable body + reachable actions → Task 2;
- explicit saving/saved/failed UI → Tasks 1–2;
- no optimistic stage progress → Task 3;
- one proposed progress value + retry → Task 3;
- retained result no-op write → Task 3;
- one-shot world-map exit → Task 3;
- old stage save queue/rollback contracts removed → Task 4;
- tech-tree/reset persistence untouched → Tasks 3–4;
- full format/analyze/test gates → Task 4.

No `TODO`, `TBD`, generic error-handling placeholder, new dependency, persistence schema migration, or unassigned feature decision should remain.
