# HPA-415 — Boss Blueprint Expansion Implementation Plan

> **One Linear ticket, one PR.** This draft begins with spec + plan; add implementation and tests **to this same PR** before marking ready for review. Work in small green commits on this branch. No separate design, implementation, or art PR.

**Linear:** [HPA-415](https://linear.app/cwchanap/issue/HPA-415/orion-give-every-boss-a-blueprint-module)

**Design authority:** [HPA-415 design](../specs/2026-10-18-hpa-415-boss-blueprint-expansion-design.md)

**Goal:** Seven bosses → seven unique, committed-clear-gated blueprint modules; catalog grows from 7 to 13 and the existing map, briefing, report, and draft surfaces communicate them.

**Architecture:** Reuse `runModuleCatalog`, `RunModuleUnlocks`, `RunModuleRules`, `GameSession._moduleCandidates`, and the HPA-528 committed-progress/replay/report flow. Exactly three focused new module-definition scalars. No new services, packages, assets, sound, persistence, or picker behavior.

## Baseline/code facts verified

- `RunModuleUnlocks.availableFor` filters catalog IDs using a private map currently containing only Relay Calibration → Outpost Alpha.
- `TowerStats.copyWith` already exposes `fieldRadius` but not `chainCount` or `pierceCount`.
- `RunModuleRules.applyTowerStats` already applies damage to direct, corrosion, and drone stats; it lacks the three identity scalars.
- `GameSession._moduleCandidates()` honors eligible modules and existing placed/unlocked family preference; no picker changes required.
- `OrionGamePage._showStageBriefing()` passes committed stage results; `_missionRewardFact()` is currently Alpha-only; same-game Replay already refreshes `availableRunModules`.
- `WorldMapView` currently passes an Alpha-wide `blueprintRecovered` boolean into nodes; `StageBriefingSheet` has an Alpha-only post-clear row; both need per-stage generalization.
- Existing tests in `test/widget_test.dart` already exercise delayed save, failed save, Retry Save, and same-game Replay for Alpha. Extend the pattern rather than building new helpers/frameworks.

## Expected file map

**Modify (rules/catalog):**
- `lib/game/models/game_models.dart` — IDs, affinities, catalog, effect text, three narrow scalar fields, `affectsTowerStats`, and `TowerStats.copyWith` for chain/pierce counts.
- `lib/game/rules/run_module_rules.dart` — three scalar applications and six affinity mappings.
- `lib/game/rules/run_module_unlocks.dart` — six new stage rows plus the single-source `blueprintForStage` lookup.
- `lib/game/rules/game_session.dart` — six arms in `_affinityTower`; **no candidate-policy rewrite**.

**Modify (presentation):**
- `lib/game/ui/world_map_view.dart` — per-stage blueprint state, existing row/glyph/semantics on all nodes.
- `lib/game/ui/stage_briefing_sheet.dart` — locked/recovered blueprint teaser + exact effect on every stage.
- `lib/game/ui/orion_game_page.dart` — generic first-clear Mission Report reward fact.

**Modify (tests):**
- `test/game/run_module_unlocks_test.dart`
- `test/game/module_offer_picker_test.dart`
- `test/game/run_module_rules_test.dart`
- `test/game/tower_stats_resolver_test.dart`
- `test/game/game_session_test.dart`
- `test/game/game_balance_test.dart`
- `test/widget/stage_briefing_sheet_test.dart`
- `test/widget_test.dart` (world map, report, save/replay integration)

No new runtime files anticipated; the existing rules and widgets already provide all needed seams.

---

## Task 1 — Pin catalog and resolved family effects

**Tests first:**
- `module_offer_picker_test.dart`: every `RunModuleId` appears exactly once in `runModuleCatalog` and catalog length becomes 13; preserve pure picker behavior.
- `run_module_rules_test.dart`: each of six modules changes only its matching tower family (including Level 1 / Level 2 / both Level 3 specializations). Check exact scalar differences and no unrelated-stat drift.
- `tower_stats_resolver_test.dart`: combined campaign + stage + acquired-module resolution remains in the existing order, especially amplified gravity → Gravity Echo field radius.
- `game_balance_test.dart`: include new `TowerStats.copyWith` fields in assertions and verify stable tower baseline without an acquired module.

**Implementation:**
1. Extend `RunModuleId` with `relayArc`, `salvagedDrones`, `foundryNanites`, `auroraFocus`, `siegeRounds`, `gravityEcho`. Extend `RunModuleAffinity` with `ionChain`, `droneBay`, `nanite`, `laser`, `railgun`, `gravityWell`. Existing Cryo, Rocket and Universal remain unchanged.
2. Add definitions matching design exactly:
   - Relay Arc: Ion Chain, `chainCountBonus: 1`.
   - Salvaged Drones: Drone Bay, `damageMultiplier: 1.20` (raises `droneDamage`).
   - Foundry Nanites: Nanite, `damageMultiplier: 1.20` (direct and corrosion DPS).
   - Aurora Focus: Laser, `fireIntervalMultiplier: 0.88`.
   - Siege Rounds: Railgun, `pierceCountBonus: 1`.
   - Gravity Echo: Gravity Well, `fieldRadiusMultiplier: 1.15`.
3. Add just three fields to `RunModuleDefinition` (neutral defaults: 0 / 0 / 1), include them in `affectsTowerStats`, extend `effectText`. `TowerStats.copyWith` gets nullable overrides for `chainCount` and `pierceCount`; existing `fieldRadius` is reused.
4. Extend `RunModuleRules.applyTowerStats` once with these scalar applications and `appliesToTower` six switch arms. No combat component or targeting-path edits.
5. Run `dart format` on touched Dart files; run all four focused tests.

**Review guardrails:** In `RunModuleRules`, apply the three scalars **only after** affinity matching, with neutral definitions leaving other towers unchanged. Treat `chainCount` as the full chain hit count: +1 means one additional victim, not an extra initial hit. `fieldRadiusMultiplier` must multiply the already stage-adjusted radius.

## Task 2 — Map every committed boss clear to one locked module

**Tests first (`run_module_unlocks_test.dart`):**
- No campaign results → six normal base modules, no blueprints.
- Each of seven stage IDs has exactly one unique mapped blueprint, and all seven locked modules are accounted for (no orphan mapping, no duplicate IDs).
- Clearing any **one** stage in isolated progress adds exactly its own blueprint, not another stage's.
- Multiple clears union eligibility without duplicates; empty progress after reset restores base pool.

**Implementation:**
1. Append the six rows to the existing private module → stage map, using these IDs: `nebula-relay`, `salvage-rift`, `asteroid-foundry`, `aurora-gate`, `void-bastion`, `singularity-core`.
2. Add one `RunModuleUnlocks.blueprintForStage(String stageId)` lookup returning the corresponding catalog definition (or `null` for an unknown/non-blueprint stage); resolve through that one map instead of duplicating a stage → module table in UI.
3. Extend `GameSession._affinityTower` for all six family affinities; add candidates tests showing no unavailable blueprint leaks.
4. Verify `GameSession.restart(availableRunModules: ...)` and `OrionGamePage` existing committed-progress inputs are sufficient. **Do not edit the restart lifecycle** unless an actual test reproduces a defect.

**Late-family candidate tests (`game_session_test.dart`):**
- With eligible Gravity Echo and a built Gravity Well by wave 5, the candidate set can contain Gravity Echo in draft 3.
- With eligible Salvaged Drones and a built Drone Bay by wave 6, the candidate set can contain Salvaged Drones in draft 3.
- Eligibility does **not** mean a forced offer; use the existing recording picker and assert candidates, not random selection.
- Confirm the preexisting universal/placed/unlocked/fallback priority and no duplicate acquired modules. The `ModuleOfferPicker` API and random algorithm remain unchanged.

## Task 3 — Generalize existing blueprint presentation

**World map:**
1. Replace Alpha-specific `blueprintRecovered` wiring with each node's own stage-clear status. Use `RunModuleUnlocks.blueprintForStage(stage.id)` for the stage-specific reward identity.
2. Reuse the memory glyph + `Blueprint • Locked / Recovered` label and semantics, for all seven.
3. Ensure Salvage Rift and Void Bastion keep their **separate** campaign reward glyph/label as well. Do not alter `SectorMapLayout` globally to hide a local overflow.

**Briefing:**
1. Resolve blueprint from the single helper. Reuse `_BriefingIntelRow` with the module name and definition's `effectText`.
2. Show `Locked` plus teaser before the first committed clear; `Recovered` after clear. Preserve best-result, existing side-stage Salvage reward, modifier, and scroll content.
3. Keep `OrionGamePage._showStageBriefing` committed-result authority; do not add a second persisted or page-owned unlock flag.

**Mission Report:**
1. Generalize `_missionRewardFact()`: current stage blueprint + captured `_missionPriorResult == null` + existing `_missionSaveState`.
2. Keep pending/saved/failed titles; insert the correct blueprint name in pending/recovered copy. Failed state tells the player to Retry Save; replay on prior clear has no recovery fact.
3. No new Mission Report model or view type.

**Widget tests:** in `test/widget_test.dart` and `test/widget/stage_briefing_sheet_test.dart`, exercise the seven map statuses, locked/recovered briefings for a main and a side stage, dual reward display, every stage name/effect, semantics, and no overflow at **360×640**. Keep tests deterministic; reuse present test stores and fake progress.

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
flutter test test/game/run_module_unlocks_test.dart
flutter test test/game/run_module_rules_test.dart
flutter test test/game/tower_stats_resolver_test.dart
flutter test test/game/module_offer_picker_test.dart
flutter test test/game/game_session_test.dart
flutter test test/widget/stage_briefing_sheet_test.dart
flutter test test/widget_test.dart
flutter test
```

**Human check:** On a real portrait device, inspect a locked main/optional stage briefing; clear an early non-Alpha boss, see recovered text after save, reopen the stage and verify the blueprint is an eligible future option. In a later-stage run, build Gravity Well or Drone Bay before draft 3 and check whether the family card feels like a meaningful choice **if offered**. No deterministic forced offers or manual multi-hour test matrix required.

**PR completion criteria:** all acceptance checks in the linked design spec are met, CI passes, and the PR has been updated with implementation + tests. Only then change draft → ready for review. Keep HPA-415 linked; do not create new tickets unless this work identifies a concrete, separately scoped defect or requires **new art/SFX**, which should be its own ticket rather than mixed into this one.
