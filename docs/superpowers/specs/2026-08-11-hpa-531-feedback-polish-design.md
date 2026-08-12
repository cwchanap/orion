# HPA-531 Lightweight Feedback Polish Design Specification

## Decision

Ship one deliberately small sensory-polish pass with:

- **Sound Effects**: one persisted on/off preference.
- **Haptics**: one persisted on/off preference where supported.
- **Reduced Motion**: follow the operating-system accessibility preference directly; do not persist a third setting.
- **Feedback hooks**: invoke a thin `GameFeedback` service only from existing authoritative game actions/results.
- **Audio**: use `flame_audio` for four short project-owned one-shot assets.
- **Screen shake**: omit it.

Do not add an event bus, semantic-event registry, playback queue, scheduler, priority arbitration, rate limiter, lifecycle replay state, generalized settings framework, or campaign-save schema change.

## Why this is the next task

HPA-526 is the higher-priority open M2 catalog-expansion issue, but its own entry gate is not fully satisfied yet. HPA-527 has two recorded human playtests; HPA-528 is merged, but its first-clear → save → Replay human product check remains pending. HPA-531 is blocked only by HPA-527, so this polish slice can proceed without prematurely expanding the module catalog.

## Product goal

Make a few important moments feel clearer and more rewarding without changing gameplay authority or slowing the player down.

```text
existing authoritative action/result
→ optional GameFeedback call
→ check current Sound/Haptics preferences
→ fire one short best-effort platform cue
```

If feedback fails, gameplay continues normally.

## Feedback catalog

Keep the catalog to the six HPA-531 product moments.

| Product moment | Sound | Haptic | Authoritative hook |
| --- | --- | --- | --- |
| Tower placed / upgraded / specialized | `confirm.wav` | selection click | successful `OrionDefenseGame` tower mutation |
| Salvage Module selected | `confirm.wav` | selection click | successful `selectRunModule(...)` |
| Non-terminal wave cleared | `clear.wav` | light impact | `_finishWaveIfComplete()` after `finishActiveWave()` |
| Boss defeated | none | medium impact | `_handleEnemyKilled(...)` when stats are `BossDefinition` |
| Mission victory | `victory.wav` | heavy impact | terminal branch of `_finishWaveIfComplete()` |
| Base defeated | `defeat.wav` | heavy impact | explicit `wave → lost` transition in `_handleEnemyReachedBase(...)` |

### Boss defeat stays haptic-only

A separate boss sound is not needed for this first slice. The boss already has a distinct death visual, and the final boss can be followed by mission victory in the same update. Deferring a boss sound avoids adding another asset and avoids creating pressure for sound suppression/priority logic. If later playtesting says the boss moment is unclear, add one sound then.

A final-boss kill may legitimately produce:

```text
bossDefeated()
missionVictory()
```

in that order in the same frame. The implementation test must verify this order explicitly.

### Terminal-wave precedence

A winning final wave fires **mission victory**, not generic wave clear. This prevents two wave-result sounds from stacking.

## Feedback service boundary

Keep the explicit six-method boundary:

```dart
abstract interface class GameFeedback {
  void towerConfirmed();
  void waveCleared();
  void moduleSelected();
  void bossDefeated();
  void missionVictory();
  void baseDefeated();
}
```

Production uses `PlatformGameFeedback`. Tests use `NoOpGameFeedback` or a recording fake.

Do **not** replace this with a production `GameCue`/`GameEvent` enum. The current feature has six fixed semantic methods and no routing requirement. Ordering can be tested by having the recording fake append a test-only token from each method. That verifies the product contract without introducing a generalized cue vocabulary into production code.

Add a const no-op implementation:

```dart
final class NoOpGameFeedback implements GameFeedback {
  const NoOpGameFeedback();

  @override
  void towerConfirmed() {}
  @override
  void waveCleared() {}
  @override
  void moduleSelected() {}
  @override
  void bossDefeated() {}
  @override
  void missionVictory() {}
  @override
  void baseDefeated() {}
}
```

`OrionDefenseGame` should call the field `gameFeedback`, not `feedback`, because `_publishSnapshot({String? feedback})` and `GameSnapshot.feedback` already use `feedback` for player-facing message text.

`OrionDefenseGame` may default its own low-level `gameFeedback` input to `const NoOpGameFeedback()`. `OrionGamePage` still owns the production platform service and passes it into each real game.

## Platform implementation

`PlatformGameFeedback` receives live predicates:

```dart
PlatformGameFeedback({
  required bool Function() soundEffectsEnabled,
  required bool Function() hapticsEnabled,
});
```

The predicates read the page-owned effective preference value, so changing Settings affects the next cue without a controller, stream, or service recreation.

Each semantic method delegates to a tiny best-effort emitter:

- Sound enabled → fire one `FlameAudio.play(...)` call without awaiting it.
- Haptics enabled → fire the corresponding Flutter `HapticFeedback` call without awaiting it.
- Catch audio/haptic failures inside the async helper.
- Never mutate game state.

There is no playback queue, lifecycle observer, or replay state. Rebuild, resize, and foregrounding therefore have no trigger path from which to replay old cues.

## Audio dependency decision and risk

`flame_audio 2.12.2` currently requires `flame ^1.38.0`, `audioplayers ^6.2.0`, Dart 3.12+, and Flutter 3.44+. Orion currently declares Flame `^1.37.0`, so adopting `flame_audio 2.12.2` deliberately upgrades Orion's direct Flame constraint to:

```yaml
flame: ^1.38.0
flame_audio: ^2.12.2
```

This is not allowed to happen silently through dependency resolution. The implementation task that adds audio must run the **full Flutter test suite** after `pub get`, not just analysis, before any feedback call sites are wired.

The transitive native audio chain is the main implementation risk in HPA-531. Android/iOS/web build workflows remain part of normal CI validation.

## Audio assets and warm-up

Ship exactly four project-owned generated one-shots:

```text
assets/audio/confirm.wav
assets/audio/clear.wav
assets/audio/victory.wav
assets/audio/defeat.wav
assets/audio/README.md
```

Generate them deterministically with a small standard-library script committed as:

```text
scripts/generate_feedback_audio.py
```

The script writes 16-bit mono PCM WAV files and uses short synthesized tones/envelopes. `assets/audio/README.md` records that these files are generated by that script and are project-owned. This gives the implementation an executable source path and avoids external license/download work.

Register the four `.wav` files **individually** in `pubspec.yaml`; do not register the whole directory, so `README.md` is not bundled into the app.

Do not block app startup on audio loading. `PlatformGameFeedback` should start a best-effort, unawaited `FlameAudio.audioCache.loadAll([...])` warm-up when the production service is constructed, with errors swallowed. Flame's audio cache exists specifically to avoid first-play latency. This is a cache warm-up, not a readiness gate: the player can interact immediately even if warming is still in progress.

## Preferences

Use a proper value type because the Settings flow skips persistence when a returned draft equals the current effective value.

```dart
class FeedbackPreferences {
  const FeedbackPreferences({
    this.soundEffectsEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool soundEffectsEnabled;
  final bool hapticsEnabled;

  FeedbackPreferences copyWith({
    bool? soundEffectsEnabled,
    bool? hapticsEnabled,
  });

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}
```

### One atomic persistence key

Do not split the two booleans across two `SharedPreferences` writes. Campaign persistence already documents why logically related persisted state should not tear across keys.

Use one independent key:

```text
orion.feedback
```

Store one tiny JSON object:

```json
{"soundEffects":true,"haptics":true}
```

No version field or migration logic is needed. Missing, malformed, wrong-typed, or otherwise unparseable data returns `const FeedbackPreferences()`.

This still survives campaign reset because campaign reset removes only the campaign key. `CampaignSave` remains untouched.

```dart
abstract interface class FeedbackPreferencesStore {
  Future<FeedbackPreferences> load();
  Future<void> save(FeedbackPreferences preferences);
}
```

Production uses `SharedPreferencesFeedbackPreferencesStore`; tests use a tiny in-memory store. A failed `setString` throws `StateError` and leaves the page's effective preferences unchanged.

## Loading and ownership

`OrionGamePage` owns shell-level preference state.

Add optional seams:

```dart
FeedbackPreferencesStore? feedbackPreferencesStore,
GameFeedback? gameFeedback,
```

Production behavior:

1. obtain `SharedPreferences` once when a default campaign and/or feedback store is needed;
2. load campaign state with existing semantics;
3. load feedback preferences independently; load failure falls back to defaults without erasing campaign progress;
4. create one `PlatformGameFeedback` when `widget.gameFeedback == null`;
5. pass that service to every real `OrionDefenseGame` as `gameFeedback:`.

### Widget-test isolation

`test/widget_test.dart` has many direct `OrionGamePage` constructions and several drive real combat. They must not instantiate the native audio plugin chain accidentally.

Add one test helper such as `_pumpGamePage(...)` that defaults `gameFeedback` to `const NoOpGameFeedback()`, then mechanically migrate the page constructions in that file to use the helper. Tests that specifically need a recording fake pass it explicitly.

This is test isolation, not a production DI layer.

## Settings UI

Add one gear button beside Codex / Tech Tree / Reset Campaign on `WorldMapView`.

Because this is a fourth 48px icon in a narrow header, keep the title to one line with ellipsis:

```dart
Text(
  'Orion Sector Map',
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  ...
)
```

Open a compact `FeedbackSettingsSheet` containing:

- `Sound Effects` switch;
- `Haptics` switch;
- `Reduced Motion` informational row: `Follows system • On` / `Off`;
- `Done` action.

The sheet edits a local draft and returns it on Done. `OrionGamePage` persists once and updates the effective value only after save succeeds.

Because `FeedbackPreferences` has value equality:

```dart
if (updated == null || updated == _feedbackPreferences) return;
```

also suppresses a toggled-then-restored draft write.

If save fails, keep the prior preferences and show `Could not save feedback settings.` on the map.

Put sheet-only rendering/interaction tests in:

```text
test/widget/feedback_settings_sheet_test.dart
```

Keep only page integration tests (load/save, reset isolation, actual modal sheet, Reduced Motion) in the already-large `test/widget_test.dart`.

## Reduced Motion

Use the system bridge only:

```dart
MediaQuery.disableAnimationsOf(context)
```

No persisted key is needed.

Add one helper as part of the Settings task:

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null;
```

Use it for both:

- existing stage briefing bottom sheet;
- new feedback Settings bottom sheet.

The Salvage Module draft and Mission Report are already immediate/static and need no changes.

### 360×640 test detail

Do not rely on `MediaQueryData(size: ...)` above `MaterialApp` to set the test surface. Flutter's `MediaQueryData.fromView` sources geometry from the test view while inheriting accessibility fields such as `disableAnimations` from platform data.

For the Reduced Motion regression:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
```

and use the ancestor/system test value only for `disableAnimations`.

## Authoritative trigger wiring

Feedback remains in `OrionDefenseGame`, not `GameSession`, rules, widgets, or snapshot observation.

### Tower confirmation

Call `gameFeedback.towerConfirmed()` only after successful place / upgrade / specialization. Invalid attempts, sell, targeting changes, and simple selection are silent.

### Module selection

Call `gameFeedback.moduleSelected()` only after `_session.selectRunModule(...)` returns true. Stale/repeated selections remain silent.

### Boss defeat

After an accepted kill is removed/rewarded, call `gameFeedback.bossDefeated()` when `enemy.stats is BossDefinition`.

### Wave clear and victory

After `_session.finishActiveWave()`:

```text
if won → missionVictory()
else     waveCleared()
```

Keep existing snapshot publication and `onStageWon` ordering intact.

### Base defeat is an explicit phase edge

This is a small production hardening bundled with the polish slice and must be stated as such in its implementation commit.

```dart
final phaseBeforeDamage = _session.phase;
_session.damageBase(enemy.stats.baseDamage);
final didLose =
    phaseBeforeDamage == GamePhase.wave &&
    _session.phase == GamePhase.lost;

if (didLose) {
  gameFeedback.baseDefeated();
  // existing defeat cleanup
}
```

The cue's one-shot semantics no longer depend indirectly on `_tickEnemyLogic` breaking after phase change.

## Testing strategy

### Preference/value tests

Cover:

- default value equality/hash behavior;
- `copyWith` change + restore-to-original equality;
- missing key defaults both channels on;
- single-key round trips for all toggle combinations;
- malformed JSON, wrong types, or absent fields fall back to defaults;
- failed save leaves effective page state unchanged;
- campaign reset does not alter `orion.feedback`.

### Platform dependency gate

The task that adds `flame_audio` must run:

```bash
flutter pub get
flutter analyze
flutter test
```

before feedback hooks are added. This makes the Flame 1.38/native-plugin upgrade an explicit test gate rather than discovering incompatibility in the final task.

### Game feedback trigger tests

Use a recording fake whose six methods append to an ordered **test-only** sequence, for example strings or a private `_RecordedCue` enum.

Verify:

- successful tower mutations append tower confirmation; rejected ones append nothing;
- valid module selection appends once; stale repeat appends nothing;
- non-terminal clear appends wave clear;
- terminal clear appends victory, not wave clear;
- boss kill appends boss defeat once;
- `_twoEnemyDefeatStage` produces exactly one base-defeat call on the `wave → lost` edge;
- one one-wave final-boss fixture produces exactly `[bossDefeated, missionVictory]` in that order and no wave clear;
- follow-up `update(0)`, resize, lifecycle processing, and snapshot publication do not append anything.

No native audio/haptic behavior is tested here.

### Widget tests

- `test/widget/feedback_settings_sheet_test.dart`: two switches, local draft, Done, system status copy, compact layout.
- `test/widget_test.dart`: production page integration with injected no-op/recording service, preference persistence, campaign-reset isolation, actual modal sheets, and Reduced Motion at a real 360×640 test view.

### Native smoke

On one iOS/Android simulator/device:

1. confirm tower/module/wave/terminal cues;
2. exercise Sound-only and Haptics-only settings;
3. verify first confirmation is not noticeably late after cache warm-up;
4. verify no old cue replays after background/foreground;
5. verify stage/settings sheets stop sliding with OS Reduce Motion;
6. inspect the 360px world-map header with four icons.

Record observations in the implementation PR/Linear comment. Do not build telemetry or an audio/haptic test harness.

## Risks

### Flame + native audio dependency upgrade

Adding `flame_audio 2.12.2` requires the direct Flame floor to move from `^1.37.0` to `^1.38.0` and introduces the `audioplayers` native plugin family. Mitigation: isolate this in the audio task and require full `flutter test` before cue wiring, then rely on existing platform CI and native smoke.

### Plugin activity in widget tests

Real plugin work under `flutter_test` can leak asynchronous player state/timers even if an immediate call is wrapped in try/catch. Mitigation: `NoOpGameFeedback` plus a common widget-test page helper; platform behavior is validated by native smoke instead.

### First-play latency

Uncached one-shots can be late on first use. Mitigation: best-effort unawaited cache warm-up; no readiness gate.

## Deliberate non-goals

- No production `GameCue`/`GameEvent` enum.
- No event bus, queue, scheduler, priority, deduplication, or rate limiter.
- No per-hit, projectile, tower-shot, enemy-spawn, or automatic-combat cues.
- No screen shake.
- No music, adaptive audio, or voice acting.
- No generalized accessibility/settings framework.
- No persisted Reduced Motion setting.
- No campaign-save schema change.
- No module/blueprint/Mission Report/combat-rule redesign.

## Acceptance mapping

- **Important moments feel clearer:** six authoritative moments have bounded cues.
- **Gameplay authority unchanged:** feedback remains outside `GameSession` and combat math.
- **Sound/Haptics independently optional:** one atomic preference payload controls two independent channels.
- **Reduced Motion:** system preference directly disables the two moving shell sheets.
- **One-shot cues do not replay:** calls occur only at success/result transitions; loss is edge-detected; no observer exists.
- **Thin implementation:** one tiny preference store, one tiny feedback service + no-op, one Settings sheet, four generated assets, direct call sites, and focused tests.
