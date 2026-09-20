# HPA-441 — Combat Readability and Feedback Design

**Linear:** HPA-441 — Orion: Make combat effects readable and satisfying

## Outcome

Make Orion's existing combat rules visually legible without changing combat outcomes.

A player watching the live board should be able to distinguish:

- Rocket splash from a normal projectile hit, including which enemies were caught in the splash.
- Ion Chain from a single-target hit, including the actual resolved chain order.
- Railgun pierce from a normal projectile, including the actual resolved pierced targets.
- Slow/corrosion state from ordinary enemy presentation.
- Enemy destruction from an enemy leaking into the core.

This is presentation polish only. Damage, targeting, enemy lifecycle, rewards, wave timing, tower stats, and balance remain authoritative in their current owners.

## Existing seams to extend

The codebase already has the right ownership:

- **lib/game/components/projectile_component.dart**
  - resolves normal/splash/chain/pierce projectile hits;
  - calls CombatEffects.selectChainTargets and CombatEffects.selectPierceTargets;
  - already owns the projectile paint/color.
- **lib/game/components/enemy_component.dart**
  - wraps EnemyLogic;
  - dispatches exactly one onKilled or onReachedBase callback;
  - renders the enemy sprite and then delegates status/health presentation to EnemyOverlayRenderer.
- **lib/game/orion_defense_game.dart**
  - owns the active Flame component collection;
  - owns the central _handleEnemyKilled / _handleEnemyReachedBase callbacks;
  - owns _clearCombatComponents.
- **lib/game/components/enemy_overlay.dart** + **lib/game/rules/enemy_overlay_state.dart**
  - already own enemy overlay painting and pure overlay geometry.
- **test/game/enemy_component_test.dart**
  - already renders components/overlays into a PictureRecorder without pixel assertions.
- **test/game/game_balance_test.dart**
  - already pins tuning invariants.

Keep those seams. Do not move combat logic into rendering and do not introduce a new event/VFX architecture.

## 1. One transient CombatFeedbackComponent

Create **lib/game/components/combat_feedback_component.dart**.

It is a presentation-only Flame Component with exactly five kinds:

1. splash
2. chain
3. pierce
4. enemyDestroyed
5. coreImpact

Use five named constructors, not a registry or sealed hierarchy.

Follow the repository callback convention with:

`typedef CombatFeedbackCallback = void Function(CombatFeedbackComponent feedback);`

ProjectileComponent receives an optional CombatFeedbackCallback.

### Total geometry fields

Keep the component's internal data bag total rather than nullable.

A simple shape is sufficient:

- `Vector2 origin` — splash center, first chain point, railgun firing origin, or resolution center;
- `List<Vector2> positions = const []` conceptually — cloned resolved target positions, empty for death/core cues;
- `double radius = 0`;
- color/paint;
- kind;
- elapsed/lifetime.

Dart/Vector2 construction details can vary, but do not create nullable fields that force `!` assertions in render branches.

The component must not own:

- EnemyComponent references;
- enemy providers;
- target selectors;
- damage callbacks;
- GameSession;
- GameFeedback.

## 2. Stationary geometry + opacity decay

Each effect appears immediately at already-resolved geometry and fades out.

Do not add:

- travelling particles;
- camera shake;
- hit-stop;
- oscillation;
- a timeline/animation state machine;
- speed-specific VFX state.

CombatFeedbackComponent uses the dt Flame already supplies. Orion's game speed changes the child dt through HasTimeScale, so the same effect naturally has a shorter wall-clock lifetime at 3x.

This is also the reduced-motion-friendly path for this ticket; do not add a new setting or persistence field.

## 3. Layering is split only by whether the target is still on screen

One priority cannot make both post-removal bursts and on-body multi-target feedback readable.

Do not build a z-layer abstraction. Pin the named constructors:

- **enemyDestroyed / coreImpact: priority 15**
  - their enemy is removed before the next render, so the cue is not hidden by the body.
- **splash / chain / pierce: priority 26**
  - these cues need to be readable on live targets;
  - priority 26 stays above the existing priority-25 GravityFieldComponent without relying on equal-priority insertion order;
  - strokes/accents stay thin and brief so they do not dominate health/status information.

Current approximate stack:

- board: 0
- towers: 10
- enemy body + overlay: 20
- gravity fields: 25
- multi-target combat feedback: 26
- projectiles: 30

## 4. Projectile feedback comes from the same damage loops

ProjectileComponent remains the projectile hit authority.

Use its existing `paint.color`; do not duplicate the TowerType -> color table.

### Rocket splash

In the existing splash branch:

1. clone the impact center once;
2. clone the primary target position immediately before its existing `applyDamage` call;
3. preserve the existing secondary identity/alive/distance checks;
4. inside the existing `distanceTo(impactPosition) <= stats.splashRadius` branch, clone the secondary position immediately before its `applyDamage` call;
5. emit one splash component with:
   - impact center;
   - stats.splashRadius;
   - the resolved positions;
   - paint.color.

Do not inspect health before/after damage and do not widen EnemyComponent.applyDamage's void API just for VFX.

### Splash visuals must consume the positions

Resolved splash positions are not test-only data.

The splash renderer draws:

- the brief splash-area ring/flash;
- one restrained resolved-hit accent at each recorded position.

This is what lets the player distinguish "the explosion caught one enemy" from "the explosion caught the cluster."

Keep the accents small/low-opacity enough that bars and status badges remain the higher-signal information.

### Cluster Rocket

Do not create a second cluster-burst visual path.

The current Cluster Rocket tuning has clusterBurstRadius <= splashRadius, so the normal splash visual covers the full affected area. Pin that relation in **game_balance_test.dart** instead of adding a special "one callback only" component assertion.

Run-module stat resolution changes splashRadius but not clusterBurstRadius; do not copy that relationship into the component.

### Ion Chain

After CombatEffects.selectChainTargets returns:

1. map the selected candidates back to the same live enemies as today;
2. clone each enemy position immediately before applying that jump's damage;
3. apply the existing falloff/shield behavior;
4. emit one chain component using the recorded positions in exactly that order.

The renderer draws thin segments through those points plus compact hit accents.

### Railgun pierce

After CombatEffects.selectPierceTargets returns:

1. map selected candidates back to live enemies as today;
2. clone each position immediately before damage;
3. apply the existing armor multiplier behavior;
4. emit one pierce component from the existing projectile origin through those points.

The renderer draws a thin firing line plus compact hit accents.

### Explicit non-goals for adjacent hit branches

Do not add new hit VFX to:

- Prism split;
- drones;
- gravity-field ticks;
- nanite/corrosion onset.

Kill feedback still catches kills from those sources centrally through _handleEnemyKilled.

## 5. Kill and leak feedback use the existing central callbacks

### Enemy destruction

At the start of _handleEnemyKilled, add enemyDestroyed using the still-live enemy position/radius.

Then run the existing reward/boss/snapshot behavior unchanged.

This automatically covers kills caused by projectiles, drones, gravity fields, and corrosion without touching each damage source.

### Core impact

Add coreImpact at the start of _handleEnemyReachedBase, alongside the kill cue's simple ownership model.

Then keep the current handler unchanged.

For a **non-losing leak**, the board remains live and the coreImpact cue is visible.

For the **losing leak**, the existing loss path calls _clearCombatComponents and the Flutter layer immediately covers the board with the full-screen MissionReportPanel. Let the loss cleanup remove the transient cue. Do not preserve an invisible VFX underneath an opaque debrief.

If product direction later requires showing the final losing hit, that is a separate UI transition task (for example delaying/reworking the debrief presentation), not an ordering special case in this VFX ticket.

### Cleanup

Extend _clearCombatComponents to sweep CombatFeedbackComponent children together with projectiles/drones/fields.

Restart therefore clears leftover feedback naturally.

## 6. Slow/corrosion rings stay in EnemyOverlayRenderer/Layout

Do not paint a second status dialect directly in EnemyComponent and do not add status timers/events.

EnemyComponent already renders:

1. enemy sprite;
2. EnemyOverlayRenderer.

Keep that split.

EnemyOverlayRenderer draws status rings before its bars/badges/name, using the existing state badges:

- EnemyOverlayBadge.slowed -> thin cool ring;
- EnemyOverlayBadge.corroded -> thin green ring.

EnemyOverlayLayout owns any ring radius/offset geometry so it remains pure and unit-testable without raster assertions.

The current overlay ordering already places corroded/slowed first before the normal two-badge cap. Preserve the existing test that expects `[corroded, slowed]` when other traits are present; it already pins the invariant the ring feature relies on. Do not add a duplicate ordering test.

## 7. No new assets or feedback catalog

Use Canvas primitives and current colors only.

Do not:

- generate image assets;
- add sprite sheets;
- add packages;
- add per-hit SFX/haptics;
- extend GameFeedback;
- reuse GravityFieldComponent as a VFX container (it applies real damage).

## 8. Testing strategy

Automated tests cover ownership, geometry, render execution, lifecycle, and unchanged combat outcomes. No pixel/golden coupling.

### CombatFeedbackComponent tests

Create **test/game/combat_feedback_component_test.dart**.

Test:

- inputs are cloned;
- fields are total and named constructors expose the expected kind/geometry;
- priorities are:
  - 15 for death/core;
  - 26 for splash/chain/pierce;
- expiry removes the component when mounted in a minimal FlameGame;
- no gameplay callback exists.

Also execute render for all five kinds using a PictureRecorder:

- once at full opacity;
- once near expiry;
- assert only `returnsNormally`.

This follows the existing EnemyOverlayRenderer/EnemyComponent recorder-test pattern and keeps the patch above the repository's 90% coverage gate without introducing image comparisons.

### ProjectileComponent tests

Create **test/game/projectile_component_test.dart**.

No FlameGame host is required for the projectile-resolution tests.

Construct EnemyComponents directly, as existing EnemyComponent tests do. Because ProjectileComponent.update currently rejects an unmounted target, explicitly mark the standalone target/candidates mounted in the test setup (using the same test-only internal-member convention already used elsewhere) before calling `projectile.update(dt)`.

Then capture the optional CombatFeedbackCallback and assert:

- splash damage and emitted center/radius/positions agree;
- splash positions are actually rendered as hit accents by the CombatFeedbackComponent render coverage above;
- chain damage order agrees with emitted ordered points;
- pierce damage agrees with firing origin + emitted ordered points;
- existing health/damage outcomes remain unchanged.

No GameWidget, FlameGame host, or processLifecycleEvents are required for these direct projectile tests.

Do not independently call CombatEffects selectors in the expected-value logic.

### Game lifecycle tests

Keep game-level tests in **test/game/orion_defense_game_test.dart**.

Test:

- kill emits enemyDestroyed and preserves rewards;
- a **non-losing** leak emits coreImpact and preserves base damage;
- kill and leak kinds are distinct;
- restart/_clearCombatComponents remove outstanding feedback;
- existing loss behavior stays unchanged.

Do **not** add a defeat-survival VFX assertion: MissionReportPanel intentionally covers the board immediately on loss.

Where existing game tests exercise queued child lifecycle, keep using their established `setMounted()` + `processLifecycleEvents()` pattern.

### Status/layout tests

Extend the existing EnemyOverlay tests in **test/game/enemy_component_test.dart**:

- slowed/corroded states produce the expected ring geometry in EnemyOverlayLayout;
- both can coexist;
- resolved/no-status state has no ring geometry;
- existing `[corroded, slowed]` badge assertion continues to pin ordering under the two-badge cap;
- explicitly render the new ring path through _renderOverlayToCanvas and assert `returnsNormally`.

No goldens.

### Balance invariant test

Extend **test/game/game_balance_test.dart** with one tuning invariant:

- Cluster Rocket `clusterBurstRadius <= splashRadius`.

That guards the actual assumption that lets cluster bursts reuse the one splash visual.

## Manual validation

On a phone-sized surface:

1. ordinary early wave at 1x;
2. dense multi-target wave at 1x and 3x;
3. boss/final wave with overlays visible;
4. a non-losing leak.

Confirm:

- splash area and per-hit accents communicate multi-hit coverage;
- chain order reads clearly;
- railgun reads as a pierce line;
- slow/corrosion rings remain secondary to health/status information;
- enemyDestroyed and a live-board coreImpact are visually distinct;
- 3x does not become persistent clutter.

The final losing leak is not a manual VFX gate because the debrief intentionally replaces the board immediately.

## Non-goals

- Damage numbers.
- Generic combat-event/VFX architecture.
- Pooling/replay/telemetry.
- New target selection or damage rules.
- GameFeedback expansion.
- New image/audio/haptic assets.
- New accessibility persistence.
- Screen shake/hit-stop.
- Status transition history/timers.
- Final-loss debrief timing changes.
- Prism/drone/gravity/nanite hit-VFX expansion.
