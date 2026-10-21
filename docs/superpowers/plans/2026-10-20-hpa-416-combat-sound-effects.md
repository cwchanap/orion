# HPA-416 — Combat Sound Effects Implementation Plan

> **One Linear coding ticket, one PR.** This draft starts with design + plan; add implementation and tests **to this same PR** before marking ready for review. **HPA-385** is a different ticket with **one separate asset-only PR**. Do not split HPA-416 into a design PR and an implementation PR.

- **Ticket:** [HPA-416](https://linear.app/cwchanap/issue/HPA-416/orion-add-combat-sound-effects)
- **Design authority:** [Combat Sound Effects design](../specs/2026-10-20-hpa-416-combat-sound-effects-design.md)
- **Asset prerequisite:** [HPA-385](https://linear.app/cwchanap/issue/HPA-385/orion-produce-combat-sfx-pack-for-hpa-416); 17 exact WAV filenames, generator, README, manifest, and audio-device acceptance belong there.
- **Read baseline:** `cwchanap/orion` `main` `3e2a7e7` (2026-10-20). Before coding or merging, fetch current `main` and rebase the same PR branch, especially after the asset PR merges. **Do not merge-commit**.

## Definition of done

Emit a typed sound request only after a combat action truly occurs (never for a capped Drone Bay), distinguish resolved multi-target impacts, protect once-per-event boss/wave/sell cues from rate limiting, and drop redundant fire/impact traffic using real wall-clock time. Existing preferences, haptics and four legacy sounds remain unchanged. No post-loss leak/death audio. The separate 17-WAV asset pack is verified against the playback mapping. The full Flutter suite and device checks pass.

## File map

**Add**
- `lib/game/feedback/combat_sound_limiter.dart` — pure per-cue interval logic and **one** shared 2-per-500 ms timestamp buffer for 11 fire/impact cues; monotonic injected `nowMs`, no timers, asset-duration table, lane types, or playback bookkeeping.
- `test/feedback/combat_sound_limiter_test.dart` — deterministic admission tests, rolling-window boundaries and synthetic 3× load.
- `test/flutter_test_config.dart` — Flutter test-runner hook installing safe, throwing audioplayers global/per-player channel mocks before each test; individual tests may override as needed.
- `test/feedback/audio_asset_contract_test.dart` — post-HPA-385 integration test proving every advertised file exists, is explicitly listed in `pubspec.yaml`, and the 17 new WAVs meet the ≤500 ms duration contract.

**Modify**
- `lib/game/feedback/game_feedback.dart` — typed methods and no-op implementations; exhaustive tower filename switch, rare cue one-shots, 13 pooled high-frequency cues, live settings, minimal owned disposal, and the **required** optional `startCombatSound` + `nowMs` test seams.
- `lib/game/orion_defense_game.dart` — emit only from real resolved transitions; prevent capped Drone Bay fire and post-loss cues.
- `lib/game/ui/orion_game_page.dart` — dispose only page-created platform feedback, not injected implementations.
- `test/game/feedback/game_feedback_test.dart` — new no-op coverage.
- `test/feedback/platform_game_feedback_test.dart` — injected start/clock tests, 21 filenames, preference and haptic checks, pool readiness/failure and disposal.
- `test/game/orion_defense_game_test.dart` — recording fake and tests colocated with the seven callback integrations.
- Existing tests with bespoke audioplayers stubs — remove duplication where global test configuration suffices, preserving per-test overrides and cleanup.
- Other implementers of `GameFeedback` exposed by the analyzer — only required typed methods.

**Do not modify in HPA-416:** `scripts/generate_feedback_audio.py`, `assets/audio/*.wav`, `assets/audio/README.md`, `pubspec.yaml`, campaign saves, tower/enemy rules, `GameSnapshot`, or unrelated screens. Those asset paths are owned by HPA-385.

---

## Step 1 — Compile-safe cue API and pure limiter

1. Extend `GameFeedback` and `NoOpGameFeedback` with `towerFired(TowerType)`, `splashImpact`, `chainImpact`, `pierceImpact`, `enemyDestroyed`, `coreHit`, `waveStarted`, `bossArrived`, and `towerSold`; retain existing `bossDefeated()`. Extend `_RecordingGameFeedback` and any other fake **before** writing assertions relying on the new contract. Run the existing no-op/recording tests.
2. Test and implement a tiny `CombatSoundLimiter` receiving concrete cue identifiers + `nowMs`. Limit only the **13 high-frequency cues**:
   - 8 fire cues + 3 impacts: 120/180 ms respective per-cue cooldown **and one shared budget** of 2 admitted starts in any rolling 500 ms.
   - Ordinary enemy destroyed: 500 ms per-cue cooldown, **not** in shared budget.
   - Nonlethal core hit: 250 ms per-cue cooldown, **not** in shared budget.
   - Synchronous admission; prune entries ≥500 ms old; denied cues drop with no catch-up; playback errors do not release timestamps. Use `Stopwatch.elapsedMilliseconds` in the platform backend, and inject `nowMs` in tests.
3. Tests prove same-timestamp fire, mixed families/impacts, shared budget exhaustion, 500 ms rolling boundaries, kill/core acceptance during full fire budget, ≤5 admitted **high-frequency** starts per 500 ms, and unchanged limits when Flame/game time runs 3× faster. No three-lane model or WAV-length tracking.
4. Decide filename mapping now: one exhaustive `TowerType` switch yielding `fire_<family>.wav`; exact names for 3 impacts, enemy kill, core hit, and 4 rare transitions. Boss/wave/sell never call the limiter (confirm/clear/victory/defeat already bypass it).

## Step 2 — Shared test setup, assets and platform playback

1. **First**, install `test/flutter_test_config.dart` with `testExecutable` and per-test default mock handlers for `xyz.luan/audioplayers.global` (init completes) and `xyz.luan/audioplayers` (unsupported native operations fail promptly rather than hang). Keep local overrides for recording/error scenarios. Note `test/widget_test.dart`'s `testGamePage` helper already injects `NoOpGameFeedback`; the global hook primarily protects tests explicitly constructing the real default feedback (including `test/widget/sell_button_test.dart`). Consolidate duplicated stubs without breaking tests that intentionally override them.
2. **Dependency gate:** merge **HPA-385's separate asset PR** and rebase this same branch before activating 17 new files in runtime warm-up or the asset-contract test. No placeholders or generation in HPA-416. Confirm all 17 new WAVs are ≤500 ms.
3. Add **two optional constructor inputs** to `PlatformGameFeedback`: `Future<void> Function(String file)? startCombatSound` and `int Function()? nowMs`. An injected starter records accepted filenames and replaces pool creation/readiness *in tests only*. The default production path eagerly initializes the 13 high-frequency `AudioPool` instances asynchronously once per page-owned service; the existing constructor-time `FlameAudio.audioCache.loadAll` warm-up remains. Use conservative player pool sizes (1–2 each). Never await audio creation in gameplay.
4. Keep admission order: enabled Sound Effects → starter/pool readiness → limiter → best-effort start. Neither disabled sound nor unready/failed pool consumes a slot; a failure **after** admission occupies its short window slot until expiry. No retries, service locators, audio registries, or `GameSession` changes. Respect independent haptics, including light boss arrival and existing medium boss defeat.
5. High-frequency 13 cues use pooled starts; `waveStarted`, `bossArrived`, `bossDefeated`, and `towerSold` use `FlameAudio.play` directly (outside limiter), as do existing four one-shots. Verify two core hits at 0 and 250 ms **cannot suppress** a boss-defeat request at 300 ms. Pool `maxPlayers` is not the shared admission cap.
6. Add `test/feedback/audio_asset_contract_test.dart`. Check that every `PlatformGameFeedback.sounds` name exists at `assets/audio/<name>` and has an explicit `pubspec.yaml` asset line. Inspect RIFF/WAV chunk header values to calculate each **new** clip's duration as data-chunk bytes / byte rate; require ≤500 ms. Assert this independently of the generator and the filename mapping unit-test table.
7. Add platform feedback tests with the injected starter/clock for mapping, accepted starts at fake timestamps, Sound Effects OFF **not consuming admission**, immediately re-enabled sound, rare boss/wave/sell bypass, original four sounds, independent haptics, pool warm-up/failure behavior and disposal. Keep tests deterministic without requiring a native audio engine.
8. **Run full `flutter test` now**, not only in Step 5. This catches cross-suite native audio mock interactions as soon as eager pool creation lands; fix the shared test setup rather than silently skipping affected widget files.

## Step 3 — Add gameplay event hooks together with their tests

Implement one authoritative call site and its recording-fake assertions **in the same substep**, so the code never outruns coverage:

1. `_launchProjectile`: after `_trackCombatEntity(ProjectileComponent)` emit one `towerFired`; after `_trackCombatEntity(GravityFieldComponent)` emit one `towerFired`; for Drone Bays emit **inside `_launchDrones` after `allowed > 0` and the launch is tracked**, only once per batch. A bay at shared/per-tower capacity produces **no** firing sound. Test all four cases, including a capped bay.
2. `_addCombatFeedback`: switch `CombatFeedbackKind.splash`, `chain`, `pierce` to a single sound request per resolved feedback component, regardless of `positions.length`. Do not turn `enemyDestroyed` or `coreImpact` **visual cues** into audio here. Test without touching hit-selection or VFX multiplicity.
3. `_handleEnemyKilled`: emit `bossDefeated` for a boss instead of ordinary `enemyDestroyed`; emit ordinary kill audio only while `_session.phase == GamePhase.wave`. Test normal/boss and post-loss callback cases. Leave existing reward/rendering semantics unchanged.
4. `_handleEnemyReachedBase`: capture `phaseBeforeDamage`, apply session damage, and emit `baseDefeated` only on the transition to `lost`. Emit `coreHit` **only if** `phaseBeforeDamage == GamePhase.wave && !didLose` (never as an unconditional `else`). Test a **second same-tick leak after fatal damage**: no post-loss core audio, no second stinger.
5. `startWave`: call `waveStarted` only after a successful `_session.startWave()`; this covers manual and auto-start. Test rejected vs successful starts, both paths.
6. `_spawnEnemy`: call `bossArrived` for `BossDefinition` only, never summoned minions. Test both.
7. `sellSelectedTower`: call `towerSold` only when a refund exists. Test successful sale and failed sale outside build phase.

No projectile damage, spawn balance, tower cooldown, save, campaign, or targeting edits.

## Step 4 — Minimal ownership and regression checks

**Page ownership:** Keep one page-created `PlatformGameFeedback` over stages/replays, distinct from `widget.gameFeedback` injection. On `OrionGamePage.dispose()` only, invoke its tiny idempotent cleanup: mark `_disposed`, dispose owned pools, and check `_disposed` after asynchronous pool creation (dispose late-completed pools immediately). Preserve the preferences-loaded gate and shared global audio cache. **Map/stage transitions do not dispose the app's `home:` page**; do not add extra stage lifecycle machinery.

Test widget disposal with `pumpWidget`/unmount, including late pool creation, and verify injected fakes are untouched. Retest platform readiness failures, haptics independent of Sound Effects, no post-loss audio and the normal/boss/critical precedence. Keep rare transition sounds independent of the high-frequency limiter. Run focused tests, `flutter analyze`, and full `flutter test`.

## Step 5 — Device listening and completion gates

Suggested focused commands:

```bash
dart format --set-exit-if-changed lib/game/feedback lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart test/flutter_test_config.dart test/feedback test/game/orion_defense_game_test.dart test/game/feedback
flutter test test/feedback/combat_sound_limiter_test.dart test/feedback/audio_asset_contract_test.dart test/feedback/platform_game_feedback_test.dart test/game/feedback/game_feedback_test.dart test/game/orion_defense_game_test.dart
flutter analyze
flutter test
```

Device smoke after HPA-385's WAV pack is merged:
- **Prioritize Outpost Alpha at 1× with 4–5 towers.** The 2-per-500 ms fire/impact budget permits at most four of those starts per second. Judge whether enough distinct attacks remain audible; tune a few constants after hearing the actual game, not by intuition.
- Then stress a dense 3× board: boss arrival/death audible through core-hit bursts, no audio wall or visible frame pacing drop, normal kill and nonlethal leak still discernible.
- Check manual/auto wave starts, successful tower sale, and capped Drone Bays **silent on unsuccessful launches**.
- Check Sound Effects OFF (no *new* starts) with Haptics ON, then the inverse. Test post-loss same-tick leaks.
- Return to map and start a new stage without duplicate audio or creating another audio service; exercise page disposal in **widget tests**, not an unreachable production screen-flow smoke test.

Keep this same PR as a draft until it contains the implementation, test suite and passing cross-PR asset contract; the HPA-385 asset PR is merged; CI is green; and device listening/frame pacing are recorded. Do not add an audio mixer, event bus, new settings, or a second HPA-416 PR to solve tuning issues.

## Acceptance crosswalk

| HPA-416 requirement | Owning step |
| --- | --- |
| All tower-family, impact, kill, core leak, wave, boss, sale cues | Steps 2–3 |
| Boss/wave/sell reliably bypass busy-shot limits | Steps 1–3 |
| Every cue silent when Sound Effects off, haptics separate | Steps 2 and 4–5 |
| ≤5 high-frequency admissions/500 ms at 3×; 1× readability | Steps 1–2 and 5 |
| Capped Drone Bays silent; no post-loss leak/kill audio | Step 3 |
| Shared native audio mocks; direct playback/clock test seams | Step 2 |
| On-disk WAV/manifest/duration contract | Step 2 after HPA-385 |
| Lifecycle ownership, recording-fake tests, full suite | Steps 2–4 |
| Asset generation and documentation | **HPA-385 (separate asset ticket/PR)** |
| One implementation PR for the ticket | All steps, same branch |
