# HPA-441 — Combat Readability and Feedback Design

**Linear:** HPA-441 — Orion: Make combat effects readable and satisfying

## Outcome

Make the existing combat rules visibly legible without changing combat outcomes.

A player watching the board should be able to distinguish:

- Rocket splash from a normal projectile hit.
- Ion Chain from a single-target hit, including the order of actual chained targets.
- Railgun pierce from a normal projectile, including the enemies actually pierced.
- Slow/corrosion state from ordinary enemy presentation.
- Enemy destruction from an enemy leaking into the core.

This is presentation polish only. Damage, targeting, wave timing, enemy lifecycle, tower stats, rewards, and balance remain authoritative in their current owners.

## Current implementation seams

The current code already has the right gameplay ownership:

- **lib/game/components/projectile_component.dart** resolves projectile impact.
  - Ion Chain calls CombatEffects.selectChainTargets and applies damage to those selected enemies.
  - Railgun calls CombatEffects.selectPierceTargets and applies damage to those selected enemies.
  - Rocket splash resolves its impact point, tests the current enemy set against splashRadius, and applies damage in that same loop.
  - Cluster Rocket's current clusterBurstRadius (42) is inside its splashRadius (72), so its extra bursts can reuse the normal splash visual instead of creating another VFX path.
- **lib/game/components/enemy_component.dart** owns the render shell around EnemyLogic and dispatches exactly one kill or reached-base callback.
- **lib/game/orion_defense_game.dart** owns the active component collection and the two distinct resolution callbacks:
  - _handleEnemyKilled
  - _handleEnemyReachedBase
- **lib/game/components/enemy_overlay.dart** and **lib/game/rules/enemy_overlay_state.dart** already own enemy status/overlay presentation and layout.
- Enemy slow/corrosion already exist as authoritative EnemyLogic state and already appear in EnemyOverlayState.

The implementation attaches feedback to these existing resolution points. It does not move combat selection into a new subsystem and does not ask presentation code to select targets again.

## Design decisions

### 1. One focused transient drawing component

Add **lib/game/components/combat_feedback_component.dart**.

CombatFeedbackComponent is a short-lived Flame component that only draws primitive geometry and removes itself after a small fixed lifetime.

It supports five presentation kinds:

1. splash
2. chain
3. pierce
4. enemyDestroyed
5. coreImpact

Use named constructors rather than a generic effect registry. Each constructor accepts only already-resolved world-space geometry needed to draw the cue.

Representative inputs:

- splash: impact center, splash radius, resolved hit positions, projectile color
- chain: resolved target positions in chain order, projectile color
- pierce: firing origin, resolved hit positions in pierce order, projectile color
- enemyDestroyed: enemy center and approximate enemy radius
- coreImpact: enemy/core impact center and approximate enemy radius

The component must not accept EnemyComponent collections, targeting callbacks, damage callbacks, GameSession, or GameFeedback. It cannot affect gameplay.

Do not extend GameFeedback for per-hit VFX. That interface remains the existing audio/haptic feedback boundary.

### 2. Stationary geometry plus opacity decay

Feedback appears immediately at the resolved geometry and fades out.

Do not add camera shake, hit-stop, travelling secondary particles, oscillation, or an animation state machine.

CombatFeedbackComponent uses the dt it already receives from Flame. There is no speed-specific VFX state: at 3x the transient naturally consumes its lifetime faster in wall-clock time with the rest of the game.

This is also the reduced-motion-friendly shape for this ticket. Do not add a new accessibility setting or persistence path.

### 3. ProjectileComponent emits feedback from the same resolution pass

ProjectileComponent remains the authority for projectile-side hit resolution.

Add one narrow optional callback:

- onCombatFeedback(CombatFeedbackComponent feedback)

OrionDefenseGame wires that callback to add(feedback). Feedback is parented on the game, never on the projectile or enemy that is about to remove itself.

Use ProjectileComponent's existing paint.color as the feedback color. Do not add a second TowerType-to-color table.

Each resolver builds feedback from the enemies it is already resolving.

#### Rocket splash

At impact:

1. Clone the impact position once.
2. Because _resolveHit already requires a live target, clone the primary target position immediately before the existing primary applyDamage call.
3. Keep the current secondary loop and its existing alive/distance checks.
4. Inside the existing distanceTo(impactPosition) <= stats.splashRadius branch, clone the secondary enemy position immediately before applyDamage.
5. Do not inspect health before/after damage and do not widen EnemyComponent.applyDamage just to prove a VFX hit.
6. Emit exactly one splash feedback component using the same impact center, stats.splashRadius, recorded resolved positions, and paint.color.
7. Cluster bursts reuse this same splash component. Do not emit one component per burst.

The feedback component never rechecks enemy distances. The splash ring is the primary readable cue; resolved positions are retained so ownership/tests stay tied to the actual damage loop rather than a second selector.

#### Ion Chain

After CombatEffects.selectChainTargets returns:

1. Map the selected candidates back to live EnemyComponents exactly as today.
2. For each enemy that passes the current live check, clone its position immediately before applying that jump's damage.
3. Apply the existing falloff/shield behavior.
4. Emit one chain feedback component using only the recorded ordered positions.

The drawn segments therefore mirror the same ordered chain used for damage.

#### Railgun pierce

After CombatEffects.selectPierceTargets returns:

1. Map selected candidates back to enemies exactly as today.
2. For each live resolved enemy, clone its position immediately before applying damage.
3. Apply the existing armor multiplier behavior.
4. Emit one pierce feedback component from the projectile origin through the recorded ordered positions.

The feedback component does not call selectPierceTargets.

Prism split, drones, gravity-field ticks, and nanite hit flashes are out of scope. Do not widen this ticket by adding feedback to adjacent combat branches.

### 4. Kill and leak cues use the existing game callbacks, with defeat ordering pinned

Enemy destruction and core impact must survive their respective resolution paths without delaying gameplay.

#### Enemy destruction

At the start of _handleEnemyKilled, while enemy.position and enemy.radius are still available, add enemyDestroyed feedback.

Then continue the existing reward/removal/snapshot path unchanged.

#### Core impact

_handleEnemyReachedBase already clears combat components when the leak changes the phase from wave to lost. Therefore the core-impact cue must not be added before that clear.

Instead:

1. Clone enemy.position and enemy.radius at the start of _handleEnemyReachedBase.
2. Run the existing handler logic unchanged, including inspection cleanup, active-enemy removal, base damage, loss detection, defeat feedback, combat cleanup, spawn reset, pacing reset, layout, and snapshot publication.
3. Add CombatFeedbackComponent.coreImpact from the cloned geometry after the possible defeat cleanup.

This makes both non-losing and losing leaks visible. On defeat, the existing cleanup removes earlier transient combat feedback, then the current leak cue is added. A later restart still removes that leftover cue through the normal combat cleanup path.

The two visual shapes must be clearly different even without color:

- enemyDestroyed: compact radial burst / short rays
- coreImpact: heavier ring + cross/diamond impact mark

Boss defeat uses the same normal destruction cue scaled from the enemy radius; existing boss audio/haptics remain unchanged.

### 5. Slow and corrosion stay inside the existing enemy overlay renderer/layout

Do not create onset/expiry events, second timers, or a second status presentation object.

EnemyComponent already renders the sprite and then calls EnemyOverlayRenderer. Keep that ownership:

1. EnemyComponent renders the enemy sprite.
2. EnemyOverlayRenderer draws a thin status ring treatment derived from the existing EnemyOverlayState badges.
3. EnemyOverlayRenderer then draws its existing health/shield bars, badges, and boss name over the ring treatment.

Use the existing EnemyOverlayBadge.slowed and EnemyOverlayBadge.corroded values; do not duplicate booleans in another model.

Add the small ring geometry to EnemyOverlayLayout so it remains unit-testable without raster/golden tests. For example, expose nullable slowed/corroded ring radii/geometry from EnemyOverlayLayout.compute.

Suggested treatment:

- slowed: thin cool outer ring
- corroded: thin green inner/offset ring

The rings disappear automatically when the authoritative status badge disappears.

## Layering and visual priority

One priority cannot both sit under enemy overlays and make chain/pierce body hits readable, so the five named constructors pin their own simple priorities. This is not a new z-layer system.

Current useful ordering is approximately:

- board: priority 0
- towers: priority 10
- enemies + their overlay: priority 20
- gravity fields: priority 25
- projectiles: priority 30

Use:

- splash: priority 15 — area ring/flash reads around enemy sprites; do not rely on on-body splash accents for readability
- enemyDestroyed: priority 15 — the enemy is removed before the next render
- coreImpact: priority 15 — the leaking enemy is removed before the next render
- chain: priority 25 — thin segments/compact center accents remain readable on live targets
- pierce: priority 25 — thin firing line/compact center accents remain readable on live targets

Chain/pierce strokes must stay thin and centered on the body so they do not compete with the health/status overlay above the enemy.

Do not reuse GravityFieldComponent. It has a similar lifetime/removal pattern but owns real damage behavior.

## No new assets

Use Canvas primitives and current projectile colors only.

Do not add:

- generated images
- sprite sheets
- new SFX
- new haptics
- package dependencies

## Testing strategy

Automated tests protect ownership, geometry, lifecycle, and unchanged combat numbers, not rendered pixels.

### CombatFeedbackComponent

Add **test/game/combat_feedback_component_test.dart** and verify:

- constructor inputs are cloned;
- kind/geometry are retained for inspection;
- named constructors choose the pinned priority for their kind;
- the component expires/removes itself after its lifetime;
- it exposes no gameplay callback or mutation path.

### Projectile resolution

Add a dedicated **test/game/projectile_component_test.dart**.

Test ProjectileComponent directly through its optional feedback callback. Do not route these geometry tests through OrionDefenseGame.

Cover representative splash, chain, and pierce resolution:

- existing health/damage outcomes remain unchanged;
- feedback geometry comes from the same enemies/positions used by the existing damage loop;
- splash uses the existing impact center/radius and records positions before applyDamage;
- chain ordering in feedback matches resolved damage order;
- pierce geometry includes the existing firing origin and resolved hit order;
- cluster burst emits one normal splash feedback component.

Do not independently reproduce target selection in the assertion and do not add a test-only production API.

### Kill vs leak

Keep game-level coverage in **test/game/orion_defense_game_test.dart**:

- killing an enemy creates enemyDestroyed feedback and preserves reward behavior;
- a non-losing leak creates coreImpact and preserves base damage;
- the existing two-enemy defeat fixture leaves a coreImpact child after defeat cleanup;
- kill and leak kinds are distinct;
- restart removes outstanding transient feedback.

When testing Flame child add/remove behavior, follow the existing test convention: mount the game with setMounted() where required and call processLifecycleEvents() before asserting queued children.

### Statuses

Do not add raster/golden tests.

Extend the existing EnemyOverlayState/EnemyOverlayLayout-focused coverage to assert that slowed/corroded state produces the expected ring geometry and that the normal bar/badge/name layout remains valid. The renderer consumes that layout; no second status object is introduced.

## Manual product validation

Check these scenarios on a phone-sized surface:

1. ordinary early-stage wave at 1x;
2. dense multi-target wave at 1x and 3x;
3. boss/final wave with health/status overlays visible;
4. a losing leak so the final coreImpact is visible after defeat cleanup.

Confirm:

- splash radius reads as area damage;
- chain order is understandable;
- railgun reads as a pierce line rather than splash;
- slow/corrosion remain visible without hiding trait/health information;
- enemy death and both non-losing/losing core impacts cannot be confused;
- 3x does not become persistent visual clutter.

## Non-goals

- Damage numbers.
- New combat math or target selection.
- Generic combat-event bus.
- Generic VFX engine or pooling framework.
- Replay/event history.
- Extending GameFeedback with hit cues.
- New audio or haptics.
- New image assets.
- New accessibility setting or persistence.
- Screen shake or mandatory hit-stop.
- New status timers or transition history.
- Prism split, drone, gravity-field, or nanite-hit VFX expansion.
