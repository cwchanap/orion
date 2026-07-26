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
- Changing enemy balance. This refactor preserves enemy *behavior* (same status math, same summon timing, same death/reach-base outcomes) with three accepted, imperceptible frame-level shifts documented below under [Intra-frame ordering and movement model](#intra-frame-ordering-and-movement-model). It is **not** bit-identical per-frame ordering. The existing rule/behavior tests (plus the ported `enemy_logic_test.dart`) are the regression net.

## Architecture

### New pure class: `rules/enemy_logic.dart`

`EnemyLogic` is a Flame-free class that owns all per-enemy mutable game state and the tick/apply math. It imports only `dart:math`, `../models/game_models.dart` (for `EnemyStats`, `BossDefinition`, `SummonMechanic`), and `combat_effects.dart` (for `resolveDamage`/`mergeSlow`/`applyRegen` — a sibling pure module; `CombatEffects` itself is unchanged). It never imports `package:flame` and never touches pixel coordinates.

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

`segmentLengths[i]` is the pixel length of the path segment between waypoint `i` and `i+1`. Because `EnemyLogic` must stay Flame-free, it cannot accept `Vector2` waypoints, so the **orchestrator** computes `segmentLengths` from its `List<Vector2>` waypoints via a small helper (e.g. `List<double> _segmentLengths(List<Vector2> waypoints)`) and hands the plain-doubles list to the logic. `totalPathLength` is derived as the sum. This avoids a construction cycle: the orchestrator computes waypoints → computes `segmentLengths` → constructs `EnemyLogic` → constructs `EnemyComponent` (which receives *both* the `Vector2` waypoints, for rendering/position-derivation, and the already-built `logic`). For minions, `_spawnMinion` computes `segmentLengths` from `boss.residualWaypointsFromHere()` the same way. The component never computes `segmentLengths` itself.

The `_initialSummonDelay` static helper (currently on `EnemyComponent`) moves here, unchanged.

**Mutable state (owned, all moved off the component):**

Combat: `health`, `shield`, `maxHealth` (final, from `stats.health`), `armorShred`, `slowMultiplier`, `slowRemaining`, `corrosionDamagePerSecond`, `corrosionRemaining`, `summonRemaining`.

Path bookkeeping (plain doubles): `targetWaypointIndex` (starts at 1), `completedDistance`, `segmentProgress`.

Resolution: `isResolved` (bool) — the **terminal-state marker**. Set by `applyDamage` when health reaches 0 and by `tick` on corrosion-death or path overrun. It drives `isAlive`. It is *not* the dispatch guard for the component's side effects (see Resolution contract below).

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
4. Summon timer (boss-only): only when `stats is BossDefinition` with a `summonMechanic` whose `interval > 0` (porting the full `mechanic != null && mechanic.interval > 0` guard from today; the `onSummonMinions != null` half is gone since the orchestrator always supplies the handler). Decrement `_summonRemaining`, accumulate triggers with the existing `maxSummonsPerFrame = 16` bound and debt-shed (`_summonRemaining = interval` on overflow). Return `summonsDue: <count>`. This step is skipped entirely if a resolution occurred in steps 1-2 — preserving the "no summon on the resolve frame" guard.

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
  final EnemyLogic logic;
  final EnemyComponent component;
  _ActiveEnemy(this.logic, this.component);
}
final Map<int, _ActiveEnemy> _activeEnemies = {};
```

A private `_registerEnemy(EnemyLogic, EnemyComponent)` and `_unregisterEnemy(int id)` are the only mutators of the map. Call-site changes are mechanical:

- **Readers** become `entry.component`/`entry.logic` accesses: `_handleSummonMinions` (counts `entry.component.minionOf`), `_spawnEnemy`/`_spawnMinion` (construct logic + component, call `_registerEnemy`), `_removeInactiveEnemyReferences` (sweeps by `entry.component.isResolved`, now a read-through getter to `logic.isResolved`).
- **Mutators** route through `_unregisterEnemy`: `_handleEnemyKilled`, `_handleEnemyReachedBase` (currently `_activeEnemyComponents.remove(id)`), and `_clearCombatComponents` (currently `.clear()` plus `removeFromParent` on each value — iterate `entry.component`).

`EnemyComponent` receives `EnemyLogic logic` as a required constructor field and keeps it as `final` — the back-reference for forwarders, render sync, and read-through getters. `stats` and `enemyId` are **not** duplicated state: the component retains them as the public identity API, and the logic holds the same immutable references (passed through at construction) so pure tests can construct a logic standalone. One source of truth, two handles.

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

`_tickEnemyLogic` iterates a snapshot of `_activeEnemies.values`, dispatches `tick()` events to the existing handlers, and calls `syncRender()`. The loop guards against combat ending mid-iteration: a reach-base that triggers defeat clears the whole registry via `_clearCombatComponents` (loss path), so the loop must stop when the phase leaves `wave` and skip any entry unregistered during this loop:

```dart
void _tickEnemyLogic(double dt) {
  for (final entry in _activeEnemies.values.toList()) {
    if (_session.phase != GamePhase.wave) break;            // defeat/win ended combat
    if (!_activeEnemies.containsKey(entry.logic.enemyId)) continue; // cleared this loop
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

Without these guards, a defeat triggered by the first enemy to reach base would leave the snapshot iterating over now-cleared entries and dispatch `onKilled`/`onReachedBase` for enemies that were merely despawned by the loss sweep (harmless to the session — `rewardKill`/`damageBase` guard on `phase == wave` — but semantically wrong and produces stray snapshot publishes). A multi-enemy defeat test (first enemy reaches base and drops base health to 0; assert the remaining snapshot entries are *not* ticked or dispatched) is required.

`_handleSummonMinions` keeps its existing cap logic (count active minions of this boss, clamp to `mechanic.maxActive`). Summon-elapsed, cap, and minion-registry bookkeeping remain in the orchestrator; the orchestrator simply reads `summonsDue` from the pure tick rather than the component firing a callback. The previous `onSummonMinions` field is removed from `EnemyComponent`.

## Damage / event flow

**External damage** (projectile/drone/gravity → `enemy.applyDamage`): the forwarder mutates logic and resolves death synchronously so the existing `isResolved` sweep and test intent are preserved:

```dart
void applyDamage(...) {                      // forwarder on EnemyComponent — stays void (zero API churn)
  if (!isAlive || amount <= 0) return;
  final outcome = logic.applyDamage(...);    // mutates logic.health/shield, sets logic.isResolved, returns {died}
  _overlayDirty = true;
  if (outcome.died) _resolve(onKilled);      // synchronous
}
void applySlow(...)      { logic.applySlow(...);      _overlayDirty = true; }
void applyCorrosion(...) { logic.applyCorrosion(...); _overlayDirty = true; }
```

The forwarder stays `void` to keep the 5 external call sites unchanged; only `EnemyLogic.applyDamage` returns `DamageOutcome` (it needs to tell the forwarder whether to resolve). `applySlow`/`applyCorrosion` cannot kill, so they need no outcome.

### Resolution contract

`logic.isResolved` (terminal marker) and the component's side-effect dispatch are **separate concerns** with a single shared dispatch rule, so callbacks fire exactly once whether death arrives via the external-damage forwarder or via `_tickEnemyLogic`:

- `logic.isResolved` — set by `applyDamage` (health→0) and by `tick` (corrosion death, path overrun). Drives `isAlive`. Pure state.
- `component._resolutionDispatched` — a **new** once-guard, distinct from `logic.isResolved`, owned by the component. Guards `_resolve`'s side effects only.

`_resolve` is rewritten to guard on `_resolutionDispatched`, **not** on `logic.isResolved` (guarding on `logic.isResolved` would drop the callback, since `tick`/`applyDamage` set it before `_resolve` runs):

```dart
void _resolve(void Function(EnemyComponent) callback) {
  if (_resolutionDispatched) return;
  _resolutionDispatched = true;
  _overlayDirty = true;
  callback(this);          // onKilled / onReachedBase -> orchestrator handler
  removeFromParent();
}
```

Exposed via two thin public methods so the orchestrator drives resolution from `_tickEnemyLogic`:

- `void resolveKilled()` → `_resolve(onKilled)`
- `void resolveReachedBase()` → `_resolve(onReachedBase)`

Sequences (both share the one dispatch):

- **External damage:** `logic.applyDamage` sets `logic.isResolved` + returns `died` → forwarder calls `_resolve(onKilled)` → dispatches once + removes. (During `super.update`.)
- **Tick-driven:** `tick` sets `logic.isResolved` + returns `reachedBase`/`diedByCorrosion` → orchestrator calls `resolveReachedBase()`/`resolveKilled()` → dispatches once + removes. (During `_tickEnemyLogic`.)

`onKilled`/`onReachedBase` each fire exactly once per enemy. The component's public `isResolved` getter delegates to `logic.isResolved` (for `_removeInactiveEnemyReferences` and tests).

## `EnemyComponent` surface after refactor

**Stays (render/identity):** `enemyId`, `stats`, `waypoints`, sprite-sheet refs (`spriteSheet`, `towerVarietySheet`, `bossSheet`), `minionOf`, `onKilled`, `onReachedBase`, `final EnemyLogic logic`, `render()`, overlay cache (`_cachedOverlayState`, `_overlayDirty`), `setInspected`, `residualWaypointsFromHere()`, `targetCandidate`, `syncRender()`, `resolveKilled()`/`resolveReachedBase()`/`_resolve()`.

**Becomes read-through getters to `logic`** (every external reader — targeting, orchestrator, tests — unchanged): `health`, `shield`, `maxHealth`, `isAlive`, `isResolved`, `isSlowed`, `isCorroded`, `armorReduction`, `pathProgress`.

**Leaves the component (moves to `EnemyLogic`):** `_moveAlongPath`, `_tickCorrosionAndRegen`, `_tickSlow`, `_currentSegmentLength`, `_initialSummonDelay`, `onSummonMinions`, and all mutable combat/path fields (`_slowMultiplier`, `_slowRemaining`, `_corrosionDamagePerSecond`, `_corrosionRemaining`, `_armorShred`, `_summonRemaining`, `_targetWaypointIndex`, `_completedDistance`, `_segmentProgress`, plus the public-mutable `health`/`shield` which become read-only getters).

**`update()` override is removed** (or reduced to a no-op `super.update(dt)`). All advance happens in `_tickEnemyLogic`; `syncRender()` (called from there) sets `position` from logic path state, and the `overlayState` getter lazily recomputes when `_overlayDirty`:

```dart
void syncRender() {
  _overlayDirty = true; // tick-driven slow/corrosion/regen changes don't dirty; recompute each tick
  if (logic.targetWaypointIndex >= waypoints.length) return; // resolved; position frozen
  final start = waypoints[logic.targetWaypointIndex - 1];
  final end = waypoints[logic.targetWaypointIndex];
  position.setFrom(start + (end - start) * logic.segmentProgress);
}
```

`syncRender()` is called every ticked frame from `_tickEnemyLogic`, so it unconditionally marks the overlay dirty. This is required because tick-internal state changes (slow expiry, corrosion clear/expiry, regen, corrosion damage) happen inside `logic.tick` and have no path to the component's `_overlayDirty`; without this, a slow ring or corrosion badge would stick until the next external `apply*` call. The cache still pays off in non-ticked frames (build phase, paused). (`apply*` forwarders also set `_overlayDirty` so external damage between ticks refreshes immediately.)

`residualWaypointsFromHere()` and `targetCandidate` derive from the synced `position` plus logic fields (`logic.targetWaypointIndex`, `logic.pathProgress`, `logic.health`, `logic.shield`), preserving minion-seeding and targeting behavior.

### Intra-frame ordering and movement model

Three accepted, intentional departures from the current per-frame execution, all imperceptible at 60fps and standard for tower-defense loops:

1. **Enemy tick batching (one-frame hit/position shift).** Today Flame updates components in priority order — Tower(10) → Enemy(20) → GravityField(25) → Projectile(30) → Drone(35) — so enemies move/status *before* projectiles and drones update, and hits land against post-move positions. After extraction, all enemy status/movement advances in a single `_tickEnemyLogic` batch *after* `super.update`, so this frame's hits land against the previous tick's positions (one-frame shift), and towers fire before enemies move. There is no way to keep the per-priority interleaving while centralizing enemy ticks; the shift is inherent to the boundary move. Speed/path/summon/rate behavior is unaffected because per-frame advancement is unchanged. Tests assert outcomes via pump-and-check (not bit-exact frame ordering).
2. **Same-frame status acceleration (the consequential one — integration-tested).** Because `_tickEnemyLogic` runs *after* `super.update`, a slow/corrosion applied by a projectile or gravity field during `super.update` is acted on by the enemy's own tick *this same frame* (movement slows, corrosion deals damage and consumes duration immediately). Today those inputs don't affect the enemy's tick until *next* frame (enemy priority 20 < projectile/gravity 30/25). We accept this rather than buffer inputs: buffering would defer `isSlowed`/`isCorroded` observability and break the same-frame combat interaction `ProjectileComponent._resolveHit` relies on (`damageAgainstSlowState` reads `target.isSlowed` synchronously so a second projectile hitting an already-slowed enemy the same frame gets the bonus). Forwarders keep mutating immediately, so combat-input observability is unchanged; only the enemy *self-tick* lands one frame earlier. Net effect over time is identical (corrosion's total damage is bounded by `damagePerSecond * duration`); only the frame boundary shifts. **Integration test required:** apply corrosion via a projectile under a large `dt` and assert lethal timing is consistent (the large-`dt` lethal-corrosion case is the observable edge).
3. **Parametric movement (intentional semantic cleanup).** The current `_moveAlongPath` advances a live `Vector2 position` using `distanceToTarget` each frame; the new logic advances pure `segmentLengths`/`segmentProgress`, and `syncRender` derives position as `start + (end-start)*segmentProgress`. This is mathematically equivalent but a different FP code path, so corner-crossing can differ in the last digits. Movement assertions (existing and new) use `closeTo` tolerances, not exact equality — the current tests already do.

## Testing

| Today | After |
|---|---|
| `test/game/enemy_component_test.dart` (~1052 lines; logic tested through the component) | **`test/game/enemy_logic_test.dart`** (new, pure, no Flame): movement/waypoint-crossing over `segmentLengths`, shield-absorb, regen-vs-corrosion pause, slow movement + expiry, regen-stays-paused-during-corrosion-expiry, lethal-damage resolution, summon `summonsDue` count + bounded-loop + reach-base-skips-summon + data-slot-boss-never-summons. All assertions run against `EnemyLogic` with plain doubles. |
| | **`test/game/enemy_component_test.dart`** (slimmed): construction + `syncRender` position derivation, `targetCandidate` reflects logic state, forwarder delegates + synchronous death resolution, `residualWaypointsFromHere`, overlay cache invalidation on logic mutation. |
| `test/game/orion_defense_game_test.dart` (multiple sites call `enemy.update(...)`/`boss.update(...)` directly to drive resolution) | **All** direct enemy/boss `.update()` sites rewrite to pump `game.update(...)`, since component `update()` becomes a no-op after step 3. Verified sites: line 392 (`enemy.update(100)` → clears inspected enemy), line 475 (`enemy.update(1)` → lost + pacing reset), line 921 (`enemy.update(1)` → base damage before restart), line 958 (`boss.update(0.5+0.01)` → summon). The line-958 "call `boss.update()` directly to avoid concurrent-modification" workaround is obsolete: summon `add()`s now happen in the orchestrator's map loop, not during Flame's tree iteration. |
| `test/game/enemy_component_test.dart` (~16 `enemy.update`/`boss.update` sites: lines 31, 34, 80, 84, 105, 129, 134, 158, 291, 316, 363, 365, 380, 400, 420, 434) | These drive logic through the component. The logic-behavioral ones (movement, status, summon, death) move to `enemy_logic_test.dart` and call `logic.tick(dt)` directly with plain doubles. Any that remain in the slimmed component test call `logic.tick(dt)` + `component.syncRender()` (not `component.update()`) to advance. |
| `test/game/game_balance_test.dart` `SummonMechanic` group (line 1136) | **Unchanged** — it tests the data type, not the tick. |

New tests are written test-first, before each production step (see Migration). Two integration tests in `orion_defense_game_test.dart` guard the accepted frame-level shifts and the snapshot-iteration safety:

- **Large-`dt` lethal corrosion (same-frame status acceleration):** a projectile applies corrosion, then a single large `game.update(dt)` is pumped; assert the corrosion's first damage tick lands this frame and the lethal outcome is consistent (no off-by-one survival vs. the pure-logic expectation).
- **Multi-enemy defeat stops the tick loop:** spawn ≥2 enemies; the first reaches base and drops base health to 0 (defeat); assert the remaining snapshot entries are not ticked and their `onKilled`/`onReachedBase` do not fire, and phase is `lost`.

## Migration

Each step leaves `flutter analyze` and `flutter test` green.

1. **Add `EnemyLogic` + `enemy_logic_test.dart`.** Introduce the pure class with all state/tick/apply methods and the `_initialSummonDelay`/`maxSummonsPerFrame`/debt-shed logic. Port the behavioral assertions from the component test as pure-logic tests. No production wiring yet; the new file stands alone and its tests pass.
2. **Make `EnemyComponent` delegate — including the new resolution contract.** Add `final EnemyLogic logic` (constructed by the orchestrator from precomputed `segmentLengths`; the component receives both waypoints and the logic — see the *New pure class* section), route `applyDamage`/`applySlow`/`applyCorrosion` and a (temporary) `update()` through it, and swap the mutable fields for read-through getters. **In this same step**, introduce the `_resolutionDispatched` once-guard and the rewritten `_resolve` (guarded on `_resolutionDispatched`, not `logic.isResolved`), plus `resolveKilled()`/`resolveReachedBase()`. This *must* land here, not in step 3, because step 2 is the first point where ticking (and thus `logic` setting `isResolved` before dispatch) happens — without the new guard, step 2 would drop callbacks. The orchestrator constructs logic+component in the correct order (compute waypoints → `segmentLengths` → `EnemyLogic` → `EnemyComponent`). Existing `enemy_component_test.dart` stays green (it now exercises the component+logic delegation + the new dispatch guard). **Speed handling:** the temporary `update(dt)` receives Flame's already-time-scaled `dt` (since `OrionDefenseGame` sets `timeScale = _speedMultiplier`) and must pass that `dt` straight to `logic.tick` — do *not* multiply by `_speedMultiplier` again, or speed double-applies. Only step 3 switches to the orchestrator's explicit `scaledDt`.
3. **Relocate ticking to the orchestrator.** Introduce `_ActiveEnemy`/`_activeEnemies` + `_registerEnemy`/`_unregisterEnemy`, add `_tickEnemyLogic` (with the phase-guard + registration-check from the snapshot-iteration safety note), replace `_activeEnemyComponents` references, and add `syncRender()`. The `_resolutionDispatched` guard and `resolveKilled()`/`resolveReachedBase()` already exist from step 2. Drop the `EnemyComponent.update()` override and remove `onSummonMinions`. Rewrite **all** direct enemy/boss `.update()` test sites (orchestrator test lines 392/475/921/958 and the ~16 component-test sites) per the testing table, and slim `enemy_component_test.dart`.
4. **Cleanup pass.** Remove any dead fields, run `flutter analyze` and the full `flutter test` suite, and confirm the affected test areas (`enemy_component_test.dart`, `enemy_logic_test.dart`, `orion_defense_game_test.dart`, `game_balance_test.dart:1136` unchanged) behave as specified.

## References

- Linear: [HPA-370](https://linear.app/cwchanap/issue/HPA-370/refactor-separate-game-logic-from-enemycomponent-rendering)
- Architecture: `AGENTS.md` (logic/rendering separation; `rules/` is pure, no Flame)
- Boss-waves plan (Task 8 placed the summon timer in `EnemyComponent`): `docs/superpowers/plans/2026-07-23-orion-boss-waves-named-elites.md`
- Existing pure combat math: `lib/game/rules/combat_effects.dart`
- Component under refactor: `lib/game/components/enemy_component.dart`
- Orchestrator: `lib/game/orion_defense_game.dart` (`update` at line 368, `_handleSummonMinions` at line 674)

## Acceptance criteria

- `EnemyComponent` contains no per-enemy game logic: no status timers, no movement advance, no summon timing, no mutable combat state. It only renders, forwards combat inputs, syncs render state from `logic`, and resolves.
- `rules/enemy_logic.dart` is Flame-free (`flutter analyze` clean; no `package:flame` import; imports only `dart:math`, `game_models.dart`, `combat_effects.dart`) and fully unit-testable with plain doubles.
- `OrionDefenseGame` owns the logic instances and ticks them in `_tickEnemyLogic`; the `_ActiveEnemy` holder is the single source of truth for the logic↔component pairing.
- The 5 external call sites in `ProjectileComponent`/`DroneComponent`/`GravityFieldComponent` are unchanged (they still call `applyDamage`/`applySlow`/`applyCorrosion`).
- No remaining production path or game-level test depends on a direct `EnemyComponent.update()` call to advance logic.
- `onKilled` and `onReachedBase` each fire **exactly once** per enemy, whether death arrives via external damage, corrosion, or reach-base (single `_resolutionDispatched` guard).
- The overlay reflects slow/corrosion expiry and regen on the tick they occur, with no need for a subsequent external `apply*` call.
- Behavior is preserved within the two accepted frame-level shifts (documented above): the ported `enemy_logic_test.dart`, the rewritten component/orchestrator tests, and the rest of the suite pass; `game_balance_test.dart` `SummonMechanic` group is untouched.
