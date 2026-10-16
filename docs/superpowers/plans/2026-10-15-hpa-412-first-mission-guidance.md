# HPA-412 — First Mission Guidance Implementation Plan

> **For agentic workers:** implement this plan on the same HPA-412 branch/PR. Do not split the ticket into multiple PRs. Work task by task, test-first, and keep each commit green.

**Goal:** Guide a fresh Outpost Alpha player through build → tower → Wave 1 → upgrade → first Salvage Module → next-wave scanner using soft, skippable callouts in the real mission, then keep the guide out of the way until Settings explicitly replays it.

**Architecture:** Tutorial eligibility/completion stays in `OrionGamePage` with one separate SharedPreferences boolean. A pure `GameSnapshot` resolver chooses the currently useful callout; one page-owned overlay points at existing controls/board coordinates. Existing gameplay/session mutation paths remain authoritative and unchanged.

**Tech Stack:** Flutter + Flame + Dart + SharedPreferences. No new packages, assets, image art, or SFX.

**Spec:** `docs/superpowers/specs/2026-10-15-hpa-412-first-mission-guidance-design.md`

## Global Constraints

- One PR for HPA-412, including design, plan, implementation, and tests.
- Outpost Alpha only; completed guide never appears on other stages or later Alpha runs unless Settings clears the flag.
- Completion lives under separate SharedPreferences key `orion.firstMissionGuide`; Reset Campaign must not clear it and campaign save format/version stays untouched.
- Guidance is never a hard lock: no modal barrier, disabled gameplay control, scripted wave, or forced tower choice.
- Progress comes from `GameSnapshot` facts. Do not add tutorial state to `GameSession`, `GameSnapshot`, campaign models, or saves.
- Tap and drag placement share the same completion fact: a placed tower exists.
- No generic tutorial engine/controller/event bus/target registry. HPA-413 remains separate work.
- Preserve all existing `ValueKey`s and real callbacks on dock/radial/scanner/module surfaces.
- No new art/SFX work in this ticket.

## Review Focus

- **Direct drag placement without cell selection:** once a tower exists, guidance must advance to Wave instead of waiting for `selectedCell`; Task 1 resolver test + Task 4 real-page drag test pin this.
- **Out-of-order early upgrade:** an already-Level-2 tower must suppress the post-Wave-1 upgrade hint; Task 1 pins it.
- **Anchor churn on the smallest phone:** callouts must survive selected-cell dock transitions, tower/radial appearance, module overlay, and scanner reappearance without duplicate GlobalKeys or overflow; Tasks 2 and 4 pin this at 360×640.
- **Completion lifetime:** Skip/Got-it/final Start Wave persist independently from Reset Campaign, while Replay Tutorial clears only this flag; Tasks 1, 3, and 4 pin it.
- **Overlay input behavior:** transparent tutorial space must not absorb board/dock/module taps; Task 2 widget test and Task 4 guided path pin this.

---

## Expected File Shape

### Create

- `lib/game/onboarding/first_mission_guide.dart` — closed step enum + pure `GameSnapshot` → step resolver.
- `lib/game/onboarding/first_mission_guide_store.dart` — completion store interface, SharedPreferences implementation, in-memory test implementation.
- `lib/game/ui/first_mission_guide_callout.dart` — one non-modal callout/pointer widget.
- `test/onboarding/first_mission_guide_test.dart` — resolver coverage.
- `test/onboarding/first_mission_guide_store_test.dart` — persistence contract.
- `test/widget/first_mission_guide_callout_test.dart` — layout/input/semantics coverage.

### Modify

- `lib/game/ui/orion_game_page.dart` — load/inject guide store; determine eligibility/step; own anchor keys; render callout; persist skip/finish/replay; pass test picker.
- `lib/game/ui/mission_chrome.dart` — accept/pass optional Wave/Laser/Upgrade/Scanner anchor keys only.
- `lib/game/ui/mission_command_dock.dart` — optional Laser + Wave anchor wrappers; selected-cell rail only gets the Laser GlobalKey.
- `lib/game/ui/next_wave_scanner.dart` — optional collapsed-scanner anchor wrapper.
- `lib/game/ui/run_module_draft_panel.dart` — optional draft-frame anchor wrapper.
- `lib/game/ui/feedback_settings_sheet.dart` — visible Settings title + Replay Tutorial async action/confirmation.
- `test/widget/feedback_settings_sheet_test.dart` — replay action regression.
- `test/widget_test.dart` — guide-store/picker injection and real first-mission path.

No gameplay/rules/campaign file changes are planned beyond importing `ModuleOfferPicker` in the page for the existing constructor seam.

---

## Task 1: Pin the guide facts and completion store

**Files:**
- Create: `lib/game/onboarding/first_mission_guide.dart`
- Create: `lib/game/onboarding/first_mission_guide_store.dart`
- Create: `test/onboarding/first_mission_guide_test.dart`
- Create: `test/onboarding/first_mission_guide_store_test.dart`

**Interfaces:**
- Produces: `enum FirstMissionGuideStep { buildCell, towerCard, startWave, upgrade, salvageModule, scanner }`
- Produces: `FirstMissionGuideStep? firstMissionGuideStepFor(GameSnapshot snapshot)`
- Produces: `FirstMissionGuideStore.loadCompleted()` / `setCompleted(bool)`
- Produces: `SharedPreferencesFirstMissionGuideStore.key == 'orion.firstMissionGuide'`
- Produces: `InMemoryFirstMissionGuideStore`

- [ ] **Step 1: Write resolver tests before production code**

In `first_mission_guide_test.dart`, construct minimal `GameSnapshot` fixtures (reuse/default optional constructor values rather than a new fixture framework) and assert:

- initial Wave-1 build/no selection/no tower → `buildCell`;
- selected cell/no tower → `towerCard`;
- tower exists → `startWave`;
- Wave 1 active → `null`;
- Wave-2 build with only Level-1 towers → `upgrade`;
- Wave-2 build with any Level-2+ tower → `null`;
- first pending module offer → `salvageModule`;
- first module acquired in Wave-3+ build → `scanner`;
- active Wave 3+ → `null`.

Include a fixture with a tower present and `selectedCell == null` explicitly named for drag placement; expect `startWave`.

- [ ] **Step 2: Run resolver test and verify RED**

Run: `flutter test test/onboarding/first_mission_guide_test.dart`

Expected: FAIL because the enum/resolver do not exist.

- [ ] **Step 3: Implement the minimal pure resolver**

Implement `firstMissionGuideStepFor(GameSnapshot snapshot)` with the spec's precedence. It must read only snapshot fields; no mutable progress object, timestamps, callbacks, or game reference.

- [ ] **Step 4: Write store tests**

In `first_mission_guide_store_test.dart`, use `SharedPreferences.setMockInitialValues` and assert:

- missing key loads `false`;
- `setCompleted(true)` round-trips true;
- `setCompleted(false)` clears it back to false;
- unexpected non-bool data under the key falls back to false;
- `InMemoryFirstMissionGuideStore` implements the same true/false behavior.

- [ ] **Step 5: Implement the stores**

`SharedPreferencesFirstMissionGuideStore` wraps one `SharedPreferences` instance, uses `getBool`/`setBool`, and throws `StateError` if `setBool` reports failure. Catch a bad stored type on load and return false. `InMemoryFirstMissionGuideStore` stores one mutable `bool completed`.

- [ ] **Step 6: Verify Task 1**

Run: `flutter test test/onboarding/first_mission_guide_test.dart test/onboarding/first_mission_guide_store_test.dart`

Expected: PASS.

Commit: `HPA-412: define first-mission guide progression and persistence`

---

## Task 2: Build one non-modal callout and narrow target anchors

**Files:**
- Create: `lib/game/ui/first_mission_guide_callout.dart`
- Create: `test/widget/first_mission_guide_callout_test.dart`
- Modify: `lib/game/ui/mission_chrome.dart`
- Modify: `lib/game/ui/mission_command_dock.dart`
- Modify: `lib/game/ui/next_wave_scanner.dart`
- Modify: `lib/game/ui/run_module_draft_panel.dart`

**Interfaces:**
- Consumes: `FirstMissionGuideStep`
- Produces: `FirstMissionGuideCallout(step:, anchorKey:, targetPoint:, onSkip:, onDone:)`
- Produces optional anchor-key inputs only; all existing gameplay callbacks stay unchanged.

- [ ] **Step 1: Write the callout widget tests**

For every `FirstMissionGuideStep`, pump the widget inside a 360×640 `MaterialApp`/`Orion` theme fixture and assert the exact copy from the spec. Assert `Skip tutorial` always exists and `Got it` exists only for `scanner`; tapping each invokes only its supplied callback.

Add:

- semantics-label assertion for the current copy;
- a GlobalKey-anchored fixture near each viewport edge and assert callout rect stays inside the SafeArea;
- a `targetPoint` fixture for the board path;
- a content button beneath empty overlay space; tap it and assert the underlying callback fires (no full-screen hit target);
- reduced-motion (`MediaQuery.disableAnimations = true`) pump with no pending transition animation/exception.

- [ ] **Step 2: Run the focused widget test and verify RED**

Run: `flutter test test/widget/first_mission_guide_callout_test.dart`

Expected: FAIL because the widget does not exist.

- [ ] **Step 3: Implement `FirstMissionGuideCallout`**

Implement one stateful widget that:

- measures `anchorKey.currentContext` after layout when an anchor key is supplied;
- otherwise uses `targetPoint` in the surrounding Stack's coordinate space;
- clamps a compact `OrionSurface` bubble to available bounds;
- paints only a simple connector/ring as ignored-pointer decoration;
- exposes Skip and optional Done buttons as the only tutorial hit targets;
- uses `orionMotionDuration` for any step/position transition (no looping/pulse animation).

Do not add a controller/overlay service or insert into Flutter's root `Overlay`.

- [ ] **Step 4: Add optional anchor wrappers without changing ownership**

`mission_chrome.dart`:

- add optional `Key? laserGuideAnchorKey`, `waveGuideAnchorKey`, `upgradeGuideAnchorKey`, `scannerGuideAnchorKey` to `MissionChrome`;
- pass them to the existing dock/radial/scanner owners;
- `TowerRadialActions` wraps only the top Upgrade/Specialize surface with `upgradeGuideAnchorKey` when supplied.

`mission_command_dock.dart`:

- add optional Laser/Wave guide keys;
- attach the Laser GlobalKey only in the **selected-cell** `TowerBuildRail` branch, never the persistent idle rail;
- wrap the Laser `_TowerBuildCard` without replacing its existing `ValueKey('tower-card-laser')`;
- wrap `_PrimaryActionPill` with the Wave guide key without replacing the existing reactor transition/value keys.

`next_wave_scanner.dart`:

- wrap the collapsed 48dp control with the optional scanner guide key; preserve `next-wave-scanner-collapsed`.

`run_module_draft_panel.dart`:

- add `Key? guideAnchorKey` and wrap the existing `run-module-draft-frame`; preserve that ValueKey.

- [ ] **Step 5: Verify the anchor changes do not alter existing controls**

Run:

`flutter test test/widget/first_mission_guide_callout_test.dart test/widget/run_module_draft_panel_test.dart test/widget/next_wave_scanner_test.dart test/widget_test.dart --name "command"`

If the final `--name` filter does not select the intended existing command-dock tests in this SDK, run the focused file(s) directly instead; do not change tests just to fit the command.

Expected: PASS, with existing tap/drag/semantics behavior unchanged.

Commit: `HPA-412: add soft guide callout anchors to mission UI`

---

## Task 3: Wire eligibility, persistence, replay, and the deterministic picker through `OrionGamePage`

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `lib/game/ui/feedback_settings_sheet.dart`
- Modify: `test/widget/feedback_settings_sheet_test.dart`
- Modify: `test/widget_test.dart` (test helper signature only in this task)

**Interfaces:**
- Consumes: `FirstMissionGuideStore`, `firstMissionGuideStepFor`, `FirstMissionGuideCallout`
- Produces: optional `OrionGamePage.firstMissionGuideStore`
- Produces: optional `OrionGamePage.moduleOfferPicker`
- Produces: page-owned `_setFirstMissionGuideCompleted(bool)`
- Produces: `FeedbackSettingsSheet.onReplayTutorial: Future<void> Function()`

- [ ] **Step 1: Add Settings replay tests first**

Extend `feedback_settings_sheet_test.dart`:

- title is `Settings`;
- Sound Effects/Haptics/Reduced Motion existing behavior stays unchanged;
- tapping `Replay Tutorial` awaits the callback exactly once, disables duplicate requests, and shows `Tutorial will replay on your next Outpost Alpha run.`;
- Done still returns the edited `FeedbackPreferences` draft exactly as before.

Run: `flutter test test/widget/feedback_settings_sheet_test.dart`

Expected: FAIL on the new replay assertions.

- [ ] **Step 2: Implement the Settings action only**

Add required/optional async replay callback as specified, local busy/queued presentation state, and visible title `Settings`. The sheet must not know about SharedPreferences or the tutorial store.

- [ ] **Step 3: Add page dependencies and load the completion flag**

In `OrionGamePage` add:

```dart
final FirstMissionGuideStore? firstMissionGuideStore;
final ModuleOfferPicker? moduleOfferPicker;
```

Page state adds the resolved guide store + `bool _firstMissionGuideCompleted` and four `GlobalKey`s for Laser/Wave/Upgrade/Scanner plus one draft anchor key. Reuse the already-created `SharedPreferences` instance in the default load path; if a custom campaign store is injected without a guide store, obtain SharedPreferences only for the guide store.

The page's initial loading gate must not clear until the guide completion flag has resolved/fallen back to false. Feedback preference loading remains independent as today.

- [ ] **Step 4: Render guidance only for eligible Alpha runs**

Inside `_buildStageScaffold`, compute:

- eligible iff active stage id is `OrionCampaign.stageOneId` and `_firstMissionGuideCompleted == false`;
- `step = eligible ? firstMissionGuideStepFor(snapshot) : null`.

Render `FirstMissionGuideCallout` last in the mission `Stack` so it can sit above the module panel/report layers but remains non-modal.

Target mapping:

- `buildCell` → `game.boardCellCenter(const GridPosition(2, 2))`;
- `towerCard` → Laser anchor key;
- `startWave` → Wave anchor key;
- `upgrade` → if `snapshot.selectedTower == null`, point to `game.boardCellCenter(snapshot.towers.first.position)`; otherwise Upgrade anchor key;
- `salvageModule` → module draft anchor key;
- `scanner` → scanner anchor key.

Pass only the relevant optional keys into MissionChrome / RunModuleDraftPanel.

- [ ] **Step 5: Implement completion/replay behavior**

`_setFirstMissionGuideCompleted(bool completed)` updates in-memory state immediately and then writes through the resolved store. Catch store failures without changing campaign/feedback breadcrumbs.

Wire:

- callout Skip → `true`;
- scanner Got it → `true`;
- mission `onStartWave`: if the currently resolved step is `scanner`, set completed before invoking `game.startWave()`; otherwise call the game unchanged;
- Settings Replay Tutorial → `false`.

Do not touch `_confirmResetCampaign` / campaign reset persistence.

- [ ] **Step 6: Pass the existing module picker seam through**

In `_startStage` construct `OrionDefenseGame(moduleOfferPicker: widget.moduleOfferPicker, ...)`.

Extend `testGamePage()` with optional `FirstMissionGuideStore? firstMissionGuideStore` and `ModuleOfferPicker? moduleOfferPicker` and pass them into `OrionGamePage`.

- [ ] **Step 7: Verify focused page/settings tests**

Run: `flutter test test/widget/feedback_settings_sheet_test.dart test/widget_test.dart --name "settings|briefing|module"`

Expected: existing selected tests plus new settings behavior pass. If Dart's test-name regex/filter syntax differs in this environment, run `test/widget_test.dart` unfiltered rather than altering code.

Commit: `HPA-412: wire first-mission guidance through the game page`

---

## Task 4: Prove the real first-mission path, soft behavior, and replay lifetime

**Files:**
- Modify: `test/widget_test.dart`
- Optional modify only if the existing smoke fixture needs dependency injection: `integration_test/app_smoke_test.dart`

**Interfaces:**
- Consumes all Tasks 1–3 interfaces.
- Produces no new runtime API beyond test coverage.

- [ ] **Step 1: Add a full fresh-Alpha guided-path test at 360×640**

Use:

- `InMemoryCampaignProgressStore` fresh progress,
- `InMemoryFirstMissionGuideStore(completed: false)`,
- the existing `testGamePage()` and `onGameCreated` handle,
- a deterministic `ModuleOfferPicker` already supported by `OrionDefenseGame`.

Drive the real page:

1. open Alpha briefing and start;
2. assert `Tap an empty cell to build here.`;
3. tap the guide's `(2, 2)` board cell and assert `Pick a tower.`;
4. tap `tower-card-laser` and assert the Wave copy;
5. start Wave 1 and assert no guide while the wave is active;
6. advance the mounted game using the same update/pump technique already used by Orion's widget/game tests until Wave 1 clears; assert upgrade copy;
7. tap the placed tower; assert the same upgrade copy now anchors to radial Upgrade; tap Upgrade and assert the guide waits silently for the next milestone;
8. advance Wave 2 to the deterministic first module draft; assert `Salvage Modules last only for this mission.`;
9. choose any offered module; assert scanner copy;
10. tap `Got it`; assert store `completed == true` and callout disappears.

At every guided build state, assert `tester.takeException()` is null. Keep the viewport at 360×640 for this test.

- [ ] **Step 2: Add direct-drag and soft-order regressions**

Add focused cases rather than duplicating the whole path:

- long-press-drag Laser from the existing card to a valid board cell from the first callout state; after commit, expect Wave copy directly (no requirement to select a cell first);
- construct/drive an early-upgraded Wave-1 state using existing public game actions; after Wave 1 clear, expect no upgrade guide;
- while a normal callout is visible, interact with another valid gameplay control/board cell and assert the game changes state (tutorial did not hard-lock it).

- [ ] **Step 3: Add lifetime/eligibility regressions**

Tests:

- store preseeded `completed: true` → Alpha shows no guide;
- another unlocked stage with `completed: false` → no guide;
- Skip from first callout → store true, relaunch Alpha → no guide;
- scanner callout + starting the next wave instead of Got it → store true;
- completed guide + Reset Campaign → store remains true;
- Settings Replay Tutorial → store false; next Alpha run starts with build-cell callout.

Do not add persistence to `CampaignSave` to make these tests pass.

- [ ] **Step 4: Keep the integration smoke on the production/default path**

Run the existing `integration_test/app_smoke_test.dart` unchanged first. Modify only if constructor dependency injection makes compilation require a mechanical optional argument (it should not, because all new page arguments are optional).

- [ ] **Step 5: Verify Task 4**

Run:

`flutter test test/onboarding/ test/widget/first_mission_guide_callout_test.dart test/widget/feedback_settings_sheet_test.dart test/widget_test.dart`

Expected: PASS.

Commit: `HPA-412: cover the complete first-mission tutorial path`

---

## Task 5: Full verification and draft-PR evidence

- [ ] Run `dart format --set-exit-if-changed .` — no formatting diff.
- [ ] Run `flutter analyze` — zero issues.
- [ ] Run `flutter test` — full suite green.
- [ ] Run the integration smoke command used by the repository/workflow for `integration_test/app_smoke_test.dart` where the required device/target is available; otherwise leave the existing smoke test source untouched and report the environment limitation in the PR.
- [ ] Manual portrait proof at 360×640 or closest emulator: start fresh Alpha, complete/skip, replay from Settings, confirm every target is visually legible and all underlying controls remain usable.
- [ ] Update the same HPA-412 PR description with the completed verification checklist/evidence. Do not open a second implementation PR.

## Risks / Deliberate Non-Work

- **Anchor measurement:** the callout may see a target only after one frame. It should render after post-frame measurement rather than inventing a second layout system. No cached target registry.
- **Dock transition:** Laser anchor is attached only to the selected-cell rail so AnimatedSwitcher never owns two widgets with the same GlobalKey.
- **Mid-wave silence:** `firstMissionGuideStepFor` intentionally returns null during active waves; no reminder toast/timer is needed.
- **App killed mid-tutorial:** only completion is persisted. A later fresh Alpha run starts guidance again; no step-resume schema is added.
- **Preference write failure:** in-memory Skip/Replay behavior wins for the current process; no new error banner is added for this non-critical flag.
- **HPA-413 reuse:** do not generalize HPA-412 around hypothetical later tips. Reuse/refactor can happen when HPA-413's actual targets/timing are implemented.
