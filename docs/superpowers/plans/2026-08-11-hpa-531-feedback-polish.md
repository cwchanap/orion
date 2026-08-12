# HPA-531 Lightweight Feedback Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small set of one-shot sound/haptic cues plus system Reduced Motion support without changing gameplay authority or introducing a generalized feedback platform.

**Architecture:** Keep feedback in the Flame/UI integration layer. `OrionDefenseGame` invokes a six-method `GameFeedback` interface only after existing authoritative mutations/results succeed. `OrionGamePage` owns two persisted feedback booleans and passes one `PlatformGameFeedback` into each game. Reduced Motion follows `MediaQuery.disableAnimations` and disables only the shell bottom-sheet transitions that currently move.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `shared_preferences` 2.5.5, `flame_audio` 2.12.2, `flutter_test`.

## Global Constraints

- Keep the catalog to six HPA-531 moments: tower confirmation, wave clear, module selection, boss defeat, mission victory, base defeat.
- No per-hit, per-projectile, tower-shot, enemy-spawn, or other high-frequency feedback.
- No semantic `GameEvent` enum, event bus, queue, scheduler, priority system, dedup layer, rate-limit framework, or lifecycle replay state.
- No screen shake.
- Feedback never mutates `GameSession` or any gameplay model.
- Trigger only after authoritative methods report success.
- Final-wave victory replaces generic wave-clear feedback.
- Boss defeat is haptic-only in this first slice; the final-boss overlap is covered explicitly rather than solved with a scheduler.
- Sound and haptics are separately persisted booleans.
- `FeedbackPreferences` is a value type with `copyWith`, `==`, and `hashCode`.
- Feedback preferences live outside `CampaignSave`; campaign reset must not remove them.
- Do not version or migrate the feedback settings.
- Reduced Motion follows the OS setting; do not persist a third toggle.
- The Reduced Motion helper and every production call site land in the same task so intermediate commits compile.
- Existing module-draft and Mission Report overlays stay immediate/static.
- Audio/haptic failures are swallowed; they never block gameplay or persistence.
- No blocking audio preload on app startup.
- Base defeat feedback is keyed to the explicit `GamePhase.wave → GamePhase.lost` edge, not merely `phase == lost` after damage.
- Target the existing 360×640 logical-pixel mobile baseline.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`, and one native simulator/device smoke check.

## File Map

### Create

- `lib/game/feedback/feedback_preferences.dart` — two booleans, value equality, SharedPreferences/in-memory stores.
- `lib/game/feedback/game_feedback.dart` — six-method interface and best-effort Flame/Flutter implementation.
- `lib/game/ui/feedback_settings_sheet.dart` — compact two-switch settings sheet plus system Reduced Motion status.
- `assets/audio/confirm.wav` — shared tower/module confirmation cue.
- `assets/audio/clear.wav` — non-terminal wave-clear cue.
- `assets/audio/victory.wav` — mission-victory cue.
- `assets/audio/defeat.wav` — base-defeat cue.
- `assets/audio/README.md` — short asset source/license note.
- `test/game/feedback_preferences_test.dart` — value semantics, defaults, and independent persistence.

### Modify

- `pubspec.yaml` — add `flame_audio` and `assets/audio/`.
- `pubspec.lock` — dependency resolution.
- `lib/game/orion_defense_game.dart` — optional `GameFeedback` input and authoritative call sites.
- `lib/game/ui/orion_game_page.dart` — preference loading/saving, production feedback service, settings sheet, Reduced Motion sheet style.
- `lib/game/ui/world_map_view.dart` — gear-button callback.
- `test/game/orion_defense_game_test.dart` — recording fake, loss edge, and same-frame final-boss coverage.
- `test/widget_test.dart` — settings, reset isolation, Reduced Motion, and 360×640 smoke coverage.

### No intended changes

- `lib/game/rules/game_session.dart`
- `lib/game/models/game_models.dart`
- `lib/game/campaign/campaign_progress.dart`
- `lib/game/campaign/campaign_progress_store.dart`
- `lib/game/rules/run_module_*`
- `lib/game/ui/run_module_draft_panel.dart`
- `lib/game/ui/mission_report_panel.dart`
- campaign save version/schema
- module catalog/draft logic
- blueprint ownership/reward logic
- combat math

---

## Task 1: Persist two value-semantic feedback preferences outside the campaign save

**Files:**
- Create: `lib/game/feedback/feedback_preferences.dart`
- Create: `test/game/feedback_preferences_test.dart`

**Interfaces:**

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

### Step 1: Write red value/persistence tests

- [ ] Create `test/game/feedback_preferences_test.dart`.
- [ ] Add value-equality coverage first:

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

test('copyWith can change and restore a draft to its original value', () {
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

- [ ] Add missing-key defaults:

```dart
test('defaults both feedback channels to enabled', () async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final store = SharedPreferencesFeedbackPreferencesStore(
    preferences: preferences,
  );

  expect(await store.load(), const FeedbackPreferences());
});
```

- [ ] Add Sound-only disabled, Haptics-only disabled, and both-disabled round trips.

### Step 2: Verify the tests are red

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
```

Expected: compile failure because the feedback preference types do not exist.

### Step 3: Implement the value type

- [ ] Create `lib/game/feedback/feedback_preferences.dart` with:

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
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FeedbackPreferences &&
            soundEffectsEnabled == other.soundEffectsEnabled &&
            hapticsEnabled == other.hapticsEnabled;
  }

  @override
  int get hashCode => Object.hash(
    soundEffectsEnabled,
    hapticsEnabled,
  );
}
```

This follows the existing `GridPosition` / `StageResult` value-type pattern. Do not substitute identity checks at the Settings call site.

### Step 4: Implement the two-key stores

- [ ] Use exactly:

```dart
static const soundEffectsKey = 'orion.feedback.soundEffects';
static const hapticsKey = 'orion.feedback.haptics';
```

- [ ] `load()` uses `getBool(...) ?? true` independently.
- [ ] `save()` writes both keys and throws `StateError` if either `setBool` returns false.
- [ ] Add the small in-memory test store:

```dart
class InMemoryFeedbackPreferencesStore
    implements FeedbackPreferencesStore {
  InMemoryFeedbackPreferencesStore({
    this.value = const FeedbackPreferences(),
  });

  FeedbackPreferences value;

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    value = preferences;
  }
}
```

Do not add JSON, versioning, migrations, or a generic settings repository.

### Step 5: Run and commit

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
```

Expected: PASS.

- [ ] Commit:

```bash
git add lib/game/feedback/feedback_preferences.dart \
  test/game/feedback_preferences_test.dart
git commit -m "feat: persist feedback preferences"
```

---

## Task 2: Add the thin platform feedback service and four one-shot assets

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/game/feedback/game_feedback.dart`
- Create: `assets/audio/confirm.wav`
- Create: `assets/audio/clear.wav`
- Create: `assets/audio/victory.wav`
- Create: `assets/audio/defeat.wav`
- Create: `assets/audio/README.md`

### Step 1: Add the Flame audio bridge

- [ ] Add:

```yaml
dependencies:
  flame_audio: ^2.12.2
```

- [ ] Register the directory once:

```yaml
flutter:
  assets:
    - assets/images/orion_sprite_sheet.png
    - assets/images/orion_tower_variety_sheet.png
    - assets/images/orion_terrain_background.png
    - assets/images/orion_path_tiles.png
    - assets/images/orion_boss_sheet.png
    - assets/audio/
```

- [ ] Run:

```bash
flutter pub get
```

Do not add a second direct `audioplayers` dependency.

### Step 2: Add the minimal asset set

- [ ] Add four short project-owned/self-created WAV one-shots:

```text
confirm.wav  # light positive UI confirmation
clear.wav    # short wave-complete accent
victory.wav  # stronger positive terminal accent
defeat.wav   # short negative terminal accent
```

- [ ] Add `assets/audio/README.md` recording the actual provenance/license. For project-owned originals:

```markdown
# Orion audio assets

`confirm.wav`, `clear.wav`, `victory.wav`, and `defeat.wav` are project-owned
original one-shot sound effects created for Orion. They may be distributed with
the project.
```

If a third-party CC0/licensed source is used, record the actual source URL, author, and license instead. No near-duplicate cue variants.

### Step 3: Implement the six-method service

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

final class PlatformGameFeedback implements GameFeedback {
  PlatformGameFeedback({
    required bool Function() soundEffectsEnabled,
    required bool Function() hapticsEnabled,
  }) : _soundEffectsEnabled = soundEffectsEnabled,
       _hapticsEnabled = hapticsEnabled;

  final bool Function() _soundEffectsEnabled;
  final bool Function() _hapticsEnabled;
}
```

- [ ] Map cues exactly:

```text
towerConfirmed  → confirm.wav + selectionClick
moduleSelected  → confirm.wav + selectionClick
waveCleared     → clear.wav   + lightImpact
bossDefeated    → no sound    + mediumImpact
missionVictory  → victory.wav + heavyImpact
baseDefeated    → defeat.wav  + heavyImpact
```

- [ ] Implement one fire-and-forget `_emit(...)` plus best-effort helpers:

```dart
void _emit({
  String? sound,
  Future<void> Function()? haptic,
}) {
  if (sound != null && _soundEffectsEnabled()) {
    unawaited(_playSound(sound));
  }
  if (haptic != null && _hapticsEnabled()) {
    unawaited(_playHaptic(haptic));
  }
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
```

No lifecycle observer, cache warm-up gate, queue, priority, replay state, or rate limiter.

### Step 4: Verify and commit

- [ ] Run:

```bash
flutter pub get
flutter analyze
```

Expected: dependency resolves and registered assets exist.

- [ ] Commit:

```bash
git add pubspec.yaml pubspec.lock \
  lib/game/feedback/game_feedback.dart \
  assets/audio
git commit -m "feat: add lightweight game feedback service"
```

---

## Task 3: Add page-owned settings and ship the Reduced Motion production bridge with them

**Files:**
- Create: `lib/game/ui/feedback_settings_sheet.dart`
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

**Produces:**

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context)
Future<void> _openFeedbackSettings()
Future<void> _saveFeedbackPreferences(FeedbackPreferences updated)
```

Both production `showModalBottomSheet(...)` call sites use `_sheetAnimationStyle(...)` before this task commits.

### Step 1: Write the 360×640 settings UI test first

- [ ] Add a widget test using:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
```

- [ ] Pump `OrionGamePage` with `InMemoryCampaignProgressStore` and `InMemoryFeedbackPreferencesStore`.
- [ ] Assert the world map exposes `Settings` by tooltip.
- [ ] Tap it and assert:

```text
Feedback
Sound Effects
Haptics
Reduced Motion
Follows system • Off
Done
```

- [ ] Assert `tester.takeException()` is null.

Expected before implementation: red because the callback/sheet do not exist.

### Step 2: Add the world-map entry point

- [ ] Extend `WorldMapView`:

```dart
final VoidCallback? onOpenSettings;
```

- [ ] Add one `IconButton` with `Icons.settings`, tooltip `Settings`, beside Codex/Tech Tree.
- [ ] Disable it while `_isBusy`, matching the existing shell actions.

Do not add a settings route or `_ShellView.settings` case.

### Step 3: Create the self-contained settings sheet

- [ ] Create `FeedbackSettingsSheet` as a small `StatefulWidget` with:

```dart
FeedbackSettingsSheet({
  required FeedbackPreferences initialPreferences,
  required bool reduceMotion,
});
```

- [ ] Copy `initialPreferences` into local `_draft` in state.
- [ ] Two `SwitchListTile`s update `_draft` independently via `copyWith`.
- [ ] Reduced Motion is informational only:

```text
Reduced Motion
Follows system • On
```

or

```text
Reduced Motion
Follows system • Off
```

- [ ] `Done` returns the local draft:

```dart
Navigator.of(context).pop(_draft);
```

Do not persist from the sheet.

### Step 4: Load feedback preferences independently from campaign progress

- [ ] Extend `OrionGamePage` with optional seams:

```dart
final FeedbackPreferencesStore? feedbackPreferencesStore;
final GameFeedback? gameFeedback;
```

- [ ] Add state:

```dart
FeedbackPreferences _feedbackPreferences =
    const FeedbackPreferences();
FeedbackPreferencesStore? _feedbackPreferencesStore;
late final GameFeedback _gameFeedback;
```

- [ ] Initialize the production service once in `initState()`:

```dart
_gameFeedback = widget.gameFeedback ?? PlatformGameFeedback(
  soundEffectsEnabled: () =>
      _feedbackPreferences.soundEffectsEnabled,
  hapticsEnabled: () => _feedbackPreferences.hapticsEnabled,
);
```

- [ ] Refactor loading only enough to obtain `SharedPreferences` once when either default store needs it.
- [ ] Keep campaign and feedback load failures independent:
  - campaign failure retains existing empty-campaign + breadcrumb behavior;
  - feedback failure falls back to `const FeedbackPreferences()` without replacing successfully loaded campaign progress.

No DI container or app-services object.

### Step 5: Add the Reduced Motion helper before any call site uses it

- [ ] Add to `orion_game_page.dart`:

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null;
```

- [ ] In the existing `_showStageBriefing(...)` call, add:

```dart
sheetAnimationStyle: _sheetAnimationStyle(context),
```

This production helper and the existing stage-briefing wiring ship in this task rather than waiting for Task 5.

### Step 6: Open and save the settings sheet using the same helper

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

Because Task 1 implemented value equality, a separate-but-equal draft and a toggled-then-restored draft correctly skip persistence.

- [ ] `_saveFeedbackPreferences(...)` semantics:
  - if no store exists, keep prior effective preferences and set `_mapFeedback = 'Could not save feedback settings.'`;
  - on success, update `_feedbackPreferences` to the saved value;
  - on failure, keep prior effective preferences and show the same breadcrumb.

The live enablement closures make service recreation unnecessary.

### Step 7: Add preference integration/reset tests

- [ ] Start Sound off / Haptics on, open Settings, toggle only Haptics off, tap Done, and assert the in-memory store is Sound off / Haptics off.
- [ ] Reopen Settings and assert both switches reflect the effective persisted state.
- [ ] Start with a non-default feedback combination, run the existing Reset Campaign flow, and assert the campaign store resets while the feedback store is unchanged.
- [ ] Do not modify `CampaignProgressStore.reset()`.

### Step 8: Run and commit

- [ ] Run:

```bash
flutter test test/widget_test.dart
```

Expected: PASS, including normal-motion stage briefing and settings behavior.

- [ ] Commit:

```bash
git add lib/game/ui/feedback_settings_sheet.dart \
  lib/game/ui/world_map_view.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget_test.dart
git commit -m "feat: add feedback settings and motion bridge"
```

---

## Task 4: Wire one-shot cues to authoritative game transitions

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/game/orion_defense_game_test.dart`

### Step 1: Add the recording fake

- [ ] Near the existing test-only picker, add:

```dart
final class _RecordingGameFeedback implements GameFeedback {
  int towerConfirmedCount = 0;
  int waveClearedCount = 0;
  int moduleSelectedCount = 0;
  int bossDefeatedCount = 0;
  int missionVictoryCount = 0;
  int baseDefeatedCount = 0;

  @override
  void towerConfirmed() => towerConfirmedCount += 1;

  @override
  void waveCleared() => waveClearedCount += 1;

  @override
  void moduleSelected() => moduleSelectedCount += 1;

  @override
  void bossDefeated() => bossDefeatedCount += 1;

  @override
  void missionVictory() => missionVictoryCount += 1;

  @override
  void baseDefeated() => baseDefeatedCount += 1;
}
```

### Step 2: Thread the optional service into `OrionDefenseGame`

- [ ] Add:

```dart
OrionDefenseGame({
  ...,
  this.feedback,
});

final GameFeedback? feedback;
```

Nullable keeps direct low-level construction silent. Do not add feedback to `GameSession`.

### Step 3: Wire tower confirmation only after success

- [ ] Add recording-fake coverage around existing action fixtures:
  - successful placement increments once;
  - successful upgrade increments again;
  - successful specialization increments again;
  - rejected/no-selection versions leave the count unchanged.
- [ ] Call `feedback?.towerConfirmed()` only after the matching session mutation succeeds.
- [ ] Sell, targeting changes, taps, and failures remain silent.

### Step 4: Wire module selection once

- [ ] Extend the existing valid-module-selection test with the recording fake.
- [ ] Successful selection increments `moduleSelectedCount` once.
- [ ] Repeating the same stale offer submission leaves the count unchanged.
- [ ] Call `feedback?.moduleSelected()` immediately after `_session.selectRunModule(...)` returns true.

### Step 5: Wire non-terminal wave clear vs terminal victory

- [ ] Reuse `stageWithWaveCount(2)`:

```text
clear wave 1 → waveCleared = 1, missionVictory = 0
clear wave 2 → waveCleared stays 1, missionVictory = 1
update(0)    → counts unchanged
```

- [ ] After `_session.finishActiveWave()`:

```dart
if (didWin) {
  feedback?.missionVictory();
} else {
  feedback?.waveCleared();
}
```

Keep existing snapshot publication and `onStageWon` ordering unchanged.

### Step 6: Wire boss defeat

- [ ] Reuse an existing `BossDefinition` combat fixture for the standalone boss-defeat assertion.
- [ ] Call after the kill is accepted/removed:

```dart
if (enemy.stats is BossDefinition) {
  feedback?.bossDefeated();
}
```

- [ ] Subsequent lifecycle/update processing does not increment it again.
- [ ] Do not add a boss sound or terminal-stage special-case in `_handleEnemyKilled`.

### Step 7: Make base defeat an explicit phase edge

- [ ] Extend the existing `defeat mid-tick stops ticking remaining enemies` test that uses `_twoEnemyDefeatStage()` with a recording fake.
- [ ] Assert the two lethal enemies are mounted before the lethal update, then:

```text
game.update(60)
→ phase == lost
→ baseDefeatedCount == 1
→ trailing same-tick enemy cannot create another cue
→ game.update(0) keeps baseDefeatedCount == 1
```

- [ ] In `_handleEnemyReachedBase(...)`, replace the planned post-damage state-only cue with the explicit edge:

```dart
final phaseBeforeDamage = _session.phase;
_session.damageBase(enemy.stats.baseDamage);
final didLose =
    phaseBeforeDamage == GamePhase.wave &&
    _session.phase == GamePhase.lost;

if (didLose) {
  feedback?.baseDefeated();
  _clearCombatComponents(removeTowers: false);
  _resetWaveSpawnState();
  _resetPacing();
  _layoutBoardIfReady();
}
```

- [ ] Keep `_publishSnapshot()` after the branch as today.

This makes one-shot defeat semantics local to the transition rather than depending on `_tickEnemyLogic` breaking later.

### Step 8: Lock the same-frame final-boss → victory overlap contract

- [ ] Add a focused one-wave fixture whose only enemy is a `BossDefinition`. It needs no summon mechanic and uses the normal short path.
- [ ] Spawn the boss, then use the same real `ProjectileComponent` testing pattern already used by the existing same-frame kill/overrun tests: mount a lethal projectile so the boss dies during `super.update(...)`, not by calling the feedback hook/test helper directly.
- [ ] In the single update that resolves that projectile and then finishes the wave, assert:

```dart
expect(feedback.bossDefeatedCount, 1);
expect(feedback.missionVictoryCount, 1);
expect(feedback.waveClearedCount, 0);
expect(game.snapshot.phase, GamePhase.won);
```

- [ ] Then run:

```dart
game.update(0);
game.processLifecycleEvents();
```

and assert all three counts are unchanged.

This is the exact overlap case that justifies boss haptic-only + victory sound/haptic. Do not solve it with a scheduler.

### Step 9: Prove resize/lifecycle work does not replay cues

- [ ] After one successful cue test path, run:

```dart
game.onGameResize(Vector2(390, 640));
game.processLifecycleEvents();
game.update(0);
```

- [ ] Assert all previously recorded counts are unchanged.

No production dedup state is expected.

### Step 10: Pass the service from the page

- [ ] In `_startStage(...)`:

```dart
final game = OrionDefenseGame(
  ...,
  feedback: _gameFeedback,
);
```

- [ ] Replay/Retry reuses the same game/service instance; do not recreate feedback during `restart()`.

### Step 11: Run and commit

- [ ] Run:

```bash
flutter test test/game/orion_defense_game_test.dart
flutter test test/widget_test.dart
```

Expected: PASS.

- [ ] Commit:

```bash
git add lib/game/orion_defense_game.dart \
  lib/game/ui/orion_game_page.dart \
  test/game/orion_defense_game_test.dart \
  test/widget_test.dart
git commit -m "feat: trigger authoritative game feedback"
```

---

## Task 5: Lock system Reduced Motion behavior with widget regressions

**Files:**
- Modify: `test/widget_test.dart`

Task 3 already ships `_sheetAnimationStyle(...)` and applies it to both stage briefing and feedback settings. This task adds only the focused accessibility regression; it must not introduce a second production helper or another preference.

### Step 1: Add the Reduced Motion regression

- [ ] Pump the page inside:

```dart
MediaQuery(
  data: const MediaQueryData(
    size: Size(360, 640),
    disableAnimations: true,
  ),
  child: MaterialApp(
    home: OrionGamePage(
      progressStore: campaignStore,
      feedbackPreferencesStore: feedbackStore,
    ),
  ),
)
```

- [ ] Tap `Alpha`, use a normal `pump()` rather than `pumpAndSettle()`, and assert briefing content / `Start Mission` is already visible.
- [ ] Dismiss the briefing, open Settings, use a normal `pump()`, and assert `Follows system • On` is already visible.

### Step 2: Lock the normal system state too

- [ ] Pump the same page with `disableAnimations: false` and open Settings.
- [ ] Assert `Follows system • Off`.
- [ ] This test validates observable behavior/status, not internal animation-controller state.

### Step 3: Run and commit

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

### Step 5: Native smoke

- [ ] Run on one native mobile target:

```bash
flutter devices
flutter run -d <device-id>
```

- [ ] Exercise:
  1. place and upgrade a tower;
  2. clear enough waves to select a Salvage Module;
  3. hear/feel the expected confirmation cues;
  4. clear a non-terminal wave;
  5. finish one mission victory or force one base defeat;
  6. confirm terminal feedback occurs once;
  7. background/foreground and confirm no old cue replays.

- [ ] Settings matrix:

```text
Sound ON  / Haptics ON  → both channels
Sound OFF / Haptics ON  → haptic only
Sound ON  / Haptics OFF → audio only
```

- [ ] Turn the OS Reduce Motion setting on and confirm stage briefing / feedback settings appear without sliding movement and remain immediately interactive.
- [ ] Reset Campaign and reopen Settings; confirm Sound/Haptics choices remain unchanged.

### Step 6: Record evidence, do not build a harness

- [ ] Add native target, result, and any observed audio/haptic limitation to the implementation PR and HPA-531 Linear comment.
- [ ] If a cue feels noisy or redundant, narrow/remove that cue rather than adding scheduler infrastructure.
- [ ] Unsupported haptics without a crash are acceptable per HPA-531.

### Step 7: Final diff check

- [ ] Run:

```bash
git diff --check
```

- [ ] Confirm the final diff contains no:
  - game-rule changes;
  - campaign-save schema changes;
  - module/blueprint logic changes;
  - event bus/scheduler abstractions;
  - screen shake.

---

## Expected final shape

```text
feedback_preferences.dart
  two booleans + copyWith + value equality + two stores

game_feedback.dart
  six methods + best-effort platform calls

feedback_settings_sheet.dart
  two switches + system Reduced Motion status

orion_defense_game.dart
  direct success/result call sites
  explicit wave → lost defeat edge

orion_game_page.dart
  owns prefs, passes service
  one shared bottom-sheet motion helper

assets/audio/
  four one-shot clips + one provenance note
```

If implementation starts requiring a semantic event layer, queue, lifecycle replay state, generalized settings controller, or more than this small file surface, stop and simplify back to these direct seams.
