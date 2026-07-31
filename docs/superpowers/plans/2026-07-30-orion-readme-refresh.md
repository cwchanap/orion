# Orion README Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dev-only `README.md` with an audience-ordered, self-contained overview of Orion — what it is, how to play, how to run/test, how the codebase is layered, the asset surface, and where planning lives.

**Architecture:** Documentation-only change to a single file, `README.md`. No code, no tests, no other files change. All factual content is sourced verbatim from the codebase (enums, balance constants, campaign definitions) in the design spec.

**Tech Stack:** Markdown (GitHub-flavored). No build step.

## Global Constraints

- **Scope:** `README.md` only. Do not modify `pubspec.yaml`, code, tests, or any other file.
- **No code changes:** This is documentation-only. If a claim can't be verified against existing code, it doesn't go in.
- **Depth:** Overview only — name towers/traits/stages; do **not** duplicate full stat tables (those live in the in-game Codex).
- **Roadmap honesty:** "Planned" must be framed as *Exploratory / not committed* — every Orion Linear issue is Done except this one, so assert nothing as a firm commitment.
- **Verified facts (copy verbatim from the spec, do not re-derive):**
  - 8 towers: Laser, Rocket, Cryo, Railgun, Ion Chain, Nanite, Gravity Well, Drone Bay.
  - 16 specializations (2 per tower); unlock waves: Laser/Rocket/Cryo = 1, Railgun = 2, Ion Chain = 3, Nanite = 4, Gravity Well = 5, Drone Bay = 6.
  - 5 enemy traits: Armored, Shielded, Swarm, Regen, Heavy.
  - 7 campaign stages (5 main + 2 side); 8 waves each; one boss in the final wave.
  - Medals: Clear / Silver / Gold; 5-node tech tree; device-local save via `shared_preferences`.
  - Linear project URL: `https://linear.app/cwchanap/project/orion-81ed4b865ae9`.
- **No invented URLs:** Only the Flame homepage (`https://flame-engine.org/`) and the verified Linear project URL may appear as external links. All other links are in-repo relative paths.

---

### Task 1: Rewrite README.md with the refreshed, audience-ordered content

**Files:**
- Modify: `README.md` (full replacement of contents)
- Reference (read-only, for accuracy): `lib/game/models/game_models.dart`, `lib/game/campaign/orion_campaign.dart`, `lib/game/campaign/tech_tree.dart`, `pubspec.yaml`

**Interfaces:**
- Consumes: the design spec at `docs/superpowers/specs/2026-07-30-orion-readme-refresh-design.md` (all facts and the section blueprint).
- Produces: the new `README.md`. Nothing else depends on it (no test imports it; no anchors are linked elsewhere), so a full content replacement is safe.

- [ ] **Step 1: Replace the entire contents of `README.md`**

Overwrite `README.md` with exactly the following (this is the complete file — do not abbreviate or paraphrase):

````markdown
# Orion

Flutter ≥ 3.44 · Dart ^3.12 · [Flame](https://flame-engine.org/) ^1.37.0

Orion is a portrait, touch-first space tower-defense game built with **Flutter** and **[Flame](https://flame-engine.org/)**. Defend a relay core across a branching campaign of space stations by placing and upgrading towers along enemy approach lanes.

## Overview

In Orion you place towers on a fixed grid during a build phase, manually start each enemy wave, earn gold from kills, then upgrade and specialize your towers between waves. Each mission is a gauntlet of eight waves ending in a named boss; survive them all without your base health hitting zero and the stage is cleared. Across the campaign you unlock new stages, earn medals, and spend points on persistent upgrades.

## Gameplay loop

1. **Build** — place, upgrade, specialize, sell, and retarget towers. A pre-wave intel panel previews the next wave's enemies, traits, and recommended counters.
2. **Start wave** — enemies spawn and follow the stage's fixed path toward your base.
3. **Defend** — towers auto-target and fire; use pause and 1×/2× speed to manage the fight.
4. **Reward** — earn gold from kills plus a clear bonus, then loop back to Build until all eight waves and the boss are cleared.

Win by clearing the final wave; lose if base health reaches zero.

## Campaign

The world map has **seven stages**: five main-route stages and two optional side stages. Each stage is a complete eight-wave mission with its own path, enemy mix, and a **named boss finale**. Many stages apply a unique **environmental modifier** (such as shield recharge, reinforced armor, or an enemy speed surge) that changes how you defend.

- **Progression** is local: clearing a stage unlocks later stages, and cleared stages stay replayable.
- **Medals** — Clear, Silver, and Gold — are awarded based on the base health you preserve at victory; your best result per stage is saved.
- **Tech tree** — five campaign-wide upgrades (for example extra starting gold, extra base health, or stronger lasers), purchased with earned points and persistent across missions.
- **Side stages** grant permanent rewards (bonus gold or bonus health) when cleared.
- **Codex** — an in-game reference browses every tower, specialization, and enemy so you can plan counters without leaving the game.

## Towers, specializations & enemies

**Towers** — eight types, each with **two specializations** and each unlocking at a specific wave within a mission:

| Tower | Unlocks | Specializations |
| --- | --- | --- |
| Laser | Wave 1 | Pulse Laser, Prism Laser |
| Rocket | Wave 1 | Siege Rocket, Cluster Rocket |
| Cryo | Wave 1 | Deep Freeze, Frostbite |
| Railgun | Wave 2 | Lance Railgun, Magnetic Railgun |
| Ion Chain | Wave 3 | Storm Relay, Overload Relay |
| Nanite | Wave 4 | Dissolver Nanites, Replicator Nanites |
| Gravity Well | Wave 5 | Singularity Well, Crush Well |
| Drone Bay | Wave 6 | Interceptor Bay, Hunter Bay |

**Enemy traits** — five traits, each demanding a specific counter:

- **Armored** — reduces incoming damage; counter with armor-shred.
- **Shielded** — regenerating shield layer; counter with EMP or shield-stripping.
- **Swarm** — many fast, weak units; counter with AoE, chain, or pierce.
- **Regen** — heals over time; counter with burst damage.
- **Heavy** — high HP; counter with sustained DPS and slows.

> Full stats, costs, and effect details for every tower and enemy live in the **in-game Codex** — the README intentionally stays at a glance.

## Persistence

Progress is stored **locally on the device** via `shared_preferences`: your best result and medal per stage, plus tech-tree purchases. There are no accounts and no online sync.

## Getting started

**Prerequisites:** Flutter ≥ 3.44 (Dart SDK ^3.12).

Install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

## Testing & checks

Run the local checks:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test --coverage
flutter build web --release
```

## Architecture

Orion keeps **pure game logic** separate from **rendering**:

- **`lib/game/models/`** — data and tuning source of truth (`GameBalance`, enums, value types). No Flame dependency.
- **`lib/game/rules/`** — deterministic gameplay logic (session, board layout, targeting, combat effects). Unit-tested, no Flame dependency.
- **`lib/game/components/`** and **`orion_defense_game.dart`** — Flame rendering and simulation; combat math is delegated to `rules/`.
- **`lib/game/ui/`** — Flutter widgets. The UI never reads game state directly; it rebuilds from an immutable `GameSnapshot` via a `ValueNotifier`.
- **`lib/game/campaign/`** — the world map, stage definitions, medals, tech tree, and the local progress store.

See [`AGENTS.md`](AGENTS.md) and the [`docs/`](docs/) folder for the full layering and design history.

## Assets

All art is project-owned sprite-sheet PNGs in `assets/images/`, declared in `pubspec.yaml` and sliced by the loaders in `lib/game/assets/`:

| File | Used for |
| --- | --- |
| `orion_sprite_sheet.png` | Core game sprites |
| `orion_tower_variety_sheet.png` | Tower variety sprites |
| `orion_terrain_background.png` | Terrain and background |
| `orion_path_tiles.png` | Path tiles |
| `orion_boss_sheet.png` | Named bosses |

If a sheet's grid layout changes, update the matching loader constants in `lib/game/assets/` and its corresponding `*_test.dart`.

## Roadmap & planning

**Shipped**

- Core tower-defense loop with 8 towers, 16 specializations, and 5 enemy traits.
- Seven-stage world-map campaign with branching main and optional side routes.
- Named boss finales, per-stage environmental modifiers, and stage medals.
- Campaign tech tree and persistent side-stage rewards.
- Per-tower targeting modes, tower sell & refund.
- Pause and speed controls, pre-wave enemy intel panel, enemy health bars and trait badges.
- In-game Codex, device-local save, and CI with coverage reporting.

**In progress**

- Documentation and polish.

**Exploratory (not committed)**

- Additional stages and campaign arcs.
- New tower specializations and enemy archetypes.
- Procedural or community-authored maps.
- Cloud save, cross-device sync, and multiple save slots.
- Audio, haptics, and accessibility options.

Designs live in [`docs/superpowers/specs/`](docs/superpowers/specs/) and implementation plans in [`docs/superpowers/plans/`](docs/superpowers/plans/). Track live work in the [Orion Linear project](https://linear.app/cwchanap/project/orion-81ed4b865ae9).

## Contributing

### Git hooks

Install the repo-owned pre-commit hook once per checkout:

```bash
scripts/install-git-hooks.sh
```

The pre-commit hook checks Dart formatting and runs `flutter analyze`.

### Continuous integration

GitHub Actions runs two jobs on pushes to `main` and on pull requests:

- `Build & lint`: installs dependencies, checks formatting, runs `flutter analyze`, and builds the web target.
- `Unit test`: installs dependencies, runs `flutter test --coverage`, and uploads `coverage/lcov.info` to Codecov with GitHub OIDC authentication.
````

- [ ] **Step 2: Verify markdown structure**

Open `README.md` and confirm:
- Exactly one `# Orion` H1 at the top; all other headings are `##` or deeper (no second H1).
- Every fenced code block has a matching closing fence (there are 4 `bash` blocks in the README).
- The two external links resolve: `https://flame-engine.org/` and `https://linear.app/cwchanap/project/orion-81ed4b865ae9`.
- The in-repo links point to existing paths: `AGENTS.md`, `docs/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`.

Run a quick relative-path existence check:

```bash
test -f AGENTS.md && test -d docs/superpowers/specs && test -d docs/superpowers/plans && echo "links OK"
```

Expected output: `links OK`.

- [ ] **Step 3: Walk the acceptance criteria**

Confirm each is satisfied by the new README (the section that satisfies it is in parentheses):

- [ ] No Flutter-starter/boilerplate framing as primary content (Overview is Orion-specific).
- [ ] Explains the gameplay loop — Build → Start wave → Defend → Reward (Gameplay loop).
- [ ] Explains campaign structure — 7 stages, 8 waves each, boss finale (Campaign).
- [ ] Documents how to run locally — `flutter pub get`, `flutter run` (Getting started).
- [ ] Documents how to run tests — `flutter test`, coverage, analyze, format (Testing & checks).
- [ ] Summarizes core systems — stages, waves, towers, specializations, enemy traits, persistence (Campaign / Towers / Persistence).
- [ ] Includes a concise roadmap and links to the planning source (Roadmap & planning).

If any box can't be checked, fix the README before proceeding.

- [ ] **Step 4: Confirm the doc-only change broke nothing**

Run the project's static + test gates (these don't read README, but confirm no accidental edit to source):

```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` exits 0 (no issues); `flutter test` reports all tests passing. If anything fails, the failure is unrelated to this change — investigate before committing rather than committing a red suite.

- [ ] **Step 5: Commit**

Stage and commit the README and the design spec together:

```bash
git add README.md docs/superpowers/specs/2026-07-30-orion-readme-refresh-design.md
git commit -m "docs: refresh README with game overview and roadmap (HPA-104)"
```

(Note: the design spec at `docs/superpowers/specs/2026-07-30-orion-readme-refresh-design.md` is currently uncommitted; include it in this commit so the work is self-documenting. If the repo prefers specs committed separately, split into two commits — one `docs: design README refresh (HPA-104)` for the spec, one `docs: refresh README ... (HPA-104)` for the README.)

---

## Self-Review

**1. Spec coverage:** Every spec section maps to README content — Overview/loop (spec §2-3), Campaign (§4), Towers/enemies (§5), Persistence (§6), Getting started (§7), Testing (§8), Architecture (§9), Assets (§10), Roadmap (§11 + concrete roadmap content), Contributing/git-hooks/CI (§12). All six acceptance criteria have an explicit check in Step 3. No gaps.

**2. Placeholder scan:** No TBD/TODO. The full README content is embedded verbatim in Step 1; facts are copied from the spec's verified list, not re-derived. The only two external URLs are explicitly permitted in Global Constraints.

**3. Consistency:** Tower names, specialization names, unlock waves, trait names, medal names, and the Linear URL match the spec's verified-facts list and the source code. "16 specializations" = 8 towers × 2 (verified). File/section names referenced (`AGENTS.md`, `docs/superpowers/...`, `lib/game/...`) exist in the repo.
