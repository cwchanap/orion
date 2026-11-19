# HPA-923 — Scrip economy, permanent levels and signal flares (Implementation Plan)

Date: 2026-11-18  
Linear: https://linear.app/cwchanap/issue/HPA-923/orion-scrip-economy-character-levels-and-the-signal-flare  
Spec: [HPA-923 design](../specs/2026-11-18-hpa-923-last-hearth-economy-design.md)  
Baseline: `main` @ `f8f89afc4b6760d2ceaf9c8b4b66b4dd6875c15e` (HPA-922 complete)  
**PR strategy: one draft PR for this ticket.** Add implementation, tests, screenshots and review fixes to this same PR. Do not open a second PR when planning is approved.

## Delivery principles

KISS/YAGNI: extend `CampaignSave` and the page's existing committed-base `_persistSave` queue; pure functions under `rules/` and a small Flutter `FlareView`. No wallet service, backend, network, gacha framework, migration layer, external images, or new gameplay mechanics. HPA-924/925/927 remain **separate art/audio tasks**; HPA-926 owns the full winter retheme. This ticket uses approved existing character portraits and backdrops without generating assets.

Do not change the ongoing in-battle tier/gold mechanics. Permanent level and persistent Scrip live in the player profile only. Ensure each task below compiles before moving on; tasks are implementation slices, **not separate PRs**.

## Task 1 — Pure economy and recruitment balance, tests first

Production:
- `lib/game/models/game_models.dart` — add all integer Scrip prices, 7-stage reward table, medal percentages, duplicate values, rank rate table and level-cost formula in `GameBalance`.
- Add small `lib/game/rules/stage_scrip_rules.dart` and `lib/game/rules/flare_rules.dart` (or equivalent two pure modules only). Do not put random decisions in widgets.

Tests: `test/game/stage_scrip_rules_test.dart`, `test/game/flare_rules_test.dart`, `test/game/game_balance_test.dart`.

1. Define `levelUpCost(currentLevel)` (60 at 1, 180 at 4, null at 40). Keep `GameBalance.characterMaxLevel` and rank/level stat multipliers from HPA-922.
2. Define `stagePayout(stageId, medal, wasAlreadyCleared)` using initial values and integer `100/125/150` medal factors from the spec. Ensure first Stage-1 Clear = 1,000, Gold = 1,050; replay = 100/125/150. Stage 2 Clear first = 300, replay = 120. Cover all seven known stages, including optional ones.
3. Define `flare` rank weights (10,50,200,1000,2000,6740 basis points) and uniform same-rank character selection by injected RNG; batch size exactly 1 or 10, costs 100/1,000. A batch reports each outcome and net balance. An already-owned character, including one recruited earlier in the batch, is a duplicate with the configured refund. No pity.
4. Refuse underfunded purchases before rolling, and never allow a level above 40 or a negative spendable balance to be committed. Define typed result/failure values only where UI/persistence needs them; avoid exception-heavy infrastructure.
5. Pure tests use deterministic roll boundaries (including bucket edges), fixed seeds, every rank/duplicate value, one vs ten affordability, first-new-then-duplicate in the same batch, and a validated sum of all rates.

**Gate:** `flutter analyze` and focused rule tests pass. No UI or persistence calls in either rule file.

## Task 2 — Extend the existing v4 campaign save and queue

Production:
- `lib/game/campaign/campaign_progress_store.dart` — add immutable `int scrip` to `CampaignSave`, encode/decode `scrip` in the **same v4 record/key**. Missing or invalid Scrip defaults to 0 while preserving other valid fields; do not bump version/reset valid v4 users or create migration code.
- `lib/game/ui/orion_game_page.dart` — add `_scrip` and `_committedScrip`, include in load, retry-load, reset, every `CampaignSave` constructor and `_persistSave` build/onCommitted lifecycle.

Tests: extend `test/game/campaign_progress_store_test.dart` and page save/reset widget tests.

1. Fresh save is 0 Scrip, Haruto/Mio level 1, both in squad. Codec round-trip keeps Scrip, owned levels, squad, best medals and Endless records.
2. Convert all aggregate reconstructions to carry Scrip. Do **not** let `withSquad` or an Endless-best save reset it to 0.
3. Retain the `_saveQueue` committed-base ordering, generation/reset guard, no optimistic durable writes, recover-from-load-failure and existing retry behavior.
4. Test two queued purchases/progress saves composing correctly; failure in the first/second operation leaves the last *actually committed* Scrip and roster intact after reload. Reset erases Scrip.
5. Existing pre-v4 reset tests remain; one v4 record with no `scrip` must load 0 without throwing away a valid character roster or medals.

**Gate:** `flutter analyze && flutter test`. All old persistence and Stage-1 starter gameplay tests still pass.

## Task 3 — Credit every successful mission clear once, even when best is unchanged

Production:
- `lib/game/ui/orion_game_page.dart` — adjust `_handleStageWon`, `_saveMissionResult`, `_missionSaveState` and per-run reward state; keep the current `_persistSave` queue.
- `lib/game/ui/mission_report_content.dart` and `mission_report_panel.dart` — independent Scrip award fact alongside existing blueprint and medal result; avoid overloading the single `MissionRewardFact`.

Tests: extend `test/game/mission_report_content_test.dart`, `test/widget/mission_report_panel_test.dart`, existing page persistence/widget tests.

1. Remove the old `!result.isBetterThan(prior) => saved` shortcut. On the **first** StageCompletion per mission attempt, always queue one win transaction for `RunMode.mission`. No Scrip on losses or Endless (Endless still saves its best-wave record as before).
2. Inside the queue, determine first-clear from `committed.progress.resultFor(stageId)`; compute Scrip from this run's medal; call `recordResult` for best-medal/HP logic; add Scrip to the same `CampaignSave`. Capture the credited amount for the report only after the save commits.
3. Keep `_missionSaveState` `saving` until the whole aggregate save succeeds; on failure keep balance/best unchanged and show `Retry Save`. Retry recomputes from committed state; one eventual success yields one credit. Never pay again for duplicate victory callback, multiple retry taps, a report rebuild, or loss→replay transitions.
4. Display Scrip pending, credited, or not credited on the mission report, *even when the best result is retained*. Preserve existing one-time blueprint recovery and navigation during pending writes.
5. Test: first clear pays ≥1,000; non-improving replay still pays >0; higher-medal replay pays more; award survives reload; failed save preserves prior Scrip and medal, then Retry saves once; double callback/tap does not double-pay; Endless/loss pays nothing; stage results and run modules still work.

**Gate:** `flutter analyze && flutter test` and the deterministic HPA-922 eight-wave Stage-1 game-loop fixture remain green. The replay-payout regression test is mandatory.

## Task 4 — Permanent level-up on the existing Camp sheet

Production:
- `lib/game/ui/camp_view.dart` — extend existing `_CharacterSheet`; add just the callbacks/saving state needed for level purchases.
- `lib/game/ui/orion_game_page.dart` — one `_persistSave` callback to purchase a level from the *committed* roster and wallet; publish only on save success.

Tests: `test/widget/camp_view_test.dart`, page purchase/persistence tests, `test/game/tower_stats_resolver_test.dart`.

1. Show current level/40, Scrip and next-level cost; render before/after stats using the **existing** `GameBalance.characterScalingFactor` and `TowerStatScale` for relevant secondary channels (corrosion/drone) without inventing new stats.
2. Upgrade one owned character by one level per press. Insufficient Scrip and level 40 disable Level Up with readable reasons. Busy state is single-flight.
3. One atomic save deducts Scrip and updates the saved level. On failure the button remains retryable, visible level/balance does not change, and the UI does not navigate. After reload, the updated level raises the actual battle resolver stats.
4. Verify compact layouts, back navigation, accessibility and a still-readable locked roster. No separate level-up dialog or animations unless the artboard requires one.

**Gate:** `flutter analyze && flutter test` with level cap, cost, stat growth and failure/persistence tests.

## Task 5 — Flare navigation, purchases, 10-pull results and rate disclosure

Production:
- Add `lib/game/ui/flare_view.dart` (compact screen + its result state; split only if the file becomes unwieldy).
- `lib/game/ui/orion_menu_shell.dart` — `OrionMenuDestination.flare`, fourth tab ordered Map/Camp/Flare/Codex, Scrip resource chip alongside existing medal/settings affordances.
- `lib/game/ui/orion_game_page.dart` — `_ShellView.flare`, view wiring, and one atomic `_persistSave` flare callback.

Tests: `test/widget/orion_menu_shell_test.dart`, new `test/widget/flare_view_test.dart`, page purchase tests.

1. Show fixed six rank rates, current balance and one/tens flare buttons. One costs 100; ten costs 1,000. Disabled states derive from the committed wallet and pending-save state (never from a speculative future refund).
2. In the queued `buildSave` closure roll with the injected RNG against **current committed ownership**; apply all draws/refunds and subtract price **in that single aggregate**. Reveal the ordered results only in `onCommitted`. A save failure leaves the screen in place, no results revealed and no currency/roster change.
3. Show 1 or 10 tiles/cards in draw order with character portrait/rank, NEW vs DUPLICATE, each refund, total refunded Scrip and resulting balance. Reuse existing approved portraits/backdrop; no asset generation.
4. Do not automatically edit the squad on recruitment. Updated roster is visible in Camp immediately and after restart; the existing briefing picker can select newly owned characters.
5. Keep Scrip visible across Map/Camp/Flare/Codex and make four tabs fit at 320×568 without clipped rates, controls or settings. Preserve title-view navigation, medals and the existing Settings affordance.

**Gate:** `flutter analyze && flutter test`; 1-/10-pull seeded tests, duplicate in same batch, failed-save rollback, correct tab order and high-text-scale widget tests pass.

## Task 6 — Briefing payout information, result polish and regression coverage

Production: `lib/game/ui/stage_briefing_sheet.dart`, relevant game-page projections, report/Flare widgets as needed.

Tests: `test/widget/stage_briefing_sheet_test.dart`, `test/widget/mission_report_panel_test.dart`, `test/widget/scene_parity_regression_test.dart`.

1. Briefing shows Scrip projection for **first clear versus replay** and how medal improves the variable component. Do not display an exact as-yet-unknown run medal payout. Stage 1 makes the ten-flare guarantee legible.
2. Mission report visibly distinguishes **best medal saved** from **Scrip earned this run**, and keeps blueprint reward intact. Saving/failed states must not falsely claim that Scrip was credited.
3. Regression: Camp sheet/back, stage briefing squad draft and Launch, Gold/boss/Endless result reports, Codex search, guide/tips, settings, and old character battle dock still work.
4. Widget-level visual assertions at **320×568 and 2× text scale**, touch targets/semantics and a missing-portrait fallback; no four-tab overflow.

**Gate:** `flutter analyze && flutter test`, targeted screenshot fixtures and existing parity tests pass.

## Task 7 — Required MCP end-to-end acceptance and screenshot comparison (same PR)

Use a browser/Playwright MCP against one served Flutter web build; a second mobile platform is unnecessary because no platform-specific behavior is changed. Capture tested head commit, browser/device size, screenshots and objective pass/fail evidence in `docs/superpowers/validation/2026-11-18-hpa-923-economy.md` or the PR description. If live wave stepping is unreliable in the browser, the **existing headless real Flame game-loop Stage-1 victory fixture** supplies the wave-completion proof, while MCP exercises the visible UI and saved state.

MCP sequence:
1. **Fresh profile → Map/Camp:** assert 0 Scrip, 2 E starters, four tabs, existing medal and Settings actions, and no purchase while underfunded.
2. **Stage 1 win:** complete via browser UI if feasible; otherwise run the deterministic real eight-wave test and use a supported test-store seed for browser validation. Assert first-clear Scrip **≥1,000**, mission report pending→saved, and persisted top-bar balance after reload.
3. **Flare purchase:** open Flare, assert all six rates, disabled Fire 10 when below threshold, then afford/fire ten after Stage 1. Verify ten ordered outcomes, per-duplicate labels/refunds and committed final balance. Return to Camp and see the newly owned roster (the seeded pure test separately proves first/new and duplicate cases).
4. **Level Up:** purchase an affordable starter level, assert cost, preview and subsequent increased level/stats. Reload and verify both Scrip debit and level persist; start a run and assert resolver/character level is reflected.
5. **Replay:** win the same stage with a non-improving best result; verify **additional** Scrip exactly once and retained best medal, then reload. Exercise report Retry Save using a failing test store and confirm no partial currency or roster update.
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
- [ ] Stage payout, flare 1/10 prices, six exact rates (sum 100%), same-rank uniform draw, level price and rank duplicate refunds come from `GameBalance` + pure tested rules.
- [ ] One- and ten-flare draws atomically consume Scrip, recruit previously unowned characters at level 1, refund duplicate dog tags including within the same batch, show ordered results, and never fire below cost.
- [ ] Camp levels an owned character to max 40 using committed Scrip; actual battle damage, corrosion or drone channels increase at the saved level; no level gain when underfunded or capped.
- [ ] One v4 `CampaignSave` stores Scrip, roster, levels, squad, stage results and Endless bests in the existing key. Restart, reset, two queued writes, failed purchase and failed victory/retry behave atomically without double rewards.
- [ ] Map/Camp/Flare/Codex, top-bar Scrip, rate table, result screen, Level Up and projected/actual Scrip reports remain readable and operable at 320×568 and 2× text scale; relevant semantics/buttons work.
- [ ] **MCP E2E** shows fresh start → Stage-1 win → 10 flares/results → Camp level purchase → reload → non-improving replay reward → reload, plus key Codex/Settings/Endless/squad regression paths. The full eight-wave victory is also proven in the existing real-game headless test.
- [ ] **MCP screenshots visually checked against Linear 11/12/13/14**, mission report, and responsive compact view. Evidence (tested SHA, screenshots, pass/fail and intentional old-backdrop differences) is committed or linked in this PR.
- [ ] Dart formatting, `flutter analyze`, `flutter test --coverage`, web release build and final-head GitHub CI pass.
- [ ] **One PR per HPA-923** includes spec, implementation, tests, visual/MCP evidence and review fixes. Art and SFX remain in HPA-924/925/927; no human signoff is a gate.
