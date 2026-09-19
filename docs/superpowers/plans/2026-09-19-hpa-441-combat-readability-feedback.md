# HPA-441 — Combat Readability and Feedback Implementation Plan

> **For agentic workers:** implement this plan on the same HPA-441 branch/PR. Do not split the ticket into multiple PRs.

**Goal:** Make Rocket splash, Ion Chain, Railgun pierce, enemy destruction, core leaks, and existing slow/corrosion state visibly distinct without changing any combat outcome.

**Architecture:** Keep gameplay resolution exactly where it is today. ProjectileComponent continues to select/apply projectile hits; EnemyLogic/EnemyComponent continue to own enemy state/lifecycle; OrionDefenseGame continues to own game-level kill/reached-base handling; EnemyOverlayRenderer/Layout continue to own enemy status presentation. Add one small presentation-only CombatFeedbackComponent and feed it already-resolved world-space geometry.

**Tech stack:** Flutter, Flame, Dart. No new packages or assets.

**Spec:** docs/superpowers/specs/2026-09-19-hpa-441-combat-readability-feedback-design.md

## Global constraints

- One PR for HPA-441, including planning and implementation.
- No balance, damage, target selection, wave, timing, reward, or persistence changes.
- No second target-selection pass for VFX.
- No generic event bus, VFX engine, pooling framework, or replay log.
- Do not extend GameFeedback; it stays the existing audio/haptic boundary.
- No new image art, SFX, haptics, package dependencies, or accessibility settings.
- Prefer stationary geometry + opacity decay over moving particles/shake.
- Use the dt CombatFeedbackComponent already receives; no speed-specific VFX state.
- Existing slow/corrosion state remains the only status lifecycle.
- Parent transient feedback on OrionDefenseGame, never on a projectile or dying enemy.
- Prism split, drones, gravity-field tick VFX, and nanite hit flashes stay out.
- Tests prove ownership/lifecycle/geometry and unchanged gameplay outcomes, not exact pixels.

---

## Expected file shape

### Create

- lib/game/components/combat_feedback_component.dart
- test/game/combat_feedback_component_test.dart
- test/game/projectile_component_test.dart

### Modify

- lib/game/components/projectile_component.dart
- lib/game/components/enemy_overlay.dart
- lib/game/rules/enemy_overlay_state.dart
- lib/game/orion_defense_game.dart
- test/game/enemy_component_test.dart or the existing overlay-state/layout test location
- test/game/orion_defense_game_test.dart

Do not add another architecture/model layer for this feature.

---

## Task 1: Add the transient combat-feedback drawing component

**Files**

- Create: lib/game/components/combat_feedback_component.dart
- Create: test/game/combat_feedback_component_test.dart

### Implementation

Add a small enum such as CombatFeedbackKind with exactly:

- splash
- chain
- pierce
- enemyDestroyed
- coreImpact

Add named constructors/factories:

- CombatFeedbackComponent.splash(...)
- CombatFeedbackComponent.chain(...)
- CombatFeedbackComponent.pierce(...)
- CombatFeedbackComponent.enemyDestroyed(...)
- CombatFeedbackComponent.coreImpact(...)

The component owns only presentation data:

- cloned world-space Vector2 positions;
- optional radius;
- paint/color;
- elapsed/lifetime;
- kind for tests/debugging.

It must not own EnemyComponents, enemy providers, targeting functions, damage callbacks, GameSession, or GameFeedback.

Pin priority in the named constructors rather than adding a z-layer abstraction:

- splash: 15
- enemyDestroyed: 15
- coreImpact: 15
- chain: 25
- pierce: 25

Render with Canvas primitives only:

- splash: fixed-radius area outline/flash; low-priority resolved hit accents are optional but are not relied on for readability;
- chain: thin static line segments through the ordered resolved points plus compact center accents;
- pierce: thin static firing line from origin through resolved hit positions plus compact center accents;
- enemyDestroyed: compact radial burst;
- coreImpact: visually different heavier ring/cross/diamond cue.

Keep chain/pierce strokes thin and centered on enemy bodies so they do not compete with health/status overlays.

Do not animate positions. Update only elapsed opacity and removeFromParent when expired.

Use the dt passed into CombatFeedbackComponent.update directly. Do not inspect game speed or create a separate 3x lifetime.

Do not reuse GravityFieldComponent: it applies gameplay damage and is therefore the wrong owner despite having a similar transient lifecycle.

### Tests

In combat_feedback_component_test.dart verify:

- constructor inputs are cloned/not mutated by the component;
- kind/geometry are retained for inspection;
- each named constructor selects the pinned priority;
- update before expiry keeps the component alive;
- update at/after expiry removes it when mounted in a minimal FlameGame;
- no gameplay callback/API exists on the component.

Avoid pixel/golden assertions.

### Gate

Run:

- dart format lib/game/components/combat_feedback_component.dart test/game/combat_feedback_component_test.dart
- flutter test test/game/combat_feedback_component_test.dart
- flutter analyze

---

## Task 2: Emit splash/chain/pierce feedback directly from ProjectileComponent

**Files**

- Modify: lib/game/components/projectile_component.dart
- Create: test/game/projectile_component_test.dart

### Implementation

Add one optional/narrow callback:

- onCombatFeedback(CombatFeedbackComponent feedback)

Do not introduce a generic dispatcher.

ProjectileComponent itself stays independently testable. OrionDefenseGame wiring is Task 3.

Use the existing ProjectileComponent paint.color for feedback. Do not add another TowerType-to-color table.

#### Splash

In the existing splash branch:

1. Clone impactPosition once.
2. Preserve current damage ordering/behavior.
3. Clone target.position immediately before the existing primary target.applyDamage call.
4. Keep the current secondary alive/identity/distance checks exactly where they are.
5. Inside the existing distanceTo(impactPosition) <= stats.splashRadius branch, clone enemy.position immediately before enemy.applyDamage.
6. Do not inspect health before/after damage and do not change EnemyComponent.applyDamage's void API.
7. Emit exactly one CombatFeedbackComponent.splash using:
   - the same impact center;
   - stats.splashRadius;
   - the recorded resolved positions;
   - paint.color.
8. Keep Cluster Rocket on this one splash visual. Its current clusterBurstRadius 42 is inside splashRadius 72; do not emit a component per cluster burst.

The feedback component must not recheck distance or select candidates.

#### Ion Chain

Keep CombatEffects.selectChainTargets exactly where it is.

While mapping selected candidates back to live enemies:

1. keep the existing live/null check;
2. clone enemy.position immediately before damage;
3. apply the existing falloff and shield multiplier behavior;
4. retain the cloned position in the same order.

Emit one chain component if at least one enemy was actually resolved.

#### Railgun pierce

Keep CombatEffects.selectPierceTargets exactly where it is.

For each selected/live enemy:

1. clone its position immediately before applying damage;
2. apply the existing armor multiplier damage;
3. retain the ordered cloned position.

Emit one pierce component from _origin through those resolved positions.

### Tests

Build direct ProjectileComponent tests around the optional callback.

For each representative mechanic:

- mount real EnemyComponents/ProjectileComponent with the minimum Flame host needed by the existing component lifecycle;
- arrange enemy positions so the outcome is unambiguous;
- capture the emitted CombatFeedbackComponent through the callback;
- assert existing enemy health/damage outcomes;
- assert captured geometry corresponds to the same enemies that were damaged, without calling CombatEffects target-selection helpers again in the expectation.

Pin:

- splash center/radius + recorded resolved positions;
- chain ordered positions;
- pierce origin + ordered resolved positions;
- Cluster Rocket emits one splash component despite its extra damage loop.

Do not add test-only production methods.

### Gate

Run:

- dart format lib/game/components/projectile_component.dart test/game/projectile_component_test.dart
- flutter test test/game/projectile_component_test.dart
- flutter analyze

---

## Task 3: Wire game-owned feedback and make the losing leak survive cleanup

**Files**

- Modify: lib/game/orion_defense_game.dart
- Modify: test/game/orion_defense_game_test.dart

### Implementation

#### Projectile sink

When constructing ProjectileComponent in _launchProjectile, pass:

- onCombatFeedback: (feedback) => add(feedback)

No queue, stream, notifier, event bus, or GameFeedback change.

#### Enemy destruction

At the start of _handleEnemyKilled, while enemy.position/radius are still available, add CombatFeedbackComponent.enemyDestroyed.

Then continue the current handler unchanged:

- inspection cleanup;
- active-enemy removal;
- rewardKill;
- boss feedback;
- snapshot publish.

Do not delay enemy removal or reward dispatch.

#### Core impact

Do **not** add coreImpact at the start of _handleEnemyReachedBase.

The current losing path calls _clearCombatComponents, which would immediately delete it.

Instead:

1. clone enemy.position and enemy.radius at the start;
2. run the existing handler body, including damageBase and the wave -> lost cleanup;
3. publish the current snapshot exactly as today;
4. add CombatFeedbackComponent.coreImpact from the cloned geometry after the possible cleanup.

This applies to both non-losing and losing leaks. On a losing leak, old combat VFX are cleared first and the current coreImpact survives.

#### Cleanup

Extend _clearCombatComponents to remove CombatFeedbackComponent children alongside projectiles/drones/fields.

This is still correct:

- restart uses the cleanup path and wipes leftover VFX;
- a losing leak clears previous VFX, then adds its own coreImpact afterward;
- no VFX component owns gameplay or delays lifecycle resolution.

### Tests

Keep game-level lifecycle tests in orion_defense_game_test.dart.

Follow the existing Flame unit-test lifecycle convention:

- call setMounted() where child add/remove during update needs queue semantics;
- call processLifecycleEvents() before asserting newly queued/removed children.

Add/extend tests for:

- a kill creates enemyDestroyed and preserves existing reward/snapshot behavior;
- a non-losing leak creates coreImpact and preserves base damage;
- the existing _twoEnemyDefeatStage case reaches lost, clears enemies, **and still has one coreImpact child after defeat cleanup**;
- enemyDestroyed and coreImpact kinds are distinct;
- restart removes an outstanding coreImpact/other transient feedback;
- existing baseDefeated/bossDefeated/wave behavior remains unchanged.

A non-losing leak test alone is insufficient; keep the defeat assertion explicit.

### Gate

Run:

- dart format lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
- flutter test test/game/orion_defense_game_test.dart
- flutter analyze

---

## Task 4: Put slow/corrosion rings into EnemyOverlayRenderer/Layout

**Files**

- Modify: lib/game/components/enemy_overlay.dart
- Modify: lib/game/rules/enemy_overlay_state.dart
- Modify: the existing enemy overlay/layout unit-test location
- Do not add a second status presentation model

### Implementation

Keep EnemyLogic and EnemyOverlayState's existing status derivation authoritative.

EnemyComponent already renders the sprite and then calls EnemyOverlayRenderer. Keep that paint order.

In EnemyOverlayRenderer.render:

1. compute EnemyOverlayLayout as today;
2. draw status rings first, using the existing state.badges to detect EnemyOverlayBadge.slowed / EnemyOverlayBadge.corroded;
3. then draw the existing badges, health/shield bars, and boss name.

This yields:

- sprite (EnemyComponent)
- status rings (EnemyOverlayRenderer)
- bars/badges/name (EnemyOverlayRenderer)

The higher-signal overlay remains legible over the ring treatment.

Extend EnemyOverlayLayout with only the ring geometry needed for non-raster testing, for example nullable slowedRingRadius / corrodedRingRadius (and offsets only if actually needed).

Recommended treatment:

- slowed: thin cool outer ring;
- corroded: thin green inner/offset ring.

Reuse the renderer's existing status colors where practical. Do not create a second status-color table if _fallbackColor already owns the same badge colors.

No timers, onset pulse, expiry animation, or transition history.

### Tests

No goldens.

Extend the existing pure layout/state tests to assert:

- slowed state yields slowed ring geometry;
- corroded state yields corroded ring geometry;
- both can coexist;
- resolved/no-status enemies have no status-ring geometry;
- bar/badge/name layout remains otherwise unchanged.

The renderer should remain a consumer of this layout, not a second geometry owner.

### Gate

Run:

- dart format lib/game/components/enemy_overlay.dart lib/game/rules/enemy_overlay_state.dart
- flutter test test/game/enemy_component_test.dart
- flutter test test/game/combat_effects_test.dart
- flutter analyze

---

## Task 5: Whole-ticket validation and product pass

### Automated

Run:

- dart format --output=none --set-exit-if-changed .
- flutter analyze
- flutter test

Confirm the diff does not change:

- combat selection/damage rules under lib/game/rules/ except the existing overlay-layout presentation file;
- game balance values in lib/game/models/;
- campaign data;
- assets/;
- pubspec.yaml;
- GameFeedback.

If gameplay tests require new expected damage, targeting, reward, wave timing, or base-damage numbers, treat that as a regression and fix implementation rather than updating the expectation.

### Manual

On a phone-sized surface:

1. **Ordinary early wave, 1x**
   - normal projectiles remain visually quiet;
   - destruction cue is visible but brief.

2. **Dense multi-target wave, 1x and 3x**
   - Rocket reads as area damage;
   - Ion Chain links the real resolved sequence;
   - Railgun reads as a pierce line;
   - chain/pierce strokes remain readable on live bodies without hiding overlays;
   - feedback does not become persistent clutter at 3x.

3. **Boss/final wave**
   - health/shield/status overlays remain readable;
   - slow/corrosion rings sit behind bars/badges/name;
   - enemy destruction remains readable.

4. **Losing leak**
   - the board cleanup still occurs immediately;
   - the final coreImpact remains visible after cleanup;
   - it is unmistakable from enemyDestroyed.

If 3x readability is poor, make the smallest duration/opacity/stroke-width adjustment in CombatFeedbackComponent. Do not introduce a separate 3x effect system.

---

## Definition of done

- Rocket splash, Ion Chain, and Railgun pierce have distinct primitive feedback.
- Chain/pierce visuals consume already-resolved target positions; splash records positions in the existing damage branch before applyDamage.
- Slow/corrosion rings use existing EnemyOverlayState + EnemyOverlayRenderer/Layout ownership.
- Enemy destruction and core impact are visibly/structurally distinct.
- The losing leak leaves coreImpact visible after defeat cleanup.
- CombatFeedbackComponent self-cleans; restart/combat cleanup removes outstanding older effects.
- No gameplay/balance behavior changes.
- No GameFeedback extension.
- No new assets or dependencies.
- Dedicated component/projectile tests plus game lifecycle tests cover ownership and cleanup.
- dart format, flutter analyze, and full flutter test pass.
- The implementation lands on this same draft PR as one HPA-441 PR.
