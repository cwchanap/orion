# Tower Sell and Refund Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players sell a selected placed tower during build phase for a 70% gold refund (integer math), removing the tower, its live drones, and clearing selection.

**Architecture:** Follows Orion's existing upgrade/specialize wiring exactly. A pure `GameBalance.refundValue` computes the refund from the tower's invested gold (derivable from `type`/`level`/`specialization`, no new persistent field). `GameSession.sellTower` mutates session state; `OrionDefenseGame.sellSelectedTower` syncs the Flame component tree (removes the `TowerComponent`, despawns the tower's `DroneComponent`s) and publishes a snapshot; the selected-tower panel renders a Sell button from the snapshot.

**Tech Stack:** Flutter + Flame (`flame: ^1.37.0`), Dart SDK `^3.12.0`. Tests via `flutter test`.

## Global Constraints

- Refund uses **integer arithmetic** only: `invested * sellRefundPercent ~/ 100` where `sellRefundPercent` is `static const int = 70`. Never a `double` rate — `(invested * 0.70).floor()` is wrong for 90/180/330 (verified: yields 62/125/230 instead of 63/126/231).
- Sell is **build-phase-gated only** (like `upgradeTower`/`specializeTower`). The Sell button's enabled condition is phase-only — selling grants gold, so it deliberately does NOT mirror upgrade's `gold >= cost` check.
- The existing Upgrade/Specialize/Max branch bodies in `_UpgradeActions` are reused **verbatim** (preserving the `canUpgrade` gate `phase == build && tower.canUpgrade && gold >= upgradeCost`); the refactor only wraps them.
- Tower types unlock by global wave (`towerUnlockWave`); `droneBay` unlocks at wave 6. To exercise a drone bay in tests you must advance to wave 6 first (see Task 3 helper).
- Naming/copy: refund feedback string is exactly `'Sold for $refund gold.'`; no-selection feedback `'Select a tower first.'`; wrong-phase feedback `'Sell towers between waves.'`.
- Widget tests live in `test/widget/` (the repo's only existing widget test is `test/widget_test.dart`; there is no `test/game/ui/` directory, and `test/game/` is reserved for the pure logic layer).
- After every task: `flutter analyze` is clean and `flutter test` passes. Commit per task.

---

## Task 1: `GameBalance.refundValue` + `sellRefundPercent`

**Files:**
- Modify: `lib/game/models/game_models.dart` (add `sellRefundPercent` constant near line 402; add `refundValue` static method inside `GameBalance`)
- Test: `test/game/game_balance_test.dart` (add a `refundValue` test inside the existing `GameBalance` group)

**Interfaces:**
- Produces: `GameBalance.sellRefundPercent` (`static const int`), `GameBalance.refundValue(PlacedTower tower) -> int`. Consumed by Task 2 (`GameSession.sellTower`) and Task 4 (UI label).

- [ ] **Step 1: Write the failing test**

Add inside the `group('GameBalance', () { ... })` block in `test/game/game_balance_test.dart` (e.g. after the `towerStats`-related tests):

```dart
test('refundValue returns 70 percent of invested gold, truncated', () {
  // Level 1 base values.
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
    )),
    35,
  );
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.rocket,
      position: GridPosition(0, 0),
    )),
    56,
  );
  // Float regression: 90 * 0.7 floors to 62; integer math yields 63.
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.nanite,
      position: GridPosition(0, 0),
    )),
    63,
  );

  // Level 2 adds the upgrade cost.
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
      level: 2,
    )),
    84,
  );

  // Level 3 specialized adds the specialization cost.
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
      level: 3,
      specialization: TowerSpecialization.pulseLaser,
    )),
    168,
  );
  // Float regression: 330 total -> 231 (not 230).
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.rocket,
      position: GridPosition(0, 0),
      level: 3,
      specialization: TowerSpecialization.siegeRocket,
    )),
    231,
  );
  // Truncation: 415 * 70 ~/ 100 = 290 (the .5 is dropped).
  expect(
    GameBalance.refundValue(const PlacedTower(
      id: 1,
      type: TowerType.ionChain,
      position: GridPosition(0, 0),
      level: 3,
      specialization: TowerSpecialization.stormRelay,
    )),
    290,
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/game/game_balance_test.dart --plain-name "refundValue returns 70 percent of invested gold"`
Expected: FAIL — `GameBalance.refundValue` is not defined (compile error: method not found).

- [ ] **Step 3: Implement `refundValue` and the constant**

In `lib/game/models/game_models.dart`:

First add the constant inside `GameBalance`, directly after the existing economy constants (after `silverMedalThreshold`, around line 402):

```dart
// Fraction of invested gold refunded when a tower is sold, as a percent.
static const int sellRefundPercent = 70;
```

Then add the `refundValue` static method inside `GameBalance` (place it immediately before the private `_towerCosts` method, since it reads costs). It reads all three cost fields from the level-1 stats (which always carry every cost), so it never throws on a level/specialization combination:

```dart
/// Gold refunded when selling [tower]: 70% of everything invested, truncated.
static int refundValue(PlacedTower tower) {
  final base = towerStats(tower.type, level: 1);
  var invested = base.cost;
  if (tower.level >= 2) {
    invested += base.upgradeCost;
  }
  if (tower.level == 3) {
    invested += base.specializationCost;
  }
  return invested * sellRefundPercent ~/ 100;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/game/game_balance_test.dart --plain-name "refundValue returns 70 percent of invested gold"`
Expected: PASS.

- [ ] **Step 5: Verify the whole suite and analyze**

Run: `flutter analyze` then `flutter test`
Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: add GameBalance.refundValue for tower sell refunds (HPA-98)"
```

---

## Task 2: `GameSession.sellTower`

**Files:**
- Modify: `lib/game/rules/game_session.dart` (add `sellTower` method)
- Test: `test/game/game_session_test.dart` (add a `sellTower` test group)

**Interfaces:**
- Consumes: `GameBalance.refundValue(PlacedTower) -> int` (from Task 1).
- Produces: `GameSession.sellTower(int towerId) -> int?` (the refund, or `null` when rejected). Consumed by Task 3.

- [ ] **Step 1: Write the failing tests**

Add a new test inside the `group('GameSession', () { ... })` block in `test/game/game_session_test.dart` (near the existing upgrade/specialize tests):

```dart
test('sells a placed tower, refunds 70 percent, and frees the cell', () {
  final session = GameSession.initial(gold: 200);
  session.placeTower(const GridPosition(0, 0), TowerType.laser);
  final tower = session.towers.single;
  expect(session.gold, 150); // 200 - 50

  final refund = session.sellTower(tower.id);

  expect(refund, 35); // 70% of 50
  expect(session.gold, 185); // 150 + 35
  expect(session.towers, isEmpty);

  // The cell is free for re-placement.
  final replace = session.placeTower(
    const GridPosition(0, 0),
    TowerType.cryo,
  );
  expect(replace.isAllowed, isTrue);
});

test('sellTower refunds upgraded and specialized investment', () {
  final session = GameSession.initial(gold: 500);
  session.placeTower(const GridPosition(0, 0), TowerType.laser);
  final tower = session.towers.single;
  session.upgradeTower(tower.id);
  session.specializeTower(tower.id, TowerSpecialization.pulseLaser);

  final refund = session.sellTower(session.towers.single.id);

  expect(refund, 168); // 70% of 50 + 70 + 120 = 240
  expect(session.towers, isEmpty);
});

test('sellTower returns null during an active wave and keeps the tower', () {
  final session = GameSession.initial(gold: 200);
  session.placeTower(const GridPosition(0, 0), TowerType.laser);
  final tower = session.towers.single;
  expect(session.startWave(), isTrue);

  expect(session.sellTower(tower.id), isNull);
  expect(session.towers, hasLength(1));
  expect(session.gold, 150); // unchanged
});

test('sellTower returns null for an unknown tower id', () {
  final session = GameSession.initial(gold: 200);

  expect(session.sellTower(999), isNull);
  expect(session.gold, 200);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/game/game_session_test.dart --plain-name "sell"`
Expected: 4 FAIL — `sellTower` is not defined (method not found).

- [ ] **Step 3: Implement `sellTower`**

In `lib/game/rules/game_session.dart`, add the method to `GameSession`. Place it directly after `specializeTower` (after line ~180) so it sits with its sibling build-phase mutators. It mirrors their shape: same build-phase gate, same `_findTowerEntry` helper, same direct `_gold` mutation. It returns `int?` (the refund, or `null` when rejected):

```dart
int? sellTower(int towerId) {
  if (_phase != GamePhase.build) {
    return null;
  }
  final entry = _findTowerEntry(towerId);
  if (entry == null) {
    return null;
  }
  final refund = GameBalance.refundValue(entry.value);
  _towersByPosition.remove(entry.key);
  _gold += refund;
  return refund;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/game/game_session_test.dart --plain-name "sell"`
Expected: 4 PASS.

- [ ] **Step 5: Verify the whole suite and analyze**

Run: `flutter analyze` then `flutter test`
Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: add GameSession.sellTower with refund (HPA-98)"
```

---

## Task 3: `OrionDefenseGame.sellSelectedTower` (component + drone cleanup)

**Files:**
- Modify: `lib/game/orion_defense_game.dart` (add `sellSelectedTower`; the file already imports `DroneComponent` at line 17)
- Test: `test/game/orion_defense_game_test.dart` (add a `sellSelectedTower` group + a `_droneBayUnlockStage` helper; the file already imports `TowerComponent`-adjacent types — add imports for `TowerComponent` and `DroneComponent`)

**Interfaces:**
- Consumes: `GameSession.sellTower(int) -> int?` (from Task 2), `GameBalance.refundValue` (Task 1, for the UI), the existing `_towerComponents`, `_activeDronesByTower`, `_clearSelection`, `_publishSnapshot`, `DroneComponent.ownerTowerId`.
- Produces: `OrionDefenseGame.sellSelectedTower() -> void`. Consumed by Task 4 (the Sell button's `onPressed`).

**Background the implementer must know:**
- The Flame game test harness uses `game.onGameResize(Vector2(800, 1200))` to lay out the board (cell size 100, origin zero) and `_tapCell(game, GridPosition)` / `_tapPoint` helpers already defined at the bottom of the test file.
- A `DroneComponent` carries `ownerTowerId` (public); `TowerComponent` and `GravityFieldComponent` do NOT. This task only cleans towers + drones (projectiles/fields self-expire and are inert in build phase — see spec).
- `droneBay` unlocks at wave 6, so the drone-despawn test advances 5 empty waves first (helper below).

- [ ] **Step 1: Write the failing tests**

In `test/game/orion_defense_game_test.dart`, first add the two missing imports at the top (alongside the existing `enemy_component.dart` import):

```dart
import 'package:orion/game/components/drone_component.dart';
import 'package:orion/game/components/tower_component.dart';
```

Add these tests inside the `group('OrionDefenseGame', () { ... })` block (near the `setTargetingMode` tests at the end of the group, before the closing `});`):

```dart
test('sellSelectedTower removes the component, clears selection, refunds', () {
  final game = OrionDefenseGame(stage: _singleEnemyStage());
  game.onGameResize(Vector2(800, 1200));
  _tapCell(game, const GridPosition(0, 1));
  game.placeTower(TowerType.laser);
  game.processLifecycleEvents();
  _tapCell(game, const GridPosition(0, 1)); // select the placed tower
  game.processLifecycleEvents();
  expect(game.snapshot.selectedTower, isNotNull);
  expect(game.children.whereType<TowerComponent>(), hasLength(1));

  game.sellSelectedTower();
  game.processLifecycleEvents();

  expect(game.children.whereType<TowerComponent>(), isEmpty);
  expect(game.snapshot.selectedTower, isNull);
  expect(game.snapshot.feedback, 'Sold for 35 gold.');
  expect(game.snapshot.gold, GameBalance.startingGold - 50 + 35);
});

test('sellSelectedTower with no selection reports feedback', () {
  final game = OrionDefenseGame(stage: _singleEnemyStage());
  game.onGameResize(Vector2(800, 1200));

  game.sellSelectedTower();

  expect(game.snapshot.feedback, 'Select a tower first.');
});

test('sellSelectedTower is denied during an active wave', () {
  final game = OrionDefenseGame(stage: _singleEnemyStage());
  game.onGameResize(Vector2(800, 1200));
  _tapCell(game, const GridPosition(0, 1));
  game.placeTower(TowerType.laser);
  game.processLifecycleEvents();
  game.startWave();
  _tapCell(game, const GridPosition(0, 1)); // re-select during wave
  game.processLifecycleEvents();
  expect(game.snapshot.selectedTower, isNotNull);

  game.sellSelectedTower();
  game.processLifecycleEvents();

  expect(game.snapshot.feedback, 'Sell towers between waves.');
  expect(game.children.whereType<TowerComponent>(), hasLength(1));
});

test('sellSelectedTower despawns a sold drone bay live drones', () {
  final game = OrionDefenseGame(stage: _droneBayUnlockStage());
  game.onGameResize(Vector2(800, 1200));

  // Advance 5 empty waves so the drone bay (unlocks at wave 6) is available.
  for (var wave = 0; wave < 5; wave += 1) {
    game.startWave();
    game.update(0);
    game.processLifecycleEvents();
  }
  expect(game.snapshot.phase, GamePhase.build);
  expect(
    game.snapshot.unlockedTowerTypes,
    contains(TowerType.droneBay),
  );

  // Place the drone bay adjacent to the wave-6 path and run that wave.
  _tapCell(game, const GridPosition(0, 1));
  game.placeTower(TowerType.droneBay);
  game.processLifecycleEvents();
  expect(game.children.whereType<TowerComponent>(), hasLength(1));

  game.startWave(); // wave 6: one durable enemy
  game.update(0.01); // spawn the enemy
  game.processLifecycleEvents();
  game.update(0.01); // tower update acquires target and launches drones
  game.processLifecycleEvents();

  final dronesBefore = game.children.whereType<DroneComponent>().toList();
  expect(dronesBefore, isNotEmpty); // guards against a vacuous pass

  // End the wave (sell is build-phase only) by resolving the enemy.
  final enemy = game.children.whereType<EnemyComponent>().single;
  enemy.applyDamage(10000);
  game.update(0.01);
  game.processLifecycleEvents();
  expect(game.snapshot.phase, GamePhase.build);

  final droneBayId = game.snapshot.selectedTower?.id;
  expect(droneBayId, isNull); // not selected yet

  _tapCell(game, const GridPosition(0, 1)); // select the drone bay
  game.processLifecycleEvents();
  final ownerTowerId = game.snapshot.selectedTower!.id;

  game.sellSelectedTower();
  game.processLifecycleEvents();

  expect(
    game.children.whereType<DroneComponent>().where(
      (d) => d.ownerTowerId == ownerTowerId,
    ),
    isEmpty,
  );
  expect(game.children.whereType<TowerComponent>(), isEmpty);
});
```

**Step 1b: add the stage helper.** The helper goes at the bottom of the file (next to the other `_…Stage()` helpers, before `_tapCell`):

```dart
/// Stage whose first 5 waves are empty (to unlock the wave-6 drone bay) and
/// whose 6th wave spawns a single durable enemy for drone-launch tests.
StageDefinition _droneBayUnlockStage() {
  return StageDefinition(
    id: 'drone-bay-unlock-stage',
    name: 'Drone Bay Unlock Stage',
    mapLabel: 'Drone',
    description: 'Stage that unlocks the drone bay for sell tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: [
      for (var wave = 0; wave < 5; wave += 1)
        const WaveDefinition(groups: [], clearBonus: 0),
      const WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: EnemyStats(
              health: 10000,
              speed: 1,
              baseDamage: 1,
              goldReward: 0,
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/game/orion_defense_game_test.dart --plain-name "sellSelectedTower"`
Expected: 4 FAIL — `sellSelectedTower` is not defined (method not found). (The drone test may also fail at compile time until the helper exists — that's expected.)

- [ ] **Step 3: Implement `sellSelectedTower`**

In `lib/game/orion_defense_game.dart`, add the method to `OrionDefenseGame`. Place it directly after `specializeSelectedTower` (after line ~223), mirroring that method's structure. It removes the `TowerComponent`, despawns the tower's live `DroneComponent`s (filtered by `ownerTowerId`), clears the drone bookkeeping, clears selection, and publishes the refund feedback:

```dart
void sellSelectedTower() {
  final tower = _selectedTower;
  if (tower == null) {
    _publishSnapshot(feedback: 'Select a tower first.');
    return;
  }

  final refund = _session.sellTower(tower.id);
  if (refund == null) {
    _publishSnapshot(feedback: 'Sell towers between waves.');
    return;
  }

  final component = _towerComponents.remove(tower.id);
  component?.removeFromParent();
  for (final drone
      in children
          .whereType<DroneComponent>()
          .where((drone) => drone.ownerTowerId == tower.id)
          .toList()) {
    drone.removeFromParent();
  }
  _activeDronesByTower.remove(tower.id);
  _clearSelection();
  _publishSnapshot(feedback: 'Sold for $refund gold.');
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/game/orion_defense_game_test.dart --plain-name "sellSelectedTower"`
Expected: 4 PASS.

If the drone test fails on `expect(dronesBefore, isNotEmpty)` (no drone launched), the tower's first fire didn't land within the two `update(0.01)` calls. Add one more `game.update(0.01); game.processLifecycleEvents();` pair before the `dronesBefore` assertion until drones are present. Do not weaken the assertion — it must prove drones existed before sell.

- [ ] **Step 5: Verify the whole suite and analyze**

Run: `flutter analyze` then `flutter test`
Expected: analyze clean, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: add sellSelectedTower with drone despawn (HPA-98)"
```

---

## Task 4: Sell button in the selected-tower panel

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart` (refactor `_UpgradeActions.build` to wrap the existing action in a `Wrap` with a Sell button)
- Test: Create `test/widget/sell_button_test.dart`

**Interfaces:**
- Consumes: `OrionDefenseGame.sellSelectedTower()` (Task 3), `GameBalance.refundValue(PlacedTower)` (Task 1), the existing `_UpgradeActions` widget and its `game`/`snapshot`/`tower`/`stats`/`canUpgrade`/`alignment` fields.
- Produces: a rendered Sell button in the selected-tower panel for every tower level.

**Background the implementer must know:**
- The existing `_UpgradeActions.build` returns one of: a bare `FilledButton.icon` (Upgrade branch), a `Wrap` of specialization chips (Specialize branch), or a bare `FilledButton.icon` (Max branch). The refactor assigns the chosen widget to a local `primary`, then returns a single `Wrap(children: [primary, sellButton])`. The Upgrade and Max branches thereby *gain* a `Wrap` wrapper they did not have before — that is intended and is exactly what the narrow-layout widget test verifies.
- The Upgrade branch's `onPressed` uses the passed-in `canUpgrade` (`phase == build && tower.canUpgrade && gold >= upgradeCost`). It MUST stay exactly as-is.
- The widget-test pattern (driving the panel via a faked `stateNotifier.value` snapshot) is established in `test/widget_test.dart` (see its targeting-mode tests). We replicate it here in a new file.

- [ ] **Step 1: Write the failing widget tests**

Create `test/widget/sell_button_test.dart`. The pump helper rebuilds the panel from a faked snapshot (the real game session has no placed tower, so tapping Sell yields the "Select a tower first." feedback — proving the callback ran, same technique as `widget_test.dart`'s targeting tap test):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/ui/orion_game_page.dart';

void main() {
  testWidgets('Sell button shows the refund for a level-1 laser', (tester) async {
    final game = await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    expect(game!.snapshot.phase, GamePhase.build);
    expect(find.text('Sell +35'), findsOneWidget);
  });

  testWidgets('Sell button is enabled during build phase', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    final sellButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Sell +35'), matching: find.byType(FilledButton)),
    );
    expect(sellButton.onPressed, isNotNull);
  });

  testWidgets('Sell button is disabled during an active wave', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
      phase: GamePhase.wave,
    );

    final sellButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Sell +35'), matching: find.byType(FilledButton)),
    );
    expect(sellButton.onPressed, isNull);
  });

  testWidgets('tapping Sell invokes game.sellSelectedTower', (tester) async {
    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    await tester.tap(find.text('Sell +35'));
    await tester.pump();

    // The faked snapshot has a selectedTower but the real session has none, so
    // sellSelectedTower reports the no-selection feedback — proving the tap ran.
    expect(find.text('Select a tower first.'), findsOneWidget);
  });

  testWidgets('Sell button renders without overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpStageWithSelectedTower(
      tester,
      const PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      ),
    );

    expect(find.text('Sell +35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Pumps [OrionGamePage], enters the first stage, and drives the panel with a
/// faked snapshot carrying [selectedTower]. Returns the captured game.
Future<OrionDefenseGame?> _pumpStageWithSelectedTower(
  WidgetTester tester,
  PlacedTower selectedTower, {
  GamePhase phase = GamePhase.build,
}) async {
  OrionDefenseGame? game;

  await tester.pumpWidget(
    MaterialApp(home: OrionGamePage(onGameCreated: (created) => game = created)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();

  final snapshot = game!.stateNotifier.value;
  game!.stateNotifier.value = GameSnapshot(
    phase: phase,
    gold: snapshot.gold,
    baseHealth: snapshot.baseHealth,
    waveNumber: snapshot.waveNumber,
    waveTotal: snapshot.waveTotal,
    stageId: snapshot.stageId,
    stageName: snapshot.stageName,
    stageLabel: snapshot.stageLabel,
    unlockedTowerTypes: snapshot.unlockedTowerTypes,
    nextWavePreview: snapshot.nextWavePreview,
    selectedCell: snapshot.selectedCell,
    selectedTower: selectedTower,
    feedback: snapshot.feedback,
    isPaused: snapshot.isPaused,
    speedMultiplier: snapshot.speedMultiplier,
    autoStartEnabled: snapshot.autoStartEnabled,
    autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
  );
  await tester.pump();

  return game;
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/sell_button_test.dart`
Expected: FAIL — `find.text('Sell +35')` finds nothing (the Sell button does not exist yet).

- [ ] **Step 3: Refactor `_UpgradeActions.build` to add the Sell button**

In `lib/game/ui/orion_game_page.dart`, in `_UpgradeActions.build` (around lines 874-913). Replace the method body so the existing branch's widget is assigned to a `primary` local and the whole thing is wrapped in a `Wrap` with a Sell button appended. The three branch bodies (Upgrade / Specialize / Max) are reused **verbatim** — only their `return` becomes `primary =`.

Replace the entire `Widget build(BuildContext context) { ... }` method of `_UpgradeActions` with:

```dart
@override
Widget build(BuildContext context) {
  final Widget primary;
  if (tower.canUpgrade) {
    primary = FilledButton.icon(
      onPressed: canUpgrade ? game.upgradeSelectedTower : null,
      icon: const Icon(Icons.upgrade),
      label: Text('Upgrade ${stats.upgradeCost}'),
    );
  } else if (tower.canSpecialize) {
    primary = Wrap(
      alignment: alignment,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final specialization in GameBalance.specializationsFor(
          tower.type,
        ))
          FilledButton.tonalIcon(
            onPressed:
                snapshot.phase == GamePhase.build &&
                    snapshot.gold >= stats.specializationCost
                ? () => game.specializeSelectedTower(specialization)
                : null,
            icon: const Icon(Icons.call_split),
            label: Text(
              '${specialization.label} ${stats.specializationCost}',
            ),
          ),
      ],
    );
  } else {
    primary = FilledButton.icon(
      onPressed: null,
      icon: const Icon(Icons.check),
      label: const Text('Max'),
    );
  }

  return Wrap(
    alignment: alignment,
    spacing: 8,
    runSpacing: 8,
    children: [
      primary,
      FilledButton.tonalIcon(
        onPressed: snapshot.phase == GamePhase.build
            ? game.sellSelectedTower
            : null,
        icon: const Icon(Icons.sell),
        label: Text('Sell +${GameBalance.refundValue(tower)}'),
      ),
    ],
  );
}
```

Note the Sell button's `onPressed` is **phase-only** by design (`snapshot.phase == GamePhase.build ? game.sellSelectedTower : null`) — selling grants gold, so it intentionally does not check gold.

- [ ] **Step 4: Run the widget tests to verify they pass**

Run: `flutter test test/widget/sell_button_test.dart`
Expected: 5 PASS.

- [ ] **Step 5: Verify the whole suite and analyze**

Run: `flutter analyze` then `flutter test`
Expected: analyze clean, all tests pass (including the pre-existing `widget_test.dart` selected-tower-panel tests, which still pass because the Upgrade/Specialize/Max bodies are unchanged in behavior).

- [ ] **Step 6: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget/sell_button_test.dart
git commit -m "feat: add Sell button to the selected-tower panel (HPA-98)"
```

---

## Notes for the implementer

- The drone-despawn test (Task 3, test 4) is the most timing-sensitive. The `expect(dronesBefore, isNotEmpty)` precondition is mandatory — if it fails, add another `game.update(0.01); game.processLifecycleEvents();` cycle before it. Never delete or weaken that assertion; a vacuous pass would hide a real regression.
- Do not add `ownerTowerId` to `ProjectileComponent` or `GravityFieldComponent`. They self-expire (projectiles on impact/expiry, gravity fields on `_remaining <= 0`) and are inert in build phase. See the spec's "Projectiles and gravity fields are not despawned" note.
- The `Icons.sell` glyph exists in the Material icon set; if for any reason it is unavailable in the SDK in use, `Icons.sell_outlined` is an acceptable substitute (update the one literal only).
