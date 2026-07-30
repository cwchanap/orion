# Orion Tower & Enemy Codex — Design

- **Date:** 2026-07-28
- **Issue:** [HPA-103 — Add in-game tower and enemy codex](https://linear.app/cwchanap/issue/HPA-103/add-in-game-tower-and-enemy-codex)
- **Status:** Design (awaiting implementation plan)
- **Branch:** `jack65786656/hpa-103-add-in-game-tower-and-enemy-codex`

## 1. Overview

Add an in-game **Codex** — a read-only reference screen reachable from the
campaign (world) map that explains Orion's towers, enemies, traits, combat
effects, and stages. All numeric data is generated from the existing tuning
source of truth (`GameBalance`) and the model enums; only short prose
descriptions are authored. This keeps the codex correct as balance changes and
satisfies the issue's "generate codex data from `GameBalance` / enums instead of
duplicating constants" requirement.

The codex is a **planning aid**, opened between missions. It does not touch live
mission state.

## 2. Goals

- One Codex entry point on the campaign map.
- Four sections — **Towers**, **Enemies**, **Effects**, **Stages** — each fully
  generated from game data.
- Player-readable explanations of every tower type, every specialization, every
  enemy trait, and every combat effect.
- Works on narrow / mobile layouts.
- A pure, unit-tested data layer that the (thin) view consumes.

## 3. Non-goals (this ticket)

- No Codex entry from the in-mission HUD (fast-follow candidate).
- No tutorial or onboarding flow.
- No README / external doc changes.
- No boss bestiary — bosses are stage-specific finale spoilers, not part of the
  recurring enemy roster. The Enemies section covers only the 9
  `EnemyArchetype`s.
- No search / filter UI (fast-follow candidate).
- No live in-mission state, no persistence of codex-specific data.

## 4. Resolved decisions

| Decision | Choice | Rationale |
|---|---|---|
| Entry point | Campaign map only | Planning surface; gives the content-heavy codex the full screen; avoids overlaying live gameplay. Mission-HUD access is a fast follow. |
| Effects presentation | Standalone mechanics glossary **plus** a short blurb on each specialization | The issue lists Effects as its own section; a glossary teaches vocabulary while per-spec blurbs stay specific. |
| Stage gating | All 7 stages shown in full, each with a Locked/Unlocked/Cleared badge | A reference tool's job is to teach; full detail aids planning. Conditional rendering is limited to the status badge. |
| Architecture | Mirror the existing `StageModifierMetadata` pattern | Pure data classes + static factories reading `GameBalance`, fully unit-testable, zero duplicated constants. |
| Navigation | In-place `_ShellView` swap (matches Tech Tree), **not** `Navigator.push` | `TechTreeView` is rendered in `OrionGamePage`'s build switch with an `onBack` callback; an `AppBar` default back button would pop the whole `OrionGamePage` route. |
| Label home | Enhanced-enum `label` on `TowerType` / `EnemyTrait` / `EnemyArchetype` (idiomatic) | Matches existing enhanced-enum precedent (`TowerSpecialization.label`, `TowerTargetingMode.label`). `EnemyArchetype.label` becomes the single source for the names wave previews already show. Only Flutter-dependent `towerIcon` stays a UI helper. |
| Bosses | Excluded from v1 | Spoilers; see Non-goals. |

## 5. Architecture

New code lives under `lib/game/codex/` (pure presentation model — no Flutter) and
`lib/game/ui/` (view + the one Flutter-dependent helper). Edits are minimal.

### 5.1 File layout

```
lib/game/
  models/game_models.dart     [edit]  add `label` to TowerType + EnemyTrait + EnemyArchetype (enhanced enums); delegate _enemyLabelForStats to EnemyArchetype.label
  ui/tower_icons.dart         [new]   IconData towerIcon(TowerType) — moved from orion_game_page._towerIcon
  codex/codex_data.dart       [new]   PURE presentation value types + CodexData façade (reads GameBalance)
  util/format.dart            [new]   shared neutral percent/number formatters (promoted from StageModifierMetadata._percent/_number)
  campaign/stage_reward_label.dart [new] shared pure stageRewardLabel(stage, {required bool isCleared}) — used by CodexStageEntry + world_map_view
  ui/codex_view.dart          [new]   Flutter widget: full-screen codex page (in-place, not pushed)
  ui/orion_game_page.dart     [edit]  drop _towerLabel/_enemyTraitLabel/_towerIcon; add _ShellView.codex + _openCodex/_closeCodex
  ui/world_map_view.dart      [edit]  add onOpenCodex callback + IconButton; drop private _rewardLabel (use shared helper)
```

### 5.2 Layering

```
GameBalance / enums (source of truth, unchanged tuning)
        │  reads constants + enum values
        ▼
codex/codex_data.dart   (PURE: value types + CodexData factories)   ◄── CampaignProgress (for stage status) + OrionCampaign.stages (for stage list)
        │  consumed by
        ▼
ui/codex_view.dart      (Flutter: renders cards)
        ▲  opened from
        │
ui/world_map_view.dart  (campaign map header button)
```

The pure / Flame-free boundary the repo deliberately maintains is preserved:
`codex_data.dart` imports only `game_models.dart`, `campaign_progress.dart`,
`orion_campaign.dart`, `stage_definition.dart`, `stage_modifier_metadata.dart`,
`campaign/stage_reward_label.dart`, and `util/format.dart`. No
`package:flutter`, no `package:flame`. Shared formatters live in the neutral
`util/format.dart` so `campaign` never depends on `codex`.

## 6. Data model (`codex/codex_data.dart`)

All classes have `const` constructors and immutable fields; instances are built
at runtime from `GameBalance` / enums, so they are **not** `const` values (e.g.
`StageDefinition`'s constructor is not `const`, and `towerStats` / `enemyArchetype`
are runtime calls). Prose fields are authored strings.

### 6.1 Value types

```dart
class CodexTowerEntry {
  final TowerType type;
  final String label;                 // TowerType.label
  final int unlockWave;               // GameBalance.towerUnlockWave(type)
  final TowerStats baseStats;         // GameBalance.towerStats(type, level: 1)
  final int upgradeCost;              // baseStats.upgradeCost (1 -> 2)
  final int specializationCost;       // GameBalance.towerStats(type, level: 2).specializationCost — per-type (from _TowerCosts), hoisted here because it is identical for both specializations
  final List<CodexSpecializationEntry> specializations; // exactly 2
}

class CodexSpecializationEntry {
  final TowerSpecialization specialization;
  final String label;                 // specialization.label (enum)
  final TowerStats specializedStats;  // GameBalance.towerStats(type, level: 3, specialization: spec)
  final String description;           // authored one-line blurb
}

class CodexEnemyEntry {
  final EnemyArchetype archetype;
  final String label;                 // archetype.label (see §6.3 — single source, matches wave-briefing text)
  final EnemyStats stats;             // GameBalance.enemyArchetype(archetype)
  final List<EnemyTrait> traits;      // EnemyTrait.values.where(stats.traits.contains).toList() — sorted to enum order (the Set is insertion-ordered, not enum-ordered)
  final String roleDescription;       // authored one-line blurb
}

class CodexTraitEntry {
  final EnemyTrait trait;
  final String label;                 // EnemyTrait.label
  final String effect;                // authored one-line effect explanation
}

class CodexEffectEntry {
  final String id;                    // 'slow' | 'corrosion' | 'armorShred' | 'shieldDamage'
                                      // | 'pierce' | 'chain' | 'splash' | 'drones' | 'gravityField'
  final String title;                 // authored
  final String description;           // authored mechanic explanation (optionally reads a global constant)
  final List<TowerSpecialization> relatedSpecializations; // cross-reference
}

class CodexStageEntry {
  final StageDefinition stage;
  final StageProgressStatus status;   // progress.statusFor(stage)
  final List<StageModifierMetadata> modifiers; // StageModifierMetadata.forModifier per stage.modifiers
  final int waveCount;                // stage.waves.length (8)
  final String? rewardLabel;          // via shared stageRewardLabel(stage, isCleared) — see §5.1; not duplicated from world_map_view
}
```

### 6.2 `CodexData` façade (static builders, pure)

```dart
class CodexData {
  static List<CodexTowerEntry> get towers;                  // one per TowerType.values (8)
  static CodexTowerEntry towerFor(TowerType type);
  static List<CodexEnemyEntry> get enemies;                 // one per EnemyArchetype.values (9)
  static List<CodexTraitEntry> get traits;                  // one per EnemyTrait.values (5)
  static List<CodexEffectEntry> get effects;                // the 9 glossary entries (fixed order)
  static List<CodexStageEntry> stagesFor(CampaignProgress progress); // one per OrionCampaign.stages (7)
}
```

`stagesFor` is the only builder that takes an argument — stage status is runtime
state. It is still pure: identical `progress` input yields identical output.

### 6.3 Shared helpers

**Formatters — `util/format.dart` (neutral).** Promote the private `_percent`
/ `_number` helpers currently inside `StageModifierMetadata` into a new neutral
`lib/game/util/format.dart`, so both `campaign/stage_modifier_metadata.dart`
and `codex/codex_data.dart` import them. This keeps the dependency direction
correct — campaign and codex both depend on a neutral util; **campaign never
depends on codex**. `StageModifierMetadata` is updated to call the shared
helpers (behaviour unchanged; its existing test guards this).

**`stageRewardLabel(stage, {required bool isCleared})` —
`campaign/stage_reward_label.dart`.** Extracted from world_map_view's private
`_rewardLabel` so both `world_map_view` and `CodexStageEntry` share one
implementation. Contract: main stages / no reward → `null`;
`CampaignReward.challengeBadge` → `null` (compound-derived, not shown here);
uncleared side stage → `'Reward: +X …'`; cleared side stage → `'+X …'`. Reads
`GameBalance.salvageRiftGoldBonus` (gold) and
`GameBalance.voidBastionHealthBonus` (HP). Pure.

**Enemy labels — `EnemyArchetype.label`.** Player-facing enemy names already
exist as literals in `GameBalance._enemyLabelForStats` ("Armored Drones",
"Regen Heavy Drones", …) and are what wave previews show. To avoid a parallel
set that would drift from the briefing text, give `EnemyArchetype` an
enhanced-enum `label` (plural, matching today's `_enemyLabelForStats` output
**exactly**) as the single source, and refactor `_enemyLabelForStats`'s nine
archetype branches to return the matching `EnemyArchetype.x.label` (boss
branch unchanged — wave-preview output must not change). `CodexEnemyEntry.label`
then reads `archetype.label`.

## 7. Label & helper extraction

- **`TowerType`**, **`EnemyTrait`**, and **`EnemyArchetype`** become enhanced
  enums with a `const` constructor and a `final String label` field, mirroring
  `TowerSpecialization`/`TowerTargetingMode` (both enhanced enums). All existing enum
  member references (`TowerType.laser`, etc.) remain valid. `EnemyArchetype.label`
  holds the plural player-facing names; `GameBalance._enemyLabelForStats` is
  refactored to return `EnemyArchetype.x.label` for the nine archetypes (§6.3),
  removing its duplicated string literals without changing preview output.
- `towerLabel(TowerType)` / `enemyTraitLabel(EnemyTrait)` are removed from
  `orion_game_page.dart`; call sites use `type.label` / `trait.label`.
- `IconData towerIcon(TowerType)` stays Flutter-dependent, so it moves to
  `lib/game/ui/tower_icons.dart` and is imported by both `orion_game_page.dart`
  and `codex_view.dart`. (Icons must not live on a model enum, which would
  couple the pure model layer to Flutter.)

## 8. Content specification

### 8.1 Towers (8 entries)

Per `TowerType`, header: `towerIcon(type)` + `type.label` + an in-mission
availability line. `towerUnlockWave(type)` is **wave gating within a single
mission** (the wave at which the tower type becomes buildable), not campaign
progression; word it as e.g. `"Available from wave N"` so it is not mistaken
for campaign-stage gating.

**Base stats** (from `towerStats(type, level: 1)`):
- Always shown: Range (`range`), Cost (`cost`), Upgrade cost (`upgradeCost`).
- Damage (`damage`) and Fire interval (`fireInterval`) are shown **only when
  meaningful** — gated on `damage > 0`. Drone Bay has `damage: 0` (it deals
  damage via drones, not a projectile), so its card suppresses both rows and
  shows the drone output below instead of a misleading "Damage 0".

**Specialty stats** (shown only when non-zero / non-default, to keep cards
focused; display is driven by the stat value, not the family):
- Splash radius (`splashRadius`) — e.g. rocket.
- Slow: `(1 - slowMultiplier)` as a %, for `slowDuration` seconds — cryo at
  base; gravity well **only once specialized** (its level-1/2 `slowMultiplier`
  defaults to 1, so this row never appears on the base card).
- Pierce (`pierceCount`) — e.g. railgun.
- Chain (`chainCount` + `chainRange`) — e.g. ion chain.
- Corrosion (`corrosionDamagePerSecond` + `corrosionDuration`) — e.g. nanite.
- Armor shred (`armorShred`) — e.g. nanite.
- Field: radius (`fieldRadius`), duration (`fieldDuration`), **and tick interval
  (`fieldTickInterval`)** — e.g. gravity well. All three are shown so the card
  conveys the field's real damage cadence (a damage tick every
  `fieldTickInterval` for `fieldDuration`), not just its footprint.
- Drones: count (`droneCount`), active cap (`maxActiveDrones`), drone damage
  (`droneDamage`), attack interval (`droneAttackInterval`), and lifetime
  (`droneLifetime`) — e.g. drone bay. The three drone-damage stats are the
  tower's actual output and must appear; they replace the suppressed
  "Damage / Fire interval" base rows.
- Shield bonus (`shieldDamageMultiplier` when `!= 1`), Armor bonus
  (`armorDamageMultiplier` when `!= 1`), Slowed bonus (`slowedDamageMultiplier`
  when `!= 1`).
- Prism split (`prismSplitDamageMultiplier`), Cluster burst
  (`clusterBurstCount`) — surfaced on the relevant specialization cards.

**Specialization cards** (exactly 2 per tower, 16 total): `label`, authored
one-line `description`, and the defining number
from `specializedStats` (format sketch only — e.g. *"Prism Laser — splits to N
targets at X% damage"*; do **not** hardcode magnitudes in the spec, read them
from `specializedStats` at render time so they track live tuning).

**Scope cut (intentional):** level-2 intermediate combat stats are **not**
shown. A tower card covers the level-1 base, the cost to upgrade, and the
level-3 specialized end-state; level 2 is a transient step. Players asking
"what does the first upgrade buy?" see its cost, not a full second stat block.

### 8.2 Enemies (9 archetypes + trait reference)

- Header row: **Traits reference** (5 entries, one per `EnemyTrait`): `label`
  + one-line `effect`. Satisfies "lists enemy traits and explains their
  effects."
- One card per `EnemyArchetype`: `label` + `roleDescription` + Health, Speed,
  Base damage, Reward, plus conditional Shield (`shieldHealth`), Armor
  (`armorReduction`), Regen (`regenPerSecond`). Traits rendered as badges
  (`trait.label`).

### 8.3 Effects (9-entry glossary)

Fixed-order list: `slow`, `corrosion`, `armorShred`, `shieldDamage`, `pierce`,
`chain`, `splash`, `drones`, `gravityField`. Each entry: `title` + authored
mechanic `description` in player language + `relatedSpecializations`
cross-reference. The glossary describes **mechanics**, not per-tower magnitudes
— those live on the tower/specialization cards — so the glossary stays stable as
tuning changes. Where a genuinely global rule exists it may reference a
`GameBalance` constant via the shared formatters.

**Glossary vs. specialization-card split (one rule):** a *base/shared mechanic*
that a tower family produces (splash, slow, chain, pierce, corrosion, drones,
the gravity field) gets a glossary entry; a *spec-only amplifier* (prism split,
cluster burst) is explained only on its specialization card (§8.1). An entry's
`relatedSpecializations` may be empty for a future mechanic with no
specialization tie — the entry still renders. Note: the
`armorDamageMultiplier` / `slowedDamageMultiplier` bonus stats (§8.1) are
explained inline on their specialization cards and deliberately have **no**
glossary entry, matching the issue's fixed 9-effect list.

**`relatedSpecializations` derivation (durable, not a static table).** For each
effect id, derive the set by scanning every `TowerSpecialization.values`'
level-3 `specializedStats` for the field(s) that signal that effect, collected
when non-default — e.g. `slow` ⇔ `slowMultiplier < 1` (cryo + gravity specs),
`corrosion` ⇔ `corrosionDamagePerSecond > 0`, `armorShred` ⇔ `armorShred > 0`,
`shieldDamage` ⇔ `shieldDamageMultiplier != 1`, `pierce` ⇔ `pierceCount > 0`,
`chain` ⇔ `chainCount > 0`, `splash` ⇔ `splashRadius > 0`, `drones` ⇔
`droneCount > 0`, `gravityField` ⇔ `fieldRadius > 0`. Deriving (rather than
tabulating) keeps the cross-refs correct as balance evolves.

### 8.4 Stages (7 entries, full detail)

Per `OrionCampaign.stages`: `name`, `mapLabel`, `description`, status badge
(Locked / Unlocked / Cleared from `progress.statusFor(stage)`), modifier cards
(reusing `StageModifierMetadata.forModifier` for each `stage.modifiers`; if a
stage has no modifiers — e.g. Outpost Alpha — render a single
`StageModifierMetadata.standardConditions` card, matching the existing
next-wave-panel fallback in `orion_game_page.dart`),
`waveCount` (8), side-stage `rewardLabel`, and a main / side marker.

### 8.5 Stat semantics

The codex shows **catalog / base values** read directly from
`GameBalance.towerStats` / `enemyArchetype` — **not** tech-tree-adjusted or
stage-modifier-adjusted effective values. Do **not** wire `TowerStatsResolver`
or `CampaignModifiers` into the codex; it is a stable reference of the base
tuning, intentionally independent of a player's current upgrades or the stage
being played.

## 9. Entry point & UI

### 9.1 Entry point (mirrors Tech Tree wiring)

`WorldMapView` already exposes `VoidCallback? onOpenTechTree` and renders a
header `IconButton` for it, gated by `_isBusy`. The Codex button follows the
same pattern exactly:

- Add `VoidCallback? onOpenCodex` to `WorldMapView`.
- Render an `Icons.menu_book` `IconButton` (tooltip `'Codex'`) in the header
  `Row`, immediately before the Tech Tree button, wrapped in
  `if (onOpenCodex != null)` — exactly like the Tech Tree button's
  `if (onOpenTechTree != null)` guard (`world_map_view.dart`).
- Gate it with `_isBusy` identically to the other header buttons.
- In `OrionGamePage` (the parent that builds `WorldMapView`), mirror the
  `_ShellView.techTree` plumbing exactly:
  - add `_ShellView.codex` to the `_ShellView` enum;
  - add `_openCodex()` / `_closeCodex()` that swap `_activeView` (copying
    `_openTechTree` / `_closeTechTree`);
  - add `case _ShellView.codex:` to the build switch returning `CodexView(
    progress: _progress, onBack: _closeCodex)`;
  - wire `onOpenCodex: _openCodex` into the `WorldMapView` in
    `_buildWorldMapScaffold()`, beside `onOpenTechTree: _openTechTree`.

No `Navigator.push` is involved — the view swap is in-place, identical to the
existing Tech Tree path.

### 9.2 `CodexView`

- `StatefulWidget` (holds the selected section index + a per-section
  `ScrollController`).
- Returns its own `Scaffold` + `SafeArea` (mirroring `TechTreeView`), rendered
  **in-place** by `OrionGamePage`'s build switch (`case _ShellView.codex`) —
  **not** pushed onto the `Navigator`. `CodexView` must therefore **not** rely
  on an `AppBar` default back button, which would pop the entire
  `OrionGamePage` route.
- Header: a `Row` + back `IconButton` wired to a required `VoidCallback onBack`
  (mirroring `TechTreeView`'s header), with title text `'Codex'`.
- Constructor: `CodexView({required CampaignProgress progress, required
  VoidCallback onBack})`. `progress` is the only data input.
- Body: a sticky chip bar (`Towers` / `Enemies` / `Effects` / `Stages`) that
  **selects the active section** (filter), above a scrollable list of that
  section's `Card`s. Tapping a chip swaps which section is rendered — it does
  **not** scroll-jump inside one lazy list, because off-screen slivers in a
  lazy `CustomScrollView` are not built and `Scrollable.ensureVisible` would
  have no target. Filter-per-section also keeps each view short for mobile;
  default selection = Towers.
- Each entry renders as a `Card`; stat rows use a `LayoutBuilder` with the
  width threshold `< 420` (the same idiom `_StageMap` already uses) so
  multi-column stat grids collapse to a single column on narrow widths.
- `CodexView` intentionally takes **no feedback slot**. A campaign save that
  fails while the codex is open sets `_mapFeedback` (see
  `_showCampaignPersistenceFailure`, which branches on `_activeView`); the
  message surfaces when the player backs out to the map. This is acceptable —
  the codex is read-only and triggers no saves itself.
- No async, no network. Empty `progress` ⇒ Outpost Alpha shows **Unlocked**
  (its `unlockDependencies` is empty, so `CampaignProgress.isUnlocked` is
  true) and every other stage shows **Locked** — this is the correct
  `statusFor` result, not a special case.

## 10. Testing

### 10.1 Pure layer — `test/game/codex/codex_data_test.dart`

This is the headline coverage required by the issue.

- `CodexData.towers` has length 8 and covers every `TowerType.values`; each
  entry's `specializations` has length 2 and equals `specializationsFor(type)`.
- Every `CodexSpecializationEntry.description`,
  `CodexEnemyEntry.roleDescription`, `CodexTraitEntry.effect`, and
  `CodexEffectEntry.description` is non-empty (guards against blank copy
  shipping).
- `CodexData.enemies` has length 9 and covers every `EnemyArchetype.values`;
  each entry's `stats` equals `GameBalance.enemyArchetype(archetype)`.
- `CodexData.traits` has length 5 and covers every `EnemyTrait.values`.
- `CodexData.effects` has exactly the 9 expected ids in the fixed order.
- `CodexData.stagesFor(progress)` over `OrionCampaign.stages`: each entry's
  `status` equals `progress.statusFor(stage)` for locked / unlocked / cleared
  samples; `waveCount == stage.waves.length` (not a bare `8`, so it fails
  cleanly if a stage ever diverges); `modifiers` equals
  `[for (final m in stage.modifiers) StageModifierMetadata.forModifier(m)]`,
  and a no-modifier stage yields `[StageModifierMetadata.standardConditions]`.
- Empty-progress invariant: `stagesFor(CampaignProgress())` marks **Outpost
  Alpha as `unlocked`** and every other stage `locked` (guards the §9.2
  default-state claim).
- `relatedSpecializations` per effect is non-empty exactly for the
  specialization values whose level-3 `specializedStats` expose the effect's
  signal field (see §8.3 derivation). Today all 9 effects resolve to ≥ 1
  specialization (e.g. `shieldDamage` → `overloadRelay`; `corrosion` /
  `armorShred` → both nanite specs; `pierce` → both railgun specs) — assert
  all 9 are non-empty (the derivation keeps this self-maintaining as balance
  evolves).

### 10.2 Shared formatters — folded into `codex_data_test.dart`

Assert `percent(0.5) == '50%'`, `number(2.0) == '2'`, `number(2.5) == '2.5'`,
and that `StageModifierMetadata.forModifier` still renders identically after
the helper promotion (its existing test continues to guard this).

### 10.3 Widget — `test/widget/codex_view_test.dart`

- Render `CodexView` with a sample `CampaignProgress`; assert the four section
  headers render and at least one tower label, enemy label, effect title, and
  stage label appear.
- Assert no overflow on a narrow surface (360 × 640).

### 10.4 Label migration

The removed `_towerLabel` / `_enemyTraitLabel` / `_towerIcon` are file-private
top-level functions in `orion_game_page.dart`, so no test outside that file can
reference them (and none inside it do). Verify no test references these symbols
(none are expected); update in-file call sites to `type.label` / `trait.label`
/ `towerIcon(type)`. Enhanced-enum conversion is source-compatible for existing
member references.

### 10.5 Static analysis

Run `flutter analyze` and `dart format .` (per `AGENTS.md`) before landing.
Required for the enhanced-enum conversion, the formatter/helper promotion, and
the label migration to be clean.

## 11. Acceptance-criteria trace

| Issue acceptance criterion | Where |
|---|---|
| Campaign map exposes a Codex entry point | §9.1 (`WorldMapView.onOpenCodex`) |
| Lists all current tower types | §8.1, `CodexData.towers` |
| Lists all current tower specializations | §8.1, `CodexSpecializationEntry` (16) |
| Lists enemy traits and explains their effects | §8.2, `CodexData.traits` + §10.1 |
| Lists combat effects in player-readable language | §8.3, `CodexData.effects` |
| Works on narrow / mobile layouts | §9.2 (`LayoutBuilder` < 420) + §10.3 |
| Tests cover codex data generation for all tower and enemy enum values | §10.1 |

## 12. Risks & notes

- **Authoring volume:** 16 spec blurbs + 9 enemy role lines + 9 effect entries
  + 5 trait effects are the only net-new strings. They are short and reviewed
  for mechanical accuracy against `combat_effects` / `enemy_logic`.
- **`game_models.dart` size:** adding two enum `label` fields is a handful of
  lines and matches existing precedent; the file does not gain presentation
  *logic*, only two `String` constants per enum.
- **Stage status freshness:** `CodexView` receives the `CampaignProgress` that
  the campaign page already holds; it does not read or mutate save state.
