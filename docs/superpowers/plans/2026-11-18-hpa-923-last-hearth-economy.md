# HPA-923 — Scrip economy, permanent levels and signal flares (Implementation Plan)

Date: 2026-11-18  
Linear: https://linear.app/cwchanap/issue/HPA-923/orion-scrip-economy-character-levels-and-the-signal-flare  
Spec: [HPA-923 design](../specs/2026-11-18-hpa-923-last-hearth-economy-design.md)  
Baseline: `main` @ `f8f89afc4b6760d2ceaf9c8b4b66b4dd6875c15e` (HPA-922 complete)  
**PR strategy: one draft PR for this ticket.** Add implementation, tests, screenshots and review fixes to this same PR. Do not open a second PR when planning is approved.

## Delivery principles

KISS/YAGNI: extend `CampaignSave` and the page's existing committed-base `_persistSave` queue, consolidate the three committed-state fields into **one aggregate**, add two per-stage Scrip fields to `StageDefinition`, and use pure functions under `rules/` plus a small Flutter `FlareView`. No wallet service, backend, network, gacha framework, migration layer, external images, or new gameplay mechanics. HPA-924/925/927 remain **separate art/audio tasks**; HPA-926 owns the full winter retheme. This ticket uses approved existing character portraits and backdrops without generating assets.

Do not change the ongoing in-battle tier/gold mechanics. Permanent level and persistent Scrip live in the player profile only. Ensure each task below compiles before moving on; tasks are implementation slices, **not separate PRs**.

## Task 1 — Pure economy and recruitment balance, tests first

Production:
- `lib/game/models/game_models.dart` — add shared integer Scrip prices, medal percentages, duplicate values, rank-rate weights and level-cost formula in `GameBalance`.
- `lib/game/campaign/stage_definition.dart` and `lib/game/campaign/orion_campaign.dart` — add `firstClearScrip` (bonus) and `replayScrip` (medal-scaled base), both defaulting to 0 for lightweight test fixtures; assign nonzero values beside each of the seven production stages' existing reward/blueprint data.
- Add small `lib/game/rules/stage_scrip_rules.dart` and `lib/game/rules/flare_rules.dart` (or equivalent two pure modules only). Do not put random decisions in widgets or create a second stage-ID registry.

Tests: `test/game/stage_scrip_rules_test.dart`, `test/game/flare_rules_test.dart`, `test/game/game_balance_test.dart` and existing `test/game/orion_campaign_test.dart` validation coverage.

1. Define `levelUpCost(currentLevel)` (60 at 1, 180 at 4, null at 40). Keep `GameBalance.characterMaxLevel` and rank/level stat multipliers from HPA-922.
2. Define `StageScripRules.award(StageDefinition, StageMedal, {required bool firstClear})` as `(firstClear ? firstClearScrip : 0) + floor(replayScrip × medalPercent / 100)`. The seven-stage values come from the spec's table, now stored on the stage instances, not a string-keyed `GameBalance` table. Stage 1 first Clear = 1,000, Gold = 1,050; replay = 100/125/150. Stage 2 Clear first = 300 and replay = 120. Unknown test stages use the provided zero defaults without throwing.
3. Extend `OrionCampaign.validateStages` to require both Scrip fields >0 for **production campaign stages**, and to assert the Stage-1 **total Clear-medal first payout** (`firstClearScrip + replayScrip`) is at least ten single-flare prices. Preserve the existing 40-ish `StageDefinition` test fixtures via zero defaults; validate those only when explicitly checking the production campaign rules.
4. Define `flare` rank weights (10,50,200,1000,2000,6740 basis points) and uniform same-rank character selection by injected RNG, using the existing page injection approach of `moduleOfferPicker`. `FlareRules.roll(owned, count, random)` returns a pure, ordered `FlareBatch` with 1 or 10 outcomes and duplicate refunds. Its new/duplicate classification considers earlier draws within the same batch. No wallet mutation or UI rolls in this rule.
5. Underfunded, invalid-level and cap checks belong to pure `CampaignSave` transforms in Task 2; the UI also disables obviously invalid controls. Tests check roll boundaries, fixed seeds, every rank/refund, duplicate of an in-batch recruit, seven-stage validation, onboarding guarantee and the sum of all rates.

**Gate:** `flutter analyze` and focused rule tests pass. No UI or persistence calls in either rule file.

## Task 2 — Extend the existing v4 campaign save and queue

Production:
- `lib/game/campaign/campaign_progress_store.dart` — add **required** immutable `int scrip` (no constructor default) to `CampaignSave`, encode/decode `scrip` in the **same v4 record/key**. Missing or invalid Scrip defaults to 0 while preserving other valid fields; do not bump version or create migration code. Add `copyWith` and pure `withLevelUp(Character)`, `withFlareBatch(FlareBatch)` and `withMissionWin(stageId, StageResult, int scripAward)` (and retain `withSquad` through `copyWith`).
- `lib/game/ui/orion_game_page.dart` — replace `_committedProgress`/`_committedOwnedLevels`/`_committedSquad` with one `CampaignSave _committed`; read displayed Scrip from `_committed.scrip`, **without** an extra `_scrip`/`_committedScrip` pair. Keep existing UI-only projections for progress/owned/squad where needed.

Tests: extend `test/game/campaign_progress_store_test.dart` and page save/reset widget tests.

1. Fresh save is 0 Scrip, Haruto/Mio level 1, both in squad. Codec round-trip keeps Scrip, owned levels, squad, best medals and Endless records. The **required** constructor argument makes missed creation sites compile errors.
2. Replace manual `CampaignSave(progress: …, ownedLevels: …, squad: …)` reconstructions with `copyWith`, including `withSquad`, mission victory, Endless saves and reset. No operation may zero the wallet accidentally.
3. Make `CampaignSave` transforms pure and directly testable without widget pumps: `withLevelUp` validates ownership, level cap and funds; `withFlareBatch` checks full initial affordability, applies recruit/refund results and preserves squad; `withMissionWin` records best progress and credits a nonnegative captured award. **Invalid inputs throw `StateError`** and are routed to existing `_persistSave.onFailed` via its catch. Do not invent another result/abort framework or return unchanged save for invalid input.
4. Retain `_saveQueue` committed-base ordering, generation/reset guard, no optimistic durable writes, first-load recovery and retry behavior. `_persistSave` takes `_committed` as its input and updates **the whole committed aggregate only on successful save**; load/recovery/reset replace the aggregate together. UI-only `_progress`/`_ownedLevels`/`_squad` are still projected as necessary, but Scrip reads only from committed state.
5. Test two queued purchases/progress saves composing correctly; failure in the first/second operation leaves the last *actually committed* Scrip and roster intact after reload. Reset erases Scrip. Existing pre-v4 reset tests remain; v4 with no `scrip` loads 0 without losing valid roster/medals.

**Gate:** `flutter analyze && flutter test`. All old persistence and Stage-1 starter gameplay tests still pass.

## Task 3 — Credit every successful mission clear once, even when best is unchanged

Production:
- `lib/game/ui/orion_game_page.dart` — adjust `_handleStageWon`, `_saveMissionResult`, `_missionSaveState` and per-run reward state; keep the current `_persistSave` queue.
- `lib/game/ui/mission_report_content.dart` and `mission_report_panel.dart` — reuse `MissionRewardFact` as `List<MissionRewardFact> rewards`: separate blueprint and Scrip entries, sharing the existing display styling; no Scrip-specific fact type.

Tests: extend `test/game/mission_report_content_test.dart`, `test/widget/mission_report_panel_test.dart`, existing page persistence/widget tests.

1. Remove the old `!result.isBetterThan(prior) => saved` shortcut. On the **first** StageCompletion per mission attempt, always queue one win transaction for `RunMode.mission`. No Scrip on losses or Endless (Endless still saves its best-wave record as before).
2. In `_handleStageWon`, compute the **exact** Scrip award once via `StageScripRules.award(stage, result.medal, firstClear: _missionPriorResult == null)`. The prior result was captured from the committed profile **at stage launch** and already drives one-time blueprint reward presentation; do not independently recompute first-clear inside the queue or on Retry. Store the award with `_missionVictoryResult` until the attempt ends.
3. Inside the queued build closure, call `committed.withMissionWin(stageId, result, capturedAward)` to retain the best medal/HP (via `recordResult`) and credit Scrip together, even when best remains unchanged. The existing `_missionSaveState` stays `saving` until the aggregate save succeeds; on failure keep wallet/best unchanged, show `Retry Save`, and retry **the same captured amount**. Double callback, double-tap, report rebuild and loss→replay must not pay extra.
4. Convert `MissionReportContent.reward` to `List<MissionRewardFact> rewards`, rendered as separate blueprint/Scrip facts. The report can show the **exact pending amount** before persistence, but only says `credited` on committed success; on failure it says `not credited`. Keep one-time blueprint recovery and navigation behavior.
5. Test: first clear pays ≥1,000; non-improving replay still pays >0; higher-medal replay pays more; award survives reload; failed save preserves prior Scrip and medal, then Retry saves once **with unchanged award**; double callback/tap does not double-pay; Endless/loss pays nothing; stage results, modules and blueprint rewards still work.

**Gate:** `flutter analyze && flutter test` and the deterministic HPA-922 eight-wave Stage-1 game-loop fixture remain green. The replay-payout regression test is mandatory.

## Task 4 — Permanent level-up on the existing Camp sheet

Production:
- `lib/game/ui/camp_view.dart` — extend existing `_CharacterSheet`; add just the callbacks/saving state needed for level purchases.
- `lib/game/ui/orion_game_page.dart` — one queued `_persistSave(buildSave: (committed) => committed.withLevelUp(character))` callback; validation/mutation are pure `CampaignSave` logic, while the page publishes only on commit.

Tests: `test/widget/camp_view_test.dart`, page purchase/persistence tests, `test/game/tower_stats_resolver_test.dart`.

1. Show current level/40, Scrip and next-level cost; render before/after stats using the **existing** `GameBalance.characterScalingFactor` and `TowerStatScale` for relevant secondary channels (corrosion/drone) without inventing new stats.
2. Upgrade one owned character by one level per press. Insufficient Scrip and level 40 disable Level Up with readable reasons. Busy state is single-flight.
3. `withLevelUp` performs an atomic Scrip debit and level increment with ownership/funds/cap checks against the committed profile, throwing `StateError` for invalid attempts (existing queue `onFailed` path). On write failure the button remains retryable, visible level/balance does not change, and the UI does not navigate. After reload, the level raises actual battle resolver stats.
4. Verify compact layouts, back navigation, accessibility and a still-readable locked roster. No separate level-up dialog or animations unless the artboard requires one.

**Gate:** `flutter analyze && flutter test` with level cap, cost, stat growth and failure/persistence tests.

## Task 5 — Flare navigation, purchases, 10-pull results and rate disclosure

Production:
- Add `lib/game/ui/flare_view.dart` (compact screen + its result state; split only if the file becomes unwieldy).
- `lib/game/ui/orion_menu_shell.dart` — `OrionMenuDestination.flare`, fourth tab ordered Map/Camp/Flare/Codex, Scrip resource chip alongside existing medal/settings affordances.
- `lib/game/ui/orion_game_page.dart` — `_ShellView.flare`, view wiring, injected RNG (same seam style as `moduleOfferPicker`), and one atomic `_persistSave` flare callback that applies a pure batch via `withFlareBatch`.

Tests: `test/widget/orion_menu_shell_test.dart`, new `test/widget/flare_view_test.dart`, page purchase tests.

1. Show fixed six rank rates, current balance and one/tens flare buttons. One costs 100; ten costs 1,000. Disabled states derive from the committed wallet and pending-save state (never from a speculative future refund).
2. In the queued `buildSave` closure call `FlareRules.roll(committed.ownedLevels.keys, count, random)`, then `committed.withFlareBatch(batch)`. The pure transform rechecks upfront funds, deducts the full fee, and applies all recruits/refunds in **one aggregate**; invalid inputs throw `StateError` via the existing queue failure path. Capture that batch and reveal it only in `onCommitted`. A save failure leaves the screen in place, with no results revealed and no currency/roster change; a retry makes a fresh roll. Do not build production seed/debug hooks.
3. Show 1 or 10 tiles/cards in draw order with character portrait/rank, NEW vs DUPLICATE, each refund, total refunded Scrip and resulting balance. Reuse existing approved portraits/backdrop; no asset generation.
4. Do not automatically edit the squad on recruitment. Updated roster is visible in Camp immediately and after restart; the existing briefing picker can select newly owned characters.
5. Keep Scrip visible across Map/Camp/Flare/Codex and make four tabs fit at 320×568 without clipped rates, controls or settings. Preserve title-view navigation, medals and the existing Settings affordance.

**Gate:** `flutter analyze && flutter test`; 1-/10-pull seeded tests, duplicate in same batch, failed-save rollback, correct tab order and high-text-scale widget tests pass.

## Task 6 — Briefing payout information, result polish and regression coverage

Production: `lib/game/ui/stage_briefing_sheet.dart`, relevant game-page projections, report/Flare widgets as needed.

Tests: `test/widget/stage_briefing_sheet_test.dart`, `test/widget/mission_report_panel_test.dart`, `test/widget/scene_parity_regression_test.dart`.

1. Briefing shows Scrip projection for **first clear versus replay** and how medal improves the variable component. Do not display an exact as-yet-unknown run medal payout. Stage 1 makes the ten-flare guarantee legible.
2. Mission report visibly distinguishes **best medal saved** from **Scrip earned this run** using separate entries in `List<MissionRewardFact> rewards`, keeping blueprint rewards intact. Pending shows the captured amount, saved means credited, and failed means **not** credited.
3. Regression: Camp sheet/back, stage briefing squad draft and Launch, Gold/boss/Endless result reports, Codex search, guide/tips, settings, and old character battle dock still work.
4. Widget-level visual assertions at **320×568 and 2× text scale**, touch targets/semantics and a missing-portrait fallback; no four-tab overflow.

**Gate:** `flutter analyze && flutter test`, targeted screenshot fixtures and existing parity tests pass.

## Task 7 — Required MCP end-to-end acceptance and screenshot comparison (same PR)

Use **Chrome DevTools MCP**, as in `docs/superpowers/validation/2026-11-16-hpa-922-character-squad.md`, against a Flutter web debug server and **isolated browser profile**. A second mobile platform is unnecessary because no platform-specific behavior changes. Capture tested head commit, browser/device size, screenshots and objective pass/fail evidence in `docs/superpowers/validation/2026-11-18-hpa-923-economy.md` or the PR description. The HPA-922 run already completed all eight Stage-1 waves in the browser; prefer that real flow. If live wave stepping proves unreliable, the **existing headless real Flame game-loop Stage-1 victory fixture** supplies wave-completion proof, while MCP exercises UI/save/reload.

MCP sequence:
1. **Fresh profile → Map/Camp:** assert 0 Scrip, 2 E starters, four tabs, existing medal and Settings actions, and no purchase while underfunded.
2. **Stage 1 win:** play the real eight waves through the browser (as HPA-922 did); if automation is unreliable, run the deterministic real eight-wave test and seed the existing **v4 campaign JSON in isolated browser `localStorage`**, then reload to check UI. Verify the actual SharedPreferences web key/prefix, preserving unrelated storage. Assert first-clear Scrip **≥1,000**, mission report pending→saved, and persisted top-bar balance after reload.
3. **Flare purchase:** open Flare, assert all six rates, disabled Fire 10 when below threshold, then afford/fire ten after Stage 1. Verify ten ordered outcomes, per-duplicate labels/refunds and committed final balance. Return to Camp and see the newly owned roster (the seeded pure test separately proves first/new and duplicate cases).
4. **Level Up:** purchase an affordable starter level, assert cost, preview and subsequent increased level/stats. Reload and verify both Scrip debit and level persist; start a run and assert resolver/character level is reflected.
5. **Replay and save failure:** win the same stage with a non-improving best; verify **additional** Scrip exactly once and retained best medal, then reload. Temporarily override the browser `localStorage` getter or write path to throw a quota/storage error (the documented HPA-922 MCP technique), assert Retry Save and unchanged committed data, restore storage, retry, and confirm exactly one award. Exercise a failed Flare/Level Up transaction the same way. Remove overrides and restore the isolated test state afterwards; **do not add any production test hooks**.
6. **Regression paths:** stage briefing squad selection/launch, 1-flare flow, Codex, Endless (no Scrip award), module/medal display and Settings remain accessible.
7. **Screenshots:** visually compare **HPA-923 Linear artboard 11** (sheet with cost/Level Up), **12** (Flare + rates), **13** (batch results + duplicate totals), **14** (briefing projected Scrip), plus mission report. Record exact expected vs actual hierarchy, currency numbers, labels, card spacing, disabled/enabled states, clipping and responsive changes. One compact 320×568 screenshot and 2× text check; use attached approved artboard sources as references. Differences due to old background art are explicitly accepted **only until HPA-926**.

No human acceptance/approval criterion. Fix issues in **this PR** and rerun the affected MCP checks.

**Gate:** all mandatory MCP UI flows and screenshot comparisons have recorded evidence; deterministic headless victory, failure injection and all relevant widget/unit tests pass.

## Task 8 — Final checks and handoff (same PR)

Run:
```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
flutter build web --release
```

- Inspect GitHub CI for the final implementation head. Include covered Stage-1 victory, seeded rank table, replay payout and failure/retry tests.
- Review for dead code/new service layers, wallet reconstruction bugs, unintended Scrip in Endless, gacha/pity logic and accidental art/SFX changes.
- Link the one PR to HPA-923; leave HPA-926 blocked until economy plus its independent asset dependencies finish.
- Keep this design and plan in the PR alongside implementation and `validation/` evidence; **no second PR**.

## End-to-end acceptance criteria (all mandatory)

- [ ] Fresh profile begins with 0 Scrip and Haruto/Mio at level 1; Stage-1 first clear credits ≥1,000 Scrip. Replay earns Scrip on **every successful mission win**, even an unchanged best; medal increases the award. No loss/Endless payout.
- [ ] Per-stage Scrip fields live on existing `StageDefinition` instances with production campaign validation (including Stage-1 first-clear ten-flare guarantee); shared flare 1/10 prices, six rates (sum 100%), level price, medal multiplier and duplicate refunds live in `GameBalance` + pure tested rules.
- [ ] One- and ten-flare draws atomically consume Scrip, recruit previously unowned characters at level 1, refund duplicate dog tags including within the same batch, show ordered results, and never fire below cost.
- [ ] Camp levels an owned character to max 40 using committed Scrip; actual battle damage, corrosion or drone channels increase at the saved level; no level gain when underfunded or capped.
- [ ] One v4 `CampaignSave` stores Scrip, roster, levels, squad, stage results and Endless bests in the existing key. `scrip` is required on construction; `copyWith` and validated `withLevelUp`/`withFlareBatch`/`withMissionWin` transforms preserve unrelated fields. The page has one `_committed` aggregate, **no parallel Scrip fields**. Restart, reset, two queued writes, failed purchase and failed victory/retry behave atomically without double rewards.
- [ ] Map/Camp/Flare/Codex, top-bar Scrip, rate table, result screen, Level Up and projected/actual Scrip reports remain readable and operable at 320×568 and 2× text scale; relevant semantics/buttons work.
- [ ] **MCP E2E** shows fresh start → Stage-1 win → 10 flares/results → Camp level purchase → reload → non-improving replay reward → reload, plus key Codex/Settings/Endless/squad regression paths. Use an isolated Chrome web profile and temporary `localStorage` interception/seed instead of production test hooks. The full eight-wave victory is also proven in the existing real-game headless test.
- [ ] **MCP screenshots visually checked against Linear 11/12/13/14**, mission report, and responsive compact view. Evidence (tested SHA, screenshots, pass/fail and intentional old-backdrop differences) is committed or linked in this PR.
- [ ] Dart formatting, `flutter analyze`, `flutter test --coverage`, web release build and final-head GitHub CI pass.
- [ ] **One PR per HPA-923** includes spec, implementation, tests, visual/MCP evidence and review fixes. Art and SFX remain in HPA-924/925/927; no human signoff is a gate.
