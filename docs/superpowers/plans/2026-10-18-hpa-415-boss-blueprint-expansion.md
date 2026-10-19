# HPA-415 — Boss Blueprint Expansion Implementation Plan

> **One Linear ticket, one PR.** This draft begins with spec + plan; add implementation and tests **to this same PR** before marking ready for review. Work in small green commits on this branch. No separate design, implementation, or art PR.

**Linear:** [HPA-415](https://linear.app/cwchanap/issue/HPA-415/orion-give-every-boss-a-blueprint-module)

**Design authority:** [HPA-415 design](../specs/2026-10-18-hpa-415-boss-blueprint-expansion-design.md)

**Goal:** Seven bosses → seven unique, committed-clear-gated blueprint modules; catalog grows from 7 to 13 and the existing map, briefing, report, and draft surfaces communicate them.

**Architecture:** Reuse `runModuleCatalog`, `RunModuleUnlocks`, `RunModuleRules`, `GameSession._moduleCandidates`, `StageDefinition`, and the HPA-528 committed-progress/replay/report flow. Store family affinity as `TowerType?` and blueprint ownership on the owning stage rather than maintaining parallel enums or stage maps. Exactly three focused new module-definition scalars. No new services, packages, assets, sound, persistence, or picker behavior.

## Baseline/code facts verified

- `RunModuleUnlocks.availableFor` currently filters catalog IDs using a private Alpha-only map. This plan **removes** that map and instead reads `StageDefinition.blueprint` from `OrionCampaign.stages`, where stage reward metadata already lives.
- `TowerStats.copyWith` already exposes `fieldRadius` but not `chainCount` or `pierceCount`.
- `RunModuleRules.applyTowerStats` already applies damage to direct, corrosion, and drone stats; it lacks the three identity scalars. The old `RunModuleAffinity` repeats `TowerType` names, with two mapping switches that can be deleted.
- `GameSession._moduleCandidates()` honors eligible modules and existing placed/unlocked family preference; no picker changes required.
- `OrionGamePage._showStageBriefing()` passes committed stage results; `_missionRewardFact()` is currently Alpha-only; same-game Replay already refreshes `availableRunModules`.
- `WorldMapView` currently passes an Alpha-wide `blueprintRecovered` boolean into nodes; remove that parameter and derive recovered status from the node's existing `StageProgressStatus`. `StageBriefingSheet` has an Alpha-only post-clear row; both need per-stage generalization.
- Existing tests in `test/widget_test.dart` already exercise delayed save, failed save, Retry Save, and same-game Replay for Alpha. Extend the pattern rather than building new helpers/frameworks.


## Expected file map

**Modify (rules/catalog/campaign):**
- `lib/game/models/game_models.dart` — six module IDs, catalog/effect copy, three narrow scalars, `TowerType? tower` replacing `RunModuleAffinity`, `affinityLabel`, `affectsTowerStats`, and `TowerStats.copyWith` chain/pierce overrides.
- `lib/game/campaign/stage_definition.dart` — optional `RunModuleId? blueprint` beside the existing campaign reward.
- `lib/game/campaign/orion_campaign.dart` — assign one blueprint directly to each of seven campaign stages.
- `lib/game/rules/run_module_unlocks.dart` — derive eligible catalog IDs from `OrionCampaign.stages`; delete the private module→stage map; no inverse helper.
- `lib/game/rules/run_module_rules.dart` — three scalar applications and nullable-`TowerType` matching.
- `lib/game/rules/game_session.dart` — delete `_affinityTower`; read `definition.tower` without changing candidate order or fallback.

**Modify (presentation):**
- `lib/game/ui/world_map_view.dart` — remove `blueprintRecovered`; derive per-node state from existing stage + status.
- `lib/game/ui/stage_briefing_sheet.dart` — locked/recovered blueprint teaser + exact effect from `stage.blueprint`.
- `lib/game/ui/orion_game_page.dart` — use `OrionCampaign.stageById(...).blueprint` for generic first-clear Mission Report reward fact.
- `lib/game/ui/run_module_draft_panel.dart` and `lib/game/ui/acquired_run_module_control.dart` — swap legacy `.affinity.label` sites to `definition.affinityLabel` and the Universal condition to `definition.tower == null`, preserving player copy.

**Modify (tests):**
- `test/game/orion_campaign_test.dart`
- `test/game/run_module_unlocks_test.dart`
- `test/game/module_offer_picker_test.dart`
- `test/game/run_module_rules_test.dart`
- `test/game/tower_stats_resolver_test.dart`
- `test/game/game_session_test.dart`
- `test/game/game_balance_test.dart`
- `test/widget/run_module_draft_panel_test.dart`
- `test/widget/acquired_run_module_control_test.dart`
- `test/widget/stage_briefing_sheet_test.dart`
- `test/widget/world_map_command_deck_test.dart` (dedicated world-map blueprint semantics regression)
- `test/widget_test.dart` (report, save/replay/reset integration)

No new runtime files anticipated; the existing rules, stage data and widgets provide the seams.

---


## Task 1 — Pin catalog, family matching, and resolved effects

**Tests first:**
- `module_offer_picker_test.dart`: all 13 `RunModuleId` entries are unique in the catalog, with the expected old module values unchanged; picker behavior stays unchanged.
- `run_module_rules_test.dart`: each new module changes **only** its intended tower family across Level 1, Level 2 and both Level 3 specializations; assert concrete scalar deltas and no unrelated stat change. Retain the existing catalog-wide `only Emergency Salvage leaves tower stats unchanged` guard — it already catches a missing `affectsTowerStats` branch for every new scalar.
- `run_module_rules_test.dart`: one table-driven `beneficiaryCount` check for **all eight** family modules (Cryo, Rocket, and the six new ones), asserting one matching placed tower counts as 1 and one unrelated tower counts as 0; keep the existing economy/universal tests. No separate three-test suite for count-bonus modules.
- `tower_stats_resolver_test.dart`: base → campaign → stage → module composition, particularly amplified gravity + Gravity Echo.
- `game_balance_test.dart`: `TowerStats.copyWith` changes only the requested `chainCount`/`pierceCount` values and leaves baseline stats stable.

**Implementation:**
1. Replace `RunModuleDefinition.affinity: RunModuleAffinity` with optional `TowerType? tower` (null = Universal) and `affinityLabel => tower?.label ?? 'Universal'`; delete the redundant `RunModuleAffinity` enum entirely. Convert existing Cryo/Rocket module definitions to their matching `TowerType`; other existing modules stay universal.
2. Add six `RunModuleId` cases: `relayArc`, `salvagedDrones`, `foundryNanites`, `auroraFocus`, `siegeRounds`, `gravityEcho`. Add definitions matching the spec:
   - Relay Arc: Ion Chain, `chainCountBonus: 1`.
   - Salvaged Drones: Drone Bay, `damageMultiplier: 1.20` (`droneDamage`).
   - Foundry Nanites: Nanite, `damageMultiplier: 1.20` (impact and corrosion).
   - Aurora Focus: Laser, `fireIntervalMultiplier: 0.88`.
   - Siege Rounds: Railgun, `pierceCountBonus: 1`.
   - Gravity Echo: Gravity Well, `fieldRadiusMultiplier: 1.15`.
3. Add just three scalar fields to `RunModuleDefinition` (neutral defaults: 0, 0, 1); extend exhaustive `effectText` and `affectsTowerStats`. Add nullable overrides for `chainCount` and `pierceCount` to `TowerStats.copyWith` (existing `fieldRadius` is reused).
4. Extend `RunModuleRules.applyTowerStats` with the three scalar applications. Match via `definition.tower == null || definition.tower == stats.type` (or one tiny shared predicate where reused by `beneficiaryCount`). No parallel enum/switches and no combat component/targeting-path edits.
5. Replace the four `.affinity.label` reads in the draft and acquired UI with `affinityLabel`, the Universal comparison with `definition.tower == null`, and the one `RunModuleAffinity.universal` expectation in `game_session_test.dart` with `definition.tower == null`. Run existing draft/acquired UI regressions to keep labels and semantics unchanged.
6. Run `dart format` on touched Dart files and focused rule/catalog + draft UI tests.

**Review guardrails:** +1 `chainCount` and `pierceCount` add **one target** (both counts include the first hit). `fieldRadiusMultiplier` operates on the stage-adjusted radius. Family matching is derived from the existing `TowerType` rather than a second type system. Keep Level-1 count bonuses at +1 for now, but prioritize their relative strength in the human playtest (Ion Chain 3 → 4, Railgun 2 → 3).


## Task 2 — Put blueprint metadata on campaign stages; preserve run candidates

**Tests first (`orion_campaign_test.dart` and `run_module_unlocks_test.dart`):**
- Pin the **exact** seven stage ID → blueprint ID pairs from the design table, not merely distinct counts.
- All seven `OrionCampaign.stages` have a non-null unique blueprint that exists exactly once in `runModuleCatalog`. The `StageDefinition` fixture default stays `null` for unrelated test stages.
- Empty committed progress → six normal ungated modules. Clearing each stage in isolation adds **only** its blueprint; multiple clears union eligibility; resetting to empty progress removes unlocks.

**Implementation:**
1. Add nullable `RunModuleId? blueprint` to `StageDefinition` (no required fixture changes). In `OrionCampaign.stages`, set seven `blueprint:` properties: Alpha → Relay Calibration; Nebula Relay → Relay Arc; Salvage Rift → Salvaged Drones; Asteroid Foundry → Foundry Nanites; Aurora Gate → Aurora Focus; Void Bastion → Siege Rounds; Singularity Core → Gravity Echo. Keep existing `CampaignReward` on both side stages.
2. Rewrite `RunModuleUnlocks.availableFor(progress)` to derive blueprint gating from these stages and the catalog. Delete `_unlockStageByModule`. Do **not** implement `blueprintForStage` or a replacement hand-maintained stage map.
3. Delete `GameSession._affinityTower`; inside the **existing** `_moduleCandidates` use `definition.tower`. Preserve eligible/not-acquired filtering, universal or placed-family priority, unlocked-family fallback when fewer than three candidates remain, and final remaining-candidate fallback. Keep `ModuleOfferPicker` unchanged.
4. Confirm same-game `restart(availableRunModules: ...)` already refreshes from committed progress; change lifecycle code only for a reproduced regression.

**Candidate tests (`game_session_test.dart`):**
- Use one table-driven test over all eight tower-family modules. Build the matching family at its **first legal wave**, progress to an appropriate scheduled draft (2, 4, or 6), then assert the already-eligible module appears in the recording picker's **candidate set**. This includes Gravity Well after wave 5 and Drone Bay after wave 6.
- For an **unplaced** family, assert absence only in a controlled draft where at least three universal/placed-family candidates already exist (so no fallback runs). Also pin a later-draft case where fewer than three preferred candidates remain and an eligible unplaced-family module legitimately enters through the existing fallback. Do **not** assert universal exclusion of unplaced-family modules or expose private candidate-policy internals just for tests.
- Verify an uncommitted/unavailable family blueprint is never a candidate, acquired modules are excluded, and three-card offers remain distinct. Assert candidate sets, **not** that the random picker must offer a named card.

**No new progression logic, persistable blueprint collection, picker weighting, forced family cards, or artificial wave exceptions.**


## Task 3 — Generalize existing presentation; remove redundant node state

**World map:**
1. Remove `_IllustratedStageNode.blueprintRecovered` constructor parameter/field and Alpha-only branch. The node already has `stage` and `status`: a real stage's `stage.blueprint` identifies the reward and `status == StageProgressStatus.cleared` determines Recovered versus Locked.
2. Reuse the memory glyph and `Blueprint • Locked / Recovered` semantics for all seven stages. Preserve stage tap and tooltip semantics.
3. Salvage Rift and Void Bastion still show their independent `CampaignReward` glyph/label alongside the blueprint glyph; don't change `SectorMapLayout` globally to work around local crowding.

**Briefing:**
1. Look up the module through `runModuleDefinition(stage.blueprint!)` when non-null; reuse `_BriefingIntelRow` with the locked/recovered name **and precise `effectText`**.
2. Preserve prior-best-result, side-stage Salvage reward, stage modifier, and scroll content. `OrionGamePage._showStageBriefing` already passes committed `result`; do not create another UI-owned unlock flag.

**Mission Report:**
1. Generalize `_missionRewardFact()`: for non-null `_missionStageId`, obtain `OrionCampaign.stageById(_missionStageId!).blueprint`, then derive `runModuleDefinition` if present; guard on captured `_missionPriorResult == null` plus the existing `_missionSaveState`.
2. Keep pending/saved/failed titles and Retry Save handling; interpolate the correct blueprint name. Already-cleared Replay/medal improvement has no first-recovery fact; preserve the Alpha strings.
3. No new Mission Report model or extra reward registry.

**Widget tests:** extend `test/widget/world_map_command_deck_test.dart`'s **"Alpha blueprint semantics follow committed progress"** to cover all seven stage nodes and optional-stage dual rewards. Extend `test/widget/stage_briefing_sheet_test.dart` and `test/widget_test.dart` for locked/recovered briefings on a main and side stage, every stage's blueprint name/effect, pending/saved/failed Mission Report states, semantics and 360×640 overflow. Preserve all existing widget keys and callbacks.

## Task 4 — Preserve report commit semantics and validate together

Extend existing `test/widget_test.dart` HPA-528 journey tests using a representative **non-Alpha** blueprint (e.g. Nebula Relay) and a later/optional one:
- First victory while save is pending: `Blueprint recovery pending`; current attempt's `availableRunModules` does not include the new blueprint.
- Successful persisted first clear: correct stage-specific `Blueprint recovered: <name>`; same-object Replay refreshes module eligibility.
- Save failure: `Blueprint not recovered`; Retry Save success then recovers it.
- An already-cleared replay (even with a better medal) has **no** first-clear recovery fact.
- Campaign reset removes the corresponding map recovered status and eligibility.
- Verify Alpha's existing end-to-end tests still pass; its exact original module values and behavior cannot drift.

**Local verification:**
```bash
dart format lib/game test
flutter analyze
flutter test test/game/orion_campaign_test.dart
flutter test test/game/run_module_unlocks_test.dart
flutter test test/game/run_module_rules_test.dart
flutter test test/game/tower_stats_resolver_test.dart
flutter test test/game/module_offer_picker_test.dart
flutter test test/game/game_session_test.dart
flutter test test/widget/run_module_draft_panel_test.dart
flutter test test/widget/acquired_run_module_control_test.dart
flutter test test/widget/stage_briefing_sheet_test.dart
flutter test test/widget/world_map_command_deck_test.dart
flutter test test/widget_test.dart
flutter test
```

**Human check:** On a real portrait device, inspect a locked main/optional stage briefing; clear an early non-Alpha boss, see recovered text after save, reopen the stage and verify the blueprint is an eligible future option. In a later-stage run, build Gravity Well or Drone Bay before draft 3 and check whether the family card feels like a meaningful choice **if offered**. Pay particular attention to Relay Arc's +1 chain target (3 → 4 at Level 1) and Siege Rounds' +1 pierce target (2 → 3 at Level 1), since their proportional caps are larger than the 12–20% modules. No deterministic forced offers or manual multi-hour test matrix required.

**PR completion criteria:** all acceptance checks in the linked design spec are met, CI passes, and the PR has been updated with implementation + tests. Only then change draft → ready for review. Keep HPA-415 linked; do not create new tickets unless this work identifies a concrete, separately scoped defect or requires **new art/SFX**, which should be its own ticket rather than mixed into this one.
