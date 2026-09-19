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

This is presentation polish only. Damage, targeting, wave timing, enemy lifecycle, tower stats, and balance remain authoritative in their current owners.

## Current implementation seams

The current code already has the right gameplay ownership:

- **lib/game/components/projectile_component.dart** resolves projectile impact.
  - Ion Chain calls CombatEffects.selectChainTargets and then applies damage to those selected enemies.
  - Railgun calls CombatEffects.selectPierceTargets and then applies damage to those selected enemies.
  - Rocket splash resolves its impact point, tests the current enemy set against splashRadius, and applies damage.
  - Cluster bursts reuse the same impact center.
- **lib/game/components/enemy_component.dart** owns the render shell around EnemyLogic and dispatches exactly one kill or reached-base callback.
- **lib/game/orion_defense_game.dart** owns the active component collection and the two distinct resolution callbacks:
  - _handleEnemyKilled
  - _handleEnemyReachedBase
- Enemy slow/corrosion already exist as authoritative EnemyLogic state and feed the existing enemy overlay.

The implementation should attach feedback to these existing resolution points. It should not move combat selection into a new subsystem and should not ask presentation code to select targets again.

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

Use small named/factory constructors rather than a generic effect registry. Each constructor accepts only already-resolved world-space geometry needed to draw the cue.

Representative inputs:

- splash: impact center, splash radius, actual hit positions, projectile color
- chain: resolved target positions in chain order, projectile color
- pierce: firing origin, resolved hit positions in pierce order, projectile color
- enemyDestroyed: enemy center and approximate enemy radius
- coreImpact: enemy/core impact center and approximate enemy radius

The component must not accept EnemyComponent collections, targeting callbacks, damage callbacks, or GameSession. It cannot affect gameplay.

### 2. Prefer stationary geometry plus opacity decay

Feedback should appear immediately at the resolved geometry and then fade out.

Do not add camera shake, hit-stop, travelling secondary particles, oscillation, or an animation state machine.

This gives useful reduced-motion behavior without introducing a new accessibility setting or persistence path: the geometry itself does not move. The only transient behavior is a brief opacity decay and component expiry.

Manual 1x/3x validation decides whether the default lifetime is readable enough. Do not add speed-specific VFX branches pre-emptively.

### 3. ProjectileComponent emits feedback from the same resolution pass

ProjectileComponent remains the authority for projectile-side hit resolution.

Add one narrow optional callback, for example:

- onCombatFeedback(CombatFeedbackComponent feedback)

OrionDefenseGame wires that callback to add(feedback).

Each resolver builds feedback from the enemies it is already resolving:

#### Rocket splash

At impact:

1. Clone the impact position.
2. Resolve the primary hit exactly as today.
3. While iterating splash candidates, record the position of each enemy that actually receives splash damage.
4. Emit one splash feedback component using the same impact center and stats.splashRadius.
5. Cluster bursts reuse this visual; do not emit one component per burst.

The feedback component never rechecks enemy distances.

#### Ion Chain

After CombatEffects.selectChainTargets returns:

1. Map the selected candidates back to live EnemyComponents exactly as today.
2. Record each position immediately before applying that jump's damage.
3. Apply the existing falloff damage.
4. Emit one chain feedback component using only the recorded positions.

The drawn segments therefore mirror the same ordered chain used for damage.

#### Railgun pierce

After CombatEffects.selectPierceTargets returns:

1. Map selected candidates back to enemies exactly as today.
2. Record each position immediately before applying damage.
3. Apply the existing armor multiplier behavior.
4. Emit one pierce feedback component from the projectile origin through the recorded resolved hits.

The feedback component does not call selectPierceTargets.

### 4. Death and leak cues attach to existing game callbacks

OrionDefenseGame adds the resolution cue before the enemy component is removed.

- _handleEnemyKilled adds enemyDestroyed feedback at enemy.position.
- _handleEnemyReachedBase adds coreImpact feedback at enemy.position.

The two visual shapes must be clearly different even without color.

Suggested primitive language:

- enemyDestroyed: compact radial burst / short rays
- coreImpact: heavier ring + cross/diamond impact mark

Boss defeat still uses the same normal destruction cue, scaled from the enemy radius; existing boss audio/haptics remain unchanged.

Transient feedback components must be included in the existing combat cleanup path so restart/return/defeat cannot leave stale effects on a fresh board.

### 5. Slow and corrosion stay state-derived

Do not create onset/expiry events or second timers.

EnemyComponent.render may add a small static treatment derived directly from:

- isSlowed
- isCorroded

For example:

- slowed: thin cool outer ring
- corroded: thin green inner/offset ring

When both are active, both treatments may render if they remain readable.

The existing EnemyOverlayState badges remain the semantic status indicator. The new treatment is only a glanceable board-level reinforcement and disappears automatically when the authoritative state becomes false.

## Layering and visual priority

Keep combat feedback secondary to enemies and their health/status overlays.

Current useful ordering is approximately:

- board: priority 0
- towers: priority 10
- enemies: priority 20
- projectiles: priority 30

CombatFeedbackComponent should render above the board/towers but below enemy bodies/overlays, around priority 15. This keeps chain/pierce/splash geometry visible without covering health bars and trait/status badges.

## No new assets

Use Canvas primitives and current sprite/projectile colors only.

Do not add:

- generated images
- sprite sheets
- new SFX
- new haptics
- package dependencies

Projectile feedback should receive the already-selected projectile color from ProjectileComponent rather than creating a second TowerType-to-color table.

## Testing strategy

Automated tests protect ownership and lifecycle, not pixels.

### CombatFeedbackComponent

Add a focused test file that verifies:

- it keeps the supplied resolved geometry;
- it expires/removes itself after its lifetime;
- it exposes no gameplay callback or mutation path.

### Projectile resolution

Add focused coverage around representative splash, chain, and pierce resolution:

- health/damage outcomes remain the same as current behavior;
- feedback geometry contains the same resolved enemies/positions that received damage;
- no extra candidate selection exists in the feedback component;
- cluster burst emits the normal splash language rather than a parallel effect system.

Use the least costly test seam that fits the existing suite. Prefer extending current component/game tests rather than adding a test-only production API.

### Kill vs leak

In OrionDefenseGame coverage:

- killing an enemy creates enemyDestroyed feedback and preserves the existing reward path;
- reaching the base creates coreImpact feedback and preserves the existing base-damage path;
- the two kinds are distinct;
- restart/combat cleanup removes outstanding transient feedback.

### Statuses

Do not add raster/golden tests for the rings. Existing logic/overlay tests already protect slow and corrosion state. Add only a small non-raster assertion if implementation needs a new derived presentation value; otherwise validate the visual manually.

## Manual product validation

Check these three scenarios on a phone-sized surface:

1. ordinary early-stage wave at 1x;
2. dense multi-target wave at 1x and 3x;
3. boss/final wave with health/status overlays visible.

Confirm:

- splash radius reads as area damage;
- chain order is understandable;
- railgun reads as a pierce line rather than splash;
- slow/corrosion remain visible without hiding trait/health information;
- enemy death and core impact cannot be confused;
- 3x does not become persistent visual clutter.

## Non-goals

- Damage numbers.
- New combat math or target selection.
- Generic combat-event bus.
- Generic VFX engine or pooling framework.
- Replay/event history.
- New audio or haptics.
- New image assets.
- New accessibility setting or persistence.
- Screen shake or mandatory hit-stop.
- New status timers or transition history.
