# HPA-413 — First-Time Contextual Tips Design

**Linear:** [HPA-413](https://linear.app/cwchanap/issue/HPA-413/orion-explain-new-systems-the-first-time-they-appear)  
**Parent:** HPA-303  
**Status:** Proposed design; PR #42 remains documentation-only until implementation.

## Outcome and scope

A player encounters nine concise, once-only hints when learning later gameplay mechanics: Railgun, Ion Chain, Nanite, Gravity Well and Drone Bay unlocks; specialization; the first upcoming boss; the first stage modifier; and targeting. Wave-1 Laser/Rocket/Cryo are already covered by HPA-412.

**Reuse, not a new tutorial framework.** Keep `GameSession`, `GameSnapshot`, rules, balance, campaign saves, combat sound and assets unchanged. The only model-layer addition is one read-only `WavePreview.bossGroups` getter sharing the scanner's existing boss-label predicate. Fully offline; no new packages, generic scheduler, event bus or analytics.

## Existing seams

- `OrionGamePage` owns HPA-412 gating, live `GameSnapshot` rendering, settings replay and store injection. It stays the only contextual-tip coordinator.
- `lib/game/onboarding/first_mission_guide.dart` demonstrates the pure snapshot-in/resolved-step-out pattern.
- `lib/game/onboarding/first_mission_guide_store.dart` contains `FirstMissionGuideStore` with SharedPreferences and in-memory implementations. Extend those, not a parallel service.
- `lib/game/ui/first_mission_guide_callout.dart` already measures anchors, clamps bubbles to the SafeArea, and keeps decorative surfaces hit-transparent. Generalize only text/actions; preserve its HPA-412 wrapper and button behavior.
- `TowerBuildRail` has **eight fixed cards**; the selected-cell dock branch already owns HPA-412's Laser anchor. Use this branch for unlocked-tower tips, not the persistent idle rail.
- `TowerRadialActions` provides the progression action and targeting action; `NextWaveScanner` owns the collapsed preview; `StageBriefingSheet` already displays actual modifier metadata.

## Tip copy and targets

| Tip | Trigger and exact target | Copy |
| --- | --- | --- |
| Railgun | Railgun unlocked and unseen **when a buildable cell is selected**; selected-cell Railgun card | **Railgun unlocked.** Pierces enemies in a line. |
| Ion Chain | Same, Ion Chain card | **Ion Chain unlocked.** Lightning jumps between targets. |
| Nanite | Same, Nanite card | **Nanite unlocked.** Corrodes armor to help other towers. |
| Gravity Well | Same, Gravity Well card | **Gravity Well unlocked.** Damages enemies within its field. |
| Drone Bay | Same, Drone Bay card | **Drone Bay unlocked.** Launches autonomous interceptors. |
| Specialization | A level-2 unspecialized tower; board cell if no selection, or **that same selected** tower's radial progression button | **Specialization ready.** Choose one of two ways to evolve this tower. |
| Boss | Actual next-wave preview contains a boss; **nothing selected**, collapsed scanner anchor | **Boss ahead.** Check the scanner and prepare your defense. |
| Modifier | First eligible briefing with `stage.modifiers.isNotEmpty`; real modifier tile | **Stage modifier.** These conditions change how this mission plays. |
| Targeting | A tower is selected after HPA-412 guidance; radial targeting button | **Targeting modes.** Choose which enemies this tower attacks first. |

All nine have **Got it**. No second Codex, lengthy tutorial or explanatory modal.

## Pure resolution and acknowledgement

`lib/game/onboarding/contextual_tips.dart` defines the closed `enum ContextualTip` in priority order (boss, the five unlocks in progression order, specialization, targeting, modifier) and two pure functions:

- `contextualTipFor(GameSnapshot snapshot, Set<ContextualTip> seen)` returns at most one eligible tip. It returns `null` unless the phase is build, no module draft is open and the snapshot is not ended. The page additionally suppresses it during HPA-412 guidance or a modal tower inspector.
- `learnedTipsIn(GameSnapshot snapshot)` returns lessons demonstrated by gameplay: placing an unlocked tower family (`placedTowers.any(type == X)`), specializing any tower (`specialization != null`), or selecting a non-default targeting mode (`targetingMode != TowerTargetingMode.first`). As with HPA-412, observe snapshot results; don't add tutorial-specific gameplay events or state.

Selection-dependent precedence ensures the hint always points at an actionable control:

| Selection state | Candidate order |
| --- | --- |
| Nothing selected | Boss (only when `nextWavePreview.bossGroups` is nonempty and the collapsed scanner can be used), then specialization pointing at a matching placed tower |
| Buildable empty cell selected | Eligible new-tower cards in unlock order; **no idle Wave pill is present in this dock branch** |
| Tower selected | Specialization only if **`selectedTower.canSpecialize`**, otherwise targeting; never point the specialization tip at a different level-1 tower's Upgrade button |

If a nonbuildable/path cell is selected, do not show an unlock-card tip. The surrounding page handles inspector, guide and route visibility gates.

**No sticky active tip, pending-fact collection, or event queue.** Recalculate one candidate on each snapshot, just as HPA-412 does. Conditions that do not currently apply simply wait for the next eligible build snapshot. If the user upgrades or retargets, changing the resolved hint is desirable.

A lesson is considered seen after **Got it** *or doing the taught action*:

- Place tower X → acknowledge unlock X.
- Specialize any tower → acknowledge specialization.
- Change any tower from default targeting → acknowledge targeting.
- For the boss tip, Got it or actively starting the boss wave while its tip is displayed → acknowledge boss. Normal play remains enabled; auto-start never gets blocked by a callout.
- Modifier is acknowledged only by Got it on its briefing (launching or closing the sheet is not an acknowledgement).

When the page observes learned snapshot facts, it unions them into `_seenTips` **post-frame** to avoid `setState` during a build. Acknowledged IDs persist; acting before a tip appears also suppresses redundant guidance. Do not acknowledge a tip just because its anchor was detached, the wave ended, or the player navigated away.

## Reusable geometry and touch safety

1. **Unlock cards:** Generalize the selected-cell `laserGuideAnchorKey` pattern to target one `TowerType` with one optional `GlobalKey`; keep HPA-412's Laser behavior. Never attach this key to the persistent rail or both `AnimatedSwitcher` branches.
2. Replace the eight-card lazy `ListView.separated` in `TowerBuildRail` with a `SingleChildScrollView` + `Row` using the same padding, card keys, separators, sizing, and tap/drag semantics. Eight eager widgets are cheaper to maintain than manually duplicating scroll geometry. After the selected-cell branch mounts or the chosen type changes, use `Scrollable.ensureVisible` (center alignment, reduced-motion aware) **once** on the real card context. Never fight the player's later scrolling. No manual index/width arithmetic.
3. **Specialization:** use `boardCellCenter` for an unselected qualifying tower; reuse the radial `upgradeGuideAnchorKey` only when the selected tower itself can specialize. A different selected tower yields to targeting.
4. **Boss:** extract the scanner's `GameBalance.bosses` label-match into `WavePreview.bossGroups`; `WaveScannerScene` and tip resolution share this getter. No `WavePreviewGroup.isBoss` or gameplay schema additions. Reuse the collapsed scanner anchor; require no selected cell/tower.
5. **Targeting:** add a simple optional `KeyedSubtree` on the actual radial targeting button, preserving its callback and semantics.
6. **Modifier:** wrap the existing modifier tile in a key. The bottom-sheet route owns a **local visible flag** (a `StatefulBuilder` in `_showStageBriefing` is sufficient); clear it immediately on Got it, then notify the page. A parent `setState` alone will not rebuild the sheet's route.

Reuse the existing renderer's connector, HitTestBehavior, SafeArea clamping and reduced-motion logic. Anchor detachment already renders nothing; do not introduce an extra anchor registry.

**Top UX risk: obstructing Start Wave.** Do not anchor unlock tips to the persistent rail, where their above-card Got it bubble can cover the bottom-right Wave pill. Run 360×640 and 1.3× text-scale tests checking the Wave pill and Got it remain independently tappable. Check radial specialization/targeting near bottom cells for the same overlap; adjust existing bubble placement minimally if necessary. Empty overlay space must remain pass-through.

## Storage, replay, and lifecycle

- Keep `orion.firstMissionGuide` as its separate boolean, with its existing nullable-record meaning.
- Extend the **same** `FirstMissionGuideStore` contract with typed `loadSeenTips() → Future<Set<ContextualTip>>` and `setSeenTips(Set<ContextualTip>)`. Store sorted enum `.name` strings under `orion.contextualTips`; read via `ContextualTip.values.asNameMap()` and drop unknown names. No handwritten ID map, stringly-typed page boundary, or migration.
- Update **all three known implementors**: SharedPreferences, in-memory, and the failing fixture `_FailingFirstMissionGuideStore` in `test/widget_test.dart`.
- Load seen IDs alongside the existing guide flag **before the startup loading gate clears**. Default SharedPreferences acquisition is reused; there is no additional service injection.
- Got it / learned-action acknowledgements update the in-memory set immediately and write through best-effort without blocking play. Use the existing HPA-412 fire-and-forget convention for routine tip writes rather than building a dedicated persistence coordinator. Keep writes idempotent, pass immutable set snapshots, and test rapid acknowledgements/replay; introduce ordering coordination **only if an actual failing test demonstrates it is required**.
- Settings → **Replay Tutorial** awaits clearing both contextual tips and the original guide flag before showing success. Update in-memory state only after the reset writes succeed. A write failure must not claim success. `Reset Campaign` still changes neither onboarding key.
- No permanent current-step/queue storage. No tips while the guided first-mission callout is active, during wave combat, a module draft, a report or modal inspector.

## Acceptance tests

- Each of the nine tips is shown only where its target exists and is tappable, and is suppressed after Got it **or a learned action** as appropriate; seen IDs survive remount and cross-stage navigation.
- Boss detection is shared with scanner; no boss hint for an ordinary wave or when cell/tower selection blocks scanner input.
- No specialization hint on a different Level-1 tower's Upgrade button; targeting can still appear.
- Selected-cell rail scrolls Railgun and Drone Bay into view once, with no duplicate `GlobalKey`; HPA-412's Laser tip and tap/drag controls still work.
- At 360×640/1.3×, every callout and the Wave button are reachable without overlapping hit areas; no modal barriers are introduced.
- Modifier hint dismisses immediately inside an already-open briefing; leaving without Got it does not mark it seen.
- Replay Tutorial resets both stores; Reset Campaign does not. No contextual hint appears over HPA-412 guidance, combat, drafts, inspector or reports.
- All integration gates live in focused `test/widget/contextual_tips_gates_test.dart`, not the root widget-test monolith. Run existing tests plus `flutter analyze` and `flutter build web --release`.

**One PR:** the design, implementation, tests and follow-up review fixes belong in the existing draft PR #42. No new SFX or art task is needed.
