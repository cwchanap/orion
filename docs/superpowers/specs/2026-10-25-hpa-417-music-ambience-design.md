# HPA-417 — Music and Ambience Design

**Linear:** [HPA-417](https://linear.app/cwchanap/issue/HPA-417/orion-add-music-and-ambience-with-a-separate-music-setting)  
**Separate music asset task:** [HPA-168](https://linear.app/cwchanap/issue/HPA-168/orion-produce-original-ambient-music-loops-for-hpa-417)  
**Baseline:** `main` at `54ddbe82259b59b646ba24167937923b68449b99` (2026-10-25 local)  
**Status:** proposed; this PR contains design and implementation plan, not runtime code or binary assets.

## Player outcome

Orion has quiet, unobtrusive ambience on the world map and a distinct loop for build, active waves and boss encounters. Music is separate from combat SFX and haptics. A player can switch it off without affecting other channels; interruption, pause and navigation never leave the wrong loop playing. This is **presentation only**, not a rule, campaign, timing or balance change.

Prefer the smallest feature that makes the existing loop feel alive. Four tracks, one Music switch, one player, no adaptive mixer, stems, crossfade scheduler, per-stage soundtrack, volume mixer, audio event bus, state persistence beyond one bool, or new gameplay snapshot/state authority.

## Verified reuse survey

- `lib/game/feedback/game_feedback.dart`: `PlatformGameFeedback` handles one-shot SFX and 13 pooled combat cues; page owns/disposes it. Leave its limiter, cue mapping and haptic semantics untouched.
- `lib/game/feedback/feedback_preferences.dart`: `FeedbackPreferences` and `SharedPreferencesFeedbackPreferencesStore` persist `orion.feedback` with `soundEffects` and `haptics`; add one field and retain both old values on read.
- `lib/game/ui/feedback_settings_sheet.dart`: modal edits a local preferences draft and returns it on Done; add Music switch using the same interaction pattern (cancelling dismisses all edits).
- `lib/game/ui/orion_game_page.dart`: one page survives map/stage transitions, loads preferences independently, owns feedback cleanup, creates each `OrionDefenseGame` in `_startStage`, returns in `_returnToMap` and `_confirmResetCampaign`, and exposes GameSnapshot via `game.stateNotifier`.
- `lib/game/models/game_models.dart`: `GameSnapshot.phase`, `isPaused` and `isEnded` already distinguish build, wave, won, lost and in-game pause; don't invent another gameplay mode.
- `lib/game/orion_defense_game.dart`: boss spawn is detected via `BossDefinition` inside `_spawnEnemy`; boss exit is known to `_handleEnemyKilled` and `_handleEnemyReachedBase`. The UI snapshot intentionally has no boss-alive field.
- `flame_audio: ^2.12.2` already provides `Bgm` with `initialize/play/stop/pause/resume/dispose` and a built-in Flutter lifecycle observer. **Create a page-owned `Bgm()` instance** using Flame's existing cache, rather than disposing/reinitializing the static-final `FlameAudio.bgm` singleton: the singleton's disposed `AudioPlayer` cannot safely be revived on page remount. Reuse the library, not a new audio stack. Native loop gaps remain a real-device risk.

## Asset contract (owned by HPA-168, not this PR)

Four bundled, original, calm files under `assets/audio/`:

| Context | Filename | Intent |
|---|---|---|
| Map, codex and tech tree | `music_map.wav` | spacious, unobtrusive navigation |
| Stage before/between waves and module draft | `music_build.wav` | restrained preparation |
| Running waves, no boss alive | `music_wave.wav` | soft motion that leaves room for SFX |
| Active spawned boss | `music_boss.wav` | distinct pressure without a loudness jump |

HPA-168 creates these files in an **asset-only PR**, using an independent offline music generator and `pubspec.yaml` registration; it must not invoke the existing feedback generator without its private ElevenLabs source takes. Prefer mono, small PCM WAV, ~15–25 seconds per loop and ≤5 MB total; fine-tune after device listening. PCM sample continuity does not guarantee seamless native playback: test repeated loops on physical iOS and Android devices. If the native player inserts an audible gap, record evidence and choose a narrowly scoped playback/encoding remedy; do not preemptively build sample scheduling or streaming infrastructure.

**Integration gate:** merge the asset PR before running HPA-417's end-to-end playback/asset test. HPA-417 must not commit placeholder tracks, bundled binary music, Python generation code, or manifest edits owned by HPA-168. If the asset contract needs adjustment, revise HPA-168 rather than duplicating ownership.

## Simple runtime design

Add one small `GameMusicController` at `lib/game/feedback/game_music.dart` and a thin `MusicPlayer` test seam. A production wrapper owns one **new `Bgm()` instance** (same Flame BGM implementation/cache, not the process-wide `FlameAudio.bgm` singleton); a fake records operations without platform channels. The controller has exactly one desired track (or none) and suspension state; it compares desired vs current before performing audio I/O. **No parallel active players, queue, timer or catch-up starts.**

- Add an optional `gameMusicController` parameter to `OrionGamePage`, following the existing `gameFeedback` injection pattern. The page creates/owns the production controller and its private `Bgm()` only when no controller was injected; page teardown disposes only page-created music resources. Never dispose an injected controller, and **never call `FlameAudio.bgm.dispose()`**.
- Initialize the page-owned `Bgm()` at most once; its built-in `WidgetsBindingObserver` handles app background/foreground and its `dispose()` removes that observer/player on page teardown. A newly mounted page can construct a fresh `Bgm()` safely. Avoid a second competing observer. On foreground return, keep Music OFF and in-game pause authoritative. **Initialization and teardown must catch/log native channel failures**, including mocked channels that throw in existing widget tests; any async failure must be consumed rather than escaping as an unhandled exception.
- The page selects the *desired* track: `_ShellView.worldMap/codex/techTree` → map; active stage `GamePhase.build` → build; `GamePhase.wave` → wave unless boss-present → boss; won/lost → **none**. The result's existing SFX victory/defeat stinger plays without music underneath. Map music returns when leaving the report.
- Subscribe once to the current game's `stateNotifier` when constructing a stage; unsubscribe before replacing/dropping that game. Listen to phase and `isPaused`; do not invoke the player from `build()` or construct one per widget rebuild. Repeated combat/countdown snapshots with an unchanged music target perform no audio calls.
- Add a **direct optional constructor parameter** `ValueChanged<bool>? onBossPresenceChanged` to `OrionDefenseGame`, matching its `onStageWon`/`onReturnToMap` constructor callbacks; do not add a mutable/settable callback. The page passes a closure capturing the newly created game and ignores notifications unless it is still the active game. Send true only after an actual `BossDefinition` spawn; send false after the real boss is removed (kill or reaches base), on stage restart/cleanup, and when the run ends. This is a small presentation notification, not a second gameplay state owner, event bus, or change to authoritative `GameSession`. Distinguish boss arrivals from summoned minions.
- Switching tracks: stop the prior loop, then play the new file at one low constant music volume (start around 0.18 and tune by device listening); no overlap or crossfade. Same-file/no-op updates do nothing. App transition, paused game or Music OFF: pause/stop as appropriate, keeping only one resume target. On result, stop to leave the stinger audible. On return map, play map loop. On restart, recompute build music.
- Serialize/supersede async native calls so a late `play(map)` from an earlier request cannot override a newer `stop` or `play(boss)`. A short single-future operation chain and final desired-state check is sufficient; **no new scheduler**. Catch/log **initialize, playback, stop, and dispose** failures and keep gameplay functional; guard synchronous exceptions and every returned asynchronous failure. Terminal disposal prevents late starts and safely releases the page-owned player.

## Preferences and sound session

Add `musicEnabled = true` to `FeedbackPreferences` (`copyWith`, equality, hash, store encoding). An existing valid `orion.feedback` record with `soundEffects` and `haptics` but no `music` must decode to **its existing values plus Music ON**, not reset the whole record. Wrong-typed `music` alone also falls back to Music ON. Corrupt overall records retain today's defaults/failure behavior; this is pre-release, so no versioned migration.

The current page's `_feedbackPreferencesLoaded` gate applies to music too: no startup sound before persisted preferences load. Commit Music switch only on Done *and successful save*, just like other toggles; keep the prior effective value if persistence fails and show the existing error breadcrumb. Toggling Music must not touch Sound Effects or Haptics, and vice versa. A volume slider is deferred (no product requirement yet); use a fixed intentionally quiet gain.

**Pass an explicit iOS `ambient` audio context into `Bgm.initialize()`**: the library default is not an ambient/silent-switch-respecting configuration. Verify that background-music initialization does not override or get overridden by existing SFX pools: configure the shared effective session consistently where needed, without creating a global audio infrastructure. Respect Android focus/interruptions using the current audioplayers/Flame integration, with no foreground service or Android background playback. A muted app should not disturb other apps. Device acceptance owns any OS-specific correction.

## Explicit behavior table

| Situation | Desired music |
|---|---|
| Initial load, before preferences resolve | silent |
| Loaded map, codex, tech tree or stage briefing | map |
| Deployed stage, build phase, between waves, module selection | build |
| Wave running, no spawned boss | wave |
| Boss spawned/alive | boss |
| Boss defeated/leaked while wave continues | wave |
| Game paused in any stage phase | pause current loop |
| App inactive/background | pause; do not play in background |
| Foreground return | resume only if Music ON and in-game not paused |
| Victory / defeat / mission report | stop; SFX stinger remains independent |
| Back to map | map |
| Restart/replay stage | build |
| Music OFF | silent regardless of SFX setting |

## Tests and acceptance

1. Store/model: defaults, old two-field JSON, a malformed Music field, full three-field round trip, equality and `copyWith`; verify Sound Effects and Haptics retain their values.
2. Pure fake music player: initial map, stage build→wave→boss→wave, wave→build/intermission, victory/defeat silence, replay/map, unchanged snapshot idempotence, startup preference gate, independent toggles, in-game pause/resume, foreground/background and rapid async transitions. No stale playing sound after disposal.
3. Page/integration: inject a fake `gameMusicController` through the page constructor for music widget tests; default production adapter tolerates test-runner audio-channel exceptions on initialization **and teardown**. Verify only one listener follows the active game; moving between stages removes prior listener; post-return old game callbacks cannot restart music; settings cancel/save failure preserves old effective music; existing SFX feedback injection works. Unmount and remount the page to prove the private `Bgm()` is disposable/recreatable without touching the static singleton.
4. Audio/device: four asset paths and bundle size (once HPA-168 merges); no click or audible native gap at loop seam; verify silent switch, mixing with external music, interruptions, background/resume, loud 3× combat and SFX independent of music toggle. Music must never slow simulation or delay UI transitions.
5. Regression: `dart format`, `flutter analyze`, `flutter test` including existing combat SFX, feedback settings, mission flow and test-channel defaults.

## Deliberately rejected

- Generalized event/mixer platform, playlists, crossfades, stem or stage-specific adaptive music.
- Adding boss state or music state as mutable authority inside `GameSession`; only the existing true game events drive presentation.
- New persistent volume/options schema beyond one Music boolean.
- Binary music creation or copyrighted stock integration in HPA-417.
- Backward-compatibility scaffolding beyond simply defaulting a missing settings field, which is required by this ticket.
