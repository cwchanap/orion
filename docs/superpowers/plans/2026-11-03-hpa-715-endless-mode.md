# HPA-715 — Endless Mode Implementation Plan

> **One Linear ticket, one PR.** This draft begins with spec + plan; add implementation and tests **to this same PR** before marking it ready for review. Work in small green commits on this branch. No separate design, implementation, or art PR.

**Linear:** [HPA-715](https://linear.app/cwchanap/issue/HPA-715/orion-add-an-endless-mode-for-cleared-stages)

**Design authority:** [HPA-715 design](../specs/2026-11-03-hpa-715-endless-mode-design.md)

**Goal:** Every cleared stage offers an Endless run that loops its wave script with compounding enemy health, ends only on defeat, and saves the best waves cleared per stage.

**Architecture:** One `RunMode` flag on `GameSession`, one pure `EndlessRules` file, one `healthMultiplier` on `EnemyModifierProfile`, one optional `endlessBest` map in the existing v3 campaign save, and small branches in the briefing, HUD/dock/scanner, and defeat report. No new services, packages, assets, sound, save keys, or save version.

## Baseline/code facts verified

- `GameSession.activeWave` is the only wave lookup; `startWave` refuses when `_waveIndex >= stage.waves.length`; `finishActiveWave` sets `GamePhase.won` after the last wave; `_effectiveClearBonus` forces the final wave's bonus to 0.
- `GameBalance.moduleDraftWaves` is `[2, 4, 6]`, so drafts stop after the first loop with no extra code.
- `GameBalance.wavePreview` labels groups with `identical(stats, _basicDrone)` etc. Scaled copies of `EnemyStats` would break labels, so scaling must happen at spawn, not in the wave data.
- `EnemyLogic` reads `stats.health`, `stats.shieldHealth` (initial shield and both shield-recharge sites), and `stats.regenPerSecond`; `EnemyComponent` passes `stats.shieldHealth` as the overlay's `maxShield`.
- `OrionDefenseGame._enemyModifierProfile` is the single profile source for wave enemies and boss minions.
- `waveTotal` is read in `mission_command_hud.dart` (2), `mission_command_dock.dart` (2), `next_wave_scanner.dart` (4), `mission_report_panel.dart` (1), `mission_report_content.dart` (1).
- `StageBriefingSheet` pops `bool`; `_showStageBriefing` calls `_startStage(stage)` on `true`.
- `CampaignProgressCodec` writes version 3; Reset Campaign removes the whole `orion.campaign.progress` key.
- The first-mission guide gate is `guideEligible` in `orion_game_page.dart`.

## Expected file map

**New:**
- `lib/game/rules/endless_rules.dart`
- `test/game/endless_rules_test.dart`

**Modify (rules/models/campaign):**
- `lib/game/models/game_models.dart` — `RunMode`, `GameBalance.endlessLoopHealthGrowth`, nullable `waveTotal` on `GameSnapshot` and `WavePreview`, `GameSnapshot.isEndless`, `WavePreview.enemyHealthMultiplier`.
- `lib/game/rules/game_session.dart` — mode, wave lookup, never-win, clear bonus, `enemyHealthMultiplier`, snapshot fields.
- `lib/game/rules/stage_modifier_rules.dart` — `EnemyModifierProfile.healthMultiplier`, passthrough in `enemyProfile`.
- `lib/game/rules/enemy_logic.dart` — scaled health/shield/regen, `maxShield`.
- `lib/game/campaign/campaign_progress.dart` — `endlessBestByStageId`, `endlessBestFor`, `recordEndlessBest`, carry the map through every rebuild.
- `lib/game/campaign/campaign_progress_store.dart` — encode/decode optional `endlessBest`.

**Modify (game/presentation):**
- `lib/game/orion_defense_game.dart` — `mode`, `onEndlessWaveCleared`, profile multiplier.
- `lib/game/components/enemy_component.dart` — overlay `maxShield` from logic.
- `lib/game/ui/stage_briefing_sheet.dart` — Endless action, best line, `RunMode?` pop.
- `lib/game/ui/orion_game_page.dart` — launch mode, best save, endless report, guide gate, replay.
- `lib/game/ui/mission_command_hud.dart`, `mission_command_dock.dart`, `next_wave_scanner.dart` — endless copy and health-bonus line.
- `lib/game/ui/mission_report_content.dart`, `mission_report_panel.dart` — `projectEndlessReport`, endless header and WAVES stat.

**Modify (tests):** `game_session_test.dart`, `enemy_logic_test.dart`, `stage_modifier_rules_test.dart`, `campaign_progress_test.dart`, `campaign_progress_store_test.dart`, `game_balance_test.dart`, `orion_defense_game_test.dart`, `mission_report_content_test.dart`, `test/widget/stage_briefing_sheet_test.dart`, `mission_command_hud_test.dart`, `mission_command_dock_test.dart`, `next_wave_scanner_test.dart`, `mission_report_panel_test.dart`, `test/widget_test.dart`.

---

## Task 1 — Pure endless rules

1. Write `test/game/endless_rules_test.dart`: `waveAt` returns `script[i % length]` (identical instances) for i = 0, 7, 8, 15, 16; `loopFor` 0/0/1/1/2 at those indices; `healthMultiplier` = 1, 1.6, 2.56, 4.096 for loops 0–3 (`closeTo`).
2. Add `GameBalance.endlessLoopHealthGrowth = 1.6` with a one-line comment; pin it in `game_balance_test.dart`.
3. Implement `EndlessRules` as in the design. Run the test file, then `flutter analyze`. Commit.

## Task 2 — Scale enemies through the modifier profile

1. Tests first in `stage_modifier_rules_test.dart` (profile defaults to 1, passthrough) and `enemy_logic_test.dart`: with `healthMultiplier: 2`, `maxHealth`/`health` double, `maxShield`/`shield` double, regen heals at double rate, shield recharge caps at `maxShield`; armor and speed unchanged; identity profile behaves exactly as before.
2. Add `healthMultiplier` to `EnemyModifierProfile` and an optional `healthMultiplier` parameter to `StageModifierRules.enemyProfile`.
3. In `EnemyLogic`, compute `maxHealth`, add `maxShield`, and replace the three `stats.shieldHealth` reads and the `stats.regenPerSecond` read with scaled values.
4. In `EnemyComponent`, pass `logic.maxShield` to the overlay. Run `enemy_logic_test`, `stage_modifier_rules_test`, `enemy_component_test`, `enemy_overlay_test`. Commit.

## Task 3 — Session run mode

1. Add `enum RunMode { mission, endless }` next to `GamePhase`.
2. Tests first in `game_session_test.dart` using an existing small fixture stage: endless `activeWave` wraps; finishing every scripted wave leaves `GamePhase.build` (not won) and `startWave` still succeeds; boss/final scripted wave pays its scripted clear bonus in endless; drafts open after waves 2, 4, 6 and not after 10, 12, 14; `enemyHealthMultiplier` is 1 in loop 0 and 1.6 in loop 1; snapshot `waveNumber` keeps counting past the script, `waveTotal == null`, `isEndless == true`, preview `enemyHealthMultiplier` matches; `restart()` keeps endless; base health 0 still loses. Mission tests unchanged.
3. Make `GameSnapshot.waveTotal` and `WavePreview.waveTotal` `int?`; add `GameSnapshot.isEndless` and `WavePreview.enemyHealthMultiplier` (default 1).
4. Implement the `GameSession` changes from the design (`mode` on `initial`, `activeWave`, `startWave`, `finishActiveWave`, `_effectiveClearBonus`, `enemyHealthMultiplier`, `snapshot`).
5. Fix the compile errors from the nullable `waveTotal` with mission-equivalent output for now (endless copy lands in Task 6). Run `flutter test test/game`. Commit.

## Task 4 — Game orchestrator

1. Tests first in `orion_defense_game_test.dart`: an endless game on a short fixture stage calls `onEndlessWaveCleared` with 1, 2, … as waves clear, continues past the script, and never calls `onStageWon`; spawned enemies in loop 1 have `maxHealth == stats.health * 1.6`; a mission game never calls `onEndlessWaveCleared`.
2. Add `RunMode mode` and `onEndlessWaveCleared` to `OrionDefenseGame`, pass `mode` to `GameSession.initial`, pass `_session.enemyHealthMultiplier` in `_enemyModifierProfile`, and fire the callback in `_finishWaveIfComplete` for endless. Run the test file. Commit.

## Task 5 — Persist the best

1. Tests first in `campaign_progress_test.dart`: `recordEndlessBest` stores the first value, replaces only with a higher value, returns `this` otherwise; `recordResult`, `withResult`, and `withoutUnknownStages` keep (and the last filters) the map.
2. Tests in `campaign_progress_store_test.dart`: v3 round trip with `endlessBest`; a v3 payload without the key decodes with an empty map and unchanged stage results; unknown stage ids, non-int, and non-positive values are dropped; reset clears it.
3. Implement in `CampaignProgress` and `CampaignProgressCodec` (version stays 3). Run both test files. Commit.

## Task 6 — Presentation

1. **Briefing.** Widget tests first in `stage_briefing_sheet_test.dart`: uncleared stage has no Endless action or best line; cleared stage shows "No endless run yet" or "Endless best: 17 waves" and an Endless action that pops `RunMode.endless`; Start/Replay pops `RunMode.mission`. Implement with `int? endlessBest` and a second `_BriefingLaunchAction` (`ENDLESS` kicker, `Icons.all_inclusive_rounded`).
2. **HUD/dock/scanner.** Widget tests first: endless snapshots show "Wave 12" without a total in the HUD readout, HUD semantics, dock tooltip/pill, and scanner; scanner shows "Enemies +60% health" only when the multiplier is above 1. Implement with plain ASCII copy.
3. **Report.** Tests first in `mission_report_content_test.dart` and `mission_report_panel_test.dart` for `projectEndlessReport` copy (first run, new best, retained best) and the "ENDLESS RUN OVER" header and WAVES stat. Implement.
4. Run `flutter test test/widget`. Commit.

## Task 7 — Page wiring

1. Integration-style tests first in `test/widget_test.dart` (follow the existing Alpha save/replay helpers): after an Alpha clear, the briefing offers Endless; launching it shows endless HUD copy; clearing a wave saves `endlessBest` for Alpha (check the in-memory store); a second, lower run does not overwrite it; a defeat shows the endless report and Replay starts a new endless run; the first-mission guide never appears in endless; Reset Campaign clears the best.
2. In `OrionGamePage`: `_showStageBriefing` reads the `RunMode?` result and passes `endlessBest: _committedProgress.endlessBestFor(stage.id)`; `_startStage(stage, mode)` stores the mode and the committed best as `_endlessPriorBest`, and passes `mode` plus `onEndlessWaveCleared: _saveEndlessBest` to the game; `_saveEndlessBest` follows the mission-result `_persistSave` shape; the lost branch picks `projectEndlessReport` when `snapshot.isEndless`; `_restartFromMissionReport` recaptures `_endlessPriorBest`; `guideEligible` adds `!snapshot.isEndless`.
3. Run `flutter test`. Commit.

## Task 8 — Final checks

- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage` (Codecov gate is 90%), `flutter build web --release`.
- Push, confirm all CI checks are green, then ask the owner to mark the PR ready.
- Record in the PR body that tuning (×1.6 per loop) is untested by a human; a playtest note goes on HPA-715 if the owner plays it.

## Not in this PR

Art, SFX, music, leaderboards, cloud sync, later-loop drafts, world-map badges, difficulty presets, speed/gold scaling, campaign rebalance.
