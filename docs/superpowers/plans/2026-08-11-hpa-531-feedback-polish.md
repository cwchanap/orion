# HPA-531 Lightweight Feedback Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six bounded one-shot sound/haptic moments plus system Reduced Motion support without changing gameplay authority or introducing a feedback platform.

**Architecture:** `OrionDefenseGame` calls a six-method `GameFeedback` boundary only after existing authoritative mutations/results succeed. `OrionGamePage` owns one atomic two-boolean feedback preference payload and one production `PlatformGameFeedback`; tests inject `NoOpGameFeedback` or a recording fake. Reduced Motion follows `MediaQuery.disableAnimations` and only disables the two shell bottom-sheet transitions that move.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame **1.38+**, `shared_preferences` 2.5.5, `flame_audio` 2.12.2, transitive `audioplayers` 6.2+, `flutter_test`; Python 3 standard library only for deterministic audio-asset generation.

## Global Constraints

- Six moments only: tower confirmation, wave clear, module selection, boss defeat, mission victory, base defeat.
- No per-hit, projectile, shot, spawn, or other high-frequency feedback.
- No production `GameCue` / `GameEvent` enum, event bus, queue, scheduler, priority system, rate limiter, replay state, or dedup framework.
- Boss defeat is haptic-only in this slice because another boss sound is not yet justified.
- Final-wave victory replaces generic wave-clear feedback.
- Sound and haptics remain independently toggleable but persist atomically under one `orion.feedback` key.
- No feedback state enters `CampaignSave`; campaign reset must leave feedback preferences untouched.
- No persisted Reduced Motion toggle; follow the OS setting.
- No screen shake, music, adaptive audio, voice, or volume sliders.
- Feedback failure never blocks or mutates gameplay.
- Audio cache warm-up is best-effort and unawaited; never a readiness gate.
- Existing module-draft and Mission Report overlays remain static/immediate.
- Target 360×640 logical pixels for compact UI checks.
- Final gates: strict format, analyze, focused tests, full `flutter test`, existing CI, and one native simulator/device smoke.

## Risks

### Flame/native audio dependency upgrade

`flame_audio 2.12.2` requires `flame ^1.38.0` and `audioplayers ^6.2.0`. Orion currently declares Flame `^1.37.0`, so Task 2 explicitly moves the direct Flame constraint to `^1.38.0`. This must not be an incidental lockfile change.

**Mitigation:** Task 2 ends with the **full** Flutter test suite before any gameplay cue call sites are wired. Existing platform CI plus the native smoke cover the plugin chain.

### Native plugin activity under `flutter_test`

Try/catch around `FlameAudio.play` cannot guarantee that transitive player registries, streams, or timers never leak beyond a widget-test body.

**Mitigation:** ship `NoOpGameFeedback` with the platform service and make the common `test/widget_test.dart` page helper default to it. Native behavior is tested by smoke, not by widget tests.

### First-play latency

The first uncached sound can lag the first tap.

**Mitigation:** unawaited best-effort `FlameAudio.audioCache.loadAll` when the production service is constructed. No startup or gameplay gate waits for it.

## File Map

### Create

- `lib/game/feedback/feedback_preferences.dart` — value type + one-key SharedPreferences store + in-memory store.
- `lib/game/feedback/game_feedback.dart` — six-method interface, const no-op, best-effort platform implementation.
- `lib/game/ui/feedback_settings_sheet.dart` — compact two-switch sheet and system Reduced Motion status.
- `scripts/generate_feedback_audio.py` — deterministic stdlib WAV generator.
- `assets/audio/confirm.wav`
- `assets/audio/clear.wav`
- `assets/audio/victory.wav`
- `assets/audio/defeat.wav`
- `assets/audio/README.md`
- `test/game/feedback_preferences_test.dart`
- `test/widget/feedback_settings_sheet_test.dart`

### Modify

- `pubspec.yaml` — explicit Flame 1.38 bump, `flame_audio`, four individual audio assets.
- `pubspec.lock` — resolved Flame/audio plugin chain.
- `lib/game/orion_defense_game.dart` — `gameFeedback` input and six authoritative call sites.
- `lib/game/ui/orion_game_page.dart` — preference load/save, platform service, Settings sheet, system motion bridge.
- `lib/game/ui/world_map_view.dart` — Settings button + one-line title guard.
- `test/game/orion_defense_game_test.dart` — ordered recording fake and trigger regressions.
- `test/widget_test.dart` — common no-op test page helper + page integration/reset/motion tests.

### No intended changes

- `lib/game/rules/game_session.dart`
- `lib/game/models/game_models.dart`
- `lib/game/campaign/campaign_progress.dart`
- `lib/game/campaign/campaign_progress_store.dart`
- run-module/blueprint rules
- Mission Report logic
- combat math
- campaign save version/schema

---

## Task 1: Persist feedback preferences atomically outside campaign save

**Files:**
- Create: `lib/game/feedback/feedback_preferences.dart`
- Create: `test/game/feedback_preferences_test.dart`

**Produces:**

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

abstract interface class FeedbackPreferencesStore {
  Future<FeedbackPreferences> load();
  Future<void> save(FeedbackPreferences preferences);
}
```

### Step 1: Write red value and codec/store tests

- [ ] Create `test/game/feedback_preferences_test.dart`.
- [ ] Add value equality and restore coverage:

```dart
test('preferences compare by value', () {
  const a = FeedbackPreferences(
    soundEffectsEnabled: false,
    hapticsEnabled: true,
  );
  const b = FeedbackPreferences(
    soundEffectsEnabled: false,
    hapticsEnabled: true,
  );

  expect(a, b);
  expect(a.hashCode, b.hashCode);
});

test('copyWith can restore a changed draft', () {
  const original = FeedbackPreferences(
    soundEffectsEnabled: false,
    hapticsEnabled: true,
  );
  final changed = original.copyWith(hapticsEnabled: false);
  final restored = changed.copyWith(hapticsEnabled: true);

  expect(changed, isNot(original));
  expect(restored, original);
});
```

- [ ] Add SharedPreferences tests for:
  - missing `orion.feedback` → `const FeedbackPreferences()`;
  - all four boolean combinations round-trip through one key;
  - malformed JSON → defaults;
  - missing/wrong-typed fields → defaults.

Example malformed-data test:

```dart
test('malformed persisted feedback falls back to defaults', () async {
  SharedPreferences.setMockInitialValues({
    SharedPreferencesFeedbackPreferencesStore.key: '{not-json',
  });
  final preferences = await SharedPreferences.getInstance();
  final store = SharedPreferencesFeedbackPreferencesStore(
    preferences: preferences,
  );

  expect(await store.load(), const FeedbackPreferences());
});
```

### Step 2: Verify red

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
```

Expected: compile failure because the preference types do not exist.

### Step 3: Implement the value type and one-key store

- [ ] Create `lib/game/feedback/feedback_preferences.dart` with `dart:convert` and `shared_preferences` imports.
- [ ] Use one key only:

```dart
static const key = 'orion.feedback';
```

- [ ] Implement the value type:

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
  }) {
    return FeedbackPreferences(
      soundEffectsEnabled:
          soundEffectsEnabled ?? this.soundEffectsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackPreferences &&
          soundEffectsEnabled == other.soundEffectsEnabled &&
          hapticsEnabled == other.hapticsEnabled;

  @override
  int get hashCode => Object.hash(
    soundEffectsEnabled,
    hapticsEnabled,
  );
}
```

- [ ] Implement decode with strict two-field validation and default fallback:

```dart
FeedbackPreferences _decode(String? source) {
  if (source == null || source.isEmpty) {
    return const FeedbackPreferences();
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      return const FeedbackPreferences();
    }
    final sound = decoded['soundEffects'];
    final haptics = decoded['haptics'];
    if (sound is! bool || haptics is! bool) {
      return const FeedbackPreferences();
    }
    return FeedbackPreferences(
      soundEffectsEnabled: sound,
      hapticsEnabled: haptics,
    );
  } on FormatException {
    return const FeedbackPreferences();
  } on TypeError {
    return const FeedbackPreferences();
  }
}
```

- [ ] Implement one atomic save call:

```dart
Future<void> save(FeedbackPreferences value) async {
  final persisted = await preferences.setString(
    key,
    jsonEncode({
      'soundEffects': value.soundEffectsEnabled,
      'haptics': value.hapticsEnabled,
    }),
  );
  if (!persisted) {
    throw StateError('Failed to save feedback preferences.');
  }
}
```

No version field, migration path, or generic app-settings store.

- [ ] Add `InMemoryFeedbackPreferencesStore` with a mutable `value` field and async load/save.

### Step 4: Run and commit

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
```

Expected: PASS.

- [ ] Commit:

```bash
git add lib/game/feedback/feedback_preferences.dart \
  test/game/feedback_preferences_test.dart
git commit -m "feat: persist feedback preferences atomically"
```

---

## Task 2: Add the explicit Flame/audio dependency, generated assets, no-op, and platform service

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/game/feedback/game_feedback.dart`
- Create: `scripts/generate_feedback_audio.py`
- Create: `assets/audio/confirm.wav`
- Create: `assets/audio/clear.wav`
- Create: `assets/audio/victory.wav`
- Create: `assets/audio/defeat.wav`
- Create: `assets/audio/README.md`

### Step 1: Make the dependency upgrade explicit

- [ ] Change:

```yaml
flame: ^1.37.0
```

to:

```yaml
flame: ^1.38.0
flame_audio: ^2.12.2
```

Do not add a direct `audioplayers` dependency; it remains transitive through `flame_audio`.

### Step 2: Add an executable asset-generation source

- [ ] Create `scripts/generate_feedback_audio.py` using only Python stdlib:

```python
#!/usr/bin/env python3
from pathlib import Path
import math
import struct
import wave

RATE = 44_100
AMPLITUDE = 0.28
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def envelope(t: float, duration: float) -> float:
    attack = min(1.0, t / 0.008)
    release = min(1.0, max(0.0, duration - t) / 0.025)
    return max(0.0, min(attack, release))


def render(name: str, notes: list[tuple[float, float]]) -> None:
    samples: list[int] = []
    for frequency, duration in notes:
        frame_count = int(RATE * duration)
        for index in range(frame_count):
            t = index / RATE
            value = (
                AMPLITUDE
                * envelope(t, duration)
                * math.sin(2 * math.pi * frequency * t)
            )
            samples.append(int(max(-1.0, min(1.0, value)) * 32767))
        samples.extend([0] * int(RATE * 0.012))

    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", s) for s in samples))


CUES = {
    "confirm.wav": [(660, 0.055), (880, 0.070)],
    "clear.wav": [(523.25, 0.060), (659.25, 0.060), (783.99, 0.090)],
    "victory.wav": [
        (523.25, 0.070),
        (659.25, 0.070),
        (783.99, 0.070),
        (1046.50, 0.140),
    ],
    "defeat.wav": [(329.63, 0.080), (246.94, 0.090), (196.00, 0.150)],
}

for filename, notes in CUES.items():
    render(filename, notes)
```

- [ ] Run:

```bash
python3 scripts/generate_feedback_audio.py
```

- [ ] Add `assets/audio/README.md`:

```markdown
# Orion feedback audio

`confirm.wav`, `clear.wav`, `victory.wav`, and `defeat.wav` are project-owned
original one-shot sound effects generated by `scripts/generate_feedback_audio.py`.
The generator uses only Python's standard library and 16-bit mono PCM synthesis.
```

No external asset pack or license lookup is required.

### Step 3: Register only shipped sound files

- [ ] Add exactly:

```yaml
flutter:
  assets:
    - assets/images/orion_sprite_sheet.png
    - assets/images/orion_tower_variety_sheet.png
    - assets/images/orion_terrain_background.png
    - assets/images/orion_path_tiles.png
    - assets/images/orion_boss_sheet.png
    - assets/audio/confirm.wav
    - assets/audio/clear.wav
    - assets/audio/victory.wav
    - assets/audio/defeat.wav
```

Do not register `assets/audio/` as a directory; `README.md` must not ship as an app asset.

### Step 4: Resolve dependencies and inspect the intended upgrade

- [ ] Run:

```bash
flutter pub get
git diff -- pubspec.yaml pubspec.lock
```

- [ ] Confirm the lockfile resolves Flame 1.38.x-compatible packages and the expected audioplayers plugin family. If unrelated dependency upgrades appear, stop and narrow the resolution before proceeding.

### Step 5: Implement `GameFeedback`, no-op, and platform service

- [ ] Create `lib/game/feedback/game_feedback.dart`:

```dart
import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';

abstract interface class GameFeedback {
  void towerConfirmed();
  void waveCleared();
  void moduleSelected();
  void bossDefeated();
  void missionVictory();
  void baseDefeated();
}

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

final class PlatformGameFeedback implements GameFeedback {
  PlatformGameFeedback({
    required bool Function() soundEffectsEnabled,
    required bool Function() hapticsEnabled,
  }) : _soundEffectsEnabled = soundEffectsEnabled,
       _hapticsEnabled = hapticsEnabled {
    unawaited(_warmAudioCache());
  }

  static const sounds = [
    'confirm.wav',
    'clear.wav',
    'victory.wav',
    'defeat.wav',
  ];

  final bool Function() _soundEffectsEnabled;
  final bool Function() _hapticsEnabled;

  @override
  void towerConfirmed() => _emit(
    sound: 'confirm.wav',
    haptic: HapticFeedback.selectionClick,
  );

  @override
  void moduleSelected() => _emit(
    sound: 'confirm.wav',
    haptic: HapticFeedback.selectionClick,
  );

  @override
  void waveCleared() => _emit(
    sound: 'clear.wav',
    haptic: HapticFeedback.lightImpact,
  );

  @override
  void bossDefeated() => _emit(haptic: HapticFeedback.mediumImpact);

  @override
  void missionVictory() => _emit(
    sound: 'victory.wav',
    haptic: HapticFeedback.heavyImpact,
  );

  @override
  void baseDefeated() => _emit(
    sound: 'defeat.wav',
    haptic: HapticFeedback.heavyImpact,
  );

  void _emit({String? sound, Future<void> Function()? haptic}) {
    if (sound != null && _soundEffectsEnabled()) {
      unawaited(_playSound(sound));
    }
    if (haptic != null && _hapticsEnabled()) {
      unawaited(_playHaptic(haptic));
    }
  }

  Future<void> _warmAudioCache() async {
    try {
      await FlameAudio.audioCache.loadAll(sounds);
    } catch (_) {}
  }

  Future<void> _playSound(String sound) async {
    try {
      await FlameAudio.play(sound);
    } catch (_) {}
  }

  Future<void> _playHaptic(Future<void> Function() haptic) async {
    try {
      await haptic();
    } catch (_) {}
  }
}
```

Do not add `GameCue`, player pools, event routing, retry, or readiness state.

### Step 6: Run the dependency risk gate now

- [ ] Run:

```bash
flutter analyze
flutter test
```

Expected: full existing suite PASS before any `OrionDefenseGame` call site is changed.

If this fails because of Flame 1.38 or the plugin chain, resolve it in Task 2 or reconsider the audio dependency. Do not carry a broken dependency forward into Task 4.

### Step 7: Commit

- [ ] Commit:

```bash
git add pubspec.yaml pubspec.lock \
  lib/game/feedback/game_feedback.dart \
  scripts/generate_feedback_audio.py \
  assets/audio
git commit -m "feat: add lightweight feedback platform support"
```

---

## Task 3: Add page-owned Settings, test isolation, and the production Reduced Motion bridge

**Files:**
- Create: `lib/game/ui/feedback_settings_sheet.dart`
- Create: `test/widget/feedback_settings_sheet_test.dart`
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Produces:**

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context)
Future<void> _openFeedbackSettings()
Future<void> _saveFeedbackPreferences(FeedbackPreferences updated)
```

Both production bottom sheets use `_sheetAnimationStyle(...)` before this task commits.

### Step 1: Write sheet-only widget tests in the focused widget file

- [ ] Create `test/widget/feedback_settings_sheet_test.dart`.
- [ ] Use a 360×640 test view:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
```

- [ ] Pump `FeedbackSettingsSheet` directly inside `MaterialApp` and assert:
  - `Feedback`, `Sound Effects`, `Haptics`, `Reduced Motion`, `Done` exist;
  - switches reflect the provided `FeedbackPreferences` independently;
  - `reduceMotion: true` shows `Follows system • On`;
  - `reduceMotion: false` shows `Follows system • Off`;
  - toggling one switch changes only the local draft;
  - tapping Done pops the final `FeedbackPreferences` value;
  - `tester.takeException()` is null.

Keep page persistence and actual modal transitions out of this file.

### Step 2: Implement the self-contained sheet

- [ ] Create `FeedbackSettingsSheet` as a small `StatefulWidget`:

```dart
class FeedbackSettingsSheet extends StatefulWidget {
  const FeedbackSettingsSheet({
    super.key,
    required this.initialPreferences,
    required this.reduceMotion,
  });

  final FeedbackPreferences initialPreferences;
  final bool reduceMotion;
}
```

- [ ] State owns only `_draft = widget.initialPreferences`.
- [ ] Two `SwitchListTile`s call `_draft.copyWith(...)`.
- [ ] Reduced Motion is informational only.
- [ ] Done returns `_draft`:

```dart
Navigator.of(context).pop(_draft);
```

No persistence or platform feedback calls live in the sheet.

### Step 3: Add the world-map entry point without crowding the header

- [ ] Extend `WorldMapView` with:

```dart
final VoidCallback? onOpenSettings;
```

- [ ] Add `Icons.settings`, tooltip `Settings`, disabled while `_isBusy`.
- [ ] Constrain the title:

```dart
Text(
  'Orion Sector Map',
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: ...,
)
```

This keeps the new fourth icon from forcing a two-line title at the 360px baseline.

### Step 4: Add a common no-op page helper before the native service is reachable from widget tests

- [ ] In `test/widget_test.dart`, import `game_feedback.dart` and add a helper that defaults to no-op:

```dart
Widget testGamePage({
  CampaignProgressStore? progressStore,
  Future<CampaignProgressStore> Function()? progressStoreLoader,
  FeedbackPreferencesStore? feedbackPreferencesStore,
  ValueChanged<OrionDefenseGame>? onGameCreated,
  GameFeedback gameFeedback = const NoOpGameFeedback(),
}) {
  return MaterialApp(
    home: OrionGamePage(
      progressStore: progressStore,
      progressStoreLoader: progressStoreLoader,
      feedbackPreferencesStore: feedbackPreferencesStore,
      onGameCreated: onGameCreated,
      gameFeedback: gameFeedback,
    ),
  );
}
```

- [ ] Mechanically migrate the standard `OrionGamePage(...)` constructions in `test/widget_test.dart` to this helper **before Task 4 introduces cue calls**.
- [ ] Replace tests that currently use `OrionApp()` only as a convenient production shell with `testGamePage(...)` as well.
- [ ] Specialized tests with custom `MediaQuery`/wrappers may construct `OrionGamePage` directly, but must pass `gameFeedback: const NoOpGameFeedback()` explicitly.

Do not add a DI container or test-mode branch to production code.

### Step 5: Load feedback preferences independently

- [ ] Extend `OrionGamePage`:

```dart
final FeedbackPreferencesStore? feedbackPreferencesStore;
final GameFeedback? gameFeedback;
```

- [ ] Add state:

```dart
FeedbackPreferences _feedbackPreferences = const FeedbackPreferences();
FeedbackPreferencesStore? _feedbackPreferencesStore;
late final GameFeedback _gameFeedback;
```

- [ ] In `initState`, create the service once:

```dart
_gameFeedback = widget.gameFeedback ?? PlatformGameFeedback(
  soundEffectsEnabled: () => _feedbackPreferences.soundEffectsEnabled,
  hapticsEnabled: () => _feedbackPreferences.hapticsEnabled,
);
```

- [ ] Refactor loading only enough to obtain one `SharedPreferences` instance when default campaign and/or feedback stores need it.
- [ ] Load campaign and feedback independently. Campaign failure keeps existing behavior; feedback failure falls back to defaults and never erases loaded campaign progress.

### Step 6: Ship `_sheetAnimationStyle` before any new call site depends on it

- [ ] Add:

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null;
```

- [ ] Add it to the existing stage briefing `showModalBottomSheet` now.

### Step 7: Open and save Settings

- [ ] Pass `_openFeedbackSettings` to `WorldMapView`.
- [ ] Implement:

```dart
Future<void> _openFeedbackSettings() async {
  final updated = await showModalBottomSheet<FeedbackPreferences>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (context) => FeedbackSettingsSheet(
      initialPreferences: _feedbackPreferences,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    ),
  );

  if (updated == null || updated == _feedbackPreferences) {
    return;
  }
  await _saveFeedbackPreferences(updated);
}
```

- [ ] `_saveFeedbackPreferences` updates `_feedbackPreferences` only after `store.save(updated)` succeeds. On missing store/failure, keep the prior value and set:

```text
Could not save feedback settings.
```

Because Task 1 implemented value equality, toggled-then-restored drafts do not write.

### Step 8: Add page integration and reset isolation tests

- [ ] In `test/widget_test.dart`, using `testGamePage(...)`:
  - load Sound off / Haptics on and verify Settings reflects it;
  - toggle only Haptics off, Done, assert the in-memory store is both off;
  - reopen Settings and assert effective saved state;
  - inject a failing feedback store and verify effective values remain unchanged plus breadcrumb;
  - perform Reset Campaign with non-default feedback prefs and assert campaign resets while feedback prefs remain unchanged.

Do not modify `CampaignProgressStore.reset()`.

### Step 9: Run and commit

- [ ] Run:

```bash
flutter test test/widget/feedback_settings_sheet_test.dart
flutter test test/widget_test.dart
```

Expected: PASS with no native audio service instantiated by ordinary widget tests.

- [ ] Commit:

```bash
git add lib/game/ui/feedback_settings_sheet.dart \
  lib/game/ui/world_map_view.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget/feedback_settings_sheet_test.dart \
  test/widget_test.dart
git commit -m "feat: add feedback settings and motion bridge"
```

---

## Task 4: Wire ordered one-shot feedback to authoritative game transitions

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/game/orion_defense_game_test.dart`

### Step 1: Add an ordered recording fake without changing the production interface

- [ ] Add a private test-only token enum:

```dart
enum _RecordedFeedbackCall {
  towerConfirmed,
  waveCleared,
  moduleSelected,
  bossDefeated,
  missionVictory,
  baseDefeated,
}

final class _RecordingGameFeedback implements GameFeedback {
  final calls = <_RecordedFeedbackCall>[];

  @override
  void towerConfirmed() =>
      calls.add(_RecordedFeedbackCall.towerConfirmed);
  @override
  void waveCleared() => calls.add(_RecordedFeedbackCall.waveCleared);
  @override
  void moduleSelected() =>
      calls.add(_RecordedFeedbackCall.moduleSelected);
  @override
  void bossDefeated() => calls.add(_RecordedFeedbackCall.bossDefeated);
  @override
  void missionVictory() =>
      calls.add(_RecordedFeedbackCall.missionVictory);
  @override
  void baseDefeated() => calls.add(_RecordedFeedbackCall.baseDefeated);
}
```

This verifies order while keeping production free of a generalized `GameCue` enum.

### Step 2: Add a non-null `gameFeedback` input to `OrionDefenseGame`

- [ ] Add:

```dart
OrionDefenseGame({
  ...,
  this.gameFeedback = const NoOpGameFeedback(),
});

final GameFeedback gameFeedback;
```

Do not name this field `feedback`; that name already means player-facing snapshot text in `_publishSnapshot({String? feedback})`.

Do not add feedback to `GameSession`.

### Step 3: Wire tower confirmation only after successful mutations

- [ ] Add tests around existing fixtures:

```text
successful place       → [towerConfirmed]
successful upgrade     → append towerConfirmed
successful specialize  → append towerConfirmed
rejected/no-selection  → append nothing
```

- [ ] Call `gameFeedback.towerConfirmed()` only after the matching `GameSession` method succeeds.

Sell, targeting changes, taps, and invalid attempts remain silent.

### Step 4: Wire module selection once

- [ ] Extend the existing module-selection fixture with the recording fake.
- [ ] Successful selection appends `moduleSelected` once.
- [ ] Repeating the stale selection appends nothing.
- [ ] Call only after `_session.selectRunModule(...)` returns true.

### Step 5: Wire non-terminal wave clear vs terminal victory

- [ ] Reuse `stageWithWaveCount(2)` and assert the ordered list:

```text
clear wave 1 → [waveCleared]
clear wave 2 → [waveCleared, missionVictory]
update(0)    → unchanged
```

- [ ] After `_session.finishActiveWave()`:

```dart
if (didWin) {
  gameFeedback.missionVictory();
} else {
  gameFeedback.waveCleared();
}
```

Keep existing snapshot publication and `onStageWon` ordering intact.

### Step 6: Wire boss defeat

- [ ] Reuse `_bossSummonStage()` for a standalone non-terminal boss kill assertion.
- [ ] After an accepted boss is removed/rewarded:

```dart
if (enemy.stats is BossDefinition) {
  gameFeedback.bossDefeated();
}
```

- [ ] Lifecycle/update work after resolution does not append another boss call.

### Step 7: Make base defeat an explicit `wave → lost` edge

- [ ] Extend the existing `defeat mid-tick stops ticking remaining enemies` test using `_twoEnemyDefeatStage()` and a recording fake.
- [ ] Assert both lethal enemies are present before the lethal update, then:

```text
game.update(60)
→ phase lost
→ calls contains baseDefeated exactly once
→ trailing enemy cannot append another baseDefeated
→ follow-up update(0) leaves calls unchanged
```

- [ ] Change `_handleEnemyReachedBase(...)`:

```dart
final phaseBeforeDamage = _session.phase;
_session.damageBase(enemy.stats.baseDamage);
final didLose =
    phaseBeforeDamage == GamePhase.wave &&
    _session.phase == GamePhase.lost;

if (didLose) {
  gameFeedback.baseDefeated();
  _clearCombatComponents(removeTowers: false);
  _resetWaveSpawnState();
  _resetPacing();
  _layoutBoardIfReady();
}
_publishSnapshot();
```

This is a small production hardening: one-shot defeat semantics become local to the actual phase transition instead of relying on the later `_tickEnemyLogic` break. State this in the commit message/body.

### Step 8: Add the exact same-frame final-boss → victory ordering regression

- [ ] Add a one-wave no-summon boss fixture:

```dart
StageDefinition _singleBossVictoryStage() {
  return StageDefinition(
    id: 'single-boss-victory-stage',
    name: 'Single Boss Victory Stage',
    mapLabel: 'Boss',
    description: 'One boss for same-frame victory feedback tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: 1,
            enemyStats: BossDefinition(
              health: 50,
              speed: 0,
              baseDamage: 1,
              goldReward: 0,
              sprite: BossSprite.swarmQueen,
              name: 'Test Boss',
            ),
          ),
        ],
        clearBonus: 0,
      ),
    ],
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
```

- [ ] Use the existing real `ProjectileComponent` same-frame test pattern. Ensure the game is mounted, spawn the boss, add a lethal projectile, then resolve it during `super.update(...)`:

```dart
const projectileStats = TowerStats(
  type: TowerType.laser,
  level: 1,
  cost: 0,
  upgradeCost: 0,
  specializationCost: 0,
  range: 100,
  damage: 1000,
  fireInterval: 1,
  projectileSpeed: 10000,
  splashRadius: 0,
  slowMultiplier: 1,
  slowDuration: 0,
  corrosionDamagePerSecond: 0,
  corrosionDuration: 0,
  armorShred: 0,
);
```

- [ ] After the one update that kills the boss and finishes the wave, assert **order**, not just counts:

```dart
expect(feedback.calls, [
  _RecordedFeedbackCall.bossDefeated,
  _RecordedFeedbackCall.missionVictory,
]);
expect(game.snapshot.phase, GamePhase.won);
```

- [ ] Then:

```dart
game.update(0);
game.processLifecycleEvents();
```

and assert the list is still exactly those two calls. There must be no `waveCleared` token.

Do not add scheduler/suppression logic to satisfy this test.

### Step 9: Prove resize/lifecycle/snapshot work cannot replay cues

- [ ] After one successful cue path:

```dart
game.onGameResize(Vector2(390, 640));
game.processLifecycleEvents();
game.update(0);
```

- [ ] Assert the ordered call list is unchanged.

### Step 10: Pass the page-owned service into real games

- [ ] In `_startStage(...)`:

```dart
final game = OrionDefenseGame(
  ...,
  gameFeedback: _gameFeedback,
);
```

Replay/Retry reuses the same game/service instance; do not recreate it during `restart()`.

### Step 11: Run and commit

- [ ] Run:

```bash
flutter test test/game/orion_defense_game_test.dart
flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] Commit with the loss-edge hardening called out:

```bash
git add lib/game/orion_defense_game.dart \
  lib/game/ui/orion_game_page.dart \
  test/game/orion_defense_game_test.dart \
  test/widget_test.dart
git commit -m "feat: trigger game feedback and edge-detect defeat"
```

---

## Task 5: Lock Reduced Motion on the actual 360×640 test view

**Files:**
- Modify: `test/widget_test.dart`

Task 3 already ships `_sheetAnimationStyle(...)` and applies it to stage briefing and Settings. This task adds regression coverage only.

### Step 1: Set the physical test view size explicitly

- [ ] In the Reduced Motion test:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
```

Do not rely on `MediaQueryData(size: ...)` above `MaterialApp` for geometry.

### Step 2: Inject only the accessibility state through MediaQuery

- [ ] Pump a specialized wrapper with explicit no-op feedback:

```dart
await tester.pumpWidget(
  MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MaterialApp(
      home: OrionGamePage(
        progressStore: campaignStore,
        feedbackPreferencesStore: feedbackStore,
        gameFeedback: const NoOpGameFeedback(),
      ),
    ),
  ),
);
```

- [ ] Tap `Alpha`, use one normal `pump()`, and assert briefing content / `Start Mission` is already visible.
- [ ] Dismiss, open Settings, use one normal `pump()`, and assert `Follows system • On` is visible immediately.
- [ ] Assert `tester.view.physicalSize == const Size(360, 640)` during the test and `tester.takeException()` is null.

### Step 3: Lock the normal state

- [ ] Repeat the Settings status assertion with `disableAnimations: false` and expect `Follows system • Off`.

Test observable behavior/status only; do not inspect internal animation controllers.

### Step 4: Run and commit

- [ ] Run:

```bash
flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] Commit:

```bash
git add test/widget_test.dart
git commit -m "test: lock system reduced motion behavior"
```

---

## Task 6: Final verification and native product smoke

### Step 1: Strict formatting

- [ ] Run:

```bash
dart format --output=none --set-exit-if-changed .
```

If it fails, run `dart format .`, inspect the diff, and rerun the strict command.

### Step 2: Static analysis

- [ ] Run:

```bash
flutter analyze
```

Expected: no issues.

### Step 3: Focused tests

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
flutter test test/widget/feedback_settings_sheet_test.dart
flutter test test/game/orion_defense_game_test.dart
flutter test test/widget_test.dart
```

Expected: PASS.

### Step 4: Full suite

- [ ] Run:

```bash
flutter test
```

Expected: current full suite PASS.

### Step 5: Platform/build checks

- [ ] Confirm existing CI runs for the implementation PR, including the repository's web and mobile build workflows. Do not create a new CI workflow for HPA-531.

### Step 6: Native smoke

- [ ] Run on one native mobile target:

```bash
flutter devices
flutter run -d <device-id>
```

- [ ] Exercise:
  1. place and upgrade a tower;
  2. select a Salvage Module;
  3. clear a non-terminal wave;
  4. finish one victory or base defeat;
  5. confirm each expected terminal/result cue occurs once;
  6. verify the first confirm cue is not noticeably delayed;
  7. background/foreground and confirm no old cue replays.

- [ ] Settings matrix:

```text
Sound ON  / Haptics ON  → both channels
Sound OFF / Haptics ON  → haptic only
Sound ON  / Haptics OFF → audio only
```

- [ ] Enable OS Reduce Motion and confirm stage briefing / Settings appear without sliding movement and remain interactive.
- [ ] Reset Campaign and confirm Sound/Haptics choices survive.
- [ ] Inspect the 360px-ish world-map header with four icons; confirm the one-line ellipsized title remains readable enough.

### Step 7: Record evidence, do not build a harness

- [ ] Add target/result and any platform limitations to the implementation PR and HPA-531 Linear comment.
- [ ] If a cue feels noisy or redundant, remove/narrow it rather than adding scheduler infrastructure.
- [ ] Unsupported haptics without a crash are acceptable.

### Step 8: Final diff check

- [ ] Run:

```bash
git diff --check
```

- [ ] Confirm no:
  - campaign-save schema change;
  - game-rule/combat-math change beyond the local `wave → lost` edge detection in the Flame orchestrator;
  - module/blueprint redesign;
  - event bus/scheduler/rate limiter;
  - third preference;
  - screen shake.

---

## Expected final shape

```text
feedback_preferences.dart
  two booleans + copyWith/value equality + one-key store + in-memory store

game_feedback.dart
  six semantic methods + const no-op + best-effort platform calls/cache warm-up

feedback_settings_sheet.dart
  two switches + system Reduced Motion status

orion_defense_game.dart
  gameFeedback field + direct success/result call sites + explicit loss edge

orion_game_page.dart
  owns prefs/service, passes gameFeedback, opens both motion-aware sheets

scripts/generate_feedback_audio.py
  deterministic project-owned WAV generation

assets/audio/
  four explicit one-shot files + provenance note
```

If implementation starts requiring a production cue enum, event routing, playback state, scheduler, generalized settings controller, or more persistence machinery than this, simplify back to these direct seams.
