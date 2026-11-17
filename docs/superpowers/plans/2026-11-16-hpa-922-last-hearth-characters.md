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
- Test after each bounded slice, but commit and finish everything in **one PR**. Avoid extracting generic registries, providers or a new architecture.

## Task 0 — Pin baseline and mockup references

1. Confirm current main: GameSession, OrionDefenseGame, TowerComponent, TowerStatsResolver, CampaignProgressStore, OrionGamePage, OrionMenuShell, StageBriefingSheet, MissionCommandDock, TowerInspector, Codex and guide/tips.
2. Capture current working web flows and save behavior, then compare the four approved HPA-922 attachments **10-camp-roster, 11-character-sheet, 14-briefing-squad, 15-battle** and their HTML source ZIP. Log intended unchanged temporary space art.
3. Identify the approved images/chibi sprites in the Linear attachments; crop/export into independent asset paths by character ID, with no asset generation. Check Flutter pubspec asset inclusion and Flame loading in the target platform.
4. Write down the starter baseline and testing command/runner availability; inspect the existing integration_test/app_smoke_test.dart so its automation is adapted rather than replaced.

Evidence: a short PR description note with baseline screenshots/mockup source references; no extra planning PR or new reusable screenshot framework.

## Task 1 — Catalog and deterministic scaling (tests first)

Expected production: lib/game/models/, lib/game/models/game_models.dart, lib/game/rules/tower_stats_resolver.dart, GameBalance in game_models.dart.  
Tests: new focused character catalog/rules tests, test/game/game_balance_test.dart, test/game/tower_stats_resolver_test.dart.

1. Write failing tests for 12 unique IDs, exact name/rank/style/fixed-signature mapping, matching signature style and two E starters. Include all S/A/B/C/D/E ranks and level bounds 1–40.
2. Implement the immutable character catalog (no database): ID, rank, label/role/bio, combat style, signature, base stat multiplier and growth-per-level scalars. Centralize numeric tuning in GameBalance/catalog instead of duplicating 12 TowerStats blocks.
3. Extend the pure resolver to take a CharacterDefinition, persistent level and battle tier. Resolve existing base combat style; activate only the fixed signature at tier 3; apply rank and level scalars; then stage and run-module modifiers. Delete tech-tree laser/cryo bonus application.
4. Verify deterministic stat previews and no regression in chain, freeze, splash, pierce, gravity, corrosion or drone stats. Record concrete starter tuning knobs and tests for E vs S, level 1 vs 40 and battle tier 1/2/3.

Stop condition: no view has been modified, yet all character combat computations are pure, testable and exhaustively cataloged.

## Task 2 — Fresh one-profile persistence and atomic save transactions

Expected production: replace lib/game/campaign/campaign_progress_store.dart aggregate/codec and lib/game/campaign/tech_tree.dart usages with a small lib/game/campaign/player_profile.dart and player_profile_store.dart (or equivalent nearby files); OrionGamePage page state/queue.  
Tests: update test/game/campaign_progress_store_test.dart to profile store/codec tests, test/game/campaign_progress_test.dart and page persistence/widget tests.

1. Test fresh default, known stage IDs, medal/endless records, unique owned IDs with 1–40 levels, valid ordered squad (0–6 distinct owned IDs), invalid/corrupt JSON and the old SharedPreferences key being ignored.
2. Implement one immutable PlayerProfile with CampaignProgress, owned-level map and squad list. New key/version only; SharedPreferences store, in-memory store and reset. No migration for v1/v2/v3 campaign saves.
3. Refactor OrionGamePage to retain its existing serial save queue, generation reset guard, last-committed payload composition and targeted optimistic rollback. Both squad edits and stage progress write one full profile. Do not let a failed squad save contaminate the next stage launch; keep feedback and retry affordances.
4. Remove R&D tech points and purchases from page state and CampaignModifiers, preserving side-stage rewards, campaign completion badges and run-module unlock rules. Delete tech-tree-only models/tests instead of leaving no-op code.

Stop condition: clean/reload/reset/save-failure tests pass; the page boots to a profile with exactly Haruto and Mio and no research UI.

## Task 3 — Session rule: one of each, tier progression, recall

Expected production: lib/game/rules/game_session.dart, lib/game/models/game_models.dart, lib/game/rules/tower_stats_resolver.dart.  
Tests: test/game/game_session_test.dart, test/game/placed_tower_test.dart (rename for the new model), test/game/tower_stats_resolver_test.dart.

1. Test the authoritative character ID placement API with session squad: reject unknown, unowned, off-squad, occupied, unaffordable, duplicate, wrong phase and pending-module placement. Two different characters sharing an underlying style **must** both deploy.
2. Replace the generic placed-tower identity with a placed character holding ID, persistent level, battle tier, grid cell and targeting mode. Keep a convenient style stat object for the existing projectile/effect code. Expose squad/deployed/available state via immutable GameSnapshot rather than exposing the session's mutable collections.
3. Convert placement, validation, upgrade and selected-cell previews to character IDs. Tier 1 → 2 uses the existing upgrade-cost seam; tier 2 → 3 automatically activates that character's fixed signature and specialization cost. Remove player-selected specialization branches/actions.
4. Convert Sell to Recall; validate build phase, refund using the existing 70% invested-gold calculation, remove the actor, free the unique deployment ID, and allow a new tier-1 placement. Explicitly test that upgrade + recall + redeploy cannot create extra gold.
5. Update session restart and Endless/new-run behavior so battle tier and deployed statuses reset; immutable profile level and chosen squad do not.

Stop condition: game-session tests cover both placement paths' common mutation entrypoint, all twelve character identities, full tier cycle and Recall.

## Task 4 — Flame integration and character images

Expected production: lib/game/orion_defense_game.dart, lib/game/components/tower_component.dart (retained combat implementation), new small character-art mapping under lib/game/assets/ if useful, pubspec.yaml and approved placeholder image files.  
Tests: test/game/orion_defense_game_test.dart, test/game/tower_component_test.dart and a character image asset contract test.

1. Route tap placement and drag begin/update/commit/cancel by character ID. Recompute preview range from character-resolved stats; ensure drag cancellation cannot accidentally deploy.
2. Pass the placed character into the existing combat component; keep target acquisition, cooldown, projectiles, field/drone ownership and radius/board hit testing unchanged.
3. Render **full-body chibi** from its own character asset path on a **rank-colored ring**, not a generic tower icon. Reuse cached images/Sprite instances; avoid loading assets per frame. Keep sprite art overhang visual-only; gameplay collision/targeting stays on existing geometry.
4. On Recall, tear down the component and associated drones/fields; retain existing feedback sound. On tier change, refresh component stats and signature visuals without changing effect implementations.
5. Test every ID has a usable portrait/chibi resource and at least one Flame-rendered actor uses the approved sprite; do not call the HPA-924 art generator in this task.

Stop condition: board placement and combat on the actual game component still work; the character is visually present and unique per ID.

## Task 5 — Camp/menu and squad briefing

Expected production: lib/game/ui/orion_menu_shell.dart, lib/game/ui/orion_game_page.dart, new lib/game/ui/camp_view.dart (and focused sheet widgets only if needed), lib/game/ui/stage_briefing_sheet.dart.  
Tests: new Camp widget tests, test/widget/orion_menu_shell_test.dart, test/widget/stage_briefing_sheet_test.dart, page profile-save/widget tests.

1. Replace Map/R&D/Codex with Map/Camp/Codex, replace the R&D page and resource chip, retain the existing theme/top bar/scroll behavior. Delete tech_tree_view.dart and dead test fixtures.
2. Camp uses catalog + owned IDs from profile to display the 12-card roster in mockup 10 order. Owned/unowned and rank are visible. Selecting any entry opens a read-only sheet with name, bio, role, stats, fixed signature and approved portrait as in mockup 11. HPA-923's Level up control is not rendered.
3. Briefing receives committed squad/roster data and displays squad slots and a picker as in mockup 14. Permit reordering/deselecting/selecting only owned IDs, max six, no duplicate IDs. Zero selection prevents launch with clear feedback.
4. Persist squad selection using the page's transactional profile save, and ensure sheet state reflects successful/failed saves without stale route-held data. A stage is launched only with the committed squad. Keep existing mission/replay/Endless choices and stage modifier tip.
5. Test 320×568, tall and high-text-scale layouts, keyboard view in any searchable subview, navigation semantics and no overflow.

Stop condition: starting a new run from briefing always has the persisted selected squad, not a transient UI-only list.

## Task 6 — Battle dock, inspector, onboarding and Codex

Expected production: lib/game/ui/mission_command_dock.dart, lib/game/ui/tower_inspector.dart, lib/game/ui/mission_chrome.dart, lib/game/ui/orion_game_page.dart, lib/game/onboarding/, lib/game/codex/codex_data.dart, lib/game/ui/codex_view.dart.  
Tests: focused dock, inspector, onboarding and Codex widget/unit suites; adjust scene-parity fixtures.

1. Reuse the existing eager horizontal build rail and drag interactions but populate only the current squad, in squad order. Cards show chibi, name/rank, deploy cost and status. Deployed cards cannot place again; insufficient gold is explained.
2. Replace inspector specialization cards with one fixed tier-3 signature action and preview, then a max-tier state. Rename Sell to Recall and preserve existing targeting/pause/wave widgets and semantics.
3. Update new-player guide anchors/copy: first build cell → Haruto/Mio card → wave → tier-2 upgrade → Salvage Module → scanner. Revise obsolete wave-unlock and two-choice specialization tips; keep boss, targeting and stage-modifier tips. Rewrite, don't skip, corresponding tests.
4. Convert the searchable Codex's Towers presentation to character identity/fixed-signature prose; retain its search, section scroll, enemy/trait/effect/stage pages and existing stage progression.
5. Remove dead wave-unlock checks, R&D points, specialization-choice actions, tech-tree test files and UI assets no longer referenced. Do not alter unrelated art themes or asset/audio generation code.

Stop condition: no reachable screen advertises generic wave-unlocked towers, selectable specializations or R&D, while existing gameplay affordances remain active.

## Task 7 — Balance and real gameplay proof

Tests: adapt integration_test/app_smoke_test.dart or a focused Flutter integration test; add a deterministic full-wave scenario in the game integration harness.

1. Run the actual Stage 1 (Outpost Alpha) **eight-wave** scenario with only Haruto and Mio. Deploy, upgrade and activate signatures, start/tick through real spawns and attacks, accept module draft offers, defeat the wave-8 boss and commit a win. Do not call finishActiveWave or fabricate StageCompletion to claim success.
2. Adjust only starter rank/battle-tier combat or deployment costs in GameBalance until the scenario is repeatably feasible, plus a small early E–C fixture along the main route. Do not add a special-case stage-1 bypass.
3. Assert saved medal, unlocked replay/Endless, unchanged stage reward/blueprint/campaign modifiers and no duplicate character placement in the tested run. Cover loss/restart and one recall/redeploy branch.
4. Validate all twelve characters against their fixed styles/signatures in unit/session tests; do not require recruiting them in this ticket (that is HPA-923).

Stop condition: a machine-run complete stage proves the starter loop is actually winnable at the current balance settings.

## Task 8 — MCP end-to-end and screenshot-based visual acceptance

Use the supported **browser/Playwright MCP** on one representative web Chrome build; record tool-run evidence, screenshots and exact build/commit SHA in the same PR's description or docs/superpowers/validation/ record. If Chrome MCP cannot drive the Flame canvas reliably, pair it with the Flutter integration-test runner for gameplay actions; still use MCP for navigation and screenshot verification. Do **not** replace MCP execution with manual signoff.

End-to-end acceptance sequence:

1. Start fresh, dismiss/complete initial guide as appropriate, open Camp; assert 12 visible catalog entries and only Haruto/Mio owned. Screenshot Camp vs Linear mockup **10**.
2. Open Haruto sheet; assert character bio, rank, stats, signature and absence of Level up. Screenshot vs **11**.
3. Open stage-1 briefing; deselect/reselect starters, check zero-squad gating and persisted order after a browser reload. Screenshot selected squad vs **14**.
4. Launch, deploy Haruto + Mio via UI, reject a second Haruto, upgrade to tier 2 and trigger fixed tier 3, Recall/redeploy in build phase, then reach a real stage-1 victory via the integration scenario. Screenshot live board and dock vs **15**.
5. Reload; verify medal and squad persist, level is still 1, and Endless appears after clear. Use Codex search and at least one first-mission guide/contextual-tip path.
6. Capture additional 320×568 and 2×-text screenshots with no clipping, unreadable overlay, missing chibi or overlap. Compare the four primary shots to approved mockups for hierarchy, spacing, visual states, sprite shape, label legibility and button usability; document justified differences caused by the intentionally unchanged space board/background.
7. Assert there is no R&D tab, research points, wave-unlocked tower rail or two-option specialization UI. Check reduced-motion and accessibility semantics by widget/integration test.

One platform is sufficient because HPA-922 is shared Flutter/Flame code with no platform-specific behavior change. No human acceptance step.

## Task 9 — Cleanup, repository gates and handoff (same PR)

- Run Dart formatting, flutter analyze, full flutter test (plus coverage), flutter build web --release, and existing GitHub CI/integration gates. Preserve the project's configured coverage thresholds.
- Fix obsolete test constructors/fixtures rather than maintaining fake legacy tower/tech-tree APIs. Remove dead files and unused images only if this ticket actually makes them unreferenced; avoid wholesale repo art cleanup.
- Review final diff for old strings (R&D, research points, tower unlock, Choose specialization) reachable through UI, imports of tech_tree.dart and obsolete profiles. Internal combat labels may remain by explicit design.
- Attach MCP screenshot comparison results and full-wave test evidence on the PR. Update this draft PR with implementation in place; do not create a separate PR.
- Update HPA-922 only when its tests, gameplay and screenshots satisfy the checklist. Leave HPA-923/HPA-924/HPA-925/HPA-927/HPA-926 separate.

## End-to-end definition of done

- [ ] New profile has two E starters, one immutable saved aggregate, a persisted squad and saved stage/Endless results; old saves are ignored.
- [ ] All 12 catalog mappings and rank/level/tier stats pass deterministic tests.
- [ ] One-of-each placement, same-style distinct characters, recall/refund/redeploy, fixed signature and tap/drag paths pass rules and integration tests.
- [ ] Real 8-wave Stage 1 with two starter characters reaches a committed win automatically.
- [ ] Camp, sheet, briefing and chibi battle screenshots have been inspected against approved mockups 10/11/14/15 by an MCP-driven run; compact/high-text cases are checked.
- [ ] Full MCP E2E covers fresh profile → squad edit/save/reload → battle → victory → restart/reload → persisted result/Endless; Codex, guide/tips and module draft still work.
- [ ] No live R&D, medal-point spending, wave-unlock cards or choose-a-specialization control; legacy code and tests removed.
- [ ] Format, analyze, unit/widget/integration suites, web build and required CI/coverage checks pass on final PR head.
- [ ] The implementation, design docs, validation notes and any scoped review fixes live in this **one PR**. No manual/human signoff acceptance condition.
