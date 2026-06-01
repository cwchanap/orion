# Orion Tower Defense MVP Design

## Context

Orion is currently a generated Flutter starter app with the default counter screen, no Flame dependency, and no game-specific source structure. The MVP will replace the starter app with a mobile portrait tower-defense game built with Flutter and Flame.

The project directory is not currently an initialized git repository. The normal brainstorming workflow requires committing this spec, so the commit step depends on initializing git or accepting a documented exception.

## Goal

Build a playable tower-defense MVP where the player defends a space outpost across five manually started waves. The MVP must prove the complete loop: place towers, start waves, earn gold, upgrade towers, survive or lose, and restart.

## Player Experience

- The game opens directly into the tower-defense board.
- The board is portrait-first and touch-friendly.
- Enemies follow a fixed winding route from spawn to base.
- The player places towers on open grid cells that are not part of the route.
- The player starts each wave manually.
- The player wins by clearing wave 5.
- The player loses if base health reaches zero.
- Win and loss states show a restart action.

## MVP Rules

- Session length: 5 waves.
- Economy: simple gold.
- Starting gold: enough for one or two initial towers.
- Income: gold per enemy killed.
- Base health: reduced when enemies reach the endpoint.
- Placement: grid-based, off-path, one tower per occupied cell.
- Pathing: fixed route for the MVP; towers do not alter enemy paths.
- Upgrades: each tower has one paid upgrade level.

## Initial Balance

These values are starter tuning for the MVP and can be adjusted after playtesting without changing the game structure.

- Base health: 20.
- Starting gold: 120.
- Laser cost: 50; upgrade cost: 70.
- Rocket cost: 80; upgrade cost: 100.
- Cryo cost: 70; upgrade cost: 90.
- Wave 1: 8 drones, 30 health, 1 base damage, 8 gold reward.
- Wave 2: 10 drones, 42 health, 1 base damage, 9 gold reward.
- Wave 3: 12 drones, 58 health, 1 base damage, 10 gold reward.
- Wave 4: 14 drones, 76 health, 2 base damage, 11 gold reward.
- Wave 5: 16 drones, 100 health, 2 base damage, 12 gold reward.

## Towers

### Laser Tower

- Role: cheap, fast, single-target damage.
- Targeting: enemy in range closest to the base.
- Upgrade: improves its defining single-target strength through better damage, fire rate, or both.

### Rocket Tower

- Role: slower, higher-cost splash damage.
- Targeting: enemy in range closest to the base.
- Projectile behavior: impact damages enemies within a small radius.
- Upgrade: improves damage and/or splash radius.

### Cryo Tower

- Role: low damage plus temporary slow.
- Targeting: enemy in range closest to the base.
- Effect: applies a temporary movement-speed slow.
- Upgrade: improves slow strength, duration, or both.

## Enemies and Waves

- Enemies are space drones rendered with simple Flame shapes/vector styling for the MVP.
- Each wave scales health, count, speed, and gold reward.
- Enemies move along waypoint positions derived from the logical grid.
- Enemies reaching the base are removed and damage base health.
- Wave completion occurs when all enemies for that wave have spawned and no active enemies remain.

## Architecture

Use a lean Flame-first architecture with Flutter overlays for controls.

### Flutter Shell

- `main.dart` bootstraps a `MaterialApp`.
- The home screen hosts a `GameWidget`.
- Flutter overlays provide HUD and menus.

### Flame Game

`OrionDefenseGame` owns:

- Board sizing and portrait layout.
- Logical grid and fixed path waypoints.
- Game phase transitions.
- Gold, base health, wave number, and victory/loss state.
- Component creation and lifecycle.
- Overlay callbacks for selected cells, selected towers, and end states.

### Components

- `EnemyComponent`: movement, health, slow effects, reward value, base damage.
- `TowerComponent`: tower type, level, range, cooldown, targeting, upgrade stats.
- `ProjectileComponent`: visible shot travel, hit resolution, splash or slow application.
- Board helpers: grid cell rendering, path rendering, placement highlight feedback.

### Models and Config

Keep balance data out of component internals:

- `TowerType`
- `TowerStats`
- `EnemyStats`
- `WaveDefinition`
- `GamePhase`
- `PlacementResult`
- Grid/path helper types

This keeps the MVP simple while leaving room for future balancing, new towers, and dynamic pathfinding.

## UI

The Flame canvas renders the board, enemies, towers, shots, and placement feedback. Flutter overlays render controls and text.

Required overlays:

- HUD: base health, gold, wave, and phase.
- Tower picker: shown after tapping an empty buildable cell.
- Upgrade panel: shown after tapping an existing tower.
- Start wave button: available only when no wave is active and the game has not ended.
- End-state panel: win/loss result and restart.

Invalid placement gives brief feedback and never spends gold.

## Error Handling and Edge Cases

- Do not allow placement outside the board.
- Do not allow placement on path cells.
- Do not allow placement on occupied cells.
- Do not allow tower purchase or upgrade without enough gold.
- Disable wave start while a wave is active.
- Ignore or close placement panels after game over.
- Clamp base health at zero.
- Ensure slow effects expire and do not permanently reduce enemy speed.
- Ensure projectiles safely handle targets that die before impact.

## Testing Strategy

Prefer focused Dart tests for deterministic rules and a small widget smoke test for app boot.

Unit-test targets:

- Placement validation for off-board, path, occupied, and valid cells.
- Gold spending for tower purchase and upgrade.
- Upgrade stat changes for each tower type.
- Tower targeting priority: enemy closest to the base among enemies in range.
- Wave completion and progression through wave 5.
- Win transition after clearing the final wave.
- Loss transition when base health reaches zero.
- Slow effect application and expiration.

Widget/smoke-test targets:

- App boots into the game shell.
- HUD exposes base health, gold, and wave state.
- Start wave control appears in the initial build phase.

Manual verification:

- Run formatter.
- Run Flutter analyzer.
- Run Flutter tests.
- Launch locally on a Flutter target when the environment permits.

## Out of Scope

- Dynamic pathfinding around placed towers.
- Asset pipeline, sprite sheets, or audio.
- Multiple maps.
- Save/load progression.
- Advanced tower upgrade trees.
- Enemy resistances or status stacking rules beyond simple cryo slow refresh.
- Desktop-specific keyboard controls.
- Online leaderboards or persistence.

## Acceptance Criteria

- The default counter app is replaced by the Orion tower-defense game.
- The player can place laser, rocket, and cryo towers on valid off-path grid cells.
- Towers attack enemies during active waves.
- Enemies follow the fixed path and damage the base if they reach the endpoint.
- The player earns gold from kills and can buy one upgrade level for each tower.
- Five manual waves can be played from start to win.
- The game can enter loss state when base health reaches zero.
- Restart returns the game to a clean initial state.
- Deterministic rule tests cover placement, economy, upgrades, wave progression, targeting, and win/loss transitions.
