# HPA-699 — Arcade Command Deck UI Revamp (Implementation Plan)

**Linear:** https://linear.app/cwchanap/issue/HPA-699/orion-revamp-the-game-ui-so-it-looks-like-a-real-game  
**Design authority:** ../specs/2026-11-06-hpa-699-arcade-command-deck-revamp-design.md  
**Reference:** Linear attachments (eight mockups, design kit, HTML archive with kit.css and board.js)  
**Workflow:** Documentation-only **draft PR now**; implementation and tests added to **the same PR** after review. Do not open one PR per section.

## Preflight: what is already implemented

| Area | Current owner | What changes |
|---|---|---|
| App navigation | lib/game/ui/orion_game_page.dart (_ShellView) | Add title and shared menu chrome; keep enum switching |
| Theme / fonts | orion_ui_theme.dart, orion_theme_data.dart, orion_typography.dart | Exact semantic palette and larger label roles from kit.css; keep vendored fonts |
| Surface system | orion_surface.dart, mission_surface.dart, test/widget/design_system_tripwire_test.dart | **Task 1:** replace `OrionSurface` blur/decorations in place; migrate Inner/Mission adapters and old t1–t4 enum atomically; update surface tests and blur tripwires once |
| Sector map / briefing | world_map_view.dart, stage_briefing_sheet.dart, sector_map_layout.dart | Visuals and controls; reuse layout/route/status calculations |
| Battle | mission_chrome.dart, mission_command_hud.dart, mission_command_dock.dart, next_wave_scanner.dart | Recompose status, pacing, intel and one-row tray; preserve callbacks/snapshots |
| Tower actions | tower_inspector.dart, mission_chrome.dart, hold_to_salvage.dart | Visual sheet/radial, six visible modes and unclipped scroll |
| End state | mission_report_panel.dart, mission_report_content.dart | Medal/outcome layout; preserve World Map callback and every save-state exit gate |
| Endless (HPA-715, already merged) | stage_briefing_sheet.dart, mission_command_hud.dart, next_wave_scanner.dart, mission_report_panel.dart | Preserve cleared-stage entry/best, unbounded waves/health scaling, and no-medal/no-reward defeat report; visual changes only |
| R&D | tech_tree_view.dart, campaign/tech_tree.dart | Network presentation only; campaign/tech_tree.dart is read-only |
| Codex | codex_view.dart, codex/codex_data.dart | Grid/tab/detail presentation; codex_data.dart is read-only |
| Board | components/board_component.dart, board_backdrop_component.dart, enemy_component.dart | Paint-only changes; rules and models are read-only |
| Other UI | feedback_settings_sheet.dart, run_module_draft_panel.dart, command_toast.dart, first_mission_guide_callout.dart, contextual tips, mission surfaces | Align chrome without changing business or tutorial logic |

Use this as a **file map, not a mandatory set of new layers**. Add only small reused widget files (likely one compact arcade-kit file, a menu shell and a title view) when they remove genuine duplication.

## Task 0 — Pin visual evidence and existing behavior

1. Open the Linear HTML attachment and inspect kit.css and board.js. **Record** exact semantic colors, gradients, border/lip sizes, shadows, button states and board-draw parameters in a **permanent table in the design spec**, with corresponding CSS selector/JS source notes; do not leave these only in ephemeral PR comments. No guessed values.
2. Confirm the eight attached artboards against actual stage-specific data; mark intentionally illustrative numbers/copy as non-authoritative.
3. Capture baseline scenes at 390×844 using the existing ORION_CAPTURE_DIR helper/test/support/reactor_rim_visual_capture.dart, and inspect 360×640 for present clipping. Preserve before images for final PR evidence, not as checked-in generated assets.
4. Run flutter analyze and flutter test before starting; record unrelated baseline failures instead of fixing them via this UI ticket.
5. HPA-715 **already merged** as PR #46 on 2026-11-08. Rebase this **same HPA-699 branch** onto current `main` before implementation; inspect the shipped Endless briefing, HUD/scanner, result-save and report paths as baseline. Adapt the restyle around them; do not implement Endless inside HPA-699.

**Done:** the design spec contains the reference-token table; baseline captures and test/analyzer results are recorded. No new dependencies or assets were created.

## Task 1 — Build the new theme and minimal solid kit

**Production:** `orion_ui_theme.dart`, `orion_theme_data.dart`, `orion_typography.dart`, `orion_primary_button.dart`, **existing** `orion_surface.dart`, deprecated `mission_surface.dart` and its ~31 call sites, plus surface/typography/tripwire tests. **Do not add a parallel solid-panel primitive.** Reuse and simplify the existing surface path. New small widgets only where a second real screen reuses them.

1. Extend OrionUiTheme semantic roles for amber primary action, selection/info cyan, credits gold, violet research, gains green, warning orange, danger red and medal ranks. Derive layout primitives, shadows and gradients from the attached kit.css. Keep existing base colors when their intended role has not changed.
2. Add **`fontFamilyFallback: ['ChakraPetch']`** to existing `OrionTypography.readout` and `.title` (the registered ChakraPetch face contains U+2192; Oxanium does not). **Do not create an arrow helper or patch each comparison separately.** Set the default `OrionTypography.microLabel` and `OrionText.micro` size to >=10; `assert(size >= 10)` for explicit overrides, update all existing 8/9px calls **in Task 1** and verify 360px layouts. Move the shared shadow literal into a semantic theme token.
3. **Rewrite `OrionSurface`/`_tierDecoration` in place** to render the kit's solid framed panels (no blur) for all existing call sites. In the same foundation change, mechanically replace `OrionInnerSurface` and the deprecated `MissionSurface` with `OrionSurface`, delete their implementations, and replace t1–t4 **blur tier names** with a small semantic role enum only where floating/card/sheet/shelf variants truly differ. Migrate all ~31 surface usages and affected tests at once, so there is **one surface API and no Task 5 migration**. Add only genuinely reused chip/tag, stat bar, segmented, tab, top status and medal widgets when needed by screens.
4. Extend `OrionPrimaryButton` with required primary/secondary/destructive variants, pressed/disabled/loading states. Reuse **`orionPressDuration` (90ms)** via `orionMotionDuration`; no new motion constants. Keep icon-only semantics on icon controls and preserve focus and touch targets.
5. **Move invariant tests into Task 1**, extending `design_system_tripwire_test.dart` and its existing `_libDartFiles()` scan: reject `BackdropFilter`/`ImageFilter.blur`, old tier/adapter APIs, and raw `Color(0x...)` literals outside `orion_ui_theme.dart` in game UI. Start a narrow file allowlist only for raw colors in screens that have not yet been restyled; remove each file as its task lands, and reach an **empty allowlist in Task 5**. Include the existing `OrionTypography.shadow` color migration. Keep the unrelated useful tripwires.

**Tests:** update/replace `test/widget/orion_ui_theme_test.dart`, `orion_typography_test.dart`, `orion_surface_test.dart`, **delete `mission_surface_test.dart` if its adapter is gone**, and update primary-button/tripwire tests in the same foundation commit. Verify surface roles, no blur, 10px label floor, Chakra Petch arrow rendering with real bundled fonts, pressed/disabled/loading semantics, and reduced motion.

**Done:** all game UI surfaces use **one solid `OrionSurface` implementation**, with no old blur tier or adapter; foundation assertions/tripwires pass, and `dart format . && flutter analyze && flutter test` are green **before committing Task 1**. Subsequent tasks focus on layout and shrinking the palette allowlist, not migrating panel APIs.

## Task 2 — Title and shared menu shell

**Production:** lib/game/ui/orion_game_page.dart, new title/menu-shell widgets as needed, world_map_view.dart, stage_briefing_sheet.dart, feedback_settings_sheet.dart.

1. Add `_ShellView.title` as the **production** post-load initial view. **Reuse** `_progress.recommendedStage(OrionCampaign.stages)` — the map's existing stage chooser — rather than duplicating progression rules. If its result is **unlocked/uncleared**, Continue opens `_showStageBriefing` (never `_startStage`); optional stages remain eligible after the main path is complete. If null or the recommendation is the helper's **already-cleared replay fallback**, show **Sectors** instead of a misleading Continue; `isCampaignComplete` controls completed-copy only. For existing world-map-first widget tests, add a `@visibleForTesting` **bool** `startOnWorldMap` (default false), initialize `_activeView` from it once, and have `testGamePage` default true with a title-test opt-out. **Audit direct `OrionGamePage(...)` constructors** in `test/widget_test.dart`, `game_music_page_test.dart`, `sell_button_test.dart`, `feedback_store_construction_failure_test.dart`, `test/feedback/platform_game_feedback_test.dart`; opt map-first cases in **in the same commit as the title-default flip**. Do not expose private `_ShellView` or add test navigation infrastructure.
2. Use the existing artwork and typography for the wordmark/front door; no new logo. Expose shortcuts for Sectors, R&D, Codex and Settings.
3. Refactor menu views so **one shell** owns the top resources/settings and Map/R&D/Codex bottom navigation. Prefer adjusting existing view bodies to fit the shell over introducing nested Scaffold or separate router state. Respect SafeArea and existing tab/view back behavior.
4. In WorldMapView, keep SectorMapLayout's geometry and route hit targets; restyle node status rings, crest frames, medal pips, readable labels, paths and the next-mission card. Remove only superseded utility rail controls: `_RailButton` disappears with `_SectorUtilityRail` rather than becoming an unnecessary lip-button wrapper.
5. Restyle StageBriefingSheet without changing committed-result, rewards, modifiers, onboarding callout or Launch callback logic. On cleared stages, preserve separate Replay Mission / Endless actions, `RunMode.mission` / `RunMode.endless` dispatch and persisted `endlessBest`; neither option may bypass current unlock/commit gates. Ensure a modal above the shared shell remains readable and closable.
6. Move Reset Campaign into Settings. A Reset tap dismisses `FeedbackSettingsSheet` with its **current `_draft` and a reset-intent flag** (a small typed result/record is enough); `Done` saves the draft without requesting reset, while a back/scrim dismissal still discards uncommitted toggles. `_openFeedbackSettings` remains the sole persistence owner: if the draft changed, await `_saveFeedbackPreferences` **before** invoking `_confirmResetCampaign`. Have the save path report success to its caller (the current `Future<void>` swallows failures): on save failure, show the existing preference-save error and **do not show the reset dialog**. If unchanged or saved successfully, invoke the existing reset confirmation; cancelling the confirmation does **not** roll back the already-saved preferences. Reuse `_isResetting`, the campaign save queue and confirmation semantics; never reset with one tap.

**Tests:** extend `test/widget_test.dart`, `world_map_command_deck_test.dart`, `stage_briefing_sheet_test.dart`, `tech_tree_view_test.dart`, `codex_view_test.dart`, `feedback_settings_sheet_test.dart` and reset page tests. Existing **fixture and direct constructor** map-first cases must keep passing; new production-default title tests cover fresh save → Outpost Alpha, cleared main + optional unlocked → the same recommended optional stage as map, all stages done → Sectors, and tab routes. Cover a cleared-stage briefing's Endless launch/best, settings **toggle → Reset → cancel/confirm/save failure**, and ordinary dismiss vs Done.

**Done:** all between-mission navigation works with one top/bottom shell and a real title screen; the title-default + test-fixture seam land as a **single tested commit**, and `dart format . && flutter analyze && flutter test` are green before completing Task 2.

## Task 3 — Mission command layout and board readability

**Production:** mission_chrome.dart, mission_command_hud.dart, mission_command_dock.dart, next_wave_scanner.dart, orion_game_page.dart; later paint work in board_component.dart / board_backdrop_component.dart / enemy_component.dart.

1. Keep OrionGamePage/OrionDefenseGame snapshot callbacks authoritative. Restructure MissionStatusHud into a single framed top bar (hull, phase/wave, credits). Preserve `snapshot.missionWaveTotal == null` as the **unbounded Endless** case; don't supply a finite denominator, and keep the spoken Endless/phase label. Do not recreate game state or add a UI state store.
2. Reposition pause, speed and auto controls as a single pacing owner. On wave phase, support the kit's segmented speed affordance without also showing a second active speed control elsewhere; preserve existing 1×/2×/3× callbacks, pause gating and auto-countdown.
3. Build phase: place existing next-wave intel next to an amber Start Wave; keep TowerBuildRail as one horizontal scrollable row. Surface current gold, tower cost, insufficient-gold and locked-until-wave states from existing snapshots and GameBalance. Replace `_PrimaryActionPill` in `mission_command_dock.dart` with the shared `OrionPrimaryButton` style/variant while preserving its 48dp footprint, tooltip, guides and tap semantics.
4. Wave phase: display progress, hostiles remaining and clear bonus from actual data. Preserve scanner behavior, auto-start countdown, build/wave transition semantics, and first-mission/contextual-guide anchor keys. For Endless, preserve unbounded `WavePreview`/scanner numbering and actual enemy health-scaling copy (including later loops), and **do not** reactivate first-mission guidance on an Endless run.
5. **Keep `WorldMapAction` visible and reachable in build phase**, in the top bar or persistent dock even when a build cell/tower is selected; reuse `game.returnToMap` so the existing build-phase return works. The normal build phase cannot toggle Pause and a wave-phase `returnToMap()` is rejected by the game; therefore **do not move the only exit to a Pause menu**. During active waves (paused or not), hide/disable World Map rather than presenting a nonfunctional exit. A surrender/abandon action would be new gameplay and is out of scope. Leave report save/exit guards unchanged.
6. Implement the board visuals from board.js: darker tone/vignette, legible channel and directional chevrons, more visible spawn/core and enemy drawn sizes. **Only change rendering**; do not touch BoardLayout, GameSession, EnemyLogic, wave definitions, collisions, logic radius, component position or stage modifiers.
7. Inspect overlays after draw-scale changes so boss bars/traits and selection rings still match on-screen sprites. Avoid expensive per-frame shaders/blur and any new package.

**Tests:** mission_command_hud_test.dart, mission_command_dock_test.dart, next_wave_scanner_test.dart, mission_chrome_test.dart, first_mission_guide_callout_test.dart, contextual_tips_gates_test.dart, orion_defense_game_test.dart and focused board/component tests. Assert build-phase World Map can return **with and without an active cell/tower selection**, and that starting/pausing a wave never exposes a misleading actionable exit. Preserve existing phase and save gates; explicitly test Endless **wave beyond finite script length** with no denominator, correct scanner scaling copy, and guide suppression. Visually verify drag/rail and overlays on both target viewports.

**Done:** battle communicates state at a glance without sacrificing a single placement, preview, or pacing interaction; `dart format . && flutter analyze && flutter test` green for Task 3.

## Task 4 — Inspector, radial and Mission Report

**Production:** tower_inspector.dart, mission_chrome.dart, hold_to_salvage.dart (presentation only), mission_report_panel.dart and mission_report_content.dart (presentation API only if needed).

1. Restyle TowerRadialActions without changing its upgrade/sell/targeting event wiring or accessible actions.
2. Place Sell and Close in the inspector header; preserve the current hold-to-salvage safety gesture. Render all six targeting modes in an adaptive 3×2 grid; keep accurate disabled states.
3. Reuse the existing progression preview calculations to render current/next stat bars and specialization cards. Provide price, cost and upgrade availability from the snapshot rather than copied mockup values. Fold the private `_MissionActionButton` styling in `mission_report_panel.dart` into the shared `OrionPrimaryButton` variants **without changing its report state gates**.
4. Bound the inspector to remaining viewport height; make content scroll while critical Close/Sell stay reachable at 360×640. Test with a tall text scale as well.
5. Rebuild MissionReportPanel visual hierarchy: existing hero art, outcome ribbon, code-drawn medals for normal victory only, and real stats/rewards. Keep **Replay/World Map**, never Report Continue/auto-next-stage. `onReturnToMap` still invokes `_returnFromMissionReport` for normal victory (including completed campaign), loss and Endless defeat. Respect the spec's state table: normal loss Retry/World Map; saving disables both exits; saved enables Replay/World Map; failed exposes Retry Save and World Map (Unsaved), not Replay. Endless loss shows **waves cleared and best-save messages without medals/R&D/rewards**, including zero-wave no-result-to-save and retained-best-on-failure.

**Tests:** tower_inspector_test.dart, sell_button_test.dart, mission_report_panel_test.dart, mission_report_content_test.dart, mission_chrome_test.dart; include all six targeting actions and non-clipped header/scroll footer. Assert World Map callback (no next-briefing) for ordinary and completed-campaign victory, regular loss, plus Endless saved/saving/failed/zero-wave report states with matching enabled actions, save copy, waves-cleared count and no medals/R&D.

**Done:** critical decision/action panels are fully reachable, readable and unchanged mechanically; `dart format . && flutter analyze && flutter test` green for Task 4.

## Task 5 — R&D, Codex and remaining small surfaces

**Production:** `tech_tree_view.dart`, `codex_view.dart`, `command_toast.dart`, `feedback_settings_sheet.dart`, `run_module_draft_panel.dart`, `first_mission_guide_callout.dart` and other screens needing **layout and raw-color cleanup**. Their surface API is already solid from Task 1.

1. Recompose R&D as fixed five-node visually connected hex layout, using the current CampaignTechUpgrade list and current canPurchase/isPurchased states. Paint decorative connector/conduit paths **behind** the real node widgets (simple background `CustomPainter` if helpful) wrapped in `IgnorePointer` + `ExcludeSemantics`; they must never intercept taps, create semantics nodes, or imply unlock prerequisites. Add the bottom detail panel/Research action.
2. Rebuild the Codex tabs as one horizontal row and data as sprite tiles/detail cards while retaining CodexData's existing search terms, per-tab search state, scroll restoration, focus and empty-result UX. Do not rewrite search logic in the styling PR.
3. Bring module draft, tips/tutorial callout, next-wave scanner, feedback settings, toasts and other modal/chrome files into the kit. Preserve callback contracts, persistence and any visibility timer/acknowledgement semantics.
4. **No deferred surface cleanup:** Task 1 already removed the old tiers/adapters and blur. In Task 5, search `lib/game/ui` for remaining raw color/gradient literals, residual 8/9px text, and presentation duplicates. Remove the last raw-color test allowlist entries so all token/tripwire tests pass unconditionally. Do not retain an "unify later" task.

**Tests:** tech_tree_view_test.dart, codex_view_test.dart, run_module_draft_panel_test.dart, command_toast_test.dart, contextual_tips_gates_test.dart, scene_parity_regression_test.dart; verify the five independent R&D purchases, decorative conduits do not consume node taps or appear in semantics, and Codex search keyboard/scroll regressions.

**Done:** no screen or overlay is left looking like the retired glass UI; raw-color allowlist is empty, and `dart format . && flutter analyze && flutter test` green for Task 5.

## Task 6 — Validation, capture and cleanup (same PR)

1. **Re-run**, do not defer, the `design_system_tripwire_test.dart` assertions **installed in Task 1**: no blur, old tier/adapter, missing font fallback, sub-10px labels or unallowlisted `Color(0x...)` literals. Task 5 must have removed the temporary palette allowlist. Keep useful existing checks (no Material `textTheme`, screen titles through `OrionTitle`, no `ColorScheme.fromSeed`).
2. Verify production title boot/Continue, shared map-first test fixture behavior, **build-phase World Map exit (idle and selected-cell) / disabled wave exit (including pause)**, and all UI flows with fresh save, partially cleared campaign, fully completed campaign, unaffordable R&D, locked stage/towers, paused combat, loss, victory, save failure, replay and reset. Include decorative R&D connector hit-test/semantics checks, cleared-stage Endless launch, late-loop unlimited wave/scanner health-scaling display, best record save/saving/failure/zero-wave report, and Settings draft toggle → Reset (cancel/confirm/save failure).
3. At 390×844 capture the title, map, build, wave, inspector, report, R&D, Codex, stage briefing, settings, module draft and relevant tips, **plus cleared-stage Endless briefing, unbounded-wave HUD/scanner and Endless loss report**. Capture before/after evidence in the PR description or review comment; do not commit ephemeral captures unless test infrastructure already expects them.
4. At 360×640 verify no clipping, no hidden/untappable targeting options, no cutoff final tower cards, scroll/keyboard behavior and no render overflow. Check contrast, press animation and missing U+2192 glyphs with real fonts.
5. Run: dart format .; flutter analyze; flutter test; flutter test integration/widget subset as supported by CI. Address only regressions caused by this PR. Verify CI green.
6. Update the draft PR body with implementation status, before/after images, test summary, any visual differences from mockups and explicit non-goals. Mark ready for review **only** once complete; never merge from the planning pass. **Each Task 1–5 must have its own green full-suite gate**, not merely a compiling intermediate commit.

## Scope guard / non-goals

- Do not introduce a router, second design-system package, generic style DSL, scene state store, external graphics/sound generation, build-time CSS renderer or new dependency.
- Do not adjust difficulty, enemy hit areas, R&D prerequisites, medals, rewards, campaign storage, Endless rules/best-save persistence or overall stage layout. Existing Endless UI is in scope for preservation only.
- Do not create a second PR for one ticket. Use multiple commits on this draft PR branch to keep review tractable.
- If code-drawn wordmark/medals/board markers are inadequate, propose a **separate art-only Linear task** for original assets; HPA-699 should not generate them while modifying UI code.
- HPA-715 is already merged into `main` (PR #46). Preserve its released widget contracts and regression coverage; no separate Endless implementation in this ticket.

## Final definition of done

- Every HPA-699 Linear UI requirement is covered; every reference mock is visibly represented using real game data.
- Exact kit.css design values have been applied where specified, with one OrionUiTheme source, no legacy blur, and no missing glyphs.
- At 390×844 the complete shell and battle presentation match the direction; at 360×640 no controls clip. All meaningful actions have correct disabled/locked/busy semantics and reduced-motion fallbacks. Task 1 centralized surface/font/motion behavior; every later task maintained green format/analyzer/test gates.
- All existing gameplay, saves, tutorial, Codex search, R&D affordability, report/World Map navigation, Settings-draft persistence on Reset, campaign flows, and released Endless entry/HUD/scanner/report/save behavior remain correct.
- flutter analyze, flutter test, format and CI pass, with before-and-after captures attached.
- One HPA-699 PR contains planning, implementation and tests, and stays draft until acceptance evidence is ready.
