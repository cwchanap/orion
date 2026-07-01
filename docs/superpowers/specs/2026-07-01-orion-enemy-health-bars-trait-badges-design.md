# Orion Enemy Health Bars And Trait Badges Design

## Context

HPA-95 improves combat readability in Orion, a portrait, touch-first Flutter and Flame tower-defense game. The existing architecture separates deterministic mission rules from Flame rendering. Enemy runtime state already lives in `EnemyComponent`: current health, current shield, traits, slow state, corrosion state, path progress, and resolution callbacks. Combat math remains in pure helpers such as `CombatEffects`.

The previous pre-wave enemy intel panel intentionally excluded in-combat health bars, shield bars, and trait badges. This feature fills that combat-readability gap without changing wave balance, enemy stats, tower behavior, or campaign persistence.

The tower variety sprite sheet already contains indicator-like sprites for shield, armor, regen, and corrosion. The design should reuse those where available and fall back to compact drawn badges where a sprite is missing or a trait has no dedicated sprite.

## Goal

Players should be able to understand enemy durability and special state during active waves without turning swarm waves into visual clutter.

The feature adds:

- Enemy health visibility.
- Separate shield visibility for shielded enemies.
- Compact trait badges for armored, shielded, regen, swarm, and heavy enemies.
- Compact effect badges for slowed and corroded enemies.
- Touch inspection for one enemy at a time, so players can reveal more detail on demand.

## Scope

In scope:

- Active-wave enemy overlays rendered by the Flame layer.
- Hybrid visibility: lightweight automatic indicators for notable enemies, expanded details for one tapped enemy.
- Health and shield display state helpers with testable ratio and badge-ordering logic.
- Reuse of `GameTowerVarietySheet` indicator sprites for shield, armor, regen, and corrosion.
- A narrow tap-hit path in `OrionDefenseGame` that can inspect enemies during waves.

Out of scope:

- Combat balance changes.
- New enemy traits.
- New generated art.
- Pre-wave intel panel changes.
- Campaign, persistence, medal, economy, or wave changes.
- A broad HUD or bottom-control redesign.

## Visibility Model

The overlay is selective instead of globally verbose.

An enemy is notable when it has at least one of:

- Current health below max health.
- Shield capacity or current shield.
- `armored`, `shielded`, `regen`, or `heavy` trait.
- Active slow effect.
- Active corrosion effect.

Swarm alone does not make an enemy notable, because swarm readability depends on keeping the mass of units light. Swarm can still appear in the badge list when the enemy is inspected or when it also has a higher-signal trait or effect.

Normal notable enemies render a minimal overlay:

- Health bar when damaged or when shield state is relevant.
- Shield bar when shield capacity or current shield is greater than zero.
- Up to two badges in priority order.

The inspected enemy renders the expanded overlay:

- Health bar for any active inspected enemy.
- Shield bar when shield capacity or current shield is greater than zero.
- Up to four badges in priority order. Four badges cover all current enemy archetype combinations plus slowed and corroded effects.

## Interaction

`OrionDefenseGame` owns `int? _inspectedEnemyId`.

During active waves, tap handling checks active enemies before board cells. If the tap is within an enemy touch radius, that enemy becomes inspected. The touch radius is `max(enemy.radius * 1.8, 24)` pixels so small sprites remain tappable on mobile. Tapping another enemy switches inspection. Tapping away from enemies clears inspection and then continues existing board/tower tap behavior where appropriate.

Inspection clears automatically when:

- The inspected enemy is killed.
- The inspected enemy reaches the base.
- Combat components are cleared on restart, loss cleanup, or wave reset.
- The inspected enemy is no longer mounted or is resolved.

This keeps the feature touch-first without depending on hover behavior.

## Display State

Add `lib/game/components/enemy_overlay.dart` for enemy overlay display state and rendering. The helper derives render decisions from `EnemyComponent` state plus an `isInspected` flag.

The helper should expose:

- `shouldRender`
- `isExpanded`
- `healthRatio`
- `shieldRatio`
- `showHealthBar`
- `showShieldBar`
- ordered badge descriptors

Ratios clamp to `0..1`. The helper suppresses all display for resolved enemies. Shield display uses max shield capacity and current shield so a shielded enemy can show shield state separately from health while the shield exists or has been depleted.

Badge priority is:

1. Corroded
2. Slowed
3. Shielded
4. Armored
5. Regen
6. Heavy
7. Swarm

Normal overlays cap badges at two highest-signal items. Expanded overlays cap badges at four highest-signal items.

## Rendering

Keep enemy body rendering in `EnemyComponent.render()` and delegate overlay drawing to a helper so `EnemyComponent` does not become a large rendering utility.

`EnemyComponent` should receive an optional `GameTowerVarietySheet` at spawn time, similar to towers and projectiles. The overlay renderer uses:

- Health bar: compact filled strip above or near the enemy.
- Shield bar: separate thinner strip or stacked strip, visible only when shield state is relevant.
- Sprites where available:
  - Shielded: `shieldIndicator`
  - Armored: `armorIndicator`
  - Regen: `regenIndicator`
  - Corroded: `corrosionIndicator`
- Drawn fallback badges for slowed, heavy, swarm, and any missing sprite asset.

The renderer should use stable dimensions relative to enemy radius so overlays scale with current board layout. It should avoid text labels during waves. Icon and shape badges are preferred because the game is portrait and touch-first.

## Architecture

Keep the pure game layer unchanged.

Expected files:

- `lib/game/components/enemy_component.dart`
  - Expose overlay input state.
  - Delegate overlay rendering.
  - Track whether the component is inspected.
  - Keep movement, damage, shield, slow, corrosion, regen, and resolution behavior unchanged.
- New component helper file under `lib/game/components/`
  - Derive `EnemyOverlayState`.
  - Render health bars, shield bars, and badges.
  - Provide deterministic badge ordering and capping.
- `lib/game/orion_defense_game.dart`
  - Pass `_towerVarietySheet` to spawned enemies.
  - Own and update `_inspectedEnemyId`.
  - Hit-test enemies before board cells during active waves.
  - Clear inspection when the selected enemy resolves or combat is cleared.
- `test/game/enemy_component_test.dart` or a focused overlay test file
  - Cover display-state helpers and relevant component state.
- `test/game/orion_defense_game_test.dart`
  - Cover enemy inspection through a test-visible game helper or direct tap simulation.

No changes are expected in `GameSession`, `CombatEffects`, `GameBalance`, stage definitions, or campaign persistence.

## Edge Cases

- Resolved or removed enemies render no overlay.
- Health and shield ratios are clamped even if damage, regen, or shield math changes later.
- Shielded enemies show shield state separately from health.
- Regen remains a trait badge even while corrosion pauses regeneration; corrosion appears first while active.
- Slowed appears only while the slow state is active.
- Swarm-only enemies stay visually light.
- Missing indicator sprites do not break rendering; drawn fallbacks are acceptable.
- Paused waves keep the last rendered overlay state without advancing timers, matching the existing pause model.

## Testing Strategy

Unit tests should cover display-state logic:

- Full health with no notable traits does not render a normal overlay.
- Damaged enemies expose a clamped health ratio.
- Shielded enemies expose shield ratio separately from health.
- Resolved enemies suppress overlays.
- Inspected enemies expand even when they would not otherwise be notable.
- Badge ordering follows corrosion, slow, shielded, armored, regen, heavy, swarm.
- Normal overlays cap badges to the highest-signal entries.
- Corroded regen enemies include both corrosion and regen in the expected order.
- Swarm-only enemies are not automatically notable.

Game/component tests should cover:

- Tapping an active enemy marks it inspected.
- Tapping another active enemy switches inspection.
- Resolving the inspected enemy clears inspection.

Verification commands:

```bash
dart format .
flutter analyze
flutter test
```

## Acceptance Criteria

- Enemies can show current health during waves without global clutter.
- Shielded enemies show shield state separately from health.
- Armored, shielded, regen, swarm, and heavy enemies are visually distinguishable through compact badges when inspected, and high-signal traits appear automatically when notable.
- Slowed and corroded effects are visible while active.
- Indicators do not render after an enemy is resolved or removed.
- Swarm waves remain legible.
- Tests cover display-state helpers and practical inspection behavior.
- Existing tower placement, targeting, combat, pacing, wave completion, and campaign flows remain unchanged.
