# HPA-415 — Boss Blueprint Expansion Design

**Linear:** [HPA-415](https://linear.app/cwchanap/issue/HPA-415/orion-give-every-boss-a-blueprint-module) · **Parent:** HPA-303 · **Status:** design proposed for review

## Decision

Extend the existing Salvage Module reward loop from **one** blueprint to **one blueprint for each of Orion's seven bosses**, with **six new family-affinity modules** (catalog: seven → thirteen). Do this inside the existing single catalog, pure stat resolver, committed-progress unlock map, and three existing presentation surfaces.

**Do not build a blueprint subsystem.** No new persistence, save migration, reward registry, event bus, custom effect pipeline, module rarities, draft weighting/pity, Codex section, art, or SFX. This ticket is one implementation PR; the design-and-plan draft PR becomes that same implementation PR.

## Why this slice

HPA-412 (first-mission guidance) is complete. HPA-303 explicitly orders HPA-415 next; it has no blockers. The gameplay gap is concrete: six boss victories currently unlock no module, and six tower families have no dedicated module.

Existing code already gives us:
- `runModuleCatalog` / `RunModuleDefinition` in `lib/game/models/game_models.dart`.
- `RunModuleUnlocks.availableFor(CampaignProgress)` and its private module → stage unlock map.
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

In `game_models.dart`:
- Add six `RunModuleId` cases and six `RunModuleAffinity` cases; reuse current `RunModuleAffinity.label` in draft cards.
- Add the six `RunModuleDefinition` entries in `runModuleCatalog` and exhaustive `effectText` arms. Favor copy that describes what the rule actually changes, not a vague thematic promise.
- Add only `chainCountBonus`, `pierceCountBonus`, and `fieldRadiusMultiplier` to `RunModuleDefinition`, with neutral defaults (0, 0, 1). Include them in `affectsTowerStats` so beneficiary indicators remain truthful.
- Extend `RunModuleRules.applyTowerStats` to apply those three fields and update `RunModuleRules.appliesToTower` for the six new affinities. Effects should apply to Level 1, Level 2 and both specializations for only their matching family.
- Extend `GameSession._affinityTower` for the six cases. Do not edit `ModuleOfferPicker` or add a second eligibility/offer policy.
- Pin `RunModuleRules.beneficiaryCount` for the three scalar-only modules (Relay Arc, Siege Rounds, Gravity Echo): at least one matching placed tower must count as affected, while unrelated towers must not count. These tests catch an omitted `affectsTowerStats` branch even when pure stat-delta tests pass.

The family-preference rule is **not a guaranteed offer**. Five universal modules exist in the catalog (four available before Relay Calibration is recovered), so an unlocked but unplaced family can legitimately be absent from a draft while at least three matching candidates remain. Late Gravity Well (wave 5) and Drone Bay (wave 6) are meaningful choices by draft 3 **when built**, and may appear through fallback when fewer than three stronger candidates remain. Do not force them into drafts, adjust the random picker, or add wave-specific exceptions.

## One unlock source, seven rewards

Keep the private `_unlockStageByModule` map in `run_module_unlocks.dart`; append six module → stage ID rows using the **actual** IDs in `OrionCampaign`, retaining Relay Calibration's row. Keep `availableFor(progress)` deriving from catalog + `progress.isCleared(stageId)`. This automatically preserves:
- no blueprint on a first stage attempt;
- first **successfully committed** clear unlocking the module on next stage launch / same-game Replay;
- no retroactive addition to the just-completed run or an in-flight draft;
- failed save / retry semantics;
- campaign reset removing cleared-stage unlocks.

For presentation, expose one narrow read helper such as `RunModuleUnlocks.blueprintForStage(String stageId)` returning a `RunModuleDefinition?`. Derive it from that **same map + catalog**, not a second hand-maintained stage → module registry. A unit test guards exactly one mapped blueprint per campaign stage and a one-to-one mapping to the seven locked modules.

## Presentation (existing widgets only)

**World map — `world_map_view.dart`**
- Every stage node gets the existing `Icons.memory_rounded` blueprint glyph and `Blueprint • Locked / Recovered` status, derived from the stage's committed clear instead of the Alpha-only boolean.
- Retain the separate side-stage `CampaignReward` glyph (gold/health) where one exists: a side-stage victory may now earn **both** a campaign stat reward and a blueprint.
- Extend the existing small row, tooltip, and semantics; do not change sector node geometry globally or create a new map component. Check glyph legibility on optional-stage nodes that already have a reward glyph.

**Stage briefing — `stage_briefing_sheet.dart`**
- Before first clear, show a compact locked teaser with **module name and exact effect**, so the boss reward is knowable before deploying.
- After clear, show the same name/effect with `Recovered` status. Keep the existing `BEST RESULT` and optional-stage `SALVAGE` rows separate.
- `StageBriefingSheet.result` is already sourced from `_committedProgress` by `OrionGamePage`; use this, not speculative/uncommitted run state.
- Reuse `_BriefingIntelRow` and scroll behavior; no new page or hero art.

**Mission Report — `orion_game_page.dart`**
- Generalize `_missionRewardFact()` from the Alpha-only case by resolving the current stage's blueprint through `RunModuleUnlocks.blueprintForStage`.
- Show `Blueprint recovery pending` / `Blueprint recovered: <name>` / `Blueprint not recovered` with the same saved/failed retry behavior as HPA-528.
- Guard on captured `_missionPriorResult == null`; already-cleared replay, later medal improvement, and loss do not falsely celebrate first recovery.
- Keep `MissionRewardFact` and `mission_report_panel.dart` unchanged unless a specific measured layout failure appears.

Draft cards gain the six affinity labels and effect copy from the existing catalog; do not change picker UI.

## Acceptance and validation

1. Catalog has exactly 13 unique IDs and one blueprint per each of the seven real stage IDs; base pool stays the six original ungated modules.
2. Each of the six new modules only affects its intended family and its existing specializations, at correct effective values. Unrelated stats/families are unchanged; Relay Arc, Siege Rounds, and Gravity Echo also report correct nonzero matching-family beneficiary counts.
3. An isolated committed stage clear unlocks **only** its stage-specific module; prior progress remains valid, save failure changes nothing, reset removes unlocks. Same-game Replay reads refreshed committed eligibility.
4. Existing draft order and selection behavior remain intact. Verify wave-6 late-family builds can be candidates for draft 3; do not test that random cards are guaranteed.
5. All seven map nodes, locked/recovered briefing copy, and three Mission Report save states work with long module names and optional-stage dual rewards at **360×640**.
6. Focused pure tests, relevant widget tests, `flutter analyze`, full `flutter test`, and one real-device pass of at least an early stage and a late-family draft are complete.

## Out of scope

No new art, glyph asset, SFX, boss encounter/balance changes, Codex page, rarity, reroll, alternative currency, permanent power treadmill, new persisted unlock records, migration, forced family offers, or preemptive abstractions. Pre-release project: no backward-compatibility work for save schema changes that are not needed.
