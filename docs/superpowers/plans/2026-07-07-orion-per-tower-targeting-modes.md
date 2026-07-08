# Per-Tower Targeting Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each placed tower carry a player-selected targeting mode (First/Strongest/Weakest/Closest/Shielded/Armored) that changes how it picks targets during waves.

**Architecture:** Approach A from the design — add a `TowerTargetingMode` enum and a `targetingMode` field on `PlacedTower` (default `first`, preserved by upgrade/specialize); extend `TargetCandidate` with the live health/shield/trait data the new modes need (defaulted so existing call sites are untouched); add a `mode` parameter to the pure `TowerTargeting.selectTarget` ranker; wire `GameSession.setTargetingMode` → `OrionDefenseGame.setTargetingMode` → a build-phase choice-chip picker in the selected-tower panel. The pure-rules layer stays Flame-free and fully unit-testable; the UI reads only `GameSnapshot.selectedTower.targetingMode`.

**Tech Stack:** Flutter, Flame `^1.37.0`, Dart SDK `^3.12.0`, `flutter_test` for unit/widget tests.

**Spec:** [`docs/superpowers/specs/2026-07-07-orion-per-tower-targeting-modes-design.md`](../specs/2026-07-07-orion-per-tower-targeting-modes-design.md)

## Global Constraints

- Dart SDK `^3.12.0`; `flame: ^1.37.0`.
- Pure-rules boundary: `lib/game/rules/` and `lib/game/models/` must not import Flame. New ranking logic lives in `lib/game/rules/tower_targeting.dart`.
- UI reads state only via `GameSnapshot` — never pokes game internals. The picker reads `snapshot.selectedTower!.targetingMode`.
- Mode changes are allowed only in `GamePhase.build`; during waves the chips render read-only (disabled).
- No tower/enemy stat rebalance and no changes to `combat_effects.dart` chain/pierce selection.
- `TargetCandidate`'s new fields are **defaulted** so existing constructors in `combat_effects_test.dart` and `tower_targeting_test.dart` compile unchanged.
- Effective HP = `currentHealth + currentShield`. Trait modes fall back to `first` when no preferred-trait enemy is in range. Ties break by pathProgress desc, then id asc.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `lib/game/models/game_models.dart` | Add `TowerTargetingMode` enum; add `targetingMode` field + `copyWith` to `PlacedTower`; thread mode through `upgraded()`/`specialized()` | Modify |
| `lib/game/rules/tower_targeting.dart` | Extend `TargetCandidate` (health/shield/trait fields + `effectiveHealth`); add `mode` param to `selectTarget` with per-mode ranking + tie-breaks + fallback | Modify |
| `lib/game/rules/game_session.dart` | Add `setTargetingMode(int towerId, TowerTargetingMode mode)` with build-phase gate | Modify |
| `lib/game/components/enemy_component.dart` | Populate the new `TargetCandidate` fields from live `health`/`shield`/`stats.traits` | Modify |
| `lib/game/orion_defense_game.dart` | Add `setTargetingMode(TowerTargetingMode)`; pass `tower.placedTower.targetingMode` into `selectTarget` | Modify |
| `lib/game/ui/orion_game_page.dart` | Add `_TargetingModePicker` (choice chips) to `_UpgradePanel` | Modify |
| `test/game/placed_tower_test.dart` | PlacedTower default mode, copyWith, preservation across upgrade/specialize; enum labels | Create |
| `test/game/tower_targeting_test.dart` | Per-mode selection, tie-breaks, trait fallback | Modify |
| `test/game/game_session_test.dart` | `setTargetingMode` happy path, phase gate, unknown id, preservation, default | Modify |
| `test/widget_test.dart` | Picker renders all modes, reflects current mode, disabled during wave | Modify |

`combat_effects.dart`, `game_balance_test.dart`, and `combat_effects_test.dart` are intentionally untouched (the defaulted `TargetCandidate` fields keep them compiling).

---

## Task 1: `TowerTargetingMode` enum + `PlacedTower.targetingMode`

**Files:**
- Modify: `lib/game/models/game_models.dart` (enum near line 61 after `PlacementFailure`; `PlacedTower` at lines 275–326)
- Test: `test/game/placed_tower_test.dart` (Create)

**Interfaces:**
- Produces: `enum TowerTargetingMode { first, strongest, weakest, closest, shielded, armored }` with a `String label`; `PlacedTower.targetingMode` (default `TowerTargetingMode.first`); `PlacedTower.copyWith({TowerTargetingMode? targetingMode})`.

- [ ] **Step 1: Write the failing test**

Create `test/game/placed_tower_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('TowerTargetingMode', () {
    test('exposes human-readable labels', () {
      expect(TowerTargetingMode.first.label, 'First');
      expect(TowerTargetingMode.strongest.label, 'Strongest');
      expect(TowerTargetingMode.weakest.label, 'Weakest');
      expect(TowerTargetingMode.closest.label, 'Closest');
      expect(TowerTargetingMode.shielded.label, 'Shielded');
      expect(TowerTargetingMode.armored.label, 'Armored');
    });
  });

  group('PlacedTower targeting mode', () {
    test('defaults to First', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      );
      expect(tower.targetingMode, TowerTargetingMode.first);
    });

    test('copyWith changes only the targeting mode', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      );
      final retargeted = tower.copyWith(
        targetingMode: TowerTargetingMode.strongest,
      );
      expect(retargeted.targetingMode, TowerTargetingMode.strongest);
      expect(retargeted.id, 1);
      expect(retargeted.type, TowerType.laser);
      expect(retargeted.position, const GridPosition(0, 0));
      expect(retargeted.level, 1);
    });

    test('upgraded preserves the targeting mode', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        targetingMode: TowerTargetingMode.weakest,
      );
      expect(tower.upgraded().targetingMode, TowerTargetingMode.weakest);
    });

    test('specialized preserves the targeting mode', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        level: 2,
        targetingMode: TowerTargetingMode.closest,
      );
      final specialized = tower.specialized(TowerSpecialization.pulseLaser);
      expect(specialized.targetingMode, TowerTargetingMode.closest);
      expect(specialized.level, 3);
      expect(specialized.specialization, TowerSpecialization.pulseLaser);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/placed_tower_test.dart`
Expected: FAIL — `TowerTargetingMode` is undefined and `targetingMode`/`copyWith` don't exist on `PlacedTower`.

- [ ] **Step 3: Add the enum**

In `lib/game/models/game_models.dart`, insert this enum immediately after the `PlacementFailure` enum (after line 61):

```dart
enum TowerTargetingMode {
  first('First'),
  strongest('Strongest'),
  weakest('Weakest'),
  closest('Closest'),
  shielded('Shielded'),
  armored('Armored');

  const TowerTargetingMode(this.label);
  final String label;
}
```

- [ ] **Step 4: Add the field and thread it through `PlacedTower`**

In `lib/game/models/game_models.dart`, modify the `PlacedTower` class (currently lines 275–326):

Constructor — add `this.targetingMode = TowerTargetingMode.first,` after `this.specialization,` and add the field declaration:

```dart
class PlacedTower {
  const PlacedTower({
    required this.id,
    required this.type,
    required this.position,
    this.level = 1,
    this.specialization,
    this.targetingMode = TowerTargetingMode.first,
  });

  final int id;
  final TowerType type;
  final GridPosition position;
  final int level;
  final TowerSpecialization? specialization;
  final TowerTargetingMode targetingMode;

  bool get canUpgrade => level == 1;
  bool get canSpecialize => level == 2;
  bool get isMaxLevel => level >= 3;
```

In `upgraded()`, pass the mode through (add `targetingMode: targetingMode,` to the returned `PlacedTower`):

```dart
  PlacedTower upgraded() {
    if (!canUpgrade) {
      throw StateError('Tower can only be upgraded from level 1');
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: 2,
      specialization: specialization,
      targetingMode: targetingMode,
    );
  }
```

In `specialized(...)`, same addition:

```dart
  PlacedTower specialized(TowerSpecialization specialization) {
    if (!canSpecialize) {
      throw StateError('Tower can only be specialized from level 2');
    }
    if (specialization.type != type) {
      throw ArgumentError.value(
        specialization,
        'specialization',
        'Specialization must match tower type',
      );
    }
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: 3,
      specialization: specialization,
      targetingMode: targetingMode,
    );
  }
```

Add a `copyWith` method at the end of the class (after `specialized`):

```dart
  PlacedTower copyWith({TowerTargetingMode? targetingMode}) {
    return PlacedTower(
      id: id,
      type: type,
      position: position,
      level: level,
      specialization: specialization,
      targetingMode: targetingMode ?? this.targetingMode,
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/game/placed_tower_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Confirm the rest of the suite still compiles**

Run: `flutter analyze`
Expected: No new warnings/errors (the new field is defaulted, so all existing `PlacedTower`/`GameSnapshot` constructions remain valid).

- [ ] **Step 7: Commit**

```bash
git add lib/game/models/game_models.dart test/game/placed_tower_test.dart
git commit -m "feat: add TowerTargetingMode and PlacedTower.targetingMode (HPA-96)"
```

---

## Task 2: Per-mode targeting algorithm + extended `TargetCandidate`

**Files:**
- Modify: `lib/game/rules/tower_targeting.dart` (whole file; currently 52 lines)
- Test: `test/game/tower_targeting_test.dart` (Modify — append)

**Interfaces:**
- Consumes: `TowerTargetingMode` from Task 1.
- Produces: `TargetCandidate` now has `currentHealth`, `currentShield`, `isShielded`, `isArmored` (all defaulted) and `double get effectiveHealth`; `TowerTargeting.selectTarget(...)` gains `TowerTargetingMode mode = TowerTargetingMode.first`.

- [ ] **Step 1: Write the failing tests**

Append to `test/game/tower_targeting_test.dart` (inside `void main()`, after the existing group). Add the import for the enum at the top of the file:

```dart
import 'package:orion/game/models/game_models.dart';
```

Then append this group:

```dart
    group('targeting modes', () {
      // Tower at (0,0). Range is large enough to include everyone.
      //   id1: hp 30,  not shielded/armored, pp 0.2, dist 10  -> eff 30
      //   id2: hp 10,  shielded,             pp 0.9, dist 20  -> eff 10
      //   id3: hp 80 + shield 20, shielded,  pp 0.5, dist 30  -> eff 100
      //   id4: hp 50,  armored,              pp 0.6, dist 40  -> eff 50
      const candidates = <TargetCandidate>[
        TargetCandidate(
          id: 1,
          x: 10,
          y: 0,
          pathProgress: 0.2,
          isAlive: true,
          currentHealth: 30,
        ),
        TargetCandidate(
          id: 2,
          x: 20,
          y: 0,
          pathProgress: 0.9,
          isAlive: true,
          currentHealth: 10,
          isShielded: true,
        ),
        TargetCandidate(
          id: 3,
          x: 30,
          y: 0,
          pathProgress: 0.5,
          isAlive: true,
          currentHealth: 80,
          currentShield: 20,
          isShielded: true,
        ),
        TargetCandidate(
          id: 4,
          x: 40,
          y: 0,
          pathProgress: 0.6,
          isAlive: true,
          currentHealth: 50,
          isArmored: true,
        ),
      ];

      test('effectiveHealth defaults to zero and sums health + shield', () {
        const bare = TargetCandidate(
          id: 0,
          x: 0,
          y: 0,
          pathProgress: 0,
          isAlive: true,
        );
        expect(bare.effectiveHealth, 0);
        const tough = TargetCandidate(
          id: 0,
          x: 0,
          y: 0,
          pathProgress: 0,
          isAlive: true,
          currentHealth: 25,
          currentShield: 15,
        );
        expect(tough.effectiveHealth, 40);
      });

      test('first (default) picks highest path progress', () {
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: candidates,
        );
        expect(target?.id, 2);
      });

      test('strongest picks highest effective health', () {
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: candidates,
          mode: TowerTargetingMode.strongest,
        );
        expect(target?.id, 3); // eff 100
      });

      test('weakest picks lowest effective health', () {
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: candidates,
          mode: TowerTargetingMode.weakest,
        );
        expect(target?.id, 2); // eff 10
      });

      test('closest picks nearest to the tower', () {
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: candidates,
          mode: TowerTargetingMode.closest,
        );
        expect(target?.id, 1); // dist 10
      });

      test('shielded ranks the shielded subset by path progress', () {
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: candidates,
          mode: TowerTargetingMode.shielded,
        );
        expect(target?.id, 2); // shielded {2,3}; highest pp is 2
      });

      test('armored picks from the armored subset', () {
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: candidates,
          mode: TowerTargetingMode.armored,
        );
        expect(target?.id, 4); // only armored candidate
      });

      test('shielded falls back to first when no shielded enemy is in range', () {
        const unshielded = <TargetCandidate>[
          TargetCandidate(
            id: 1,
            x: 10,
            y: 0,
            pathProgress: 0.2,
            isAlive: true,
          ),
          TargetCandidate(
            id: 2,
            x: 20,
            y: 0,
            pathProgress: 0.9,
            isAlive: true,
          ),
        ];
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: unshielded,
          mode: TowerTargetingMode.shielded,
        );
        expect(target?.id, 2); // fallback to highest path progress
      });

      test('strongest tie breaks to higher path progress', () {
        const tied = <TargetCandidate>[
          TargetCandidate(
            id: 1,
            x: 10,
            y: 0,
            pathProgress: 0.3,
            isAlive: true,
            currentHealth: 50,
          ),
          TargetCandidate(
            id: 2,
            x: 20,
            y: 0,
            pathProgress: 0.8,
            isAlive: true,
            currentHealth: 50,
          ),
        ];
        final target = TowerTargeting.selectTarget(
          tower: const TargetPoint(x: 0, y: 0),
          range: 999,
          candidates: tied,
          mode: TowerTargetingMode.strongest,
        );
        expect(target?.id, 2);
      });
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/tower_targeting_test.dart`
Expected: FAIL — `effectiveHealth`, `currentHealth`, `isShielded`, `isArmored`, and the `mode` parameter don't exist.

- [ ] **Step 3: Extend `TargetCandidate` and rewrite `selectTarget`**

Replace the entire contents of `lib/game/rules/tower_targeting.dart` with:

```dart
import '../models/game_models.dart';

class TargetPoint {
  const TargetPoint({required this.x, required this.y});

  final double x;
  final double y;
}

class TargetCandidate {
  const TargetCandidate({
    required this.id,
    required this.x,
    required this.y,
    required this.pathProgress,
    required this.isAlive,
    this.currentHealth = 0,
    this.currentShield = 0,
    this.isShielded = false,
    this.isArmored = false,
  });

  final int id;
  final double x;
  final double y;
  final double pathProgress;
  final bool isAlive;
  final double currentHealth;
  final double currentShield;
  final bool isShielded;
  final bool isArmored;

  double get effectiveHealth => currentHealth + currentShield;
}

class TowerTargeting {
  static TargetCandidate? selectTarget({
    required TargetPoint tower,
    required double range,
    required Iterable<TargetCandidate> candidates,
    TowerTargetingMode mode = TowerTargetingMode.first,
  }) {
    final rangeSquared = range * range;
    final inRange = <TargetCandidate>[];
    for (final candidate in candidates) {
      if (!candidate.isAlive) {
        continue;
      }
      if (_distanceSquaredTo(candidate, tower) > rangeSquared) {
        continue;
      }
      inRange.add(candidate);
    }
    if (inRange.isEmpty) {
      return null;
    }

    final pool = _modePool(inRange, mode);
    if (pool.isEmpty) {
      return null;
    }

    TargetCandidate? best;
    for (final candidate in pool) {
      if (best == null || _prefers(candidate, best, tower, mode)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Shrinks the in-range pool for trait modes. Returns the full pool for
  /// non-trait modes and when the trait subset is empty (graceful fallback).
  static List<TargetCandidate> _modePool(
    List<TargetCandidate> inRange,
    TowerTargetingMode mode,
  ) {
    switch (mode) {
      case TowerTargetingMode.shielded:
        final subset = inRange.where((c) => c.isShielded).toList();
        return subset.isEmpty ? inRange : subset;
      case TowerTargetingMode.armored:
        final subset = inRange.where((c) => c.isArmored).toList();
        return subset.isEmpty ? inRange : subset;
      default:
        return inRange;
    }
  }

  /// True when [a] should be selected over [b] under [mode]. Primary key first;
  /// falls through to the universal tie-break (pathProgress desc, then id asc).
  static bool _prefers(
    TargetCandidate a,
    TargetCandidate b,
    TargetPoint tower,
    TowerTargetingMode mode,
  ) {
    switch (mode) {
      case TowerTargetingMode.strongest:
        final byHealth = a.effectiveHealth.compareTo(b.effectiveHealth);
        if (byHealth != 0) {
          return byHealth > 0;
        }
        break;
      case TowerTargetingMode.weakest:
        final byHealth = a.effectiveHealth.compareTo(b.effectiveHealth);
        if (byHealth != 0) {
          return byHealth < 0;
        }
        break;
      case TowerTargetingMode.closest:
        final byDistance = _distanceSquaredTo(a, tower).compareTo(
          _distanceSquaredTo(b, tower),
        );
        if (byDistance != 0) {
          return byDistance < 0;
        }
        break;
      case TowerTargetingMode.first:
      case TowerTargetingMode.shielded:
      case TowerTargetingMode.armored:
        // pathProgress IS the ranking key; resolved by the universal tie-break.
        break;
    }
    final byProgress = a.pathProgress.compareTo(b.pathProgress);
    if (byProgress != 0) {
      return byProgress > 0;
    }
    return a.id < b.id;
  }

  static double _distanceSquaredTo(TargetCandidate candidate, TargetPoint tower) {
    final dx = candidate.x - tower.x;
    final dy = candidate.y - tower.y;
    return (dx * dx) + (dy * dy);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/tower_targeting_test.dart`
Expected: PASS (the 2 original tests + the new mode tests).

- [ ] **Step 5: Confirm dependent rule tests still compile and pass**

Run: `flutter test test/game/combat_effects_test.dart`
Expected: PASS — the defaulted `TargetCandidate` fields keep `combat_effects` chain/pierce selection working unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/game/rules/tower_targeting.dart test/game/tower_targeting_test.dart
git commit -m "feat: per-mode target selection in TowerTargeting (HPA-96)"
```

---

## Task 3: `GameSession.setTargetingMode`

**Files:**
- Modify: `lib/game/rules/game_session.dart` (add method near `specializeTower`, ~line 180)
- Test: `test/game/game_session_test.dart` (Modify — append a group)

**Interfaces:**
- Consumes: `PlacedTower.copyWith` (Task 1), `TowerTargetingMode` (Task 1).
- Produces: `bool GameSession.setTargetingMode(int towerId, TowerTargetingMode mode)` — build-phase gated; returns `true` on success, `false` on wrong phase or unknown id.

- [ ] **Step 1: Write the failing tests**

Append this group inside `void main()` in `test/game/game_session_test.dart` (after the existing `specialize*` tests, before the `starts waves` test around line 454):

```dart
    group('targeting mode', () {
      test('newly placed tower defaults to First', () {
        final session = GameSession.initial();
        session.placeTower(const GridPosition(0, 0), TowerType.laser);

        expect(
          session.towers.single.targetingMode,
          TowerTargetingMode.first,
        );
      });

      test('setTargetingMode updates the mode during build phase', () {
        final session = GameSession.initial();
        session.placeTower(const GridPosition(0, 0), TowerType.laser);
        final tower = session.towers.single;

        expect(
          session.setTargetingMode(tower.id, TowerTargetingMode.strongest),
          isTrue,
        );
        expect(
          session.towers.single.targetingMode,
          TowerTargetingMode.strongest,
        );
      });

      test('setTargetingMode is denied during wave', () {
        final session = GameSession.initial();
        session.placeTower(const GridPosition(0, 0), TowerType.laser);
        final tower = session.towers.single;
        expect(session.startWave(), isTrue);

        expect(
          session.setTargetingMode(tower.id, TowerTargetingMode.weakest),
          isFalse,
        );
        expect(
          session.towers.single.targetingMode,
          TowerTargetingMode.first,
        );
      });

      test('setTargetingMode returns false for an unknown tower id', () {
        final session = GameSession.initial();

        expect(
          session.setTargetingMode(999, TowerTargetingMode.closest),
          isFalse,
        );
      });

      test('targeting mode survives upgrade and specialization', () {
        final session = GameSession.initial(gold: 500);
        session.placeTower(const GridPosition(0, 0), TowerType.laser);
        final tower = session.towers.single;
        expect(
          session.setTargetingMode(tower.id, TowerTargetingMode.closest),
          isTrue,
        );

        expect(session.upgradeTower(tower.id), isTrue);
        expect(
          session.towers.single.targetingMode,
          TowerTargetingMode.closest,
        );

        expect(
          session.specializeTower(tower.id, TowerSpecialization.pulseLaser),
          isTrue,
        );
        expect(
          session.towers.single.targetingMode,
          TowerTargetingMode.closest,
        );
      });
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/game_session_test.dart`
Expected: FAIL — `setTargetingMode` is undefined.

- [ ] **Step 3: Implement `setTargetingMode`**

In `lib/game/rules/game_session.dart`, add this method immediately after `specializeTower(...)` (after line 180), mirroring the upgrade/specialize pattern:

```dart
  bool setTargetingMode(int towerId, TowerTargetingMode mode) {
    if (_phase != GamePhase.build) {
      return false;
    }

    final entry = _findTowerEntry(towerId);
    if (entry == null) {
      return false;
    }

    _towersByPosition[entry.key] = entry.value.copyWith(targetingMode: mode);
    return true;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/game_session_test.dart`
Expected: PASS (all existing tests + the new targeting-mode group).

- [ ] **Step 5: Commit**

```bash
git add lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: GameSession.setTargetingMode with build-phase gate (HPA-96)"
```

---

## Task 4: Wire the mode into the game layer

This task is glue between the pure rules (Tasks 1–3) and the Flame components/UI. The orchestration layer (`OrionDefenseGame`, `EnemyComponent`) has no direct unit test in this repo; correctness is verified by `flutter analyze` plus the existing widget smoke (`test/widget_test.dart`) which boots the game and exercises tower placement, while the behavior it wires is already covered by the rule/session unit tests.

**Files:**
- Modify: `lib/game/components/enemy_component.dart` (`targetCandidate` getter, lines 103–111)
- Modify: `lib/game/orion_defense_game.dart` (`_selectTargetForTower` lines 371–384; add `setTargetingMode` near `specializeSelectedTower` after line 223)

**Interfaces:**
- Consumes: `TargetCandidate` new fields (Task 2); `PlacedTower.targetingMode` (Task 1); `GameSession.setTargetingMode` (Task 3).
- Produces: `OrionDefenseGame.setTargetingMode(TowerTargetingMode mode)` (called by the UI in Task 5).

- [ ] **Step 1: Populate the new `TargetCandidate` fields from live enemy state**

In `lib/game/components/enemy_component.dart`, replace the `targetCandidate` getter (lines 103–111):

```dart
  TargetCandidate get targetCandidate {
    return TargetCandidate(
      id: enemyId,
      x: position.x,
      y: position.y,
      pathProgress: pathProgress,
      isAlive: isAlive,
      currentHealth: health,
      currentShield: shield,
      isShielded: stats.traits.contains(EnemyTrait.shielded),
      isArmored: stats.traits.contains(EnemyTrait.armored),
    );
  }
```

- [ ] **Step 2: Pass the tower's mode into `selectTarget`**

In `lib/game/orion_defense_game.dart`, update `_selectTargetForTower` (lines 371–384) to forward the mode:

```dart
  EnemyComponent? _selectTargetForTower(TowerComponent tower) {
    final candidates = _activeEnemyComponents.values
        .where((enemy) => enemy.isAlive)
        .map((enemy) => enemy.targetCandidate);
    final selected = TowerTargeting.selectTarget(
      tower: TargetPoint(x: tower.position.x, y: tower.position.y),
      range: tower.stats.range,
      candidates: candidates,
      mode: tower.placedTower.targetingMode,
    );
    if (selected == null) {
      return null;
    }
    return _activeEnemyComponents[selected.id];
  }
```

- [ ] **Step 3: Add `OrionDefenseGame.setTargetingMode`**

In `lib/game/orion_defense_game.dart`, add this method immediately after `specializeSelectedTower(...)` (after line 223), mirroring its structure:

```dart
  void setTargetingMode(TowerTargetingMode mode) {
    final tower = _selectedTower;
    if (tower == null) {
      _publishSnapshot(feedback: 'Select a tower first.');
      return;
    }

    if (!_session.setTargetingMode(tower.id, mode)) {
      _publishSnapshot(
        feedback: 'Targeting can only change during build phase.',
      );
      return;
    }

    final updated = _session.towerAt(tower.position);
    final component = _towerComponents[tower.id];
    if (updated != null && component != null) {
      component.updateTower(updated);
      _selectedTower = updated;
    }
    _publishSnapshot();
  }
```

- [ ] **Step 4: Verify static analysis and the widget smoke**

Run: `flutter analyze`
Expected: No new warnings/errors.

Run: `flutter test test/widget_test.dart`
Expected: PASS — the game still boots, a stage loads, and tower placement works.

- [ ] **Step 5: Commit**

```bash
git add lib/game/components/enemy_component.dart lib/game/orion_defense_game.dart
git commit -m "feat: wire per-tower targeting mode into game layer (HPA-96)"
```

---

## Task 5: Targeting-mode picker in the selected-tower panel

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart` (restructure `_UpgradePanel.build`, lines 720–779; add `_TargetingModePicker`)
- Test: `test/widget_test.dart` (Modify — append widget tests)

**Interfaces:**
- Consumes: `OrionDefenseGame.setTargetingMode` (Task 4); `PlacedTower.targetingMode` + `TowerTargetingMode.label` (Task 1).
- Produces: a build-phase-enabled wrap of `ChoiceChip`s beneath the tower summary.

- [ ] **Step 1: Write the failing widget tests**

Append to `test/widget_test.dart` inside `void main()`. (`OrionGamePage`, `GameSnapshot`, `GamePhase`, `PlacedTower`, `TowerType`, `TowerTargetingMode`, `GridPosition` are all importable from the existing imports — `game_models.dart` already imported. `ChoiceChip` comes from `material.dart`, already imported.)

```dart
  testWidgets(
    'selected tower panel shows targeting chips reflecting the current mode',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      OrionDefenseGame? game;

      await tester.pumpWidget(
        MaterialApp(
          home: OrionGamePage(onGameCreated: (created) => game = created),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      final snapshot = game!.stateNotifier.value;
      const selectedTower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        targetingMode: TowerTargetingMode.strongest,
      );
      game!.stateNotifier.value = GameSnapshot(
        phase: GamePhase.build,
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

      for (final mode in TowerTargetingMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
      final strongestChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('Strongest'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(strongestChip.selected, isTrue);
    },
  );

  testWidgets('targeting chips are disabled during wave phase', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OrionDefenseGame? game;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionGamePage(onGameCreated: (created) => game = created),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final snapshot = game!.stateNotifier.value;
    const selectedTower = PlacedTower(
      id: 1,
      type: TowerType.laser,
      position: GridPosition(0, 0),
    );
    game!.stateNotifier.value = GameSnapshot(
      phase: GamePhase.wave,
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

    final firstChip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('First'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(firstChip.onSelected, isNull);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget_test.dart`
Expected: FAIL — the mode labels aren't found (no picker yet).

- [ ] **Step 3: Add `_TargetingModePicker` and restructure `_UpgradePanel`**

In `lib/game/ui/orion_game_page.dart`, replace the `build` method of `_UpgradePanel` (lines 726–779) so the summary+actions row is wrapped in an outer `Column` with the picker beneath it:

```dart
  @override
  Widget build(BuildContext context) {
    final tower = snapshot.selectedTower!;
    final stats = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    final towerName = _towerLabel(tower.type);
    final canUpgrade =
        snapshot.phase == GamePhase.build &&
        tower.canUpgrade &&
        snapshot.gold >= stats.upgradeCost;

    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = _UpgradeActions(
          game: game,
          snapshot: snapshot,
          tower: tower,
          stats: stats,
          canUpgrade: canUpgrade,
          alignment: constraints.maxWidth < 440
              ? WrapAlignment.start
              : WrapAlignment.end,
        );

        final Widget summaryAndActions;
        if (constraints.maxWidth < 440) {
          summaryAndActions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TowerSummary(tower: tower, towerName: towerName),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        } else {
          summaryAndActions = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TowerSummary(tower: tower, towerName: towerName),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(alignment: Alignment.centerRight, child: actions),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            summaryAndActions,
            const SizedBox(height: 10),
            _TargetingModePicker(game: game, snapshot: snapshot, tower: tower),
          ],
        );
      },
    );
  }
}
```

Then add the `_TargetingModePicker` widget immediately after `_UpgradePanel` (before `_TowerSummary`):

```dart
class _TargetingModePicker extends StatelessWidget {
  const _TargetingModePicker({
    required this.game,
    required this.snapshot,
    required this.tower,
  });

  final OrionDefenseGame game;
  final GameSnapshot snapshot;
  final PlacedTower tower;

  @override
  Widget build(BuildContext context) {
    final enabled = snapshot.phase == GamePhase.build;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in TowerTargetingMode.values)
          ChoiceChip(
            label: Text(mode.label),
            selected: tower.targetingMode == mode,
            onSelected: enabled ? (_) => game.setTargetingMode(mode) : null,
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget_test.dart`
Expected: PASS (all existing widget tests + the two new picker tests).

- [ ] **Step 5: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: targeting-mode picker in selected-tower panel (HPA-96)"
```

---

## Task 6: Full verification gate

**Files:** none (verification only)

- [ ] **Step 1: Run the entire unit/widget suite**

Run: `flutter test`
Expected: All tests pass — including `placed_tower_test.dart`, `tower_targeting_test.dart`, `game_session_test.dart`, `combat_effects_test.dart`, `game_balance_test.dart`, and `widget_test.dart`.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Format**

Run: `dart format .`
Expected: No diff beyond formatting (commit any formatting changes with `style:` if the prior tasks left any).

- [ ] **Step 4: (Optional, requires a device/emulator) Integration smoke**

The existing `integration_test/app_smoke_test.dart` already places a tower and starts a wave, exercising the wiring end-to-end. If a device is available, run:

Run: `flutter test integration_test/app_smoke_test.dart`
Expected: PASS. (This is optional for local dev; CI covers it. No edits required — the new field is defaulted and the picker is additive.)

---

## Self-Review

**Spec coverage:** Every spec section maps to a task — enum + `PlacedTower` field (Task 1); `TargetCandidate` extension + per-mode ranking + tie-breaks + fallback (Task 2); `GameSession.setTargetingMode` + build-phase gate (Task 3); `EnemyComponent.targetCandidate` population + `OrionDefenseGame.setTargetingMode` + mode forwarding (Task 4); build-phase choice-chip picker (Task 5). Acceptance criteria are each covered: default = `first` (Task 1 + Task 3 test), build-phase picker (Task 5), affects acquisition during waves (Task 4 forwards mode), graceful fallback (Task 2 trait-fallback + null-on-empty), preservation across upgrade/specialize (Task 1 + Task 3 test), per-mode tests (Task 2).

**Placeholder scan:** No TBD/TODO; every code step contains full source.

**Type consistency:** `TowerTargetingMode`, `targetingMode`, `copyWith`, `selectTarget(..., mode:)`, `GameSession.setTargetingMode(int, TowerTargetingMode)`, `OrionDefenseGame.setTargetingMode(TowerTargetingMode)`, `currentHealth`/`currentShield`/`isShielded`/`isArmored`/`effectiveHealth` — names match across all tasks. `tower.placedTower.targetingMode` matches the existing public `placedTower` field on `TowerComponent`.
