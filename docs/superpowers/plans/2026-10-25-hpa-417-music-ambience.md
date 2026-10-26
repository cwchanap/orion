# HPA-417 — Music and Ambience Implementation Plan

> **One coding ticket, one PR:** this *same* HPA-417 draft PR starts with docs, then receives runtime changes and tests before being marked ready. **HPA-168** is a separate, asset-only ticket and PR. Do **not** split this feature into a design PR and another coding PR.

- **Ticket:** [HPA-417](https://linear.app/cwchanap/issue/HPA-417/orion-add-music-and-ambience-with-a-separate-music-setting)
- **Spec:** [Music and ambience design](../specs/2026-10-25-hpa-417-music-ambience-design.md)
- **Asset handoff:** [HPA-168](https://linear.app/cwchanap/issue/HPA-168/orion-produce-original-ambient-music-loops-for-hpa-417)
- **Baseline:** `main` `54ddbe82259b59b646ba24167937923b68449b99` — re-check `main` before implementation/merge; use rebase or fast-forward, no merge commit.

## Definition of done

A single low-volume, looped background track plays for the current surface (map, build, wave, boss), stays silent for mission results, and suspends during game pause and app background. Music OFF works independently of Sound Effects/Haptics and persists; platform audio respects silent mode and other apps. No gameplay/rule/balance modifications and no separate playback infrastructure.

## File ownership

**HPA-417 coding PR**
- Add `lib/game/feedback/game_music.dart`: minimal `GameMusicController`, exact four track identities and playback fake seam; production adapter owns a **new page-scoped `Bgm()`** from existing `flame_audio`, not its static-final `FlameAudio.bgm` singleton.
- Modify `lib/game/feedback/feedback_preferences.dart`: `musicEnabled` default true, independent read/write, value semantics.
- Modify `lib/game/ui/feedback_settings_sheet.dart`: one Music switch next to Sound Effects, no volume slider.
- Modify `lib/game/ui/orion_game_page.dart`: injectable `gameMusicController` constructor parameter (like `gameFeedback`); page owns/disposes only the default-created controller and private `Bgm()`, plus initial settings gate, stage/map lifecycle synchronization, game snapshot subscription and boss callback.
- Modify `lib/game/orion_defense_game.dart`: one optional presentation-only callback for actual boss spawn and boss exit/cleanup; no rule changes.
- Add/extend `test/feedback/game_music_test.dart`, `test/game/feedback_preferences_test.dart`, `test/feedback/shared_preferences_feedback_store_test.dart`, `test/widget/feedback_settings_sheet_test.dart`, and relevant page/game tests. The existing test runner's `test/flutter_test_config.dart` native channel stubs must remain valid.
- **Required:** initialize the owned BGM player with an explicit iOS ambient audio context to respect the silent switch; verify the effective session remains compatible with existing SFX without adding a service registry or package.

**HPA-168 asset-only PR:** `assets/audio/music_{map,build,wave,boss}.wav`, music generator, generator tests, audio README and **`pubspec.yaml` registration**. No WAV/asset commits in HPA-417. Integrate after that asset PR merges.

## Step 1 — Preference model and settings contract

1. Add `musicEnabled` as the third boolean with default true, update equality, hash, and `copyWith`.
2. Preserve the existing `soundEffects` and `haptics` values when reading valid JSON missing `music` or with only an invalid `music`; default that single field to true. Retain today's corrupt-record fallback and independent failure handling. Save all three fields under unchanged key `orion.feedback`.
3. Add the Music `SwitchListTile` to `FeedbackSettingsSheet`. Save only when Done closes the modal; cancellation returns null and doesn't change playback. Keep in-flight save guard, prior-value-on-save-failure, and breadcrumb in `OrionGamePage`.
4. Tests: default/old-key JSON, malformed field, round-trip, switch independence and cancellation; ensure existing tests with two explicit fields continue to pass.

## Step 2 — One fakeable, race-safe music coordinator

1. Implement `MusicTrack` enum with four exact filenames and `GameMusicController` wrapping a small `MusicPlayer` interface or equivalent injected callbacks for `play/stop/pause/resume/dispose`. Allow `OrionGamePage(gameMusicController: fake)` to inject that same controller for widget tests, matching existing `gameFeedback` injection. This is **one** test seam, not a generalized audio backend.
2. Controller API accepts resolved desired track (nullable) and whether output is suspended/disabled. Compare target before I/O: repeated equal states issue no player commands. Only one loop plays; stopping replaces any current track.
3. BGM adapter constructs one **private `Bgm()`** for each page-created controller and calls its `initialize(...)` once, passing the required iOS ambient context. Use that instance's `play`, `pause`, `resume`, `stop`, `dispose` and built-in lifecycle observer; don't add another observer. **Never call `FlameAudio.bgm.dispose()` or reinitialize its singleton**, because its disposed internal `AudioPlayer` is not reusable. On page teardown, stop and dispose the owned `Bgm()` once, so a later page remount builds a healthy new instance. Never dispose an injected controller. Avoid `FlameAudio.loop` per snapshot.
4. Serialize pending async native calls and compare the latest desired state after each await. A late previous play must not restart audio after Music OFF/map exit/disposal. **Catch/log failures in `initialize()`, `play/stop/pause/resume`, and `dispose()`**, including synchronous platform exceptions and rejected futures: existing `test/flutter_test_config.dart` intentionally throws from unconfigured audioplayers channels. Never leak an unhandled async teardown error or block gameplay. Keep fixed quiet volume, tuned after listening; no slider.
5. Fake tests for repeated snapshots, quick map→wave→boss, disabled while play is pending, paused vs app background, foreground with game still paused, stopped terminal scene, and idempotent disposal. Add a default-production-adapter widget smoke under the existing throwing audio stubs: initial load, page unmount and remount must complete without unhandled channel errors or a disposed static singleton.

## Step 3 — Wire the existing page and authoritative boss moments

1. Add optional `GameMusicController? gameMusicController` to the `OrionGamePage` constructor, parallel to `gameFeedback`. If absent, create one page-owned production controller and `Bgm()` in state; if supplied, reuse the injected controller and **do not dispose it**. Do not allocate either in `build()`. As soon as feedback preferences resolve, choose map music if Music is ON. Preference load failure uses existing defaults. Do not start audible music before that gate.
2. Centralize a small `_syncMusic()` on page: for `worldMap/codex/techTree` choose map; for stage choose null when won/lost; otherwise derive build/wave from `game.snapshot.phase`, `game.snapshot.isPaused`, and a page-owned transient `_bossPresent`. This boolean is presentation state only; clear it at stage creation, replay and exit.
3. Subscribe to `game.stateNotifier` once in `_startStage`; unsubscribe from the previous active notifier **before** dropping it at `_returnToMap`, reset or another stage. In listener verify callback belongs to current active game. The existing `ValueListenableBuilder` still drives widgets; don't add player calls inside its builder.
4. Add `ValueChanged<bool>? onBossPresenceChanged` as an **optional constructor parameter** of `OrionDefenseGame`, just like its existing `onStageWon`/`onReturnToMap`. When constructing the game in `_startStage`, supply a closure capturing that specific game and ignore stale notifications unless `identical(_game, game)`; do not expose a settable callback. Emit true after `_spawnEnemy` tracks actual `BossDefinition`; emit false when the boss is removed after a real kill or base reach (including a nonlethal boss leak **without** a `bossDefeated` SFX), and on explicit reset/combat cleanup, with no redundant false emission. Do not treat summoned minions or generic enemy destroyed as boss. Keep SFX `gameFeedback.bossArrived/bossDefeated` unchanged.
5. Wire `_syncMusic` at `_startStage`, `_openTechTree/_closeTechTree`, `_openCodex/_closeCodex`, `_returnToMap`, `_restartFromMissionReport`, campaign reset and successful preference save; null track for won/lost suppresses music under SFX result stingers. Stage briefing remains map music.
6. End-state safety: old stage callback after map/replay must not trigger boss track. Same snapshot repeated from countdown or repeated game updates must not restart player. Page disposal detaches listeners and disposes **only its page-created controller/private `Bgm()`**; neither injected `gameMusicController`/`GameFeedback` nor the process-wide `FlameAudio.bgm` singleton is disposed. Dispose asynchronously/best-effort without leaking errors. Test mount→unmount→mount again.

## Step 4 — Platform behavior and asset handoff

1. **Pass an explicit `AudioContextIOS` ambient, silent-switch-respecting context to page-owned `Bgm.initialize()`**; the library's default context is only `mixWithOthers` and is not enough. Confirm the pinned audioplayers constructor/options for that context before coding. Verify shared audio session does not get reverted by `PlatformGameFeedback` pool initialization. Make only the minimum shared configuration change required for both channels to behave; no new package, no `UIBackgroundModes=audio`.
2. Android: defer to existing audioplayers audio focus and interruptions; music must not keep playing with app backgrounded or keep another application's audio ducked. Test actual focus switching rather than adding native code in anticipation.
3. Merge **HPA-168's separate PR** containing the four registered WAVs before invoking the real BGM player in integration or native device smoke. Assert each expected asset is bundled. If wav looping has perceptible platform gaps, record device/platform/file evidence and fix the smallest proven cause. Keep asset changes in HPA-168.
4. Volume and mix: at 1× with 4–5 towers and at busy 3×, manually listen for fatigue, masked core hits, boss cue clarity and clean return to silence on result. Adjust the one default gain based on evidence, not a configurable UI.

## Step 5 — Validation and completion

Run after coding:

```bash
dart format lib/game/feedback lib/game/ui/orion_game_page.dart lib/game/orion_defense_game.dart lib/game/ui/feedback_settings_sheet.dart test
flutter test test/game/feedback_preferences_test.dart test/feedback/shared_preferences_feedback_store_test.dart test/widget/feedback_settings_sheet_test.dart test/feedback/game_music_test.dart
flutter analyze
flutter test
```

Device smoke matrix (real devices preferred for audio behavior):
- Cold launch with saved Music OFF; neither initial map nor stage begins a loop, but SFX ON still sounds.
- Map → briefing → build → wave → boss → wave → build/intermission → victory/defeat → map; repeat with Retry. Verify one active loop and no stale previous stage.
- Pause and app switch independently; return foreground while paused remains silent, then explicit resume works. No background audio.
- Silent switch / existing external music on iOS; music and SFX should mix politely without overriding silent mode. Android app focus/interruption behavior.
- Repeated loop seam for each asset; no clicks/gaps, bounded app bundle size, low mix relative to existing combat SFX.
- Store failure/cancel keeps prior Music state, and Sound Effects / Haptics remain independent.

**Exit gates:** tests and static checks green; four assets merged separately; one documented real-device listening pass. If a real device is unavailable, leave that verification explicitly unchecked rather than claiming acceptance. Design/plan changes and runtime code remain in **this same HPA-417 PR**; do not open a follow-up coding PR for the same task.
