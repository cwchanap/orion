# HPA-715 — Endless Mode Implementation Plan

> **One Linear ticket, one PR.** This draft begins with spec + plan; add implementation and tests **to this same PR** before marking it ready for review. Work in small green commits on this branch. No separate design, implementation, or art PR.

**Linear:** [HPA-715](https://linear.app/cwchanap/issue/HPA-715/orion-add-an-endless-mode-for-cleared-stages)

**Design authority:** [HPA-715 design](../specs/2026-11-03-hpa-715-endless-mode-design.md)

**Goal:** Every cleared stage offers an Endless run that loops its wave script with compounding enemy health, ends only on defeat, and saves the best waves cleared per stage.

**Architecture:** One `RunMode` flag on `GameSession`, one pure `EndlessRules` file, one `healthMultiplier` on `EnemyModifierProfile`, one optional `endlessBest` map in the existing v3 campaign save, and small branches in the briefing, HUD/dock/scanner, and defeat report. Rename nullable `waveTotal` to `missionWaveTotal` for a reliable compile sweep; expose `GameSnapshot.wavesCleared` as the single scoring authority. Reuse the existing `MissionSaveState` for pending/failed high-score writes. No new services, packages, assets, sound, save keys, or save version.

## Baseline/code facts verified

- `GameSession.activeWave` is the only wave lookup; `startWave` refuses when `_waveIndex >= stage.waves.length`; `finishActiveWave` sets `GamePhase.won` after the last wave; `_effectiveClearBonus` forces the final wave's bonus to 0.
- `GameBalance.moduleDraftWaves` is `[2, 4, 6]`, so drafts stop after the first loop with no extra code.
- `GameBalance.wavePreview` labels groups with `identical(stats, _basicDrone)` etc. Scaled copies of `EnemyStats` would break labels, so scaling must happen at spawn, not in the wave data.
- `EnemyLogic` reads `stats.health`, `stats.shieldHealth` (initial shield and both shield-recharge sites), and `stats.regenPerSecond`; `EnemyComponent` passes `stats.shieldHealth` as the overlay's `maxShield`.
- `OrionDefenseGame._enemyModifierProfile` is the single profile source for wave enemies and boss minions.
- `waveTotal` is read in `mission_command_hud.dart` (2), `mission_command_dock.dart` (2), `next_wave_scanner.dart` (4), `mission_report_panel.dart` (1), and `mission_report_content.dart` (1). All current UI reads interpolate it as text, which **does not cause a compile error when it becomes nullable**. Rename to `missionWaveTotal` everywhere to force the compile sweep; audit accessibility semantics as well.
- `StageBriefingSheet` pops `bool`; `_showStageBriefing` calls `_startStage(stage)` on `true`. The widget-test harness in `test/widget/stage_briefing_sheet_test.dart` also calls `showModalBottomSheet<bool>` and records a `bool?`; update it explicitly to `RunMode` because `Navigator.pop` does not enforce the new type at compile time.
- `CampaignProgressCodec` writes version 3; Reset Campaign removes the whole `orion.campaign.progress` key.
- The first-mission guide gate is `guideEligible` in `orion_game_page.dart`.
- `CampaignProgress.withResult` and `.withoutUnknownStages` have no production call sites; their tests are helper-only. The codec already filters unknown IDs. Delete these methods and their tests rather than extending them.
- `_persistSave` already serializes writes against committed state; `_pendingSaves`, `_isSavingProgress`, and `MissionSaveState` support save gating and Retry Save without a new pending-save flag.

## Expected file map

**New:**
- `lib/game/rules/endless_rules.dart`
- `test/game/endless_rules_test.dart`

**Modify (rules/models/campaign):**
- `lib/game/models/game_models.dart` — `RunMode`, `GameBalance.endlessLoopHealthGrowth`, renamed nullable `missionWaveTotal` on `GameSnapshot`, `WavePreview`, and `GameBalance.wavePreview`; required `GameSnapshot.wavesCleared`; `GameSnapshot.isEndless`; `WavePreview.enemyHealthMultiplier`.
- `lib/game/rules/game_session.dart` — mode, wave lookup, never-win, clear bonus, `enemyHealthMultiplier`, snapshot fields.
- `lib/game/rules/stage_modifier_rules.dart` — `EnemyModifierProfile.healthMultiplier`, passthrough in `enemyProfile`.
- `lib/game/rules/enemy_logic.dart` — scaled health/shield/regen, `maxShield`.
- `lib/game/campaign/campaign_progress.dart` — `endlessBestByStageId`, `endlessBestFor`, `recordEndlessBest`, preserve the map in `recordResult`, and **remove unused** `withResult` / `withoutUnknownStages` methods.
- `lib/game/campaign/campaign_progress_store.dart` — encode/decode optional `endlessBest`.

**Modify (game/presentation):**
- `lib/game/orion_defense_game.dart` — `mode`, `onEndlessWaveCleared`, profile multiplier.
- `lib/game/components/enemy_component.dart` — overlay `maxShield` from logic.
- `lib/game/ui/stage_briefing_sheet.dart` — Endless action, best line, `RunMode?` pop.
- `lib/game/ui/orion_game_page.dart` — launch mode, best save via existing `_persistSave` / `_missionSaveState`, Retry Save and queue-aware defeat gating, endless report, guide gate, replay.
- `lib/game/ui/mission_command_hud.dart`, `mission_command_dock.dart`, `next_wave_scanner.dart` — endless copy and health-bonus line.
- `lib/game/ui/mission_report_content.dart`, `mission_report_panel.dart` — `projectEndlessReport` with `MissionSaveState`, endless header and `snapshot.wavesCleared` WAVES stat, reuse save-state actions and hide campaign rewards.

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
2. Tests first in `game_session_test.dart` using an existing small fixture stage: endless `activeWave` wraps; finishing every scripted wave leaves `GamePhase.build` (not won) and `startWave` still succeeds; boss/final scripted wave pays its scripted clear bonus in endless; drafts open after waves 2, 4, 6 and not after 10, 12, 14; `enemyHealthMultiplier` is 1 in loop 0 and 1.6 in loop 1; snapshot `waveNumber` keeps counting past the script, `missionWaveTotal == null`, `isEndless == true`, preview `enemyHealthMultiplier` matches; `snapshot.wavesCleared` equals 0 when defeat happens during wave 1 and 8 when defeat happens during wave 9; `restart()` keeps endless; base health 0 still loses. Mission tests unchanged.
3. **Rename** `GameSnapshot.waveTotal` and `WavePreview.waveTotal` to nullable `int? missionWaveTotal`, and rename the `GameBalance.wavePreview` named parameter to match. Add `GameSnapshot.isEndless`, required `int wavesCleared` (from `clearedWaveCount`), and `WavePreview.enemyHealthMultiplier` (default 1); forward the nullable total and multiplier in the preview factory. Update direct model fixtures/test constructors.
4. Implement the `GameSession` changes from the design (`mode` on `initial`, `activeWave`, `startWave`, `finishActiveWave`, `_effectiveClearBonus`, `enemyHealthMultiplier`, `snapshot`).
5. Use the **removed old field name** to drive a real compile sweep of every constructor/call site. Dart interpolates `int?` without an error (and would show `of null`); **nullability alone is not an audit**. Replace old reads with `missionWaveTotal`, retain mission-equivalent output, and explicitly verify that no `of null` or `/null` remains. Endless-specific copy and semantic tests land in Task 6. Run `flutter test test/game` and `flutter analyze`. Commit.

## Task 4 — Game orchestrator

1. Tests first in `orion_defense_game_test.dart`: an endless game on a short fixture stage calls `onEndlessWaveCleared` with 1, 2, … as waves clear, continues past the script, and never calls `onStageWon`; spawned enemies in loop 1 have `maxHealth == stats.health * 1.6`; a mission game never calls `onEndlessWaveCleared`.
2. Add `RunMode mode` and `onEndlessWaveCleared` to `OrionDefenseGame`, pass `mode` to `GameSession.initial`, pass `_session.enemyHealthMultiplier` in `_enemyModifierProfile`, and fire the callback in `_finishWaveIfComplete` for endless. Run the test file. Commit.

## Task 5 — Persist the best

1. Tests first in `campaign_progress_test.dart`: `recordEndlessBest` stores the first value, replaces only with a higher value, returns `this` otherwise, and `recordResult` preserves the map. **Delete** `withResult` / `withoutUnknownStages` and their helper-only tests; their only callers are tests and the codec already filters unknown IDs.
2. Tests in `campaign_progress_store_test.dart`: v3 round trip with `endlessBest`; a v3 payload without the key decodes with an empty map and unchanged stage results; unknown stage ids, non-int, and non-positive values are dropped; reset clears it.
3. Implement in `CampaignProgress` and `CampaignProgressCodec` (version stays 3). Limit production map-reconstruction sites to `recordResult` and codec decode; delete the dead helpers rather than porting them. Run both test files. Commit.

## Task 6 — Presentation

1. **Briefing.** Widget tests first in `stage_briefing_sheet_test.dart`: uncleared stage has no Endless action or best line; cleared stage shows "No endless run yet" or "Endless best: 17 waves" and an Endless action that pops `RunMode.endless`; Start/Replay pops `RunMode.mission`; Dismiss returns `null`. Change `_PopRecorder.popped` to `RunMode?` and **both** the page and the test harness to `showModalBottomSheet<RunMode>` (old `bool` harness would fail at runtime). Implement with `int? endlessBest` and a second `_BriefingLaunchAction` (`ENDLESS` kicker, `Icons.all_inclusive_rounded`).
2. **HUD/dock/scanner.** Widget tests first: endless snapshots show "Wave 12" without a total in the HUD readout, HUD semantics, dock tooltip/pill, and scanner **including collapsed-scanner semantics**; scanner shows "Enemies +60% health" only when the multiplier is above 1. Pass a null denominator to `OrionReadout`, never `'null'`, and use `missionWaveTotal` throughout. Implement with plain ASCII copy.
3. **Report.** Tests first in `mission_report_content_test.dart` and `mission_report_panel_test.dart` for `projectEndlessReport(snapshot, priorBest, saveState)` copy (first run, new best, retained best, saved/saving/failed states), the "ENDLESS RUN OVER" header, `snapshot.wavesCleared` for the WAVES stat (0 on wave-1 defeat, 8 on wave-9 defeat), and no medal/R&D reward. Make the existing action switch honor `saveState` for **Endless loss only**, preserving ordinary mission-loss Retry behavior. Implement the existing `Retry Save`, Replay disabled during pending/failed save, and Return disabled only while saving.
4. Run `flutter test test/widget`. Commit.

## Task 7 — Page wiring

1. Integration-style tests first in `test/widget_test.dart` (follow the existing Alpha save/replay helpers): after a **committed** Alpha clear, briefing offers Endless (not for an unlocked-but-uncleared stage); launching shows endless HUD; clearing a wave saves `endlessBest`; lower subsequent runs do not overwrite it; defeat shows the Endless report; Replay starts Endless again; first-mission guide never appears; Reset Campaign clears the best. Reuse `_TestCampaignProgressStore(delaySaves: true, failOnSaveIndices: {...})` for three **mandatory save-race regressions**:
   - Delay the wave-N best write, then lose: Replay and Return stay disabled until the pending write settles, and the next run sees the committed best.
   - Fail the **last** write: Retry Save appears, committed best remains unchanged, retry can commit the finished run's score; unsaved World Map exit remains possible after the failure.
   - Queue two wave-clear writes before the first completes: the larger score wins on disk, and completing the first must not prematurely enable report actions while the second is pending.
2. In `OrionGamePage`: `_showStageBriefing` awaits `RunMode?` and passes `endlessBest: _committedProgress.endlessBestFor(stage.id)`; `_startStage(stage, mode)` **rejects Endless unless `_committedProgress.isCleared(stage.id)`**, stores the mode and `_endlessPriorBest`, and passes `mode` plus `onEndlessWaveCleared: _saveEndlessBest` into the game. `_saveEndlessBest(wavesCleared)` uses `_persistSave` and builds from `committed.progress.recordEndlessBest(wavesCleared)`; drive the **existing** `_missionSaveState` as `saving` -> `saved`/`failed`, and update `_progress` on commit. Because multiple writes can queue, use existing `_pendingSaves`/`_isSavingProgress` rather than treating any earlier completion as final; the last relevant queued result controls when the report becomes saved/failed. On defeat, `projectEndlessReport` receives `_missionSaveState` (treat a non-improving/zero-wave run with no writes as saved); reuse won-report gating and Retry Save for a failed final write, retrying `snapshot.wavesCleared`. `_restartFromMissionReport` refuses Endless Replay until save state is `saved` and no best write remains, then recaptures the committed prior best. `_returnFromMissionReport` emits Endless-specific unsaved feedback on failed exit; the existing `_returnToMap` blocks during saves. `guideEligible` adds `!snapshot.isEndless`. No new save-status variable, persistence service, or per-wave retry system.
3. Run `flutter test`. Commit.

## Task 8 — Final checks

- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage` (Codecov gate is 90%), `flutter build web --release`.
- Recheck `main` before implementation, and reconcile UI changes from [HPA-699 / PR #49](https://github.com/cwchanap/orion/pull/49) within this same PR if that restyle merges first. Avoid importing the redesign or creating a separate integration PR.
- Push, confirm all CI checks are green, then ask the owner to mark the PR ready.
- Record in the PR body that tuning (×1.6 per loop) is untested by a human; a playtest note goes on HPA-715 if the owner plays it.

## Not in this PR

Art, SFX, music, leaderboards, cloud sync, later-loop drafts, world-map badges, difficulty presets, speed/gold scaling, campaign rebalance.

## Review notes (2026-11-06)

- Rechecked Linear HPA-715's latest description and the current `main`: the existing eight tasks remain aligned. The earlier design-only PR #46 was closed unmerged; reuse this branch and PR instead of creating a duplicate.
- Additional regression assertions: no Endless launch for an unlocked-but-uncleared stage; no campaign result, medal, tech points, or blueprint on an Endless boss clear; boss returns on wave 8/16; scanner and semantics show no denominator; `wavesCleared` on wave-1 and wave-9 defeats is 0 and 8; pending high-score writes never permit stale Replay; failed last write is recoverable via Retry Save.
- When editing HUD/briefing/report code, preserve the live `main` look and feel rather than adding another design system. This remains **one feature PR**, with art and sound work out of scope.

## Review disposition (2026-11-06, PR #46)

All four substantive design-review findings were accepted:

1. **Compiler sweep:** `waveTotal` -> `missionWaveTotal` in both models and the preview factory. Nullable interpolation alone is not a static error; update model fixtures and typed briefing harness explicitly.
2. **Save durability:** reuse `_missionSaveState`, `_persistSave`, and existing queued-save counters. Do not mark the report saved while a later wave's write remains pending; failed final writes get Retry Save and an optional unsaved exit.
3. **Dead methods:** delete `CampaignProgress.withResult` and `withoutUnknownStages` and their tests rather than carry `endlessBest` through unused reconstruction paths.
4. **Score authority:** `GameSnapshot.wavesCleared = GameSession.clearedWaveCount`, reused by callback and report with no UI arithmetic.

Scope is unchanged: **one implementation PR for HPA-715**; no new art, sound, services, or UI design system. All changes in this review are planning documents; implementation and tests remain outstanding.
