# HPA-412 — First Mission Guidance Design

**Linear:** HPA-412 — Orion: Guide a new player through their first mission

## Outcome

A fresh player entering **Outpost Alpha** gets six short, soft callouts through the real mission loop instead of being dropped from the briefing directly onto an unexplained build board:

1. **Build cell** — point at one empty cell beside the path: `Tap an empty cell to build here.`
2. **Tower card** — point at the Laser card: `Pick a tower.`
3. **Wave** — point at the Wave 1 action: `Start the wave when you're ready. Towers fire on their own.`
4. **Upgrade** — after Wave 1 clears, point at a placed tower; once selected, point at its radial Upgrade action: `Tap a tower, then Upgrade between waves.`
5. **Salvage Module** — over the first post-Wave-2 draft: `Salvage Modules last only for this mission.`
6. **Scanner** — point at the next-wave scanner: `Check the scanner before the next wave.`

The guide is **soft guidance, not a tutorial mode**. It never disables or captures the board, dock, scanner, module cards, or radial actions. The player may act in any order. A milestone that is already satisfied is skipped rather than forcing the player to repeat it.

`Skip tutorial` is available from every callout. The final scanner callout adds `Got it`. Skip, final acknowledgement, or starting the next wave while the final callout is active marks the guide completed.

No new art or SFX is required.

## Why this is the next slice

HPA-412 is the remaining High-priority onboarding child under HPA-303 and directly blocks HPA-413 (later-system first-time explanations). It also has no blockers. This makes it a better next slice than adding more replay/content polish before the core mission loop is understandable.

## Existing seams to reuse

The current UI already exposes nearly everything this guide needs:

- `OrionGamePage._showStageBriefing` → `_startStage` is the real mission launch seam.
- `OrionGamePage` already owns page-level persistence injection and the Settings sheet.
- `OrionDefenseGame.stateNotifier` publishes the `GameSnapshot` the page/chrome already renders from; UI does not need to read `GameSession` directly.
- `GameSession.towers` already exposes an immutable list of placed towers inside the rules layer, but `GameSnapshot` does not currently project it. HPA-412 needs one neutral read-side `placedTowers` projection so UI can observe placement/upgrade facts without breaking the snapshot-only UI boundary.
- `OrionDefenseGame.boardCellCenter` maps a grid cell to the live transformed board coordinate, so the first callout can point at a real board cell without duplicating board geometry.
- `TowerBuildRail` already identifies cards with `tower-card-<type>` and supports both tap and drag placement.
- `IdleCommandBar` owns the Wave action.
- `TowerRadialActions` owns the Upgrade action.
- `RunModuleDraftPanel` owns the first Salvage Module choice.
- `NextWaveScanner` owns the collapsed scanner control.
- `FeedbackPreferencesStore` demonstrates the small SharedPreferences-store + in-memory-test-double pattern, but tutorial completion must use its own key and must not become feedback state.
- `OrionDefenseGame` already accepts `ModuleOfferPicker`; `OrionGamePage` only needs to pass an optional injected picker through for deterministic page tests.

## Approaches considered

### A. Page-local, snapshot-derived guide — chosen

Keep one completion flag in a tiny store. While Outpost Alpha is active and that flag is false, derive the currently useful callout from the live `GameSnapshot`. Add only the missing neutral `placedTowers` read projection; the page owns the overlay and a handful of target anchors.

This matches Orion's existing state flow, naturally treats tap and drag placement the same once a tower exists, and avoids persisting transient tutorial state.

### B. Generic coach-mark/tutorial controller — rejected

A registry/controller with named steps, target registration, transitions, and persistence could be reused by HPA-413, but HPA-412 has only six fixed milestones and HPA-413 may not share the same timing/target model. Building a framework now adds abstraction before the second use case is known.

### C. Tutorial state in `GameSession` / campaign save — rejected

That would make pure game rules own presentation onboarding, add tutorial-specific fields to gameplay state/saves, and create a second reason to mutate session state. The one `placedTowers` snapshot field in the chosen approach is different: it is a read-only projection of existing authoritative tower state, not tutorial progress.

## 1. Completion is one preference, outside campaign progress

Create `FirstMissionGuideStore` with exactly two operations:

```dart
abstract interface class FirstMissionGuideStore {
  Future<bool?> loadCompleted();
  Future<void> setCompleted(bool completed);
}
```

Provide:

- `SharedPreferencesFirstMissionGuideStore`, backed by the boolean key `orion.firstMissionGuide`.
- `InMemoryFirstMissionGuideStore` for widget/unit tests.

`null` means no usable record (missing or unreadable); the loader resolves it through campaign progress — a committed Alpha result counts as complete — while an explicit `false` is honored. `setCompleted(true)` is used by Skip/finish; `setCompleted(false)` by Settings → Replay Tutorial.

`OrionGamePage` accepts an optional store. For the production/default path, reuse the same `SharedPreferences` instance already acquired during page startup when possible. The guide flag is loaded before the shell becomes interactive, so a completed player never gets a one-frame tutorial flash or a race where they can enter Alpha before eligibility is known.

This preference is deliberately independent of `CampaignProgressStore`:

- **Reset Campaign does not clear it.**
- No campaign save field/version changes.
- A replay request does not alter campaign results, tech, or feedback preferences.

A tutorial-store write failure keeps the requested state in memory for the current process and does not add a new blocking error surface. This flag is non-critical UX state; campaign persistence behavior stays untouched.

## 2. Add one neutral tower projection, then derive progression from snapshots

### Snapshot projection

Add one optional field to `GameSnapshot`:

```dart
List<PlacedTower> placedTowers = const []
```

Store it as `List.unmodifiable`. `GameSession.snapshot()` populates it from its existing `_towersByPosition.values`/`towers` authority.

Why this is the right seam:

- Orion's UI contract says widgets read game state through `GameSnapshot`, not `GameSession`.
- Placement and early-upgrade completion cannot be determined from `selectedTower` alone because placement clears selection and drag placement may never set `selectedCell`.
- A neutral immutable placed-tower projection is simpler and more reusable than tutorial-only booleans such as `hasPlacedTower` / `hasUpgradedTower`.
- Default `const []` keeps existing `GameSnapshot(...)` fixtures source-compatible.
- This is read-side only; it does not change placement/upgrade mutation, save state, balance, or simulation.

### Guide resolver

Add a small closed enum and pure resolver in `lib/game/onboarding/first_mission_guide.dart`:

```dart
enum FirstMissionGuideStep {
  buildCell,
  towerCard,
  startWave,
  upgrade,
  salvageModule,
  scanner,
}

FirstMissionGuideStep? firstMissionGuideStepFor(GameSnapshot snapshot);
```

The resolver uses the following precedence:

| Current game fact | Callout |
|---|---|
| First `pendingRunModuleOffer` is visible | `salvageModule` |
| Build phase after the first module is acquired (Wave 3+) | `scanner` |
| Build phase after Wave 1, and no `placedTowers` entry is Level 2+ | `upgrade` |
| Wave 1 build phase, `placedTowers` is non-empty | `startWave` |
| Wave 1 build phase, no tower exists, a cell is selected | `towerCard` |
| Wave 1 build phase, no tower/cell selection | `buildCell` |
| Active wave / waiting between guided milestones | no callout |

This is deliberately stateless:

- **Tap placement:** selecting a cell moves build-cell → tower-card; placing any tower moves tower-card → start-wave.
- **Drag placement:** creating a tower directly moves build-cell/tower-card → start-wave. No special drag tutorial event is needed.
- Choosing Rocket/Cryo instead of Laser still counts as understanding "pick a tower"; Laser is the visual target, not a forced choice.
- If the player upgrades before Wave 1, the post-wave upgrade callout is already satisfied and never appears.
- Starting Wave 1 hides guidance until the build phase after the wave clears.
- Selecting the first Salvage Module naturally replaces the draft callout with the scanner callout when the draft disappears.

The resolver does not decide whether the tutorial is eligible. `OrionGamePage` calls it only when the active stage is `OrionCampaign.stageOneId` and the completion flag is false.

## 3. One callout overlay; existing controls remain authoritative

Create `FirstMissionGuideCallout` as one presentation widget. It renders above the mission stack and receives:

- the `FirstMissionGuideStep`,
- either a board-local target point or an optional `GlobalKey` for a Flutter target,
- `onSkip`,
- optional `onDone` for the scanner step.

It owns only callout layout/presentation:

- compact `OrionSurface` bubble,
- a short connector/ring toward the target,
- `Skip tutorial` on every step,
- `Got it` only on the final scanner step,
- a live-region semantics label for the callout copy.

There is **no modal barrier, spotlight mask, or full-screen GestureDetector**. Transparent space must not participate in hit testing; only the bubble buttons do. Existing controls keep their real callbacks and availability rules.

The callout clamps its bubble to the SafeArea at 360×640 and larger portrait sizes. It prefers placing the bubble away from the target and may flip above/below when space is tight. Any step transition uses `orionMotionDuration`; reduced-motion therefore becomes immediate. Do not add pulsing, bouncing, or looping coach-mark animation.

### Target anchors

The page owns the anchor keys/board points; target widgets only accept an optional `Key`/anchor wrapper. No target registry or controller is introduced.

- **Build cell:** `game.boardCellCenter(const GridPosition(2, 2))`. On Outpost Alpha this is buildable and directly beside the `(3, 2)` path cell. Board geometry remains owned by `OrionDefenseGame`.
- **Tower card:** add an optional guide anchor to the selected-cell `TowerBuildRail`; attach it only to the Laser card. The persistent idle rail does not receive this key, avoiding duplicate `GlobalKey`s during dock transitions.
- **Wave:** optional anchor on `_PrimaryActionPill` in `IdleCommandBar`.
- **Upgrade:** before a tower is selected, target `boardCellCenter` for `snapshot.placedTowers.first.position`. Once a tower is selected, target the radial Upgrade surface/button via an optional anchor in `TowerRadialActions`. This produces the requested "tower, then Upgrade" behavior without another tutorial step.
- **Salvage Module:** optional anchor around the existing `run-module-draft-frame` surface.
- **Scanner:** optional anchor on the collapsed `NextWaveScanner` control.

Existing `ValueKey`s used by regression tests remain in place; anchor keys wrap rather than replace them.

## 4. Finish/skip and replay behavior

`OrionGamePage` owns `_setFirstMissionGuideCompleted(bool)`:

- update the in-memory completion state immediately,
- persist via `FirstMissionGuideStore`,
- ignore persistence failure beyond keeping the in-memory state.

Completion happens when:

- `Skip tutorial` is tapped on any step,
- `Got it` is tapped on the scanner step,
- or `onStartWave` is invoked while the active guide step is `scanner` (acting instead of acknowledging is enough).

Settings remains the existing sheet rather than creating a new settings subsystem:

- change the visible sheet title from **Feedback** to **Settings**,
- keep Sound Effects, Haptics, and Reduced Motion exactly as they are,
- add a **Replay Tutorial** action beneath them,
- the sheet calls an async page-owned callback; after success in the current session it shows a small `Tutorial will replay on your next Outpost Alpha run.` confirmation and disables duplicate requests.

Clearing the completion flag does not launch a mission or close the sheet automatically.

## 5. Deterministic full-path tests need only one new game seam

Add `ModuleOfferPicker? moduleOfferPicker` to `OrionGamePage` and pass it directly to `OrionDefenseGame` in `_startStage`. Production leaves it null, preserving existing random offer behavior.

Add the same optional argument to `testGamePage()` so the full onboarding widget test can pin the first module draft. Do **not** add a game factory, fake `GameSession`, tutorial-only game API, or scripted waves.

## Out of scope

- HPA-413 later-system hints (new tower types, targeting, bosses, campaign systems).
- Separate tutorial stage, scripted tutorial waves, altered Outpost Alpha balance, guaranteed player actions, or hard locks.
- Voiceover, new SFX, new sprites/illustrations, dimming masks, analytics, tutorial telemetry.
- Persisting the active tutorial step or resume-in-place tutorial sessions.
- Generic onboarding/coach-mark framework, event bus, controller, target registry, or tutorial data schema.
- Tutorial-specific fields in `GameSession`/campaign save; the neutral `GameSnapshot.placedTowers` projection is the only game-state read change.
- Campaign save migration/version bump.

## Validation

### Pure/store/rules tests

- Fresh `SharedPreferencesFirstMissionGuideStore` loads `false`; `true` and later `false` round-trip under `orion.firstMissionGuide`.
- `game_session_test.dart`: initial snapshot has no `placedTowers`; after placement it contains that tower; after upgrade the snapshot contains the Level-2 replacement. Mutating the session later does not mutate an already-returned snapshot list.
- `firstMissionGuideStepFor` covers: initial build cell, selected cell, tower created, active Wave 1 (no callout), Wave-2 build upgrade, pre-upgraded skip, first module draft, acquired module/scanner, and active-wave gaps.
- A snapshot with `placedTowers` non-empty and `selectedCell == null` proves drag/tap need no distinct guide branch.

### Widget tests

`FirstMissionGuideCallout`:

- renders each exact copy and semantics label,
- Skip is present for all steps; Got it only for scanner,
- target/bubble remain inside 360×640 bounds,
- empty overlay space does not absorb a tap supplied to content beneath,
- reduced-motion pumps without pending transition animation.

`FeedbackSettingsSheet`:

- existing feedback toggles/Done behavior stays green,
- Replay Tutorial invokes the provided callback exactly once and shows its queued confirmation.

`test/widget_test.dart` through the real `testGamePage()`:

- fresh guide store + Outpost Alpha shows the build-cell callout,
- selecting a cell advances to the tower-card callout,
- placing by tap advances to Wave; a separate direct-drag case proves drag placement also advances,
- starting Wave 1 removes the callout; after Wave 1 clear the upgrade guidance points at the tower, then at radial Upgrade when selected,
- upgrading satisfies that step,
- deterministic first module draft shows the temporary-module copy,
- choosing a module shows the scanner callout,
- Got it (and a separate start-wave-finalization assertion) persists completion,
- relaunching Alpha with the completed flag shows no callout,
- another stage never shows one,
- Replay Tutorial clears the flag and Alpha shows the first callout again,
- Reset Campaign does not clear a completed flag.

Run the same path at 360×640 with no Flutter overflow and with dock/HUD controls still tappable.

### Regression gates

- `flutter test test/game/game_session_test.dart test/onboarding/ test/widget/first_mission_guide_callout_test.dart test/widget/feedback_settings_sheet_test.dart test/widget_test.dart`
- `flutter test integration_test/app_smoke_test.dart` when the integration target is available in the existing workflow/environment.
- `dart format --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`

## Acceptance mapping

| HPA-412 acceptance | Design |
|---|---|
| Fresh Alpha starts with build guidance | §1–§3 |
| Tap + drag placement both advance | §2, validation |
| Wave / upgrade / first module / scanner sequence | §2–§3 |
| Reuses snapshot-only UI flow | §2 (`placedTowers` projection + resolver) |
| Soft guidance; player may act in any order | Outcome, §2–§3 |
| Skip/finish persist; replay clears | §1, §4 |
| Survives Reset Campaign; no save bump | §1 |
| Other stages never show | §2 |
| 360×640, HUD/dock usable, reduced motion | §3, validation |
| Full real-page widget path + smoke regression | §5, validation |
| One PR, no art/SFX work | Out of scope + implementation plan |
