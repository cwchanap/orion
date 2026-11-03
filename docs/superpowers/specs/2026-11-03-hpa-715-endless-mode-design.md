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

**Waves cleared** is the score. On defeat during wave `n` (1-based), the run cleared `n - 1` waves.

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
- `snapshot()`: `waveNumber` is `_waveIndex + 1` unclamped in endless; `waveTotal` becomes **`int?`**, `null` in endless. `GameSnapshot` gains `bool get isEndless => waveTotal == null`.
- `WavePreview.waveTotal` becomes `int?`; `WavePreview` gains `double enemyHealthMultiplier` (default 1), passed by the session.

Making `waveTotal` nullable is the deliberate breaking change: the compiler flags every "of 8" site, so none is missed.

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
- Every method that rebuilds `CampaignProgress` (`recordResult`, `withResult`, `withoutUnknownStages`) carries the map; `withoutUnknownStages` filters it too.

`CampaignProgressCodec` writes an extra `endlessBest` object (sorted keys) into the **existing version 3** payload and reads it back when present; a missing key decodes to empty, and unknown stage ids or non-positive values are dropped. No version bump: the field is additive. Reset Campaign already removes the whole key, so endless bests reset with the campaign.

**Save timing.** `OrionGamePage` handles `onEndlessWaveCleared`: when `wavesCleared` beats `_committedProgress.endlessBestFor(stageId)`, call `_persistSave` with `buildSave` = committed progress `.recordEndlessBest(...)` and `onCommitted` updating `_progress`, the same shape as the mission-result save. On failure the existing campaign persistence toast shows, and the next cleared wave retries because the committed best is still lower. Saving after each record-breaking wave means quitting mid-run keeps the record without a separate quit path.

## UI

**Stage briefing.** `StageBriefingSheet` gains `int? endlessBest`. When `result != null` (stage cleared), it shows a line "Endless best: N waves" or "No endless run yet" and a second launch action **Endless** (icon `Icons.all_inclusive_rounded`, kicker `ENDLESS`) beside Replay Mission, reusing `_BriefingLaunchAction`. The sheet pops a `RunMode?` instead of `bool?`; `_showStageBriefing` passes it to `_startStage(stage, mode)`. Locked or uncleared stages look exactly as today.

**HUD, dock, scanner.** Where a site printed `waveNumber`/`waveTotal`, endless prints the wave number alone: HUD readout with no denominator and semantics "Endless. Wave 12", dock tooltip/pill "Wave 12", scanner "Next wave 12". When `preview.enemyHealthMultiplier > 1`, the scanner adds one line: "Enemies +60% health" (percent rounded). Use plain ASCII copy; avoid glyphs the game fonts may lack (the HPA-20 arrow rendered as a box in tests).

**Defeat report.** New `projectEndlessReport({snapshot, priorBest})` in `mission_report_content.dart`:
- `outcomeText`: "Survived N waves"
- `comparisonText`: "New best! Previous: M waves" / "New best!" (first run) / "Best: M waves"
- `nextOpportunityText`: "Replay to push further, or return to the World Map."

`MissionReportPanel` shows "ENDLESS RUN OVER" instead of "MISSION FAILED" when `content.snapshot.isEndless`, and the WAVES stat shows waves cleared. Replay and Return to Map reuse the existing handlers; `_restartFromMissionReport` recaptures the committed best as the next run's `priorBest`.

**Guide and tips.** The first-mission guide never shows in endless (`guideEligible` adds `!snapshot.isEndless`). Contextual first-time tips stay as they are: they are once-only and already seen by anyone who cleared a stage.

**Unchanged.** World map, Codex, tech tree, music, SFX, haptics, settings.

## Testing

- `endless_rules_test.dart`: wave wrap-around, loop index, multiplier at loops 0–3.
- `game_session_test.dart`: endless continues past the script length, never wins, pays the boss-wave clear bonus, drafts only in loop 0, `waveTotal == null`, preview multiplier, restart keeps mode; mission tests untouched.
- `enemy_logic_test.dart` / `stage_modifier_rules_test.dart`: multiplier scales health, shield, regen, and shield recharge; armor and speed untouched.
- `campaign_progress_test.dart` / `campaign_progress_store_test.dart`: record/keep best, survives `recordResult`/`withResult`/`withoutUnknownStages`, codec round trip, missing key, bad values.
- `game_balance_test.dart`: pin `endlessLoopHealthGrowth`.
- `orion_defense_game_test.dart`: endless callback fires with waves cleared; `onStageWon` never fires.
- Widget: briefing Endless action and best line (cleared vs uncleared), HUD/dock/scanner endless copy, endless defeat report, and one `widget_test.dart` flow: clear Alpha → launch Endless → clear a wave → best saved → relaunch shows it.

Mission-mode expectations in existing tests should not change beyond the `waveTotal` type.

## Out of scope

New art, SFX, or music; leaderboards or cloud sync; extra module drafts in later loops; world-map badges for endless bests; difficulty presets; speed or gold scaling; a campaign rebalance. Revisit tuning after a playtest rather than adding knobs now.
