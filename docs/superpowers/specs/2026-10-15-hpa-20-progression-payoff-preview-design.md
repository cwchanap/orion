# HPA-20 — Progression Payoff Preview Design

**Linear:** HPA-20 — Orion: Explain upgrade, specialization, and Salvage Module payoff

## Outcome

Before spending credits or committing to a module, the player can answer **"what changes if I choose this?"** from the surface they are already looking at:

- A Level 1 tower's inspector shows a compact current → Level 2 comparison with the Upgrade action.
- Each Level 2 specialization card shows a one-sentence role and a compact current → candidate comparison.
- Each Salvage Module draft card shows one line of honest current-run context (how many placed towers it touches, or that it pays off later, or nothing extra for economy modules).

This is decision-clarity polish. There is no recommendation, ranking, power score, simulation, board highlight, new module, balance change, or art.

## Existing seams to extend

The ownership already exists; this ticket adds read-side data only.

- **lib/game/rules/tower_stats_resolver.dart** — `TowerStatsResolver.resolve` is the single authority for runtime tower stats (base → campaign → stage → run modules).
- **lib/game/rules/game_session.dart** — `GameSession.resolveTowerStats(tower)` wraps the resolver with this run's campaign modifiers, stage modifiers, and acquired modules. `GameSession.snapshot()` already publishes `selectedTowerStats` through it.
- **lib/game/models/game_models.dart** — `PlacedTower.upgraded()` and `PlacedTower.specialized(spec)` are pure value transforms (they return new instances and validate level/type). `TowerSpecialization` is the canonical specialization enum. `RunModuleDefinition` / `runModuleCatalog` own module data and `effectText`.
- **lib/game/rules/run_module_rules.dart** — `RunModuleRules.applyTowerStats` and the private `_appliesToTower(affinity, type)` predicate decide which towers a module touches.
- **lib/game/codex/codex_data.dart** — `CodexData._specializationDescription(spec)` already holds a one-sentence role for all 16 specializations.
- **lib/game/ui/tower_inspector.dart** — `_ProgressionActions` renders the Upgrade button or the two `_SpecializationCard`s; `_InspectorBody._secondaryLabel/_secondaryValue` already format the four inspector metrics; `TowerStatScale.forType(type).secondaryMetric` picks the tower-specific secondary metric.
- **lib/game/ui/run_module_draft_panel.dart** — `_RunModuleCard` renders title, `effectText`, affinity label, and a combined semantics label.

## 1. Preview stats come from the session's resolver

Add two optional fields to `GameSnapshot`:

```dart
final TowerStats? selectedTowerUpgradeStats;               // non-null only when selectedTower.canUpgrade
final Map<TowerSpecialization, TowerStats> selectedTowerSpecializationStats; // non-empty only when selectedTower.canSpecialize
```

`GameSession.snapshot()` fills them when a tower is selected:

```dart
selectedTowerUpgradeStats: selectedTower != null && selectedTower.canUpgrade
    ? resolveTowerStats(selectedTower.upgraded())
    : null,
selectedTowerSpecializationStats: selectedTower != null && selectedTower.canSpecialize
    ? {
        for (final spec in GameBalance.specializationsFor(selectedTower.type))
          spec: resolveTowerStats(selectedTower.specialized(spec)),
      }
    : const {},
```

Why this shape:

- It goes through `resolveTowerStats`, the same call the real tower uses after the mutation, so campaign upgrades, stage modifiers, and acquired Salvage Modules are reflected automatically. Widgets never compute stats.
- `upgraded()` / `specialized()` return new `PlacedTower` values; the session's `_towersByPosition`, gold, phase, modules, and offers are untouched. Reading a snapshot stays side-effect free.
- It mirrors the existing `selectedTowerStats` field rather than adding a preview API, comparison model, or view-model layer.
- Previews are populated in every phase (read-only info is useful mid-wave); the buttons keep their current phase/affordability gating.

Both fields default to `null` / `const {}` so the 13 existing `GameSnapshot(...)` constructions in lib/test compile unchanged.

## 2. Comparison rows (presentation formatting only)

Inside `tower_inspector.dart`, add a small private helper that turns `(current, candidate, secondaryMetric)` into display rows:

- Candidate metrics, in order: **Damage**, **Fire**, **Range**, and the tower's secondary metric from `TowerStatScale.forType(type).secondaryMetric` when non-null.
- Labels and value formatting reuse `_InspectorBody._secondaryLabel` / `_secondaryValue` and the existing `number` / `cadence` formatters, so preview text matches the live stat readouts exactly (`Fire 0.42s → 0.34s`, `Slow 1.4s → 1.8s`, `Corrosion 4/s → 6/s`).
- A row is shown only when the **formatted** current and candidate strings differ. This hides unchanged values and avoids "18 → 18" rows produced by rounding.
- No aggregate score, percent delta, or colour-coded better/worse judgement. The arrow is neutral.

This is string formatting of two resolved `TowerStats`; it does no combat math. Every specialization in the current balance changes at least Range, so no specialization card ends up with zero rows; if one ever does, the card simply shows the role sentence alone.

The upgrade preview has no role sentence, so it also lists the tower-specific mechanics an upgrade changes after the four metrics: Slow power, Pierce width, Chain range/dmg, Corrode time, Shred, Field radius/time/pulse, and Drones, Max drones, Drone life and Drone fire (e.g. Drone Bay `Drones 2 → 3`, Gravity Well `Field 72 → 86`). Projectile speed is left out as cosmetic. Specialization cards keep the four metrics only; their specialization-only mechanics (prism split, armor/shield damage multipliers, cluster bursts, drone count, field radius) are explained by the role sentence, keeping the cards compact.

## 3. Upgrade preview placement

For `tower.canUpgrade`, `_ProgressionActions` renders a column:

1. `OrionText.micro('UPGRADE - LV ${tower.level + 1}')` header, matching the existing `'SPECIALIZE - LV ${tower.level + 1}'` convention in the same widget.
2. The comparison rows (key `tower-upgrade-preview`), each a single line `Label  current → candidate` in `OrionTypography.readout` at the inspector's existing small sizes.
3. The existing `tower-upgrade` button, unchanged in cost text, enabled state, and callback.

Semantics: the preview is a single `Semantics(container: true, label: 'Upgrade preview. Damage 12 to 18. Fire 0.42 seconds to 0.34 seconds. Range 145 to 160')` with `excludeSemantics: true`, so screen readers say "to" instead of reading an arrow glyph. The button's existing semantics are unchanged.

## 4. Specialization role + preview

### Role sentence: one canonical home

Move the 16 role sentences out of `CodexData._specializationDescription` into the canonical enum as a getter:

```dart
enum TowerSpecialization {
  ...
  String get role => switch (this) { ... same 16 strings ... };
}
```

`CodexData.towerFor` then uses `spec.role` for `CodexSpecializationEntry.description`. The Codex output is byte-identical; the inspector reads the same `spec.role`. No widget-owned copy exists. (Exposing the private Codex helper publicly was considered, but it would make the inspector depend on the Codex layer for core specialization metadata; the enum is the data's natural owner, next to `label`.)

### Card content

`_SpecializationCard` gains `currentStats` and `candidateStats` inputs and renders, in order:

1. Existing sprite, label, and cost (unchanged).
2. `specialization.role` in `OrionTypography.microLabel(size: 9, color: textMuted)`, centered, no `maxLines` cap so it never truncates.
3. Comparison rows (key `tower-specialization-preview-${spec.name}`), same helper as the upgrade preview.

The two cards stay side by side in the existing `Row`/`Expanded` layout; the inspector body already scrolls (`tower-inspector-scroll`) inside a height-capped sheet, so taller cards scroll rather than overflow.

Semantics: the card's existing button semantics label grows from `'Pulse Laser 90'` to `'Pulse Laser 90. Maximized fire rate for concentrated single-target damage. Fire 0.34 seconds to 0.24 seconds. Range 160 to 165'`. The key, `button`, `enabled`, and `onTap` stay as they are.

### Inputs

`_ProgressionActions` reads `snapshot.selectedTowerSpecializationStats[spec]` for each card and `snapshot.selectedTowerStats` as "current". If either is null (e.g. a test snapshot without previews), the card renders exactly as today minus the rows, and still shows the role sentence.

## 5. Salvage Module beneficiary context

### Rules: count with the same predicate the stats use

In `run_module_rules.dart`:

- Make the affinity predicate public as `RunModuleRules.appliesToTower(RunModuleAffinity, TowerType)` and keep `applyTowerStats` using it, so counting and applying can never disagree.
- Add `RunModuleRules.beneficiaryCount(RunModuleDefinition, Iterable<PlacedTower>) → int`: the number of placed towers the module's affinity applies to, or `0` for a module that does not affect tower stats.

In `game_models.dart`, add `RunModuleDefinition.affectsTowerStats` — true when any of the stat multipliers ≠ 1 or `slowDurationBonus` ≠ 0. Emergency Salvage is the only current module where this is false.

### Snapshot

Add `final Map<RunModuleId, int> pendingRunModuleBeneficiaries` (default `const {}`) to `GameSnapshot`. `GameSession.snapshot()` fills it only while `_pendingRunModuleOffer != null`, one entry per offered id, using `beneficiaryCount(definition, towers)`.

### Wording (draft panel)

`RunModuleDraftPanel` takes a `beneficiaries` map (passed from `snapshot.pendingRunModuleBeneficiaries` in `orion_game_page.dart`). `_RunModuleCard` adds one line under the affinity label:

| Module kind | Count | Line |
|---|---|---|
| `!affectsTowerStats` (economy) | — | no extra line; `effectText` already says "Gain 90 gold immediately." |
| universal | n ≥ 1 | `Affects your n placed tower(s)` |
| universal | 0 | `Affects every tower you build` |
| affinity (Cryo/Rocket) | n ≥ 1 | `Affects your n placed Cryo tower(s)` |
| affinity | 0 | `Benefits Cryo towers you build later` |

The affinity name comes from `RunModuleAffinity.label`. Singular/plural is handled in the wording helper. Nothing compares modules with each other, sorts them, or marks any as "best". The offer order from `ModuleOfferPicker` is unchanged.

The card's semantics label appends the same line: `'Cryo Reservoir. Cryo slows last 0.6 seconds longer. Affinity: Cryo. Benefits Cryo towers you build later'`.

The wording helper is a small private function in `run_module_draft_panel.dart`; it formats a count and an affinity label and does no game logic.

## Out of scope (unchanged)

- Upgrade/specialize/module-selection mutation paths, costs, affordability checks, phase gating.
- `_moduleCandidates`, `ModuleOfferPicker`, and offer eligibility.
- Post-selection board highlights, new Codex sections, recommendations, power scores, DPS/clear predictions, analytics, new modules, balance tuning, new art.
- A generic stat-comparison or view-model framework.

## Validation

Pure logic (`test/game/`):

- `game_session_test.dart`: with a non-empty campaign modifier, a stage modifier, and an acquired module, `snapshot(selectedTower: l1).selectedTowerUpgradeStats` equals `resolveTowerStats` of the tower after a real `upgradeTower`; likewise each `selectedTowerSpecializationStats[spec]` equals the real resolved stats after `specializeTower(spec)` on a fresh session.
- Reading `snapshot()` with previews leaves `gold`, `towers`, `acquiredRunModules`, `pendingRunModuleOffer`, and `phase` identical.
- Previews are absent/empty for a Level 3 tower and for no selection; upgrade preview absent at Level 2, specialization map empty at Level 1.
- `run_module_rules_test.dart`: `beneficiaryCount` for universal (counts all), affinity with matches, affinity with zero matches, and economy (0); `applyTowerStats` results unchanged.
- `pendingRunModuleBeneficiaries` populated only while an offer is pending and keyed exactly by the offered ids.
- `codex_data_test.dart`: Codex descriptions still non-empty and equal `spec.role`.

Widgets (`test/widget/`):

- `tower_inspector_test.dart`: L1 tower shows `tower-upgrade-preview` with only changed rows and the existing upgrade button/cost; L2 cards show role + preview rows; unchanged rows hidden; semantics labels as above; existing tests stay green; no overflow at 360×640 and 390×844.
- `run_module_draft_panel_test.dart`: each wording row in the table; economy card has no context line; semantics labels; still no overflow at 360×640; selection callback unchanged.

Gates: focused tests, `flutter analyze`, `dart format --set-exit-if-changed .`, full `flutter test`.

## Acceptance mapping

| Acceptance criterion | Where |
|---|---|
| L1 shows current → L2 comparison | §1, §3 |
| Specialization role + changes | §1, §4 |
| Reuses authoritative resolver | §1 (`resolveTowerStats`) |
| Reuses existing description metadata | §4 (`TowerSpecialization.role`, Codex reads it) |
| Module cards: concise context, no ranking | §5 |
| Mutation/picker unchanged | Out of scope list; regression tests |
| No board highlight / new modules / balance / art | Out of scope list |
| Tests, analyze, full suite | Validation |
| One PR | Plan |
