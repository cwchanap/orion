# Orion Pause and Wave Speed Controls Design

## Context

HPA-102 adds player pacing controls to Orion missions. Orion is a Flutter and Flame tower-defense game with a deliberate split between pure game rules and the Flame rendering/simulation layer. The current mission state flows from `OrionDefenseGame` through `GameSession` snapshots into `OrionGamePage`.

The feature should preserve that split. Pacing is not a tower-defense rule like gold, health, wave index, or tower placement. It is runtime control for the current mission instance, so it belongs in `OrionDefenseGame` and is exposed to Flutter through `GameSnapshot`.

## Goal

Let players pause active combat, choose 1x, 2x, or 3x wave speed, and toggle auto-start for the next wave after a short countdown. Speed persists across waves in the same mission, while restart, returning to the world map, and launching a new stage reset pacing to defaults.

## Player Experience

- Missions start at 1x speed, unpaused, with auto-start off.
- During an active wave, the player can pause and resume combat.
- The player can select 1x, 2x, or 3x speed during a mission.
- The selected speed persists after a wave clears and applies to later waves in the same mission.
- Auto-start can be toggled on. When a wave clears and another wave remains, a 3-second build-phase countdown begins.
- During the countdown, the player can still place, upgrade, and specialize towers.
- Turning auto-start off during the countdown cancels it.
- Starting a wave manually cancels any pending countdown.
- Pause freezes both active combat and the auto-start countdown.
- Win/loss states disable pacing controls and clear pause/auto-start state.

## Scope

In scope:

- Pause/resume control.
- Speed selection for 1x, 2x, and 3x.
- Auto-start-next-wave toggle with a 3-second countdown.
- Snapshot fields needed for the UI.
- Tests for mission pacing state, countdown behavior, reset behavior, and control exposure.

Out of scope:

- Offline or background simulation.
- Auto-battle, tower AI changes, or new combat logic.
- Persisting pacing settings across app launches or campaign stages.
- Keyboard shortcuts.
- Visual redesign beyond fitting the controls into the current HUD/bottom-control structure.

## Architecture

`OrionDefenseGame` will mix in Flame's `HasTimeScale`. The game object will own:

- `isPaused`
- `speedMultiplier`
- `autoStartEnabled`
- `autoStartCountdownRemaining`

`GameSession` remains pure mission rules. It should not know about pause, speed, or auto-start because those controls do not change deterministic rules like placement validity, tower stats, or wave progression.

`GameSnapshot` gains pacing fields so the UI can render controls without reading game internals:

- `isPaused`
- `speedMultiplier`
- `autoStartEnabled`
- nullable `autoStartCountdownRemaining`

`OrionDefenseGame` methods will mutate pacing state and publish snapshots:

- `togglePause()`
- `setSpeedMultiplier(double multiplier)`
- `toggleAutoStart()`
- private helpers to reset pacing and apply the effective time scale.

The effective Flame time scale is:

- `0` when paused.
- selected speed when the mission is playable and not paused.
- `1` after won/lost or restart reset.

## Time Flow

Current combat components already use `dt` for movement, cooldowns, projectile travel, drone lifetime, gravity field duration, damage-over-time, slow expiration, and regen. With `HasTimeScale` on `OrionDefenseGame`, those component updates receive scaled time through Flame's component tree.

`OrionDefenseGame.update(dt)` will continue to call `super.update(dt)`, then run mission orchestration. Because `HasTimeScale` applies to the game update, the game's own spawn timer and countdown logic also receive the scaled delta. Paused state sets the scale to zero, so combat components, spawn timers, and countdowns do not advance.

## UI

The existing bottom controls remain the main interaction surface. When no cell or tower panel is active, the controls show:

- World Map button.
- Pause/resume icon button.
- Speed selector for 1x, 2x, 3x.
- Auto-start toggle.
- Start Wave button.

The controls should stay compact and touch-friendly. After win/loss, the end-state panel remains primary and pacing controls are disabled through the snapshot state.

The HUD can show countdown feedback when auto-start is pending, either as feedback text or a small status chip. The UI should not read from the game directly; it only uses the snapshot.

## Auto-Start Rules

When a wave clears:

1. `GameSession.finishActiveWave()` transitions to build or won.
2. If the mission is won, auto-start is cleared and no countdown starts.
3. If the mission is still in build phase and auto-start is enabled, a 3-second countdown starts.
4. Countdown time advances only when unpaused.
5. When the countdown reaches zero, `startWave()` is invoked once.

Cancellation rules:

- Toggling auto-start off clears the countdown.
- Manual `startWave()` clears the countdown.
- Restart clears auto-start and countdown.
- Returning to map drops the mission instance, so no pacing state leaks.
- Loss clears auto-start and countdown.

## Edge Cases

- `returnToMap()` remains blocked during active waves, even when paused.
- Pause can be toggled during active waves and auto-start countdowns. It has no gameplay effect during ordinary build phase except freezing any active countdown.
- Speed selection is allowed during build and wave phases so a player can preselect the next-wave speed.
- Invalid speed values are rejected or ignored. Supported values are exactly `1`, `2`, and `3`.
- Multiple countdown completions cannot start multiple waves because manual start and countdown start both clear the countdown before calling session start.
- Empty-wave test stages still clear normally. If auto-start is on and a subsequent wave exists, countdown behavior still applies.

## Testing Strategy

Add focused tests around game-level pacing behavior:

- New mission snapshot defaults to 1x, unpaused, auto-start off, and no countdown.
- Setting 2x and 3x updates the snapshot and effective game time scale.
- Pause sets effective time to zero; resume restores the selected speed.
- Restart resets speed to 1x, unpauses, disables auto-start, and clears countdown.
- Wave clear with auto-start on starts a 3-second countdown when another wave remains.
- Turning auto-start off during countdown cancels it.
- Countdown starts the next wave after enough unpaused scaled update time.
- Paused countdown does not advance.
- Won/lost states clear pause, auto-start, and countdown.
- Widget smoke test confirms pause/resume, speed selection, and auto-start controls are exposed from the mission screen.

Verification commands:

```bash
dart format .
flutter analyze
flutter test
```

## Acceptance Criteria

- The HUD or bottom controls expose pause/resume, 1x, 2x, 3x, and auto-start.
- Pausing freezes enemy movement, tower firing, projectiles, drones, gravity fields, spawn timers, and auto-start countdowns.
- Resuming continues the current wave from the same state.
- 2x and 3x accelerate wave gameplay consistently.
- Speed persists across waves within one mission.
- Restart, returning to map, and launching a new stage reset pacing state.
- Auto-start starts the next remaining wave after a 3-second countdown.
- Auto-start countdown can be canceled by turning auto-start off.
- Won/lost states disable or reset pacing controls.
- Tests cover state transitions and time-scaling helpers where practical.
