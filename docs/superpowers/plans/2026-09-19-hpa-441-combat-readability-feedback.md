# HPA-441 — Combat Readability and Feedback Implementation Plan

> **For agentic workers:** implement this plan on the same HPA-441 branch/PR. Do not split the ticket into multiple PRs.

**Goal:** Make Rocket splash, Ion Chain, Railgun pierce, enemy destruction, non-losing core leaks, and existing slow/corrosion state visibly distinct without changing combat outcomes.

**Architecture:** Keep gameplay resolution where it is today. ProjectileComponent continues to resolve projectile hits; EnemyLogic/EnemyComponent continue to own enemy lifecycle; OrionDefenseGame continues to own kill/reached-base orchestration and cleanup; EnemyOverlayRenderer/Layout continue to own enemy status presentation. Add one presentation-only CombatFeedbackComponent and feed it already-resolved geometry.

**Tech stack:** Flutter + Flame + Dart. No new packages or assets.

**Spec:** docs/superpowers/specs/2026-09-19-hpa-441-combat-readability-feedback-design.md

## Global constraints

- One PR for HPA-441, including planning and implementation.
- No balance, damage, target selection, wave timing, reward, persistence, or enemy lifecycle changes.
- No second target-selection pass for VFX.
- No generic event bus, VFX engine, registry, pool, replay log, or telemetry.
- Do not extend GameFeedback.
- No new image art, SFX, haptics, package dependencies, or accessibility settings.
- Stationary geometry + opacity decay only.
- Use normal Flame dt; no speed-specific VFX state.
- Parent feedback on OrionDefenseGame, never on a projectile/enemy that immediately removes itself.
- Existing slow/corrosion state remains the only status lifecycle.
- Final-loss debrief timing is out of scope.
- Prism split, drones, gravity-field ticks, and nanite hit flashes stay out.
- Tests prove ownership, geometry, render execution, lifecycle, and unchanged gameplay numbers; no golden/pixel assertions.

---

## Expected file shape

### Create

- lib/game/components/combat_feedback_component.dart
- test/components/combat_feedback_component_test.dart
- test/components/projectile_component_test.dart
- test/components/enemy_overlay_test.dart

### Modify

- lib/game/components/projectile_component.dart
- lib/game/components/enemy_overlay.dart
- lib/game/rules/enemy_overlay_state.dart
- lib/game/orion_defense_game.dart
- test/game/enemy_component_test.dart
- test/game/game_balance_test.dart
- test/game/orion_defense_game_test.dart

Do not add another architecture/model layer.

---

## Task 1: Add CombatFeedbackComponent with executable render coverage

**Files**

- Create: lib/game/components/combat_feedback_component.dart
- Create: test/components/combat_feedback_component_test.dart

### Production shape

Add:

- enum CombatFeedbackKind:
  - splash
  - chain
  - pierce
  - enemyDestroyed
  - coreImpact

- typedef:
  - `CombatFeedbackCallback = void Function(CombatFeedbackComponent feedback)`

- named constructors:
  - CombatFeedbackComponent.splash(...)
  - CombatFeedbackComponent.chain(...)
  - CombatFeedbackComponent.pierce(...)
  - CombatFeedbackComponent.enemyDestroyed(...)
  - CombatFeedbackComponent.coreImpact(...)

Keep geometry fields total, not nullable.

A simple implementation can use:

- `Vector2 origin`
- cloned `List<Vector2> positions` (empty when unused)
- `double radius` (0 when unused)
- Color/paint
- kind
- elapsed/lifetime

Do not introduce a sealed data hierarchy.

### Priority

Pin constructor priority:

- enemyDestroyed: 15
- coreImpact: 15
- splash: 26
- chain: 26
- pierce: 26

26 intentionally clears the existing GravityField priority 25 rather than relying on equal-priority insertion order.

### Rendering

Use Canvas primitives:

- splash:
  - thin area ring/flash at origin/radius;
  - restrained low-opacity hit accent at every resolved position.
- chain:
  - thin lines through ordered positions;
  - compact hit accents.
- pierce:
  - thin line from origin through ordered positions;
  - compact hit accents.
- enemyDestroyed:
  - compact radial burst.
- coreImpact:
  - visibly different heavier ring + cross/diamond mark.

Keep multi-target cue strokes brief/thin so health/status information remains higher signal.

Do not animate positions. Only advance elapsed opacity and remove on expiry.

### Tests

In combat_feedback_component_test.dart:

1. verify every constructor clones caller-owned Vector2/list inputs;
2. verify kind/geometry values are retained;
3. verify total fields have sensible empty/zero values for unused geometry;
4. verify priorities 15 vs 26;
5. mount one component in a minimal FlameGame and verify expiry/removal lifecycle;
6. drive `render()` into a `ui.PictureRecorder` for **all five kinds**:
   - once at full opacity;
   - once after update to a near-expiry elapsed value;
   - assert `returnsNormally`.

No image comparison/golden.

The render-execution tests are required because repository Codecov enforces 90% patch coverage and render() is a large part of this diff.

### Gate

Run:

- dart format lib/game/components/combat_feedback_component.dart test/components/combat_feedback_component_test.dart
- flutter test test/components/combat_feedback_component_test.dart
- flutter analyze

---

## Task 2: Emit projectile feedback from current damage loops

**Files**

- Modify: lib/game/components/projectile_component.dart
- Create: test/components/projectile_component_test.dart
- Modify: test/game/game_balance_test.dart

### Production callback

Add optional:

- `CombatFeedbackCallback? onCombatFeedback`

Follow the existing typedef-per-callback convention instead of an inline function type.

Use ProjectileComponent's existing `paint.color`; do not add another TowerType/color map.

### Rocket splash

Inside the existing splash branch:

1. clone impactPosition once;
2. clone target.position immediately before the existing primary `target.applyDamage`;
3. keep current secondary checks:
   - not identical target;
   - alive;
   - within splashRadius;
4. inside the existing radius branch, clone enemy.position immediately before `enemy.applyDamage`;
5. append each cloned position to resolvedPositions;
6. emit exactly one `CombatFeedbackComponent.splash` with:
   - origin = impactPosition;
   - radius = stats.splashRadius;
   - positions = resolvedPositions;
   - color = paint.color.

Do not:

- inspect pre/post health just for VFX;
- change EnemyComponent.applyDamage return type;
- re-run distance checks in CombatFeedbackComponent.

The positions are real presentation data because splash render draws one restrained accent per resolved hit.

### Cluster Rocket

Do not add cluster-specific feedback code and do not add a special "one callback despite cluster bursts" component assertion.

Instead add one **game_balance_test.dart** invariant:

- `clusterBurstRadius <= splashRadius` for Cluster Rocket.

That is the tuning relation that justifies using the one normal splash visual.

### Ion Chain

Keep CombatEffects.selectChainTargets where it is.

For each candidate mapped to a live EnemyComponent:

1. clone enemy.position immediately before damage;
2. apply existing falloff + shield multiplier behavior;
3. keep the cloned point in the same order.

Emit one chain component from those points.

### Railgun pierce

Keep CombatEffects.selectPierceTargets where it is.

For each selected live enemy:

1. clone enemy.position immediately before damage;
2. apply existing armor multiplier behavior;
3. retain ordered point.

Emit one pierce component using:

- origin = _origin;
- positions = ordered resolved points.

### Dedicated direct tests

Use **test/components/projectile_component_test.dart**.

No FlameGame host is needed for these projectile-resolution tests.

Construct EnemyComponents directly using the same small fixtures as enemy_component_test.dart.

Important existing guard: `ProjectileComponent.update` requires `target.isMounted`.

Therefore, in test setup:

- explicitly call the component test-only `setMounted()` on the standalone target (and candidates where useful for fidelity);
- use the same `invalid_use_of_internal_member` ignore style already used elsewhere;
- construct ProjectileComponent directly;
- call `projectile.update(dt)`;
- capture feedback via the optional callback.

Do **not** create a GameWidget/FlameGame host or call processLifecycleEvents for Task 2.

Test:

- splash health outcomes + emitted center/radius/positions;
- chain health outcomes + emitted ordered positions;
- pierce health outcomes + origin/ordered positions;
- no expected-value logic calls CombatEffects selectors again.

### Gate

Run:

- dart format lib/game/components/projectile_component.dart test/components/projectile_component_test.dart test/game/game_balance_test.dart
- flutter test test/components/projectile_component_test.dart
- flutter test test/game/game_balance_test.dart
- flutter analyze

---

## Task 3: Wire game-level kill/leak cues and cleanup

**Files**

- Modify: lib/game/orion_defense_game.dart
- Modify: test/game/orion_defense_game_test.dart

### Projectile sink

When constructing ProjectileComponent in _launchProjectile:

- `onCombatFeedback: _addCombatFeedback`

No notifier, queue, stream, bus, or GameFeedback change.

### Enemy destruction

At the start of _handleEnemyKilled:

- emit CombatFeedbackComponent.enemyDestroyed via _addCombatFeedback using current enemy.position/radius.

Then keep existing logic unchanged:

- inspected-enemy cleanup;
- active enemy removal;
- rewardKill;
- boss feedback;
- snapshot publication.

This one central seam automatically covers kills from projectile/drone/gravity/corrosion sources.

### Core impact

At the start of _handleEnemyReachedBase:

- emit CombatFeedbackComponent.coreImpact via _addCombatFeedback using current enemy.position/radius.

Then keep current handler unchanged.

Expected behavior:

- non-losing leak: cue survives and is visible on the live board;
- losing leak: _clearCombatComponents cancels the still-queued cue before the full-screen MissionReportPanel appears.

Do not clone geometry and re-add the effect after defeat cleanup.

If final losing-hit readability is wanted later, scope a separate UI transition task; do not delay/reorder the debrief in HPA-441.

### Cleanup

All feedback additions route through _addCombatFeedback, which tracks each cue in a `_combatFeedbackComponents` set. _clearCombatComponents calls removeFromParent on every tracked cue — for a cue whose add is still queued, removeFromParent cancels the pending add, so defeat cleanup cannot be outrun by the mount queue — then clears the set, together with removing:

- projectiles;
- drones;
- gravity fields.

Restart then clears leftover effects naturally.

### Tests

In orion_defense_game_test.dart:

- kill emits enemyDestroyed and preserves existing reward outcome;
- non-losing reach-base emits coreImpact and preserves base-health damage;
- kill/core kinds are distinct;
- restart removes outstanding CombatFeedbackComponent children;
- losing leak leaves no queued coreImpact behind after defeat cleanup;
- existing loss fixture still reaches lost and clears combat components;
- **do not** assert losing defeat retains coreImpact.

Where game children are queued by Flame lifecycle, continue using the existing:

- `game.setMounted()`
- `processLifecycleEvents()`

pattern before child assertions.

### Gate

Run:

- dart format lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
- flutter test test/game/orion_defense_game_test.dart
- flutter analyze

---

## Task 4: Add state-derived status rings through the existing overlay owner

**Files**

- Modify: lib/game/components/enemy_overlay.dart
- Modify: lib/game/rules/enemy_overlay_state.dart
- Modify: test/game/enemy_component_test.dart
- Create: test/components/enemy_overlay_test.dart

### Layout

Extend EnemyOverlayLayout with only the geometry the new ring branches require, e.g.:

- slowedRingRadius (0/null-free representation preferred if clean)
- corrodedRingRadius
- offset only if the actual render needs it

Keep geometry computation pure.

### Renderer

EnemyComponent already renders the sprite and then calls EnemyOverlayRenderer. Do not modify that ownership.

EnemyOverlayRenderer.render:

1. compute layout;
2. draw status rings from existing `state.badges`:
   - corroded;
   - slowed;
3. draw existing badges;
4. draw health/shield bars;
5. draw boss name.

Reuse existing badge colors where practical; do not introduce a second status-color map.

No timers, onset pulse, transition history, or second status object.

### Ordering invariant

The existing EnemyComponent test already applies slow + corrosion while shielded/regen traits are present and expects exactly:

- corroded
- slowed

under the normal two-badge cap.

That already pins the critical ordering invariant. Keep it; do not add a duplicate ordering test.

### Tests

Extend enemy_component_test.dart:

- layout exposes slowed-ring geometry when slowed badge present;
- layout exposes corroded-ring geometry when corroded badge present;
- both coexist;
- no status ring geometry for a resolved/no-status overlay;
- current bar/badge layout invariants remain green.

Add explicit render execution for a state containing both statuses and assert `returnsNormally`. This renderer test lives in **test/components/enemy_overlay_test.dart** — recorder-based render coverage sits outside the pure-logic `test/game/` suite — while the layout assertions stay in enemy_component_test.dart.

No golden tests.

### Gate

Run:

- dart format lib/game/components/enemy_overlay.dart lib/game/rules/enemy_overlay_state.dart test/game/enemy_component_test.dart test/components/enemy_overlay_test.dart
- flutter test test/game/enemy_component_test.dart test/components/enemy_overlay_test.dart
- flutter analyze

---

## Task 5: Whole-ticket validation

### Automated

Run:

- dart format --output=none --set-exit-if-changed .
- flutter analyze
- flutter test

Verify CI/coverage:

- Codecov patch target remains >= 90%.

Confirm the diff does not change:

- combat/damage targeting rules under lib/game/rules/ except enemy_overlay_state.dart presentation layout;
- GameBalance tuning except the **test-only** cluster relation assertion;
- campaign definitions;
- assets;
- pubspec.yaml;
- GameFeedback.

If existing gameplay tests require changed expected:

- damage;
- target selection;
- rewards;
- wave timing;
- base damage;

treat it as a regression rather than updating the expectation.

### Manual product checks

On a phone-sized surface:

1. **ordinary early wave @ 1x**
   - normal projectiles remain quiet;
   - enemyDestroyed is readable and brief.

2. **dense multi-target wave @ 1x and 3x**
   - splash ring reads as AoE;
   - per-hit splash accents show which enemies were caught;
   - chain links the real resolved sequence;
   - railgun reads as pierce;
   - priority-26 strokes remain thin enough not to obscure bars/statuses;
   - 3x does not leave persistent clutter.

3. **boss/final wave**
   - status rings remain secondary to bars/badges/name;
   - destruction cue remains readable.

4. **non-losing leak**
   - coreImpact is visible;
   - base damage remains unchanged;
   - cue is visibly distinct from enemyDestroyed.

No manual requirement for the final losing leak because the full-screen debrief intentionally replaces the board immediately.

If 3x readability is poor, adjust only local duration/opacity/stroke width. Do not add a separate high-speed VFX system.

---

## Definition of done

- One CombatFeedbackComponent; five named constructors; no VFX framework.
- CombatFeedbackCallback follows existing callback typedef convention.
- Geometry fields are total rather than nullable/asserted.
- Splash/chain/pierce use already-resolved damage-loop geometry.
- Splash actually draws its resolved-hit positions.
- Cluster Rocket reuse is guarded by a balance-test relation, not a special VFX path/test.
- Splash/chain/pierce priority 26; death/core priority 15.
- Kill cue comes from _handleEnemyKilled.
- Non-losing leak cue comes from _handleEnemyReachedBase; losing leak is allowed to be cleared by the debrief transition.
- Slow/corrosion rings use EnemyOverlayState + EnemyOverlayRenderer/Layout.
- Existing badge-order test remains the invariant for status-ring eligibility.
- Recorder tests execute every new render branch without pixel coupling.
- Direct projectile tests require no FlameGame host; standalone target mounting is explicit.
- Combat cleanup removes transient feedback.
- No GameFeedback extension, new assets, dependencies, SFX, haptics, or balance changes.
- dart format, flutter analyze, full flutter test, and 90% patch coverage gate pass.
- Everything lands on this same draft PR.
