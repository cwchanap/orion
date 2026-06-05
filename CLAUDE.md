# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Orion is a portrait, touch-first space tower-defense game built with **Flutter + Flame** (`flame: ^1.37.0`). The player places towers on a fixed grid, manually starts waves, earns gold from kills, upgrades/specializes towers, and wins by clearing all 8 waves (loses if base health hits zero). Dart SDK `^3.12.0`.

## Commands

```bash
flutter pub get                       # install deps
flutter run                           # run on a connected device/emulator
flutter analyze                       # static analysis (flutter_lints, see analysis_options.yaml)
flutter test                          # run all tests
flutter test test/game/game_session_test.dart   # run a single test file
flutter test --name "starts in build phase"      # run tests matching a name
```

There is no separate format/lint script; use `dart format .` and `flutter analyze`.

## Architecture

The codebase deliberately separates **pure game logic** (deterministic, unit-tested, no Flame imports) from the **Flame rendering/simulation layer**. Keep this boundary intact — logic changes belong in `rules/`/`models/`, not in components.

### Layers (under `lib/game/`)

- **`models/game_models.dart`** — The single source of truth for data and tuning. Defines all enums (`TowerType`, `TowerSpecialization`, `EnemyTrait`, `EnemyArchetype`, `GamePhase`, `PlacementFailure`), value types (`GridPosition`, `TowerStats`, `PlacedTower`, `WaveDefinition`, `EnemyStats`, `GameSnapshot`), and **`GameBalance`** — all economy/wave/tower/enemy constants, the `waves` list, `towerStats()`, `towerUnlockWave()`, and `specializationsFor()`. This is a ~1100-line file; balance tuning happens here.
- **`rules/`** — Pure logic, no Flame dependency:
  - `game_session.dart` — `GameSession` owns mutable game state (gold, base health, wave index, placed towers, phase) and the rules for placing/upgrading/specializing towers and advancing waves. Produces immutable `GameSnapshot`s.
  - `board_layout.dart` — `BoardLayout`: 8×12 grid, the hard-coded enemy `pathCells`, and cell↔pixel coordinate conversion.
  - `tower_targeting.dart` — `TowerTargeting`: range/target selection against `TargetCandidate`s.
  - `combat_effects.dart` — `CombatEffects`: damage resolution (armor/shield/shred), regen, slow merging, chain/pierce target selection, and drone launch caps.
- **`orion_defense_game.dart`** — `OrionDefenseGame extends FlameGame`. The orchestrator that wires logic to rendering. Owns the `GameSession`, runs the wave spawn loop in `update()`, handles taps (`TapCallbacks`), spawns/removes components, and bridges combat decisions to the pure `rules/` functions. Exposes a `ValueNotifier<GameSnapshot> stateNotifier` that the UI listens to.
- **`components/`** — Flame `Component`s for everything on screen: `BoardComponent`, `EnemyComponent`, `TowerComponent`, `ProjectileComponent`, `DroneComponent`, `GravityFieldComponent`. These render and animate; combat math is delegated to `rules/`.
- **`assets/`** — Sprite-sheet loaders that slice the PNGs in `assets/images/` into named `Sprite`s (`GameSpriteSheet`, `GameTowerVarietySheet`, `GamePathTiles`, `GameTerrain`). Each defines its grid dimensions and an enum of sprite names.
- **`ui/orion_game_page.dart`** — Flutter widget layer. Hosts the `GameWidget`, and a `ValueListenableBuilder<GameSnapshot>` drives the HUD, bottom controls (tower picker, upgrade/specialize, start wave), and end-state panel. **The UI never reads game state directly — only via the snapshot.**

### Key patterns

- **State flow:** UI calls methods on `OrionDefenseGame` → it mutates `GameSession` → calls `_publishSnapshot()` → `stateNotifier` updates → `ValueListenableBuilder` rebuilds the UI. Feedback messages to the player are passed through the snapshot's `feedback` field.
- **Phase gating:** Towers can only be placed/upgraded/specialized during `GamePhase.build`. `onGameResize` deliberately skips re-layout during `GamePhase.wave` so spawned enemy paths stay stable.
- **Tower progression:** place (level 1) → upgrade → specialize (one of two `TowerSpecialization`s per `TowerType`). Tower types unlock at specific waves via `GameBalance.towerUnlockWave`.

## Testing

Tests live in `test/game/` and target the **pure logic layer** (`GameSession`, `BoardLayout`, `CombatEffects`, `TowerTargeting`, the sheet loaders, and `game_balance_test.dart` which guards tuning). `test/widget_test.dart` boots the app shell. When changing balance or rules, expect `game_balance_test.dart` and the rule tests to need updates — they assert concrete numbers.

## Assets

The four PNGs in `assets/images/` are project-owned generated sprite sheets (declared in `pubspec.yaml`). The corresponding loaders in `lib/game/assets/` hard-code each sheet's column/row counts and source-rect math — if a PNG's grid layout changes, update the matching loader constants and its `*_test.dart`. Image-generation scratch work lives under `tmp/` (gitignored).

## Docs

`docs/superpowers/specs/` and `docs/superpowers/plans/` hold the design specs and implementation plans behind each feature (MVP, sprite sheet, path tiles, terrain, tower variety). Read the relevant spec before changing a feature's behavior.
