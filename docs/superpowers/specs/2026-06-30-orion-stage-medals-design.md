# Orion Stage Medals Design

## Context

Orion already has a local world-map campaign with seven replayable stages. Campaign progress currently records only whether a stage is cleared. HPA-93 adds a best-performance result for each completed stage so replaying can improve the campaign record without changing mission balance, tower progression, or unlock rules.

The existing architecture should stay intact:

- Pure campaign and mission rules live under `lib/game/campaign/`, `lib/game/rules/`, and `lib/game/models/`.
- `OrionDefenseGame` runs a selected stage and publishes mission snapshots.
- `OrionGamePage` acts as the campaign shell and persists progress.
- `WorldMapView` renders stage state from `CampaignProgress`.

## Goal

Store and display the best earned medal for each completed stage. A stage remains cleared if it has any saved result. Replaying a stage can improve the saved best result by earning a higher medal or, within the same medal, finishing with more base health.

## Scope

HPA-93 includes three player-facing medals:

- `Clear`: stage completed with less than 10 base health remaining.
- `Silver`: stage completed with at least 10 base health remaining.
- `Gold`: stage completed with full base health remaining.

With the current balance, full base health means `GameBalance.initialBaseHealth`, currently 20.

The world map should show the best medal label on each completed node. The victory panel should show the medal earned by that run and the remaining base health.

## Out Of Scope

- Stars.
- Platinum.
- No-retry, limited-tower, or other challenge constraints.
- Campaign rewards or tech-tree unlocks.
- Wave, enemy, tower, or economy rebalancing.
- Migration of old cleared-only save data. The app has not launched, so old incompatible progress can be discarded.

## Data Model

Add a pure result model in `lib/game/campaign/campaign_progress.dart`.

`StageMedal`:

- `clear`
- `silver`
- `gold`

`StageResult`:

- `medal`
- `bestBaseHealth`, an integer from 0 through `GameBalance.initialBaseHealth`

`StageResult.fromVictoryBaseHealth(int baseHealth)` creates the result for a completed run:

- Gold when `baseHealth == GameBalance.initialBaseHealth`.
- Silver when `baseHealth >= 10`.
- Clear otherwise.

`StageResult.isBetterThan(StageResult? other)` compares:

1. Higher medal rank wins.
2. If medal rank is equal, higher `bestBaseHealth` wins.

`CampaignProgress` should store immutable best results by stage id instead of a cleared-id set:

- `bestResultsByStageId`
- `resultFor(stageId)`
- `isCleared(stageId)` returns true when a result exists.
- `recordResult(stageId, result)` returns progress with that result only when it improves on the saved result.
- `withoutUnknownStages(stages)` filters result entries to known stage ids.

Unlock and campaign-complete rules continue to derive from `isCleared`, so the current main and side stage behavior remains unchanged.

## Persistence

`CampaignProgressCodec` should use a new versioned JSON shape:

```json
{
  "version": 2,
  "stageResults": {
    "outpost-alpha": {
      "medal": "gold",
      "bestBaseHealth": 20
    }
  }
}
```

Decode behavior:

- Missing save returns empty progress.
- Empty save returns empty progress.
- Unsupported version returns empty progress.
- Corrupt JSON or wrong top-level types return empty progress.
- Unknown stage ids are ignored.
- Unknown medal values are ignored.
- Invalid `bestBaseHealth` values, including negative values or values above `GameBalance.initialBaseHealth`, cause that stage result to be ignored.
- Reset continues to remove the save key and load as empty progress.

The codec intentionally does not migrate the old version 1 `clearedStageIds` shape.

## Game Flow

On victory, `OrionDefenseGame` should report a stage completion payload instead of only a `StageDefinition`.

Payload:

- `StageCompletion`
  - `stage`
  - `result`

The game should create the `StageResult` from the final session base health after the last wave transitions to `GamePhase.won`. This keeps medal calculation in the game/campaign boundary instead of making `OrionGamePage` infer it from widget state.

`OrionGamePage` should replace `_markStageCleared` with result recording while preserving the existing save queue and reset-generation guard. Save failures should still show the same campaign persistence feedback and should not update local progress.

Replaying a stage:

- Higher medal replaces lower medal.
- Same medal with higher base health replaces the saved result.
- Lower medal or same medal with lower or equal base health does not downgrade the saved result.

## UI

Victory panel:

- Keep the title `Victory`.
- Add a compact result line:
  - `Gold medal - Base 20/20`
  - `Silver medal - Base 14/20`
  - `Clear medal - Base 6/20`
- Loss panel remains unchanged.

World map:

- Locked and open stages keep their current behavior.
- Completed nodes show the best medal label: `Clear`, `Silver`, or `Gold`.
- Medal nodes use distinct icon and color treatment while staying within the current compact node size.
- Exact base health does not need to appear on the map node in this ticket.

## Error Handling

- Locked stages still cannot launch.
- Unknown stage ids still cannot launch.
- Invalid persisted progress should never crash the app.
- Invalid persisted stage results should be ignored rather than repaired with invented data.
- A save failure after victory should leave the previous progress in place and show the existing save-failure feedback.
- Pending result saves should remain serialized so sibling stage completions cannot overwrite each other.
- Reset generation should continue to prevent stale completion saves from restoring progress after a successful reset.

## Testing Strategy

Pure campaign tests:

- Medal calculation thresholds.
- Result comparison by medal and then base health.
- `isCleared`, stage unlocks, and campaign completion derive from stored results.
- `recordResult` improves but does not downgrade saved results.
- Unknown-stage filtering preserves only known result entries.

Persistence tests:

- Version 2 encode/decode round trip.
- Missing, empty, corrupt, unsupported-version, and wrong-type saves decode empty.
- Version 1 cleared-only saves decode empty.
- Unknown stage ids, unknown medal values, and invalid base health entries are ignored.
- In-memory and shared-preferences stores still save, load, and reset progress.

Game and widget tests:

- `OrionDefenseGame` win callback includes the expected stage result from final base health.
- Victory panel shows the earned medal and base health.
- World map renders medal labels for completed nodes.
- Save failure keeps prior progress and shows feedback.
- Serialized completion saves preserve all improved stage results.
- Existing unlock logic still works for main and side stages.

## Acceptance Criteria

- Campaign progress stores per-stage best results instead of only cleared ids.
- A stage is cleared when it has any saved result.
- Victory communicates the earned medal and remaining base health.
- The world map visually distinguishes completed stages by best medal.
- Replays can improve but not downgrade saved best results.
- Existing main and side stage unlock logic remains unchanged.
- Invalid or unsupported saved progress is discarded safely.
- Focused tests cover medal calculation, persistence, replay improvement, map display, and victory display.
