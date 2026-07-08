# Orion Per-Tower Targeting Modes Design

## Context

HPA-96 lets players choose a targeting mode for each placed tower instead of always targeting the enemy furthest along the path. Orion is a Flutter + Flame tower-defense game with a deliberate split between pure mission rules (`lib/game/rules/`, `lib/game/models/`) and the Flame rendering layer (`lib/game/components/`, `lib/game/orion_defense_game.dart`). Mission state flows from `GameSession` through immutable `GameSnapshot`s into `OrionGamePage`; the UI reads only snapshots.

Today `TowerTargeting.selectTarget` (`lib/game/rules/tower_targeting.dart`) is a pure function that filters alive, in-range `TargetCandidate`s and picks the one with the highest `pathProgress`. `OrionDefenseGame._selectTargetForTower` calls it with each tower's position and range, then maps the chosen `TargetCandidate.id` back to an `EnemyComponent`. `TargetCandidate` currently carries only `id`, `x`, `y`, `pathProgress`, `isAlive`. `PlacedTower` is an immutable value type with `id`, `type`, `position`, `level`, `specialization`; `upgraded()` and `specialized()` produce copies.

## Goal

Let each placed tower carry a selectable targeting mode that changes how it picks targets during waves. Players choose the mode from the selected-tower panel during build phase; the choice persists for the tower across upgrades and specializations and feeds the existing pure targeting rule.

Initial modes:

- **First** — highest path progress (current behavior, the default).
- **Strongest** — highest effective HP (current health + current shield).
- **Weakest** — lowest effective HP.
- **Closest** — nearest to the tower.
- **Shielded** — prefer shielded enemies; fall back to First.
- **Armored** — prefer armored enemies; fall back to First.

## Scope

In scope:

- A `TowerTargetingMode` enum and a `targetingMode` field on `PlacedTower` (default `first`), preserved by upgrade and specialization.
- Extending `TargetCandidate` with the live data the new modes need (current health, current shield, shielded/armored trait flags), populated by `EnemyComponent.targetCandidate`.
- A `mode` parameter on `TowerTargeting.selectTarget` with per-mode ranking, deterministic tie-breaks, and graceful fallback.
- `GameSession.setTargetingMode` + `OrionDefenseGame.setTargetingMode` mirroring the existing upgrade/specialize wiring.
- A build-phase choice-chip picker in the selected-tower panel.
- Pure-rule and session tests covering every mode, tie-breaks, the trait-mode fallback, and preservation across upgrade/specialize.

Out of scope (non-goals from the issue):

- Per-stage automated targeting presets.
- Tower or enemy stat rebalance.
- Changes to `combat_effects.dart` chain/pierce target selection (proximity-based, mode-independent).
- A broader HUD or bottom-control redesign.

## Data Model

### `lib/game/models/game_models.dart`

Add an enhanced enum mirroring the `TowerSpecialization` pattern:

```dart
enum TowerTargetingMode {
  first('First'),
  strongest('Strongest'),
  weakest('Weakest'),
  closest('Closest'),
  shielded('Shielded'),
  armored('Armored');

  const TowerTargetingMode(this.label);
  final String label;
}
```

`PlacedTower` gains a field, defaulting to the current behavior so new placements are unaffected:

- `final TowerTargetingMode targetingMode;` (constructor default `TowerTargetingMode.first`).
- `upgraded()` and `specialized(...)` pass `targetingMode: targetingMode` through, so leveling and specialization preserve the player's choice.
- A new `PlacedTower copyWith({TowerTargetingMode? targetingMode})` produces the mode-change copy used by `GameSession.setTargetingMode`.

### `lib/game/rules/tower_targeting.dart`

`TargetCandidate` gains four fields, all **defaulted** so existing call sites in `combat_effects_test.dart` and `tower_targeting_test.dart` compile unchanged:

```dart
this.currentHealth = 0,
this.currentShield = 0,
this.isShielded = false,
this.isArmored = false,
```

Plus a convenience getter:

```dart
double get effectiveHealth => currentHealth + currentShield;
```

`EnemyComponent.targetCandidate` (`lib/game/components/enemy_component.dart`) populates these from its live state: `currentHealth: health`, `currentShield: shield`, `isShielded: stats.traits.contains(EnemyTrait.shielded)`, `isArmored: stats.traits.contains(EnemyTrait.armored)`.

## Targeting Algorithm

`TowerTargeting.selectTarget` gains `TowerTargetingMode mode = TowerTargetingMode.first` and keeps the same return type (`TargetCandidate?`). It runs in two phases:

1. **Filter** — drop dead candidates and those outside `range` (existing behavior, unchanged).
2. **Rank** the surviving candidates by mode.

For `shielded` and `armored`, first restrict to candidates where `isShielded` / `isArmored` is true. If that subset is non-empty, rank only the subset by path progress; if the subset is empty, fall back to ranking the full in-range set by path progress (i.e. behave as `first`). This keeps DPS up when the preferred trait is momentarily absent.

Ranking keys and tie-breaks:

| Mode | Primary key | Tie-break 1 | Tie-break 2 |
|------|-------------|-------------|-------------|
| first | pathProgress desc | id asc | — |
| strongest | effectiveHealth desc | pathProgress desc | id asc |
| weakest | effectiveHealth asc | pathProgress desc | id asc |
| closest | distance² to tower asc | pathProgress desc | id asc |
| shielded | (trait subset) pathProgress desc | id asc | — |
| armored | (trait subset) pathProgress desc | id asc | — |

The `id` final tie-break makes selections deterministic for tests. When no alive candidate is in range, `selectTarget` returns `null`, preserving today's graceful fallback.

## Session and Game Wiring

### `lib/game/rules/game_session.dart`

Add `bool setTargetingMode(int towerId, TowerTargetingMode mode)`, mirroring `upgradeTower`:

- Return `false` if `phase != GamePhase.build`.
- Return `false` if the tower is not found.
- Otherwise replace the tower via `tower.copyWith(targetingMode: mode)` and return `true`.

Mode changes are free (no gold cost).

### `lib/game/orion_defense_game.dart`

- `void setTargetingMode(TowerTargetingMode mode)` mirrors `specializeSelectedTower`: reads `_selectedTower`, calls `_session.setTargetingMode`, on success refreshes `_selectedTower` from the session and calls `_towerComponents[id]?.updateTower(...)` so the component carries the new mode, then `_publishSnapshot()`. On failure it publishes a feedback message.
- `_selectTargetForTower` reads `tower.placedTower.targetingMode` and passes it as the `mode` argument to `TowerTargeting.selectTarget`. The component already exposes its current `PlacedTower` and is refreshed via the existing `updateTower` path used by upgrade/specialize, so no new component plumbing is required.

`GameSnapshot` is unchanged: the UI reads `selectedTower.targetingMode`, which is already reachable through the snapshot.

## UI

`lib/game/ui/orion_game_page.dart` gains a `_TargetingModePicker` widget rendered inside `_UpgradePanel`, as a `Wrap` of six `ChoiceChip`s placed beneath `_TowerSummary`:

- Chip labels come from `TowerTargetingMode.label`.
- Selected chip = `tower.targetingMode`.
- `onSelected` calls `game.setTargetingMode(mode)`.
- Chips are enabled only when `snapshot.phase == GamePhase.build`. During waves they render disabled and show the current mode (read-only), matching the build-phase-only change rule.
- The existing upgrade/specialize actions row and the panel's responsive `LayoutBuilder` layout are otherwise unchanged; the panel grows slightly taller to fit the chip row.

## Tests

- **`test/game/tower_targeting_test.dart`** — a group per mode with representative candidates mixing health, shield, traits, distance, and path progress. Each group asserts the selected id, the deterministic tie-break, and the `shielded`/`armored` fallback-to-`first` case when no preferred-trait enemy is in range.
- **`test/game/game_session_test.dart`** — `setTargetingMode` updates the tower's mode; returns `false` during `GamePhase.wave`; the selected mode survives a subsequent `upgradeTower` and a subsequent `specializeTower`; newly placed towers default to `TowerTargetingMode.first`.
- **`test/game/combat_effects_test.dart`** — expected to compile and pass unchanged because the new `TargetCandidate` fields are defaulted; it is run as part of verification rather than edited.
- **`test/game/game_balance_test.dart`** — unaffected; no tuning constants change.

## Acceptance Criteria Mapping

- Towers default to the current targeting behavior — `PlacedTower.targetingMode` defaults to `first`; new placements inherit it.
- Players can change targeting mode from the selected tower panel during build phase — `_TargetingModePicker` choice chips call `game.setTargetingMode`, build-phase gated.
- Targeting mode affects target acquisition during active waves — `_selectTargetForTower` passes the tower's mode into `selectTarget`.
- Invalid or unavailable targets fall back gracefully — no in-range candidate returns `null`; trait modes fall back to `first` when their subset is empty.
- Tower upgrades and specializations preserve the selected targeting mode — `upgraded()` / `specialized()` carry `targetingMode` through; covered by session tests.
- Tests cover each targeting mode with representative target candidates — `tower_targeting_test.dart` per-mode groups.
