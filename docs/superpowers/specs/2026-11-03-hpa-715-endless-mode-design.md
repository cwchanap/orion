# HPA-715 — Endless Mode Design

**Linear:** [HPA-715](https://linear.app/cwchanap/issue/HPA-715/orion-add-an-endless-mode-for-cleared-stages) · **Status:** design proposed for review

## Decision

Add an **Endless** run to every stage the player has cleared. An endless run loops the stage's own wave script forever, makes enemies tougher after each completed loop, and ends only when base health reaches zero. The best number of waves cleared is saved per stage.

**Do not build a second game mode subsystem.** Endless is one `RunMode` flag threaded through `GameSession`, one pure rules file, one health multiplier on the existing enemy modifier profile, one optional map in the existing campaign save, and small branches in four existing UI surfaces. No new art, SFX, music, packages, persistence keys, save version, wave generator, or difficulty framework. One implementation PR; this design-and-plan draft PR becomes that PR.

## Why this slice

Every roadmap item through HPA-303 has shipped. A cleared stage currently offers only a medal replay; after Gold there is no reason to return. Endless gives each of the seven stages a replayable high-score target using content that already exists: paths, the eight-wave scripts, bosses, stage modifiers, tech-tree bonuses, towers, and Salvage Module drafts.

Existing code already gives us:
- `GameSession` owns wave index, phase, clear bonus, and drafts; `activeWave` is the only wave lookup.
- `EnemyModifierProfile` is the per-spawn seam `EnemyLogic` already reads for stage modifiers (speed, armor, shield recharge).
- `CampaignProgress` + `CampaignProgressCodec` persist stage results under one SharedPreferences key that Reset Campaign wipes.
- `OrionGamePage._persistSave` serialises saves against committed disk state.
- `StageBriefingSheet` is the single launch point; `MissionReportPanel` already renders loss reports.

## Run rules

| Rule | Mission (unchanged) | Endless |
| --- | --- | --- |
| Available | Stage unlocked | Stage has a **committed clear** (`_committedProgress.isCleared`) |
| Wave at index `i` | `stage.waves[i]` | `stage.waves[i % length]` |
| End | Win after last wave, or lose | Lose only; never `GamePhase.won` |
| Clear bonus | Scripted, final wave forced to 0 | Scripted for every wave, including the boss wave |
| Enemy health/shield/regen | ×1 | ×`1.6 ^ loop`, where `loop = i ~/ length` |
| Module drafts | After waves 2, 4, 6 | Same three drafts, first loop only |
| Tower unlocks, stage modifiers, campaign modifiers | Normal | Normal |
| Medal, tech points, blueprint, campaign progress | Awarded on win | Never |

**Loop scaling.** Add `GameBalance.endlessLoopHealthGrowth = 1.6`. Loop 0 (waves 1–8) is the normal script. Loop 1 multiplies health, shield, and regen by 1.6; loop 2 by 2.56; loop 3 by 4.10. Armor reduction, speed, base damage, and gold rewards are **not** scaled: gold income stays flat while enemy toughness compounds, so every run ends. The boss returns as the last wave of every loop. These are initial values; tune after a playtest.

A loop boundary is a deliberate breather (boss → wave 1 at the next multiplier). No smoothing within a loop: the script already ramps.

**Waves cleared** is the score. `GameSession.clearedWaveCount` is the one authority, published as `GameSnapshot.wavesCleared` and passed unchanged to the per-wave save callback. On defeat during 1-based wave 1, that value is **0**; on defeat during wave 9, it is **8**. Both report copy and the WAVES stat read `snapshot.wavesCleared` directly, never infer a score from the attempted wave number.

## Pure rules

New `lib/game/rules/endless_rules.dart`, no Flame:

```dart
class EndlessRules {
  const EndlessRules._();

  static int loopFor(int waveIndex, int scriptLength) => waveIndex ~/ scriptLength;

  static WaveDefinition waveAt(List<WaveDefinition> script, int waveIndex) =>
      script[waveIndex % script.length];

  static double healthMultiplier(int waveIndex, int scriptLength) =>
      math.pow(GameBalance.endlessLoopHealthGrowth, loopFor(waveIndex, scriptLength)).toDouble();
}
```

Scaling stays out of `WaveDefinition`/`EnemyStats`: the scripted stats keep their identity, so `GameBalance.wavePreview` labels (which compare by `identical`), `is BossDefinition` checks, boss sprites, summon mechanics, the Codex, and the boss tip keep working with zero changes.

## Session

Add `enum RunMode { mission, endless }` beside `GamePhase` in `game_models.dart`.

`GameSession.initial({..., RunMode mode = RunMode.mission})` stores `mode`; `restart()` keeps it.
- `activeWave` → `EndlessRules.waveAt(stage.waves, _waveIndex)` in endless.
- `enemyHealthMultiplier` (new getter) → `EndlessRules.healthMultiplier(_waveIndex, stage.waves.length)` in endless, `1` in mission.
- `startWave` drops the `_waveIndex >= stage.waves.length` guard in endless.
- `finishActiveWave` never sets `GamePhase.won` in endless.
- `_effectiveClearBonus` applies the final-wave-is-zero rule only in mission.
- `_openModuleDraftIfDue` unchanged: `moduleDraftWaves` contains 2, 4, 6, so drafts naturally stop after loop 0.
- `snapshot()`: `waveNumber` is `_waveIndex + 1` unclamped in endless; rename `GameSnapshot.waveTotal` to **`int? missionWaveTotal`**, null in endless, and add required `int wavesCleared` from `clearedWaveCount`. `GameSnapshot.isEndless` is `missionWaveTotal == null`.
- Rename `WavePreview.waveTotal` to nullable **`missionWaveTotal`**; also add `double enemyHealthMultiplier` (default 1), passed by the session.

**The rename is intentional.** Dart accepts `int?` in string interpolation (`'Wave ${snapshot.waveTotal}'` compiles and prints `null`), so merely changing its type provides no compile-time audit. Removing the old name forces all model constructors, test fixtures, and HUD/dock/scanner/report reads to fail compilation until explicitly migrated; verify the rendered text and accessibility semantics in widget tests as well.

`GameBalance.wavePreview(...)` must rename its parameter to nullable `missionWaveTotal` and forward it along with `enemyHealthMultiplier` into `WavePreview`; changing only the model fields is insufficient because this factory is the session's preview construction path.

## Enemy scaling seam

`EnemyModifierProfile` gains `healthMultiplier` (default 1). `StageModifierRules.enemyProfile` takes an optional `healthMultiplier` and passes it through; `OrionDefenseGame._enemyModifierProfile` supplies `_session.enemyHealthMultiplier`. That one call covers wave enemies and boss minions.

`EnemyLogic` applies it once at construction:
- `maxHealth = health = stats.health * m`
- new `maxShield = shield = stats.shieldHealth * m`; shield recharge caps and rates read `maxShield` instead of `stats.shieldHealth`
- regen uses `stats.regenPerSecond * m`

`EnemyComponent`'s overlay reads `logic.maxShield` instead of `stats.shieldHealth`. Mission behaviour is identical because `m == 1`.

## Game orchestrator

`OrionDefenseGame` takes `RunMode mode = RunMode.mission` and `ValueChanged<int>? onEndlessWaveCleared`. In `_finishWaveIfComplete`, after `finishActiveWave()`, an endless run calls `onEndlessWaveCleared(_session.clearedWaveCount)`. `onStageWon` cannot fire in endless because the session never wins. Defeat, restart, return-to-map, pause, speed, auto-start, and drafts are unchanged.

## Persistence

`CampaignProgress` gains `Map<String, int> endlessBestByStageId` (waves cleared, > 0):
- `int? endlessBestFor(String stageId)`
- `CampaignProgress recordEndlessBest(String stageId, int wavesCleared)` returns `this` unless it beats the saved value.
- `recordResult` carries the map unchanged; `CampaignProgressCodec.decode` reads and filters `endlessBest` against known stage IDs. Remove the unused `CampaignProgress.withResult` and `withoutUnknownStages` helpers **and their helper-only tests**: they have no production callers, and fewer rebuild paths reduce the risk of dropping the new map. No replacement helper is needed.

`CampaignProgressCodec` writes an extra `endlessBest` object (sorted keys) into the **existing version 3** payload and reads it back when present; a missing key decodes to empty, and unknown stage ids or non-positive values are dropped. No version bump: the field is additive. Reset Campaign already removes the whole key, so endless bests reset with the campaign.

**Save timing and failure recovery.** `OrionGamePage` handles `onEndlessWaveCleared`: for each strictly higher count, call the existing serialized `_persistSave` with `buildSave` reading `committed.progress.recordEndlessBest(wavesCleared)` and `onCommitted` updating `_progress`. This preserves the maximum even when two wave clears enqueue writes before the first commits. Saving after each improvement means quitting mid-run keeps the last **committed** record; no separate quit save is needed.

Reuse the page's existing `_missionSaveState` (`saving`/`saved`/`failed`) for Endless rather than adding a new flag. Multiple wave saves may be in flight: keep the run in `saving` while **any** queued best-save write remains; an earlier completion must not mark it `saved` while a newer one is pending. Reuse `_pendingSaves` / `_isSavingProgress` from `_persistSave` to determine when the final queued save has settled, then reflect that final result. An intermediate failure can be superseded by a later successful higher save. If the last relevant write fails, retain the committed best and expose **Retry Save** in the defeat report, saving the run's `snapshot.wavesCleared` through the same queue. When there is no new score to persist (including a wave-1 loss), treat the report as saved with no write. The existing on-map failure toast remains useful during an active run, but is not a substitute for report retry.

## UI

**Stage briefing.** `StageBriefingSheet` gains `int? endlessBest`. When `result != null` (stage cleared), it shows a line "Endless best: N waves" or "No endless run yet" and a second launch action **Endless** (icon `Icons.all_inclusive_rounded`, kicker `ENDLESS`) beside Replay Mission, reusing `_BriefingLaunchAction`. The sheet pops `RunMode.mission` / `RunMode.endless`, while dismissal returns `null`; `_showStageBriefing` awaits `showModalBottomSheet<RunMode>` and passes the result to `_startStage(stage, mode)`. Update the test harness `_PopRecorder` and its `showModalBottomSheet<bool>` to `RunMode?` / `showModalBottomSheet<RunMode>` explicitly: `Navigator.pop` is not a compile-time type-safety check. Locked or uncleared stages look exactly as today.

**HUD, dock, scanner.** Where a site previously read `waveNumber`/`waveTotal`, migrate it to `missionWaveTotal`. Endless prints the wave number alone: HUD readout with a **null denominator** and semantics "Endless. Wave 12", dock tooltip/pill "Wave 12", scanner "Next wave 12" (including its collapsed semantics). When `preview.enemyHealthMultiplier > 1`, the scanner adds one line: "Enemies +60% health" (percent rounded). Use plain ASCII copy; avoid glyphs the game fonts may lack (the HPA-20 arrow rendered as a box in tests).

**Defeat report.** New `projectEndlessReport({required snapshot, required priorBest, required saveState})` in `mission_report_content.dart`, using existing `MissionReportContent.saveState`, `saveText`, and action copy:
- `outcomeText`: "Survived N waves", with `N = snapshot.wavesCleared`.
- `comparisonText`: "New best! Previous: M waves" / "New best!" (first run) / "Best: M waves", comparing against the committed best captured **at run start**.
- `nextOpportunityText` / `saveText` vary by `MissionSaveState`, reusing the victory report's pending, saved, and retry-failure messaging.

`MissionReportPanel` shows "ENDLESS RUN OVER" instead of "MISSION FAILED" and reads `snapshot.wavesCleared` for the WAVES stat. Suppress medal/R&D rewards for Endless; the regular mission-loss presentation and behavior remain unchanged. For Endless only, reuse the victory branch's save-dependent action rules: **while saving, disable Replay and Return; after success, enable both; after failure, offer Retry Save or Return to Map (Unsaved)**. `_returnToMap` already gates on saving; `_restartFromMissionReport` must also refuse an Endless restart until saved (including queued saves), and then recapture the committed best as the next run's `priorBest`. Retry Save writes the finished run's exact `wavesCleared` again; the existing callback should not award campaign rewards.

**Guide and tips.** The first-mission guide never shows in endless (`guideEligible` adds `!snapshot.isEndless`). Contextual first-time tips stay as they are: they are once-only and already seen by anyone who cleared a stage.

**Unchanged.** World map, Codex, tech tree, music, SFX, haptics, settings.

## Testing

- `endless_rules_test.dart`: wave wrap-around, loop index, multiplier at loops 0–3.
- `game_session_test.dart`: endless continues past the script length, never wins, pays the boss-wave clear bonus, drafts only in loop 0, `missionWaveTotal == null`, preview multiplier, restart keeps mode, and `wavesCleared` is 0 on a wave-1 loss and 8 on a wave-9 loss; mission tests untouched.
- `enemy_logic_test.dart` / `stage_modifier_rules_test.dart`: multiplier scales health, shield, regen, and shield recharge; armor and speed untouched.
- `campaign_progress_test.dart` / `campaign_progress_store_test.dart`: record/keep best, survives `recordResult`, codec round trip, missing key, invalid/unknown stage IDs and bad values; remove tests for the two deleted production helpers.
- `game_balance_test.dart`: pin `endlessLoopHealthGrowth`.
- `orion_defense_game_test.dart`: endless callback fires with waves cleared; `onStageWon` never fires.
- Widget: briefing Endless action and best line (cleared vs uncleared), typed modal return test harness, HUD/dock/scanner endless copy, Endless defeat report save states, and `widget_test.dart` flows: clear Alpha → launch Endless → clear a wave → best saved → relaunch shows it; delayed save blocks both exit actions; failed final save exposes Retry Save; two queued scores persist the maximum.

Mission-mode expectations in existing tests should remain unchanged in behavior. The rename from `waveTotal` to `missionWaveTotal` and the required `wavesCleared` constructor field intentionally require test-fixture updates.

## Out of scope

New art, SFX, or music; leaderboards or cloud sync; extra module drafts in later loops; world-map badges for endless bests; difficulty presets; speed or gold scaling; a campaign rebalance. Revisit tuning after a playtest rather than adding knobs now.

## Implementation coordination (2026-11-06 revalidation)

- The current `main` still has no `RunMode`, `EndlessRules`, or endless save field. This document is the implementation specification; no game code is part of this docs-only draft.
- [HPA-699 / PR #49](https://github.com/cwchanap/orion/pull/49) is a separate UI-only overhaul touching briefing, HUD, scanner, and report. Keep Endless behavior isolated from theme/style decisions. Whichever implementation merges second adapts to the current widgets within its **existing single PR**; do not duplicate either ticket or create an integration ticket merely for cosmetic conflicts.
- An Endless launch must be authorized from **committed** stage-clear state both when rendering the briefing action and at `_startStage(stage, mode)` (not merely from the current stage being unlocked).
- Save only **strictly higher** wave counts. The existing `_persistSave` queue must build each new record from `committed.progress.recordEndlessBest(...)` so back-to-back wave clears cannot overwrite a higher record. Track queued writes via the **existing** `_missionSaveState` and save-queue counters; the last relevant completion controls when the report can unblock. On failure expose Retry Save and a deliberate unsaved exit; do not rely only on a toast or introduce a new save-status subsystem.
- `OrionReadout.denominator` should receive `null` when total waves are absent, not the string `'null'`. The collapsed scanner's semantic text also needs the same omission, and the scaling callout is based on the exact next-wave multiplier.
