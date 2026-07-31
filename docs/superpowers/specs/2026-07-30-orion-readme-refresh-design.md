# Orion README Refresh Design

## Context

`README.md` currently contains a one-line intro plus developer-facing content (local dev, git hooks, CI). It is no longer the raw Flutter starter copy, but it does not explain what Orion *is*: the gameplay loop, the multi-stage campaign, the tower/enemy systems, persistence, or where to find the design roadmap. A developer or reviewer opening the repo cannot quickly understand or pitch in.

Since the README was last touched, the codebase has grown well beyond the single-mission MVP. There is now a seven-stage world-map campaign, stage modifiers, boss finales, medals, a five-node tech tree, an in-game Codex, and device-local persistence. The README should reflect all of this.

## Goal

Rewrite `README.md` as an audience-ordered, self-contained overview of Orion: what it is and how to play, how to run and test it, how the codebase is layered, the asset surface, and where planning lives — at "overview" depth (names and concepts, not full stat tables). Full tuning numbers already live in the in-game Codex and are intentionally not duplicated in the README.

## Scope

- **In scope:** rewrite `README.md` only.
- **Out of scope (per issue):** gameplay changes, generated screenshots, a separate `docs/game-design.md`, and the unrelated stale `description` field in `pubspec.yaml` (left for a separate cleanup). No code changes are required; all facts are sourced from existing code.

## Decisions (from brainstorm)

- **Structure:** Approach A — audience-ordered. Game overview first, then run/test, then architecture, then roadmap. Reuses existing dev/CI prose, repositioned.
- **Game-system depth:** Overview. Name the towers, traits, and systems; do not enumerate full stat tables. Pointer to the in-game Codex for numbers.
- **Roadmap:** Both — a short inline high-level roadmap (shipped / in progress / planned themes) plus links to the spec/plan docs and the Orion Linear project.

## Source-of-truth facts (verified from code)

These concrete facts anchor the README content so it does not drift from reality.

- **Engine:** Flutter (Flutter ≥ 3.44, Dart SDK ^3.12), `flame: ^1.37.0`, `shared_preferences: ^2.5.5`.
- **Towers (8):** Laser, Rocket, Cryo, Railgun, Ion Chain, Nanite, Gravity Well, Drone Bay (`TowerType`, `lib/game/models/game_models.dart`).
- **Specializations:** 2 per tower (16 total), e.g. Pulse/Prism Laser, Siege/Cluster Rocket, etc. (`GameBalance.specializationsFor`).
- **Tower unlock cadence:** towers unlock at specific waves within a mission (`GameBalance.towerUnlockWave`): Laser/Rocket/Cryo at wave 1, Railgun 2, Ion Chain 3, Nanite 4, Gravity Well 5, Drone Bay 6.
- **Enemy traits (5):** Armored, Shielded, Swarm, Regen, Heavy (`EnemyTrait`). Counters: armor shred vs Armored; EMP/shield-stripping vs Shielded; AoE/chain vs Swarm; burst vs Regen; sustained DPS/slow vs Heavy.
- **Enemy archetypes (9):** basic / basic-elite / armored / shielded / swarm / regen drones, plus heavy / armored-heavy / regen-heavy drones (`EnemyArchetype`).
- **Mission structure:** exactly 8 waves per stage; each stage's final wave contains exactly one boss group (`OrionCampaign.validateStages`).
- **Campaign (7 stages):** 5 main + 2 optional side (`OrionCampaign.stages`).
  - Main: Outpost Alpha → Nebula Relay → Asteroid Foundry → Aurora Gate → Singularity Core.
  - Side: Salvage Rift (bonus-gold reward), Void Bastion (bonus-health reward).
- **Stage modifiers (8):** shieldRecharge, swarmBounty, reinforcedArmor, regenPressurePulses, reducedStartingHealth, enhancedClearBonus, enemySpeedSurge, amplifiedGravityWells (`StageModifier`).
- **Bosses:** one named boss finale per stage (e.g. Shield Matriarch, Armored Excavator, Regen Warden, Swarm Queen, Siege Carrier, Singularity Core).
- **Medals:** Clear / Silver / Gold, derived from surviving base health at victory (`StageMedal`, `StageResult.fromVictoryBaseHealth`).
- **Tech tree (5 campaign upgrades):** Solar Capacitors, Hardened Core, Salvage Crew, Laser Tuning, Cryo Coolant (`CampaignTechUpgrade`). Single-rank, campaign-wide effects; purchased with earned points.
- **Codex:** in-game browser for towers, specializations, and enemies (`lib/game/codex/codex_data.dart`, `lib/game/ui/codex_view.dart`) — the canonical place for full stats.
- **Persistence:** device-local via `shared_preferences`. Stores best result + medal per stage and tech-tree purchases. No accounts, no online sync (`lib/game/campaign/campaign_progress_store.dart`).
- **Phases:** build, wave, won, lost (`GamePhase`). Towers may only be placed/upgraded/specialized during `build`.
- **Architecture layers:** pure rules (`lib/game/models/`, `lib/game/rules/` — deterministic, unit-tested, no Flame) ↔ Flame rendering/simulation (`lib/game/orion_defense_game.dart`, `lib/game/components/`) ↔ Flutter UI (`lib/game/ui/`) driven by an immutable `GameSnapshot` via a `ValueNotifier`.
- **Assets (5 PNGs in `assets/images/`):** `orion_sprite_sheet.png`, `orion_tower_variety_sheet.png`, `orion_terrain_background.png`, `orion_path_tiles.png`, `orion_boss_sheet.png` (declared in `pubspec.yaml`, sliced by loaders in `lib/game/assets/`).
- **Commands (existing, reused verbatim):** `flutter pub get`; `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, `flutter test --coverage`, `flutter build web --release`; `scripts/install-git-hooks.sh`.
- **CI (existing, reused verbatim):** two jobs on push to `main` and on PRs — `Build & lint` and `Unit test` (uploads `coverage/lcov.info` to Codecov).
- **Roadmap source docs:** `docs/superpowers/specs/` (designs), `docs/superpowers/plans/` (implementation plans). Linear project: Orion (`https://linear.app/cwchanap/project/orion-81ed4b865ae9`).

## README structure (section-by-section blueprint)

The final `README.md` will contain these sections, in order:

1. **Title + tagline + badges** — `# Orion`, one-line tagline (portrait, touch-first space tower-defense; Flutter + Flame). A compact badges line (Flutter version, Dart SDK).

2. **Overview** — 3-4 sentence pitch: place towers on a fixed grid, manually start waves, earn gold from kills, upgrade and specialize; survive eight waves per stage across a branching campaign; lose if base health hits zero.

3. **Gameplay loop** — the build → start wave → defend → reward cycle, with pause/speed controls and a pre-wave enemy intel panel. A short bullet cycle.

4. **Campaign** — seven stages (five main + two optional side); each is a full eight-wave mission with its own path, enemy mix, stage modifier(s), and a named boss finale. Local unlock progression, medals (Clear/Silver/Gold), a five-node tech tree of campaign-wide upgrades, and an in-game Codex.

5. **Towers, specializations & enemies** — overview depth. Name the 8 towers, note 2 specializations each and wave-based unlock within a mission. Name the 5 enemy traits with one-line counters. Explicit pointer: full stats live in the in-game Codex, not in the README.

6. **Persistence** — device-local via `shared_preferences`: best result + medal per stage, tech-tree purchases. No accounts, no online sync.

7. **Getting started** — prerequisites + `flutter pub get` + `flutter run`. (Existing prose, lightly reorganized.)

8. **Testing & checks** — `dart format`, `flutter analyze`, `flutter test`, coverage, web build. (Existing prose, lightly reorganized.)

9. **Architecture** — one paragraph + a layered bullet list on the pure-rules ↔ Flame-rendering ↔ snapshot-driven-UI boundary. Pointer to `AGENTS.md` and `docs/` for depth.

10. **Assets** — the five sprite sheets and expected `assets/images/` paths; note the loaders in `lib/game/assets/` slice each sheet.

11. **Roadmap & planning** — inline high-level themes plus links. Concrete content (see "Roadmap content" below): grouped **Shipped** themes drawn from completed Linear issues, a one-line **In progress**, and an **Exploratory / not committed** future-directions list grounded in the "Out of scope" notes of existing specs. Links to `docs/superpowers/specs/`, `docs/superpowers/plans/`, and the Orion Linear project for the live backlog.

### Roadmap content (concrete)

**Shipped**
- Core tower-defense loop (build → wave → defend) with 8 towers, 16 specializations, and 5 enemy traits.
- Seven-stage world-map campaign with branching main + optional side routes.
- Named boss finales, per-stage environmental modifiers, and stage medals (Clear / Silver / Gold).
- Campaign-wide tech tree and persistent side-stage rewards.
- Per-tower targeting modes, tower sell & refund.
- Pause / speed controls, pre-wave enemy intel panel, enemy health bars & trait badges.
- In-game Codex, device-local save, and CI with coverage reporting.

**In progress**
- Documentation & polish — including this README refresh (HPA-104).

**Exploratory / not committed**
- Additional stages and campaign arcs.
- New tower specializations and enemy archetypes.
- Procedural or community-authored maps.
- Cloud save / cross-device sync and multiple save slots.
- Audio, haptics, and accessibility options.

(Rationale: as of this writing every Orion Linear issue is Done except HPA-104, so there is no committed future backlog to cite. The exploratory list is sourced from the "Out of scope" sections of existing design specs — e.g. the world-map-campaign design defers procedural maps, online sync/accounts, and multiple save slots — and is framed as directional, not promised.)

12. **Contributing (Git hooks & CI)** — the existing git-hooks and CI sections, reused verbatim, under a `## Contributing` umbrella.

## Verification (acceptance criteria mapping)

- [ ] README no longer leads with Flutter-starter/boilerplate framing as primary content.
- [ ] README explains the gameplay loop (build→wave→defend→reward) and campaign structure (7 stages, 8 waves each, boss finale).
- [ ] README documents how to run the app locally (`flutter pub get`, `flutter run`).
- [ ] README documents how to run tests (`flutter test`, coverage, analyze, format).
- [ ] README summarizes core systems: stages, waves, towers, specializations, enemy traits, and persistence.
- [ ] README includes a concise roadmap and links to the Orion planning source (specs/plans + Linear).

## Risks / maintenance

- **Drift:** any inline game facts (8 towers, 7 stages, 5 traits) can go stale. Mitigation: keep README at overview depth; point readers to the Codex and `GameBalance`/`OrionCampaign` for the source of truth; the rule tests guard concrete numbers.
- **Link rot:** external Linear link may move. Mitigation: also link the in-repo `docs/superpowers/` folders, which are version-controlled.
