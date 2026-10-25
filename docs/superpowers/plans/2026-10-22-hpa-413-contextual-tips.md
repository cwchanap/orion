# HPA-413 — Contextual Tips Implementation Plan

> **One PR / one ticket:** continue on `hpa-413-contextual-first-time-tips` / draft PR #42. Design, code, tests, and review follow-ups remain in this PR. End each vertical slice in a runnable/testable state. Do not create a second PR for any phase.

**Linear:** https://linear.app/cwchanap/issue/HPA-413/orion-explain-new-systems-the-first-time-they-appear  
**Spec:** `docs/superpowers/specs/2026-10-22-hpa-413-contextual-tips-design.md`  
**Status:** Implemented in PR #42 (slices 1–4); full validation and device smoke test pending.

## Architecture and reuse contract

- Page coordinates eligibility and owns `Set<ContextualTip> _seenTips`. A pure `contextualTipFor(snapshot, seen)` picks **one current** candidate; `learnedTipsIn(snapshot)` supplies action-based acknowledgements. No pending-fact collection, sticky active-tip queue, timers, or generic tutorial controller.
- The old HPA-412 guide always wins. Only build-phase, no-draft, no-inspector gameplay can show a contextual tip; the modifier tip belongs to a separate briefing route.
- Extend the existing `FirstMissionGuideStore`, reusing its page injection and SharedPreferences instance. Typed `Set<ContextualTip>`, with `orion.contextualTips` storing sorted enum names; unknown stored IDs ignored. Update SharedPreferences, in-memory and `test/widget_test.dart`'s `_FailingFirstMissionGuideStore`.
- Share one read-only `WavePreview.bossGroups` getter between scanner and tip resolver. Do not change `GameSnapshot`, `GameSession`, combat, campaign save or tuning.
- Reuse the existing HPA-412 callout geometry, anchor wrappers, stage sheet and Settings Replay Tutorial. All UI is non-modal and normal game input remains active.
- No new assets, SFX, runtime packages, engine, event bus, persisted current-step queue or generalized scheduler.

### Key acceptance risk: Wave button overlap

The persistent idle rail sits **below** the bottom-right Wave pill; a 300×120 bubble anchored to this rail can flip upward over the pill on a 360-wide phone. **Never anchor unlock tips to the persistent rail.** Only the selected-cell rail (which replaces the idle bar) may carry the unlock-tip key. Also test radial targeting/specialization bubbles near bottom cells so their action areas do not overlap Wave controls.

## Expected files

**Create**
- `lib/game/onboarding/contextual_tips.dart` — closed enum, copy, `contextualTipFor`, `learnedTipsIn`.
- `test/onboarding/contextual_tips_test.dart` — resolver, learned-action and shared boss-predicate tests.
- `test/widget/contextual_tips_gates_test.dart` — focused end-to-end build/draft/inspector/briefing/replay tests.

**Modify**
- `lib/game/onboarding/first_mission_guide_store.dart`, `test/onboarding/first_mission_guide_store_test.dart` — typed seen-tip read/write next to the existing boolean.
- `test/widget_test.dart` — **only** update `_FailingFirstMissionGuideStore` interface methods (and any strictly required existing fixture compile errors). Put new integration tests in the focused file above.
- `lib/game/models/game_models.dart`, `lib/game/ui/next_wave_scanner.dart` — one read-only boss-groups getter replacing the scanner's duplicated label predicate.
- `lib/game/ui/first_mission_guide_callout.dart` and focused callout tests — generalize copy/actions while preserving original wrapper, semantics, keys and geometry.
- `lib/game/ui/orion_game_page.dart` — load/ack/reset seen state, gating, board targets and briefing entry.
- `lib/game/ui/mission_chrome.dart`, `lib/game/ui/mission_command_dock.dart` — generalize selected-cell Laser anchor to one tower type and wire new radial targeting anchor.
- `lib/game/ui/stage_briefing_sheet.dart` — key the existing modifier tile and immediately dismiss the tip inside the active modal route.
- Existing targeted rail, scanner, radial, stage sheet and settings tests as needed.

Avoid touching the underlying gameplay mutation paths and art/audio assets.

---

## Slice 1 — Boss tip end to end: store, resolver, callout, page and replay

**Goal:** Prove one contextual tip from real preview → on-screen scanner anchor → Got it → persistence → Replay Tutorial, while preserving the six-step HPA-412 guide. This vertical slice sets up the exact reusable seams for later tips.

1. **RED tests: typed store.** Add `ContextualTip` enum declared in resolver priority order: `bossWave`, `railgun`, `ionChain`, `nanite`, `gravityWell`, `droneBay`, `specialization`, `targeting`, `stageModifier`. Extend `FirstMissionGuideStore` with `Future<Set<ContextualTip>> loadSeenTips()` and `Future<void> setSeenTips(Set<ContextualTip>)`; test missing/unreadable -> empty, `.name` sorted list round trip, unknown names dropped, in-memory implementation and original `loadCompleted()/setCompleted()` unaffected. Update the **third implementor** `_FailingFirstMissionGuideStore` in `test/widget_test.dart` to satisfy the interface.
2. **RED tests: boss fact and gating.** Move the existing `WaveScannerScene` predicate `preview.groups.where((g) => GameBalance.bosses.any((b) => b.name == g.label))` into a read-only `WavePreview.bossGroups` getter. Both the scanner and `contextualTipFor` consume it, not separate copies. Test matching/nonmatching labels, no boss on ordinary preview, and no tip during wave, draft or ended session. Require **no selected cell or selected tower** so the collapsed scanner is usable. No `isBoss` model field.
3. **RED tests: existing renderer contract.** Refactor `FirstMissionGuideCallout` into a thin adapter over the shared text/actions/anchor renderer. Contextual mode shows its copy and Got it without Skip tutorial. HPA-412 still renders its original six texts, Skip tutorial everywhere, Got it only on scanner, hit-transparent surfaces and reduced-motion geometry.
4. **Wire page for boss only.** Load `_seenTips` before the loading gate clears, from the already-injected guide store. With HPA-412 active show only HPA-412. Otherwise build-phase, no-selection and real boss preview may show a boss tip on the **existing collapsed scanner key**. On Got it (or Start Wave while this tip is currently shown), mark boss seen in memory and write through best-effort; starting a wave is never blocked. Do not add a controller or pending queue.
5. **Replay Tutorial.** The existing settings callback must await `setSeenTips({})` and `setCompleted(false)` before reporting success. Keep old error behavior if a write fails; Reset Campaign changes neither preference. Routine acknowledgements use HPA-412-style best-effort write-through; **do not prebuild a serialization framework**. Pass immutable set snapshots and add rapid-tap + replay tests; add minimal ordering coordination only if a focused test proves an actual overwrite race.
6. Write focused widget gates for first boss display and scanner anchor, HPA-412 exclusivity, no boss during combat/draft/report/selection, once-seen after page remount, and replay reset.

**Verification:** `flutter test test/onboarding/contextual_tips_test.dart test/onboarding/first_mission_guide_store_test.dart test/widget/contextual_tips_gates_test.dart` plus existing callout/scanner/settings tests. End green before proceeding.

Suggested commit: `HPA-413: deliver once-only boss tip and shared guidance store`

## Slice 2 — Unlock tips on selected-cell rail only

**Goal:** Show five role hints on the actual selectable cards with zero Wave-pill obstruction.

1. **RED resolver tests:** When `selectedCellBuildable && selectedCell != null && selectedTower == null`, a currently unlocked unseen Railgun/Ion/Nanite/Gravity/Drone card is eligible in unlock order; otherwise none. Do not render in the persistent rail, a nonbuildable cell, an active wave, or while HPA-412 is eligible. A previously placed type counts as learned and suppresses its own hint.
2. Generalize the existing HPA-412 **selected-cell Laser anchor** to an optional `TowerType` + `Key` for exactly one active card; no second parallel GlobalKey. Do not attach it to the persistent rail, including during `AnimatedSwitcher` transitions. Preserve card `ValueKey` and all drag/tap handling.
3. Since there are only eight fixed cards, replace `TowerBuildRail`'s lazy `ListView.separated` with `SingleChildScrollView` + `Row`, preserving horizontal/vertical padding, separators, text scaling, card semantics and hit targets. All eight anchors are then built; use `Scrollable.ensureVisible` after layout (center, reduced-motion aware) once when target type activates or branch mounts. No manual card-width/index/gap arithmetic or repeated auto-scroll after the user scrolls.
4. Wire the page's resolver to the card anchor in the selected-cell branch only, and add learned-action acknowledgement after placing any matching tower. The page should not need a pending event queue; the unlocked list remains a current fact across build phases.
5. **Widget gates:** Railgun + offscreen Drone Bay on 360×640 at 1.3x text scale; both dock branches transition with no GlobalKey collision; Got it reachable; Wave pill does not share the bubble's tap rect; scroll occurs once without fighting user interaction; HPA-412 Laser plus long-press drag regression stays green.

**Verification:** focused resolver and rail/chrome/widget gate tests, `flutter analyze`.

Suggested commit: `HPA-413: guide newly unlocked tower cards without obscuring Wave`

## Slice 3 — Specialization and targeting on the radial

**Goal:** Reuse real board/radial targets and automatically acknowledge observed gameplay actions.

1. **RED resolver tests:** With nothing selected and a placed tower whose `canSpecialize` is true, aim at that real tower cell. With that very tower selected, aim at `upgradeGuideAnchorKey` only while `selectedTower.canSpecialize` (level 2). If a different level-1 tower is selected, **do not** aim at its Upgrade button; targeting may appear instead. A selected tower with an available radial targeting action may show targeting (unless specialization has priority for that tower). Suppress all during inspector/draft/combat.
2. Add one optional `targetingGuideAnchorKey` wrapper around the existing radial targeting button; keep its tooltip, semantics, callback and test `ValueKey` stable. No new radial menu abstraction.
3. `learnedTipsIn(snapshot)` returns specialization when any placed tower has `specialization != null` and targeting when any has `targetingMode != TowerTargetingMode.first`. Union newly learned facts into the page's seen set **after frame**, so an early upgrade/retarget action makes later tips unnecessary; do not mutate state in a build callback. The unlock learned-action logic shares this helper.
4. **Widget gates:** specialization board/radial anchoring, wrong-tower selection yielding to targeting, targeting button tapped, automatic recognition of specialized/nondefault-targeting towers, once-only persistence across restart, and no coverage of the Wave pill even when selecting a tower near the bottom rows.

**Verification:** focused resolver/radial/widget tests, `flutter analyze`.

Suggested commit: `HPA-413: add selection-safe specialization and targeting tips`

## Slice 4 — Modifier briefing tip and full regression

**Goal:** One once-only tip attached to the existing modifier tile, immediately removable inside the active modal sheet.

1. **RED tests:** Stage with `modifiers.isNotEmpty` shows the tip when unseen; Alpha's Standard Conditions does not; close/start without Got it leaves it unseen; Got it hides immediately and persists across reopen/restart; more than one modifier still shows one tip only.
2. In `OrionGamePage._showStageBriefing`, seed a route-local `tipVisible` bool from the page's seen set. Use a `StatefulBuilder` or a small stateful wrapper **inside that route** to clear the bool immediately on Got it before telling the page to persist it. The parent's `setState` alone will not rebuild this modal route. Wrap the existing `_BriefingModifierTile` with an optional anchor; keep its effect copy and real launch action unchanged.
3. Check at-most-one visible tip; one true target per tip; no HPA-412 overlap; no gesture interception; no wave/draft/report/inspector hints. Run size regression at 360×640 and 1.3× and verify Wave and contextual Got it can both be tapped without intersection (including radial tips).
4. Reuse `test/widget/contextual_tips_gates_test.dart` for cross-stage, remount, simultaneous-candidate, inferred-action, replay and reset coverage. Keep `test/widget_test.dart` unchanged except the failing-store interface implementation.
5. Verify full repository before marking the **same** PR ready for review:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
```

Device smoke test: fresh Alpha guide, later-stage modified briefing, five unlock milestones through Wave 6, level-2 radial, targeting, boss preview, normal 3x progression. Log and fix HPA-413 defects within PR #42; unrelated polish belongs to focused future tickets.

Suggested commit: `HPA-413: explain stage modifiers and finish regression gates`

## Final acceptance

Nine tips maximum, one displayed at a time, on true actionable anchors. Players can always build/start waves/select modules, and either Got it or the relevant learned gameplay action acknowledges a tip. All recognized tips persist across app restarts; Settings Replay Tutorial resets both guidance stores; Reset Campaign does not. Zero new packages, art/audio generation tasks, gameplay mutation paths or save schema changes.

Keep draft PR #42 open until implementation, tests and the device UI overlap checks pass.
