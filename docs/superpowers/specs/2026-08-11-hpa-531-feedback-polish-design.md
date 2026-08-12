# HPA-531 Lightweight Feedback Polish Design Specification

## Decision

HPA-531 is Orion's next actionable M2 slice.

Ship one deliberately small sensory-polish pass with:

- **Sound Effects**: one persisted on/off preference.
- **Haptics**: one persisted on/off preference where the platform supports it.
- **Reduced Motion**: follow the operating-system accessibility preference directly; do not add a third persisted setting.
- **Feedback hooks**: invoke a thin `GameFeedback` service only from existing authoritative game actions/results.
- **Audio**: use `flame_audio` for four short project-owned one-shot assets.
- **Screen shake**: omit it.

Do not add an event bus, semantic-event registry, scheduler, channel arbitration, generalized platform adapter layer, versioned settings payload, or feedback from widget rebuild observation.

## Why this is the next task

HPA-526 is the highest-priority open M2 catalog-expansion issue, but its own entry gate is not fully satisfied yet:

- HPA-527 has two recorded human playtests in merged PR #17.
- HPA-528 is merged, but merged PR #21 still records its first-clear → save → Replay human product check as pending.
- HPA-526 explicitly requires that proof plus concrete catalog-gap notes before expanding the module pool.

HPA-531 is blocked only by HPA-527, which is complete. The HPA-527 human runs reported positive draft comprehension and pacing, so the sensory-polish slice can proceed without pretending HPA-526's broader catalog gate has passed.

## Product goal

Make a few important moments feel clearer and more rewarding without changing gameplay authority or slowing the player down.

The implementation should remain invisible to game rules:

```text
existing authoritative action/result
→ optional GameFeedback call
→ check current Sound/Haptics preferences
→ fire one short best-effort platform cue
```

If feedback fails, gameplay continues normally.

## First feedback catalog

Keep the catalog to the six product moments already named by HPA-531. Reuse sound assets where the distinction can come from haptic strength or the existing visual state.

| Product moment | Sound | Haptic | Authoritative hook |
| --- | --- | --- | --- |
| Tower placed / upgraded / specialized | `confirm.wav` | selection click | successful `OrionDefenseGame` tower mutation |
| Salvage Module selected | `confirm.wav` | selection click | successful `selectRunModule(...)` |
| Non-terminal wave cleared | `clear.wav` | light impact | `_finishWaveIfComplete()` after `finishActiveWave()` |
| Boss defeated | none in first slice | medium impact | `_handleEnemyKilled(...)` when stats are `BossDefinition` |
| Mission victory | `victory.wav` | heavy impact | terminal branch of `_finishWaveIfComplete()` |
| Base defeated | `defeat.wav` | heavy impact | first transition to `GamePhase.lost` in `_handleEnemyReachedBase(...)` |

### Why boss defeat is haptic-only initially

A boss kill can immediately end the final wave and mission. Giving it a separate one-shot sound would overlap with the victory cue in the same frame unless Orion also gained suppression/priority logic. That is exactly the kind of scheduler HPA-531 says not to build.

The existing boss death visual plus a medium haptic is enough for this slice. If a later playtest finds the moment unclear, add a sound then based on evidence.

### Terminal-wave precedence

A winning final wave fires **mission victory**, not the generic wave-clear cue. This prevents two wave-result sounds from stacking.

A boss-defeat haptic may still precede the victory haptic when the final enemy is a boss; both are separate authoritative moments and require no queue or replay mechanism.

## Feedback service boundary

Add a focused integration-layer service under `lib/game/feedback/`:

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

Production uses `PlatformGameFeedback`. Tests can pass a tiny recording fake.

`PlatformGameFeedback` receives two live predicates:

```dart
PlatformGameFeedback({
  required bool Function() soundEffectsEnabled,
  required bool Function() hapticsEnabled,
});
```

The predicates read the current page-owned preference value, so changing settings affects the next cue without a controller, event stream, or service re-creation.

Each method:

1. checks the relevant channel preference;
2. starts the short sound and/or haptic without awaiting it;
3. catches platform/audio errors and drops them;
4. never mutates game state.

There is no playback queue and no lifecycle observer. Because the service is called only at action/result transitions, background/foreground and rebuilds have nothing to replay.

## Audio dependency and assets

Orion already uses Flame. Add the Flame bridge package rather than a second game-audio abstraction:

```yaml
dependencies:
  flame_audio: ^2.12.2
```

The planned app toolchain (Dart 3.12+, Flutter 3.44+) satisfies the current package minimums at the time of this design.

Register the directory once:

```yaml
flutter:
  assets:
    - assets/images/...
    - assets/audio/
```

First asset set:

```text
assets/audio/confirm.wav
assets/audio/clear.wav
assets/audio/victory.wav
assets/audio/defeat.wav
assets/audio/README.md
```

The four WAV files should be short project-owned/self-created one-shots. `README.md` records that provenance and any generation/source notes in a few lines.

Do not pre-load audio on the critical startup path. `PlatformGameFeedback` starts playback fire-and-forget; a missing/unsupported asset is treated as feedback failure, not gameplay failure.

## Preferences

Add a tiny value object and store:

```dart
class FeedbackPreferences {
  const FeedbackPreferences({
    this.soundEffectsEnabled = true,
    this.hapticsEnabled = true,
  });

  final bool soundEffectsEnabled;
  final bool hapticsEnabled;
}

abstract interface class FeedbackPreferencesStore {
  Future<FeedbackPreferences> load();
  Future<void> save(FeedbackPreferences preferences);
}
```

Production storage reuses the already-installed `shared_preferences` package with two independent keys:

```text
orion.feedback.soundEffects
orion.feedback.haptics
```

Missing keys default to `true`.

Do not add:

- a JSON settings blob;
- a version field;
- migration code;
- a generic app-settings repository.

The existing campaign reset removes only `orion.campaign.progress`, so these separate preference keys survive campaign reset naturally.

An `InMemoryFeedbackPreferencesStore` can mirror the existing campaign-store testing pattern.

## Loading and ownership

`OrionGamePage` remains the owner of shell-level settings state.

Extend its constructor with optional test seams:

```dart
FeedbackPreferencesStore? feedbackPreferencesStore,
GameFeedback? gameFeedback,
```

Production behavior:

1. obtain `SharedPreferences` once when a default campaign store and/or feedback store is needed;
2. load campaign state with the existing failure behavior;
3. load feedback preferences independently, falling back to defaults if that load fails;
4. build/use one `PlatformGameFeedback` whose enablement predicates read the current page preferences;
5. pass that service to every newly created `OrionDefenseGame`.

A feedback-settings failure must not erase or replace successfully loaded campaign progress.

## Settings UI

Add one gear button beside Codex / Tech Tree / Reset Campaign on `WorldMapView`.

It opens a small `FeedbackSettingsSheet` containing:

- `Sound Effects` switch;
- `Haptics` switch;
- `Reduced Motion` informational row: `Follows system • On` or `Follows system • Off`;
- `Done` action.

The sheet edits a local `FeedbackPreferences` draft. `Done` returns the final value to `OrionGamePage`, which persists it once and updates the page-owned preference state only after save succeeds.

This avoids a settings controller and avoids half-updated UI if persistence fails.

If save fails, keep the prior effective preferences and surface a short map breadcrumb such as `Could not save feedback settings.`

No settings route, generalized settings page, sliders, volume controls, music controls, or per-cue toggles are part of HPA-531.

## Reduced Motion

Use Flutter's existing system accessibility bridge:

```dart
final reduceMotion = MediaQuery.disableAnimationsOf(context);
```

No persisted Reduced Motion key is needed.

The current Salvage Module draft and Mission Report overlays are already immediate/static; they contain no custom entrance controller or large card movement. Do not add animation to them.

The current stage briefing does use `showModalBottomSheet(...)`. Add one narrow helper:

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null;
```

Use it for:

- the existing stage-briefing bottom sheet;
- the new feedback-settings bottom sheet.

This makes the only relevant shell-level large transition immediate when the operating system requests reduced motion. It adds no animation framework and never delays input or hides state.

## Authoritative trigger wiring

`OrionDefenseGame` is already the Flame integration/orchestration layer between pure `GameSession` rules and rendering. Keep feedback there; do not move it into `rules/` or `GameSession`.

### Tower confirmation

Call `towerConfirmed()` only after a successful:

- `placeTower(...)`;
- `upgradeSelectedTower()`;
- `specializeSelectedTower(...)`.

Invalid attempts and selling are silent in this first slice.

### Module selection

Call `moduleSelected()` only after `_session.selectRunModule(...)` returns true.

Repeated/stale offer submissions already return false, so they cannot replay the cue.

### Boss defeat

In `_handleEnemyKilled(...)`, call `bossDefeated()` when `enemy.stats is BossDefinition` after the kill is accepted.

Do not trigger from an `EnemyComponent` animation or widget observation.

### Wave clear and victory

In `_finishWaveIfComplete()` after `_session.finishActiveWave()`:

```text
if won → missionVictory()
else     waveCleared()
```

Then keep the existing snapshot publication and `onStageWon` callback ordering intact.

### Base defeat

In `_handleEnemyReachedBase(...)`, call `baseDefeated()` only inside the branch where the damage call has transitioned the session to `GamePhase.lost`.

The update loop already stops combat once phase leaves `wave`, so no second defeat cue is generated by later enemies.

## Testing strategy

### Preference store tests

Create focused tests for:

- both missing keys default to enabled;
- disabling Sound does not change Haptics;
- disabling Haptics does not change Sound;
- a save/load round-trip preserves both booleans;
- campaign reset remains scoped to the campaign key in the page integration test.

### Game feedback trigger tests

Use a local `_RecordingGameFeedback implements GameFeedback` in `orion_defense_game_test.dart`.

Verify:

- successful place/upgrade/specialize calls tower confirmation; rejected attempts do not;
- valid module selection calls once; stale/repeated selection does not;
- non-terminal empty-wave clear calls wave-clear once;
- final empty-wave clear calls victory once and does not call wave-clear;
- boss kill calls boss-defeat once;
- base loss calls defeat once;
- subsequent `update(0)`, resize, lifecycle processing, or snapshot publication does not replay prior cues.

These tests verify the important contract without testing native audio or haptic plugins.

### Widget tests

Cover:

- 360×640 world-map smoke with the new gear button;
- settings sheet shows two independent switches and system Reduced Motion status;
- saving settings updates the persisted test store;
- campaign reset leaves feedback preferences unchanged;
- with `MediaQueryData(disableAnimations: true)`, stage briefing becomes visible without waiting for a transition.

### Native smoke

On one iOS Simulator/device or Android emulator/device:

1. launch with Sound/Haptics enabled;
2. place/upgrade a tower and select one module;
3. clear a wave and finish a victory or defeat;
4. disable Sound and confirm haptics remain;
5. enable Sound + disable Haptics and confirm audio remains;
6. toggle the OS Reduce Motion setting and confirm stage/settings sheets no longer slide;
7. background/foreground the app and confirm no past cue replays.

Record the result in the implementation PR/Linear comment. Do not build automated telemetry or a harness for this check.

## Deliberate non-goals

- No `GameEvent` enum or event bus.
- No feedback queue, priority, deduplication, rate limiter, or voice-count scheduler.
- No per-hit, per-projectile, tower-shot, enemy-spawn, or automatic-combat cues.
- No screen shake.
- No music, adaptive audio, or voice acting.
- No generalized accessibility/settings framework.
- No persisted Reduced Motion setting.
- No campaign-save schema change.
- No changes to `GameSession`, module catalog/drafts, blueprint ownership, Mission Report logic, or combat math.

## Acceptance mapping

- **Important moments feel clearer:** six authoritative moments have a small cue catalog.
- **Gameplay authority unchanged:** feedback lives only in the Flame/UI integration layer and never mutates `GameSession`.
- **Sound/Haptics independently optional:** separate booleans and keys gate separate channels.
- **Reduced Motion:** direct system bridge disables shell bottom-sheet movement; existing result/module overlays remain immediate.
- **One-shot cues do not replay:** calls occur only at successful mutations/result transitions; no rebuild/lifecycle observer exists.
- **Thin implementation:** two small feedback files, one small settings sheet, direct call sites, four assets, and no platform architecture.
