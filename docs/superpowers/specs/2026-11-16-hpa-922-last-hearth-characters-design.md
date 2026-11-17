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

Catalog IDs are stable lowercase given names and are also the per-character art folder names.

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

### Catalog

- Add a small immutable CharacterDefinition catalog under lib/game/models/ with ID, full/display names, rank (E–S), concise role, bio, existing TowerType, fixed TowerSpecialization, signature display name and rank/level stat scalars. Validate the 12 unique IDs and that each signature belongs to its style.
- Keep existing combat enums and effects as internal implementation vocabulary. Do **not** build a new character combat engine or duplicate base TowerStats blocks. Derive style stats using existing GameBalance values, apply character rank/base modifiers and per-level growth in one pure resolver, then stage modifiers and run modules. Level is bounded to 1–40; it is independent of battle tier.
- Place character tuning constants together in GameBalance (or the catalog when character-specific). All formulas are deterministic, checked by unit tests; tune stage-1 starter damage/cost/interval using actual full-wave gameplay results. Rank and growth must change effective stats at level 1 vs 40 and E vs S, without accidentally changing unrelated stage rules.
- Keep targeting modes, projectile/splash/freeze/chain/drone effects, run modules, boss blueprints, stage modifiers and Endless health scaling. Do not add new combat mechanics.

### Profile and persistence

- One immutable PlayerProfile aggregate contains CampaignProgress (including medals/results and Endless records), owned character levels keyed by ID and an ordered squad list. Fresh profile: owned {haruto: 1, mio: 1}, squad [haruto, mio], empty progress.
- Replace the old save aggregate/store with PlayerProfileStore using SharedPreferences and an in-memory test implementation. Persist the entire aggregate in **one key/write** (new profile key/version). The old campaign save key and tech-tree data are ignored; no conversion, migration, dual-read or backward compatibility. Malformed/unrecognized data safely starts a fresh profile.
- Preserve the page's serialized **committed-state** transaction model: stage results and squad edits must compose against the last successfully saved profile, with rollback or visible retry feedback on failures. Launches read the committed squad, not an optimistic uncommitted edit. Reset restores the two starters.
- Scrip, recruitment and level-purchase transactions are HPA-923. HPA-922 still persists and resolves levels for test fixtures; regular users initially remain at level 1. Do not add a temporary economy or lootbox.

### Squad and battle invariant

- A squad has 0–6 distinct owned IDs; the UI prevents launching a mission with zero members and never shows unowned characters as selectable. Preserve user-chosen ordering when saved and across stage launches. Later recruit expansion needs no structural rewrite.
- A session receives an immutable squad/owned-level snapshot at stage start. Its placement API accepts a **character ID**, and validates membership, affordability, phase, cell/path occupancy and **already on field** status. Different characters sharing a TowerType can both deploy; the same character cannot deploy twice by tapping, dragging or invoking session methods.
- Dock order matches squad order, shows deploy cost and status (ready, unaffordable, deployed). Selection, previews, radial/inspector and board overlays derive from GameSnapshot; the Flutter layer never mutates session rules directly.
- Deployed actor stores character ID, battle tier (1–3), resolved persistent level and targeting mode. Tier 1 deploys; gold upgrades to tier 2; a fixed signature activation at tier 3 applies its preselected specialization. There is **no specialization picker**. Battle tier resets on a new mission, while persistent level remains in profile.
- **Recall** is build-phase only and replaces Sell. It refunds 70% of the invested in-battle gold through the existing refund calculation and plays the existing feedback cue. It removes the actor and any owned temporary field/drone effects, frees that character's deployment slot and permits redeployment elsewhere. Re-deploy starts at tier 1; prior battle upgrades are not retained or refunded above the established sell rule. Recall cannot be used during a wave.
- Snapshot exposes the squad/placement availability and the selected character's stats/next tier preview. Existing stage and run-module projections remain immutable.

## UI contract against approved HPA-922 mockups

The issue contains images **10 Camp roster**, **11 Character sheet**, **14 Stage briefing with squad** and **15 Battle**, plus an HTML mockup source ZIP. These are visual acceptance references, not a reason to recreate the entire current theme. All visual comparisons use the approved images and current Flutter screenshot output.

| Surface | Required behavior | Reference |
| --- | --- | --- |
| Bottom navigation | Map / Camp / Codex; R&D tab and research-point chip gone | 10, 11 |
| Camp | All 12 in the roster grid, owned/locked distinction, rank, read-only selection. R&D bay background may be reused until HPA-926 | 10 |
| Character sheet | Portrait, rank, name, role, bio, effective level-1 stats and signature; **no Level up button** (HPA-923) | 11 |
| Stage briefing | Current squad preview and picker, maximum six, selected state, launch gate for empty squad; preserve replay, rewards, modifiers and Endless controls | 14 |
| Battle | Only squad member cards in dock, status/affordability, rank-colored ring and full-body chibi on board, same chibi in dock; 3-tier inspector with one fixed signature and Recall | 15 |

Image contract: assets/images/characters/{id}/portrait.png and assets/images/characters/{id}/chibi.png. Use the **already approved** concept and chibi images from the Linear attachments as initial placeholders; crop/export them to these independent paths, reuse the app/Flame image caches and keep gameplay rendering independent of image loading. No generated or newly commissioned art or SFX belongs in HPA-922: HPA-924, HPA-925 and HPA-927 own final asset production.

Use practical Flutter constraints: one scrollable roster grid, responsive briefing/squad layout, readable 320×568 portrait with safe areas and a keyboard/text-scale pass; preserve the current UI kit tokens, semantics and reduced-motion behavior. Temporary space boards/enemies are intentional until HPA-926.

## Existing systems to keep functioning

- Preserve CampaignProgress results/medals, stage unlocks and main/optional route recommendations; remove only R&D tech points and purchases. Keep the existing side-stage reward modifiers and Challenge Badge independent of tech-tree code.
- Salvage Modules and boss-blueprint unlocks remain functional against character combat styles. Existing run-module compatibility is based on the underlying style, not a new character-specific bonus framework.
- Endless remains unlocked by stage clear and persists the best-wave record in the same profile.
- Codex remains searchable and usable: present the playable character identity/signature instead of advertising wave-unlocked build types or a user-selectable specialty; retain Enemies, Effects and Stages.
- Adapt the first-mission guide to the two starters and battle-tier Upgrade. Remove wave-unlock tips, replace the obsolete pick-a-specialization callout with an optional fixed-signature lesson, and keep boss/targeting/stage-modifier tips. Do not preserve stale enum/storage compatibility.
- Preserve feedback preferences, music, accessibility, existing stage scripts, mission report, pause/speed, gameplay art for enemies, and title flow.

## Constraints / deliberate exclusions

HPA-923: Scrip, flare odds, duplicate sales, progression purchasing and level-up UI. HPA-924/925/927: final character/enemy/board audio/visual art. HPA-926: winter narrative labels, scene retheme and wiring completed assets. Also excluded: migration, banners/pity, real money, gear, skill trees, story scenes, new maps, new enemies, new combat behaviors, online services, a generic entity/component framework.

## Acceptance contract (all automated, same PR)

1. Catalog/rule tests verify all 12 mappings, ranks, signatures, unique IDs, and deterministic rank/level/tier stat differences. Direct GameSession tests reject an unowned/off-squad/duplicate deploy, permit two characters of the same combat style, and verify refund + redeploy without cost exploits.
2. Codec/store and page tests cover clean start, old-save ignored, character level/squad/medal/Endless persistence across relaunch, save-failure rollback, reset and concurrent save ordering. No R&D schema or old migration tests remain.
3. A real **full 8-wave stage-1 run**, with only Haruto/Mio and feasible in-battle upgrades, reaches victory in an automated Flame/integration scenario. No fake finishActiveWave shortcut counts as this proof. At least one run module draft and the boss wave must be exercised.
4. A browser/Flutter **MCP-driven end-to-end** flow starts from a fresh profile, opens Camp and the character sheet, edits the briefing squad, launches stage 1, deploys/upgrades/signatures/recalls, wins, reloads and sees saved medals and squad. Verify Codex search, guide/tips, and that cleared stage Endless remains accessible.
5. Using the same MCP run on **one representative platform (web Chrome)**, capture screenshots of Camp, character sheet, squad briefing and battle. Compare each to Linear mockups 10/11/14/15 (composition, art, order, states, legibility); also capture 320×568 and 2× text scale. Record screenshot evidence and deviations in the PR; no human approval, manual acceptance or separate platform run is a completion gate unless a platform-specific change is introduced.
6. Formatting, flutter analyze, relevant unit/widget suites, full flutter test, Flutter web build and existing CI/coverage gates pass. Delete/rewrite tests that assert removed tech tree, wave unlock or specialization choice, not leave dead production code behind.
