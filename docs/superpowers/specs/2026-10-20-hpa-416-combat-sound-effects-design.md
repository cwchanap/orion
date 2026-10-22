# HPA-416 — Readable Combat Sound Design

**Linear:** [HPA-416](https://linear.app/cwchanap/issue/HPA-416/orion-add-combat-sound-effects)  
**Separate asset supply:** [HPA-385](https://linear.app/cwchanap/issue/HPA-385/orion-produce-combat-sfx-pack-for-hpa-416)  
**Baseline:** `main` at `3e2a7e76f7272d106d7ad059dffe3b933a356ba9` (2026-10-20)  
**Status:** design implemented in this PR; asset-contract and device gates pending HPA-385.

## Outcome and constraints

A player should hear tower firing, multi-target impacts, enemy deaths, core leaks, the start of a wave, a boss entering/leaving, and selling a tower. Combat must remain intelligible on a full board at 3× speed and must honor the existing Sound Effects preference immediately.

This is **presentation only**. No damage, targeting, spawn, balance, run-module, snapshot, campaign, or save changes. No event bus, generalized mixer, service locator, per-tower audio components, or new package. Keep game rules in `GameSession`; `OrionDefenseGame` already owns the resolved rendering callbacks and can emit the sound cues.

**Dependency split:** HPA-385 owns original 17 WAVs, their generation script, the audio README and `pubspec.yaml` registration in **one separate asset PR**. HPA-416 owns *only* the feedback contract, playback/voice limiter, existing combat call sites, and tests in **one implementation PR** (the same PR that starts with this spec and plan). Do not create placeholders or duplicate asset generation here. The integration phase requires the asset PR merged first.

## Verified reuse seams

- `lib/game/feedback/game_feedback.dart`: `GameFeedback`, `NoOpGameFeedback`, and `PlatformGameFeedback` already exist. `PlatformGameFeedback` eagerly warms four WAVs and checks live Sound Effects/Haptics callbacks. Preserve those behaviors.
- `lib/game/ui/orion_game_page.dart`: page constructs one feedback instance, passes it to every `OrionDefenseGame`, and waits until persisted feedback preferences load before allowing output. Keep that gate; do not add new settings.
- `OrionDefenseGame.startWave()` handles both manual and auto-start; emit only after `_session.startWave()` succeeds.
- `_launchProjectile` is the common firing seam for projectile towers **and** the Gravity Well and Drone Bay branches. Emit **after an entity is actually scheduled**: after tracking a projectile or gravity field, or inside `_launchDrones` only after `allowed > 0` and tracking its drones. Emit once per successful launch batch, **not** once per individual drone/tick or a failed capacity check.
- `_addCombatFeedback(CombatFeedbackComponent)` receives actual resolved splash/chain/pierce effects; these carry `CombatFeedbackKind`. The same function also receives `enemyDestroyed` and `coreImpact` **visual** cues. Do not interpret those last two as extra audio events there.
- `_handleEnemyKilled`, `_handleEnemyReachedBase`, `_spawnEnemy`, and `sellSelectedTower` already know whether an authoritative transition happened. Prefer them to polling `GameSnapshot`.
- `test/game/orion_defense_game_test.dart` has `_RecordingGameFeedback`; `test/feedback/platform_game_feedback_test.dart` already mocks the audio cache and platform channels.
- Current pinned dependency is `flame_audio: ^2.12.2`, whose `FlameAudio.createPool(..., maxPlayers: ...)` / `AudioPool.start()` can reuse high-frequency players. A pool's maxPlayers alone is **not** our global concurrent-voice admission policy.

## Cue contract and mapping

Add these methods to `GameFeedback` (and corresponding no-op methods / recording fake implementations). Use the existing `TowerType`, not a duplicate eight-family enum. No generic `emit(String event)` layer.

| GameFeedback method | Source and condition | HPA-385 WAV |
| --- | --- | --- |
| `towerFired(TowerType type)` | projectile/field tracked, or Drone Bay launches at least one drone (silent at session cap) | `fire_<family>.wav` (8 cases) |
| `splashImpact()` | `_addCombatFeedback`: `CombatFeedbackKind.splash` | `impact_splash.wav` |
| `chainImpact()` | same, `chain` | `impact_chain.wav` |
| `pierceImpact()` | same, `pierce` | `impact_pierce.wav` |
| `enemyDestroyed()` | `_handleEnemyKilled`, normal enemy only **while `GamePhase.wave`** | `enemy_destroyed.wav` |
| `coreHit()` | `_handleEnemyReachedBase`, **nonlethal leak only while phase before damage is `GamePhase.wave`** | `core_hit.wav` |
| `waveStarted()` | after successful manual/auto `startWave` | `wave_start.wav` |
| `bossArrived()` | `_spawnEnemy` when actual stats are `BossDefinition` | `boss_arrival.wav` |
| `bossDefeated()` | already called on boss kill; **extend** with audio, retain medium haptic | `boss_defeated.wav` |
| `towerSold()` | after `sellTower` returns a refund | `tower_sold.wav` |

For tower family mapping use exactly: laser, cryo, rocket, railgun, ion_chain, nanite, gravity_well, drone_bay. Enumerate `TowerType` exhaustively in the playback mapping (prefer a switch), so a newly added family requires an explicit decision.

Preserve the four existing files/cues: confirm, clear, victory, defeat. A boss kill should play `bossDefeated` instead of a second generic death sound. A lethal leak should play the existing `baseDefeated` stinger instead of a simultaneous `coreHit`. A **later same-tick leak after loss** must emit **no** `coreHit`: check `phaseBeforeDamage == GamePhase.wave && !didLose`, never a plain `else`. Suppress normal enemy death audio once the session is no longer in `GamePhase.wave` as well; leave existing simulation and visuals untouched. Each resolved splash, chain or pierce attack emits **one visual feedback component containing all resolved target positions**, not one per target (see `ProjectileComponent._resolveHit`, `_resolveChainHit`, and `_resolvePierceHit`). Each component requests one audio cue. Multiple attacks in a busy frame can still issue repeated requests; the limiter's per-kind interval folds those into fewer *audible* cues without changing impact rendering or damage. Cluster bursts do not add separate splash components. Keep haptics unchanged apart from a light impact on boss arrival; respect the independent haptics preference.

## Rate limits, caps, and priority

Measure high-frequency audio in **monotonic wall-clock milliseconds** (`Stopwatch`), never Flame's speed-scaled `dt`. At 3×, deny and drop extra requests: **no queue, deferred playback, or catch-up burst**.

Use one small pure `CombatSoundLimiter` in `lib/game/feedback/combat_sound_limiter.dart`. It accepts a concrete high-frequency cue and an injected `nowMs`, and holds last-admitted timestamps for each cue. Only the **11 low-priority cues** (eight tower families, three impacts) also share one rolling timestamp buffer, capped at **2 accepted starts in any 500 ms**; prune timestamps at least 500 ms old. The other two high-frequency cues have separate per-cue intervals, never consume the shared low budget, and therefore cannot be starved by tower fire:

| Cue group | Admission | Initial tuning |
| --- | --- | --- |
| Tower fire (8 kinds) and impacts (3 kinds) | Per-cue interval **plus** shared 2 starts/500 ms | 120 ms per tower-family cue; 180 ms per impact kind |
| Ordinary enemy destroyed | Per-cue interval, no shared budget | 500 ms |
| Nonlethal core hit | Per-cue interval, no shared budget | 250 ms |

This gives a bound of **5 admitted high-frequency starts per rolling 500 ms** (2 shared low + 1 enemy-death + 2 core-hit); it does **not** limit rare transition stingers or measure the platform's actual number of mixer voices. HPA-385 must produce all 17 combat WAVs at **≤ 500 ms**, ensuring this admission bound also controls nominal high-frequency overlap without managing file-specific durations. A failed async playback attempt keeps its timestamp until it naturally expires; no reservation/release machinery or timers.

**Always-audible rare transition cues** — `waveStarted`, `bossArrived`, `bossDefeated`, `towerSold` — bypass the limiter, like existing confirm, clear, victory, and defeat stingers. They remain gated by the live Sound Effects preference and play best-effort as one-shots. This avoids a pair of rapid leaks suppressing an important boss-defeat announcement. Keep boss defeat versus generic kill, and losing leak versus ordinary core-hit, mutually exclusive at their owning handlers.

Use `AudioPool` for the **13 high-frequency cues** (11 fire/impact, enemy destroyed, core hit); `FlameAudio.play` is appropriate for the rare transition cues and four existing stingers. Create pools once per page-owned `PlatformGameFeedback`, eagerly and asynchronously with best-effort error handling; never block gameplay on loading. Pools use conservative `maxPlayers` (1–2 per sound), but pool size is **not** a global voice limiter. Audio starts require (1) live Sound Effects enabled, (2) a ready pooled player or injected test start, and (3) synchronous limiter admission, in that order. If a pool is unready or failed, silently drop without consuming an admission; once admitted, a playback-start failure is logged/swallowed and is not retried.

**Test seam:** make `PlatformGameFeedback` accept optional constructor callbacks `Future<void> Function(String file)? startCombatSound` and `int Function()? nowMs`. If a test supplies the start callback, it records *accepted starts* with exact filenames and bypasses real pool creation/readiness; production (`null`) uses `AudioPool`. The fake clock makes the time-based assertions deterministic. Preserve existing constructor-time `audioCache.loadAll` warm-up and Sound Effects/Haptics callbacks. Avoid a new audio backend abstraction or registry.

**Test setup:** the standard `test/widget_test.dart` page helper already injects `NoOpGameFeedback`; not every widget test constructs native feedback. However, some tests (including `sell_button_test.dart`) instantiate the real page default, and eager pool creation calls audioplayers platform channels. Centralize default throwing stubs for `xyz.luan/audioplayers.global` and `xyz.luan/audioplayers` in Flutter's `test/flutter_test_config.dart` (registered before each test), allowing specific tests to override them. Avoid leaving an unstubbed native channel that can hang an otherwise unrelated widget test. The isolated platform feedback tests should still use their explicit recording cache and controlled overrides.

No settings schema changes; switching Sound Effects off prevents *new* sound starts without disabling haptics. Add a light boss-arrival haptic; retain the boss-defeat medium haptic and all existing four cue mappings.

**Cross-PR contract:** add `test/feedback/audio_asset_contract_test.dart` to check that every file in `PlatformGameFeedback.sounds` exists under `assets/audio/` and is explicitly registered in `pubspec.yaml`. Read the RIFF/WAV header for each of the 17 combat clips and assert duration (data bytes divided by byte rate) **≤ 500 ms**. This integration guard must pass once HPA-385 merges; it is intentionally not satisfied by the pre-asset main branch, so run as part of the post-merge gate instead of generating placeholder WAVs in HPA-416. Keep the asset generator and manifest edits in HPA-385.

### Ownership and shutdown

`OrionGamePage` owns its default-created `PlatformGameFeedback` across multiple missions; do **not** create pools per stage or restart. Add a **minimal**, idempotent best-effort `dispose()` method to `PlatformGameFeedback` and call it only when the owning page is disposed (normally a widget-test or app-root teardown, **not** a map/stage transition). Track whether the page created the feedback; never dispose an injected `GameFeedback`. Dispose owned pools, set `_disposed`, and check that flag after each awaited pool initialization so late results are immediately disposed; do not add lifecycle methods to the shared interface or clear the global Flame audio cache.

## Alternatives rejected

1. **Sound event bus / generic mixer / audio registry** — unnecessary for fixed, direct owner callbacks.
2. **Call `FlameAudio.play` for every projectile and hit** — no admission bound; unacceptable at 3×.
3. **Use `AudioPool.maxPlayers` as the only voice cap** — per-sound pool limits are not a global cap; keep the single shared fire/impact admission budget.
4. **Make every projectile/drone/target its own sound source** — duplicates callbacks, increases allocations and noise.
5. **Generate assets in HPA-416** — violates the required separate-asset ticket/PR boundary and makes sound-design iteration drag gameplay code.
6. **Persist cue throttle state or expose per-cue volume sliders** — no user value at current scope.

## Validation and acceptance

- Pure limiter unit tests advance an injected wall clock: same-family fire bursts, mixed families/impacts, 2-per-500 ms shared saturation, and rolling-window expiry; prove a saturated low budget does not block enemy-death/core-hit starts. Test 500 ms kill and 250 ms core intervals (at most 5 accepted high-frequency starts per 500 ms total), including synthetic 3× input. Rare boss/wave/sell events **never call the limiter** and must still play when the shared budget is full.
- `platform_game_feedback_test.dart`: injected recording start + fake clock prove mapping of 13 pooled and 4 rare transition filenames, Sound Effects OFF suppresses all combat audio **without consuming admission**, haptics remain independent, and default pool warm-up/failure/dispose paths settle under global channel stubs. Keep the existing four original sounds.
- `orion_defense_game_test.dart`: record successful vs denied wave start/sell, direct and auto wave transitions, projectile/field/drone launch only when a real entity is created (including **capped Drone Bay silence**), one request per resolved splash/chain/pierce component, boss arrival/defeat, normal enemy death, nonlethal and lethal leaks, and a **second same-tick leak after losing** that emits no audio. Assert no post-loss enemy-death sound.
- `game_feedback_test.dart`: `NoOpGameFeedback` covers all added methods. `audio_asset_contract_test.dart`: disk, explicit `pubspec.yaml` membership, and all 17 combat WAV lengths ≤ 500 ms after HPA-385 merges.
- Regression: `flutter analyze`, focused tests, `flutter test`. On device, **listen at 1× with 4–5 towers first** to assess whether the shared fire/impact budget is too sparse, then stress a busy 3× board for intelligibility and frame pacing. Verify boss transitions remain audible during leaks, the Sound Effects toggle silences new starts, and haptics work independently. Asset-production listening/README checks remain HPA-385 acceptance.

**Scope exclusions:** music/ambience and audio-session/lifecycle music policy (HPA-417), per-cue settings, stereo panning, new gameplay mechanics, voice acting, or unrelated UI redesign.
