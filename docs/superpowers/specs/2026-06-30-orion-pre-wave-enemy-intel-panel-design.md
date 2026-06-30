# Orion Pre-Wave Enemy Intel Panel Design

## Context

HPA-92 adds a build-phase intel panel to Orion missions. Orion is a Flutter and Flame tower-defense game with a deliberate split between pure mission rules and the Flame rendering layer. Mission state flows from `GameSession` through immutable `GameSnapshot`s into `OrionGamePage`, and the UI should keep using snapshots instead of reading game internals directly.

The current campaign system lets each `StageDefinition` provide its own eight-wave list. The first stage uses `GameBalance.waves`, which includes multi-group mixed waves. Other campaign stages currently use single-group waves produced from enemy archetypes. The intel panel must derive from the selected stage's active wave so both shapes are represented correctly.

## Goal

Let players preview the next wave during build phase before pressing `Start Wave`, so tower placement, upgrades, and specializations can respond to upcoming enemy composition instead of relying on guesswork.

The panel should expose:

- Upcoming wave number and total wave count.
- All enemy groups in the upcoming wave.
- All distinct incoming traits.
- Clear bonus when the bonus is greater than zero.
- Compact recommended counters filtered to towers already unlocked for the current wave.

## Scope

In scope:

- Build-phase-only next-wave preview data.
- A compact panel under the existing HUD.
- Enemy group labels, distinct trait labels, positive clear bonus display, and unlocked-only tower recommendations.
- Snapshot, model, pure rule, and widget tests covering multi-group and single-group waves.

Out of scope:

- Boss waves or named elite enemies.
- Enemy health bars, shield bars, or in-combat trait badges.
- Stage medals, side-stage rewards, or campaign persistence changes.
- Tower or enemy stat rebalance unless a preview test exposes an existing data bug.
- A broader HUD or bottom-control redesign.

## Data Model

Add lightweight preview data to `lib/game/models/game_models.dart`:

- `WavePreview`
  - `waveNumber`
  - `waveTotal`
  - `groups`
  - `traits`
  - `clearBonus`
  - `recommendedTowerTypes`
- `WavePreviewGroup`
  - `enemyCount`
  - `label`
  - `traits`

`GameSnapshot` gains a nullable `nextWavePreview` field.

`GameSession.snapshot()` populates `nextWavePreview` only when:

- `phase == GamePhase.build`
- `activeWave` is not null

It returns `null` during `GamePhase.wave`, `GamePhase.won`, and `GamePhase.lost`. This keeps the UI hiding behavior data-driven and preserves the existing snapshot-only UI contract.

Preview generation must read `stage.waves[_waveIndex]`, not `GameBalance.waves`, so stage-specific missions remain correct.

## Enemy Labels

`WaveGroup` stores `EnemyStats`, not `EnemyArchetype`, so preview labels need an explicit formatter instead of relying on archetype data that is not present in the group.

Known balance stats should map to stable readable labels:

- Basic drone stats: `Drones`
- Basic elite drone stats: `Elite Drones`
- Armored stats: `Armored Drones`
- Shielded stats: `Shielded Drones`
- Swarm stats: `Swarm Drones`
- Regen stats: `Regen Drones`
- Heavy stats: `Heavy Drones`
- Armored heavy stats: `Armored Heavy Drones`
- Regen heavy stats: `Regen Heavy Drones`

Unknown or custom stats should fall back to trait-based labels:

- Multiple traits: combine trait adjectives in stable trait order, then `Drones`, for example `Armored Heavy Drones`.
- One trait: use that trait adjective, for example `Shielded Drones`.
- No traits: use `Drones`.

Trait display order should follow `EnemyTrait.values` so output stays deterministic.

## Counter Recommendations

Recommendations are generated with preview data and filtered to `snapshot.unlockedTowerTypes`.

The v1 rules are deliberately small:

- `shielded` waves recommend `Ion Chain` if unlocked.
- `armored` or `heavy` waves recommend `Rocket` and `Railgun` if unlocked.
- `swarm` waves recommend `Rocket`, `Cryo`, and `Gravity Well` if unlocked.
- `regen` waves recommend `Laser`, `Ion Chain`, and `Nanite` if unlocked.
- Traitless waves recommend no counters.

Recommendations should be distinct, ordered by the first relevant trait encountered in the upcoming wave, then capped to three tower types. This keeps the panel compact and avoids turning it into a full build guide.

The UI should display existing tower labels such as `Rocket`, `Railgun`, and `Ion Chain`. Locked future counters should not appear.

## UI

Add a `_NextWavePanel` widget in `lib/game/ui/orion_game_page.dart`.

The panel renders directly under `_Hud` in the top overlay stack when `snapshot.nextWavePreview != null`. It stays visible while the player selects a build cell or tower, because planning intel is most useful while choosing placements, upgrades, and specializations.

The panel layout:

- Title row: `Next Wave 5/8`.
- Group summary chips or compact text entries, such as `20 Swarm Drones` and `4 Heavy Drones`.
- Trait chips in a `Wrap`, such as `Swarm`, `Heavy`, `Shielded`, `Armored`, and `Regen`.
- Clear bonus chip only when `clearBonus > 0`, such as `Clear bonus 80`.
- Recommendation row only when `recommendedTowerTypes` is not empty, such as `Recommended: Rocket, Cryo`.

The existing bottom controls remain focused on actions: pacing, world map, `Start Wave`, tower picker, upgrade, and specialization. The intel panel should not be placed inside the bottom controls because that would hide it during tower selection.

## Snapshot Copy Paths

`OrionGamePage._showCampaignPersistenceFailure()` manually reconstructs a `GameSnapshot` to add feedback. That copy path must preserve `nextWavePreview` when the new field is added.

Any future manual snapshot copy should carry the field forward or use a helper if the snapshot object grows further.

## Error Handling and Edge Cases

- If there is no active wave, `nextWavePreview` is null.
- During an active wave, the preview is hidden.
- On final-wave build phase, a zero clear bonus is omitted instead of showing awkward `Clear bonus 0` text.
- Empty-wave test stages produce a preview with no groups, no traits, no recommendations, and no bonus text.
- Unknown custom enemy stats still produce readable fallback group labels.
- Recommendations are omitted when all relevant counters are still locked.

## Testing Strategy

Pure Dart tests:

- Initial `GameSession.snapshot()` exposes preview wave number `1` and wave total `8`.
- A multi-group baseline wave includes every group, not only the first group.
- A single-group campaign-stage wave exposes the correct group and wave total.
- Distinct traits are aggregated once in stable order.
- Known enemy stats produce stable readable group labels.
- Unknown/custom enemy stats use trait-based fallback labels.
- Recommendations are filtered to unlocked tower types.
- Active wave snapshots hide `nextWavePreview`.
- Final-wave zero clear bonus remains represented in data but is omitted by the widget.

Widget tests:

- Starting an unlocked stage from the world map displays `Next Wave 1/8`.
- The panel remains visible while a build cell or tower is selected.
- Pressing `Start Wave` hides the panel during active combat.
- A final-wave or zero-bonus preview does not render `Clear bonus 0`.

Verification commands:

```bash
dart format .
flutter analyze
flutter test
```

## Acceptance Criteria

- In build phase, the player can see the upcoming wave before pressing `Start Wave`.
- The panel correctly summarizes all `WaveGroup`s in the active stage wave.
- The summary includes enemy count and a readable enemy label.
- The summary includes all distinct traits represented in the wave.
- The panel shows clear bonus only when the bonus is greater than zero.
- The panel does not appear during an active wave, win state, or loss state.
- The panel handles final waves with `clearBonus == 0` without awkward text.
- Recommended counters appear only when the relevant tower type is already unlocked.
- Existing tower selection, build, upgrade, specialization, pacing, and start-wave flows still work.
- Focused tests cover at least one multi-group baseline wave and one single-group campaign-stage wave.
