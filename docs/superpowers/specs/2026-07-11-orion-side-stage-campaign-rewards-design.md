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

New enum in `lib/game/campaign/stage_definition.dart` (not `campaign_progress.dart`, which would create a circular import since `campaign_progress.dart` already imports `stage_definition.dart`):

```dart
enum CampaignReward {
  bonusGold,
  bonusHealth,
  challengeBadge,
}
```

Each side stage carries one reward type on its `StageDefinition`. Main stages have no reward (`null`). The challenge badge is a compound reward derived from clearing both side stages; it is not assigned to a single stage. `campaign_progress.dart` gets `CampaignReward` transitively through its existing `stage_definition.dart` import.

### `GameBalance` constants

Add two tuning constants to `GameBalance` in `lib/game/models/game_models.dart`:

```dart
static const int salvageRiftGoldBonus = 30;
static const int voidBastionHealthBonus = 5;
```

These follow the existing pattern where all economy tuning lives in `GameBalance`.

### `StageDefinition` change

`StageDefinition` in `lib/game/campaign/stage_definition.dart` gains the `CampaignReward` enum (defined above) and an optional field:

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
2. `OrionDefenseGame` constructor gains an optional `CampaignModifiers? modifiers` parameter (defaults to `null`). The `_session` field is `final`, so it must be initialized in the initializer list, not the constructor body:
   ```dart
   OrionDefenseGame({
     StageDefinition? stage,
     this.modifiers,
     this.onStageWon,
     this.onReturnToMap,
   }) : stage = stage ?? OrionCampaign.stageOne,
        _session = GameSession.initial(
          stage: stage ?? OrionCampaign.stageOne,
          gold: modifiers?.adjustedStartingGold,
          baseHealth: modifiers?.adjustedStartingBaseHealth,
        ) {
     _resetPacing();
   }

   final CampaignModifiers? modifiers;
   ```
3. `GameSession.initial` already accepts optional `gold` and `baseHealth` overrides and defaults to `GameBalance.startingGold` / `GameBalance.initialBaseHealth` when omitted. No signature change needed.

When `modifiers` is `null` (the default), behavior is identical to today. This keeps existing tests and callers unchanged.

### Effective starting values on GameSession

`GameSession` must store the effective starting gold and health (including any campaign bonus) as fields, not just the base-health ceiling. Both are needed:

```dart
final int startingGold;
final int startingBaseHealth;
```

These are set in the `GameSession.initial` constructor to the resolved values (the override if provided, otherwise the `GameBalance` default):

```dart
GameSession.initial({StageDefinition? stage, int? gold, int? baseHealth})
  : stage = stage ?? OrionCampaign.stageOne,
    startingGold = gold ?? GameBalance.startingGold,
    startingBaseHealth = baseHealth ?? GameBalance.initialBaseHealth,
    _gold = gold ?? GameBalance.startingGold,
    _baseHealth = baseHealth ?? GameBalance.initialBaseHealth { ... }
```

### Clamps and restart

Two existing code paths hardcode `GameBalance` defaults and must use the session's effective starting values instead:

1. **`damageBase`** (`game_session.dart:245-247`) currently clamps to `GameBalance.initialBaseHealth` (20). With a +5 health bonus, a session starts at 25; the first enemy hit of even 1 damage would clamp from 24 down to 20, instantly destroying the bonus. The clamp must use `startingBaseHealth`:
   ```dart
   _baseHealth = (_baseHealth - amount).clamp(0, startingBaseHealth).toInt();
   ```

2. **`restart()`** (`game_session.dart:255-262`) currently resets to hardcoded `GameBalance.startingGold` and `GameBalance.initialBaseHealth`. A restart during a bonus session would silently drop both bonuses and make a Gold medal unreachable (the player restarts at 20 but `startingBaseHealth` says 25). It must reset to the stored starting values:
   ```dart
   void restart() {
     _towersByPosition.clear();
     _nextTowerId = 1;
     _gold = startingGold;
     _baseHealth = startingBaseHealth;
     _waveIndex = 0;
     _phase = GamePhase.build;
   }
   ```

### Medal calculation with bonus health

The current `StageResult.fromVictoryBaseHealth` clamps `bestBaseHealth` to `GameBalance.initialBaseHealth` (20). With a +5 health bonus, a session may start at 25. Medal calculation must know the starting health to determine whether the player took damage.

Changes:

- `GameSession` stores `final int startingBaseHealth` (see "Effective starting values" above).
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

### Callers of `fromVictoryBaseHealth`

There are **two** production callers, both of which must supply `startingBaseHealth`:

1. **`OrionDefenseGame._onPhaseChange`** (`orion_defense_game.dart:697`) — builds the `StageCompletion` result. It has access to `_session.startingBaseHealth`:
   ```dart
   result: StageResult.fromVictoryBaseHealth(
     _session.baseHealth,
     startingBaseHealth: _session.startingBaseHealth,
   ),
   ```

2. **`_EndStatePanel.build`** (`orion_game_page.dart:942`) — the victory screen. It currently calls `StageResult.fromVictoryBaseHealth(snapshot.baseHealth)` and displays `Base ${result.bestBaseHealth}/${GameBalance.initialBaseHealth}` (a hardcoded `/20`). With the new required parameter this won't compile, and the `/20` denominator is wrong with a bonus.

   The UI follows the pattern "never reads game state directly — only via the snapshot." So `GameSnapshot` must carry `startingBaseHealth`. Add it as a required field:
   ```dart
   final int startingBaseHealth;
   ```
   `GameSession.snapshot()` includes it, and `_EndStatePanel` uses it:
   ```dart
   final result = didWin
       ? StageResult.fromVictoryBaseHealth(
           snapshot.baseHealth,
           startingBaseHealth: snapshot.startingBaseHealth,
         )
       : null;
   ```
   The victory display denominator changes from `${GameBalance.initialBaseHealth}` to `${snapshot.startingBaseHealth}` so it shows `Base 25/25` (not `Base 25/20`).

### Backward compatibility of medal and snapshot changes

All callers of `StageResult.fromVictoryBaseHealth` must supply `startingBaseHealth`. Tests that construct results directly will pass `GameBalance.initialBaseHealth` (the default 20) for non-bonus scenarios, preserving existing behavior.

`GameSnapshot` gains a new required field (`startingBaseHealth`). All snapshot construction sites (`GameSession.snapshot()` and any test helpers) must be updated. For non-bonus sessions the value is always `GameBalance.initialBaseHealth`.

### What stays unchanged

- `GameSession.initial` constructor signature (already accepts overrides).
- Main-path unlock behavior (unlocks still derive from `isCleared`).
- Losing a stage does not change campaign progress.
- The `StageCompletion` payload shape.

## Activation Boundary

Rewards are computed from in-memory `CampaignProgress` at two moments: when `_startStage` creates a new `OrionDefenseGame`, and nowhere else. Two edge cases need explicit rules.

### Restart replays with original modifiers

The victory panel's Restart button calls `game.restart()`, which calls `_session.restart()`. This resets the session to its `startingGold` / `startingBaseHealth` — the values locked at session creation. It does **not** re-evaluate campaign modifiers.

This is by design: Restart means "replay this exact mission setup," not "start a fresh mission with current campaign state." If a player clears Salvage Rift for the first time and immediately hits Restart, the replay still starts with 150 gold because the session predates the clear. The player must return to the world map and launch a new mission to benefit from the newly earned reward.

This avoids a surprising difficulty change mid-victory-screen and keeps `OrionDefenseGame` free of a dependency on live campaign progress.

### Optimistic in-memory progress update

`_saveStageCompletion` currently updates `_progress` via `setState` only after `await store.save(progress)` succeeds (`orion_game_page.dart:234`). Between victory and save completion, the player can return to the map and `_startStage` will derive modifiers from stale `_progress` — missing a reward that finishes saving moments later. This same race affects stage unlock visibility today.

Fix: update `_progress` optimistically **before** awaiting the store save, and roll back on failure:

```dart
final priorProgress = _progress;
setState(() {
  _progress = progress;
});

try {
  await store.save(progress);
} catch (_) {
  if (!mounted || saveGeneration != _progressGeneration) {
    return;
  }
  setState(() {
    _progress = priorProgress;
  });
  _showCampaignPersistenceFailure();
  return;
}
```

The rollback restores the exact prior `_progress` instance. On success, no further `setState` is needed — the optimistic update already applied. The generation guard still prevents stale saves from overwriting a reset.

This is a targeted change to the save flow, not a redesign. It also fixes the pre-existing unlock-visibility race for the same reason.

## World Map Display

### Side-stage reward labels

Each `_StageNode` in `WorldMapView` gains a compact reward line for stages that have a non-null `reward`. The node already receives `stage`, `status`, and `result`, which is enough to render the label without new parameters.

Label format (amounts resolved from `GameBalance`, not hardcoded):

| Reward type | Cleared (earned) | Not cleared (teaser) |
|---|---|---|
| `bonusGold` | `+30 Gold` | `Reward: +30 Gold` |
| `bonusHealth` | `+5 HP` | `Reward: +5 HP` |

The line appears below the existing status label, using `theme.textTheme.labelSmall`. It is omitted for main stages (no reward). The current `_StageNode` is a fixed 92px tall `Positioned` box with centered content (icon + label + status); adding a fourth text line (~15px) is tight against the available content area (~74px after vertical padding). The implementer should verify the reward line fits without clipping, or bump `nodeHeight` from 92 to ~104 if needed.

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

**Cross-bonus replay comparison:** `StageResult.isBetterThan` compares medal rank first, then `bestBaseHealth`. A Gold medal earned at 25 HP (with bonus) ranks higher than a prior Gold at 20 HP (no bonus), so the stored "best" can reflect the bonus rather than raw play. This is a deliberate consequence of the "trust stored values" model — the health bonus is a permanent reward, and its effect on recorded bests is part of that reward.

**Silver threshold interaction:** The Silver threshold remains absolute (`>= 10` remaining). With 25 starting HP, the player can absorb 15 damage and still earn Silver; without the bonus, only 10. This makes Silver (and to a lesser degree Gold, since "no damage" is still required) easier with the bonus. This is the intended reward effect, not an unintended rebalance — but it does mean the HP bonus has a real balance impact on medal attainment, which sits in mild tension with the "no rebalancing" non-goal. This is acceptable because the bonus is earned and optional.

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
- A save failure after victory rolls back in-memory progress to its prior state and shows the existing save-failure feedback. The optimistic update is reverted so stale modifiers are not applied to the next mission.

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

- `startingBaseHealth` and `startingGold` reflect bonus when overrides are provided.
- `startingBaseHealth` and `startingGold` equal `GameBalance` defaults when no override.
- `damageBase` with bonus starting health (25) preserves health above 20 after small hits (e.g., 1 damage -> 24, not clamped to 20).
- `restart()` restores `startingGold` and `startingBaseHealth`, not bare `GameBalance` defaults.
- `snapshot()` includes `startingBaseHealth` matching the session's effective ceiling.

`OrionCampaign.validate`:

- Valid reward assignments (side stages have rewards, main stages don't) pass.
- Invalid assignments (main stage with reward, side stage without) fail.

### Game and widget tests

- `OrionDefenseGame` with `CampaignModifiers(bonusGold: 30, bonusHealth: 5)` starts session with 180 gold and 25 base health.
- `OrionDefenseGame` with `null` modifiers starts with defaults (regression).
- Victory with bonus health produces the correct medal via `startingBaseHealth`.
- Victory panel displays `Base 25/25` (not `Base 25/20`) when session had bonus health.
- **Restart after first clear:** a session created without modifiers (side stage not yet cleared) still restarts with original starting values (150 gold / 20 health), not newly earned bonus values. Restart does not re-evaluate campaign modifiers.
- World map shows reward label on uncleared side stages (teaser format).
- World map shows reward label on cleared side stages (earned format).
- World map shows challenge badge summary when both side stages cleared.
- Existing tests pass unchanged when modifiers default to none. All callers of `StageResult.fromVictoryBaseHealth` in tests are updated to pass `startingBaseHealth`. All `GameSnapshot` construction sites in tests are updated to include `startingBaseHealth`.

### Persistence tests

- **Save → reload → derive modifiers:** save a `CampaignProgress` with side-stage results to `InMemoryCampaignProgressStore`, load a fresh progress from the store, compute `CampaignModifiers.fromProgress` from the loaded progress, and verify `bonusGold`, `bonusHealth`, and `hasChallengeBadge` are correct. This covers the "rewards persist across app restarts" acceptance criterion with a real store round-trip, not just in-memory data.
- **Optimistic update with rollback:** after recording a stage completion, in-memory `_progress` reflects the clear immediately (before the store save resolves). On save failure, `_progress` rolls back to its prior state and the save-failure feedback is shown.

## Acceptance Criteria

- `StageDefinition` can describe an optional `CampaignReward`.
- `CampaignProgress` can determine which side-stage rewards are active via `CampaignModifiers.fromProgress`.
- Starting a mission applies active campaign modifiers consistently (adjusted gold and base health).
- `damageBase` and `restart()` use the session's effective starting values, not bare `GameBalance` defaults.
- Restart replays the mission with its original modifiers; newly earned rewards require returning to the map.
- In-memory campaign progress updates optimistically on victory; save failure rolls back to prior progress.
- `GameSnapshot` carries `startingBaseHealth` so the UI can compute medals and display correct denominators.
- The victory panel displays the correct `startingBaseHealth` denominator (not hardcoded `/20`).
- The world map shows reward information for side stages (earned/teaser labels and challenge badge).
- Rewards persist across app restarts (derived from existing clear status, no new save data), verified by a store round-trip test.
- Main-path unlock behavior remains unchanged.
- Medal calculation remains damage-based: Gold at zero damage, Silver at 10+ remaining, Clear below.
- `OrionCampaign.validate()` guards reward assignments on stage definitions.
- Tests cover reward activation, persistence (store round-trip), mission-start modifiers, damage/restart clamp behavior, restart boundary, optimistic update with rollback, medal calculation with bonus health, victory panel display, and world map display.
