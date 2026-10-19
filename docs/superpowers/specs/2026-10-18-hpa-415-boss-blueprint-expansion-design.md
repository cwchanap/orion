# HPA-415 — Boss Blueprint Expansion Design

**Linear:** [HPA-415](https://linear.app/cwchanap/issue/HPA-415/orion-give-every-boss-a-blueprint-module) · **Parent:** HPA-303 · **Status:** design proposed for review

## Decision

Extend the existing Salvage Module reward loop from **one** blueprint to **one blueprint for each of Orion's seven bosses**, with **six new family-affinity modules** (catalog: seven → thirteen). Do this inside the existing module catalog, pure stat resolver, campaign stage definitions, and three existing presentation surfaces.

**Do not build a blueprint subsystem.** No new persistence, save migration, reward registry, event bus, custom effect pipeline, module rarities, draft weighting/pity, Codex section, art, or SFX. This ticket is one implementation PR; the design-and-plan draft PR becomes that same implementation PR.

## Why this slice

HPA-412 (first-mission guidance) is complete. HPA-303 explicitly orders HPA-415 next; it has no blockers. The gameplay gap is concrete: six boss victories currently unlock no module, and six tower families have no dedicated module.

Existing code already gives us:
- `runModuleCatalog` / `RunModuleDefinition` in `lib/game/models/game_models.dart`.
- `RunModuleUnlocks.availableFor(CampaignProgress)` currently gates Relay Calibration from an Alpha-only map; move that one reward fact onto `StageDefinition`, which already stores stage rewards.
- `RunModuleRules.applyTowerStats` as the sole stat-applying seam after campaign and stage modifiers.
- `GameSession._moduleCandidates`: eligible + not acquired; family matching first, unlocked family fallback when fewer than 3, then remaining candidates.
- `OrionGamePage._committedProgress` and `_missionPriorResult`, including pending/saved/failed Mission Report handling and new-attempt refresh.
- Existing blueprint glyph/row, briefing intel row, and `MissionRewardFact` presentation from HPA-528.

## Fixed stage → module contract

The existing Outpost Alpha → Relay Calibration blueprint remains unchanged: Universal; +8% range, -8% attack interval. Add the following six:

| Stage / boss | Module (proposed player-facing name) | Family | Effect | Existing/new scalar seam |
| --- | --- | --- | --- | --- |
| Nebula Relay / Shield Matriarch | **Relay Arc** | Ion Chain | Arc chains to **1 more target** | `chainCountBonus: 1` (new) |
| Salvage Rift / Swarm Queen | **Salvaged Drones** | Drone Bay | Drone attacks deal **20% more damage** | `damageMultiplier: 1.20` (existing; `droneDamage`) |
| Asteroid Foundry / Armored Excavator | **Foundry Nanites** | Nanite | Impact and corrosion damage rise **20%** | `damageMultiplier: 1.20` (existing) |
| Aurora Gate / Regen Warden | **Aurora Focus** | Laser | Attack interval falls **12%** | `fireIntervalMultiplier: 0.88` (existing) |
| Void Bastion / Siege Carrier | **Siege Rounds** | Railgun | Shots pierce **1 additional target** | `pierceCountBonus: 1` (new) |
| Singularity Core / Singularity Core | **Gravity Echo** | Gravity Well | Field radius grows **15%** | `fieldRadiusMultiplier: 1.15` (new) |

These are initial restrained tuning values, not a promise of perfect balance. Keep old seven definitions and values intact; resist a simultaneous campaign rebalance. If a human playthrough reveals a concrete dominating or dead option, record a focused follow-up rather than inventing a broader framework here.

The three new module scalar fields are deliberately specific to real resolved `TowerStats` fields. Add `chainCount` and `pierceCount` to `TowerStats.copyWith`; `fieldRadius` already exists. No new fields in `TowerStats` itself. Multipliers compose in the current resolution order: base → campaign → stage → run modules. In particular, Gravity Echo grows the **post-modifier** Gravity Well radius.

Names, copy, and values are pinned here for the first implementation. If existing game terminology requires a minor wording change, keep the exact mathematical effect/test expectation.


## Module catalog and rule ownership

Eliminate the parallel `RunModuleAffinity` enum: once all six families are added, its cases simply duplicate `TowerType`. In `RunModuleDefinition`, replace `affinity` with `TowerType? tower` (null = Universal) and `String get affinityLabel => tower?.label ?? 'Universal'`.

- The four initially universal modules and Relay Calibration set `tower: null` (by default); Cryo Reservoir and Rocket Fusing use their existing `TowerType` cases; the six new entries use their respective tower types.
- Add six `RunModuleId` cases and six catalog entries, retaining the existing seven module effects and names. Extend exhaustive `effectText`; the definition's affinity label comes from `TowerType.label` rather than a second enum.
- Add only `chainCountBonus`, `pierceCountBonus`, and `fieldRadiusMultiplier` to `RunModuleDefinition`, with neutral defaults (0, 0, 1), and include them in `affectsTowerStats`.
- Add nullable `chainCount` and `pierceCount` overrides to `TowerStats.copyWith`; `fieldRadius` is already supported. Do not add new `TowerStats` fields.
- `RunModuleRules` matches a tower using `definition.tower == null || definition.tower == stats.type`, applying existing damage, range, and interval seams plus the three narrow scalars. `beneficiaryCount` must use that same equality.
- Delete `GameSession._affinityTower`; `_moduleCandidates` reads `definition.tower` directly, preserving its current candidate-selection order and fallbacks.
- Update the four `.affinity.label` usages in `run_module_draft_panel.dart` and `acquired_run_module_control.dart` to `.affinityLabel`, and the draft's Universal branch to `definition.tower == null`. Preserve the existing text and semantics.

There are **five** universal definitions after expansion (four ungated at a fresh save and Relay Calibration after Alpha), but a specific unplaced family is **not guaranteed** a card merely because it is eligible. Keep the existing order: universal + matching placed families first, then unlocked-family fallback only if fewer than three candidates remain, then any remaining eligible module. An unplaced family's module **may** therefore be a fallback when candidates would otherwise be too few. Do not force offers or change `ModuleOfferPicker`.

Late Gravity Well (wave 5) and Drone Bay (wave 6) are valid draft-3 candidates **when built**; test the eligibility and candidate list, not a guaranteed random offer.

## One unlock source, seven rewards

Put blueprint ownership directly on `StageDefinition`, alongside its existing optional `CampaignReward`:

```dart
final RunModuleId? blueprint; // nullable for lightweight test stages
```

Declare `blueprint: RunModuleId.<id>` once on each of the seven real stages in `OrionCampaign.stages`, including Outpost Alpha's existing Relay Calibration. Remove `RunModuleUnlocks._unlockStageByModule` rather than keeping two sources. Do **not** add a stage-ID-to-module lookup helper.

`RunModuleUnlocks.availableFor(progress)` derives the locked module set from `OrionCampaign.stages` and returns catalog IDs that are ungated or whose owning stage has `progress.isCleared(stage.id)`. `RunModuleUnlocks.baseModules` still derives from empty progress. The world map and briefing already receive a `StageDefinition`; the Mission Report obtains its stage through `OrionCampaign.stageById(_missionStageId)` when the ID is non-null. Neither UI widget maintains another ownership table.

One invariant test iterates `OrionCampaign.stages`: seven distinct non-null blueprints, all present in the unique catalog and each mapped once. Retain a separate `CampaignReward` on Salvage Rift and Void Bastion; blueprint and campaign reward are independent.

This preserves current semantics without new persistence:
- no blueprint is offered before its stage has a **successfully committed** clear;
- eligibility freezes at attempt start and refreshes only on next launch / same-game Replay;
- failed save and retry don't confer early ownership;
- campaign reset clears derived eligibility.

Avoid a new registry, ownership collection, per-stage duplicate strings, save migrations, or backward-compatibility paths.

## Presentation (existing widgets only)

**World map — `world_map_view.dart`**
- Every real stage node with `stage.blueprint` gets the existing `Icons.memory_rounded` glyph and `Blueprint • Locked / Recovered` label. Delete `_IllustratedStageNode.blueprintRecovered` entirely: `status == StageProgressStatus.cleared` already expresses its committed-clear state.
- Retain the separate side-stage `CampaignReward` glyph (gold/health) where one exists: a side-stage victory may now earn **both** a campaign stat reward and a blueprint.
- Extend the existing small row, tooltip, and semantics; do not change sector node geometry globally or create a new map component. Check glyph legibility on optional-stage nodes that already have a reward glyph.

**Stage briefing — `stage_briefing_sheet.dart`**
- Before first clear, show a compact locked teaser with **module name and exact effect**, resolved via `runModuleDefinition(stage.blueprint!)`, so the boss reward is knowable before deploying.
- After clear, show the same name/effect with `Recovered` status. Keep the existing `BEST RESULT` and optional-stage `SALVAGE` rows separate.
- `StageBriefingSheet.result` is already sourced from `_committedProgress` by `OrionGamePage`; use this, not speculative/uncommitted run state.
- Reuse `_BriefingIntelRow` and scroll behavior; no new page or hero art.

**Mission Report — `orion_game_page.dart`**
- Generalize `_missionRewardFact()` from the Alpha-only case by resolving the current stage's `StageDefinition.blueprint` via `OrionCampaign.stageById` and `runModuleDefinition`.
- Show `Blueprint recovery pending` / `Blueprint recovered: <name>` / `Blueprint not recovered` with the same saved/failed retry behavior as HPA-528.
- Guard on captured `_missionPriorResult == null`; already-cleared replay, later medal improvement, and loss do not falsely celebrate first recovery.
- Keep `MissionRewardFact` and `mission_report_panel.dart` unchanged unless a specific measured layout failure appears.

Draft cards gain the six affinity labels and effect copy from the existing catalog; do not change picker UI.

## Acceptance and validation

1. Catalog has exactly 13 unique IDs; all seven real `StageDefinition` values have distinct valid blueprints, with no parallel stage map. Base pool stays the six original ungated modules.
2. Each of the six new modules only affects its intended family and existing specializations, at correct effective values. Unrelated stats/families are unchanged; beneficiaries and draft labels follow the same `TowerType? tower` field. Existing catalog-wide `affectsTowerStats` guard stays green.
3. An isolated committed stage clear unlocks **only** its stage-specific module; prior progress remains valid, save failure changes nothing, reset removes unlocks. Same-game Replay reads refreshed committed eligibility.
4. Existing draft order, universal-first preference, fallback and selection behavior remain intact. Cover all six new family candidates (plus Cryo and Rocket) with a table-driven check, including late wave-6 builds; never assert an unplaced module is excluded when fallback allows it, or that a random card is guaranteed.
5. All seven map nodes, locked/recovered briefing copy, and three Mission Report save states work with long module names and optional-stage dual rewards at **360×640**.
6. Focused pure tests, relevant widget tests, `flutter analyze`, full `flutter test`, and one real-device pass of at least an early stage and a late-family draft are complete.

## Out of scope

No new art, glyph asset, SFX, boss encounter/balance changes, Codex page, rarity, reroll, alternative currency, permanent power treadmill, new persisted unlock records, migration, forced family offers, or preemptive abstractions. Pre-release project: no backward-compatibility work for save schema changes that are not needed.
