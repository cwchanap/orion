# Orion Pause and Wave Speed Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mission-local pause, 1x/2x/3x speed selection, and cancelable auto-start countdown controls for Orion waves.

**Architecture:** `OrionDefenseGame` owns pacing state and uses Flame `HasTimeScale` for component updates. `GameSession` remains pure rules, while `GameSnapshot` carries pacing fields for the Flutter UI. Auto-start countdown uses the same scaled, unpaused mission delta as wave spawning.

**Tech Stack:** Flutter, Flame 1.37, Dart 3.12, flutter_test.

---

## File Structure

- Modify `lib/game/models/game_models.dart`
  - Add pacing fields to `GameSnapshot`.
  - Keep snapshot values immutable and UI-facing.
- Modify `lib/game/rules/game_session.dart`
  - Add optional pacing parameters to `GameSession.snapshot()` with safe defaults.
  - Keep `GameSession` unaware of pacing state storage.
- Modify `lib/game/orion_defense_game.dart`
  - Add `HasTimeScale`.
  - Store mission-local pause, speed, auto-start, and countdown state.
  - Apply scaled time to spawn timers and countdowns.
  - Reset pacing on restart, win, and loss.
- Modify `lib/game/ui/orion_game_page.dart`
  - Preserve pacing fields when injecting campaign persistence feedback.
  - Add compact pause, speed, and auto-start controls in the existing bottom controls.
- Modify `test/game/game_session_test.dart`
  - Cover snapshot pacing defaults and explicit snapshot overrides.
- Modify `test/game/orion_defense_game_test.dart`
  - Cover game-level pacing state, time scale, countdown, pause, restart, win, and loss behavior.
- Modify `test/widget_test.dart`
  - Cover visible mission pacing controls.

## Task 1: Snapshot Pacing Fields

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Test: `test/game/game_session_test.dart`

- [ ] **Step 1: Write failing snapshot tests**

Add these tests inside the existing `GameSession` group in `test/game/game_session_test.dart`:

```dart
test('snapshot exposes default mission pacing state', () {
  final snapshot = GameSession.initial().snapshot();

  expect(snapshot.isPaused, isFalse);
  expect(snapshot.speedMultiplier, 1);
  expect(snapshot.autoStartEnabled, isFalse);
  expect(snapshot.autoStartCountdownRemaining, isNull);
});

test('snapshot can carry mission pacing state from the game layer', () {
  final snapshot = GameSession.initial().snapshot(
    isPaused: true,
    speedMultiplier: 2,
    autoStartEnabled: true,
    autoStartCountdownRemaining: 1.5,
  );

  expect(snapshot.isPaused, isTrue);
  expect(snapshot.speedMultiplier, 2);
  expect(snapshot.autoStartEnabled, isTrue);
  expect(snapshot.autoStartCountdownRemaining, 1.5);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk flutter test test/game/game_session_test.dart --name "snapshot exposes default mission pacing state"
```

Expected: FAIL with analyzer or compile errors because `GameSnapshot` has no pacing fields and `GameSession.snapshot()` does not accept pacing parameters.

- [ ] **Step 3: Add pacing fields to `GameSnapshot`**

In `lib/game/models/game_models.dart`, replace the `GameSnapshot` constructor and field section with this shape:

```dart
class GameSnapshot {
  GameSnapshot({
    required this.phase,
    required this.gold,
    required this.baseHealth,
    required this.waveNumber,
    required this.waveTotal,
    required this.stageId,
    required this.stageName,
    required this.stageLabel,
    required List<TowerType> unlockedTowerTypes,
    required this.selectedCell,
    required this.selectedTower,
    required this.feedback,
    required this.isPaused,
    required this.speedMultiplier,
    required this.autoStartEnabled,
    required this.autoStartCountdownRemaining,
  }) : unlockedTowerTypes = List.unmodifiable(unlockedTowerTypes);

  final GamePhase phase;
  final int gold;
  final int baseHealth;
  final int waveNumber;
  final int waveTotal;
  final String stageId;
  final String stageName;
  final String stageLabel;
  final List<TowerType> unlockedTowerTypes;
  final GridPosition? selectedCell;
  final PlacedTower? selectedTower;
  final String? feedback;
  final bool isPaused;
  final double speedMultiplier;
  final bool autoStartEnabled;
  final double? autoStartCountdownRemaining;

  bool get canStartWave => phase == GamePhase.build;
  bool get isEnded => phase == GamePhase.won || phase == GamePhase.lost;
}
```

- [ ] **Step 4: Thread pacing through `GameSession.snapshot()`**

In `lib/game/rules/game_session.dart`, replace the `snapshot` method signature and constructor call with:

```dart
GameSnapshot snapshot({
  GridPosition? selectedCell,
  PlacedTower? selectedTower,
  String? feedback,
  bool isPaused = false,
  double speedMultiplier = 1,
  bool autoStartEnabled = false,
  double? autoStartCountdownRemaining,
}) {
  return GameSnapshot(
    phase: _phase,
    gold: _gold,
    baseHealth: _baseHealth,
    waveNumber: (_waveIndex + 1).clamp(1, stage.waves.length).toInt(),
    waveTotal: stage.waves.length,
    stageId: stage.id,
    stageName: stage.name,
    stageLabel: stage.mapLabel,
    unlockedTowerTypes: unlockedTowerTypes,
    selectedCell: selectedCell,
    selectedTower: selectedTower,
    feedback: feedback,
    isPaused: isPaused,
    speedMultiplier: speedMultiplier,
    autoStartEnabled: autoStartEnabled,
    autoStartCountdownRemaining: autoStartCountdownRemaining,
  );
}
```

- [ ] **Step 5: Preserve pacing fields in campaign feedback snapshots**

In `lib/game/ui/orion_game_page.dart`, update the manual `GameSnapshot` constructor inside `_showCampaignPersistenceFailure()` by adding the new fields:

```dart
game.stateNotifier.value = GameSnapshot(
  phase: snapshot.phase,
  gold: snapshot.gold,
  baseHealth: snapshot.baseHealth,
  waveNumber: snapshot.waveNumber,
  waveTotal: snapshot.waveTotal,
  stageId: snapshot.stageId,
  stageName: snapshot.stageName,
  stageLabel: snapshot.stageLabel,
  unlockedTowerTypes: snapshot.unlockedTowerTypes,
  selectedCell: snapshot.selectedCell,
  selectedTower: snapshot.selectedTower,
  feedback: message,
  isPaused: snapshot.isPaused,
  speedMultiplier: snapshot.speedMultiplier,
  autoStartEnabled: snapshot.autoStartEnabled,
  autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
);
```

- [ ] **Step 6: Run snapshot tests**

Run:

```bash
rtk flutter test test/game/game_session_test.dart --name "snapshot"
```

Expected: PASS for the snapshot tests.

- [ ] **Step 7: Commit snapshot plumbing**

Run:

```bash
rtk git add lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/ui/orion_game_page.dart test/game/game_session_test.dart
rtk git commit -m "feat: expose Orion pacing in snapshots"
```

Expected: commit succeeds.

## Task 2: Game Pacing State and Time Scale

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Test: `test/game/orion_defense_game_test.dart`

- [ ] **Step 1: Write failing game pacing tests**

Add these tests inside the `OrionDefenseGame` group in `test/game/orion_defense_game_test.dart`:

```dart
test('defaults to unpaused 1x pacing with auto-start disabled', () {
  final game = OrionDefenseGame();

  expect(game.snapshot.isPaused, isFalse);
  expect(game.snapshot.speedMultiplier, 1);
  expect(game.snapshot.autoStartEnabled, isFalse);
  expect(game.snapshot.autoStartCountdownRemaining, isNull);
  expect(game.timeScale, 1);
});

test('sets supported speed multipliers and ignores unsupported values', () {
  final game = OrionDefenseGame();

  game.setSpeedMultiplier(2);
  expect(game.snapshot.speedMultiplier, 2);
  expect(game.timeScale, 2);

  game.setSpeedMultiplier(3);
  expect(game.snapshot.speedMultiplier, 3);
  expect(game.timeScale, 3);

  game.setSpeedMultiplier(4);
  expect(game.snapshot.speedMultiplier, 3);
  expect(game.timeScale, 3);
});

test('pause freezes time scale and resume restores selected speed', () {
  final game = OrionDefenseGame();

  game.setSpeedMultiplier(3);
  game.startWave();
  game.togglePause();

  expect(game.snapshot.isPaused, isTrue);
  expect(game.timeScale, 0);

  game.togglePause();

  expect(game.snapshot.isPaused, isFalse);
  expect(game.timeScale, 3);
});

test('toggleAutoStart updates snapshot and clears countdown when disabled', () {
  final game = OrionDefenseGame();

  game.toggleAutoStart();
  expect(game.snapshot.autoStartEnabled, isTrue);

  game.toggleAutoStart();
  expect(game.snapshot.autoStartEnabled, isFalse);
  expect(game.snapshot.autoStartCountdownRemaining, isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name "pacing|speed|pause|toggleAutoStart"
```

Expected: FAIL with missing `timeScale`, `setSpeedMultiplier`, `togglePause`, and `toggleAutoStart` errors.

- [ ] **Step 3: Add `HasTimeScale` and pacing fields**

In `lib/game/orion_defense_game.dart`, add the Flame components import:

```dart
import 'package:flame/components.dart';
```

Change the class declaration to:

```dart
class OrionDefenseGame extends FlameGame with TapCallbacks, HasTimeScale {
```

Add these constants and fields near the existing spawn fields:

```dart
static const double defaultSpeedMultiplier = 1;
static const Set<double> supportedSpeedMultipliers = {1.0, 2.0, 3.0};
static const double autoStartCountdownSeconds = 3;

bool _isPaused = false;
double _speedMultiplier = defaultSpeedMultiplier;
bool _autoStartEnabled = false;
double? _autoStartCountdownRemaining;
```

Add these public read-only accessors near `GameSnapshot get snapshot`:

```dart
bool get isPaused => _isPaused;
double get speedMultiplier => _speedMultiplier;
bool get autoStartEnabled => _autoStartEnabled;
double? get autoStartCountdownRemaining => _autoStartCountdownRemaining;
```

- [ ] **Step 4: Add pacing mutation methods**

Add these methods after `returnToMap()` in `lib/game/orion_defense_game.dart`:

```dart
void togglePause() {
  if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
    return;
  }

  _isPaused = !_isPaused;
  _applyTimeScale();
  _publishSnapshot();
}

void setSpeedMultiplier(double multiplier) {
  if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
    return;
  }
  if (!supportedSpeedMultipliers.contains(multiplier)) {
    return;
  }

  _speedMultiplier = multiplier;
  _applyTimeScale();
  _publishSnapshot();
}

void toggleAutoStart() {
  if (_session.phase == GamePhase.won || _session.phase == GamePhase.lost) {
    return;
  }

  _autoStartEnabled = !_autoStartEnabled;
  if (!_autoStartEnabled) {
    _autoStartCountdownRemaining = null;
  }
  _publishSnapshot();
}
```

Add these private helpers near `_publishSnapshot()`:

```dart
void _applyTimeScale() {
  timeScale = _isPaused ? 0 : _speedMultiplier;
}

void _resetPacing() {
  _isPaused = false;
  _speedMultiplier = defaultSpeedMultiplier;
  _autoStartEnabled = false;
  _autoStartCountdownRemaining = null;
  _applyTimeScale();
}
```

- [ ] **Step 5: Publish pacing in snapshots**

Replace `_publishSnapshot()` with:

```dart
void _publishSnapshot({String? feedback}) {
  stateNotifier.value = _session.snapshot(
    selectedCell: _selectedCell,
    selectedTower: _selectedTower,
    feedback: feedback,
    isPaused: _isPaused,
    speedMultiplier: _speedMultiplier,
    autoStartEnabled: _autoStartEnabled,
    autoStartCountdownRemaining: _autoStartCountdownRemaining,
  );
}
```

- [ ] **Step 6: Run game pacing tests**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name "defaults to unpaused|sets supported speed|pause freezes|toggleAutoStart"
```

Expected: PASS for the new pacing state tests.

- [ ] **Step 7: Commit pacing state**

Run:

```bash
rtk git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
rtk git commit -m "feat: add Orion mission pacing state"
```

Expected: commit succeeds.

## Task 3: Scaled Spawn Timers and Auto-Start Countdown

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Test: `test/game/orion_defense_game_test.dart`

- [ ] **Step 1: Add countdown test stage helper**

At the bottom of `test/game/orion_defense_game_test.dart`, add this helper outside `main()`:

```dart
StageDefinition _emptyWaveStage({int waveCount = 2}) {
  return StageDefinition(
    id: 'empty-wave-stage',
    name: 'Empty Wave Stage',
    mapLabel: 'Empty',
    description: 'Stage with empty waves for timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      waveCount,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
```

- [ ] **Step 2: Write failing auto-start tests**

Add these tests inside the `OrionDefenseGame` group:

```dart
test('wave clear starts auto-start countdown when another wave remains', () {
  final game = OrionDefenseGame(stage: _emptyWaveStage());

  game.toggleAutoStart();
  game.startWave();
  game.onGameResize(Vector2(800, 1200));
  game.update(0);

  expect(game.snapshot.phase, GamePhase.build);
  expect(game.snapshot.waveNumber, 2);
  expect(game.snapshot.autoStartEnabled, isTrue);
  expect(game.snapshot.autoStartCountdownRemaining, 3);
});

test('auto-start countdown can be canceled by turning auto-start off', () {
  final game = OrionDefenseGame(stage: _emptyWaveStage());

  game.toggleAutoStart();
  game.startWave();
  game.onGameResize(Vector2(800, 1200));
  game.update(0);
  game.toggleAutoStart();

  expect(game.snapshot.autoStartEnabled, isFalse);
  expect(game.snapshot.autoStartCountdownRemaining, isNull);
  expect(game.snapshot.phase, GamePhase.build);
});

test('auto-start countdown starts next wave after scaled unpaused time', () {
  final game = OrionDefenseGame(stage: _emptyWaveStage());

  game.toggleAutoStart();
  game.setSpeedMultiplier(3);
  game.startWave();
  game.onGameResize(Vector2(800, 1200));
  game.update(0);

  game.update(1);

  expect(game.snapshot.phase, GamePhase.wave);
  expect(game.snapshot.waveNumber, 2);
  expect(game.snapshot.autoStartCountdownRemaining, isNull);
});

test('paused auto-start countdown does not advance', () {
  final game = OrionDefenseGame(stage: _emptyWaveStage());

  game.toggleAutoStart();
  game.startWave();
  game.onGameResize(Vector2(800, 1200));
  game.update(0);
  game.togglePause();

  game.update(10);

  expect(game.snapshot.phase, GamePhase.build);
  expect(game.snapshot.isPaused, isTrue);
  expect(game.snapshot.autoStartCountdownRemaining, 3);
});

test('restart resets pacing state', () {
  final game = OrionDefenseGame(stage: _emptyWaveStage());

  game.toggleAutoStart();
  game.setSpeedMultiplier(3);
  game.startWave();
  game.togglePause();

  game.restart();

  expect(game.snapshot.phase, GamePhase.build);
  expect(game.snapshot.isPaused, isFalse);
  expect(game.snapshot.speedMultiplier, 1);
  expect(game.snapshot.autoStartEnabled, isFalse);
  expect(game.snapshot.autoStartCountdownRemaining, isNull);
  expect(game.timeScale, 1);
});

test('won state resets pacing state', () {
  final game = OrionDefenseGame(stage: _emptyWaveStage(waveCount: 1));

  game.toggleAutoStart();
  game.setSpeedMultiplier(3);
  game.startWave();
  game.onGameResize(Vector2(800, 1200));
  game.update(0);

  expect(game.snapshot.phase, GamePhase.won);
  expect(game.snapshot.isPaused, isFalse);
  expect(game.snapshot.speedMultiplier, 1);
  expect(game.snapshot.autoStartEnabled, isFalse);
  expect(game.snapshot.autoStartCountdownRemaining, isNull);
  expect(game.timeScale, 1);
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart --name "auto-start|restart resets pacing|won state resets pacing"
```

Expected: FAIL because countdown logic, restart reset, and win reset have not been implemented.

- [ ] **Step 4: Add wave spawn reset and countdown helpers**

In `lib/game/orion_defense_game.dart`, add these helpers near `_spawnWaveEnemies()`:

```dart
void _resetWaveSpawnState() {
  _spawnTimer = 0;
  _spawnedCount = 0;
  _activeGroupIndex = 0;
  _spawnedInGroup = 0;
}

bool _tickAutoStartCountdown(double dt) {
  final remaining = _autoStartCountdownRemaining;
  if (remaining == null) {
    return false;
  }
  if (_session.phase != GamePhase.build) {
    _autoStartCountdownRemaining = null;
    _publishSnapshot();
    return false;
  }

  final nextRemaining = remaining - dt;
  if (nextRemaining > 0) {
    _autoStartCountdownRemaining = nextRemaining;
    _publishSnapshot();
    return false;
  }

  _autoStartCountdownRemaining = null;
  startWave();
  return true;
}

void _startAutoStartCountdownIfNeeded() {
  if (_autoStartEnabled && _session.phase == GamePhase.build) {
    _autoStartCountdownRemaining = autoStartCountdownSeconds;
  }
}
```

- [ ] **Step 5: Use scaled time in `update()`**

Replace `update(double dt)` with:

```dart
@override
void update(double dt) {
  super.update(dt);
  _removeInactiveEnemyReferences();

  if (_isPaused) {
    return;
  }

  final scaledDt = dt * _speedMultiplier;
  if (scaledDt > 0 && _tickAutoStartCountdown(scaledDt)) {
    return;
  }

  if (_session.phase != GamePhase.wave) {
    return;
  }

  if (scaledDt > 0) {
    _spawnWaveEnemies(scaledDt);
  }
  _removeInactiveEnemyReferences();
  _finishWaveIfComplete();
}
```

This preserves existing empty-wave tests because `_finishWaveIfComplete()` still runs on unpaused `dt == 0` updates.

- [ ] **Step 6: Reset wave spawn state in existing flows**

In `startWave()`, replace the repeated spawn reset assignments with:

```dart
_autoStartCountdownRemaining = null;
_resetWaveSpawnState();
```

The full method should read:

```dart
void startWave() {
  if (!_session.startWave()) {
    _publishSnapshot(feedback: 'Wave cannot start right now.');
    return;
  }

  _autoStartCountdownRemaining = null;
  _resetWaveSpawnState();
  _clearSelection();
  _publishSnapshot();
}
```

In `restart()`, replace the repeated spawn reset assignments with `_resetWaveSpawnState();` and call `_resetPacing();` before `_publishSnapshot()`:

```dart
void restart() {
  _clearCombatComponents(removeTowers: true);
  _resetWaveSpawnState();
  _nextEnemyId = 1;
  _clearSelection();
  _session.restart();
  _resetPacing();
  _layoutBoard(size);
  _publishSnapshot();
}
```

- [ ] **Step 7: Reset pacing on loss and start countdown after wave clear**

In `_handleEnemyReachedBase()`, inside the `if (_session.phase == GamePhase.lost)` block, replace repeated spawn reset assignments with `_resetWaveSpawnState();` and add `_resetPacing();`:

```dart
if (_session.phase == GamePhase.lost) {
  _clearCombatComponents(removeTowers: false);
  _resetWaveSpawnState();
  _resetPacing();
  _layoutBoard(size);
}
```

Replace `_finishWaveIfComplete()` with:

```dart
void _finishWaveIfComplete() {
  final wave = _session.activeWave;
  if (wave == null) {
    return;
  }
  if (_spawnedCount < wave.enemyCount || _activeEnemyComponents.isNotEmpty) {
    return;
  }

  _session.finishActiveWave();
  final didWin = _session.phase == GamePhase.won;
  _resetWaveSpawnState();
  if (didWin) {
    _resetPacing();
  } else {
    _startAutoStartCountdownIfNeeded();
  }
  _layoutBoard(size);
  _publishSnapshot();
  if (didWin) {
    onStageWon?.call(stage);
  }
}
```

- [ ] **Step 8: Run auto-start and existing game tests**

Run:

```bash
rtk flutter test test/game/orion_defense_game_test.dart
```

Expected: PASS for all `OrionDefenseGame` tests.

- [ ] **Step 9: Commit countdown and scaled time**

Run:

```bash
rtk git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
rtk git commit -m "feat: add Orion auto-start countdown"
```

Expected: commit succeeds.

## Task 4: Bottom Pacing Controls

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Write failing widget control test**

In `test/widget_test.dart`, add this test near the existing unlocked-stage launch test:

```dart
testWidgets('mission screen exposes pause speed and auto-start controls', (
  tester,
) async {
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(const OrionApp());
  await tester.pumpAndSettle();

  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();

  expect(find.byTooltip('Pause'), findsOneWidget);
  expect(find.text('1x'), findsOneWidget);
  expect(find.text('2x'), findsOneWidget);
  expect(find.text('3x'), findsOneWidget);
  expect(find.byTooltip('Auto-start waves'), findsOneWidget);
  expect(find.text('Start Wave'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
rtk flutter test test/widget_test.dart --name "mission screen exposes pause speed and auto-start controls"
```

Expected: FAIL because the new controls do not exist.

- [ ] **Step 3: Update bottom controls layout**

In `lib/game/ui/orion_game_page.dart`, replace the final `return Row(...)` branch in `_BottomControls._content()` with:

```dart
return Column(
  key: const ValueKey('start-wave'),
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _PacingControls(game: game, snapshot: snapshot),
    const SizedBox(height: 10),
    Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'World Map',
          onPressed: snapshot.phase == GamePhase.wave
              ? null
              : game.returnToMap,
          icon: const Icon(Icons.map),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: snapshot.canStartWave ? game.startWave : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              snapshot.autoStartCountdownRemaining == null
                  ? 'Start Wave'
                  : 'Start Now',
            ),
          ),
        ),
      ],
    ),
  ],
);
```

- [ ] **Step 4: Add `_PacingControls` widget**

Add this widget after `_BottomControls` and before `_TowerPicker`:

```dart
class _PacingControls extends StatelessWidget {
  const _PacingControls({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final canUsePacing = !snapshot.isEnded;
    final canTogglePause =
        canUsePacing &&
        (snapshot.phase == GamePhase.wave ||
            snapshot.autoStartCountdownRemaining != null ||
            snapshot.isPaused);
    final countdown = snapshot.autoStartCountdownRemaining;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: snapshot.isPaused ? 'Resume' : 'Pause',
          onPressed: canTogglePause ? game.togglePause : null,
          icon: Icon(snapshot.isPaused ? Icons.play_arrow : Icons.pause),
        ),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<double>(value: 1.0, label: Text('1x')),
            ButtonSegment<double>(value: 2.0, label: Text('2x')),
            ButtonSegment<double>(value: 3.0, label: Text('3x')),
          ],
          selected: {snapshot.speedMultiplier},
          onSelectionChanged: canUsePacing
              ? (selection) => game.setSpeedMultiplier(selection.single)
              : null,
        ),
        FilterChip(
          tooltip: 'Auto-start waves',
          label: const Text('Auto'),
          selected: snapshot.autoStartEnabled,
          onSelected: canUsePacing ? (_) => game.toggleAutoStart() : null,
        ),
        if (countdown != null)
          _StatusChip(label: 'Next ${countdown.ceil()}s'),
      ],
    );
  }
}
```

- [ ] **Step 5: Run widget control test**

Run:

```bash
rtk flutter test test/widget_test.dart --name "mission screen exposes pause speed and auto-start controls"
```

Expected: PASS.

- [ ] **Step 6: Commit UI controls**

Run:

```bash
rtk git add lib/game/ui/orion_game_page.dart test/widget_test.dart
rtk git commit -m "feat: add Orion pacing controls"
```

Expected: commit succeeds.

## Task 5: Full Verification

**Files:**
- Verify all modified Dart files.

- [ ] **Step 1: Format the repository**

Run:

```bash
rtk dart format .
```

Expected: command exits 0 and reports formatted files or no changes.

- [ ] **Step 2: Run static analysis**

Run:

```bash
rtk flutter analyze
```

Expected: command exits 0 with no analyzer issues.

- [ ] **Step 3: Run full test suite**

Run:

```bash
rtk flutter test
```

Expected: command exits 0 with all tests passing.

- [ ] **Step 4: Inspect git diff**

Run:

```bash
rtk git status --short
rtk git diff --stat
```

Expected: only intended implementation files are modified, or the worktree is clean if Task 1 through Task 4 commits were already made.

- [ ] **Step 5: Commit formatting-only changes if needed**

If `dart format .` changed files after the Task 4 commit, run:

```bash
rtk git add lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart test/game/game_session_test.dart test/game/orion_defense_game_test.dart test/widget_test.dart
rtk git commit -m "chore: format Orion pacing controls"
```

Expected: commit succeeds only when formatting produced changes.
