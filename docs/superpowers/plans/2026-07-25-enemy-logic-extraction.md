# Enemy Logic Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all per-enemy game logic out of `EnemyComponent` into a new pure, Flame-free `EnemyLogic` class in `rules/`, with `OrionDefenseGame` owning and ticking the instances, leaving `EnemyComponent` as a render shell.

**Architecture:** `EnemyLogic` (new, `rules/enemy_logic.dart`) owns combat state, path/position math (via `dart:ui` `Offset`), and the tick/apply methods; it reports events through an `EnemyTickResult` value. `OrionDefenseGame` constructs one logic per enemy and ticks them in a new `_tickEnemyLogic` phase after `super.update`. `EnemyComponent` holds a `final EnemyLogic logic` back-reference, exposes thin `void` forwarders (`applyDamage`/`applySlow`/`applyCorrosion`), and syncs render state (`syncRender`/`markOverlayDirty`). Death resolution uses a component-side `_resolutionDispatched` once-guard distinct from `logic.isResolved`.

**Tech Stack:** Flutter + Flame (`flame: ^1.37.0`), Dart SDK `^3.12.0`. Pure logic uses `dart:math` + `dart:ui` (`Offset`) + sibling `combat_effects.dart`; no `package:flame` in `rules/`.

## Global Constraints

- `rules/` is Flame-free: `enemy_logic.dart` may import only `dart:math`, `dart:ui`, `../models/game_models.dart`, and `combat_effects.dart`. `dart:ui` is allowed (precedent: `rules/board_layout.dart:1`).
- The three consumer files `ProjectileComponent`, `DroneComponent`, `GravityFieldComponent` stay **unmodified** — the 19 `applyDamage`/`applySlow`/`applyCorrosion` invocations across them keep calling the unchanged `void` forwarders.
- `Map<int, EnemyComponent> _activeEnemyComponents` is **unchanged** (no wrapper struct). All 16 existing use sites stay as-is.
- Movement must be **byte-identical FP** to today's `_moveAlongPath` — port `Vector2` ops to `Offset` verbatim (`.length` → `.distance`).
- Two accepted frame-level shifts (documented in the spec): enemy-tick batching (gravity/projectile/drone hit pre-move positions) and same-frame status acceleration. Movement FP is identical.
- Commits use Conventional Commits (`feat:`/`refactor:`/`test:`/`docs:`) suffixed `(HPA-370)`.
- Every task ends with `flutter analyze` clean and `flutter test` green before committing.

## File Structure

- **Create** `lib/game/rules/enemy_logic.dart` — pure per-enemy logic: state, `tick`, `applyDamage`/`applySlow`/`applyCorrosion`, path/position math, `EnemyTickResult`.
- **Create** `test/game/enemy_logic_test.dart` — pure-logic unit tests (no Flame harness).
- **Modify** `lib/game/components/enemy_component.dart` — render shell: holds `logic`, forwarders, `syncRender`/`markOverlayDirty`, resolution guard; drops ticking + waypoints + combat fields.
- **Modify** `lib/game/orion_defense_game.dart` — constructs `EnemyLogic` in `_spawnEnemy`/`_spawnMinion`, adds `_tickEnemyLogic` phase to `update`.
- **Modify** `test/game/enemy_component_test.dart` — slimmed; drives `logic.tick()` directly, tests shell behavior.
- **Modify** `test/game/orion_defense_game_test.dart` — rewrite direct `.update()` sites to `game.update(...)`; add 4 integration tests.

---

### Task 1: EnemyLogic skeleton + path/movement (pure)

**Files:**
- Create: `lib/game/rules/enemy_logic.dart`
- Create: `test/game/enemy_logic_test.dart`

**Interfaces:**
- Consumes: `EnemyStats` (`lib/game/models/game_models.dart`), `Offset` (`dart:ui`).
- Produces: `class EnemyLogic` with constructor `EnemyLogic({required int enemyId, required EnemyStats stats, required List<Offset> waypoints, double initialCompletedDistance = 0})`; mutable `Offset position`; getters `pathProgress`, `targetWaypointIndex`; method `List<Offset> residualWaypointsFromHere()`; private `_moveAlongPath(double dt, double slowMultiplier)`.

- [ ] **Step 1: Write the failing tests** for movement (assert byte-identical results to today's component, using `Offset` waypoints). Create `test/game/enemy_logic_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/enemy_logic.dart';

void main() {
  group('EnemyLogic movement', () {
    test('pathProgress includes full completed segments after waypoint crossing', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
        waypoints: [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)],
      );
      logic.tick(0.6);
      expect(logic.pathProgress, closeTo(6, 0.001));
      logic.tick(0.6);
      expect(logic.position.dx, closeTo(10, 0.001));
      expect(logic.position.dy, closeTo(2, 0.001));
      expect(logic.pathProgress, closeTo(12, 0.001));
    });

    test('reaches base and reports reachedBase when path is exhausted', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
        waypoints: [const Offset(0, 0), const Offset(5, 0)],
      );
      final result = logic.tick(1); // speed 10 * dt 1 = 10 > segment length 5
      expect(result.reachedBase, isTrue);
      expect(logic.isResolved, isTrue);
      expect(logic.position, const Offset(5, 0)); // snapped to waypoints.last
    });

    test('residualWaypointsFromHere starts at current position', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
        waypoints: [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)],
      );
      logic.tick(0.3); // moves 3 units along x
      final residual = logic.residualWaypointsFromHere();
      expect(residual.first, closeToOffset(const Offset(3, 0)));
      expect(residual, hasLength(3)); // current pos + 2 remaining waypoints
    });
  });
}

Matcher closeToOffset(Offset value) => predicate<Offset>(
      (o) => (o.dx - value.dx).abs() < 0.001 && (o.dy - value.dy).abs() < 0.001,
      'is close to $value',
    );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/enemy_logic_test.dart`
Expected: FAIL — `EnemyLogic` undefined / `enemy_logic.dart` not found.

- [ ] **Step 3: Implement `EnemyLogic` movement.** Create `lib/game/rules/enemy_logic.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

import '../models/game_models.dart';
import 'combat_effects.dart';

class EnemyLogic {
  EnemyLogic({
    required this.enemyId,
    required this.stats,
    required List<Offset> waypoints,
    double initialCompletedDistance = 0,
  })  : waypoints = List<Offset>.unmodifiable(waypoints),
        position = waypoints.first,
        _completedDistance = initialCompletedDistance,
        _summonRemaining = _initialSummonDelay(stats),
        assert(waypoints.length >= 2, 'EnemyLogic requires at least two waypoints');

  final int enemyId;
  final EnemyStats stats;
  final List<Offset> waypoints;

  Offset position;
  double health = stats.health;
  late final double maxHealth = stats.health;
  late double shield = stats.shieldHealth;

  bool _isResolved = false;
  int _targetWaypointIndex = 1;
  double _completedDistance;
  double _segmentProgress = 0;
  double _summonRemaining;

  bool get isResolved => _isResolved;
  bool get isAlive => !_isResolved && health > 0;

  double get _currentSegmentLength {
    if (_targetWaypointIndex >= waypoints.length) return 0;
    return waypoints[_targetWaypointIndex - 1].distanceTo(waypoints[_targetWaypointIndex]);
  }

  double get pathProgress =>
      _completedDistance + _currentSegmentLength * _segmentProgress;

  List<Offset> residualWaypointsFromHere() =>
      [position, ...waypoints.sublist(_targetWaypointIndex)];

  static double _initialSummonDelay(EnemyStats stats) {
    if (stats is BossDefinition) {
      final mechanic = stats.summonMechanic;
      if (mechanic != null) return mechanic.firstDelay;
    }
    return 0;
  }

  EnemyTickResult tick(double dt) {
    // Task 1: movement only. Combat/summon filled in later tasks.
    final slowMultiplier = 1.0;
    _moveAlongPath(dt, slowMultiplier);
    return EnemyTickResult(reachedBase: _isResolved, diedByCorrosion: false, summonsDue: 0, overlayDirty: false);
  }

  void _moveAlongPath(double dt, double slowMultiplier) {
    var distanceRemaining = stats.speed * slowMultiplier * dt;
    while (distanceRemaining > 0 && !_isResolved) {
      if (_targetWaypointIndex >= waypoints.length) {
        _isResolved = true;
        return;
      }
      final target = waypoints[_targetWaypointIndex];
      final toTarget = target - position;
      final distanceToTarget = toTarget.distance;
      final segmentLength = _currentSegmentLength;

      if (distanceToTarget <= distanceRemaining) {
        position = target;
        _completedDistance += segmentLength;
        _segmentProgress = 1;
        _targetWaypointIndex += 1;
        distanceRemaining -= distanceToTarget;
        if (_targetWaypointIndex >= waypoints.length) {
          _isResolved = true;
          return;
        }
        _segmentProgress = 0;
      } else {
        final step = toTarget..scale(distanceRemaining / distanceToTarget);
        position = position + step;
        _segmentProgress = 1 - ((distanceToTarget - distanceRemaining) / _currentSegmentLength);
        distanceRemaining = 0;
      }
    }
  }
}

class EnemyTickResult {
  const EnemyTickResult({
    required this.reachedBase,
    required this.diedByCorrosion,
    required this.summonsDue,
    required this.overlayDirty,
  });
  final bool reachedBase;
  final bool diedByCorrosion;
  final int summonsDue;
  final bool overlayDirty;
}
```

Note `health`/`shield` initialization: `health = stats.health` is set in `tick` for Task 1 only (tests don't pre-damage). Task 2 moves it to the constructor initializer. `Offset` has no `scale` mutator (it's immutable) — use `position = position + step` where `step` is scaled; fix the `toTarget..scale(...)` to compute a scaled `Offset` (see correction below).

- [ ] **Step 4: Correct the `Offset` arithmetic** (immutable `Offset` has no in-place `scale`/`add`). Replace the `else` branch of `_moveAlongPath` with:

```dart
      } else {
        final scale = distanceRemaining / distanceToTarget;
        position = position + Offset(toTarget.dx * scale, toTarget.dy * scale);
        _segmentProgress = 1 - ((distanceToTarget - distanceRemaining) / _currentSegmentLength);
        distanceRemaining = 0;
      }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/game/enemy_logic_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/game/rules/enemy_logic.dart test/game/enemy_logic_test.dart
git commit -m "feat: add EnemyLogic movement (pure, Offset-based) (HPA-370)"
```

---

### Task 2: EnemyLogic combat state + apply methods + resolution marker

**Files:**
- Modify: `lib/game/rules/enemy_logic.dart`
- Modify: `test/game/enemy_logic_test.dart`

**Interfaces:**
- Consumes: `CombatEffects.resolveDamage`/`mergeSlow` (`combat_effects.dart`), `DamageInput`, `DamageResult`, `SlowMergeResult`.
- Produces: `EnemyLogic.applyDamage` returns `DamageOutcome({bool died})`; `applySlow`/`applyCorrosion` return `void`; mutable combat fields `health`, `shield`, `armorShred`, `slowMultiplier`, `slowRemaining`, `corrosionDamagePerSecond`, `corrosionRemaining`; `bool get isResolved`; `bool get isSlowed`/`isCorroded`; `double get armorReduction`.

- [ ] **Step 1: Write failing tests** appended to `enemy_logic_test.dart`:

```dart
  group('EnemyLogic combat', () {
    EnemyLogic make({double health = 100, double shield = 0, double armorReduction = 0}) =>
        EnemyLogic(
          enemyId: 1,
          stats: EnemyStats(
            health: health, speed: 10, baseDamage: 1, goldReward: 1,
            shieldHealth: shield, armorReduction: armorReduction,
          ),
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        );

    test('shield absorbs damage before health', () {
      final logic = make(health: 50, shield: 20);
      final outcome = logic.applyDamage(15);
      expect(logic.health, 50);
      expect(logic.shield, 5);
      expect(outcome.died, isFalse);
      expect(logic.isAlive, isTrue);
    });

    test('lethal damage marks resolved and reports died', () {
      final logic = make(health: 10);
      final outcome = logic.applyDamage(10);
      expect(logic.health, 0);
      expect(outcome.died, isTrue);
      expect(logic.isResolved, isTrue);
      expect(logic.isAlive, isFalse);
    });

    test('applySlow merges and exposes isSlowed', () {
      final logic = make();
      logic.applySlow(multiplier: 0.5, duration: 1);
      expect(logic.isSlowed, isTrue);
      expect(logic.slowMultiplier, closeTo(0.5, 0.001));
    });

    test('applyCorrosion stacks dps/duration/shred and exposes isCorroded', () {
      final logic = make();
      logic.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      expect(logic.isCorroded, isTrue);
      expect(logic.corrosionDamagePerSecond, 5);
      expect(logic.armorShred, closeTo(0.1, 0.001));
    });

    test('armorReduction clamps after shred', () {
      final logic = make(armorReduction: 0.4);
      logic.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      expect(logic.armorReduction, closeTo(0.3, 0.001));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/enemy_logic_test.dart --name "EnemyLogic combat"`
Expected: FAIL — `applyDamage`/`applySlow`/`applyCorrosion`/`DamageOutcome` undefined.

- [ ] **Step 3: Implement combat state + apply methods.** In `enemy_logic.dart`: `health`/`maxHealth`/`shield`/`_isResolved`/`isResolved`/`isAlive` already exist from Task 1. **Add** the remaining combat fields and getters, and the apply methods:

```dart
  // additional combat state (health/shield/maxHealth/isResolved come from Task 1)
  double armorShred = 0;
  double slowMultiplier = 1;
  double slowRemaining = 0;
  double corrosionDamagePerSecond = 0;
  double corrosionRemaining = 0;

  bool get isSlowed => slowRemaining > 0 && slowMultiplier < 1;
  bool get isCorroded => corrosionRemaining > 0;
  double get armorReduction => (stats.armorReduction - armorShred).clamp(0, 0.75).toDouble();

  DamageOutcome applyDamage(
    double amount, {
    double shieldDamageMultiplier = 1,
    double armorDamageMultiplier = 1,
    double armorShred = 0,
    bool bypassArmor = false,
  }) {
    if (!isAlive || amount <= 0) return const DamageOutcome(died: false);
    final result = CombatEffects.resolveDamage(
      DamageInput(
        health: health,
        maxHealth: maxHealth,
        shield: shield,
        damage: amount,
        armorReduction: stats.armorReduction,
        armorShred: math.max(this.armorShred, armorShred),
        shieldDamageMultiplier: shieldDamageMultiplier,
        armorDamageMultiplier: armorDamageMultiplier,
        bypassArmor: bypassArmor,
      ),
    );
    health = result.health;
    shield = result.shield;
    if (health == 0) {
      _isResolved = true;
      return const DamageOutcome(died: true);
    }
    return const DamageOutcome(died: false);
  }

  void applySlow({required double multiplier, required double duration}) {
    if (!isAlive || multiplier >= 1 || multiplier <= 0 || duration <= 0) return;
    final result = CombatEffects.mergeSlow(
      currentMultiplier: slowMultiplier,
      currentRemaining: slowRemaining,
      incomingMultiplier: multiplier,
      incomingDuration: duration,
    );
    slowMultiplier = result.multiplier;
    slowRemaining = result.remaining;
  }

  void applyCorrosion({
    required double damagePerSecond,
    required double duration,
    required double armorShred,
  }) {
    if (!isAlive || damagePerSecond <= 0 || duration <= 0) return;
    this.corrosionDamagePerSecond = math.max(this.corrosionDamagePerSecond, damagePerSecond);
    corrosionRemaining = math.max(corrosionRemaining, duration);
    this.armorShred = math.max(this.armorShred, armorShred);
  }
```

Add the `DamageOutcome` value type at the bottom of the file:

```dart
class DamageOutcome {
  const DamageOutcome({required this.died});
  final bool died;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/enemy_logic_test.dart`
Expected: PASS (all combat + movement tests).

- [ ] **Step 5: Commit**

```bash
git add lib/game/rules/enemy_logic.dart test/game/enemy_logic_test.dart
git commit -m "feat: EnemyLogic combat state and apply methods (HPA-370)"
```

---

### Task 3: EnemyLogic.tick — corrosion/regen + slow decay + overlayDirty

**Files:**
- Modify: `lib/game/rules/enemy_logic.dart`
- Modify: `test/game/enemy_logic_test.dart`

**Interfaces:**
- Consumes: `CombatEffects.applyRegen`.
- Produces: full `EnemyLogic.tick(double dt)` returning `EnemyTickResult` with correct `diedByCorrosion`/`reachedBase`/`overlayDirty`.

- [ ] **Step 1: Write failing tests** appended to `enemy_logic_test.dart`:

```dart
  group('EnemyLogic tick status', () {
    test('regen restores health while corrosion pauses regen', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100, speed: 10, baseDamage: 1, goldReward: 1,
          traits: {EnemyTrait.regen}, regenPerSecond: 10,
        ),
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      logic.applyDamage(30);
      logic.tick(1);
      expect(logic.health, 80);
      logic.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      final r = logic.tick(1);
      expect(logic.health, 75); // corrosion dmg 5, no regen
      expect(logic.isCorroded, isTrue);
      expect(r.overlayDirty, isTrue);
    });

    test('regen stays paused during corrosion expiry tick', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100, speed: 10, baseDamage: 1, goldReward: 1,
          traits: {EnemyTrait.regen}, regenPerSecond: 10,
        ),
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      logic.applyDamage(50);
      logic.applyCorrosion(damagePerSecond: 5, duration: 1, armorShred: 0.1);
      logic.tick(1); // corrosion expires this tick, regen still paused
      expect(logic.isCorroded, isFalse);
      expect(logic.health, closeTo(45, 0.001)); // 50 - 5 corrosion, no regen
    });

    test('slow movement and expiry', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(health: 100, speed: 10, baseDamage: 1, goldReward: 1),
        waypoints: const [Offset(0, 0), Offset(100, 0)],
      );
      logic.applySlow(multiplier: 0.5, duration: 1);
      logic.tick(1); // moves 5 units
      expect(logic.position.dx, closeTo(5, 0.001));
      expect(logic.isSlowed, isFalse);
    });

    test('overlayDirty is false when only position changes (no status/health)', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(health: 100, speed: 10, baseDamage: 1, goldReward: 1),
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      final r = logic.tick(1); // pure movement, no status
      expect(r.overlayDirty, isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/enemy_logic_test.dart --name "EnemyLogic tick status"`
Expected: FAIL — `tick` doesn't apply corrosion/regen/slow yet.

- [ ] **Step 3: Implement the full `tick`.** Replace the Task-1 `tick` body with the ordered sequence (corrosion/regen → movement → slow decay). Summon is added in Task 4. Set `overlayDirty` exactly at today's mutation points:

```dart
  EnemyTickResult tick(double dt) {
    var overlayDirty = false;
    final movementSlowMultiplier = isSlowed ? slowMultiplier : 1.0;
    final wasCorrodedAtTickStart = isCorroded;

    // 1. Corrosion + regen
    if (corrosionRemaining > 0) {
      final tick = math.min(math.max(0, dt), corrosionRemaining);
      corrosionRemaining = math.max(0, corrosionRemaining - tick);
      final dmg = applyDamage(corrosionDamagePerSecond * tick, bypassArmor: true);
      if (corrosionRemaining == 0) {
        corrosionDamagePerSecond = 0;
        armorShred = 0;
        overlayDirty = true;
      }
      if (dmg.died) {
        return EnemyTickResult(
          reachedBase: false, diedByCorrosion: true, summonsDue: 0, overlayDirty: true,
        );
      }
    }
    final previousHealth = health;
    health = CombatEffects.applyRegen(
      health: health,
      maxHealth: maxHealth,
      regenPerSecond: stats.regenPerSecond,
      dt: dt,
      isCorroded: wasCorrodedAtTickStart,
    );
    if (health != previousHealth) overlayDirty = true;

    // 2. Movement
    _moveAlongPath(dt, movementSlowMultiplier);
    if (_isResolved) {
      return EnemyTickResult(
        reachedBase: true, diedByCorrosion: false, summonsDue: 0, overlayDirty: true,
      );
    }

    // 3. Slow decay
    if (slowRemaining > 0) {
      slowRemaining = math.max(0, slowRemaining - dt);
      if (slowRemaining == 0) {
        slowMultiplier = 1;
        overlayDirty = true;
      }
    }

    // 4. Summon — filled in Task 4 (returns 0 for now).
    final summonsDue = _tickSummon(dt);

    return EnemyTickResult(
      reachedBase: false, diedByCorrosion: false, summonsDue: summonsDue, overlayDirty: overlayDirty,
    );
  }

  int _tickSummon(double dt) => 0; // Task 4 fills this in
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/enemy_logic_test.dart`
Expected: PASS (all tests including new tick-status tests).

- [ ] **Step 5: Commit**

```bash
git add lib/game/rules/enemy_logic.dart test/game/enemy_logic_test.dart
git commit -m "feat: EnemyLogic tick (corrosion/regen/slow) with overlayDirty (HPA-370)"
```

---

### Task 4: EnemyLogic summon tick

**Files:**
- Modify: `lib/game/rules/enemy_logic.dart`
- Modify: `test/game/enemy_logic_test.dart`

**Interfaces:**
- Consumes: `BossDefinition.summonMechanic`, `SummonMechanic`.
- Produces: `EnemyLogic._tickSummon` returns the bounded trigger count; `summonsDue` populated in `EnemyTickResult`.

- [ ] **Step 1: Write failing tests** appended to `enemy_logic_test.dart`:

```dart
  group('EnemyLogic summon', () {
    test('summonsDue fires after firstDelay then every interval', () {
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.relayBreaker, // firstDelay 4, interval 8, count 3
        waypoints: const [Offset(0, 0), Offset(10000, 0)],
      );
      expect(boss.tick(4.0).summonsDue, 1);
      expect(boss.tick(8.0).summonsDue, 1);
      expect(boss.tick(7.9).summonsDue, 0);
    });

    test('data-slot boss never summons', () {
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.shieldMatriarch, // no summonMechanic
        waypoints: const [Offset(0, 0), Offset(10000, 0)],
      );
      expect(boss.tick(100).summonsDue, 0);
    });

    test('summon loop is bounded when dt is unusually large', () {
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.relayBreaker,
        waypoints: const [Offset(0, 0), Offset(10000, 0)],
      );
      // Huge dt must not spin unboundedly; result is bounded and debt is shed.
      final due = boss.tick(1000).summonsDue;
      expect(due, lessThanOrEqualTo(16));
      expect(due, greaterThan(0));
    });

    test('reach-base frame produces no summons', () {
      // relayBreaker speed 46; path length 46*4 so it reaches base at t=4
      // (same frame firstDelay would fire).
      final boss = EnemyLogic(
        enemyId: 1,
        stats: GameBalance.relayBreaker,
        waypoints: const [Offset(0, 0), Offset(46 * 4, 0)],
      );
      final r = boss.tick(4.0);
      expect(r.reachedBase, isTrue);
      expect(r.summonsDue, 0);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/enemy_logic_test.dart --name "EnemyLogic summon"`
Expected: FAIL — `_tickSummon` always returns 0.

- [ ] **Step 3: Implement `_tickSummon`.** Replace the stub in `enemy_logic.dart`:

```dart
  int _tickSummon(double dt) {
    final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
    final mechanic = bossDef?.summonMechanic;
    if (mechanic == null || mechanic.interval <= 0) return 0;
    _summonRemaining -= dt;
    const maxSummonsPerFrame = 16;
    var summons = 0;
    while (_summonRemaining <= 0 && summons < maxSummonsPerFrame) {
      _summonRemaining += mechanic.interval;
      summons += 1;
    }
    if (_summonRemaining <= 0) {
      // Unusually large dt: shed the debt instead of carrying it forward.
      _summonRemaining = mechanic.interval;
    }
    return summons;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/enemy_logic_test.dart`
Expected: PASS (full pure-logic suite green).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: no issues in `enemy_logic.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/game/rules/enemy_logic.dart test/game/enemy_logic_test.dart
git commit -m "feat: EnemyLogic summon tick (bounded, debt-shed) (HPA-370)"
```

---

### Task 5: EnemyComponent delegates to logic + resolution contract (migration step 2)

**Files:**
- Modify: `lib/game/components/enemy_component.dart`
- Modify: `lib/game/orion_defense_game.dart` (`_spawnEnemy`, `_spawnMinion`)
- Modify: `test/game/enemy_component_test.dart` — every `EnemyComponent(...)` construction swaps the `waypoints:` argument for a `logic:` argument (an `EnemyLogic` built from the same stats + `Offset` waypoints); boss sites rename `onSummonMinions:` → `onSummonMinionsFn:`. Exact transformation in Step 5.

**Interfaces:**
- Consumes: `EnemyLogic` (Tasks 1-4).
- Produces: `EnemyComponent` takes `required EnemyLogic logic`; forwarders `applyDamage`/`applySlow`/`applyCorrosion`; `resolveKilled()`/`resolveReachedBase()`; `_resolutionDispatched` guard. The component **no longer accepts `waypoints`** (logic owns them); it seeds `position` from `logic.position`.

- [ ] **Step 1: Write a focused failing test** appended to `enemy_component_test.dart` proving the new resolution contract (death via forwarder fires the callback exactly once even though `logic.isResolved` is already true):

```dart
    test('applyDamage lethal fires onKilled exactly once via the new guard', () {
      var killed = 0;
      var removed = false;
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
        waypoints: const [Offset(0, 0), Offset(1000, 0)],
      );
      final enemy = EnemyComponent(
        logic: logic,
        onKilled: (_) => killed += 1,
        onReachedBase: (_) {},
      );
      enemy.applyDamage(10);
      expect(killed, 1);
      expect(logic.isResolved, isTrue);
      // A second lethal hit must not re-fire (guard holds even with logic already resolved).
      enemy.applyDamage(10);
      expect(killed, 1);
    });
```

(Add `import 'package:orion/game/rules/enemy_logic.dart';` and `import 'dart:ui';` at the top of the test file if missing.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/enemy_component_test.dart --name "applyDamage lethal fires onKilled exactly once"`
Expected: FAIL — `EnemyComponent` constructor doesn't take `logic` yet.

- [ ] **Step 3: Rewrite `EnemyComponent`.** In `lib/game/components/enemy_component.dart`:

Change the constructor to take `logic` and drop `waypoints`/`initialCompletedDistance`/`onSummonMinions` and all mutable combat/path fields. Keep sprite sheets, callbacks, minionOf. The temporary `update(dt)` delegates to `logic.tick` (using the Flame-scaled `dt` it receives) and dispatches results — preserve today's behavior. Replace the field block (lines ~49-82) and constructor with:

```dart
class EnemyComponent extends CircleComponent {
  EnemyComponent({
    required this.enemyId,
    required EnemyStats stats,
    required this.logic,
    required this.onKilled,
    required this.onReachedBase,
    this.spriteSheet,
    this.towerVarietySheet,
    this.bossSheet,
    this.minionOf,
    this.onSummonMinionsFn,
    double radius = 11,
    super.priority,
  })  : stats = stats,
        super(
          radius: radius,
          anchor: Anchor.center,
          position: Vector2(logic.position.dx, logic.position.dy),
          paint: Paint()..color = const Color(0xFFE35D6A),
        );

  final int enemyId;
  final EnemyStats stats;
  final EnemyLogic logic;
  final EnemyKilledCallback onKilled;
  final EnemyReachedBaseCallback onReachedBase;
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;
  final GameBossSheet? bossSheet;
  final int? minionOf;
  final void Function(EnemyComponent source, int count)? onSummonMinionsFn;

  bool _isInspected = false;
  bool _resolutionDispatched = false;
  EnemyOverlayState? _cachedOverlayState;
  bool _overlayDirty = true;

  static final EnemyOverlayRenderer _overlayRenderer = EnemyOverlayRenderer();

  // read-through getters to logic
  double get health => logic.health;
  double get shield => logic.shield;
  double get maxHealth => logic.maxHealth;
  bool get isAlive => logic.isAlive;
  bool get isResolved => logic.isResolved;
  bool get isInspected => _isInspected;
  bool get isCorroded => logic.isCorroded;
  bool get isSlowed => logic.isSlowed;
  double get armorReduction => logic.armorReduction;
  double get pathProgress => logic.pathProgress;

  void setInspected(bool value) {
    if (_isInspected == value) return;
    _isInspected = value;
    _overlayDirty = true;
  }

  void applyDamage(double amount,
      {double shieldDamageMultiplier = 1,
      double armorDamageMultiplier = 1,
      double armorShred = 0,
      bool bypassArmor = false}) {
    if (!isAlive || amount <= 0) return;
    final outcome = logic.applyDamage(amount,
        shieldDamageMultiplier: shieldDamageMultiplier,
        armorDamageMultiplier: armorDamageMultiplier,
        armorShred: armorShred,
        bypassArmor: bypassArmor);
    _overlayDirty = true;
    if (outcome.died) _resolve(onKilled);
  }

  void applySlow({required double multiplier, required double duration}) {
    if (!isAlive) return;
    logic.applySlow(multiplier: multiplier, duration: duration);
    _overlayDirty = true;
  }

  void applyCorrosion({
    required double damagePerSecond,
    required double duration,
    required double armorShred,
  }) {
    if (!isAlive) return;
    logic.applyCorrosion(
        damagePerSecond: damagePerSecond, duration: duration, armorShred: armorShred);
    _overlayDirty = true;
  }

  List<Vector2> residualWaypointsFromHere() =>
      [position.clone(), ...logic.residualWaypointsFromHere().map((o) => Vector2(o.dx, o.dy))];

  TargetCandidate get targetCandidate => TargetCandidate(
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

  void resolveKilled() => _resolve(onKilled);
  void resolveReachedBase() => _resolve(onReachedBase);

  void _resolve(void Function(EnemyComponent enemy) callback) {
    if (_resolutionDispatched) return;
    _resolutionDispatched = true;
    _overlayDirty = true;
    callback(this);
    removeFromParent();
  }

  // temporary (removed in Task 7): component still ticks during super.update
  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    final result = logic.tick(dt); // dt is already Flame-time-scaled
    position.setValues(logic.position.dx, logic.position.dy);
    if (result.overlayDirty) _overlayDirty = true;
    if (result.reachedBase) {
      resolveReachedBase();
    } else if (result.diedByCorrosion) {
      resolveKilled();
    } else {
      final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
      final mechanic = bossDef?.summonMechanic;
      if (mechanic != null) {
        for (var i = 0; i < result.summonsDue; i++) {
          onSummonMinionsFn?.call(this, mechanic.count);
        }
      }
    }
  }
```

Delete the old `overlayState` getter's reliance on local fields — it already reads through the getters above, so it stays valid. Delete `_moveAlongPath`, `_tickCorrosionAndRegen`, `_tickSlow`, `_currentSegmentLength`, `_initialSummonDelay`, and the old `_resolve`. Keep `render()` unchanged (it reads `stats`/`bossSheet`/`overlayState`). Keep `EnemyOverlayState get overlayState` unchanged.

Keep the typedefs `EnemyKilledCallback`/`EnemyReachedBaseCallback`. The `onSummonMinionsFn` field is the transitional summon hook (the orchestrator supplies `_handleSummonMinions`); Task 7 removes it along with the `update` override.

- [ ] **Step 4: Update the orchestrator construction.** In `lib/game/orion_defense_game.dart` `_spawnEnemy` (line ~654) and `_spawnMinion` (line ~691), construct `EnemyLogic` first, then `EnemyComponent`. Add a helper near the top of the class:

```dart
  List<Offset> _offsetWaypoints(List<Vector2> v) =>
      [for (final p in v) Offset(p.x, p.y)];
```

Rewrite `_spawnEnemy`:

```dart
  void _spawnEnemy(EnemyStats stats) {
    final bossDef = stats is BossDefinition ? stats : null;
    final waypoints = _pathWaypoints();
    final logic = EnemyLogic(
      enemyId: _nextEnemyId,
      stats: stats,
      waypoints: _offsetWaypoints(waypoints),
    );
    final enemy = EnemyComponent(
      enemyId: _nextEnemyId,
      stats: stats,
      logic: logic,
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      bossSheet: _bossSheet,
      onKilled: _handleEnemyKilled,
      onReachedBase: _handleEnemyReachedBase,
      onSummonMinionsFn: bossDef == null ? null : _handleSummonMinions,
      radius: bossDef == null ? 11 : 20,
      priority: 20,
    );
    _nextEnemyId += 1;
    _activeEnemyComponents[enemy.enemyId] = enemy;
    add(enemy);
  }
```

Rewrite `_spawnMinion`:

```dart
  void _spawnMinion(EnemyComponent boss, EnemyStats stats) {
    final residualOffsets = boss.logic.residualWaypointsFromHere();
    if (residualOffsets.length < 2) return;
    final logic = EnemyLogic(
      enemyId: _nextEnemyId,
      stats: stats,
      waypoints: residualOffsets,
      initialCompletedDistance: boss.logic.pathProgress,
    );
    final enemy = EnemyComponent(
      enemyId: _nextEnemyId,
      stats: stats,
      logic: logic,
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      minionOf: boss.enemyId,
      onKilled: _handleEnemyKilled,
      onReachedBase: _handleEnemyReachedBase,
      priority: 20,
    );
    _nextEnemyId += 1;
    _activeEnemyComponents[enemy.enemyId] = enemy;
    add(enemy);
  }
```

Add `import 'dart:ui';` to `orion_defense_game.dart` if `Offset` isn't already in scope (it likely is via flame re-export; if not, add the import). Add `import '../rules/enemy_logic.dart';`.

- [ ] **Step 5: Update the existing `enemy_component_test.dart` constructor call sites.** Every `EnemyComponent(...)` in this file currently passes `waypoints:` and (for bosses) `onSummonMinions:`. Transform each: construct an `EnemyLogic` from the same stats + waypoints, then pass `logic:` instead of `waypoints:`; rename `onSummonMinions:` to `onSummonMinionsFn:`. Example for the first site (line ~18):

```dart
// before
final enemy = EnemyComponent(
  enemyId: 1,
  stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
  waypoints: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)],
  onKilled: (_) {},
  onReachedBase: (_) {},
);
// after
final enemy = EnemyComponent(
  enemyId: 1,
  stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
  logic: EnemyLogic(
    enemyId: 1,
    stats: const EnemyStats(health: 10, speed: 10, baseDamage: 1, goldReward: 1),
    waypoints: const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
  ),
  onKilled: (_) {},
  onReachedBase: (_) {},
);
```

Apply the same transformation to every `EnemyComponent(` construction in `test/game/enemy_component_test.dart` (sites at lines ~18, ~42, ~64, ~91, ~112, ~140, ~165, ~185, ~205, ~245, ~270, ~291, ~324, ~351, ~372, ~392, ~407, ~421 — verify each with `rg 'EnemyComponent\(' test/game/enemy_component_test.dart`). For boss sites (e.g. line ~351 using `GameBalance.relayBreaker`), pass `onSummonMinionsFn:` and keep `logic:` with the boss stats. The boss summon tests at lines ~348 and ~370 should still pass unchanged in behavior because the component's temporary `update` dispatches summons via `_onSummonMinions`.

- [ ] **Step 6: Run the full component test file**

Run: `flutter test test/game/enemy_component_test.dart`
Expected: PASS (including the new resolution-contract test and the existing summon tests, which now run through `logic.tick`).

- [ ] **Step 7: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (the orchestrator tests that call `enemy.update(...)`/`boss.update(...)` still work because the component's temporary `update` still ticks logic).

- [ ] **Step 8: Commit**

```bash
git add lib/game/components/enemy_component.dart lib/game/orion_defense_game.dart test/game/enemy_component_test.dart
git commit -m "refactor: EnemyComponent delegates to EnemyLogic; resolution contract (HPA-370)"
```

---

### Task 6: Drive component tests via `logic.tick()` directly; slim the file

**Files:**
- Modify: `test/game/enemy_component_test.dart`

**Goal:** Stop calling `enemy.update(dt)` in the component tests so Task 7 can drop the override. Replace with `enemy.logic.tick(dt)` + `enemy.update(0)` is NOT used — instead call a public render-sync. Since `syncRender` is added in Task 7, expose a minimal temporary: tests call `enemy.logic.tick(dt)` then set position via the existing temporary `update(0)`? No — to keep this task green without Task 7's `syncRender`, add the `syncRender()`/`markOverlayDirty()` methods now (they're harmless ahead of the orchestrator wiring).

- [ ] **Step 1: Add `syncRender`/`markOverlayDirty` to `EnemyComponent`** (in `enemy_component.dart`), and refactor the temporary `update` to call them:

```dart
  void syncRender() {
    position.setValues(logic.position.dx, logic.position.dy);
  }
  void markOverlayDirty() => _overlayDirty = true;

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;
    final result = logic.tick(dt);
    syncRender();
    if (result.overlayDirty) markOverlayDirty();
    // ... dispatch as before ...
  }
```

- [ ] **Step 2: Rewrite the component-test `.update()` sites** to drive logic directly. Transformation rule for every `enemy.update(dt)` / `boss.update(dt)` call in `test/game/enemy_component_test.dart`:

```dart
// before
enemy.update(0.6);
// after
final _r = enemy.logic.tick(0.6);
enemy.syncRender();
```

For sites that then assert on summon side-effects (the `onSummonMinionsFn` callbacks), the dispatch no longer happens automatically (the component `update` is no longer called). For those specific tests (the summon-callback tests at lines ~348, ~370, ~407, ~421), after `enemy.logic.tick(dt)` dispatch the summons manually to exercise the callback:

```dart
final r = boss.logic.tick(4.0);
boss.syncRender();
final bossDef = boss.stats as BossDefinition;
final mechanic = bossDef.summonMechanic!;
for (var i = 0; i < r.summonsDue; i++) {
  bossOnSummonFn(boss, mechanic.count); // the test's recorded callback
}
```

(Where `bossOnSummonFn` is the callback passed as `onSummonMinionsFn:` — capture it in a local variable in the test.) Apply to the ~16 `.update()` sites in this file (lines 31, 34, 80, 84, 105, 129, 134, 158, 291, 316, 363, 365, 380, 400, 420, 434 per `rg '(enemy|boss)\.update\(' test/game/enemy_component_test.dart`). Movement-asserting sites need `syncRender()` before asserting on `enemy.position`.

- [ ] **Step 3: Slim the file.** Remove tests whose behavior is now fully covered by `enemy_logic_test.dart` (movement, shield-absorb, regen/corrosion, slow, summon counts) — keep only shell-specific tests: construction, `syncRender` position derivation, `targetCandidate` reflects logic, forwarder delegates + synchronous death (the resolution-contract test from Task 5), `residualWaypointsFromHere`, overlay cache invalidation on forwarder mutation.

- [ ] **Step 4: Run tests**

Run: `flutter test test/game/enemy_component_test.dart`
Expected: PASS (slimmed set; no test calls `enemy.update` anymore — verify with `rg '\.update\(' test/game/enemy_component_test.dart` returning no `enemy`/`boss` update calls).

- [ ] **Step 5: Commit**

```bash
git add lib/game/components/enemy_component.dart test/game/enemy_component_test.dart
git commit -m "test: drive component tests via logic.tick; slim to shell behavior (HPA-370)"
```

---

### Task 7: Relocate ticking to orchestrator; rewrite orchestrator-test `.update()` sites; add integration tests (migration step 3)

**Files:**
- Modify: `lib/game/orion_defense_game.dart` (`update`, new `_tickEnemyLogic`)
- Modify: `lib/game/components/enemy_component.dart` (drop `update` override, `_onSummonMinions`, transitional ctor param)
- Modify: `test/game/orion_defense_game_test.dart` (rewrite sites at 392, 475, 921, 958; add 4 integration tests)

- [ ] **Step 1: Add `_tickEnemyLogic` to the orchestrator and wire it into `update()`.** In `orion_defense_game.dart`, update `update()` (line ~368) to tick logic after `super.update`:

```dart
  @override
  void update(double dt) {
    if (_isPaused) {
      processLifecycleEvents();
      _removeInactiveEnemyReferences();
      return;
    }
    final scaledDt = dt * _speedMultiplier;

    super.update(dt);
    _removeInactiveEnemyReferences();

    if (scaledDt > 0 && _tickAutoStartCountdown(scaledDt)) return;
    if (_session.phase != GamePhase.wave) return;

    if (scaledDt > 0) {
      _tickEnemyLogic(scaledDt);
    }
    _removeInactiveEnemyReferences();
    if (scaledDt > 0) {
      _spawnWaveEnemies(scaledDt);
    }
    _removeInactiveEnemyReferences();
    _finishWaveIfComplete();
  }

  void _tickEnemyLogic(double dt) {
    for (final enemy in _activeEnemyComponents.values.toList()) {
      if (_session.phase != GamePhase.wave) break; // defeat/win ended combat
      if (!_activeEnemyComponents.containsKey(enemy.enemyId)) continue; // cleared this loop
      final logic = enemy.logic;
      if (!logic.isAlive) continue;
      final result = logic.tick(dt);
      enemy.syncRender();
      if (result.overlayDirty) enemy.markOverlayDirty();
      if (result.reachedBase) {
        enemy.resolveReachedBase();
      } else if (result.diedByCorrosion) {
        enemy.resolveKilled();
      } else {
        final bossDef = logic.stats is BossDefinition
            ? logic.stats as BossDefinition
            : null;
        final mechanic = bossDef?.summonMechanic;
        if (mechanic != null) {
          for (var i = 0; i < result.summonsDue; i++) {
            _handleSummonMinions(enemy, mechanic.count);
          }
        }
      }
    }
  }
```

- [ ] **Step 2: Drop the component's temporary `update` override and summon plumbing.** In `enemy_component.dart`, remove the `update(dt)` override entirely, remove `_onSummonMinions` and the `onSummonMinionsFn` constructor param. The component is now a pure shell (render + forwarders + syncRender/markOverlayDirty + resolve*).

- [ ] **Step 3: Rewrite the orchestrator-test `.update()` sites.** In `test/game/orion_defense_game_test.dart`, every `enemy.update(...)`/`boss.update(...)` is now a no-op. Transform each to pump `game.update(...)` (and `game.processLifecycleEvents()` where the test already uses it):

- Line 392 `enemy.update(100)` (clears inspected enemy) → replace with `game.update(0.01); game.processLifecycleEvents();` (enough to advance the inspected-enemy sweep).
- Line 475 `enemy.update(1)` (lost + pacing reset) → `game.update(1); game.processLifecycleEvents();`.
- Line 921 `enemy.update(1)` (base damage before restart) → `game.update(1); game.processLifecycleEvents();`.
- Line 958 `boss.update(0.5 + 0.01)` (summon) → `game.update(0.5 + 0.01); game.processLifecycleEvents();` and remove the comment about the concurrent-modification workaround.

Verify with `rg '(enemy|boss)\.update\(' test/game/orion_defense_game_test.dart` returning no matches after the rewrite.

- [ ] **Step 4: Add integration test — large-`dt` lethal corrosion (same-frame status acceleration).** First add a `_oneEnemyStage()` helper at the bottom of `orion_defense_game_test.dart` (next to `_emptyWaveStage` at line ~1001): a `StageDefinition` with one wave spawning a single `EnemyStats(health: 100, speed: 10, baseDamage: 1, goldReward: 1)` on the standard `pathCells`, following the `_emptyWaveStage` pattern. Then append the test:

```dart
    test('corrosion applied by a projectile ticks damage same frame (large dt)', () {
      final game = OrionDefenseGame(stage: _oneEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01); game.processLifecycleEvents();
      final enemy = game.children.whereType<EnemyComponent>().single;
      // Simulate a nanite hit applying corrosion mid-super.update, then a large tick.
      enemy.applyCorrosion(damagePerSecond: enemy.maxHealth, duration: 10, armorShred: 0);
      game.update(1); game.processLifecycleEvents();
      expect(enemy.isResolved, isTrue); // corrosion killed it this frame
    });
```

- [ ] **Step 5: Add integration test — multi-enemy defeat stops the tick loop.** Append:

```dart
    test('defeat mid-tick stops ticking remaining enemies', () {
      final game = OrionDefenseGame(stage: _twoEnemyDefeatStage());
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01); game.processLifecycleEvents();
      final goldBefore = game.snapshot.gold;
      // Advance: the lead enemy reaches base and (base health = 1) defeats.
      // The loop must break so the trailing enemy is NOT dispatched as killed.
      game.update(60); game.processLifecycleEvents();
      expect(game.snapshot.phase, GamePhase.lost);
      // reach-base never rewards gold; a spurious onKilled for the trailing
      // enemy would have called rewardKill and increased gold.
      expect(game.snapshot.gold, goldBefore);
    });
```

Add the helper at the bottom of the file next to `_emptyWaveStage` (line ~1001): a `StageDefinition` with `startingBaseHealth: 1`, one wave of two `EnemyStats(health: 100, speed: 10, baseDamage: 1, goldReward: 50)` enemies on the standard `pathCells`, following the existing `_emptyWaveStage`/`_bossSummonStage` pattern. The observable is gold: reach-base awards none, so any kill dispatch on the trailing enemy would raise gold above `goldBefore`.

- [ ] **Step 6: Add integration test — exactly-once callbacks across paths.** Append:

```dart
    test('onKilled fires exactly once when lethal damage lands on a would-overrun frame', () {
      final game = OrionDefenseGame(stage: _oneEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01); game.processLifecycleEvents();
      final enemy = game.children.whereType<EnemyComponent>().single;
      final goldBefore = game.snapshot.gold;
      // Lethal projectile damage during super.update frame, before the enemy's tick.
      enemy.applyDamage(enemy.maxHealth);
      game.update(0.01); game.processLifecycleEvents();
      // onKilled -> rewardKill adds goldReward exactly once.
      expect(game.snapshot.gold, goldBefore + enemy.stats.goldReward);
      enemy.applyDamage(enemy.maxHealth); // second lethal hit must not re-reward
      game.update(0.01); game.processLifecycleEvents();
      expect(game.snapshot.gold, goldBefore + enemy.stats.goldReward);
    });
```

Reuses `_oneEnemyStage()` from Step 4. The observable is the gold delta equal to exactly one `goldReward` — no `@visibleForTesting` hook needed.

- [ ] **Step 7: Add integration test — overlay reflects tick expiry.** Append:

```dart
    test('overlay drops slow/corrosion on tick expiry without an external apply', () {
      final game = OrionDefenseGame(stage: _oneEnemyStage());
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0.01); game.processLifecycleEvents();
      final enemy = game.children.whereType<EnemyComponent>().single;
      enemy.applySlow(multiplier: 0.5, duration: 1);
      enemy.applyCorrosion(damagePerSecond: 1, duration: 1, armorShred: 0);
      expect(enemy.overlayState.badges, contains(EnemyOverlayBadge.slowed));
      game.update(1); game.processLifecycleEvents(); // both expire via tick
      expect(enemy.isSlowed, isFalse);
      expect(enemy.isCorroded, isFalse);
      expect(enemy.overlayState.badges, isNot(contains(EnemyOverlayBadge.slowed)));
    });
```

(If `EnemyOverlayBadge`/`overlayState` import is needed, add `import 'package:orion/game/rules/enemy_overlay_state.dart';`.)

- [ ] **Step 8: Run the full suite and analyzer**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/game/orion_defense_game.dart lib/game/components/enemy_component.dart test/game/orion_defense_game_test.dart
git commit -m "refactor: orchestrator-owned enemy ticking; drop component update override (HPA-370)"
```

---

### Task 8: Cleanup and final verification (migration step 4)

**Files:**
- Modify: `lib/game/components/enemy_component.dart` (remove any dead fields/imports), `lib/game/rules/enemy_logic.dart` (finalize), `lib/game/orion_defense_game.dart`.

- [ ] **Step 1: Remove dead code.** In `enemy_component.dart`, delete any now-unused imports (`dart:math` if no longer referenced), the `_overlayDirty` field if overlay is fully lazy (it isn't — keep it), and confirm no references to removed symbols (`waypoints`, `_currentSegmentLength`, `onSummonMinions`). Run `flutter analyze` to find unused-element warnings and fix them.

- [ ] **Step 2: Verify the non-goals.** Confirm the three consumer files are unmodified:

Run: `git diff main -- lib/game/components/projectile_component.dart lib/game/components/drone_component.dart lib/game/components/gravity_field_component.dart`
Expected: no output (empty diff). If any shows changes, revert them.

Confirm `rules/enemy_logic.dart` imports only the allowed set:

Run: `rg '^import' lib/game/rules/enemy_logic.dart`
Expected: only `dart:math`, `dart:ui`, `../models/game_models.dart`, `combat_effects.dart`.

- [ ] **Step 3: Final full verification**

Run: `dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`
Expected: format clean, analyze clean, all tests pass.

- [ ] **Step 4: Commit (if any cleanup changes)**

```bash
git add -A
git commit -m "refactor: cleanup after EnemyLogic extraction (HPA-370)"
```

---

## Notes for the implementer

- **TDD discipline:** every task writes/updates the test first, watches it fail, implements, watches it pass, then commits. Do not batch tasks.
- **`Vector2` → `Offset` mapping:** `.length` → `.distance`; mutation (`position.setFrom`/`.add`) → reassignment (`position = position + ...`); `Vector2(x,y)` from `Offset(o.dx, o.dy)`.
- **Speed scaling:** the only place `dt` is multiplied by `_speedMultiplier` for logic is `_tickEnemyLogic(scaledDt)`. Never multiply inside `logic.tick`. The existing `orion_defense_game_test.dart:399` '3x speed accelerates real enemy progress' test guards a double-apply.
- **If a test helper referenced (`_emptyWaveStage`, `_bossSummonStage`, `_twoEnemyDefeatStage`) doesn't exist**, add it at the bottom of `orion_defense_game_test.dart` next to the existing `_emptyWaveStage` (line ~1001), following its pattern.
- **Acceptance criteria** are the spec's: shell-only component, Flame-free logic, unchanged consumer files + 16 orchestrator sites, no `.update()`-dependent test, exactly-once callbacks, overlay reflects tick expiry.
