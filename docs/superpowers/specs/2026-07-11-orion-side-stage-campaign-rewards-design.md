# Orion Side-Stage Campaign Rewards Design

## Context

Orion has a local world-map campaign with seven stages: five main-path stages and two optional side stages (Salvage Rift and Void Bastion). Campaign progress records best results per stage and derives unlocks. Side stages currently have no reward beyond being marked cleared — there is no strategic reason for a player to complete them.

HPA-94 makes side stages grant persistent campaign rewards so clearing them feels valuable. The existing architecture stays intact: pure campaign and mission rules live under `lib/game/campaign/`, `lib/game/rules/`, and `lib/game/models/`; `OrionDefenseGame` runs a selected stage; `OrionGamePage` is the campaign shell; `WorldMapView` renders stage state.

## Goal

When a side stage is cleared, unlock a campaign-wide modifier that applies to all future missions. Three rewards:

- **Salvage Rift** cleared: start each mission with +30 bonus gold.
- **Void Bastion** cleared: start each mission with +5 bonus base health.
- **Both side stages** cleared: earn a challenge badge displayed on the world map.

Rewards apply to every mission the player starts after unlocking, including replaying the side stages themselves. Rewards persist across app restarts because they derive from existing clear status.

## Scope

This ticket implements exactly the three rewards above. The first two are gameplay stat modifiers; the third is a visual challenge badge with no gameplay effect.

## Out of Scope

- A full campaign tech tree (tracked in HPA-100, which this ticket blocks).
- New side stages.
- Cosmetic tower variants or tower skins requiring new sprite art.
- Wave, enemy, tower, or economy rebalancing.
- Migration of old save data (the app has not launched; version 2 saves remain valid as-is).

## Data Model

### `CampaignReward` enum

New enum in `lib/game/campaign/campaign_progress.dart`:

```dart
enum CampaignReward {
  bonusGold,
  bonusHealth,
  challengeBadge,
}
```

Each side stage carries one reward type on its `StageDefinition`. Main stages have no reward (`null`). The challenge badge is a compound reward derived from clearing both side stages; it is not assigned to a single stage.

### `GameBalance` constants

Add two tuning constants to `GameBalance` in `lib/game/models/game_models.dart`:

```dart
static const int salvageRiftGoldBonus = 30;
static const int voidBastionHealthBonus = 5;
```

These follow the existing pattern where all economy tuning lives in `GameBalance`.

### `StageDefinition` change

Add an optional field to `StageDefinition` in `lib/game/campaign/stage_definition.dart`:

```dart
final CampaignReward? reward;
```

Defaults to `null`. Set on side stages only:

- `salvage-rift` -> `CampaignReward.bonusGold`
- `void-bastion` -> `CampaignReward.bonusHealth`

### `CampaignModifiers` value object

New pure class in `lib/game/campaign/campaign_progress.dart`:

```dart
class CampaignModifiers {
  const CampaignModifiers({
    this.bonusGold = 0,
    this.bonusHealth = 0,
    this.hasChallengeBadge = false,
  });

  final int bonusGold;
  final int bonusHealth;
  final bool hasChallengeBadge;

  int get adjustedStartingGold => GameBalance.startingGold + bonusGold;
  int get adjustedStartingBaseHealth => GameBalance.initialBaseHealth + bonusHealth;

  static const CampaignModifiers empty = CampaignModifiers();

  static CampaignModifiers fromProgress(
    CampaignProgress progress,
    Iterable<StageDefinition> stages,
  );
}
```

`fromProgress` iterates the provided stages and accumulates effects:

1. For each cleared stage with a `bonusGold` reward, add `GameBalance.salvageRiftGoldBonus`.
2. For each cleared stage with a `bonusHealth` reward, add `GameBalance.voidBastionHealthBonus`.
3. Set `hasChallengeBadge` to `true` when every side stage (every stage where `isMainPath == false`) is cleared.

This is pure and testable without any Flame dependency.

## Applying Rewards at Mission Start

### Flow

1. `OrionGamePage._startStage` already has access to `_progress`. It computes modifiers:
   ```dart
   final modifiers = CampaignModifiers.fromProgress(_progress, OrionCampaign.stages);
   ```
2. `OrionDefenseGame` constructor gains an optional `CampaignModifiers? modifiers` parameter (defaults to `null`). When non-null, it passes the adjusted starting values to the session:
   ```dart
   _session = GameSession.initial(
     stage: stage ?? OrionCampaign.stageOne,
     gold: modifiers?.adjustedStartingGold,
     baseHealth: modifiers?.adjustedStartingBaseHealth,
   )
   ```
3. `GameSession.initial` already accepts optional `gold` and `baseHealth` overrides and defaults to `GameBalance.startingGold` / `GameBalance.initialBaseHealth` when omitted. No signature change needed.

When `modifiers` is `null` (the default), behavior is identical to today. This keeps existing tests and callers unchanged.

### Medal calculation with bonus health

The current `StageResult.fromVictoryBaseHealth` clamps `bestBaseHealth` to `GameBalance.initialBaseHealth` (20). With a +5 health bonus, a session may start at 25. Medal calculation must know the starting health to determine whether the player took damage.

Changes:

- `GameSession` stores a `final int startingBaseHealth` field, set to the effective starting health (the `_baseHealth` value after the constructor initializer). This field records the health ceiling for the session, including any campaign bonus.
- `StageResult.fromVictoryBaseHealth` gains a required `startingBaseHealth` parameter:
  ```dart
  factory StageResult.fromVictoryBaseHealth(
    int baseHealth, {
    required int startingBaseHealth,
  })
  ```
  - Gold when `baseHealth >= startingBaseHealth` (took zero damage).
  - Silver when `baseHealth >= GameBalance.silverMedalThreshold` (absolute threshold, unchanged at 10).
  - Clear otherwise.
  - `bestBaseHealth` stores `baseHealth.clamp(0, startingBaseHealth)`.
- `OrionDefenseGame` passes `session.startingBaseHealth` when constructing the `StageResult` for `StageCompletion`.

### Backward compatibility of medal change

All callers of `StageResult.fromVictoryBaseHealth` must supply `startingBaseHealth`. The only production caller is `OrionDefenseGame`, which has access to the session. Tests that construct results directly will pass `GameBalance.initialBaseHealth` (the default 20) for non-bonus scenarios, preserving existing behavior.

### What stays unchanged

- `GameSession.initial` constructor signature (already accepts overrides).
- Main-path unlock behavior (unlocks still derive from `isCleared`).
- Losing a stage does not change campaign progress.
- The `StageCompletion` payload shape and the save flow in `OrionGamePage`.

## World Map Display

### Side-stage reward labels

Each `_StageNode` in `WorldMapView` gains a compact reward line for stages that have a non-null `reward`. The node already receives `stage`, `status`, and `result`, which is enough to render the label without new parameters.

Label format (amounts resolved from `GameBalance`, not hardcoded):

| Reward type | Cleared (earned) | Not cleared (teaser) |
|---|---|---|
| `bonusGold` | `+30 Gold` | `Reward: +30 Gold` |
| `bonusHealth` | `+5 HP` | `Reward: +5 HP` |

The line appears below the existing status label, using `theme.textTheme.labelSmall`. It is omitted for main stages (no reward) and does not change the compact node dimensions.

### Challenge badge

`WorldMapView` gains an optional `CampaignModifiers? modifiers` parameter. When `modifiers?.hasChallengeBadge == true`, a dedicated summary line appears below the campaign-complete banner (or below the header if the campaign is not yet complete):

```
Challenge Badge Earned - All side stages cleared
```

This is purely visual recognition with no gameplay effect.

### Display inputs

`OrionGamePage` passes `CampaignModifiers.fromProgress(_progress, OrionCampaign.stages)` to `WorldMapView` via the `modifiers` parameter. The reward labels on side nodes are derived from `stage.reward` and `progress.isCleared(stage.id)` directly, needing no extra data.

## Persistence

**No new save data.** Rewards derive entirely from existing `CampaignProgress.bestResultsByStageId`. If Salvage Rift is cleared, its gold bonus is active. The codec, store interfaces, and JSON shape (version 2) are unchanged. Rewards automatically persist across app restarts because clear status already persists.

The `bestBaseHealth` field in saved `StageResult`s may now store values up to `GameBalance.initialBaseHealth + GameBalance.voidBastionHealthBonus` (25) for sessions played with the health bonus. Old saves (max 20) remain valid:

- The codec trusts stored medal and base-health values and does not re-derive them.
- The existing `< 0` corruption guard still applies.
- Values above 20 in old saves are impossible, so no clamping change is needed for decode.

## Validation

Extend `OrionCampaign.validateStages` to verify reward assignments:

- Side stages (`isMainPath == false`) must have a non-null `reward`.
- Main stages (`isMainPath == true`) must have a null `reward`.
- `bonusGold` and `bonusHealth` rewards should each appear on at most one stage.
- `challengeBadge` should not be assigned to any individual stage (it is compound-derived).

These are development-time guards caught by tests, not runtime errors.

## Error Handling

- `CampaignModifiers.fromProgress` with empty progress returns all-zero defaults (`CampaignModifiers.empty`) - safe for new players.
- `OrionDefenseGame` with `null` modifiers behaves exactly as before (no bonus).
- A stage with a reward that is never cleared never activates its reward - no special handling needed.
- Invalid persisted progress is still discarded safely by the existing codec.
- A save failure after victory still leaves previous progress in place and shows the existing save-failure feedback.

## Testing Strategy

### Pure logic tests

`CampaignModifiers`:

- `fromProgress` with no clears returns all-zero defaults.
- `fromProgress` with only Salvage Rift cleared returns `bonusGold == 30`, `bonusHealth == 0`, `hasChallengeBadge == false`.
- `fromProgress` with only Void Bastion cleared returns `bonusHealth == 5`, `bonusGold == 0`, `hasChallengeBadge == false`.
- `fromProgress` with both side stages cleared returns `bonusGold == 30`, `bonusHealth == 5`, `hasChallengeBadge == true`.
- `adjustedStartingGold` and `adjustedStartingBaseHealth` compute correct totals.

`StageResult` medal calculation:

- `fromVictoryBaseHealth(baseHealth: 25, startingBaseHealth: 25)` -> Gold (no damage with bonus).
- `fromVictoryBaseHealth(baseHealth: 23, startingBaseHealth: 25)` -> Silver (took damage, but 10+ remaining).
- `fromVictoryBaseHealth(baseHealth: 20, startingBaseHealth: 20)` -> Gold (no damage, no bonus - regression).
- `fromVictoryBaseHealth(baseHealth: 9, startingBaseHealth: 25)` -> Clear (below silver threshold).

`GameSession`:

- `startingBaseHealth` reflects bonus when `baseHealth` override is provided.
- `startingBaseHealth` equals `GameBalance.initialBaseHealth` when no override.

`OrionCampaign.validate`:

- Valid reward assignments (side stages have rewards, main stages don't) pass.
- Invalid assignments (main stage with reward, side stage without) fail.

### Game and widget tests

- `OrionDefenseGame` with `CampaignModifiers(bonusGold: 30, bonusHealth: 5)` starts session with 180 gold and 25 base health.
- `OrionDefenseGame` with `null` modifiers starts with defaults (regression).
- Victory with bonus health produces the correct medal via `startingBaseHealth`.
- World map shows reward label on uncleared side stages (teaser format).
- World map shows reward label on cleared side stages (earned format).
- World map shows challenge badge summary when both side stages cleared.
- Existing tests pass unchanged when modifiers default to none. Callers of `StageResult.fromVictoryBaseHealth` in tests are updated to pass `startingBaseHealth`.

## Acceptance Criteria

- `StageDefinition` can describe an optional `CampaignReward`.
- `CampaignProgress` can determine which side-stage rewards are active via `CampaignModifiers.fromProgress`.
- Starting a mission applies active campaign modifiers consistently (adjusted gold and base health).
- The world map shows reward information for side stages (earned/teaser labels and challenge badge).
- Rewards persist across app restarts (derived from existing clear status, no new save data).
- Main-path unlock behavior remains unchanged.
- Medal calculation remains damage-based: Gold at zero damage, Silver at 10+ remaining, Clear below.
- `OrionCampaign.validate()` guards reward assignments on stage definitions.
- Tests cover reward activation, persistence, mission-start modifiers, medal calculation with bonus health, and world map display.
