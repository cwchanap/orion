# HPA-441 — Combat Readability and Feedback Implementation Plan

> **For agentic workers:** implement this plan on the same HPA-441 branch/PR. Do not split the ticket into multiple PRs.

**Goal:** Make Rocket splash, Ion Chain, Railgun pierce, enemy destruction, core leaks, and existing slow/corrosion state visibly distinct without changing any combat outcome.

**Architecture:** Keep all gameplay resolution exactly where it is today. ProjectileComponent continues to select/apply projectile hits; EnemyLogic/EnemyComponent continue to own enemy state/lifecycle; OrionDefenseGame continues to own game-level kill/reached-base handling. Add one small presentation-only CombatFeedbackComponent and feed it already-resolved world-space geometry.

**Tech stack:** Flutter, Flame, Dart. No new packages or assets.

**Spec:** docs/superpowers/specs/2026-09-19-hpa-441-combat-readability-feedback-design.md

## Global constraints

- One PR for HPA-441, including this planning commit and implementation.
- No balance, damage, target selection, wave, timing, reward, or persistence changes.
- No second target-selection pass for VFX.
- No generic event bus, VFX engine, pooling framework, or replay log.
- No new image art, SFX, haptics, package dependencies, or accessibility settings.
- Prefer stationary geometry + opacity decay over moving particles/shake.
- Existing slow/corrosion state remains the only status lifecycle.
- Keep feedback below enemy health/status overlays.
- Tests should prove ownership/lifecycle and unchanged gameplay outcomes, not exact rendered pixels.

---

## Expected file shape

### Create

- lib/game/components/combat_feedback_component.dart
- test/game/combat_feedback_component_test.dart

### Modify

- lib/game/components/projectile_component.dart
- lib/game/components/enemy_component.dart
- lib/game/orion_defense_game.dart
- test/game/orion_defense_game_test.dart

Modify another existing focused test file only if it is clearly the smaller seam. Do not add a separate architecture/model layer for this feature.

---

## Task 1: Add the transient combat-feedback drawing component

**Files**

- Create: lib/game/components/combat_feedback_component.dart
- Create: test/game/combat_feedback_component_test.dart

### Implementation

Add a small enum such as CombatFeedbackKind with exactly the required kinds:

- splash
- chain
- pierce
- enemyDestroyed
- coreImpact

Add CombatFeedbackComponent with focused named constructors/factories:

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
- presentation kind for tests/debugging.

Use priority around 15 so feedback appears above the board/towers but below enemies and their overlays.

Render with Canvas primitives only:

- splash: fixed-radius outline + small hit accents;
- chain: static line segments between ordered resolved points;
- pierce: static firing line from origin through resolved hit positions + small hit accents;
- enemyDestroyed: compact radial burst;
- coreImpact: visually different heavier ring/cross/diamond cue.

Do not animate positions. Update only elapsed opacity and removeFromParent when expired.

Keep durations local constants in this file. Start with a short lifetime that remains plausible at 3x; do not branch on game speed.

### Tests

In combat_feedback_component_test.dart verify:

- constructor inputs are cloned/not mutated by the component;
- kind/geometry are retained for inspection;
- update before expiry keeps the component alive;
- update at/after expiry requests/removes the component when mounted in a minimal FlameGame;
- there is no gameplay callback/API on the component.

Avoid pixel/golden assertions.

### Gate

Run:

- dart format lib/game/components/combat_feedback_component.dart test/game/combat_feedback_component_test.dart
- flutter test test/game/combat_feedback_component_test.dart
- flutter analyze

---

## Task 2: Emit splash/chain/pierce feedback from ProjectileComponent

**Files**

- Modify: lib/game/components/projectile_component.dart
- Modify: test/game/orion_defense_game_test.dart, or the smallest existing projectile-focused test seam if one is already present

### Implementation

Add one optional/narrow callback to ProjectileComponent:

- onCombatFeedback(CombatFeedbackComponent feedback)

Do not introduce a generic dispatcher.

OrionDefenseGame will wire this callback later; ProjectileComponent itself remains usable without feedback in tests.

#### Splash

In the existing splash branch:

1. Clone the impact position once.
2. Preserve current damage ordering/behavior.
3. Record the position of the primary target when it receives damage.
4. While iterating current splash candidates, record each secondary position only when that enemy actually receives splash damage.
5. Emit exactly one CombatFeedbackComponent.splash using:
   - the same impact center;
   - stats.splashRadius;
   - recorded actual hit positions;
   - the existing projectile color.
6. Keep cluster bursts on the same visual. Do not emit one feedback component per cluster burst.

Do not move the distance check into the feedback component.

#### Ion Chain

Keep CombatEffects.selectChainTargets exactly where it is.

While mapping selected candidates back to live enemies:

1. check the same conditions used before applying damage;
2. clone the enemy position immediately before damage;
3. apply existing falloff/shield behavior;
4. append the recorded position.

After the loop, emit one chain component if at least one point was actually resolved.

The line order must match damage order.

#### Railgun pierce

Keep CombatEffects.selectPierceTargets exactly where it is.

For each selected/live enemy:

1. clone its position immediately before applying damage;
2. apply the existing armor multiplier damage;
3. retain the ordered position.

Emit one pierce component from _origin through the recorded hit positions.

### Tests

Add representative assertions for all three mechanics. The important contract is:

- the same enemies that lose health are the enemies represented in feedback geometry;
- chain ordering in feedback matches the resolved chain ordering;
- pierce geometry includes the existing firing origin and resolved hits;
- splash feedback uses the actual impact center/radius;
- existing health/damage results remain unchanged;
- cluster burst still uses one splash feedback component.

Do not test implementation by independently reproducing target selection in the assertion. Set up known enemy positions/health and compare resulting health changes with the emitted component's recorded points.

### Gate

Run the focused projectile/game tests plus:

- flutter analyze

---

## Task 3: Wire feedback into OrionDefenseGame and distinguish kill vs leak

**Files**

- Modify: lib/game/orion_defense_game.dart
- Modify: test/game/orion_defense_game_test.dart

### Implementation

#### Projectile sink

When constructing ProjectileComponent in _launchProjectile, pass:

- onCombatFeedback: (feedback) => add(feedback)

No queue, stream, notifier, or event bus.

#### Enemy destruction

At the start of _handleEnemyKilled, while the enemy position/radius are still available, add CombatFeedbackComponent.enemyDestroyed.

Then continue the current path unchanged:

- inspection cleanup;
- active-enemy removal;
- rewardKill;
- boss feedback;
- snapshot publish.

Do not delay enemy removal or reward dispatch for the animation.

#### Core impact

At the start of _handleEnemyReachedBase, add CombatFeedbackComponent.coreImpact at the enemy's current position/radius.

Then continue the current base-damage/loss path unchanged.

The death and leak components must have distinct CombatFeedbackKind values and distinct primitive shapes.

#### Cleanup

Extend _clearCombatComponents to remove outstanding CombatFeedbackComponent children along with projectiles/drones/fields.

This makes restart/defeat/other combat cleanup deterministic without adding new lifecycle ownership.

### Tests

Extend OrionDefenseGame coverage:

- killing a spawned enemy creates enemyDestroyed feedback;
- kill reward/snapshot outcome stays the same;
- forcing an enemy to reach the base creates coreImpact feedback;
- base health/loss behavior stays the same;
- the two feedback kinds are distinct;
- restart/cleanup removes outstanding combat-feedback components.

Avoid adding public test-only mutation methods to OrionDefenseGame. Use the current enemy/component seams already exercised by the test suite.

### Gate

Run:

- flutter test test/game/orion_defense_game_test.dart
- flutter analyze

---

## Task 4: Reinforce slow/corrosion from existing authoritative state

**Files**

- Modify: lib/game/components/enemy_component.dart
- Modify an existing enemy/overlay test only if a new pure derived value is introduced

### Implementation

Keep EnemyOverlayState and EnemyLogic as-is.

In EnemyComponent.render, add a small static state treatment derived directly from:

- isSlowed
- isCorroded

Recommended shape:

- slowed: thin cool outer ring;
- corroded: thin green inner/offset ring.

Draw these around the sprite without obscuring:

- health/shield bars;
- trait/status badges;
- boss name.

No timers, onset pulses, expiry animation, or transition history.

If both statuses are active, both may render if manual validation shows they remain legible.

Do not create a second status-presentational state object unless the render code becomes genuinely difficult to read. Two booleans are already the correct source.

### Tests

Do not add a golden test.

Existing EnemyLogic and EnemyOverlayState coverage should continue to prove the state itself. Only add a small unit assertion if implementation introduces a new pure helper; otherwise leave visual verification to the manual gate.

### Gate

Run:

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

Confirm the diff contains no changes under:

- lib/game/rules/ except incidental formatting (prefer none);
- lib/game/models/;
- campaign balance data;
- assets/;
- pubspec.yaml.

If gameplay tests change expected damage, targeting, reward, wave timing, or base damage values, treat that as a regression and fix the implementation rather than updating the expectation.

### Manual

On a phone-sized surface:

1. **Ordinary early wave, 1x**
   - normal projectiles remain visually quiet;
   - destruction cue is visible but brief.

2. **Dense multi-target wave, 1x and 3x**
   - Rocket reads as area damage;
   - Ion Chain links the real resolved sequence;
   - Railgun reads as a pierce line;
   - feedback does not become persistent clutter at 3x.

3. **Boss/final wave**
   - health/shield/status overlays remain readable;
   - slow/corrosion reinforcement does not hide boss/trait information;
   - enemy destruction cannot be confused with a core leak.

If 3x readability is poor, make the smallest duration/opacity adjustment in CombatFeedbackComponent. Do not introduce a separate 3x effect system.

---

## Definition of done

- Rocket splash, Ion Chain, and Railgun pierce have distinct primitive feedback.
- Secondary-hit visuals use already-resolved targets/positions.
- Slow/corrosion reinforcement reads directly from authoritative existing state.
- Enemy destruction and core impact are visibly/structurally distinct.
- Effects self-clean and are also removed by combat cleanup.
- No gameplay/balance behavior changes.
- No new assets or dependencies.
- Focused tests, flutter analyze, and full flutter test pass.
- The implementation lands on this same draft PR as one HPA-441 PR.
