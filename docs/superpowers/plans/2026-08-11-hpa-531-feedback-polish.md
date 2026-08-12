# HPA-531 Lightweight Feedback Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small set of one-shot sound/haptic cues plus system Reduced Motion support without changing gameplay authority or introducing a generalized feedback platform.

**Architecture:** Keep feedback in the Flame/UI integration layer. `OrionDefenseGame` invokes a six-method `GameFeedback` interface only after existing authoritative mutations/results succeed. `OrionGamePage` owns two persisted feedback booleans and passes one `PlatformGameFeedback` into each game. Reduced Motion follows `MediaQuery.disableAnimations` and only disables the shell bottom-sheet transitions that currently move.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `shared_preferences` 2.5.5, `flame_audio` 2.12.2, `flutter_test`.

## Global Constraints

- Keep the catalog to the six HPA-531 moments: tower confirmation, wave clear, module selection, boss defeat, mission victory, base defeat.
- No per-hit, per-projectile, tower-shot, enemy-spawn, or other high-frequency feedback.
- No semantic `GameEvent` enum, event bus, queue, scheduler, priority system, dedup layer, or rate-limit framework.
- No screen shake.
- Feedback never mutates `GameSession` or any gameplay model.
- Trigger only after authoritative methods report success.
- Final-wave victory replaces generic wave-clear feedback.
- Boss defeat is haptic-only in this first slice to avoid sound overlap with immediate mission victory.
- Sound and haptics are separately persisted booleans.
- Feedback preferences live outside `CampaignSave`; campaign reset must not remove them.
- Do not version or migrate the feedback settings.
- Reduced Motion follows the OS setting; do not persist a third toggle.
- Existing module-draft and Mission Report overlays stay immediate/static.
- Audio/haptic failures are swallowed; they never block gameplay or persistence.
- No blocking audio preload on app startup.
- Target the existing 360×640 logical-pixel mobile baseline.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`, and one native simulator/device smoke check.

## File Map

### Create

- `lib/game/feedback/feedback_preferences.dart` — two booleans plus SharedPreferences/in-memory stores.
- `lib/game/feedback/game_feedback.dart` — six-method interface and best-effort Flame/Flutter implementation.
- `lib/game/ui/feedback_settings_sheet.dart` — compact two-switch settings sheet plus system Reduced Motion status.
- `assets/audio/confirm.wav` — shared tower/module confirmation cue.
- `assets/audio/clear.wav` — non-terminal wave-clear cue.
- `assets/audio/victory.wav` — mission-victory cue.
- `assets/audio/defeat.wav` — base-defeat cue.
- `assets/audio/README.md` — short asset source/license note.
- `test/game/feedback_preferences_test.dart` — defaults and independent persistence.

### Modify

- `pubspec.yaml` — add `flame_audio` and `assets/audio/`.
- `pubspec.lock` — dependency resolution.
- `lib/game/orion_defense_game.dart` — optional `GameFeedback` input and authoritative call sites.
- `lib/game/ui/orion_game_page.dart` — preference loading/saving, production feedback service, settings sheet, Reduced Motion sheet style.
- `lib/game/ui/world_map_view.dart` — gear-button callback.
- `test/game/orion_defense_game_test.dart` — recording fake and one-shot trigger coverage.
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

## Task 1: Persist two feedback preferences outside the campaign save

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
}

abstract interface class FeedbackPreferencesStore {
  Future<FeedbackPreferences> load();
  Future<void> save(FeedbackPreferences preferences);
}
```

### Step 1: Write red persistence tests

- [ ] Create `test/game/feedback_preferences_test.dart` with `SharedPreferences.setMockInitialValues(...)` in each test.
- [ ] Cover missing-key defaults:

```dart
test('defaults both feedback channels to enabled', () async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final store = SharedPreferencesFeedbackPreferencesStore(
    preferences: preferences,
  );

  expect(
    await store.load(),
    const FeedbackPreferences(
      soundEffectsEnabled: true,
      hapticsEnabled: true,
    ),
  );
});
```

- [ ] Add a Sound-only disable case and assert Haptics remains enabled after reload.
- [ ] Add a Haptics-only disable case and assert Sound remains enabled after reload.
- [ ] Add a both-disabled round-trip case.

### Step 2: Verify the tests are red

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
```

Expected: compile failure because the feedback preference types do not exist.

### Step 3: Implement the value and stores

- [ ] Create `lib/game/feedback/feedback_preferences.dart`.
- [ ] Use exactly two keys:

```dart
static const soundEffectsKey = 'orion.feedback.soundEffects';
static const hapticsKey = 'orion.feedback.haptics';
```

- [ ] `load()` uses `getBool(...) ?? true` independently.
- [ ] `save()` uses `setBool(...)` for each key and throws `StateError` if either call reports failure.
- [ ] Add a tiny `InMemoryFeedbackPreferencesStore` matching the existing campaign-store testing style:

```dart
class InMemoryFeedbackPreferencesStore implements FeedbackPreferencesStore {
  FeedbackPreferences value;

  InMemoryFeedbackPreferencesStore({
    this.value = const FeedbackPreferences(),
  });

  @override
  Future<FeedbackPreferences> load() async => value;

  @override
  Future<void> save(FeedbackPreferences preferences) async {
    value = preferences;
  }
}
```

Do not add JSON, a version field, migration helpers, or a generic settings repository.

### Step 4: Run the focused tests

- [ ] Run:

```bash
flutter test test/game/feedback_preferences_test.dart
```

Expected: PASS.

### Step 5: Commit

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

- [ ] Keep every clip short enough to be a one-shot UI/game cue; no loops or music.
- [ ] Add `assets/audio/README.md` with a concise provenance statement, for example:

```markdown
# Orion audio assets

`confirm.wav`, `clear.wav`, `victory.wav`, and `defeat.wav` are project-owned
original one-shot sound effects created for Orion. They may be distributed with
the project.
```

If implementation uses a third-party CC0/licensed source instead, replace that note with the actual source URL, author, and license. Do not add multiple near-duplicate variants.

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

  // six public methods delegate to _emit(...)
}
```

- [ ] Map cues exactly as the design specifies:

```text
towerConfirmed  → confirm.wav + selectionClick
moduleSelected  → confirm.wav + selectionClick
waveCleared     → clear.wav   + lightImpact
bossDefeated    → no sound    + mediumImpact
missionVictory  → victory.wav + heavyImpact
baseDefeated    → defeat.wav  + heavyImpact
```

- [ ] Implement `_emit(...)` as fire-and-forget. Wrap plugin calls in private async helpers that catch all audio/haptic errors internally before they escape:

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
  } catch (_) {
    // Sensory feedback is best-effort and never gameplay authority.
  }
}

Future<void> _playHaptic(Future<void> Function() haptic) async {
  try {
    await haptic();
  } catch (_) {
    // Unsupported platform/plugin: deliberately silent.
  }
}
```

No lifecycle observer, cache warm-up gate, queue, priority, replay state, or rate limiter.

### Step 4: Verify package/assets compile

- [ ] Run:

```bash
flutter pub get
flutter analyze
```

Expected: dependency resolves and all registered assets exist.

### Step 5: Commit

- [ ] Commit:

```bash
git add pubspec.yaml pubspec.lock \
  lib/game/feedback/game_feedback.dart \
  assets/audio
git commit -m "feat: add lightweight game feedback service"
```

---

## Task 3: Add the small settings sheet and page-owned preferences

**Files:**
- Create: `lib/game/ui/feedback_settings_sheet.dart`
- Modify: `lib/game/ui/world_map_view.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

### Step 1: Write the 360×640 settings UI test first

- [ ] In `test/widget_test.dart`, add a test using:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1;
addTearDown(tester.view.reset);
```

- [ ] Pump `OrionGamePage` with an `InMemoryCampaignProgressStore` and `InMemoryFeedbackPreferencesStore`.
- [ ] Assert the world map exposes `Settings` by tooltip.
- [ ] Tap it and assert the sheet shows exactly:

```text
Feedback
Sound Effects
Haptics
Reduced Motion
Follows system
Done
```

- [ ] Assert there is no overflow/exception on 360×640.

Expected before implementation: red because the settings callback/sheet do not exist.

### Step 2: Add the world-map entry point

- [ ] Extend `WorldMapView` with:

```dart
final VoidCallback? onOpenSettings;
```

- [ ] Add one `IconButton` with `Icons.settings` and tooltip `Settings` beside Codex / Tech Tree.
- [ ] Disable it while `_isBusy`, matching the existing shell buttons.

Do not add a settings shell enum/view.

### Step 3: Create the self-contained settings sheet

- [ ] Create `FeedbackSettingsSheet` as a small `StatefulWidget` that owns only a local draft copied from `initialPreferences`.
- [ ] Expose:

```dart
FeedbackSettingsSheet({
  required FeedbackPreferences initialPreferences,
  required bool reduceMotion,
});
```

- [ ] Two `SwitchListTile`s update the local draft independently.
- [ ] The Reduced Motion row is informational only:

```text
Reduced Motion
Follows system • On
```

or

```text
Follows system • Off
```

- [ ] `Done` returns the local draft:

```dart
Navigator.of(context).pop(_draft);
```

Do not save from inside the sheet; the page owns persistence.

### Step 4: Load feedback preferences independently from campaign progress

- [ ] Extend `OrionGamePage` with optional test seams:

```dart
final FeedbackPreferencesStore? feedbackPreferencesStore;
final GameFeedback? gameFeedback;
```

- [ ] Add page state:

```dart
FeedbackPreferences _feedbackPreferences = const FeedbackPreferences();
FeedbackPreferencesStore? _feedbackPreferencesStore;
late final GameFeedback _gameFeedback;
```

- [ ] Initialize `_gameFeedback` in `initState()`:

```dart
_gameFeedback = widget.gameFeedback ?? PlatformGameFeedback(
  soundEffectsEnabled: () => _feedbackPreferences.soundEffectsEnabled,
  hapticsEnabled: () => _feedbackPreferences.hapticsEnabled,
);
```

- [ ] Refactor the existing load path just enough to obtain `SharedPreferences` once when either default store needs it.
- [ ] Keep campaign and feedback error handling independent:
  - campaign load failure retains the existing empty-campaign + map breadcrumb behavior;
  - feedback load failure uses `const FeedbackPreferences()` and does **not** replace successfully loaded campaign progress.
- [ ] Existing tests that do not inject a feedback store must still boot if the plugin/store is unavailable; default preferences are sufficient.

Do not add a new dependency-injection container or app-services object.

### Step 5: Open/save settings from the page

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

  if (updated == null || updated == _feedbackPreferences) return;
  await _saveFeedbackPreferences(updated);
}
```

- [ ] Implement save semantics:
  - if no store exists, keep prior preferences and set `_mapFeedback = 'Could not save feedback settings.'`;
  - on success, set `_feedbackPreferences = updated`;
  - on failure, keep prior preferences and show the same breadcrumb.

Because `PlatformGameFeedback` reads closures, no service update/recreation is needed after save.

### Step 6: Add preference integration tests

- [ ] Add a widget test that starts with Sound off / Haptics on, opens the sheet, toggles only Haptics off, taps Done, and asserts the in-memory store now contains Sound off / Haptics off.
- [ ] Reopen the sheet and assert both switches reflect the persisted page state.
- [ ] Add the inverse independence case if the focused store tests do not already make the intent obvious enough.

### Step 7: Prove campaign reset does not reset feedback settings

- [ ] In `test/widget_test.dart`, initialize feedback preferences to a non-default combination.
- [ ] Perform the existing Reset Campaign flow.
- [ ] Assert the campaign store resets while the feedback store still contains the same values.

Do not change `CampaignProgressStore.reset()`.

### Step 8: Run focused UI tests

- [ ] Run the new/updated widget test names with `flutter test --name ...` or the full widget file:

```bash
flutter test test/widget_test.dart
```

Expected: PASS.

### Step 9: Commit

- [ ] Commit:

```bash
git add lib/game/ui/feedback_settings_sheet.dart \
  lib/game/ui/world_map_view.dart \
  lib/game/ui/orion_game_page.dart \
  test/widget_test.dart
git commit -m "feat: add feedback settings"
```

---

## Task 4: Wire one-shot cues to authoritative game transitions

**Files:**
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/game/orion_defense_game_test.dart`

### Step 1: Add a recording fake and red success/failure tests

- [ ] Near the existing test-only picker in `test/game/orion_defense_game_test.dart`, add:

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
  // same pattern for the other five methods
}
```

- [ ] Add tests around existing action fixtures:
  - successful placement increments `towerConfirmedCount` once;
  - successful upgrade increments it once more;
  - successful specialization increments it once more;
  - rejected/no-selection placement/upgrade/specialization does not increment it.

### Step 2: Thread the optional service into `OrionDefenseGame`

- [ ] Add:

```dart
OrionDefenseGame({
  ...,
  this.feedback,
});

final GameFeedback? feedback;
```

Nullable keeps direct low-level construction/tests silent by default; production will pass the page-owned service.

Do not add feedback to `GameSession`.

### Step 3: Wire tower confirmation only after success

- [ ] `placeTower(...)`: call `feedback?.towerConfirmed()` only after `_session.placeTower(...)` is allowed.
- [ ] `upgradeSelectedTower()`: call only after `_session.upgradeTower(...)` returns true.
- [ ] `specializeSelectedTower(...)`: call only after `_session.specializeTower(...)` returns true.
- [ ] Do not call for sell, targeting mode, selection, or failed attempts.

### Step 4: Test and wire module selection

- [ ] Extend the existing valid-module-selection test with a recording fake.
- [ ] Assert one successful selection increments `moduleSelectedCount` exactly once.
- [ ] Repeat the same stale `offerId/moduleId` call and assert the count stays unchanged.
- [ ] Implement the call immediately after `_session.selectRunModule(...)` returns true.

### Step 5: Test and wire wave clear vs victory precedence

- [ ] Reuse `stageWithWaveCount(2)`:
  - clear wave 1 → `waveClearedCount == 1`, victory == 0;
  - clear wave 2 → `missionVictoryCount == 1`, `waveClearedCount` stays 1;
  - call `game.update(0)` again → counts unchanged.
- [ ] In `_finishWaveIfComplete()` after `_session.finishActiveWave()`:

```dart
if (didWin) {
  feedback?.missionVictory();
} else {
  feedback?.waveCleared();
}
```

Keep existing snapshot publication and `onStageWon` semantics intact.

### Step 6: Test and wire boss defeat

- [ ] Reuse the existing boss combat fixture/test path that resolves a `BossDefinition` kill.
- [ ] Pass `_RecordingGameFeedback` and assert `bossDefeatedCount == 1` after the boss is accepted as killed.
- [ ] Assert subsequent lifecycle processing/update does not increment it again.
- [ ] In `_handleEnemyKilled(...)`, after accepting/removing the enemy:

```dart
if (enemy.stats is BossDefinition) {
  feedback?.bossDefeated();
}
```

Do not add boss sound or terminal-stage special-case logic here.

### Step 7: Test and wire base defeat

- [ ] Reuse the existing reach-base/loss fixture.
- [ ] Assert the first transition to `GamePhase.lost` increments `baseDefeatedCount` once.
- [ ] Run another `update(0)` / lifecycle pass and assert the count remains one.
- [ ] Call `feedback?.baseDefeated()` only inside the existing lost-phase branch after `damageBase(...)`.

### Step 8: Prove rebuild/resize does not replay feedback

- [ ] After one successful cue in a game test:

```dart
game.onGameResize(Vector2(390, 640));
game.processLifecycleEvents();
game.update(0);
```

- [ ] Assert every recording count is unchanged.

No production deduplication state should be required; the absence of observer-driven trigger paths is the guarantee.

### Step 9: Pass the service from the page

- [ ] In `_startStage(...)` add:

```dart
final game = OrionDefenseGame(
  ...,
  feedback: _gameFeedback,
);
```

- [ ] `restart(...)` reuses the same game/service instance automatically; do not recreate feedback on Retry/Replay.

### Step 10: Run focused game + widget tests

- [ ] Run:

```bash
flutter test test/game/orion_defense_game_test.dart
flutter test test/widget_test.dart
```

Expected: PASS.

### Step 11: Commit

- [ ] Commit:

```bash
git add lib/game/orion_defense_game.dart \
  lib/game/ui/orion_game_page.dart \
  test/game/orion_defense_game_test.dart \
  test/widget_test.dart
git commit -m "feat: trigger authoritative game feedback"
```

---

## Task 5: Bridge system Reduced Motion without an accessibility framework

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/widget_test.dart`

### Step 1: Add the system preference helper

- [ ] Add one private helper in `orion_game_page.dart`:

```dart
AnimationStyle? _sheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null;
```

Do not create a motion service or persist this value.

### Step 2: Apply it to the existing stage briefing

- [ ] Add to the existing `_showStageBriefing(...)` `showModalBottomSheet` call:

```dart
sheetAnimationStyle: _sheetAnimationStyle(context),
```

- [ ] The settings sheet added in Task 3 uses the same helper.

No changes are needed in `RunModuleDraftPanel` or `MissionReportPanel`; both are already immediate static overlays.

### Step 3: Add a Reduced Motion widget regression

- [ ] Pump the page inside:

```dart
MediaQuery(
  data: const MediaQueryData(
    size: Size(360, 640),
    disableAnimations: true,
  ),
  child: MaterialApp(...),
)
```

- [ ] Tap `Alpha`, call a normal `pump()` rather than `pumpAndSettle()`, and assert the briefing content/action is already visible.
- [ ] Open Settings and assert `Follows system • On`.
- [ ] Repeat the status assertion with `disableAnimations: false` → `Follows system • Off`.

The test should validate behavior/state, not animation-controller internals.

### Step 4: Run focused tests

- [ ] Run:

```bash
flutter test test/widget_test.dart
```

Expected: PASS.

### Step 5: Commit

- [ ] Commit:

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "feat: follow system reduced motion"
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

- [ ] On a normal campaign attempt:
  1. place and upgrade a tower;
  2. clear enough waves to select a Salvage Module;
  3. hear/feel the expected confirmation cues;
  4. finish one mission victory or force one base defeat;
  5. confirm terminal cue occurs once;
  6. resize/rotate only if the target permits it and confirm no old cue replays;
  7. background/foreground and confirm no old cue replays.

- [ ] Settings matrix:

```text
Sound ON  / Haptics ON  → both channels
Sound OFF / Haptics ON  → haptic only
Sound ON  / Haptics OFF → audio only
```

- [ ] Turn the operating-system Reduce Motion setting on and confirm stage briefing / feedback settings appear without a sliding transition and remain immediately interactive.
- [ ] Reset Campaign and reopen Settings; confirm Sound/Haptics choices remain unchanged.

### Step 6: Record evidence, do not build a harness

- [ ] Add the native target, result, and any observed audio/haptic limitation to the implementation PR and HPA-531 Linear comment.
- [ ] If a cue feels noisy or redundant, narrow/remove that cue rather than adding scheduler infrastructure.
- [ ] If a platform has no haptic effect but does not crash, treat that as acceptable per HPA-531.

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

The implementation should remain approximately:

```text
feedback_preferences.dart
  two booleans + two stores

game_feedback.dart
  six methods + best-effort platform calls

feedback_settings_sheet.dart
  two switches + system Reduced Motion status

orion_defense_game.dart
  direct success/result call sites only

orion_game_page.dart
  owns prefs, passes service, disables bottom-sheet motion

assets/audio/
  four one-shot clips + one provenance note
```

If implementation starts requiring a semantic event layer, queue, lifecycle replay state, generalized settings controller, or more than this small file surface, stop and simplify back to these direct seams.
