# HPA-413 — First-Time Contextual Tips Implementation Plan

> **For implementing agents:** use the existing `hpa-413-contextual-first-time-tips` branch and **this single draft PR** from spec through implementation and tests. Do not open separate PRs per task or for review fixes. Keep intermediate commits buildable and tests green.

**Linear:** https://linear.app/cwchanap/issue/HPA-413/orion-explain-new-systems-the-first-time-they-appear  
**Design:** `docs/superpowers/specs/2026-10-22-hpa-413-contextual-tips-design.md`  
**Status:** Proposed; not yet implemented.

## Goal and constraints

Deliver nine concise once-only contextual hints (five unlocks + specialization + upcoming boss + stage modifier + targeting) by reusing the HPA-412 SharedPreferences injection and anchored non-modal callout. Remain offline and presentation-only: **no GameSession/GameSnapshot schema additions, combat changes, balance tuning, new packages, image art, or SFX**. One PR for the ticket.

The important existing contracts to preserve:

- `OrionGamePage` is the state/persistence coordinator; widget consumers read `GameSnapshot`, not `GameSession`.
- `FirstMissionGuideStore.loadCompleted/setCompleted` and `orion.firstMissionGuide` remain semantically unchanged; `Replay Tutorial` awaits a store write and reports errors.
- Existing `FirstMissionGuideCallout` has hit-transparent chrome and safe-area anchor measurement. Reuse/refactor the renderer, not duplicate it.
- Dock has two mutually exclusive tower rails, one of which is persistent; do **not** attach the same `GlobalKey` to both. Current `TowerBuildRail` uses a lazy horizontal `ListView.separated` with 70dp cards and 8dp gaps.
- `NextWaveScanner` has an anchor on its collapsed control only; `TowerRadialActions` already has an optional progression anchor.
- The stage briefing displays modifier title/effect; tips never introduce a second explanation sheet.

## Expected file shape

**Create**
- `lib/game/onboarding/contextual_tips.dart` — closed IDs, concise copy and pure current-snapshot candidate selection (no mutable session state).
- `test/onboarding/contextual_tips_test.dart` — trigger/order/guard tests.

**Modify**
- `lib/game/onboarding/first_mission_guide_store.dart` and `test/onboarding/first_mission_guide_store_test.dart` — load/save the seen-tip IDs under separate SharedPreferences key; keep existing tutorial flag.
- `lib/game/ui/first_mission_guide_callout.dart` and `test/widget/first_mission_guide_callout_test.dart` — share renderer via copy/actions while preserving the current first-mission wrapper/API/copy/keys.
- `lib/game/ui/mission_command_dock.dart` — optional tip-card key/type, one-time scroll-to-card in the active rail only.
- `lib/game/ui/mission_chrome.dart` — forward optional tip-card and radial-targeting anchors, reuse progression/scanner keys.
- `lib/game/ui/stage_briefing_sheet.dart` — optional modifier anchor/callout inputs; no new modal.
- `lib/game/ui/orion_game_page.dart` — load seen flags, coordinate eligibility/one active tip, queue transient trigger facts, persist Got it and settings replay.
- `test/widget_test.dart` — integrated mission/briefing/settings/phase gates.
- Narrow existing widget tests for the dock, radial, scanner, and briefing wherever those surfaces have dedicated fixtures.

Avoid editing `GameSession`, `game_models.dart`, `OrionDefenseGame`, `FeedbackPreferences`, campaign save models, assets, or audio.

---

## Task 1: Pin and implement stable IDs, pure trigger logic, and the store contract

**Files:** `contextual_tips.dart`, `contextual_tips_test.dart`, `first_mission_guide_store.dart`, `first_mission_guide_store_test.dart`.

1. Add RED tests defining nine stable IDs: `railgun`, `ionChain`, `nanite`, `gravityWell`, `droneBay`, `specialization`, `bossWave`, `stageModifier`, `targeting`. Tip copy and ordering are fixed; only the five `GameBalance.towerUnlockWave > 1` families get tower-unlock tips.
2. Cover snapshot facts: fresh build with no new tower -> none; Railgun appears at its actual unlock; subsequent types activate in their respective waves; level-2 unspecialized tower -> specialization candidate; real `WavePreview.groups` with a `BossDefinition` name -> boss candidate; ordinary preview -> no boss; selected tower in build -> targeting candidate. Preview and selected-tower conditions must not require reading the underlying `GameSession`.
3. Pure trigger candidates must return none during `GamePhase.wave`, `won`, `lost`, or pending module offer. A pure resolver should return candidate IDs in deterministic priority, excluding seen IDs. Stage modifier is a separate `stage.modifiers.isNotEmpty` briefing fact.
4. Extend `FirstMissionGuideStore` (and both current implementations) with `loadSeenTips()` and `setSeenTips(Set<String>)`; store a sorted string list at `orion.contextualTips`. Test missing/unreadable key => empty; persisted IDs round-trip and unknown values are filtered; the old nullable completion flag still has the same semantics; the two keys do not overwrite each other. Keep a typed enum-to-string mapping local to contextual tips.
5. Run `flutter test test/onboarding/contextual_tips_test.dart test/onboarding/first_mission_guide_store_test.dart`.

**Definition of done:** deterministic decisions with no new game-model fields; both stores round-trip state and existing guide-store tests still pass.

**Suggested commit:** `HPA-413: define contextual tips and persist acknowledgements`

## Task 2: Share the existing callout and anchor the real controls

**Files:** `first_mission_guide_callout.dart`, `mission_chrome.dart`, `mission_command_dock.dart`, `stage_briefing_sheet.dart`, relevant widget tests.

1. RED widget test: contextual variant shows exactly the provided copy and **Got it**, no `Skip tutorial`. HPA-412 variant still shows its original text, Skip tutorial everywhere, and scanner-only Got it. Preserve existing safe-area, semantics, pointer-pass-through, and reduced-motion expectations.
2. Factor the existing widget's measured bubble/connector/button-row code into one shared presentation widget within the same UI file, with text and primary/optional secondary actions as inputs. Leave a thin `FirstMissionGuideCallout` adaptor matching current call sites/tests. No new generic tutorial controller; no second painter or duplicated 450-line widget.
3. Expose one optional `tipTowerType` + `tipAnchorKey` through `MissionChrome` → `MissionCommandDock` → **visible** `TowerBuildRail`. Attach only to that type's existing `_TowerBuildCard`, wrapping its `ValueKey`. On a changed active tip, scroll once into view with card width `70 * textScale`, 8dp gap, and existing padding; clamp to current scroll extent, schedule after layout, respect reduced motion; do not scroll again on each snapshot. Once the card is built, the callout measures its actual anchor. Test Railgun and offscreen Drone Bay at 360×640 and 1.3x text scale, both dock branches, no duplicate keys, and user scroll after activation.
4. For specialization reuse the existing radial progression anchor; when no suitable tower is selected, point to the actual board cell using `game.boardCellCenter`. For targeting, add an optional `targetingGuideAnchorKey` wrapping the radial targeting button and preserve its `ValueKey`/onPressed/tooltip.
5. For boss reuse the scanner's collapsed anchor; do not attach an anchor to expanded scanner content. For stage modifier, accept optional copy, anchor and acknowledgement callback on `StageBriefingSheet`, wrap its existing modifier tile, and render the same contextual callout last in its `Stack`.
6. Run focused callout, rail, scanner, radial and briefing widget tests (then `flutter analyze` before the next commit).

**Definition of done:** all five target types map to real controls; no dead anchor, click interception, re-scrolling loop, or overlay duplication.

**Suggested commit:** `HPA-413: reuse anchored callout across contextual surfaces`

## Task 3: Wire page eligibility, lifecycle, acknowledgments, and Settings replay

**Files:** `orion_game_page.dart`, `test/widget_test.dart`, `test/widget/feedback_settings_sheet_test.dart` (when needed).

1. Load the seen-tip set through the **existing injected** `FirstMissionGuideStore`, together with `loadCompleted` before clearing the page loading gate. A default SharedPreferences instance must continue to be reused; no extra persistence injection/factory. Test no transient hint before the store resolves.
2. In the stage scaffold, check the HPA-412 `guideEligible` result first. If it owns guidance, show only its original callout and do not queue later tips. Otherwise derive current snapshot candidate IDs, retain only a tiny ordered pending list of transient facts as necessary, and choose one tip whose **actual target is attached and actionable**. Never show it during active wave, report, pending module draft, modal inspector, or detached/expanded scanner.
3. For a tower unlock first detected during an active wave, do not show it until the following build phase. If the player starts another wave before acknowledging, keep the tip unseen and eligible on the next suitable build; do not interfere with auto-start. Tower unlocks already present when guidance completes remain eligible on a later build snapshot.
4. A Got it callback adds the tip ID to in-memory seen state, removes it from the current pending list, and enqueues a write of an immutable seen-ID snapshot. Serialize writes so rapid acknowledgements cannot resurrect earlier states. Never mark as seen merely because a callout was mounted or its target disappeared; errors do not block gameplay.
5. In `_showStageBriefing`, attach modifier guidance only if `stage.modifiers` is nonempty and the modifier ID is unseen. If the sheet closes without Got it, it is still unseen for a later briefing. Acknowledging modifier does not launch the stage.
6. Extend the existing `onReplayTutorial` callback (not the Settings UI or feedback preferences) to **await pending tip writes**, persist an empty seen-tip set and tutorial completion `false`, then update in-memory state and report success. Keep the existing error propagation/disabled-while-in-flight behavior. `Reset Campaign` still leaves both keys untouched.
7. Run focused integrated widget tests for Alpha guide exclusivity, first later-wave unlock, level-2 selection, boss preview, modifier briefing, targeting radial, repeated stage navigation, restart, settings replay, and phase/draft/inspector suppression.

**Definition of done:** all nine tips can be acknowledged exactly once, user actions remain authoritative and immediately usable, first-mission guidance stays unchanged.

**Suggested commit:** `HPA-413: show once-only tips and reset them with Replay Tutorial`

## Task 4: Regression and device validation

**Files:** tests and any fixes **inside this same PR**.

- [ ] HPA-412 tutorial intact: brand-new Alpha guide still advances through six steps without contextual interruption; Skip, final Got it, and inferred completion still work.
- [ ] Five unlock tips individually tested with a persisted seen set across a remount/new page; seeing one does not suppress the other four.
- [ ] Specialization waits for Level 2 and can point at board or real radial action; targeting requires the visible radial button; no tip overlays tower inspector.
- [ ] Boss tip depends on real next-wave boss group; not every wave 8 merely because it is last; never mid-combat. Scanner expansion/detachment hides the tip rather than drawing at a false anchor.
- [ ] Modifier tip appears on the first eligible stage briefing, not Alpha's Standard Conditions; dismissing/closing briefing without Got it does not persist it.
- [ ] At most one tip rendered while multiple conditions are eligible; unseen tips remain eligible, with no forced replay steps.
- [ ] 360×640 and text scale 1.3: Drone Bay card scrolls into view once, Got it reachable, no Wave button obstruction or overflow, transparent overlay taps reach game controls.
- [ ] Rapid double Got it and Replay Tutorial cannot persist stale seen state; Reset Campaign does not clear onboarding tips.
- [ ] No new assets, packages, gameplay-state writes or balance changes.

Commands:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
```

Perform one human device smoke test with fresh Outpost Alpha onboarding, a later stage with a modifier, a specialization, boss scanner, and rail scroll at 3x. Record concrete failures and only fix in this PR if they affect HPA-413; unrelated improvements become later focused tickets.

**Final PR criteria:** both design/plan docs accurately describe the implementation, focused and full checks pass, one-screen-at-a-time usability validated. Convert this **same** PR from Draft only after code and test gates are complete; do not merge as part of planning.
