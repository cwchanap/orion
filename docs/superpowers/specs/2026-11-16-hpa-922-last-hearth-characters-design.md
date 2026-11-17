# HPA-922 — Last Hearth characters, squad and battle (Design Spec)

Date: 2026-11-16  
Linear: https://linear.app/cwchanap/issue/HPA-922/orion-characters-replace-towers-roster-squad-and-battle  
Parent/authoritative product direction: https://linear.app/cwchanap/issue/HPA-921/orion-pivot-to-last-hearth-an-anime-character-tower-defense  
Scope: one implementation PR (this draft); no separately merged planning PR.

## Outcome

Replace generic purchasable towers with owned anime characters. A fresh profile owns **Haruto** and **Mio**, selects up to six owned characters for a squad, and deploys each squad member **at most once** on a battle board. Each deployable character uses an existing combat style and a fixed signature effect. The battle progression is **Deploy → Upgrade → Signature**; a separately stored persistent character level scales stats. Camp replaces R&D, and stage briefing exposes squad selection. The character shown on the board and dock is an actual **chibi full-body sprite**, not a circular icon.

The HPA-921 story, named roster, rank rules and approved mockups are authoritative. The UI uses the current shared Orion UI kit where compatible; final winter skins, enemy art and narrative renaming belong to HPA-926.

## Verified baseline on main

- The pure GameSession (lib/game/rules/game_session.dart) owns tower placement, affordability, upgrade, specialization, sell/refund, run-module drafts and the immutable GameSnapshot. A new character identity must be enforced **there**, not by a disabled Flutter button.
- PlacedTower and TowerStats (lib/game/models/game_models.dart) currently mix battle level and user-selected specialization. TowerStatsResolver composes base stats → tech-tree combat bonuses → stage modifiers → run modules. Replace the tech-tree stage, keep stage/run effects and targeting.
- OrionDefenseGame owns Flame components and two placement paths (cell tap and drag preview/commit). TowerComponent owns rendering and combat timing. Reuse both paths and the existing effect implementations; preserve board coordinate/targeting geometry.
- OrionGamePage owns loading, the serialized committed-state save queue, stage launch/results, reset and navigation. CampaignProgressStore/Codec currently persist campaign progress plus a tech tree. Do not retain old profile formats or migration.
- OrionMenuShell has Map/R&D/Codex destinations and a research-points chip. StageBriefingSheet has no squad picker. MissionCommandDock builds eight TowerType cards. TowerInspector offers one of two specializations.
- The FirstMissionGuide references a generic tower, and ContextualTips trigger wave-based tower unlocks and a specialization choice. Codex has a searchable Towers tab. All need scoped adjustments, not hidden broken destinations.
- Existing integration_test/app_smoke_test.dart and test/widget/scene_parity_regression_test.dart provide useful end-to-end and visual regression seams. HPA-699 introduced the current reusable theme.

## Roster and combat mapping

Character enum values have stable lowercase given names. Their `.name` is the save key and per-character art folder, with parsing confined to the codec.

| Rank | ID | Character | Existing combat style / fixed signature | Working signature name |
| --- | --- | --- | --- | --- |
| S | hikari | Hikari Amatsu, Dawnbringer | Laser / Prism | Dawnbreak |
| S | jin | Jin Kamishiro, the Thawed One | Cryo / Deep Freeze | Absolute Zero |
| A | akane | Akane Hinomori | Rocket / Siege | Hearthfire |
| A | ren | Ren Kurosawa | Gravity Well / Singularity | Crushing Field |
| B | elena | Elena Volkova | Railgun / Magnetic | Heat Sight |
| B | shiori | Dr. Shiori Kusanagi | Nanite / Dissolver | Dissolving Serum |
| C | rin | Rin Fuyutsuki | Cryo / Frostbite | Frostbite |
| C | kaito | Kaito Narumi | Ion Chain / Storm | Live Wire |
| D | sayo | Sayo Kitami | Railgun / Lance | Through Shot |
| D | tetsuo | Tetsuo Kanda | Drone Bay / Interceptor | Scrap Swarm |
| E | haruto | Haruto Sakaki | Laser / Pulse | Steady Volley |
| E | mio | Mio Tachibana | Rocket / Cluster | Kitchen Fire |

The remaining variants (Hunter Bay, Overload Relay, Replicator Nanites, Crush Well) have no character yet; do not expose them as choices or invent additional units.

## Pure data and rules


### Catalog and stat resolution

- Implement an **enhanced enum `Character`** with exactly the 12 values in the table, in Camp display order. Each entry holds full name, rank (E–S), role/bio, fixed TowerSpecialization and working signature name. Derive `style => signature.type`; a character cannot contain a mismatched combat style. `Character.values` gives the roster; `character.name` is the stable save key/asset folder. Only persistence decodes IDs with `Character.values.asNameMap()`. No parallel string-ID registry or generic character framework.
- Preserve `TowerType`/`TowerSpecialization` as **internal** combat vocabularies used by projectiles, sound, stats and sprites; existing `GameBalance.towerStats` remains the source of the eight styles. Keep all effects and targeting modes.
- Rank multipliers are a six-entry table in `GameBalance` plus **one** per-level growth constant (persistent levels 1–40), not per-character numerical configs. The pure resolver applies `base style/tier → character rank+level → stage modifiers → run modules`; remove the tech-tree bonus step. Rank/level scale **`damage`, `corrosionDamagePerSecond` and `droneDamage` together** with one `TowerStats.scaleDamageChannels` helper, also reused in `RunModuleRules`. This ensures Shiori and Tetsuo receive meaningful scaling. Other combat characteristics remain those of the style/tier unless starter headless balance results justify an explicit, tested adjustment.
- **Battle costs are per combat style**, independent of rank and persistent level. Use existing `GameBalance` deploy/upgrade/signature costs and `refundValue`; no parallel per-character cost table. Add one `TowerStats.nextUpgradeCost` (tier 1 uses `upgradeCost`, tier 2 uses `specializationCost`, tier 3 returns null) and use it consistently in session, radial action, inspector, guide and signature-tip affordances. Check that recall never creates gold. Calibrate any needed style/tier costs through the early headless full-wave test rather than speculative UI tuning.
- Pure tests cover E–S ranks, level 1 vs 40, tiers 1/2/3, all 12 fixed signatures, and non-damage effect preservation. No new combat mechanics are introduced.


### Profile and persistence

- **Extend the existing atomic save implementation in place.** `CampaignSave` in `lib/game/campaign/campaign_progress_store.dart` holds `CampaignProgress` (medals, stage results, Endless), `Map<Character, int> ownedLevels`, and ordered `List<Character> squad` in place of `techTree`. A rename of the aggregate for clarity is optional; do **not** introduce duplicate store/interface/codec files. Keep the existing `CampaignProgressStore`, SharedPreferences and in-memory implementations, key `orion.campaign.progress`, and the page's serialized committed-state queue.
- Codec writes **version 4** to the existing key. Versions 1–3/unknown or absent payloads start a fresh profile with owned `{Character.haruto: 1, Character.mio: 1}`, squad `[haruto, mio]`, empty progress; **no migration, alternate key or dual-read**. For a version-4 payload, parse progress and character fields independently; skip unknown IDs, invalid levels and unowned/duplicate squad members without wiping valid stage results, normalize to the two starters if nothing remains owned. This is minimal local validation, not a compatibility subsystem.
- Squad picker edits remain a **route-local draft**. Cancel dismisses without persistence. **Launch** validates nonempty squad and persists one updated aggregate. The existing `StageBriefingSheet` buttons currently pop their modal before any write; replace this with one async handler that keeps the sheet open and disables launch buttons while saving. Make `_persistSave` return `Future<bool>` **after its queued `saveTask` and saving-state `finally` settle**, rather than returning merely when the task is enqueued. On success only, pop the modal with `RunMode` and use the existing `_showStageBriefing` continuation to call `_startStage` **once** with the committed squad. On failure, show a retryable message inside the still-open sheet and retain its draft; do not call `_startStage` from `onCommitted` (it runs before the busy guard clears).
- Existing stage results and save-failure rollback still compose against last committed state, and reset restores two E starters. Persistent level is stored even though UI stays level-1 until HPA-923. Scrip, recruitment and level purchasing remain **only** HPA-923.


### Squad and battle invariant

- Squad is an ordered list of at most six distinct **owned `Character` values**. A session receives an immutable `Map<Character, int>` of squad members to persistent levels at launch. The placement API takes `Character`; `GameSession` alone rejects off-squad, already-deployed, unaffordable, invalid phase, occupied/path and module-draft placements. Different characters may share a `TowerType`; one character cannot appear twice even through alternate tap/drag paths.
- **Extend existing `PlacedTower` instead of creating a parallel placed-unit type.** Replace stored `type`/`specialization` with `character` and `characterLevel`. Keep existing battle `level` as tier 1–3, targeting and cell. Compute `type => character.style` and `specialization => level == 3 ? character.signature : null` as getters, so existing Flame/effect/run-module readers continue to work.
- Use **one** `GameSession.upgradeTower` path for tier 1→2 (existing `upgradeCost`) and 2→3 (existing `specializationCost`, automatically applying the character's fixed signature). `PlacedTower.upgraded()` covers either transition; delete selectable specialization APIs, `canSpecialize`, `specialized()`, `specializeTower` and `selectedTowerSpecializationStats`. Reuse `selectedTowerUpgradeStats` for the next-tier/signature preview. Keep battle tier and persistent level separate. Each new run resets only battle tier.
- **Recall** is the existing sell mutation renamed in UI: build-phase only, existing 70%-of-invested-gold `GameBalance.refundValue` and sound, and cleanup of owned drones/fields. Recalled character is available for re-placement at tier 1; nothing can be recalled during a wave.
- Reinterpret `GameSession.unlockedTowerTypes` as the **distinct combat styles in the squad** (regardless of wave). It remains an internal projection powering scanner recommendations and module-draft candidate affinity; the dock itself displays squad characters. Keep the current module-offer tiering (placed style → squad style → existing fallback when fewer than three remain) and test that off-squad options do not appear prematurely. The late fallback is deliberate given the limited starter-only catalog; do not break three-card drafts or silently omit wave 6.
- `GameSnapshot` exposes the **ordered `List<Character> squad`** separately from the deduplicated style projection, so the dock can display Haruto and Hikari (both Laser) as distinct members in the correct order. Snapshot remains the immutable source for placement, dock status and inspector stats. Existing stages, boss blueprints, run modules, medals, Endless and enemy traits continue to function.

## UI contract against approved HPA-922 mockups

The issue contains images **10 Camp roster**, **11 Character sheet**, **14 Stage briefing with squad** and **15 Battle**, plus an HTML mockup source ZIP. These are visual acceptance references, not a reason to recreate the entire current theme. All visual comparisons use the approved images and current Flutter screenshot output.

| Surface | Required behavior | Reference |
| --- | --- | --- |
| Bottom navigation and title | Map / Camp / Codex; R&D shortcut and research-point chip removed from both `OrionMenuShell` **and `OrionTitleView`**; medal display derives from `CampaignProgress.totalMedalRank` after the tech-tree code is deleted | 10, 11 |
| Camp | All 12 in the roster grid, owned/locked distinction, rank, read-only selection. R&D bay background may be reused until HPA-926 | 10 |
| Character sheet | Portrait, rank, name, role, bio, effective level-1 stats and signature; **no Level up button** (HPA-923) | 11 |
| Stage briefing | Current squad preview and picker, maximum six, selected state, launch gate for empty squad; preserve replay, rewards, modifiers and Endless controls | 14 |
| Battle | Only squad member cards in dock, status/affordability, rank-colored ring and full-body chibi on board, same chibi in dock; 3-tier inspector with one fixed signature and Recall | 15 |

Image contract: assets/images/characters/{id}/portrait.png and assets/images/characters/{id}/chibi.png. Copy **full-size approved** character portraits/chibis from the asset ZIP attached to **HPA-924**, preserving one file set per ID; do **not** crop composites from mockup screenshots. Reuse `OrionArtDescriptor` (UI cache/retry/test reset) through `OrionArt.characterPortrait/characterChibi`; Flame `onLoad` should fetch only the **active squad's** chibis, never all twelve. Existing FakeAsync widget fixtures require asset prewarming via `tester.runAsync`. Keep gameplay rendering independent of image loading. No generated or newly commissioned art or SFX belongs in HPA-922: HPA-924, HPA-925 and HPA-927 own final asset production.

Use practical Flutter constraints: one scrollable roster grid, responsive briefing/squad layout, readable 320×568 portrait with safe areas and a keyboard/text-scale pass; preserve the current UI kit tokens, semantics and reduced-motion behavior. Temporary space boards/enemies are intentional until HPA-926.

## Existing systems to keep functioning

- Preserve CampaignProgress results/medals, stage unlocks and main/optional route recommendations; remove only R&D tech points and purchases. Keep the existing side-stage reward modifiers and Challenge Badge independent of tech-tree code.
- Salvage Modules and boss-blueprint unlocks remain functional against the squad's underlying combat styles (not wave unlocks). Existing run-module compatibility is based on the underlying style, not a new character-specific bonus framework.
- Endless remains unlocked by stage clear and persists the best-wave record in the same profile.
- Codex remains searchable and usable: present the playable character identity/signature instead of advertising wave-unlocked build types or a user-selectable specialty; retain Enemies, Effects and Stages. In the Effects **Used by** projection, derive playable relations from `Character.values` and each character's fixed signature instead of iterating all `TowerSpecialization.values`, which includes unassigned specializations. Reuse `TowerStatScale.forType(character.style)` for character-sheet stat display rather than building another chart/scale.
- Adapt the first-mission guide to the two starters and battle-tier Upgrade. Remove wave-unlock tips, replace the obsolete pick-a-specialization callout with an optional fixed-signature lesson, and keep boss/targeting/stage-modifier tips. Do not preserve stale enum/storage compatibility.
- Preserve feedback preferences, music, accessibility, existing stage scripts, mission report, pause/speed, gameplay art for enemies, and title flow.


## Risks and intermediate-state limits

- **Early viability is the main risk.** Replacing eight freely repeatable tower types with only two unique E starters, while removing Solar Capacitors/Hardened Core/Salvage Crew, may make Stage 1 impossible at original costs or damage. A **headless full-eight-wave Stage 1 test is a gate immediately after the session refactor**, before chibi or Camp work; adjust the minimal shared tuning constants and exercise real spawns/combat/module drafts/boss.
- **Later stages before HPA-923:** the shipped player still owns only Haruto and Mio, so stages 2+ need not be independently beatable with just those two. This temporary content limitation is accepted until recruitment; nevertheless an automated E–C fixture profile must prove main-path progression is viable when those characters become obtainable. Do not invent extra starter ownership, boost stage rewards or move HPA-923 economy scope here.
- **Launch/save race:** `_persistSave.onCommitted` currently fires before busy status clears; launching there would be rejected. Require post-queue-settlement launch and a real rollback/failure test for it.

## Constraints / deliberate exclusions

HPA-923: Scrip, flare odds, duplicate sales, progression purchasing and level-up UI. HPA-924/925/927: final character/enemy/board audio/visual art (HPA-922 may copy the already approved HPA-924 art pack as placeholders). HPA-926: winter narrative labels, scene retheme and wiring completed assets. Also excluded: migration, banners/pity, real money, gear, skill trees, story scenes, new maps, new enemies, new combat behaviors, online services, a generic entity/component framework.


## Acceptance contract (all automated, same PR)

1. Pure catalog/session tests cover all 12 enum mappings, all six ranks, deterministic rank/level/tier stat channels (damage, corrosion, drones), same-style distinct characters, off-squad/duplicate rejection, 70%-refund Recall/redeploy and style-based costs. Old selectable specialization API and research purchases are deleted.
2. In-place **version-4** codec/store and page tests verify clean start, old-save discard, partial invalid v4 entry handling, squad/medal/Endless persistence across relaunch, failed squad-on-Launch (no mission start), save-queue ordering and reset. No migration adapters survive.
3. **Before UI/art work**, `test/game/stage_one_starters_win_test.dart` runs full `OrionCampaign.stageOne` in a plain headless `flutter test` using a deterministic module picker, scripted Haruto/Mio placements/upgrades and `game.update(1/30)` through real enemy spawns and combat to wave-8 boss victory. No shortcut to force wave completion. A parameterized full-main-path E–C fixture proof tests later-game tuning; it does not imply the two starters can beat all stages. Runs in CI under `flutter test --coverage`.
4. Deterministic widget tests check Camp roster/sheet, squad draft/save-on-Launch, battle dock/inspector/Recall, Codex search, guide/tips and absence of R&D/wave-unlock/specialization chooser. Test 320×568 and 2× text without clipping/overflow. Any platform-specific code requires dedicated tests; otherwise one platform suffices.
5. **MCP-driven E2E acceptance on web Chrome (required for this project):** fresh profile → Camp → character sheet → briefing edit → Launch committed squad → real placement/upgrade/signature/Recall → win → reload → saved medal/squad/Endless, plus Codex and guide/tips checks. The headless full-game proof may provide deterministic combat completion where browser canvas stepping is impractical; MCP must still execute the user-visible path and assert navigation/persistence.
6. **Visual check with approved Linear mockups is also required:** capture through MCP the Camp (10), character sheet (11), briefing (14) and battle (15) screens and compare visible content, full-body chibi, selected/deployed status, hierarchy, clipping/overlap, text legibility and usable controls. Log screenshot paths and concrete discrepancies/fixes in the PR. Accept explicitly temporary space backdrops; no separate human sign-off or subjective style score. Keep checks narrow, using existing widget screenshot fixtures when possible.
7. On the final head, `flutter analyze`, `flutter test`, coverage/CI checks and `flutter build web --release` pass. **After each implementation slice**, the full repository stays green with `flutter analyze && flutter test`; add related call-site rewrites to that slice rather than merging intermediate broken commits. All work remains in this single draft PR.

