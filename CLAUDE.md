# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Orion is a portrait, touch-first tower-defense game built with **Flutter + Flame** (`flame: ^1.37.0`). Players choose an ordered squad of owned characters, deploy each member at most once on a fixed grid, and upgrade them between waves. A campaign stage is won by clearing all 8 waves and lost if base health hits zero. Dart SDK `^3.12.0`.

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

- **`models/game_models.dart`** — The source of truth for character identity, rank, fixed signatures, combat data and tuning. `Character` maps each member to a combat style and signature; `PlacedTower` retains its internal name but represents a deployed character. `GameSnapshot` exposes the ordered squad and deployed characters separately from the squad's distinct combat styles.
- **`rules/`** — Pure logic, no Flame dependency:
  - `game_session.dart` — `GameSession` owns mutable game state (gold, base health, wave index, deployed members, phase) and validates placement, upgrades, Recall and wave progression. Produces immutable `GameSnapshot`s.
  - `board_layout.dart` — `BoardLayout`: 8×12 grid, the hard-coded enemy `pathCells`, and cell↔pixel coordinate conversion.
  - `tower_targeting.dart` — `TowerTargeting`: range/target selection against `TargetCandidate`s.
  - `combat_effects.dart` — `CombatEffects`: damage resolution (armor/shield/shred), regen, slow merging, chain/pierce target selection, and drone launch caps.
- **`orion_defense_game.dart`** — `OrionDefenseGame extends FlameGame`. The orchestrator that wires logic to rendering. Owns the `GameSession`, runs the wave spawn loop in `update()`, handles taps (`TapCallbacks`), spawns/removes components, and bridges combat decisions to the pure `rules/` functions. Exposes a `ValueNotifier<GameSnapshot> stateNotifier` that the UI listens to.
- **`components/`** — Flame `Component`s for everything on screen: `BoardComponent`, `EnemyComponent`, `TowerComponent`, `ProjectileComponent`, `DroneComponent`, `GravityFieldComponent`, `CombatFeedbackComponent`. These render and animate; combat math is delegated to `rules/`.
- **`assets/`** — Sprite-sheet loaders that slice the PNGs in `assets/images/` into named `Sprite`s (`GameSpriteSheet`, `GameTowerVarietySheet`, `GamePathTiles`, `GameBoardSkin`). Each defines its grid dimensions and an enum of sprite names.
- **`campaign/`** — `CampaignProgress` and `CampaignProgressStore` persist stage results, Endless records, owned character levels and squad order as one serialized profile. The v4 codec intentionally starts a fresh profile for pre-v4 saves.
- **`ui/orion_game_page.dart`** — Flutter widget layer. Hosts the `GameWidget`, and a `ValueListenableBuilder<GameSnapshot>` drives the HUD, squad dock, member controls and end-state panel. `camp_view.dart`, `stage_briefing_sheet.dart` and `codex_view.dart` provide the roster, save-on-launch squad draft and playable character reference. **The UI never reads game state directly — only via the snapshot.**

### Key patterns

- **State flow:** UI calls methods on `OrionDefenseGame` → it mutates `GameSession` → calls `_publishSnapshot()` → `stateNotifier` updates → `ValueListenableBuilder` rebuilds the UI. Feedback messages to the player are passed through the snapshot's `feedback` field.
- **Phase gating:** Members can only be deployed, upgraded or recalled during `GamePhase.build`. `onGameResize` deliberately skips re-layout during `GamePhase.wave` so spawned enemy paths stay stable.
- **Member progression:** deploy at tier 1, upgrade to tier 2, then upgrade to tier 3 to apply the character's fixed signature. Costs remain style-based; Recall refunds 70% of invested gold and permits a tier-1 redeployment. Fresh profiles own Haruto and Mio at E rank/level 1; recruitment and persistent level upgrades are separate work.

## Testing

Tests mirror the layers: pure game logic in `test/game/` (`GameSession`, `BoardLayout`, `CombatEffects`, `TowerTargeting`, the sheet loaders, and `game_balance_test.dart` which guards tuning), Flame component behavior in `test/components/`, and feedback stores/UI in `test/feedback/` and `test/widget/`. `test/widget_test.dart` boots the app shell. When changing balance or rules, expect `game_balance_test.dart` and the rule tests to need updates — they assert concrete numbers.

## Assets

The sprite sheets in `assets/images/` are declared in `pubspec.yaml`; loaders in `lib/game/assets/` hard-code their grids and source-rect math. Approved placeholder portraits and chibis live under `assets/images/characters/<character>/` and use the shared `OrionArt` cache. If a sheet layout or character asset mapping changes, update its matching tests. Image-generation scratch work lives under `tmp/` (gitignored).

## Docs

`docs/superpowers/specs/` and `docs/superpowers/plans/` hold the design specs and implementation plans behind each feature (MVP, sprite sheet, path tiles, terrain, tower variety). Read the relevant spec before changing a feature's behavior.
