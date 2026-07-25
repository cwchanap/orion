# Orion Enemy Logic Extraction Design

## Context

HPA-370 is a refactor that separates per-enemy game logic from `EnemyComponent` rendering. Orion's `AGENTS.md` mandates a strict boundary between pure game logic (`rules/`, `models/` — deterministic, unit-tested, no Flame imports) and the Flame rendering/simulation layer (`components/`). `GameSession`, `CombatEffects`, `TowerTargeting`, and `BoardLayout` already follow this boundary. `EnemyComponent` does not.

Today `lib/game/components/enemy_component.dart` (`EnemyComponent.update`, line 253) owns per-enemy mutable game-logic state and the per-tick orchestration of it:

- Movement: `_moveAlongPath` (line 305)
- Slow: `_tickSlow`, `_slowMultiplier`, `_slowRemaining` (line 373)
- Corrosion/regen: `_tickCorrosionAndRegen`, `_corrosionDamagePerSecond`, `_corrosionRemaining` (line 341)
- Armor shred: `_armorShred` (field at line 73)
- Shield/health: `shield`, `health`, `applyDamage` (line 152)
- Summon timer: `_summonRemaining`, `onSummonMinions` callback (lines 274-293)

The pure damage/slow/regen math is already extracted into `CombatEffects` (`rules/combat_effects.dart`); what remains inside the component is the per-enemy mutable state and the per-tick sequencing of that state. `_moveAlongPath` further interleaves pure distance bookkeeping with pixel-position mutation and resolution callbacks.

## Goal

Move all per-enemy game logic out of `EnemyComponent` into a new pure, deterministic, Flame-free class `EnemyLogic` in `rules/enemy_logic.dart`, with per-frame ticking owned by `OrionDefenseGame`. Leave `EnemyComponent` as a render/animation shell that holds a back-reference to its `EnemyLogic`, exposes thin forwarders for the combat inputs, and derives its render state (pixel position, overlay) from logic state.

## Non-goals (out of scope)

- `TowerComponent`, `ProjectileComponent`, `DroneComponent`, `GravityFieldComponent` — these keep calling the unchanged `applyDamage`/`applySlow`/`applyCorrosion` forwarders and are otherwise untouched. No call-site changes outside `enemy_component.dart` and `orion_defense_game.dart`.
- The partial single-timer move proposed in the original review (move only the summon timer). It is explicitly rejected: it breaks 3 tests, duplicates per-boss state in the orchestrator, and contradicts the boss-waves plan (`docs/superpowers/plans/2026-07-23-orion-boss-waves-named-elites.md` Task 8) without achieving a coherent boundary.
- Changing `CombatEffects`, `TowerTargeting`, `BoardLayout`, or `GameSession`.
- Changing enemy balance or behavior. This refactor must be observably behavior-preserving; the existing rule/behavior tests are the regression net.

## Architecture

### New pure class: `rules/enemy_logic.dart`

`EnemyLogic` is a Flame-free class that owns all per-enemy mutable game state and the tick/apply math. It imports only `dart:math` and `../models/game_models.dart` (for `EnemyStats`, `BossDefinition`, `SummonMechanic`). It never imports `package:flame` and never touches pixel coordinates.

**Immutable inputs (constructor):**

```dart
class EnemyLogic {
  EnemyLogic({
    required int enemyId,
    required EnemyStats stats,
    required List<double> segmentLengths, // precomputed from waypoints
    double initialCompletedDistance = 0,
  });
}
```

`segmentLengths[i]` is the pixel length of the path segment between waypoint `i` and `i+1`. The component precomputes this list from its `Vector2 waypoints` at construction (it owns the pixel geometry; the logic owns only the distances). `totalPathLength` is derived as the sum.

The `_initialSummonDelay` static helper (currently on `EnemyComponent`) moves here, unchanged.

**Mutable state (owned, all moved off the component):**

Combat: `health`, `shield`, `maxHealth` (final, from `stats.health`), `armorShred`, `slowMultiplier`, `slowRemaining`, `corrosionDamagePerSecond`, `corrosionRemaining`, `summonRemaining`.

Path bookkeeping (plain doubles): `targetWaypointIndex` (starts at 1), `completedDistance`, `segmentProgress`.

Resolution: `isResolved` (bool).

**Derived getters:** `isAlive` (`!isResolved && health > 0`), `isSlowed`, `isCorroded`, `armorReduction` (the clamped `stats.armorReduction - armorShred`), `pathProgress` (`completedDistance + currentSegmentLength * segmentProgress`).

**Tick API:**

```dart
class EnemyTickResult {
  final bool reachedBase;
  final bool diedByCorrosion;
  final int summonsDue;
}
EnemyTickResult tick(double dt);
```

`tick` runs the exact ordered sequence currently in `EnemyComponent.update`, terminating at most one resolution:

1. Corrosion/regen (`_tickCorrosionAndRegen`): decrement `_corrosionRemaining`, apply `_corrosionDamagePerSecond * tick` as bypass-armor damage via `CombatEffects.resolveDamage`, clear shred when corrosion expires, then `CombatEffects.applyRegen` gated on `wasCorrodedAtTickStart`. If health hits 0, set `isResolved` and return `diedByCorrosion: true`.
2. Movement (the `_moveAlongPath` loop): advance `targetWaypointIndex`/`completedDistance`/`segmentProgress` against `segmentLengths` using `stats.speed * movementSlowMultiplier * dt`. If it runs off the end, set `isResolved` and return `reachedBase: true`.
3. Slow decay (`_tickSlow`): decrement `_slowRemaining`, reset `_slowMultiplier` to 1 at expiry.
4. Summon timer (boss-only): decrement `_summonRemaining`, accumulate triggers with the existing `maxSummonsPerFrame = 16` bound and debt-shed (`_summonRemaining = interval` on overflow). Return `summonsDue: <count>`. This step is skipped entirely if a resolution occurred in steps 1-2 — preserving the "no summon on the resolve frame" guard.

`tick` never calls back into the world; it reports events. `movementSlowMultiplier` uses `isSlowed ? slowMultiplier : 1.0` exactly as today (captured before step 3 mutates slow).

**Combat-input API:**

```dart
class DamageOutcome {
  final bool died;
}
DamageOutcome applyDamage(double amount, {double shieldDamageMultiplier, double armorDamageMultiplier, double armorShred, bool bypassArmor});
void applySlow({required double multiplier, required double duration});
void applyCorrosion({required double damagePerSecond, required double duration, required double armorShred});
```

These carry the existing guard clauses and delegate the merge math to `CombatEffects` (`resolveDamage`, `mergeSlow`). `applyDamage` sets `isResolved` and returns `died: true` when health reaches 0, so the caller can resolve synchronously. These methods are safe to call between ticks (external damage arrives during `super.update`).

### Ownership: orchestrator-owned, component holds a back-reference

`OrionDefenseGame` constructs one `EnemyLogic` per enemy inside `_spawnEnemy`/`_spawnMinion` and owns the instances. To keep the logic and component references in lockstep without two drifting maps, `Map<int, EnemyComponent> _activeEnemyComponents` is replaced by:

```dart
class _ActiveEnemy {
  EnemyLogic logic;
  EnemyComponent component;
}
final Map<int, _ActiveEnemy> _activeEnemies = {};
```

A private `_registerEnemy(EnemyLogic, EnemyComponent)` and `_unregisterEnemy(int id)` are the only mutators of the map. Call-site changes are mechanical:

- **Readers** become `entry.component`/`entry.logic` accesses: `_handleSummonMinions` (counts `entry.component.minionOf`), `_spawnEnemy`/`_spawnMinion` (construct logic + component, call `_registerEnemy`), `_removeInactiveEnemyReferences` (sweeps by `entry.component.isResolved`, now a read-through getter to `logic.isResolved`).
- **Mutators** route through `_unregisterEnemy`: `_handleEnemyKilled`, `_handleEnemyReachedBase` (currently `_activeEnemyComponents.remove(id)`), and `_clearCombatComponents` (currently `.clear()` plus `removeFromParent` on each value — iterate `entry.component`).

`EnemyComponent` receives `EnemyLogic logic` as a required constructor field and keeps it as `final` — the back-reference for forwarders, render sync, and read-through getters.

### New tick flow in `OrionDefenseGame.update()`

A new `_tickEnemyLogic(double dt)` phase runs once per frame inside the wave branch, using `scaledDt` (`dt * _speedMultiplier`), since `EnemyLogic` is not a Flame component and is not affected by `timeScale`. Updated `update()` body:

```dart
@override
void update(double dt) {
  if (_isPaused) {
    processLifecycleEvents();
    _removeInactiveEnemyReferences();
    return;
  }
  final scaledDt = dt * _speedMultiplier;

  super.update(dt);                       // Flame: projectiles/drones fly, hit enemies via forwarders
  _removeInactiveEnemyReferences();

  if (scaledDt > 0 && _tickAutoStartCountdown(scaledDt)) return;
  if (_session.phase != GamePhase.wave) return;

  if (scaledDt > 0) {
    _tickEnemyLogic(scaledDt);            // NEW: pure status/movement/summon + render sync
  }
  _removeInactiveEnemyReferences();
  if (scaledDt > 0) {
    _spawnWaveEnemies(scaledDt);
  }
  _removeInactiveEnemyReferences();
  _finishWaveIfComplete();
}
```

`_tickEnemyLogic` iterates a snapshot of `_activeEnemies.values`, dispatches `tick()` events to the existing handlers, and calls `syncRender()`:

```dart
void _tickEnemyLogic(double dt) {
  for (final entry in _activeEnemies.values.toList()) {
    if (!entry.logic.isAlive) continue;
    final result = entry.logic.tick(dt);
    entry.component.syncRender();
    if (result.reachedBase) {
      entry.component.resolveReachedBase();
    } else if (result.diedByCorrosion) {
      entry.component.resolveKilled();
    } else {
      final mechanic = (entry.logic.stats is BossDefinition)
          ? (entry.logic.stats as BossDefinition).summonMechanic
          : null;
      if (mechanic != null) {
        for (var i = 0; i < result.summonsDue; i++) {
          _handleSummonMinions(entry.component, mechanic.count);
        }
      }
    }
  }
}
```

`_handleSummonMinions` keeps its existing cap logic (count active minions of this boss, clamp to `mechanic.maxActive`). Summon-elapsed, cap, and minion-registry bookkeeping remain in the orchestrator; the orchestrator simply reads `summonsDue` from the pure tick rather than the component firing a callback. The previous `onSummonMinions` field is removed from `EnemyComponent`.

## Damage / event flow

**External damage** (projectile/drone/gravity → `enemy.applyDamage`): the forwarder mutates logic and resolves death synchronously so the existing `isResolved` sweep and test intent are preserved:

```dart
DamageOutcome applyDamage(...) {           // forwarder on EnemyComponent
  if (!isAlive || amount <= 0) return;
  final outcome = logic.applyDamage(...);  // mutates logic.health/shield
  _overlayDirty = true;
  if (outcome.died) _resolve(onKilled);    // synchronous
}
void applySlow(...)      { logic.applySlow(...);      _overlayDirty = true; }
void applyCorrosion(...) { logic.applyCorrosion(...); _overlayDirty = true; }
```

`_resolve` stays on the component (it owns `removeFromParent`), exposed via two thin public methods so the orchestrator can drive resolution from `_tickEnemyLogic`:

- `void resolveKilled()` → `_resolve(onKilled)`
- `void resolveReachedBase()` → `_resolve(onReachedBase)`

Death-by-external-damage resolves synchronously inside the forwarder (during `super.update`); death-by-corrosion and reach-base resolve from `_tickEnemyLogic`. Both funnel through the same `_resolve` → callback → orchestrator handler path.

## `EnemyComponent` surface after refactor

**Stays (render/identity):** `enemyId`, `stats`, `waypoints`, sprite-sheet refs (`spriteSheet`, `towerVarietySheet`, `bossSheet`), `minionOf`, `onKilled`, `onReachedBase`, `final EnemyLogic logic`, `render()`, overlay cache (`_cachedOverlayState`, `_overlayDirty`), `setInspected`, `residualWaypointsFromHere()`, `targetCandidate`, `syncRender()`, `resolveKilled()`/`resolveReachedBase()`/`_resolve()`.

**Becomes read-through getters to `logic`** (every external reader — targeting, orchestrator, tests — unchanged): `health`, `shield`, `maxHealth`, `isAlive`, `isResolved`, `isSlowed`, `isCorroded`, `armorReduction`, `pathProgress`.

**Leaves the component (moves to `EnemyLogic`):** `_moveAlongPath`, `_tickCorrosionAndRegen`, `_tickSlow`, `_currentSegmentLength`, `_initialSummonDelay`, `onSummonMinions`, and all mutable combat/path fields (`_slowMultiplier`, `_slowRemaining`, `_corrosionDamagePerSecond`, `_corrosionRemaining`, `_armorShred`, `_summonRemaining`, `_targetWaypointIndex`, `_completedDistance`, `_segmentProgress`, plus the public-mutable `health`/`shield` which become read-only getters).

**`update()` override is removed** (or reduced to a no-op `super.update(dt)`). All advance happens in `_tickEnemyLogic`; `syncRender()` (called from there) sets `position` from logic path state, and the `overlayState` getter lazily recomputes when `_overlayDirty`:

```dart
void syncRender() {
  if (logic.targetWaypointIndex >= waypoints.length) return; // resolved; position frozen
  final start = waypoints[logic.targetWaypointIndex - 1];
  final end = waypoints[logic.targetWaypointIndex];
  position.setFrom(start + (end - start) * logic.segmentProgress);
}
```

`residualWaypointsFromHere()` and `targetCandidate` derive from the synced `position` plus logic fields (`logic.targetWaypointIndex`, `logic.pathProgress`, `logic.health`, `logic.shield`), preserving minion-seeding and targeting behavior.

## Testing

| Today | After |
|---|---|
| `test/game/enemy_component_test.dart` (~1052 lines; logic tested through the component) | **`test/game/enemy_logic_test.dart`** (new, pure, no Flame): movement/waypoint-crossing over `segmentLengths`, shield-absorb, regen-vs-corrosion pause, slow movement + expiry, regen-stays-paused-during-corrosion-expiry, lethal-damage resolution, summon `summonsDue` count + bounded-loop + reach-base-skips-summon + data-slot-boss-never-summons. All assertions run against `EnemyLogic` with plain doubles. |
| | **`test/game/enemy_component_test.dart`** (slimmed): construction + `syncRender` position derivation, `targetCandidate` reflects logic state, forwarder delegates + synchronous death resolution, `residualWaypointsFromHere`, overlay cache invalidation on logic mutation. |
| `test/game/orion_defense_game_test.dart:940` (calls `boss.update(0.5 + 0.01)` directly to trigger summon) | Rewritten to pump `game.update(0.5 + 0.01)`. Summon now fires inside `_tickEnemyLogic`; the "call `boss.update()` directly to avoid concurrent-modification" workaround is obsolete because summon `add()`s happen in the orchestrator's map loop, not during Flame's tree iteration. |
| `test/game/game_balance_test.dart` `SummonMechanic` group (line 1136) | **Unchanged** — it tests the data type, not the tick. |

New tests are written test-first, before each production step (see Migration).

## Migration

Each step leaves `flutter analyze` and `flutter test` green.

1. **Add `EnemyLogic` + `enemy_logic_test.dart`.** Introduce the pure class with all state/tick/apply methods and the `_initialSummonDelay`/`maxSummonsPerFrame`/debt-shed logic. Port the behavioral assertions from the component test as pure-logic tests. No production wiring yet; the new file stands alone and its tests pass.
2. **Make `EnemyComponent` delegate.** Add `final EnemyLogic logic`, route `applyDamage`/`applySlow`/`applyCorrosion` and a (temporary) `update()` through it, swap the mutable fields for read-through getters, and precompute `segmentLengths` for the logic. Existing `enemy_component_test.dart` stays green (it now exercises the component+logic delegation).
3. **Relocate ticking to the orchestrator.** Introduce `_ActiveEnemy`/`_activeEnemies` + `_registerEnemy`/`_unregisterEnemy`, add `_tickEnemyLogic`, replace `_activeEnemyComponents` references, and add `syncRender()`/`resolveKilled()`/`resolveReachedBase()`. Drop the `EnemyComponent.update()` override and remove `onSummonMinions`. Rewrite the orchestrator summon test (line 940) and slim/rewrite `enemy_component_test.dart` per the table above.
4. **Cleanup pass.** Remove any dead fields, run `flutter analyze` and the full `flutter test` suite, and confirm the four affected test areas (`enemy_component_test.dart`, `orion_defense_game_test.dart:940`, `game_balance_test.dart:1136` unchanged) behave as specified.

## References

- Linear: [HPA-370](https://linear.app/cwchanap/issue/HPA-370/refactor-separate-game-logic-from-enemycomponent-rendering)
- Architecture: `AGENTS.md` (logic/rendering separation; `rules/` is pure, no Flame)
- Boss-waves plan (Task 8 placed the summon timer in `EnemyComponent`): `docs/superpowers/plans/2026-07-23-orion-boss-waves-named-elites.md`
- Existing pure combat math: `lib/game/rules/combat_effects.dart`
- Component under refactor: `lib/game/components/enemy_component.dart`
- Orchestrator: `lib/game/orion_defense_game.dart` (`update` at line 368, `_handleSummonMinions` at line 674)

## Acceptance criteria

- `EnemyComponent` contains no per-enemy game logic: no status timers, no movement advance, no summon timing, no mutable combat state. It only renders, forwards combat inputs, syncs render state from `logic`, and resolves.
- `rules/enemy_logic.dart` is Flame-free (`flutter analyze` clean; no `package:flame` import) and fully unit-testable with plain doubles.
- `OrionDefenseGame` owns the logic instances and ticks them in `_tickEnemyLogic`; the `_ActiveEnemy` holder is the single source of truth for the logic↔component pairing.
- The 5 external call sites in `ProjectileComponent`/`DroneComponent`/`GravityFieldComponent` are unchanged (they still call `applyDamage`/`applySlow`/`applyCorrosion`).
- Behavior is preserved: the ported `enemy_logic_test.dart`, the rewritten component/orchestrator tests, and the rest of the suite pass; `game_balance_test.dart` `SummonMechanic` group is untouched.
