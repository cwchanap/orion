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
- Changing enemy balance. This refactor preserves enemy *behavior* (same status math, same summon timing, same death/reach-base outcomes, bit-identical movement FP) with two accepted, imperceptible frame-level shifts documented below under [Intra-frame ordering and movement model](#intra-frame-ordering-and-movement-model). It is **not** bit-identical per-frame *ordering* of enemies vs. gravity/projectiles/drones. The existing rule/behavior tests (plus the ported `enemy_logic_test.dart`) are the regression net.

## Architecture

### New pure class: `rules/enemy_logic.dart`

`EnemyLogic` is a Flame-free class that owns all per-enemy mutable game state, the tick/apply math, **and the path/position math**. It imports `dart:math`, `dart:ui` (for `Offset` — the same precedent `rules/board_layout.dart:1` already sets; `Offset` is Flutter's dart:ui, not Flame, and carries no `vector_math` dependency), `../models/game_models.dart` (for `EnemyStats`, `BossDefinition`, `SummonMechanic`), and `combat_effects.dart` (for `resolveDamage`/`mergeSlow`/`applyRegen` — a sibling pure module; `CombatEffects` itself is unchanged). It never imports `package:flame`.

**Design choice — `Offset` waypoints, not `segmentLengths`.** The logic takes `List<Offset> waypoints` and owns `Offset position` outright, rather than taking precomputed segment lengths and exposing parametric progress for the component to lerp. Trade-off recorded: plain doubles are marginally more "abstract-pure," but `Offset` is two doubles with arithmetic (`+`, `-`, `.distance`) and lets the movement code stay the *same FP code path* as today's `_moveAlongPath` (live position, `distanceToTarget`, incremental advance) — so there is no parametric-vs-delta numerical drift, and `syncRender` collapses to copying `logic.position` into the component's `Vector2`. `dart:ui` is already in `rules/`.

**Immutable inputs (constructor):**

```dart
class EnemyLogic {
  EnemyLogic({
    required int enemyId,
    required EnemyStats stats,
    required List<Offset> waypoints,
    double initialCompletedDistance = 0,
  }) : position = waypoints.first, ...;
}
```

The orchestrator converts its `List<Vector2>` path to `List<Offset>` (`Offset(v.dx, v.dy)` — note Flame `Vector2` stores `.x`/`.y`; the existing `_pathWaypoints()` returns `Vector2` so the conversion is `Offset(p.x, p.y)`) and passes it to the logic. For minions, the boss's `residualWaypointsFromHere()` (now a logic method returning `List<Offset>`) seeds the minion's logic directly — no `Vector2` round-trip.

The `_initialSummonDelay` static helper (currently on `EnemyComponent`) moves here, unchanged.

**Mutable state (owned, all moved off the component):**

Combat: `health`, `shield`, `maxHealth` (final, from `stats.health`), `armorShred`, `slowMultiplier`, `slowRemaining`, `corrosionDamagePerSecond`, `corrosionRemaining`, `summonRemaining`.

Path/position: `Offset position` (reassigned during movement, initialized to `waypoints.first`), `targetWaypointIndex` (starts at 1), `completedDistance`, `segmentProgress`.

Resolution: `isResolved` (bool) — the **terminal-state marker**. Set by `applyDamage` when health reaches 0 and by `tick` on corrosion-death or path overrun. It drives `isAlive`. It is *not* the dispatch guard for the component's side effects (see Resolution contract below).

**Derived getters:** `isAlive` (`!isResolved && health > 0`), `isSlowed`, `isCorroded`, `armorReduction` (the clamped `stats.armorReduction - armorShred`), `pathProgress` (`completedDistance + currentSegmentLength * segmentProgress`), `residualWaypointsFromHere()` (returns `[position, ...waypoints.sublist(targetWaypointIndex)]`).

**Tick API:**

```dart
class EnemyTickResult {
  final bool reachedBase;
  final bool diedByCorrosion;
  final int summonsDue;
  final bool overlayDirty;   // true when tick mutated overlay-relevant state
}
EnemyTickResult tick(double dt);
```

`tick` runs the exact ordered sequence currently in `EnemyComponent.update`, terminating at most one resolution. It reports `overlayDirty: true` at the same mutation points today's `_tickCorrosionAndRegen`/`_tickSlow` set `_overlayDirty` (health changed by corrosion or regen; corrosion expiry clearing shred; slow expiry resetting the multiplier) — so the component's overlay cache stays valid without re-allocating `EnemyOverlayState.fromData`'s badge list every frame.

1. Corrosion/regen (`_tickCorrosionAndRegen`): decrement `_corrosionRemaining`, apply `_corrosionDamagePerSecond * tick` as bypass-armor damage via `CombatEffects.resolveDamage`, clear shred when corrosion expires, then `CombatEffects.applyRegen` gated on `wasCorrodedAtTickStart`. If health hits 0, set `isResolved` and return `diedByCorrosion: true`.
2. Movement (the `_moveAlongPath` loop, ported `Vector2`→`Offset`): advance `position`/`targetWaypointIndex`/`completedDistance`/`segmentProgress` using `stats.speed * movementSlowMultiplier * dt`. The loop body is byte-for-byte today's FP (`toTarget = target - position`, `distanceToTarget = toTarget.distance`, `position = target` on waypoint arrival before incrementing the index), so on path overrun `position` is already at `waypoints.last`. If the index runs off the end, set `isResolved` and return `reachedBase: true`.
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

`OrionDefenseGame` constructs one `EnemyLogic` per enemy inside `_spawnEnemy`/`_spawnMinion` and owns the ticking. **Keep `Map<int, EnemyComponent> _activeEnemyComponents` as-is** — do *not* introduce a wrapper struct. Because `EnemyComponent` holds `final EnemyLogic logic` (the back-reference, set at construction), the component and its logic are constructed together and cannot drift apart; a separate `_ActiveEnemy` pair would bundle two things already bundled and, worse, would force retyping the `enemiesProvider` closures (`Iterable<EnemyComponent> Function()` at `orion_defense_game.dart:466`/`:483`, consumed by `ProjectileComponent`/`GravityFieldComponent`) — breaking the "no call-site changes outside the two in-scope files" non-goal.

Construction order resolves the cycle and stays entirely in the orchestrator:

1. Compute `List<Vector2> waypoints` (`_pathWaypoints()`, or `boss.logic.residualWaypointsFromHere()` converted for a minion).
2. Convert to `List<Offset>` and construct `EnemyLogic`.
3. Construct `EnemyComponent({ logic: logic, ... })` (no `waypoints` param — the component no longer holds waypoints; it seeds its `position` from `logic.position`).
4. `_activeEnemyComponents[enemy.enemyId] = enemy` (unchanged).

`_tickEnemyLogic` reaches the logic via `component.logic`. All 16 existing `_activeEnemyComponents` use sites (`:444`, `:456`, `:466`, `:483`, `:534`, `:550`, `:570`, `:575`, `:663`, `:671`, `:680`, `:696`, `:728`, `:734`, `:739`, `:758`) are **unchanged** — readers, mutators, `enemiesProvider`, `_removeInactiveEnemyReferences` sweep, and `_clearCombatComponents` all keep operating on `EnemyComponent` values. No `_registerEnemy`/`_unregisterEnemy` indirection.

`stats` and `enemyId` are **not** duplicated state: the component retains them as the public identity API, and the logic holds the same immutable references (passed through at construction) so pure tests can construct a logic standalone. One source of truth, two handles.

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

`_tickEnemyLogic` iterates a snapshot of `_activeEnemyComponents.values`, reaches each logic via `component.logic`, dispatches `tick()` events to the existing handlers, syncs render, and forwards the dirty flag. The loop guards against combat ending mid-iteration: a reach-base that triggers defeat clears the whole registry via `_clearCombatComponents` (loss path), so the loop must stop when the phase leaves `wave` and skip any enemy unregistered during this loop:

```dart
void _tickEnemyLogic(double dt) {
  for (final enemy in _activeEnemyComponents.values.toList()) {
    if (_session.phase != GamePhase.wave) break;          // defeat/win ended combat
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
      final mechanic = (logic.stats is BossDefinition)
          ? (logic.stats as BossDefinition).summonMechanic
          : null;
      if (mechanic != null) {
        for (var i = 0; i < result.summonsDue; i++) {
          _handleSummonMinions(enemy, mechanic.count);
        }
      }
    }
  }
}
```

Without these guards, a defeat triggered by the first enemy to reach base would leave the snapshot iterating over now-cleared enemies and dispatch `onKilled`/`onReachedBase` for enemies that were merely despawned by the loss sweep (harmless to the session — `rewardKill`/`damageBase` guard on `phase == wave` — but semantically wrong and produces stray snapshot publishes). A multi-enemy defeat test (first enemy reaches base and drops base health to 0; assert the remaining snapshot entries are *not* ticked or dispatched) is required.

`markOverlayDirty()` is a thin setter (`_overlayDirty = true`) so `tick` can flag the cache without the logic reaching into the component; `syncRender()` copies position but leaves the cache alone, so a tick that only moves (no status/health change) does not re-allocate the overlay.

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

The forwarder stays `void` to keep the external call sites unchanged (19 `applyDamage`/`applySlow`/`applyCorrosion` invocations across the three consumer files); only `EnemyLogic.applyDamage` returns `DamageOutcome` (it needs to tell the forwarder whether to resolve). `applySlow`/`applyCorrosion` cannot kill, so they need no outcome.

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

**Stays (render/identity):** `enemyId`, `stats`, sprite-sheet refs (`spriteSheet`, `towerVarietySheet`, `bossSheet`), `minionOf`, `onKilled`, `onReachedBase`, `final EnemyLogic logic`, `render()`, overlay cache (`_cachedOverlayState`, `_overlayDirty`), `setInspected`, `targetCandidate`, `syncRender()`, `markOverlayDirty()`, `resolveKilled()`/`resolveReachedBase()`/`_resolve()`. The component seeds its `Vector2 position` from `logic.position` at construction and re-syncs via `syncRender()` each tick; it no longer holds waypoints.

**Becomes read-through getters to `logic`** (every external reader — targeting, orchestrator, tests — unchanged): `health`, `shield`, `maxHealth`, `isAlive`, `isResolved`, `isSlowed`, `isCorroded`, `armorReduction`, `pathProgress`.

**Leaves the component (moves to `EnemyLogic`):** `_moveAlongPath`, `_tickCorrosionAndRegen`, `_tickSlow`, `_currentSegmentLength`, `_initialSummonDelay`, `residualWaypointsFromHere()`, the `waypoints` field, `onSummonMinions`, and all mutable combat/path fields (`_slowMultiplier`, `_slowRemaining`, `_corrosionDamagePerSecond`, `_corrosionRemaining`, `_armorShred`, `_summonRemaining`, `_targetWaypointIndex`, `_completedDistance`, `_segmentProgress`, plus the public-mutable `health`/`shield` which become read-only getters). `pathProgress` becomes a read-through getter to `logic.pathProgress`.

**`update()` override is removed** (or reduced to a no-op `super.update(dt)`). All advance happens in `_tickEnemyLogic`; `syncRender()` (called from there) just copies the logic's authoritative position into the component's `Vector2`, and `markOverlayDirty()` is called only when `tick` reports `overlayDirty`:

```dart
void syncRender() {
  position.setValues(logic.position.dx, logic.position.dy);
}
void markOverlayDirty() => _overlayDirty = true;
```

Because the logic owns the full movement loop (including `position = waypoints.last` on path overrun), `syncRender` has no conditional — reach-base position is correct on the resolve frame (matching today's `position.setFrom(target)` before `_resolve` at `enemy_component.dart:319`). The overlay cache stays valid: `tick` reports `overlayDirty` only at the mutation points today's code dirtied (health/corrosion/slow changes), so `EnemyOverlayState.fromData`'s badge-list allocation happens only when something actually changed, not once per enemy per frame. The `apply*` forwarders also call `markOverlayDirty()` so external damage between ticks refreshes immediately.

`targetCandidate` derives from the synced `position` plus logic fields (`logic.pathProgress`, `logic.health`, `logic.shield`), preserving targeting behavior; minion-seeding reads `boss.logic.residualWaypointsFromHere()`.

### Intra-frame ordering and movement model

Two accepted, intentional departures from the current per-frame execution, both imperceptible at 60fps and standard for tower-defense loops:

1. **Enemy tick batching (one-frame hit/position shift, gravity/projectile/drone only).** Today Flame updates components in priority order — Tower(10) → Enemy(20) → GravityField(25) → Projectile(30) → Drone(35). Enemy status/movement runs at priority 20, so gravity fields, projectiles, and drones (25/30/35) act on *post-move* positions. After extraction, all enemy status/movement advances in a single `_tickEnemyLogic` batch *after* `super.update`, so this frame's gravity/projectile/drone hits land against the *previous* tick's positions (one-frame shift). Note "towers fire before enemies move" is *already* true today (Tower 10 < Enemy 20) and is not a change; the shift is confined to priorities 25/30/35. There is no way to keep the per-priority interleaving while centralizing enemy ticks; the shift is inherent to the boundary move. Speed/path/summon/rate behavior is unaffected because per-frame advancement is unchanged. Tests assert outcomes via pump-and-check (not bit-exact frame ordering).
2. **Same-frame status acceleration (the consequential one — integration-tested).** Because `_tickEnemyLogic` runs *after* `super.update`, a slow/corrosion applied by a projectile or gravity field during `super.update` is acted on by the enemy's own tick *this same frame* (movement slows, corrosion deals damage and consumes duration immediately). Today those inputs don't affect the enemy's tick until *next* frame (enemy priority 20 < projectile/gravity 30/25). We accept this rather than buffer inputs: buffering would defer `isSlowed`/`isCorroded` observability and break the same-frame combat interaction `ProjectileComponent._resolveHit` relies on (`damageAgainstSlowState` reads `target.isSlowed` synchronously so a second projectile hitting an already-slowed enemy the same frame gets the bonus). Forwarders keep mutating immediately, so combat-input observability is unchanged; only the enemy *self-tick* lands one frame earlier. Net effect over time is identical (corrosion's total damage is bounded by `damagePerSecond * duration`); only the frame boundary shifts. **Integration test required:** apply corrosion via a projectile under a large `dt` and assert lethal timing is consistent (the large-`dt` lethal-corrosion case is the observable edge).

Movement itself is **not** a behavioral shift: because the logic owns the same `Offset`-based `_moveAlongPath` FP code path as today (live position, `distanceToTarget`, incremental advance), per-frame movement is bit-identical — no parametric-vs-delta drift, no tolerance caveat. (Existing movement tests already use `closeTo`, which still passes.)

## Testing

| Today | After |
|---|---|
| `test/game/enemy_component_test.dart` (~1052 lines; logic tested through the component) | **`test/game/enemy_logic_test.dart`** (new, pure, no Flame): movement/waypoint-crossing (asserting bit-identical FP to today's `_moveAlongPath`), shield-absorb, regen-vs-corrosion pause, slow movement + expiry, regen-stays-paused-during-corrosion-expiry, lethal-damage resolution, summon `summonsDue` count + bounded-loop + reach-base-skips-summon + data-slot-boss-never-summons, and `overlayDirty` set exactly on health/corrosion/slow mutations. Assertions run against `EnemyLogic` with `Offset` waypoints. |
| | **`test/game/enemy_component_test.dart`** (slimmed): construction + `syncRender` position derivation, `targetCandidate` reflects logic state, forwarder delegates + synchronous death resolution, `residualWaypointsFromHere`, overlay cache invalidation on logic mutation. |
| `test/game/orion_defense_game_test.dart` (multiple sites call `enemy.update(...)`/`boss.update(...)` directly to drive resolution) | **All** direct enemy/boss `.update()` sites rewrite to pump `game.update(...)`, since component `update()` becomes a no-op after step 3. Verified sites: line 392 (`enemy.update(100)` → clears inspected enemy), line 475 (`enemy.update(1)` → lost + pacing reset), line 921 (`enemy.update(1)` → base damage before restart), line 958 (`boss.update(0.5+0.01)` → summon). The line-958 "call `boss.update()` directly to avoid concurrent-modification" workaround is obsolete: summon `add()`s now happen in the orchestrator's map loop, not during Flame's tree iteration. |
| `test/game/enemy_component_test.dart` (~16 `enemy.update`/`boss.update` sites: lines 31, 34, 80, 84, 105, 129, 134, 158, 291, 316, 363, 365, 380, 400, 420, 434) | These drive logic through the component. The logic-behavioral ones (movement, status, summon, death) move to `enemy_logic_test.dart` and call `logic.tick(dt)` directly with plain doubles. Any that remain in the slimmed component test call `logic.tick(dt)` + `component.syncRender()` (not `component.update()`) to advance. |
| `test/game/game_balance_test.dart` `SummonMechanic` group (line 1136) | **Unchanged** — it tests the data type, not the tick. |

New tests are written test-first, before each production step (see Migration). Two integration tests in `orion_defense_game_test.dart` guard the accepted frame-level shifts and the snapshot-iteration safety:

- **Large-`dt` lethal corrosion (same-frame status acceleration):** a projectile applies corrosion, then a single large `game.update(dt)` is pumped; assert the corrosion's first damage tick lands this frame and the lethal outcome is consistent (no off-by-one survival vs. the pure-logic expectation).
- **Multi-enemy defeat stops the tick loop:** spawn ≥2 enemies; the first reaches base and drops base health to 0 (defeat); assert the remaining snapshot entries are not ticked and their `onKilled`/`onReachedBase` do not fire, and phase is `lost`.
- **Exactly-once callbacks across paths:** an enemy that is lethally damaged by a projectile during `super.update` on the same frame its `tick` would overrun the path — assert `onKilled` fires exactly once (the `_resolutionDispatched` guard holds across the external-damage and tick paths).
- **Overlay reflects tick expiry:** apply slow + corrosion, pump until each expires via `tick` (no external `apply*`), and assert `overlayDirty` is true on the expiry tick and the rendered overlay drops the slow/corrosion signal — guarding the `EnemyTickResult.overlayDirty` → `markOverlayDirty` wiring.

## Migration

Each step leaves `flutter analyze` and `flutter test` green.

1. **Add `EnemyLogic` + `enemy_logic_test.dart`.** Introduce the pure class with all state/tick/apply methods and the `_initialSummonDelay`/`maxSummonsPerFrame`/debt-shed logic. Port the behavioral assertions from the component test as pure-logic tests. No production wiring yet; the new file stands alone and its tests pass.
2. **Make `EnemyComponent` delegate — including the new resolution contract.** Add `final EnemyLogic logic` (constructed by the orchestrator from `List<Offset>` waypoints; the component receives the logic but **not** waypoints — the logic owns them — see the *New pure class* section), route `applyDamage`/`applySlow`/`applyCorrosion` and a (temporary) `update()` through it, and swap the mutable fields for read-through getters. **In this same step**, introduce the `_resolutionDispatched` once-guard and the rewritten `_resolve` (guarded on `_resolutionDispatched`, not `logic.isResolved`), plus `resolveKilled()`/`resolveReachedBase()`. This *must* land here, not in step 3, because step 2 is the first point where ticking (and thus `logic` setting `isResolved` before dispatch) happens — without the new guard, step 2 would drop callbacks. Existing `enemy_component_test.dart` stays green (no test assigns `enemy.health`/`enemy.shield`, so the read-only-getter swap is safe; it now exercises the component+logic delegation + the new dispatch guard). **Speed handling:** the temporary `update(dt)` receives Flame's already-time-scaled `dt` (since `OrionDefenseGame` sets `timeScale = _speedMultiplier`) and must pass that `dt` straight to `logic.tick` — do *not* multiply by `_speedMultiplier` again, or speed double-applies (the existing `orion_defense_game_test.dart:399` '3x speed accelerates real enemy progress' test catches this). Only step 3 switches to the orchestrator's explicit `scaledDt`.
3. **Relocate ticking to the orchestrator.** Keep `Map<int, EnemyComponent> _activeEnemyComponents` as-is (no wrapper, no register/unregister — the component holds its logic). Add `_tickEnemyLogic` reading `component.logic` (with the phase-guard + registration-check from the snapshot-iteration safety note, and forwarding `result.overlayDirty` to `markOverlayDirty`), and add `syncRender()`/`markOverlayDirty()`. The `_resolutionDispatched` guard and `resolveKilled()`/`resolveReachedBase()` already exist from step 2. Drop the `EnemyComponent.update()` override, the `waypoints` field, `residualWaypointsFromHere`/`_currentSegmentLength` (moved to logic), and `onSummonMinions`. Rewrite **all** direct enemy/boss `.update()` test sites (orchestrator test lines 392/475/921/958 and the ~16 component-test sites) per the testing table, and slim `enemy_component_test.dart`.
4. **Cleanup pass.** Remove any dead fields, run `flutter analyze` and the full `flutter test` suite, and confirm the affected test areas (`enemy_component_test.dart`, `enemy_logic_test.dart`, `orion_defense_game_test.dart`, `game_balance_test.dart:1136` unchanged) behave as specified.

## References

- Linear: [HPA-370](https://linear.app/cwchanap/issue/HPA-370/refactor-separate-game-logic-from-enemycomponent-rendering)
- Architecture: `AGENTS.md` (logic/rendering separation; `rules/` is pure, no Flame)
- Boss-waves plan (Task 8 placed the summon timer in `EnemyComponent`): `docs/superpowers/plans/2026-07-23-orion-boss-waves-named-elites.md`
- Existing pure combat math: `lib/game/rules/combat_effects.dart`
- Component under refactor: `lib/game/components/enemy_component.dart`
- Orchestrator: `lib/game/orion_defense_game.dart` (`update` at line 368, `_handleSummonMinions` at line 674)

## Acceptance criteria

- `EnemyComponent` contains no per-enemy game logic: no status timers, no movement advance, no summon timing, no mutable combat state, no waypoints. It only renders, forwards combat inputs, syncs render state from `logic`, and resolves.
- `rules/enemy_logic.dart` is Flame-free (`flutter analyze` clean; no `package:flame` import; imports only `dart:math`, `dart:ui`, `game_models.dart`, `combat_effects.dart` — same `dart:ui` precedent as `rules/board_layout.dart`) and fully unit-testable with `Offset` waypoints.
- `OrionDefenseGame` owns logic construction and ticking in `_tickEnemyLogic` (reaching logic via `component.logic`); `Map<int, EnemyComponent> _activeEnemyComponents` is unchanged (no wrapper struct).
- The three consumer files `ProjectileComponent`, `DroneComponent`, `GravityFieldComponent` are unmodified (the 19 `applyDamage`/`applySlow`/`applyCorrosion` invocations across them keep working through the unchanged forwarders), and all 16 `_activeEnemyComponents` use sites in the orchestrator are unchanged.
- No remaining production path or game-level test depends on a direct `EnemyComponent.update()` call to advance logic.
- `onKilled` and `onReachedBase` each fire **exactly once** per enemy, whether death arrives via external damage, corrosion, or reach-base (single `_resolutionDispatched` guard; covered by the cross-path integration test).
- The overlay reflects slow/corrosion expiry and regen on the tick they occur, with no need for a subsequent external `apply*` call (covered by the `overlayDirty` integration test).
- Behavior is preserved within the two accepted frame-level shifts (documented above); movement is bit-identical FP. The ported `enemy_logic_test.dart`, the rewritten component/orchestrator tests, and the rest of the suite pass; `game_balance_test.dart` `SummonMechanic` group is untouched.
