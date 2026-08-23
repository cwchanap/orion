# Selected-State Pacing Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore full board reachability during cell and tower selection by showing pacing controls only in the unselected command-dock state.

**Architecture:** Keep `MissionCommandDock` responsible for choosing idle, build, or inspector content. Gate the page-level `MissionPacingStrip` and its vertical gap from the same snapshot selection state, without changing pacing callbacks, tap arbitration, or game logic.

**Tech Stack:** Flutter, Dart 3.12, Flutter widget tests, Flame game host

## Global Constraints

- Hide pacing whenever either `snapshot.selectedCell` or `snapshot.selectedTower` is non-null, in every game phase.
- Restore pacing when both selection fields are null.
- Keep existing pacing callbacks and idle-state tap forwarding unchanged.
- Do not change scanner, dock-content, game-state, or board-tap arbitration behavior.

---

### Task 1: Gate Pacing Controls by Selection State

**Files:**
- Modify: `test/widget_test.dart:671-715`
- Modify: `lib/game/ui/orion_game_page.dart:414-440`

**Interfaces:**
- Consumes: `GameSnapshot.selectedCell`, `GameSnapshot.selectedTower`, `MissionPacingStrip`, and the existing `MissionCommandDock` content keys.
- Produces: Page-level widget behavior where `MissionPacingStrip` exists only when both selection fields are null.

- [ ] **Step 1: Write the failing widget regression test**

Add this test beside the existing mission pacing widget tests in `test/widget_test.dart`:

```dart
  testWidgets('selection replaces pacing with build or inspector controls', (
    tester,
  ) async {
    OrionDefenseGame? game;
    await tester.pumpWidget(
      testGamePage(onGameCreated: (created) => game = created),
    );
    await tester.pumpAndSettle();
    await startStageFromBriefing(tester);

    expect(find.byType(MissionPacingStrip), findsOneWidget);
    expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);

    game!.stateNotifier.value = commandDeckSnapshot(
      selectedCell: const GridPosition(1, 1),
    );
    await tester.pump();

    expect(find.byType(MissionPacingStrip), findsNothing);
    expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

    final tower = const PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(1, 1),
    );
    game!.stateNotifier.value = commandDeckSnapshot(
      selectedTower: tower,
      selectedTowerStats: GameBalance.towerStats(
        tower.type,
        level: tower.level,
      ),
    );
    await tester.pump();

    expect(find.byType(MissionPacingStrip), findsNothing);
    expect(find.byKey(const ValueKey('command-dock-tower')), findsOneWidget);
  });
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/widget_test.dart --plain-name 'selection replaces pacing with build or inspector controls'
```

Expected: FAIL on the selected-cell assertion because `MissionPacingStrip` is still found once.

- [ ] **Step 3: Implement the minimal visibility gate**

Replace the unconditional pacing widgets in `lib/game/ui/orion_game_page.dart` with a collection-if that gates both the strip and its gap:

```dart
                      if (snapshot.selectedCell == null &&
                          snapshot.selectedTower == null) ...[
                        GestureDetector(
                          onTapUp: (details) =>
                              _routeTapToBoard(details.globalPosition),
                          child: MissionPacingStrip(
                            snapshot: snapshot,
                            onTogglePause: game.togglePause,
                            onSpeedSelected: game.setSpeedMultiplier,
                            onToggleAutoStart: game.toggleAutoStart,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
```

Update the existing bottom-overlay comment to state that pacing is interactive only while no cell or tower is selected and that selection replaces it with build or inspector controls. Do not change `_routeTapToBoard`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
flutter test test/widget_test.dart --plain-name 'selection replaces pacing with build or inspector controls'
```

Expected: PASS.

- [ ] **Step 5: Run related widget regressions**

Run:

```bash
flutter test test/widget_test.dart
flutter test test/widget/mission_command_hud_test.dart test/widget/mission_command_dock_test.dart
```

Expected: All tests pass, including idle pacing controls, pacing dead-space forwarding, and command-dock state switching.

- [ ] **Step 6: Format and analyze**

Run:

```bash
dart format lib/game/ui/orion_game_page.dart test/widget_test.dart
flutter analyze
```

Expected: Formatting reports no remaining changes after the first pass, and analysis reports `No issues found!`.

- [ ] **Step 7: Review the final diff and commit**

Run:

```bash
git diff --check
git diff -- lib/game/ui/orion_game_page.dart test/widget_test.dart
git add lib/game/ui/orion_game_page.dart test/widget_test.dart docs/superpowers/plans/2026-08-22-selected-state-pacing-visibility.md
git commit -m "fix: hide pacing controls during selection"
```

Expected: The diff contains only the regression test, the selection visibility gate, the corrected overlay comment, and this implementation plan; the commit succeeds.
