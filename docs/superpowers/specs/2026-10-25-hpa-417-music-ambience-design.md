# HPA-417 — Music and Ambience Design

**Linear:** [HPA-417](https://linear.app/cwchanap/issue/HPA-417/orion-add-music-and-ambience-with-a-separate-music-setting)  
**Separate music asset task:** [HPA-168](https://linear.app/cwchanap/issue/HPA-168/orion-produce-original-ambient-music-loops-for-hpa-417)  
**Baseline:** `main` at `54ddbe82259b59b646ba24167937923b68449b99` (2026-10-25 local)  
**Status:** proposed; this PR contains design and implementation plan, not runtime code or binary assets.

## Player outcome

Orion has quiet, unobtrusive ambience on the world map and a distinct loop for build, active waves and boss encounters. Music is separate from combat SFX and haptics. A player can switch it off without affecting other channels; interruption, pause and navigation stop the loop, and music restarts at the start of the selected loop when playback is allowed again. This is **presentation only**, not a rule, campaign, timing or balance change.

Prefer the smallest feature that makes the existing loop feel alive. Four tracks, one Music switch, one player, no adaptive mixer, stems, crossfade scheduler, per-stage soundtrack, volume mixer, audio event bus, state persistence beyond one bool, or new gameplay snapshot/state authority.

## Verified reuse survey

- `lib/game/feedback/game_feedback.dart`: `PlatformGameFeedback` handles one-shot SFX and 13 pooled combat cues; page owns/disposes it. Leave its limiter, cue mapping and haptic semantics untouched.
- `lib/game/feedback/feedback_preferences.dart`: `FeedbackPreferences` and `SharedPreferencesFeedbackPreferencesStore` persist `orion.feedback` with `soundEffects` and `haptics`; add one field and retain both old values on read.
- `lib/game/ui/feedback_settings_sheet.dart`: modal edits a local preferences draft and returns it on Done; add Music switch using the same interaction pattern (cancelling dismisses all edits).
- `lib/game/ui/orion_game_page.dart`: one page survives map/stage transitions, loads preferences independently, owns feedback cleanup, creates each `OrionDefenseGame` in `_startStage`, returns in `_returnToMap` and `_confirmResetCampaign`, and exposes GameSnapshot via `game.stateNotifier`.
- `lib/game/models/game_models.dart`: `GameSnapshot.phase`, `isPaused` and `isEnded` already distinguish build, wave, won, lost and in-game pause. Extend this same read-only projection with `bossActive` (default false for existing test fixtures); don't invent another gameplay mode or mutable authority.
- `lib/game/orion_defense_game.dart`: `_activeEnemyComponents` already tracks live enemies; `_spawnEnemy` adds actual `BossDefinition` enemies to that map, and kill/leak/cleanup removes them. Compute `bossActive` from this canonical map in `_publishSnapshot()`; add one publish on boss spawn because that path currently does not publish. No callback or mirrored UI state.
- `flame_audio: ^2.12.2` provides `Bgm.play/stop/dispose`, looping and the existing audio cache. Construct a **private page-owned `Bgm()` lazily on the first real play**, never use/dispose/reinitialize the static-final `FlameAudio.bgm` singleton, and deliberately **do not call `Bgm.initialize()`**: it installs a competing lifecycle observer and per-player context setup. The page owns lifecycle; the app sets shared audio context once. Native loop gaps remain a real-device risk.

## Asset contract (owned by HPA-168, not this PR)

Four bundled, original, calm files under `assets/audio/`:

| Context | Filename | Intent |
|---|---|---|
| Map, codex and tech tree | `music_map.wav` | spacious, unobtrusive navigation |
| Stage before/between waves and module draft | `music_build.wav` | restrained preparation |
| Running waves, no boss alive | `music_wave.wav` | soft motion that leaves room for SFX |
| Active spawned boss | `music_boss.wav` | distinct pressure without a loudness jump |

HPA-168 creates these files in an **asset-only PR**, using an independent offline music generator and `pubspec.yaml` registration; it must not invoke the existing feedback generator without its private ElevenLabs source takes. Prefer mono, small PCM WAV, ~15–25 seconds per loop and ≤5 MB total; fine-tune after device listening. PCM sample continuity does not guarantee seamless native playback: test repeated loops on physical iOS and Android devices. If the native player inserts an audible gap, record evidence and choose a narrowly scoped playback/encoding remedy; do not preemptively build sample scheduling or streaming infrastructure.

**Integration gate:** merge the asset PR before running HPA-417's end-to-end playback/asset test. HPA-417 may extend the existing `test/feedback/audio_asset_contract_test.dart` with **code-only** music filename, explicit manifest, mono PCM WAV, duration and total-size assertions. Those tests use the established missing-asset `skip:` gate until HPA-168 merges; HPA-168 owns the four files and `pubspec.yaml` registration. HPA-417 must not commit placeholder tracks, bundled binary music, Python generation code, or manifest edits owned by HPA-168. If the asset contract needs adjustment, revise HPA-168 rather than duplicating ownership.

## First verification: short uncommitted device spike

Before implementing the controller, try a disposable local WAV loop on one iOS and one Android device using a private `Bgm()` (without `initialize()`) and the proposed shared audio context. Check repeated loop seams, iOS silent switch, other-app music mixing and Android behavior. Record device/format findings and adjust the HPA-168 file contract *before* writing music playback code if necessary. The spike code and temporary sound file are **not committed** to this PR. When physical devices are unavailable, record the spike as unverified and retain the device gate; do not claim that native looping or audio-focus behavior has been validated.

## Simple runtime design

Use `lib/game/feedback/game_music.dart` for a tiny `MusicTrack` enum (map, build, wave, boss), a **pure track-selection function**, and one `GameMusicController` that accepts only `set(MusicTrack?)`. A fake `MusicPlayer` provides `play/stop/dispose` with no native channels. A production adapter creates its own private `Bgm()` only on the first non-null `set`, and calls `play(filename, volume: 0.18)`, `stop()` and `dispose()` on that instance. One active loop maximum; no mixer, timers, extra event bus, or pause/resume API.

- The pure function is `desiredMusicTrack({required bool prefsLoaded, required bool musicOn, required bool appForeground, GameSnapshot? stage})`. Return **null** before prefs resolve, while Music is OFF, while the app is not `resumed`, for `stage.isPaused`, or for `stage.isEnded`. Otherwise `stage == null` means map (including codex, tech tree and briefing), `stage.phase == build` means build, `wave && stage.bossActive` means boss, and the other wave case means wave. This single selector covers the behavior table without widget-test-only branching.
- `OrionGamePage` takes an optional injected `gameMusicController` like `gameFeedback`. The page creates and disposes only its default production controller; **never dispose injected controllers or `FlameAudio.bgm`**. The default adapter constructs `Bgm()` lazily, so creating a page does not eagerly start native player creation in Flutter widget tests. Audio-player construction, commands and terminal teardown must guard synchronous and asynchronous errors; unhandled constructor/channel futures are unacceptable.
- The page owns one Flutter `AppLifecycleListener` (dispose it on unmount), holds `appForeground` derived from `AppLifecycleState.resumed`, and re-evaluates the selector on lifecycle changes. `inactive`, `hidden`, `paused` and `detached` resolve to silence. **Do not call `Bgm.initialize()`** or rely on `Bgm`'s built-in observer: it can resume outside the serialized controller and has unawaited native channel calls. The single page-owned lifecycle listener is the only playback lifecycle authority.
- The page passes `_game?.snapshot` to the pure function; `_game == null` covers map, codex, tech tree and stage briefing. Subscribe once to the current game's `stateNotifier` and unsubscribe before replacing/dropping that game. Synchronize on the initial preference load, successful preference save, stage creation, the **two `_game = null` paths** (return to map and campaign reset), active game snapshot updates (including restart), lifecycle changes and teardown. No additional sync on codex/tech-tree open/close or in widget `build()`. No stale game listener after navigation.
- Extend `GameSnapshot` with `bossActive` (default false for fixtures), passed through the pure `GameSession.snapshot(bossActive: false)` parameter. Inside `OrionDefenseGame._publishSnapshot()`, compute `_activeEnemyComponents.values.any((enemy) => enemy.stats is BossDefinition)`; this is **read-only projection of existing live state**, not another gameplay state owner. Publish just after a real boss is added in `_spawnEnemy`; kill, base reach and restart already remove/clear enemies before their snapshot publishes. Minions do not match `BossDefinition`. The derivation remains correct even if later stages support multiple bosses. No `onBossPresenceChanged` callback, `_bossPresent` page field, or reset/emit bookkeeping.
- Controller commands have **latest desired track wins** semantics. On a change, stop the previous track before starting the new one; equal desired track is a no-op. A short serialized future chain, following the page's existing write-queue idiom, rechecks the latest intention after each awaited native call so late play cannot survive an OFF, background, stage exit or disposal. A null desired track uses **stop**, not pause; returning from pause/background restarts the short ambience from the beginning. No suspension state, position preservation, or foreground-specific resume case.
- Catch/log errors on playback, global context setup, and disposal without affecting gameplay. Terminal disposal invalidates pending desired work and prevents late starts. The fixed quiet gain is tuned only from real-device listening.

## Preferences and sound session

Add `musicEnabled = true` to `FeedbackPreferences` (`copyWith`, equality, hash, store encoding). An existing valid `orion.feedback` record with `soundEffects` and `haptics` but no `music` must decode to **its existing values plus Music ON**, not reset the whole record. Wrong-typed `music` alone also falls back to Music ON. Corrupt overall records retain today's defaults/failure behavior; this is pre-release, so no versioned migration.

The current page's `_feedbackPreferencesLoaded` gate applies to music too: no startup sound before persisted preferences load. Commit Music switch only on Done *and successful save*, just like other toggles; keep the prior effective value if persistence fails and show the existing error breadcrumb. Toggling Music must not touch Sound Effects or Haptics, and vice versa. A volume slider is deferred (no product requirement yet); use a fixed intentionally quiet gain.

Configure the **shared process-wide audio session once in app startup, awaiting completion before constructing `PlatformGameFeedback` or any other audio player**. Use `AudioPlayer.global.setAudioContext(AudioContext(iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient), android: AudioContextAndroid(usageType: AndroidUsageType.game, audioFocus: AndroidAudioFocus.none)))`; verify exact syntax against the pinned audioplayers dependency when coding. Pinned `flame_audio` 2.12.2 applies its own context in `FlameAudio.createPool` and `FlameAudio.play`, so both existing SFX call sites must receive this same value to preserve the intended platform settings. `AudioContextIOS.ambient` respects the iOS silent switch, and the shared session affects **existing SFX too**: this is an explicit, player-visible behavior correction. With Android `audioFocus: none`, neither music nor SFX claim exclusive focus or pause another app, but they also do **not** receive an Android audio-focus-loss callback: handle app background through the page listener and verify calls/interruptions on device. Do **not** use `AudioContextConfig(respectSilence: true)`: its inferred Android focus/usage can conflict with this behavior. Keep the pool/player arguments identical to the global value; do not add background audio services. App bootstrap should catch/log a context setup failure, which must not prevent gameplay startup; device acceptance still requires the intended mix/silent behavior.

## Explicit behavior table

| Situation | Desired music |
|---|---|
| Initial load, before preferences resolve | silent |
| Loaded map, codex, tech tree or stage briefing | map |
| Deployed stage, build phase, between waves, module selection | build |
| Wave running, no spawned boss | wave |
| One or more actual spawned bosses alive | boss |
| Boss defeated/leaked while wave continues | wave |
| Game paused in any stage phase | stop loop; restart from beginning on unpause |
| App inactive/hidden/paused/detached | stop loop; do not play in background |
| Foreground return | start desired loop from beginning only if Music ON and in-game not paused |
| Victory / defeat / mission report | stop; SFX stinger remains independent |
| Back to map | map |
| Restart/replay stage | build |
| Music OFF | silent regardless of SFX setting |

## Tests and acceptance

1. Preference/store: defaults, old two-field JSON, wrong-typed `music`, three-field round trip, equality and `copyWith`; Sound Effects/Haptics retain their values. Settings cancel or failed save does not change effective music.
2. Pure selector: table-driven tests for every row above, including no stage (map), build, wave, active boss, leaked/killed last boss, result, pause, foreground gate, Music OFF, and preferences not yet resolved. `GameSnapshot.bossActive` defaults false for old fixtures; the game projects from actual live enemies, so multiple bosses/minions and cleanup cannot leave a stale flag.
3. Controller with fake player: no-op repeated set, build→wave→boss→wave, `set(null)` on pause/background/result, restart at beginning, rapid OFF/new-track races, native failures, one player at a time, and idempotent terminal dispose. No separate pause/resume behavior.
4. Page tests: injected controller follows the existing `gameFeedback` ownership seam; attach and detach exactly one active `stateNotifier` listener across navigation and reset. Test lifecycle `resumed` vs `inactive/hidden/paused`, delayed preferences, independent toggles and save failure. **One** default-production smoke test under `test/flutter_test_config.dart`'s throwing audio channels must build, pump and unmount without uncaught failures; do not mount/remount simply to test Flame's internal singleton.
5. Asset contract: extend existing `audio_asset_contract_test.dart` in HPA-417 with `MusicTrack.filename` references, four explicit `pubspec.yaml` registrations, mono PCM WAV metadata, ~15–25 second durations and combined size ≤5 MB, gated by the established missing-asset `skip:` until HPA-168 merges.
6. Devices/regression: early uncommitted loop/context spike, then real music asset listening for native loop gaps, iOS silent switch and external audio mixing (SFX as well), Android calls/interruptions and other-app audio, loud 3× combat vs music balance, lifecycle stop/restart, `dart format`, `flutter analyze`, and `flutter test`.

## Deliberately rejected

- Generalized event/mixer platform, playlists, crossfades, stem or stage-specific adaptive music.
- Duplicating boss state or music state as mutable authority in the page/`GameSession`; the single `bossActive` snapshot value is derived from already-authoritative live enemies.
- Extra `Bgm` lifecycle observer, controller pause/resume position handling, or new persistent volume/options schema beyond one Music boolean.
- Binary music creation or copyrighted stock integration in HPA-417.
- Backward-compatibility scaffolding beyond simply defaulting a missing settings field, which is required by this ticket.
