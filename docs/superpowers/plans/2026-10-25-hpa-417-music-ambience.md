# HPA-417 — Music and Ambience Implementation Plan

> **One coding ticket, one PR:** this *same* HPA-417 draft PR starts with docs, then receives runtime changes and tests before being marked ready. **HPA-168** is a separate, asset-only ticket and PR. Do **not** split this feature into a design PR and another coding PR.

- **Ticket:** [HPA-417](https://linear.app/cwchanap/issue/HPA-417/orion-add-music-and-ambience-with-a-separate-music-setting)
- **Spec:** [Music and ambience design](../specs/2026-10-25-hpa-417-music-ambience-design.md)
- **Asset handoff:** [HPA-168](https://linear.app/cwchanap/issue/HPA-168/orion-produce-original-ambient-music-loops-for-hpa-417)
- **Baseline:** `main` `54ddbe82259b59b646ba24167937923b68449b99` — re-check `main` before implementation/merge; use rebase or fast-forward, no merge commit.

## Definition of done

A single low-volume, looped background track plays for the current surface (map, build, wave, boss), stays silent for mission results, and **stops** during game pause and app background (restarting at the beginning when allowed). Music OFF works independently of Sound Effects/Haptics and persists; shared platform context makes both music **and existing SFX** honor iOS silent mode and mix with other apps. No gameplay/rule/balance modifications and no separate playback infrastructure.

## File ownership

**HPA-417 coding PR**
- Add `lib/game/feedback/game_music.dart`: `MusicTrack`, pure `desiredMusicTrack`, minimal `GameMusicController.set(MusicTrack?)`, fakeable `MusicPlayer.play/stop/dispose`, and adapter with a **lazy page-owned private `Bgm()`**. No `Bgm.initialize()`, global singleton, pause/resume seam, or second lifecycle observer.
- Modify `lib/game/feedback/feedback_preferences.dart`: `musicEnabled` default true, independent read/write, value semantics.
- Modify `lib/game/ui/feedback_settings_sheet.dart`: one Music switch next to Sound Effects, no volume slider.
- Modify `lib/game/models/game_models.dart`: add `GameSnapshot.bossActive`, with default false for existing tests.
- Modify `lib/game/rules/game_session.dart`: accept optional `bossActive = false` snapshot projection input; it is **not** mutable `GameSession` state.
- Modify `lib/game/orion_defense_game.dart`: project live boss presence from `_activeEnemyComponents` in `_publishSnapshot` and publish after a real boss spawn; no callbacks or gameplay rule changes.
- Modify `lib/game/ui/orion_game_page.dart`: injected/owned controller, **one `AppLifecycleListener`**, preferences gate, snapshot subscription/cleanup, pure-selector call and disposal. No codex/tech-tree sync hooks or page boss flag.
- Modify `lib/main.dart` (or the existing app startup entrypoint): before `runApp` and `PlatformGameFeedback` construction, **await one `AudioPlayer.global.setAudioContext`** with iOS ambient and Android game/none-focus. Log failures without blocking the game; no per-player session override. This intentionally changes SFX silent-switch/mixing behavior too.
- Add/extend `test/feedback/game_music_test.dart`, `test/game/feedback_preferences_test.dart`, `test/feedback/shared_preferences_feedback_store_test.dart`, `test/widget/feedback_settings_sheet_test.dart`, pertinent game/page snapshot tests, and the **existing** `test/feedback/audio_asset_contract_test.dart` (music checks skip until HPA-168). Keep the existing test runner's `test/flutter_test_config.dart` throwing channel stubs valid.

**HPA-168 asset-only PR:** four `assets/audio/music_{map,build,wave,boss}.wav` files, generator, generator tests, audio README and **`pubspec.yaml` registration**. No binary music, generator, or manifest edits in HPA-417. HPA-417 owns only the cross-PR contract test and integration, after the asset PR merges.

## Step 0 — Validate the native unknowns before coding

1. In disposable **uncommitted** device-spike code, use a local throwaway WAV loop with private `Bgm().play` (no `initialize()`) and the intended global context. Try one real iOS and one Android device. Observe repeated loop seams, silent switch, other-app music and Android calls/interruptions. Do not use copyrighted music or commit scratch assets.
2. If the native player introduces a loop gap or platform session side effect, record the platform/format and resolve the smallest file/encoding or adapter issue now; coordinate any changed music-file contract with HPA-168 **before** building the playback controller. Do not build an adaptive audio engine.
3. When devices are unavailable, document this as **unverified**, proceed with code/tests but keep the real-device acceptance gate unchecked. Do not claim that a spike ran simply because it is planned.

## Step 1 — Preference model and settings contract

1. Add `musicEnabled` as the third boolean with default true, update equality, hash, and `copyWith`.
2. Preserve the existing `soundEffects` and `haptics` values when reading valid JSON missing `music` or with only an invalid `music`; default that single field to true. Retain today's corrupt-record fallback and independent failure handling. Save all three fields under unchanged key `orion.feedback`.
3. Add the Music `SwitchListTile` to `FeedbackSettingsSheet`. Save only when Done closes the modal; cancellation returns null and doesn't change playback. Keep in-flight save guard, prior-value-on-save-failure, and breadcrumb in `OrionGamePage`.
4. Tests: default/old-key JSON, malformed field, round-trip, switch independence and cancellation; ensure existing tests with two explicit fields continue to pass.

## Step 2 — Pure selector, fakeable controller and single playback owner

1. Add `MusicTrack` with four filenames and a pure `desiredMusicTrack({required bool prefsLoaded, required bool musicOn, required bool appForeground, GameSnapshot? stage})`. With no active stage (`stage == null`), select map. Return null for unloaded prefs, Music OFF, app not resumed, paused game or result. Otherwise select build, wave or boss via `stage.phase` and `stage.bossActive`. Unit-test **each behavior-table row** without pumping a Flutter widget; `_syncMusic` should only supply inputs and pass its answer to the controller.
2. Implement `GameMusicController.set(MusicTrack?)` and a small `MusicPlayer` seam with **only** `play/stop/dispose`. Repeated equal targets do nothing; null means stop even for game pause/background. Resuming starts the short ambient loop from the beginning; no position-preserving pause/resume, suspension flag or background ownership in the player.
3. Default adapter lazily constructs one private `Bgm()` **upon first play, never in `OrionGamePage.initState`**. Use `play(filename, volume: 0.18)`, `stop`, `dispose`; do not call `Bgm.initialize()` or any method on the static-final `FlameAudio.bgm`. A new page/controller owns a new disposable player. An injected controller is not disposed by the page.
4. Serialize pending async native calls and compare the latest requested target after every await. An older play cannot survive Music OFF, app background, result or disposal; stop before a different track. Follow the existing page future-chain idiom, not a new scheduler. Guard synchronous constructor failures and rejected futures during play/stop/teardown; log and swallow native channel/asset errors without blocking gameplay or leaking widget-test exceptions.
5. Fake-player tests cover unchanged targets, rapid map→wave→boss, Music OFF while play is pending, stage result, pause/background as `set(null)`, foreground/unpause restarting from zero, native command failures and repeated disposal. Add **one** default production-adapter/page test under the existing throwing audioplayers stubs: build/pump/unmount with no uncaught errors. Do not test Flame's global singleton lifecycle through unrelated remount tests.

## Step 3 — Snapshot boss presence and minimal page wiring

1. Extend `GameSnapshot` with read-only `bossActive` default false, and accept/pass the same optional named parameter in `GameSession.snapshot`. The `GameSession` does not own or mutate enemy state; the optional parameter simply supplies presentation data, matching its existing `isPaused`/pacing parameters.
2. In `OrionDefenseGame._publishSnapshot`, supply `bossActive: _activeEnemyComponents.values.any((e) => e.stats is BossDefinition)`. Add **one** `_publishSnapshot()` after `gameFeedback.bossArrived()` at boss spawn, because spawn currently does not publish. Existing kill, nonlethal boss base reach, game loss, restart and combat cleanup clear enemies before the next publish. Minions do not count. Test boss arrival, removal on kill/leak, multiple-boss correctness and restart; preserve existing SFX emissions.
3. Add optional `GameMusicController? gameMusicController` to `OrionGamePage` alongside `gameFeedback`. Create the default coordinator in page state, but it must not construct the native `Bgm()` until music is really requested. Dispose only the page-created controller. No separate `_bossPresent` field, boss callback or stale boss callback guard.
4. Page owns one `AppLifecycleListener` with `onStateChange`; `appForeground` is true **only** for `AppLifecycleState.resumed`. Set the initial foreground input from the binding lifecycle, treating an absent test/runtime lifecycle state as resumed until a non-resumed state is observed; stop on inactive/hidden/paused/detached and recompute on resume. Dispose the listener at page teardown. No `Bgm` observer; the controller is the sole audio command owner.
5. Subscribe once to `_game!.stateNotifier` on `_startStage`; remove the previous listener before replacing the game or setting `_game = null` in `_returnToMap` and successful campaign reset. No music commands inside widget `build`. The sync sites are: feedback preference load (and fallback), successful settings save, stage entry, these two stage-exit sites, snapshot updates (including restart), lifecycle changes and teardown. **Do not add** hooks to codex/tech-tree opening/closing or the stage-briefing modal; when `_game == null`, the pure selector already returns map. Guard disposed state/obsolete stage listeners.
6. `_syncMusic()` calls `controller.set(desiredMusicTrack(prefsLoaded: _feedbackPreferencesLoaded, musicOn: _feedbackPreferences.musicEnabled, appForeground: _appForeground, stage: _game?.snapshot))`. Verify paused-game foreground remains silent, won/lost stinger has no music underneath, reset/return selects map, and old stage events cannot restart a discarded track.

## Step 4 — Shared platform context and asset handoff

1. Before building the app page in production (e.g. `main()` startup before `runApp`), await a **single global** `AudioPlayer.global.setAudioContext(AudioContext(iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient), android: AudioContextAndroid(usageType: AndroidUsageType.game, audioFocus: AndroidAudioFocus.none)))`. Confirm exact enum/constructor names from pinned `audioplayers` 6.8.1 first. Catch/log initialization failures; gameplay still boots. Do **not** use `AudioContextConfig(respectSilence: true)`, `Bgm.initialize()`, or contradictory pool contexts.
2. This context applies to **both music and SFX** on iOS: existing SFX now also respect silent switch and mix with external audio, replacing library defaults. On Android, focus `none` prevents the game from interrupting other audio, but intentionally means no focus-loss callback for calls; rely on the app lifecycle listener for foreground/background and **test device interruptions explicitly**. No native audio service, focus request or background mode.
3. Extend existing `test/feedback/audio_asset_contract_test.dart` to derive four music filenames from `MusicTrack.values`, require explicit `pubspec.yaml` declarations, check mono PCM WAV duration (~15–25 s) and total size ≤5 MB by reusing existing WAV duration parsing. Follow its HPA-385 cross-PR gate: skip with a concrete missing-asset reason until the **HPA-168 asset-only PR** lands, then enforce full contract automatically. The asset files and manifest remain HPA-168-owned.
4. After HPA-168 merges, listen on real iOS/Android to each loop seam and the 1×/3× SFX balance (4–5 towers and busiest waves), result silence, iOS silent switch and mixing, Android call/other-app behavior and background/foreground restart. If native WAV looping has a measured audible gap, record evidence and choose the smallest proven fix; adjust file encoding in HPA-168, not a generalized scheduler.

## Step 5 — Validation and completion

Run after coding:

```bash
dart format lib/game/feedback lib/game/ui/orion_game_page.dart lib/game/orion_defense_game.dart lib/game/ui/feedback_settings_sheet.dart test
flutter test test/game/feedback_preferences_test.dart test/feedback/shared_preferences_feedback_store_test.dart test/widget/feedback_settings_sheet_test.dart test/feedback/game_music_test.dart test/feedback/audio_asset_contract_test.dart
flutter analyze
flutter test
```

Device smoke matrix (real devices preferred for audio behavior):
- Cold launch with saved Music OFF; neither initial map nor stage begins a loop, but SFX ON still sounds.
- Map → briefing → build → wave → boss → wave → build/intermission → victory/defeat → map; repeat with Retry. Verify `bossActive` derives from live bosses, including nonlethal leaks, and only one loop plays.
- Pause and app switch independently; the current loop **stops** and restarts from the beginning when allowed. Foreground while the game remains paused stays silent. No background audio.
- Silent switch / existing external music on iOS; **music and SFX** should mix politely and obey silent mode. Android `audioFocus: none` does not react to focus-loss callbacks; test app lifecycle, interruptions and other-app audio.
- Complete early device spike (or document why not verified), then repeated loop seam for each HPA-168 asset; no clicks/gaps, mono PCM, 15–25 seconds, combined ≤5 MB, low mix relative to existing combat SFX. Confirm code-only cross-PR contract test is unskipped after asset merge.
- Store failure/cancel keeps prior Music state, and Sound Effects / Haptics remain independent.

**Exit gates:** tests and static checks green; four assets merged separately; one documented real-device listening pass. If a real device is unavailable, leave that verification explicitly unchecked rather than claiming acceptance. Design/plan changes and runtime code remain in **this same HPA-417 PR**; do not open a follow-up coding PR for the same task.
