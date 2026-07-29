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
| Label home | Enhanced-enum `label` on `TowerType` / `EnemyTrait` (idiomatic) | Matches existing precedent (`TowerSpecialization.label`, `TowerTargetingMode.label`, `StageMedal.label`). Only Flutter-dependent `towerIcon` stays a UI helper. |
| Bosses | Excluded from v1 | Spoilers; see Non-goals. |

## 5. Architecture

New code lives under `lib/game/codex/` (pure presentation model — no Flutter) and
`lib/game/ui/` (view + the one Flutter-dependent helper). Edits are minimal.

### 5.1 File layout

```
lib/game/
  models/game_models.dart     [edit]  add `label` to TowerType + EnemyTrait (enhanced enums)
  ui/tower_icons.dart         [new]   IconData towerIcon(TowerType) — moved from orion_game_page._towerIcon
  codex/codex_data.dart       [new]   PURE presentation value types + CodexData façade (reads GameBalance)
  codex/codex_format.dart     [new]   shared percent/number formatters (promoted from StageModifierMetadata._percent/_number)
  ui/codex_view.dart          [new]   Flutter widget: full-screen codex page
  ui/orion_game_page.dart     [edit]  drop _towerLabel/_enemyTraitLabel/_towerIcon; use enum.label + towerIcon
  ui/world_map_view.dart      [edit]  add onOpenCodex callback + IconButton in the header row
```

### 5.2 Layering

```
GameBalance / enums (source of truth, unchanged tuning)
        │  reads constants + enum values
        ▼
codex/codex_data.dart   (PURE: value types + CodexData factories)   ◄── CampaignProgress (for stage status only)
        │  consumed by
        ▼
ui/codex_view.dart      (Flutter: renders cards)
        ▲  opened from
        │
ui/world_map_view.dart  (campaign map header button)
```

The pure / Flame-free boundary the repo deliberately maintains is preserved:
`codex_data.dart` imports only `game_models.dart`, `campaign_progress.dart`,
`stage_definition.dart`, `stage_modifier_metadata.dart`, and `codex_format.dart`.
No `package:flutter`, no `package:flame`.

## 6. Data model (`codex/codex_data.dart`)

All types are `const` and immutable. Numbers are pulled from `GameBalance` /
enums at construction time; prose fields are authored strings.

### 6.1 Value types

```dart
class CodexTowerEntry {
  final TowerType type;
  final String label;                 // TowerType.label
  final int unlockWave;               // GameBalance.towerUnlockWave(type)
  final TowerStats baseStats;         // GameBalance.towerStats(type, level: 1)
  final int upgradeCost;              // baseStats.upgradeCost (1 -> 2)
  final List<CodexSpecializationEntry> specializations; // exactly 2
}

class CodexSpecializationEntry {
  final TowerSpecialization specialization;
  final String label;                 // specialization.label (enum)
  final int specializationCost;       // GameBalance.towerStats(type, level: 2).specializationCost (2 -> 3)
  final TowerStats specializedStats;  // GameBalance.towerStats(type, level: 3, specialization: spec)
  final String description;           // authored one-line blurb
}

class CodexEnemyEntry {
  final EnemyArchetype archetype;
  final String label;                 // authored (e.g. "Armored Drone")
  final EnemyStats stats;             // GameBalance.enemyArchetype(archetype)
  final List<EnemyTrait> traits;      // stats.traits, deterministic order (enum order)
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
  final String? rewardLabel;          // side-stage reward, mirrors world_map_view._rewardLabel
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

### 6.3 Shared formatters (`codex/codex_format.dart`)

Promote the private `_percent` / `_number` helpers currently inside
`StageModifierMetadata` into `codex_format.dart` so both
`StageModifierMetadata` and `CodexEffectEntry` share one formatting path.
`StageModifierMetadata` is updated to call the shared helpers (behaviour
unchanged; its existing test guards this).

## 7. Label & helper extraction

- **`TowerType`** and **`EnemyTrait`** become enhanced enums with a `const`
  constructor and a `final String label` field, mirroring
  `TowerSpecialization`/`TowerTargetingMode`/`StageMedal`. All existing enum
  member references (`TowerType.laser`, etc.) remain valid.
- `towerLabel(TowerType)` / `enemyTraitLabel(EnemyTrait)` are removed from
  `orion_game_page.dart`; call sites use `type.label` / `trait.label`.
- `IconData towerIcon(TowerType)` stays Flutter-dependent, so it moves to
  `lib/game/ui/tower_icons.dart` and is imported by both `orion_game_page.dart`
  and `codex_view.dart`. (Icons must not live on a model enum, which would
  couple the pure model layer to Flutter.)

## 8. Content specification

### 8.1 Towers (8 entries)

Per `TowerType`, header: `towerIcon(type)` + `type.label` + `"Unlocks wave
${towerUnlockWave(type)}"`.

**Base stats** (from `towerStats(type, level: 1)`), always shown:
- Damage (`damage`), Range (`range`), Fire interval (`fireInterval`, seconds),
  Cost (`cost`), Upgrade cost (`upgradeCost`).

**Specialty stats** (shown only when non-zero / non-default, to keep cards
focused):
- Splash radius (`splashRadius`) — rocket family.
- Slow: `(1 - slowMultiplier)` as a %, for `slowDuration` seconds — cryo family.
- Pierce (`pierceCount`) — railgun family.
- Chain (`chainCount` + `chainRange`) — ion chain family.
- Corrosion (`corrosionDamagePerSecond` + `corrosionDuration`) — nanite family.
- Armor shred (`armorShred`) — nanite family.
- Field radius / duration (`fieldRadius` + `fieldDuration`) — gravity well.
- Drones (`droneCount` + `maxActiveDrones`) — drone bay.
- Shield bonus (`shieldDamageMultiplier` when `!= 1`), Armor bonus
  (`armorDamageMultiplier` when `!= 1`), Slowed bonus (`slowedDamageMultiplier`
  when `!= 1`).
- Prism split (`prismSplitDamageMultiplier`), Cluster burst
  (`clusterBurstCount`) — surfaced on the relevant specialization cards.

**Specialization cards** (exactly 2 per tower, 16 total): `label`,
`specializationCost`, authored one-line `description`, and the defining number
from `specializedStats` (e.g. "Prism Laser — splits to 2 extra targets at 60%
damage").

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

### 8.4 Stages (7 entries, full detail)

Per `OrionCampaign.stages`: `name`, `mapLabel`, `description`, status badge
(Locked / Unlocked / Cleared from `progress.statusFor(stage)`), modifier cards
(reusing `StageModifierMetadata.forModifier` for each `stage.modifiers`),
`waveCount` (8), side-stage `rewardLabel`, and a main / side marker.

## 9. Entry point & UI

### 9.1 Entry point (mirrors Tech Tree wiring)

`WorldMapView` already exposes `VoidCallback? onOpenTechTree` and renders a
header `IconButton` for it, gated by `_isBusy`. The Codex button follows the
same pattern exactly:

- Add `VoidCallback? onOpenCodex` to `WorldMapView`.
- Render an `Icons.menu_book` `IconButton` (tooltip `'Codex'`) in the header
  `Row`, immediately before the Tech Tree button.
- Gate it with `_isBusy` identically to the other header buttons.
- The parent that builds `WorldMapView` wires `onOpenCodex` to open
  `CodexView`, using the same navigation mechanism it already uses for
  `onOpenTechTree`.

No new navigation mechanism is introduced.

### 9.2 `CodexView`

- `StatefulWidget` (holds a `ScrollController` for section-jump only).
- `Scaffold` + `AppBar(title: const Text('Codex'))` with the default back
  button.
- Constructor: `CodexView({required CampaignProgress progress})`. `progress` is
  the only runtime input.
- Body: a sticky chip bar (`Towers` / `Enemies` / `Effects` / `Stages`) above a
  single lazy `CustomScrollView` of `Card`s. Tapping a chip scrolls to that
  section.
- Each entry renders as a `Card`; stat rows use a `LayoutBuilder` with the
  width threshold `< 420` (the same idiom `_StageMap` already uses) so
  multi-column stat grids collapse to a single column on narrow widths.
- No async, no network. Empty `progress` ⇒ every stage shows **Locked** (the
  correct default, not an error state).

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
  samples; `waveCount == 8`; `modifiers` equals
  `[for (final m in stage.modifiers) StageModifierMetadata.forModifier(m)]`.

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

Update any test that referenced the removed private
`_towerLabel` / `_enemyTraitLabel` / `_towerIcon` to use `type.label` /
`trait.label` / `towerIcon(type)`. (No public API change is expected to break
otherwise; enhanced-enum conversion is source-compatible for existing member
references.)

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
