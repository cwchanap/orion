# HPA-413 — First-Time Contextual Tips Design

**Linear:** [HPA-413](https://linear.app/cwchanap/issue/HPA-413/orion-explain-new-systems-the-first-time-they-appear)  
**Parent:** HPA-303  
**Status:** Design proposed; no runtime changes in this initial draft PR.

## Outcome

After the HPA-412 first-mission guide, later mechanics explain themselves where the player can act. There is at most one short, tappable, non-modal tip at a time, and an acknowledged tip does not recur across missions or app restarts.

The fixed catalog is **nine tips**: five separately acknowledged mid-mission tower families (Railgun, Ion Chain, Nanite, Gravity Well, Drone Bay), plus one each for specialization, the first upcoming boss, the first stage modifier, and targeting. The three Wave-1 tower families are already covered by first-mission guidance and are not new-unlock tips.

No gameplay tuning, new assets, SFX, Codex work, or generalized tutorial engine.

## Existing code to reuse

- `lib/game/ui/orion_game_page.dart` owns HPA-412 eligibility, SharedPreferences loading, settings replay, and the live `ValueListenableBuilder<GameSnapshot>`. It is the sole tip coordinator.
- `GameSnapshot` already projects `unlockedTowerTypes`, `placedTowers`, `selectedTower`, `nextWavePreview`, `stageModifiers`, `phase`, and `pendingRunModuleOffer`. No new snapshot fields or gameplay events are needed.
- `lib/game/onboarding/first_mission_guide_store.dart` implements the injected SharedPreferences + in-memory test-store pattern; extend it for acknowledged tip IDs rather than adding another service.
- `lib/game/ui/first_mission_guide_callout.dart` contains the non-modal, safe-area-clamped anchor/connector logic. Reuse this renderer, not a second 450-line painter/overlay.
- `MissionChrome` routes optional target keys to `TowerRadialActions` and the collapsed `NextWaveScanner`. `TowerBuildRail` has eight cards in a horizontal, lazily built `ListView.separated`; a new-tower tip must bring its actual card into view before anchoring.
- `StageBriefingSheet` already displays a modifier tile and its effect text, so stage-modifier guidance can attach there; `OrionGamePage._showStageBriefing` decides eligibility.
- `FeedbackSettingsSheet.onReplayTutorial` already awaits the page callback and reports success/failure.

## Player-facing contract

| Tip | Trigger / target | Short copy (proposal) |
| --- | --- | --- |
| Railgun | First eligible build phase with Railgun unlocked; Railgun rail card | **Railgun unlocked.** Pierces enemies in a line. |
| Ion Chain | First eligible build phase with Ion Chain unlocked; its card | **Ion Chain unlocked.** Lightning jumps between targets. |
| Nanite | First eligible build phase with Nanite unlocked; its card | **Nanite unlocked.** Corrodes armor to help other towers. |
| Gravity Well | First eligible build phase with Gravity Well unlocked; its card | **Gravity Well unlocked.** Damages enemies within its field. |
| Drone Bay | First eligible build phase with Drone Bay unlocked; its card | **Drone Bay unlocked.** Launches autonomous interceptors. |
| Specialization | First build phase with a level-2 unspecialized tower; that tower's board cell, then its radial progression action when selected | **Specialization ready.** Choose one of two ways to evolve this tower. |
| Boss wave | Build phase whose actual next-wave preview includes a named boss; collapsed scanner | **Boss ahead.** Check the scanner and prepare your defense. |
| Stage modifier | First briefing of a stage with nonempty modifiers; existing modifier tile | **Stage modifier.** These conditions change how this mission plays. |
| Targeting | First build-phase radial selection after HPA-412 guidance is complete; radial targeting action | **Targeting modes.** Choose which enemies this tower attacks first. |

Copy is intentionally one or two short sentences; existing UI/Codex owns detailed numbers.

All tips have **Got it**. Acknowledging a tip immediately hides it and marks its stable ID as seen. No other action silently marks it seen; backing out of a sheet, using a tower, leaving a mission, or ending a wave does not count as acknowledgement. Once acknowledged, it is suppressed across later missions and restarts.

## Eligibility, timing, and queue behavior

- HPA-412 guidance wins: while its callout is eligible, do not enqueue or render HPA-413 tips. If the player skips/completes that guidance during Alpha, later tips may become eligible on subsequent build snapshots, not during the guided path.
- **In-mission tips appear only during `GamePhase.build`**, with no pending module offer and no mission report/inspector covering the target. Active waves (even at 3x), drafts, and ended sessions remain untouched. A trigger first observable during combat is evaluated when the next build phase arrives.
- Stage-modifier tip is a separate **briefing-only** surface; it never overlays the in-mission dock or a module draft. A stage without modifiers cannot trigger it.
- The page derives candidate IDs only from current snapshot/briefing facts and seen IDs; an ordered, small page-local pending list is enough to retain a transient specialization/targeting observation until that target is actionable again. No event bus, registry, global coordinator, timer, or persisted in-flight queue.
- Keep at most one active tip. Use deterministic priority among actionable candidates: boss when the next-wave preview actually contains a boss, then newly unlocked tower families in unlock order, then specialization, then targeting. Do not interrupt a currently visible tip to reshuffle priorities; acknowledge it first or let it wait for the target to reappear.
- If a queued tip loses its target, leave it unacknowledged and defer until a matching build snapshot. A new mission may satisfy it later. No phantom anchor or fixed-screen fallback to the wrong control.
- Starting a wave or selecting a module always works; a tip never pauses the game, captures the board, or forces a choice. The existing tutorial overlay's hit-transparent behavior applies unchanged.

## Anchoring decisions

1. **Tower rail:** add one optional `TowerType` + `Key` tip target through `MissionChrome` → `MissionCommandDock` → visible `TowerBuildRail`. Keep existing card `ValueKey`s. Because `ListView.separated` lazily builds cards, scroll the selected card into view **once when its tip activates**, with its existing fixed 70dp card width, 8dp separator and text scaling; clamp to valid extents and respect reduced motion. Only then attach/measure the `GlobalKey`. Handle both selected-cell and persistent-rail branches without duplicate keys; never continuously fight the user's scrolling.
2. **Specialization:** aim at the unspecialized level-2 tower's live `boardCellCenter` if unselected; otherwise reuse the radial Upgrade/Specialize surface anchor. If its surface is detached or an inspector is open, defer.
3. **Boss:** reuse the scanner's collapsed-control anchor. Use the real `nextWavePreview.groups` and known boss definitions, not `waveNumber == 8` alone. If the scanner is expanded or unavailable, defer.
4. **Targeting:** add one optional anchor wrapper on the existing radial targeting button; do not change its selection callback or semantics.
5. **Modifier:** wrap the existing briefing modifier tile in an optional anchor and render the same reusable callout last in the briefing `Stack`. The sheet stays a normal (existing) modal briefing; the tip itself is hit-transparent outside its Got it button.

Generalize only the **copy + action inputs** of the existing callout renderer (for example, a shared `GuidanceCallout` with the old `FirstMissionGuideCallout` as a thin adaptor). Preserve existing HPA-412 copy, Skip tutorial / final Got it behavior, pointer semantics, and existing widget keys. Do not fork the geometry algorithm. On small portrait viewports, verify the new bubbles avoid the Wave action; use a small layout exclusion only if the existing placement logic cannot meet that test.

## Persistence and replay

Keep `orion.firstMissionGuide` as its existing boolean. Extend the same `FirstMissionGuideStore` implementations with read/write of a `Set<String>` of tip IDs, stored as a sorted string list under **`orion.contextualTips`**. The ID names come from one closed enum; unknown stored IDs are ignored. Missing/unreadable lists load as empty. No campaign-save migration or compatibility branch for old users.

Load the seen set with the tutorial completion flag before clearing the shell's loading gate, to avoid one-frame tip flashes. In-memory acknowledgment is immediate; serialize write-through snapshots so rapid acknowledgements cannot persist in reverse order. Write failures are non-blocking UX failures: suppress the tip for the current session, but allow it to recur after restart if the write genuinely failed.

Settings → Replay Tutorial resets **both** the original completion flag and all acknowledged contextual tips. Wait for any prior queued tip writes, then persist the empty set and original `false` flag before reporting success from the Settings sheet. A reset error must not claim success. Reset Campaign still clears neither tutorial preference.

## Explicitly out of scope

- Gameplay/rules, balance, damage, campaign progression, `GameSnapshot` schema, audio, new visual assets.
- Tips per enemy, module, specialization choice, stage, or targeting mode; Codex access or rewrites.
- Tutorial analytics, guided-mode locks, timeouts, priority scheduler, event bus, generalized coach-mark framework, separate discovery subsystem, persisted queue.
- Save migrations/versioning for unreleased players.

## Acceptance/validation

- Five tower-card tips, specialization, boss, modifier, and targeting each have a trigger/anchor widget test and each persist as seen after Got it.
- Combat, drafts, mission reports, and the active HPA-412 guide show no contextual tip. Tips do not cover the Wave action at 360×640; transparent areas remain tappable.
- The tower rail scrolls to late cards (including Drone Bay), does not duplicate GlobalKeys across dock branches, and does not auto-scroll repeatedly after user interaction.
- Pre-boss scanner tip comes from preview content and does not fire for ordinary waves. Modifier tip appears on its first eligible briefing, not on Standard Conditions.
- Restart/replay and cross-stage navigation preserve seen state; Settings Replay Tutorial resets both; Reset Campaign does not.
- Existing HPA-412 tutorial-path, settings, scanner, rail, radial, and callout tests remain green.
- Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `flutter build web --release`. Smoke-test Alpha (tutorial) and a later modified stage on a small portrait device.

**One PR for HPA-413:** this design, the implementation plan, actual runtime work, and tests live together on the same branch. Initial PR is documentation-only and stays Draft until implementation gates pass.
