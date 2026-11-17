# HPA-922 — Last Hearth character roster, squad and battle (Implementation Plan)

Date: 2026-11-16  
Linear: https://linear.app/cwchanap/issue/HPA-922/orion-characters-replace-towers-roster-squad-and-battle  
Design: ../specs/2026-11-16-hpa-922-last-hearth-characters-design.md  
Target branch: main; **this same PR** moves from documentation draft to implementation. Do not create a second implementation PR.

## Execution principles

- Keep the vertical slice playable end to end: fresh two-character profile → Camp → briefing squad → battle → tier upgrade/signature → stage-1 victory → persisted result/Endless.
- Replace old R&D, wave-unlock and selectable-specialization code, tests and UI directly. No deprecation wrappers, old-save migration or compatibility adapters.
- Preserve existing pure GameSession/rules versus Flame/rendering boundary. Character IDs are the placement identity; underlying TowerType and TowerSpecialization may remain private implementation vocabulary for existing combat mechanics.
- All new art in this task is **extraction/copy of already approved placeholders**. Production illustration and sound creation stay in HPA-924/925/927. Do not expand the code ticket to include those tasks.
- Keep the **entire repo green after every implementation slice** with `flutter analyze && flutter test`. Each slice owns any caller/fixture changes needed to compile. Commit and finish everything in **one PR**; avoid generic registries, providers or new architecture.

## Task 0 — Verify source files and approved assets

1. Verify main's authoritative seams: `GameSession`, `OrionDefenseGame`, `PlacedTower`, `TowerStatsResolver`, `CampaignSave`, `OrionGamePage`'s committed save queue, and the existing widget/Flame tests.
2. Read HPA-922 mockups **10 Camp, 11 Character sheet, 14 Briefing squad, 15 Battle** (and HTML sources) as UI references; **no need to capture baseline web screenshots**.
3. Obtain the **full-size approved art ZIP attached to HPA-924**, not composites/crops from HPA-922 mockups. Inspect its per-ID folders and use those approved files as placeholders only; final art/SFX creation remains in separate tickets.
4. Confirm `test/game/orion_defense_game_test.dart` headless game-loop harness, deterministic `ModuleOfferPicker`, and `.github/workflows/ci.yml` coverage job before changing the API.

Done: references and available assets identified; no new screenshot framework or separate PR.

## Task 1 — Closed Character enum and pure scaling

Production: `lib/game/models/game_models.dart` (or one closely related model file), `lib/game/rules/tower_stats_resolver.dart`, `lib/game/rules/run_module_rules.dart`.  
Tests: focused character catalog, game-balance, run-module and stat-resolver tests.

1. Define enhanced `enum Character` with 12 exact roster entries (stable lowercase `.name`), rank, full/display name, role, bio, fixed signature and label. Derive `style` from `signature.type`; **do not store separate style or string IDs**. `Character.values` defines Camp order.
2. Define one rank multiplier per E/D/C/B/A/S and one level-growth constant (1–40) in `GameBalance`. Retain existing `TowerType`, `TowerSpecialization` and `GameBalance.towerStats` internally.
3. Add a minimal `TowerStats.scaleDamageChannels(factor)` covering `damage`, `corrosionDamagePerSecond` and `droneDamage`; use it both for character scaling and `RunModuleRules`. Tests explicitly include Shiori/Nanite and Tetsuo/Drone Bay.
4. Resolve base style/tier → rank+level channels → stage modifiers → run modules. Remove the tech-tree damage/slow bonus step at the appropriate compile-green slice; keep the existing style-specific movement/freeze/pierce/field mechanics.
5. Decide once: **deploy, upgrade, signature and Recall costs remain style-based** through `GameBalance._towerCosts` and `refundValue`, never rank/level-based. Tests assert no extra gold can be minted.
6. Add `int? TowerStats.nextUpgradeCost` derived from battle tier (`level == 1 ? upgradeCost : level == 2 ? specializationCost : null`). This is one authoritative price for both tier transitions. Do not silently keep reading `stats.upgradeCost` at tier 2; wire remaining callers in Task 3/7.

**Gate:** `flutter analyze && flutter test`; catalog/stats test assertions pass.

## Task 2 — Extend atomic CampaignSave in place (v4), remove R&D in the same slice

Production: `lib/game/campaign/campaign_progress_store.dart`, `campaign_progress.dart`, `lib/game/ui/orion_game_page.dart`, `orion_menu_shell.dart`; delete tech-tree-only files in this slice.  
Tests: `test/game/campaign_progress_store_test.dart`, page save/relaunch/reset cases, menu-shell and legacy-tech-tree test cleanup.

1. Extend existing `CampaignSave` with `Map<Character, int> ownedLevels` and ordered `List<Character> squad`, replacing `techTree`. Keep existing `CampaignProgressStore`, SharedPreferences, in-memory store and **same key `orion.campaign.progress`**. No extra profile store files.
2. Codec writes **v4**; anything not v4 (including v1–3 old saves) starts a fresh two-E-character profile. For v4, parse the existing stage/endless results independently from character fields, skip bad/unknown character IDs/levels/duplicated squad IDs and restore starters if the owned map is empty. Decode strings only here via `Character.values.asNameMap()`. No migration, alternate keys or backward compatibility.
3. Preserve the page's `_persistSave` generation guard and last-committed-state serialized queue, plus rollback/retry behavior. Supply fresh/default profile for reset. Squad writes are deferred to **Task 6 Launch**; stage and Endless records use the same aggregate.
4. **In this same task**, remove `CampaignTechTree` purchases, its fields in `CampaignModifiers` and `OrionGamePage`, `TechTreeView`, the R&D tab/research chip and their tests/fixtures. **Include `OrionTitleView`**: remove its `researchPoints` campaign-card chip/parameter and change its `onOpenResearch` / `R&D` shortcut to **Camp**. Move the still-needed `CampaignTechTree.totalMedalRank(progress)` calculation to a simple `CampaignProgress.totalMedalRank` getter and replace all title/menu/page references before deleting `tech_tree.dart`. Replace nav with Map/Camp/Codex; a lightweight compile-safe Camp placeholder can render the two owned starters until Task 6's full view. Preserve side-stage reward bonuses and Challenge Badge from progress.
5. Test startup, relaunch, partial invalid v4 data, old v3 disregard, reset, failed save and two queued save operations.

**Gate:** `flutter analyze && flutter test`; no live or test-only TechTreeView import survives. The whole app still launches.

## Task 3 — Extend PlacedTower, session one-of-each and minimal presentation wiring

Production: `lib/game/models/game_models.dart`, `lib/game/rules/game_session.dart`, `lib/game/orion_defense_game.dart`, minimal `mission_command_dock.dart` and other callers/fixtures.  
Tests: `test/game/game_session_test.dart`, placed-tower, resolver, placement tap/drag tests.

1. **Keep `PlacedTower`** rather than add `PlacedCharacter` or an adapter: replace stored `type`/`specialization` with `Character character` and `int characterLevel`; retain battle `level` as tier, position, targeting and ID. Derived getters `type => character.style`, `specialization => level == 3 ? character.signature : null` preserve effect/render readers.
2. `GameSession.initial(squad: Map<Character, int>)` takes the selected squad with persistent levels; the page supplies its committed profile. `placeTower(position, Character)` and preview validation reject off-squad/already deployed, phase, path/occupied cell, pending module and low gold. One character per field, but different characters sharing a style can both be placed.
3. Merge tier progression into **one** `upgradeTower`: tier1→2 charges `upgradeCost`; tier2→3 charges `specializationCost` and automatically activates the fixed signature. `PlacedTower.upgraded()` supports both. Remove `specializeTower`, `canSpecialize` and user-selected branch; reuse `selectedTowerUpgradeStats` for the next-tier preview. Use `TowerStats.nextUpgradeCost` for session affordability **and** the matching radial (`mission_chrome.dart`), inspector (`tower_inspector.dart`) and tutorial-anchor (`orion_game_page.dart`) cost/display/enable conditions; adjust contextual signature-tip gating in Task 7. Test that the displayed price, disabled state and deducted gold all agree at tier 2.
4. **Recall** reuses `sellTower` logic and existing `GameBalance.refundValue`; keep build-only gating, 70%-of-invested-gold accounting, component-owned field/drone cleanup, availability reset and re-deploy as tier 1. No gold exploits.
5. Keep `unlockedTowerTypes` as an **internal list of distinct squad styles**, replacing wave-based unlocks for the scanner and module draft pool. Preserve ordered candidate priority (placed → squad → existing any-module fallback after exhaustion) and three-card drafts; test no premature off-squad offering on starter wave 2 and correct late fallback.
6. Expose the **ordered `List<Character> squad` on the immutable `GameSnapshot`** separately from deduplicated `unlockedTowerTypes` (which remains scanner/module-style input). Update **all compiling callers in this same slice**: minimal dock iterates squad IDs even when two characters share the same `TowerType` (e.g. Haruto + Hikari), Flame tap/drag/preview methods forward typed Character, and test fixtures use selected squads. Board can still render old tower sprites until Task 5.

**Gate:** `flutter analyze && flutter test`; all 12 Character styles deploy in pure tests, direct duplicate prevention, fixed 3-tier upgrade and Recall/refund/redeploy work.

## Task 4 — Headless real-game starter victory and main-path E–C tuning (**before UI/art**)

Tests: add `test/game/stage_one_starters_win_test.dart` under ordinary `flutter test --coverage` (not emulator-only).

1. Instantiate actual `OrionCampaign.stageOne`, `OrionDefenseGame` with squad `{Character.haruto: 1, Character.mio: 1}`, a deterministic module picker, `onGameResize` and scripted placement/tier upgrades.
2. Start each wave, tick real gameplay via `game.update(1/30)`, pick offered Salvage Modules, and continue to the **wave-8 boss death and GamePhase.won callback**. Guard the loop against indefinite hangs and verify spawns/combat actually occur. Do not call `finishActiveWave` or fabricate completion.
3. If the two starters cannot win, change **only** the minimal shared rank/tier/cost tuning in `GameBalance`; no Stage 1 scripted overrides, cheat auto-kills or extra starter character.
4. Extend the same headless fixture pattern to the five-stage **main path with an E–C owned/squad profile**; demonstrate eventual viability when HPA-923 provides more recruits. Only Haruto/Mio are playable by default until HPA-923; Stage 2+ may remain impossible for that two-character profile in this intermediate version.
5. Assert victory result/medal, boss encounter, module draft compatibility, no duplicate placement and a restart. Test that the scenario catches regressions to starter costs and stats.

**Gate:** `flutter analyze && flutter test`, including a repeatable real Stage 1 win and the representative E–C main-path fixture. **Do not start full Camp/chibi UI before this passes.**

## Task 5 — Flame chibi sprites from approved pack

Production: `lib/game/orion_defense_game.dart`, existing `lib/game/components/tower_component.dart`, optional tiny asset map and `pubspec.yaml`; approved per-ID assets.  
Tests: Flame component tests and per-ID portrait/chibi asset-contract tests.

1. Copy full-size approved portraits/chibi from HPA-924's ZIP to `assets/images/characters/{character.name}/{portrait,chibi}.png`; no mockup screenshot crops, new illustrations or audio generation.
2. Keep original combat implementation, targeting geometry, projectile, field and drone lifecycle; render **full-body chibi over a rank-colored ring** from cached per-ID assets. Reuse the existing `OrionArtDescriptor` cache/retry/test-reset path by adding `OrionArt.characterPortrait(Character)` and `OrionArt.characterChibi(Character)`; do not introduce a second Flutter image loader/cache. Use the same chibi in dock later.
3. On Recall remove component plus owned drone/field effects; on tier change refresh existing component's resolved stats and effect. Tap, drag preview/update/commit/cancel continue using character identity and the same session placement rule.
4. In `OrionDefenseGame.onLoad()`, load chibi sprites only for the **active squad** (not all 12); the Camp portraits load as their UI requests them. Existing widget fixtures prewarm `Flame.images` inside `tester.runAsync` before mounting a game to avoid cold engine decodes hanging under `FakeAsync`. Extend the targeted warm-up helper/fixture for the active squad only and test cache reset/retry. Confirm rendering and asset paths for every ID and at least one live on-board chibi; old space boards/enemies intentionally remain until HPA-926.

**Gate:** `flutter analyze && flutter test`, including render and asset checks. No final asset task scope added.

## Task 6 — Camp and squad picker; save **once on Launch**

Production: `lib/game/ui/orion_game_page.dart`, `orion_menu_shell.dart`, small `camp_view.dart`, `stage_briefing_sheet.dart`.  
Tests: Camp, sheet, shell and page persistence/widget tests.

1. Finish Camp roster as in mockup 10: 12 Character entries in enum order, owned/locked and rank state, read-only sheet with portrait/name/bio/signature/stats as in 11. Reuse `TowerStatScale.forType(character.style)` for the character sheet's existing combat stat bars, not a second scale/meter implementation. Keep current theme and temporary R&D bay backdrop, but **no R&D tab/research points** and no Level up UI.
2. Stage briefing shows a local **draft** squad (up to six unique owned characters; ordering explicit). No per-tap disk write. Cancel discards the draft; a zero-member draft disables Launch with clear feedback. Keep mission/replay/Endless controls and modifier tip.
3. **Keep the briefing route open while committing.** Today `_BriefingLaunchAction` and replay/Endless buttons immediately `Navigator.pop(mode)`; instead pass a single async `onLaunch(RunMode mode, List<Character> draft)` handler to `StageBriefingSheet`, including replay/Endless. Disable all launch/dismiss actions during the in-flight save and surface a retryable error inside the still-open modal on failure. Save the draft **once on Launch** via the existing committed-base `CampaignSave.withSquad(draft)`.
   - Change `_persistSave` to return `Future<bool>` that **awaits its queued `saveTask`** and resolves success/failure only after its `finally { _decrementPendingSaves(); }` executes; simply adding `await` to the current early-returning method or starting in `onCommitted` is wrong.
   - On `true` only, **pop the sheet with the selected `RunMode`**. Keep the current `_showStageBriefing` post-`showModalBottomSheet` **single** `_startStage(stage, mode)` path; do not also start the game in the callback (would double-launch). On `false`, keep the draft and modal open, allow retry and never launch. Use committed squad after the save settles.
4. Test Cancel/no write; mission/Replay/Endless Launch all save once; pending-save buttons disabled and modal remains mounted; failure leaves draft and feedback visible with no navigation; retry succeeds once; simultaneous taps produce one start; squad order survives reload; stage launch reads committed state. Include failed-save regression against both the old early-pop behavior and double-start.
5. Widget-test 320×568 and 2× text, touch targets and semantics, missing portrait fallback and accessibility.

**Gate:** `flutter analyze && flutter test`; screenshot candidates render, squad persistence is deterministic and no launch-on-save-error is possible.

## Task 7 — Full dock/inspector, guide/tips, Codex cleanup

Production: `mission_command_dock.dart`, `tower_inspector.dart`, `mission_chrome.dart`, `orion_game_page.dart`, onboarding/ and Codex files.  
Tests: dock, inspector, guide/tips, Codex, scene parity and integration fixture rewrites.

1. Use existing horizontal dock drag mechanics, but show **current squad only**, in order. Each card uses chibi/name/rank, existing style-based price and ready/deployed/unaffordable state; it cannot deploy a second copy.
2. Inspector shows one next tier action. At tier 2, the action/preview displays the character's fixed signature (no picker); all upgrade action prices and enable conditions read `TowerStats.nextUpgradeCost` (including the radial/inspector and tutorial). Recall shows its refund and respects build-only gating. Preserve targeting, pause/speed and stage overlays.
3. Update guide anchors to available starter cards, first upgrade, module draft and scanner. Remove obsolete wave-unlock and selectable-specialization tip triggers; keep boss, targeting and stage modifier tips. Rewrite tests for intended behavior rather than keep dead enums.
4. Codex playable section uses character identity and fixed signature, while search and Enemies/Effects/Stages continue to work. `CodexData._specsWhere` currently scans all `TowerSpecialization.values` and leaks **unused** variants in Effects `Used by:`. Compute playable-effect relations from `Character.values` and their fixed signatures, and show character names/signatures in the Effects view (deduping as necessary) rather than advertising Hunter Bay/Overload/Replicator/Crush. Add a test that no unused specialization appears. Delete old tech-tree, wave unlock and choose-specialization references/tests, but leave internal combat enum names in place.

**Gate:** `flutter analyze && flutter test`; every reachable screen uses character vocabulary and all existing gameplay controls work.


## Task 8 — MCP web E2E and targeted visual evidence (required)

The project requires acceptance via **MCP**, plus visual checking against Linear mockups. Use a browser/Playwright MCP connected to one web Chrome build. This is **one focused flow**, not a cross-platform matrix or a new screenshot framework. Record the tested commit SHA, run evidence and screenshot paths in PR comments or a validation note. If browser canvas simulation cannot deterministically advance wave combat, reuse Task 4's headless proof for the eight-wave victory, while MCP still exercises all UI paths, state updates and reload checks.

1. Fresh profile → Camp: assert 12 entries, only Haruto/Mio owned and absence of R&D. Capture **mockup 10** view.
2. Open starter character sheet: assert portrait, rank, bio, stats, signature and no Level up action. Capture **mockup 11** view.
3. Stage-1 briefing: draft deselect/reselect, test zero-squad Launch disabled, cancel behavior, then reorder/Launch; assert saved order after reload and that a failed save never begins a stage. Capture **mockup 14** view.
4. Battle: deploy Haruto/Mio (tap or drag), reject duplicate, tier 2 and fixed tier-3 signature, Recall and redeploy; inspect board chibi and dock statuses. Capture **mockup 15** view. Full eight-wave victory proof remains Task 4's automated fixture; use UI wave progression where MCP supports it.
5. Reload saved profile: check medals/Endless availability, squad persistence, Codex search, guide/tips and run-module presentation. Assert no research chip, wave-locked build cards or selectable-specialization controls.
6. Compare the **four screenshots** with approved Linear mockups for required visible elements, sprite type, selected/deployed states, layout hierarchy, overlapping/clipped text and tappable controls. Log concrete pass/fail evidence and any intentional deviations (temporary old board/backdrop). Run widget layout assertions at 320×568 and 2× text; capture one additional compact screenshot when a discrepancy needs illustration.
7. No human approval as acceptance and no second platform required unless there is a platform-specific code change.

**Gate:** MCP-run evidence exists, all mandatory visual/state checks passed, and gaps are recorded as issues/fixed in this **same PR**.

## Task 9 — Final CI, PR cleanup and handoff (same PR)

- Run Dart formatting, `flutter analyze`, `flutter test --coverage` (including **headless Stage 1 full game loop**), `flutter build web --release` and required GitHub CI/integration checks on final head.
- Rewrite/remove obsolete fixtures instead of adding backwards-compatible scaffolding. Review for dead `CampaignTechTree`, research points, wave unlock and selectable-specialization UI, while retaining valid combat `TowerType` internal uses.
- Attach screenshot checks and headless/CI evidence. All feature code, tests, docs and review fixes go into **PR #50**, never a separate implementation PR.
- Mark HPA-922 done only after the acceptance contract has passed. HPA-923/924/925/927/926 remain separate.

## Risk note

Until HPA-923, only Haruto and Mio can be obtained by ordinary play. Their loss of existing R&D campaign bonuses makes Stage 1 a tuning gate; the E–C main-path fixture checks the intended progression after recruitment exists. Stage 2+ need **not** be winnable with two E starters during this intermediate state.

## End-to-end definition of done

- [ ] Enhanced `Character` enum has 12 fixed styles/signatures, rank+level scaling includes all three damage channels, and costs remain style-based.
- [ ] Existing atomic `CampaignSave` v4 key stores two initial E starters, owned levels, squad and stage/Endless results; pre-v4 saves are discarded; save failures and reset are tested.
- [ ] `PlacedTower` is extended (not duplicated), one-of-each, tier 1→2→fixed tier 3, Recall and tap/drag session-authoritative validation pass.
- [ ] **Before UI/art** a headless real `OrionCampaign.stageOne` eight-wave Haruto/Mio victory, module drafts and boss are proven in `flutter test`; main path has an E–C fixture validation.
- [ ] Camp, character sheet, briefing squad and live chibi dock/board pass widget layout tests and **MCP screenshot checks vs Linear mockups 10/11/14/15**.
- [ ] **MCP E2E** covers fresh profile → squad draft/Launch/save → battle interactions → reload/persisted progress/Endless/Codex. Browser combat stepping may reuse deterministic headless victory proof.
- [ ] No live R&D, medal-point spending, wave-unlock cards or choose-a-specialization UI; all tests updated, no old save compatibility code.
- [ ] Each slice is green (`flutter analyze && flutter test`), and final format/CI/coverage/web build checks pass.
- [ ] One PR (#50) contains design, implementation, screenshot evidence and any review fixes; no human acceptance criterion.
