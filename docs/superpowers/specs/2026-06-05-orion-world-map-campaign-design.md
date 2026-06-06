# Orion World Map Campaign Design

## Context

Orion is a portrait, touch-first tower-defense game built with Flutter and Flame. The current game has one complete eight-wave mission, eight tower types, wave-based tower unlocks, tower upgrades and specializations, fixed path rendering, and a pure Dart rule layer for deterministic gameplay.

The world-map campaign adds a layer above the existing TD mission. It should preserve the current separation between pure rules and Flame rendering: campaign state decides which mission can start, while `GameSession` decides what happens inside a selected mission.

## Goal

Add a world map made of multiple full tower-defense stages. Each stage is a complete eight-wave mission with its own route and enemy wave composition. The campaign unlocks stages through local progress, opens on the world map first, and lets the player replay unlocked stages.

## Scope

The v1 campaign contains seven stages:

- Five main-route stages.
- Two optional side stages.

Each stage is a full eight-wave mission. The current mission becomes the baseline first stage. The other six stages add route and enemy-mix variety.

Campaign progress is local to the device. It stores cleared stages and derives unlocked stages from the static campaign definition.

## Out Of Scope

- Permanent tower upgrades.
- Campaign currency.
- Stage modifiers.
- Star ratings, medals, scores, or completion grades.
- Stage rewards beyond unlocking later stages.
- Procedural maps.
- Online sync or accounts.
- Multiple campaign save slots.

## Campaign Structure

Use a branching sector map with a main path and optional side branches.

Main path:

1. Stage 1: unlocked by default.
2. Stage 2: unlocks after Stage 1 is cleared.
3. Stage 3: unlocks after Stage 2 is cleared.
4. Stage 4: unlocks after Stage 3 is cleared.
5. Stage 5: unlocks after Stage 4 is cleared.

Side path:

- Side Stage A unlocks after Stage 2 is cleared.
- Side Stage B unlocks after Stage 4 is cleared.

The side stages are truly optional. Clearing Stage 5 completes the campaign even if side stages remain uncleared. Side stages still remain visible and replayable as optional completion content.

## Stage Gameplay

Shared global mission rules stay the same across all stages:

- Tower roster.
- Tower unlock cadence within a mission.
- Upgrade and specialization rules.
- Starting gold.
- Base health.
- Kill rewards.
- Clear bonuses.
- Build, wave, won, and lost phase behavior.

Each stage starts fresh. Towers, gold earned during a mission, selected cell or tower state, active projectiles, enemies, drones, gravity fields, statuses, and wave index do not carry between stages.

Stage-specific data:

- Stage id.
- Display name.
- Short map label.
- World-map position/order metadata.
- Unlock dependency ids.
- Fixed path cells.
- Eight wave definitions.

Winning a stage marks only that stage as cleared. Losing a stage does not change campaign progress. Any unlocked stage can be retried.

## Architecture

Add a pure campaign layer above the current game session.

### `StageDefinition`

`StageDefinition` is pure data for one mission:

- `id`
- `name`
- `mapLabel`
- `description`
- `pathCells`
- `waves`
- `unlockDependencies`
- `isMainPath`
- `mainPathOrder`, nullable for side stages
- `mapColumn` and `mapRow` integer coordinates for rendering the world map

### `CampaignDefinition`

`CampaignDefinition` owns the static seven-stage graph and validation helpers. It exposes:

- all stage definitions in stable display order.
- lookup by id.
- main path stage ids.
- side stage ids.
- derived initial unlocked stage ids.
- validation for ids, dependencies, paths, and wave counts.

### `CampaignProgress`

`CampaignProgress` is the persisted local state:

- cleared stage ids.

It derives:

- unlocked stages from `CampaignDefinition` and cleared ids.
- campaign completion from main path completion.
- cleared and locked stage display states.

Do not persist unlocked ids. This keeps saves resilient when unlock rules change.

### `GameSession`

`GameSession` should be created for a selected `StageDefinition`. It should read the active stage's wave list instead of always reading `GameBalance.waves`.

The session should continue to own mission-only state: gold, base health, wave index, phase, placed towers, and mission snapshots.

### `BoardLayout`

Board geometry remains an 8 by 12 grid. The current hard-coded path becomes a default path for Stage 1, while stage-specific path cells come from `StageDefinition`.

Path helpers should support stage-specific data without introducing Flame dependencies into pure rules.

### `OrionDefenseGame`

`OrionDefenseGame` runs one selected stage. It creates a `GameSession` for that stage, computes waypoints from that stage's path, and reports mission win/loss through the existing snapshot flow.

### `OrionGamePage`

`OrionGamePage` becomes the campaign shell:

- load campaign progress.
- show the world map first.
- launch an unlocked stage.
- host the current `GameWidget` while a mission is active.
- persist cleared progress after a mission win.
- return to the world map after win, loss, or build-phase exit.

## UI Flow

The app opens to the world map.

World map requirements:

- Show all seven stages in a branching layout.
- Show locked, unlocked, cleared, and next-main-path states.
- Disable locked stages visually.
- Tapping an unlocked stage starts that stage.
- Tapping a locked stage shows short feedback and does not start a mission.
- Include a reset campaign action with confirmation.

Mission screen requirements:

- Keep the existing TD board, HUD, tower picker, upgrade and specialization controls, start-wave button, and end-state panel.
- Show the current stage name or compact stage label in the HUD.
- Allow returning to the map only during build phase or after win/loss in v1.
- On win, mark the selected stage cleared, save progress, and update map unlocks.
- On loss, allow retry or return to map without changing campaign progress.

Reset requirements:

- Reset clears local campaign progress.
- After reset, only Stage 1 is unlocked and no stages are cleared.

## Local Persistence

Store the cleared stage ids locally on the device. A simple versioned JSON shape is enough for v1:

```json
{
  "version": 1,
  "clearedStageIds": ["stage-1", "stage-2"]
}
```

Behavior:

- Missing save creates an empty progress state.
- Corrupt save creates an empty progress state.
- Unknown saved stage ids are ignored.
- Duplicate ids are collapsed.
- Reset deletes or overwrites progress with an empty cleared set.

Use a small persistence adapter around the storage backend so campaign rules stay pure and testable. Add `shared_preferences` as the Flutter storage backend. Tests should cover the adapter with in-memory inputs instead of depending on platform storage.

## Error Handling

- Locked stages cannot be launched through UI or campaign rules.
- Unknown stage ids cannot start a mission.
- Stage definitions must have unique ids.
- Unlock dependencies must reference existing stage ids.
- The campaign must contain exactly seven stages in v1.
- The main path must contain exactly five stages.
- Side stages must not be required for campaign completion.
- Each stage must have exactly eight waves.
- Each stage path cell must be in bounds.
- Each stage path must provide at least two cells so waypoints can be generated.
- Development-time invalid stage data should fail tests rather than silently falling back.

## Testing Strategy

Pure Dart tests:

- Campaign unlock derivation.
- Stage 1 unlocked by default.
- Main path progression.
- Side-stage optionality.
- Campaign completion after main Stage 5.
- Reset behavior.
- Save encode/decode.
- Missing, corrupt, duplicate, and unknown-id save handling.
- Stage definition validation.
- Stage path bounds validation.
- Each stage has eight waves.
- `GameSession` uses a selected stage's waves.
- Stage-specific path data is used for waypoints and placement blocking.

Widget tests:

- App opens to the world map.
- Locked, unlocked, and cleared node states render.
- Locked stage tap gives feedback and does not launch.
- Unlocked stage tap launches a mission.
- Mission HUD shows stage identity.
- Reset confirmation clears progress.

Regression tests:

- Existing TD tests continue to pass through the Stage 1 baseline definition.
- Existing placement, tower unlock, upgrade, specialization, combat, win/loss, and restart behavior remain mission-local.

Manual verification:

- Run `dart format .`.
- Run `flutter analyze`.
- Run `flutter test`.
- Launch the app.
- Confirm the world map appears first.
- Start Stage 1, clear it, and confirm Stage 2 unlocks.
- Confirm side stages unlock at their milestones.
- Confirm clearing Stage 5 marks the campaign complete.
- Restart the app and confirm cleared progress persists.
- Reset the campaign and confirm progress is cleared.

## Acceptance Criteria

- The app opens on a seven-stage branching world map.
- Stage 1 is unlocked by default.
- Main stages unlock in order.
- Two side stages unlock from main-path milestones and remain optional.
- Clearing the fifth main stage completes the campaign.
- Campaign progress persists locally across app restarts.
- Reset campaign clears local progress after confirmation.
- Each stage launches as a fresh eight-wave TD mission.
- Each stage can define its own fixed path and wave list.
- The existing tower roster, mission economy, upgrade rules, specialization rules, and combat behavior remain global and mission-local.
- Losing a stage does not change campaign progress.
- Winning a stage marks that stage cleared and updates unlocks.
- Focused tests cover campaign rules, persistence, stage definitions, stage-specific mission data, and world-map UI flow.
