# HPA-416 — Combat Sound Effects Implementation Plan

> **One Linear coding ticket, one PR.** This draft starts with design + plan; add implementation and tests **to this same PR** before marking ready for review. **HPA-385** is a different ticket with **one separate asset-only PR**. Do not split HPA-416 into a design PR and an implementation PR.

- **Ticket:** [HPA-416](https://linear.app/cwchanap/issue/HPA-416/orion-add-combat-sound-effects)
- **Design authority:** [Combat Sound Effects design](../specs/2026-10-20-hpa-416-combat-sound-effects-design.md)
- **Asset prerequisite:** [HPA-385](https://linear.app/cwchanap/issue/HPA-385/orion-produce-combat-sfx-pack-for-hpa-416); 17 exact WAV filenames, generator, README, manifest, and audio-device acceptance belong there.
- **Read baseline:** `cwchanap/orion` `main` `3e2a7e7` (2026-10-20). Before coding or merging, fetch current `main` and rebase the same PR branch, especially after the asset PR merges. **Do not merge-commit**.

## Definition of done

The game emits one meaningful semantic request per resolved combat feedback component/transition (one splash/chain/pierce component can contain several target positions). The sound backend checks the existing live Sound Effects preference and admits only a bounded number of sounds in elapsed real time, protecting kill/core/boss messages during a busy 3× fight. Existing haptics and four feedback cues continue working. Focused tests + whole Flutter suite pass; device listening and frame pacing are checked. No code changes outside this ticket's stated responsibility.

## File map

**Add**
- `lib/game/feedback/combat_sound_limiter.dart` — pure, small cue/priority admission logic using supplied monotonic milliseconds and per-lane rolling admission timestamps; no per-asset duration data, timers, Flutter, or `GameSession`.
- `test/feedback/combat_sound_limiter_test.dart` — deterministic burst/priority/rolling-window tests.

**Modify**
- `lib/game/feedback/game_feedback.dart` — add typed cue methods, no-op definitions, platform filename mapping, high-frequency `AudioPool` startup, admission before playback, async failure handling and owned-resource disposal. If necessary, put a **single narrow playback test seam** here; no audio registry/framework.
- `lib/game/orion_defense_game.dart` — call existing feedback interface at existing resolved moments.
- `lib/game/ui/orion_game_page.dart` — dispose only the page-owned default platform feedback; never dispose an injected fake. Preserve existing delayed-preferences-load gating.
- `test/game/feedback/game_feedback_test.dart` — expand NoOp coverage.
- `test/feedback/platform_game_feedback_test.dart` — file mapping, preference gating, player/pool setup and failure/cleanup regression.
- `test/game/orion_defense_game_test.dart` — expand the existing recording fake and cover authoritative call sites.
- Any additional `GameFeedback` implementations revealed by `flutter analyze` — add matching no-op/recording methods only.

**Do not modify in HPA-416:** `scripts/generate_feedback_audio.py`, `assets/audio/*.wav`, `assets/audio/README.md`, `pubspec.yaml`, campaign saves, tower/enemy rules, `GameSnapshot`, onboarding/UI redesign. Those audio asset paths are supplied by HPA-385.

---

## Step 1 — Lock the API and the gate in tests

**Compile-safe first slice:**
1. Extend `GameFeedback` and `NoOpGameFeedback` with the typed methods `towerFired(TowerType)`, `splashImpact`, `chainImpact`, `pierceImpact`, `enemyDestroyed`, `coreHit`, `waveStarted`, `bossArrived` and `towerSold`; keep the existing `bossDefeated` signature. Update `_RecordingGameFeedback` and any other implementers so the project compiles before adding call-site assertions. Then add exhaustive no-op/recording tests.
2. Add pure limiter tests with an explicit `nowMs` argument; model real-time bursts. Cases:
   - 100 same-family fire requests at the same millisecond admit at most one from that family; mixed simultaneous families cannot exceed the **two low** budget.
   - Repeated splash/chain/pierce each obey a 180 ms per-kind interval and share that low budget.
   - Saturated low lane does **not** suppress an enemy kill (normal lane) or a core hit/boss cue (critical lane).
   - Across any rolling **500 ms** interval, admit at most **two low**, **one normal**, **two critical**, and **five total** combat starts.
   - Old timestamps fall out of the window and allow new starts; a failed player start **does not** release its admitted timestamp early.
   - Advancing the *game* time by 3× without advancing wall-clock `nowMs` does not admit additional sounds.
3. Add a table of `TowerType -> fire_<family>.wav` filenames and impact/semantic mappings to the playback test. Keep asset names in one implementation switch/mapping, not string concatenation scattered across the game.

**Implementation:** Small `CombatSoundLimiter` with three reserved lanes (low 2; normal 1; critical 2) and a single 500 ms rolling window. Hold the last N admitted timestamps per lane plus the last-admitted time per concrete cue for its minimum interval. Use monotonic `Stopwatch.elapsedMilliseconds` from platform feedback and record admitted starts **synchronously** before async playback, so same-frame bursts cannot race past limits. No timers, WAV-duration table, reservations, playback-failure release logic, or audio controls in `GameSession`. HPA-385 supplies WAVs no longer than 500 ms, so the rolling bound also constrains nominal simultaneous combat output without per-asset coupling.

## Step 2 — Extend PlatformGameFeedback without a new audio stack

**Tests first:** Verify all 17 new cue filenames, the original four cue mappings, sounds on/off, haptics on/off, best-effort warm-up/pool creation, and disposal. Test **Sound Effects OFF does not call or consume the limiter**, so an immediate re-enable permits a new sound, here in the platform integration test (not the pure-limiter test). Include an injected recording output at the narrow admission boundary if existing `AudioCache`/platform-channel fakes do not expose accepted start requests reliably; avoid mocking the entire game/Flame engine.

**Implement:**
1. Reuse the typed `GameFeedback` / `NoOpGameFeedback` contract established in Step 1; map `TowerType` to filenames exhaustively (no additional event API).
2. Preserve `PlatformGameFeedback`'s constructor-time cache warm-up and live preference callbacks. Start `AudioPool` instances **once per page-owned service**, asynchronously and best-effort, for shots, multi-target impacts and enemy death; no work per tower/game tick apart from the limiter check. Use pool limits 1–2 per sound *in addition to* the explicit gate. Rare events may retain `FlameAudio.play`. The asset list must match HPA-385 exactly after its PR merges.
3. Skip play on disabled sound, unavailable/uninitialized pool, or denied admission. Disabled sound or unready pool never calls/consumes the limiter; after admission, a failed audio start retains its short window slot. Do not enqueue/resume skipped sounds. Preserve haptics separately; add a light boss-arrival haptic and keep boss-defeat medium haptic.
4. Provide idempotent/best-effort `PlatformGameFeedback.dispose()` that prevents late pool initialization from leaking or playing and releases owned pools. Do not touch shared `FlameAudio.audioCache` or add lifecycle methods to every fake.

**Important:** `AudioPool.maxPlayers` is not a substitute for the five-starts-per-500-ms priority gate. Tests assert **accepted playback requests in every rolling window**, not a fabricated exact platform mixer voice count or merely pool size.

## Step 3 — Wire only existing resolved gameplay call sites

In `lib/game/orion_defense_game.dart`, follow the real success branch rather than a UI-button click or a snapshot observation:

1. In `_launchProjectile`, call `gameFeedback.towerFired(tower.placedTower.type)` once **before** the gravity-field/drone early returns. Never produce additional fire cues per drone's autonomous attack or gravity tick.
2. In `_addCombatFeedback`, switch only the `splash`, `chain`, and `pierce` variants to the three impact methods. Each splash/chain/pierce **visual component is one resolved multi-target event** with a list of positions, so emit one audio request per component, **not per target**. The limiter suppresses rapid *separate attack* requests; no change to damage or visual callback multiplicity. Ignore `enemyDestroyed` and `coreImpact` variants for **audio** (visual rendering continues unchanged); those are owned by their handlers.
3. In `_handleEnemyKilled`, call `enemyDestroyed` for regular kills; for a `BossDefinition`, call the already-existing `bossDefeated` once, with no generic death audio.
4. In `_handleEnemyReachedBase`, check the post-damage phase; use `coreHit` on nonlethal leaks, and existing `baseDefeated` on a losing leak. Do not stack both.
5. In `startWave`, emit `waveStarted` after `_session.startWave()` returns true. This covers manual and auto-start without duplicating code.
6. In `_spawnEnemy`, emit `bossArrived` only for an actual `BossDefinition`, not each summoned minion.
7. In `sellSelectedTower`, emit `towerSold` only after `_session.sellTower` returns a non-null refund.

No changes to projectile damage or hit selection, tower cadence, stage data, or campaign results.

## Step 4 — Ownership and integration tests

**Page ownership:** Track the **default-created** `PlatformGameFeedback` separately from injected `widget.gameFeedback`. Dispose it from `OrionGamePage.dispose()` once, ignoring best-effort cleanup errors; do not destroy/recreate it when switching stage/map or replaying. Retain the current callback that prevents sound/haptics until `_feedbackPreferencesLoaded` is true.

**Gameplay tests:** Update `_RecordingGameFeedback`; assert semantic event order and counts for all seven emission locations. Pin checks for rejected wave start/sell, boss vs normal kill, lethal vs nonlethal leak, and that the visual impact callback doesn't duplicate kill/core audio. Exercise one gameplay path each for normal projectile, gravity field, Drone Bay, and auto-start. Reuse current test fixtures; do not add a test-only game event bus.

**Audio tests:** Continue the existing `flame_audio` mock conventions; use deterministic fake time/playback for burst caps where testing real audio player completion would be flaky. Verify no extra sound requests after page disposal.

## Step 5 — Final validation and completion gates

Once HPA-385 is merged into `main`, update/rebase this **same** branch and exercise real assets. No placeholder binary assets or duplicate asset PR under HPA-416.

Suggested focused commands:

```bash
dart format --set-exit-if-changed lib/game/feedback lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart test/feedback test/game/orion_defense_game_test.dart test/game/feedback
flutter test test/feedback/combat_sound_limiter_test.dart test/feedback/platform_game_feedback_test.dart test/game/feedback/game_feedback_test.dart test/game/orion_defense_game_test.dart
flutter analyze
flutter test
```

Human device smoke:
- New Outpost Alpha mission at 1×, then a late-stage full board at 3×: distinct fire/impact/kill/core/boss cues without a constant audio wall or visible frame drop.
- Both manual and auto-start, boss arrival + boss defeat, and nonlethal vs lethal leak.
- Sound Effects OFF makes new starts silent; Haptics ON continues to work; reverse toggle combination also works.
- Return to map, launch another stage, and dispose/reopen page without duplicate playback or retained audio pools.

Mark draft ready only after the single coding PR contains its implementation and tests, the separate asset PR is merged, CI is green, and the device smoke is recorded. If listening shows oversaturation, first tune the small limiter constants rather than introducing a larger sound system.

## Acceptance crosswalk

| HPA-416 requirement | Owning step |
| --- | --- |
| All tower-family, impact, kill, leak, wave, boss, sell cues | Steps 2–3 |
| Every cue silent when Sound Effects off | Steps 1–2, 5 |
| Bounded combat start density / nominal voices and priority at 3× | Steps 1–2, 5 (with HPA-385 <= 500 ms clip bound) |
| Preserve old sounds/haptics; boss-arrival haptic | Steps 2–3 |
| Recording-fake + gameplay tests | Steps 1, 4 |
| WAV generation and asset documentation | **HPA-385 (separate asset ticket/PR)** |
| One implementation PR for the ticket | All steps, same branch |
