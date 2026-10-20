# HPA-416 — Readable Combat Sound Design

**Linear:** [HPA-416](https://linear.app/cwchanap/issue/HPA-416/orion-add-combat-sound-effects)  
**Separate asset supply:** [HPA-385](https://linear.app/cwchanap/issue/HPA-385/orion-produce-combat-sfx-pack-for-hpa-416)  
**Baseline:** `main` at `3e2a7e76f7272d106d7ad059dffe3b933a356ba9` (2026-10-20)  
**Status:** design proposal; this draft PR is documentation-only.

## Outcome and constraints

A player should hear tower firing, multi-target impacts, enemy deaths, core leaks, the start of a wave, a boss entering/leaving, and selling a tower. Combat must remain intelligible on a full board at 3× speed and must honor the existing Sound Effects preference immediately.

This is **presentation only**. No damage, targeting, spawn, balance, run-module, snapshot, campaign, or save changes. No event bus, generalized mixer, service locator, per-tower audio components, or new package. Keep game rules in `GameSession`; `OrionDefenseGame` already owns the resolved rendering callbacks and can emit the sound cues.

**Dependency split:** HPA-385 owns original 17 WAVs, their generation script, the audio README and `pubspec.yaml` registration in **one separate asset PR**. HPA-416 owns *only* the feedback contract, playback/voice limiter, existing combat call sites, and tests in **one implementation PR** (the same PR that starts with this spec and plan). Do not create placeholders or duplicate asset generation here. The integration phase requires the asset PR merged first.

## Verified reuse seams

- `lib/game/feedback/game_feedback.dart`: `GameFeedback`, `NoOpGameFeedback`, and `PlatformGameFeedback` already exist. `PlatformGameFeedback` eagerly warms four WAVs and checks live Sound Effects/Haptics callbacks. Preserve those behaviors.
- `lib/game/ui/orion_game_page.dart`: page constructs one feedback instance, passes it to every `OrionDefenseGame`, and waits until persisted feedback preferences load before allowing output. Keep that gate; do not add new settings.
- `OrionDefenseGame.startWave()` handles both manual and auto-start; emit only after `_session.startWave()` succeeds.
- `_launchProjectile` is the common firing seam for projectile towers **and** the early-return Gravity Well and Drone Bay branches; emit exactly once on that invocation, before branching, not for every drone tick or field tick.
- `_addCombatFeedback(CombatFeedbackComponent)` receives actual resolved splash/chain/pierce effects; these carry `CombatFeedbackKind`. The same function also receives `enemyDestroyed` and `coreImpact` **visual** cues. Do not interpret those last two as extra audio events there.
- `_handleEnemyKilled`, `_handleEnemyReachedBase`, `_spawnEnemy`, and `sellSelectedTower` already know whether an authoritative transition happened. Prefer them to polling `GameSnapshot`.
- `test/game/orion_defense_game_test.dart` has `_RecordingGameFeedback`; `test/feedback/platform_game_feedback_test.dart` already mocks the audio cache and platform channels.
- Current pinned dependency is `flame_audio: ^2.12.2`, whose `FlameAudio.createPool(..., maxPlayers: ...)` / `AudioPool.start()` can reuse high-frequency players. A pool's maxPlayers alone is **not** our global concurrent-voice admission policy.

## Cue contract and mapping

Add these methods to `GameFeedback` (and corresponding no-op methods / recording fake implementations). Use the existing `TowerType`, not a duplicate eight-family enum. No generic `emit(String event)` layer.

| GameFeedback method | Source and condition | HPA-385 WAV |
| --- | --- | --- |
| `towerFired(TowerType type)` | successful `_launchProjectile` call, including field/drone cases | `fire_<family>.wav` (8 cases) |
| `splashImpact()` | `_addCombatFeedback`: `CombatFeedbackKind.splash` | `impact_splash.wav` |
| `chainImpact()` | same, `chain` | `impact_chain.wav` |
| `pierceImpact()` | same, `pierce` | `impact_pierce.wav` |
| `enemyDestroyed()` | `_handleEnemyKilled`, normal enemy only | `enemy_destroyed.wav` |
| `coreHit()` | `_handleEnemyReachedBase`, **nonlethal leak only** | `core_hit.wav` |
| `waveStarted()` | after successful manual/auto `startWave` | `wave_start.wav` |
| `bossArrived()` | `_spawnEnemy` when actual stats are `BossDefinition` | `boss_arrival.wav` |
| `bossDefeated()` | already called on boss kill; **extend** with audio, retain medium haptic | `boss_defeated.wav` |
| `towerSold()` | after `sellTower` returns a refund | `tower_sold.wav` |

For tower family mapping use exactly: laser, cryo, rocket, railgun, ion_chain, nanite, gravity_well, drone_bay. Enumerate `TowerType` exhaustively in the playback mapping (prefer a switch), so a newly added family requires an explicit decision.

Preserve the four existing files/cues: confirm, clear, victory, defeat. A boss kill should play `bossDefeated` instead of a second generic death sound. A lethal leak should play the existing `baseDefeated` stinger instead of a simultaneous `coreHit`. Each resolved splash, chain or pierce attack emits **one visual feedback component containing all resolved target positions**, not one per target (see `ProjectileComponent._resolveHit`, `_resolveChainHit`, and `_resolvePierceHit`). Each component requests one audio cue. Multiple attacks in a busy frame can still issue repeated requests; the limiter's per-kind interval folds those into fewer *audible* cues without changing impact rendering or damage. Cluster bursts do not add separate splash components. Keep haptics unchanged apart from a light impact on boss arrival; respect the independent haptics preference.

## Rate limits, caps, and priority

Audio intensity is measured in **real wall-clock elapsed time** (monotonic `Stopwatch`), never Flame's speed-scaled `dt`. A 3× session may produce more requests, but not more sound starts per real second. Drop a denied cue; **no queue or catch-up burst**.

Implement one small pure `CombatSoundLimiter` in `lib/game/feedback/combat_sound_limiter.dart`, called by `PlatformGameFeedback` *after* checking the live Sound Effects flag **and playback readiness**. The limiter takes a concrete cue identifier and injected `nowMs`, making bursts deterministic in unit tests. Keep the last accepted timestamp for each cue and the last N accepted timestamps per priority lane. Prune lane timestamps older than a fixed **500 ms rolling window**, then accept only if the cue's minimum interval has elapsed and the lane has room. One synchronous admission check happens before asynchronous playback. No timers, WAV-duration table, in-flight reservations, or failure-release bookkeeping: an attempted start that fails simply occupies a lane slot until its timestamp ages out.

Initial tuning targets (adjust only after one device listen; one place for constants):

| Lane | Cues | Max accepted starts per rolling 500 ms | Minimum interval per cue |
| --- | --- | ---: | ---: |
| Low | eight tower firing and three multi-target impacts | 2 total | 120 ms per tower-family cue; 180 ms per impact kind |
| Normal | enemy destroyed, wave start, tower sold | 1 total | 150 ms for enemy deaths; 250 ms for other normal cues |
| Critical | core hit, boss arrival, boss defeat | 2 total | 200 ms core hit; boss cues one per actual event |

Maximum **five accepted combat starts in any rolling 500 ms** (2 low + 1 normal + 2 critical). HPA-385 will keep every new combat WAV at or below 500 ms; with this bound the admission policy also caps nominal concurrent combat cue playback, without tracking individual asset lengths. It is an admission/start-rate bound, not an exact measurement of platform mixer voices or old stingers. The reserved normal/critical lanes ensure a busy laser barrage cannot consume capacity reserved for kills, leaks, or boss calls. Existing one-shot confirmation/clear/victory/defeat remain outside the combat limiter; they are rare player/system feedback, not autonomous combat spam. The final loss/victory stinger takes precedence at its owning call site as specified above.

Use `AudioPool` for high-frequency sounds (family shots, impacts and enemy death; core leak may use one too). Start pools best-effort when `PlatformGameFeedback` is initialized and keep pool construction asynchronous so gameplay never waits for sound. Set each pool's maxPlayers conservatively (1–2); the **explicit limiter** is the admission authority, rather than assuming a pool cap is a global cap. Rare wave/boss/sell sounds may stay on `FlameAudio.play`. Preload the asset list once, as current feedback does. No user-visible error or blocking dialog on an audio failure.

If the pool is not ready or failed to initialize, drop the cue without consuming limiter capacity or enqueueing it. After admission, a failed playback start is swallowed by the existing best-effort error path and keeps its short rolling-window slot; no retries or async release bookkeeping. The Sound Effects callback is evaluated at each request; turning it off prevents any **new** starts, without shutting off haptics. No settings schema changes.

### Ownership and shutdown

`OrionGamePage` owns its default-created `PlatformGameFeedback` across multiple missions; do **not** create pools per stage or restart. Add a lightweight best-effort `dispose()` method to `PlatformGameFeedback` and call it when the owning page is disposed. Track whether the page created the feedback; never dispose an injected `GameFeedback`. Do not add `dispose` to the shared `GameFeedback` interface solely for tests. Guard late asynchronous pool initialization against page disposal and do not clear globally shared Flame audio cache during page teardown.

## Alternatives rejected

1. **Sound event bus / generic mixer / audio registry** — unnecessary for fixed, direct owner callbacks.
2. **Call `FlameAudio.play` for every projectile and hit** — no admission bound; unacceptable at 3×.
3. **Use `AudioPool.maxPlayers` as the only voice cap** — it governs player pool retention/reuse, not our explicit cross-cue priority budget.
4. **Make every projectile/drone/target its own sound source** — duplicates callbacks, increases allocations and noise.
5. **Generate assets in HPA-416** — violates the required separate-asset ticket/PR boundary and makes sound-design iteration drag gameplay code.
6. **Persist cue throttle state or expose per-cue volume sliders** — no user value at current scope.

## Validation and acceptance

- Pure limiter unit tests advance an injected wall clock: repeated same-family fire, mixed families, impact bursts, lane saturation, priority while low is saturated, and rolling-window expiry. Assert at most 2 low, 1 normal, 2 critical, and 5 accepted starts in *every* 500 ms window. Add a dense synthetic 3× pattern (many calls at the same timestamps); no async start-failure/release tests in the pure limiter.
- `platform_game_feedback_test.dart`: exact filename mapping for all eight types and three impacts, existing four cues remain, Sound Effects off suppresses **all** combat audio, haptics gate remains independent, constructor warm-up and pool ready/failure behavior do not throw, and owned pools clean up.
- `orion_defense_game_test.dart`: recording fake verifies successful vs denied start/sell, both direct and auto-start wave transitions, shot invocation through projectile/field/drone branches, one request per resolved splash/chain/pierce visual component (regardless of its target count), boss arrival/defeat, enemy death, nonlethal leak, lethal defeat without duplicated leak cue.
- `game_feedback_test.dart`: `NoOpGameFeedback` covers all added methods.
- Regression: `flutter analyze`, focused tests, `flutter test`. On device, listen to a busy 3× board and ensure frame pacing is unchanged, high-priority cues remain distinguishable, Sound Effects toggle silences new starts, and haptics still work independently. Asset-production listening/README checks remain HPA-385 acceptance.

**Scope exclusions:** music/ambience and audio-session/lifecycle music policy (HPA-417), per-cue settings, stereo panning, new gameplay mechanics, voice acting, or unrelated UI redesign.
