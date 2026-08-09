# HPA-527 Salvage Module Vertical Slice Design

## Context

HPA-527 is the first implementation task in Orion's simplified reward-loop roadmap. Its purpose is not to build a reusable roguelite framework. It is to answer one product question quickly: **do three small mid-mission upgrade choices make an eight-wave Orion mission more fun and replayable?**

The current codebase already has the seams this feature needs:

- `GameSession` owns mutable mission rules, economy, tower state, wave progression, and authoritative phase validation.
- `GameSession.finishActiveWave()` is the single transition that knows a wave has completed.
- `GameSnapshot` is the immutable projection consumed by Flutter UI.
- `TowerStatsResolver` already resolves runtime tower stats in the order base → campaign → stage.
- `TowerComponent` re-resolves stats when its `PlacedTower` changes.
- `OrionDefenseGame` owns Flame orchestration, pacing, component refresh, and snapshot publication.
- `OrionGamePage` renders the stage from `GameSnapshot` and already uses a top-level `Stack` for HUD, bottom controls, and terminal overlays.

That means the vertical slice should extend the existing flow instead of introducing a new game-state machine, event bus, effect-command engine, deterministic protocol, or persistence model.

## Goal

Ship six temporary Salvage Modules and three one-tap drafts after waves 2, 4, and 6. A selected module affects the remainder of the current run, is visible in the mission UI, and is cleared on restart or stage exit.

The implementation must preserve Orion's current ownership rules:

- rules and run state remain outside widgets;
- UI consumes immutable snapshot data;
- Flame components render resolved values rather than deciding module eligibility;
- stat effects reuse `TowerStatsResolver`;
- economy effects reuse `GameSession`.

## Non-goals

This slice intentionally does **not** include:

- boss-blueprint progression;
- Mission Report changes;
- Codex module pages;
- sound, haptics, screen shake, or feedback settings;
- module rarity, rerolls, decks, inventories, upgrades, or discard mechanics;
- shareable seeds or seeded replay;
- versioned draft algorithms, hashes, fingerprints, or canonical serialization;
- persistent run history or mid-run save/resume;
- generic semantic combat events, generated attacks, recursion protection, or per-event cap infrastructure;
- a seven-stage release-certification or statistical seed-sweep program.

## Approaches considered

### A. Store acquired module IDs and resolve their effects through one pure rules step — selected

`GameSession` stores acquired module IDs and the current offer. `TowerStatsResolver` receives those IDs and applies `RunModuleRules` after campaign and stage modifiers. Immediate economy effects are applied by `GameSession` when selection succeeds.

**Advantages**

- Reuses the existing stat pipeline.
- Existing and newly placed towers resolve the same way.
- Re-resolving cannot accidentally compound modifiers because every calculation starts from `GameBalance`.
- Module definitions remain small and declarative.
- Easy to test without Flame or Flutter.

**Cost**

- `TowerStats.copyWith` needs three additional fields used by this slice.
- `TowerComponent` needs to carry the current acquired module IDs when resolving stats.

This is the preferred balance of simplicity and maintainability.

### B. Mutate live `TowerComponent.stats` directly when a card is selected

This is initially the smallest code diff, but it creates two correctness problems: repeated refreshes can compound multipliers, and towers placed after the selection need a separate path to reconstruct prior effects. Avoid this approach.

### C. Introduce a generic modifier/effect framework

A generic effect registry, typed event routing, or command graph could support future triggered modules, but none of the six vertical-slice modules require it. Building that framework now would delay the product experiment and create speculative abstractions. Defer until an accepted module actually cannot fit the existing stat/economy seams.

## Module domain

Create a focused module domain file at `lib/game/modules/run_module.dart`.

### IDs and affinity

Use enums because modules are run-only and are not persisted:

```dart
enum RunModuleId {
  heavyCaliber,
  overclockRelay,
  longSight,
  emergencySalvage,
  cryoReservoir,
  rocketFusing,
}

enum RunModuleAffinity { universal, cryo, rocket }
```

`RunModuleDefinition` contains only player-facing/catalog metadata:

```dart
final class RunModuleDefinition {
  const RunModuleDefinition({
    required this.id,
    required this.title,
    required this.effectText,
    required this.affinity,
  });

  final RunModuleId id;
  final String title;
  final String effectText;
  final RunModuleAffinity affinity;
}
```

The catalog is a fixed ordered list plus a lookup helper. Do not put executable closures in definitions.

### Initial tuning

These values are intentionally simple and may be adjusted from the two required human playtests without changing architecture:

| Module | Initial effect | Affinity |
| --- | --- | --- |
| Heavy Caliber | `damage × 1.20`, `fireInterval × 1.10` | Universal |
| Overclock Relay | `fireInterval × 0.85`, `damage × 0.92` | Universal |
| Long Sight | `range × 1.15` | Universal |
| Emergency Salvage | gain `90` gold immediately | Universal |
| Cryo Reservoir | `slowDuration + 0.60s` | Cryo |
| Rocket Fusing | `splashRadius × 1.25`, `damage × 0.90` | Rocket |

There are four universal modules, so a draft can always remain useful even if future tower-affinity eligibility becomes narrower. Cryo and Rocket are both unlocked from wave 1 today, but eligibility is still expressed explicitly rather than relying on that fact.

### Composition

Apply acquired stat modules in catalog order after existing stage resolution:

```text
GameBalance base
→ CampaignModifiers
→ StageModifierRules
→ RunModuleRules
```

Multiplicative effects compose multiplicatively. Additive `Cryo Reservoir` applies once because acquired IDs are unique. `Emergency Salvage` has no tower-stat effect.

## Offer model and picker

Create `RunModuleOffer` in the module domain:

```dart
final class RunModuleOffer {
  RunModuleOffer({
    required this.offerId,
    required this.draftNumber,
    required List<RunModuleId> moduleIds,
  }) : moduleIds = List.unmodifiable(moduleIds);

  final int offerId;
  final int draftNumber;
  final List<RunModuleId> moduleIds;
}
```

The session stores the immutable offer instance. Snapshot rebuilding, resizing, pausing, and foregrounding only re-project that stored offer; they never invoke the picker.

Use a tiny injectable picker under `lib/game/rules/module_offer_picker.dart`:

```dart
abstract interface class ModuleOfferPicker {
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count});
}
```

Production uses an ordinary `dart:math Random` implementation that shuffles a candidate copy and takes three. Tests inject a fixed picker.

No run seed, algorithm version, hash ranking, prior-offer history, or cross-platform byte-identity contract is introduced.

If fewer than three eligible candidates exist, throw `StateError`. With the fixed six-module catalog and its four universal entries this represents a developer-authored invariant failure, not a recoverable player state. Unit tests guard the invariant instead of adding a production recovery UI.

## Eligibility

Eligibility is pure and small:

1. Exclude already acquired module IDs.
2. Universal modules are eligible.
3. Cryo-affinity modules are eligible when Cryo is in `GameSession.unlockedTowerTypes`.
4. Rocket-affinity modules are eligible when Rocket is in `GameSession.unlockedTowerTypes`.

"Currently buildable" means unlocked for the current wave progression, not currently affordable. Gold should not make a future-useful card disappear.

Unselected cards may reappear in later offers. No complete offer-history structure is stored.

## Session state and lifecycle

Add run-only state to `GameSession`:

```dart
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _completedModuleDrafts = 0;
int _nextModuleOfferId = 1;
```

Expose immutable getters for acquired modules and the pending offer.

`_nextModuleOfferId` remains monotonic across `restart()` on the same `GameSession`. Restart clears acquired modules, pending offer, and completed draft count, but does not reuse old offer IDs. This makes old callbacks unable to match a later offer accidentally without introducing a full run-identity object.

### Draft schedule

`finishActiveWave()` remains the only draft-opening boundary.

After the current wave is accounted for and `_waveIndex` increments:

- if the mission is complete, enter `won` and open no draft;
- otherwise enter `build`;
- when the completed wave count is exactly 2, 4, or 6, generate and store one offer.

`GameSession.snapshot()` never generates offers.

### Selection

Add:

```dart
bool selectRunModule({
  required int offerId,
  required RunModuleId moduleId,
});
```

A selection succeeds only when:

- there is a pending offer;
- `offerId` matches that offer;
- the module is one of the three offered IDs;
- the module is not already acquired.

On success:

1. append the module ID to acquired modules;
2. apply the one-time `Emergency Salvage` gold reward when selected;
3. clear the pending offer;
4. increment the completed draft count;
5. return `true`.

Duplicate, stale, or non-offered selections return `false` with no mutation.

## Authoritative intermission gate

A pending offer is still `GamePhase.build`; do not add a fifth phase.

Add one private/session-level predicate equivalent to:

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Use it for:

- placement validation;
- upgrade;
- specialization;
- sale;
- targeting-mode changes;
- manual/automatic `startWave()`.

This is the correctness boundary. Widget disabling is only presentation.

## Snapshot projection

Extend `GameSnapshot` with immutable module data:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
```

`game_models.dart` may import `modules/run_module.dart`; the module domain deliberately does not import `game_models.dart`, avoiding a circular dependency. Tower affinity is therefore represented by `RunModuleAffinity`, with the rules layer mapping that affinity to `TowerType`.

Update:

```dart
bool get canStartWave =>
    phase == GamePhase.build && pendingRunModuleOffer == null;
```

No separate module view model is needed for six static definitions; UI may map immutable IDs to the read-only catalog helper for title/effect copy.

## Runtime stat integration

Create `lib/game/rules/run_module_rules.dart` with two responsibilities:

1. determine whether a definition is eligible for the current unlocked tower set;
2. apply acquired tower-stat effects to an already campaign/stage-resolved `TowerStats`.

Extend `TowerStats.copyWith` only with fields used by the vertical slice:

```dart
double? range,
double? fireInterval,
double? splashRadius,
```

Do not generalize `copyWith` to every `TowerStats` field.

Extend `TowerStatsResolver.resolve` with:

```dart
Iterable<RunModuleId> runModules = const []
```

and apply `RunModuleRules.applyTowerStats(...)` after `StageModifierRules.effectiveTowerStats(...)`.

`TowerComponent` stores the current immutable run-module list alongside existing campaign/stage modifiers. Add `updateRunModules(...)` to replace the list and re-resolve `stats` from the current `PlacedTower`. `updateTower(...)` continues to re-resolve with the stored module list.

`OrionDefenseGame` passes current acquired IDs when creating a new tower component. After a successful module selection it calls `updateRunModules` for every existing tower component. This keeps old and newly placed towers consistent without mutating stats incrementally.

## OrionDefenseGame pacing integration

Add a small public bridge:

```dart
void selectRunModule(int offerId, RunModuleId moduleId)
```

On successful session selection:

1. refresh all existing tower components;
2. start a fresh auto-start countdown if auto-start is enabled;
3. publish the updated snapshot.

When `_finishWaveIfComplete()` opens a pending offer:

- set `_autoStartCountdownRemaining = null`;
- preserve `_autoStartEnabled`;
- do not call `_startAutoStartCountdownIfNeeded()`.

When the player selects a module, `_startAutoStartCountdownIfNeeded()` starts the normal full three-second countdown from scratch.

Also make `_tickAutoStartCountdown()` and `_startAutoStartCountdownIfNeeded()` respect `snapshot/session pending offer` through `GameSession.startWave()` and an explicit pending check. No hidden countdown time accrues during the intermission.

`onTapDown` should return early while an offer is pending so the board selection highlight does not change beneath the modal intermission.

Pause and speed values are preserved but need no special intermission controls; there is no active combat while the offer is pending.

## UI design

Create `lib/game/ui/run_module_draft_panel.dart` rather than adding the complete feature UI to the already-large `orion_game_page.dart`.

The file contains two small widgets:

- `RunModuleDraftPanel` — blocking full-screen intermission for a pending offer;
- `AcquiredRunModuleStrip` — compact read-only chip list.

### Draft panel

`OrionGamePage` inserts the panel in the stage `Stack` above gameplay controls and below the terminal end-state overlay:

```dart
if (snapshot.pendingRunModuleOffer != null)
  Positioned.fill(
    child: RunModuleDraftPanel(...),
  ),
```

The panel uses an opaque-enough `Material` barrier so taps do not reach Flame. On 360×640 it uses a scroll-safe vertical column of exactly three `FilledButton`/card controls.

Each card shows:

- module title;
- one-sentence effect;
- `Universal`, `Cryo`, or `Rocket` affinity.

Header copy is `Salvage Module N of 3`.

One tap calls `game.selectRunModule(offer.offerId, id)`. The session is the final one-shot guard; the widget does not keep independent gameplay state.

### Acquired strip

Show acquired modules below the HUD using compact chips/titles. Hide the strip when empty. It is `IgnorePointer`/read-only and should not cover the primary board area more than the existing HUD stack already does.

## Restart and route exit

`GameSession.restart()` clears:

- acquired module IDs;
- pending offer;
- completed draft count.

It preserves only the monotonic next offer ID.

Returning to the map already discards the `OrionDefenseGame` instance, so run-only module state dies with that session. No campaign persistence change is required.

App background/foreground with the process alive naturally preserves the offer because it is ordinary in-memory session state. No process-death resume is added.

## Testing strategy

Follow existing test locations and style.

### Pure rules

- `test/game/run_module_rules_test.dart`
  - eligibility for universal/Cryo/Rocket affinity;
  - exact initial stat modifiers;
  - composition of multiple acquired modules;
  - non-matching towers remain unaffected.
- `test/game/module_offer_picker_test.dart`
  - returns requested distinct count from candidates;
  - does not mutate caller list;
  - fails clearly when fewer than three candidates exist.
- `test/game/tower_stats_resolver_test.dart`
  - proves order base → campaign → stage → run module;
  - proves no-module output remains unchanged.

### Session

Extend `test/game/game_session_test.dart` for:

- drafts after waves 2, 4, and 6 only;
- stable stored offer across repeated snapshots;
- acquired exclusion and no duplicate cards;
- stale/duplicate/non-offered selection rejection;
- immediate Emergency Salvage gold applied exactly once;
- placement, upgrade, specialization, sale, targeting, and wave start blocked while pending;
- restart clears temporary module state and does not reuse offer IDs.

### Game orchestration

Extend `test/game/orion_defense_game_test.dart` for:

- auto-start countdown clears when a draft opens;
- successful selection begins a fresh full countdown;
- existing tower components refresh after stat-module selection;
- towers placed after selection receive the same run modifiers.

### Widget

Add `test/widget/run_module_draft_panel_test.dart` for:

- 360×640 layout without overflow;
- exactly three visible/selectable cards;
- header draft number and affinity/effect copy;
- acquired module strip appears after selection;
- modal panel prevents ordinary controls from being the active interaction surface.

No platform build matrix, thousand-seed sweep, or new integration-test infrastructure is required.

## Human validation

Before implementation PR completion, play:

1. Stage 1 at 1×;
2. one later campaign stage at 1×.

Record concise observations in the implementation PR:

- whether each draft was understandable in a few seconds;
- whether the three pauses improved mission rhythm or felt disruptive;
- whether any module was obviously dead or mandatory;
- whether the selected modules were noticeable during play;
- any obvious tuning adjustment made to the six constants.

The purpose is product validation, not formal balance evidence.

## Acceptance criteria

- [ ] A normal eight-wave mission produces one stable three-card offer after waves 2, 4, and 6.
- [ ] Offers are stored in session state and are never regenerated by snapshot/UI lifecycle work.
- [ ] Acquired modules never reappear; one offer contains no duplicate IDs.
- [ ] Selection is one tap, applies exactly once, and stale/non-offered callbacks do nothing.
- [ ] A pending offer authoritatively blocks all build mutations and wave starts while remaining in `GamePhase.build`.
- [ ] Auto-start pauses for the intermission and restarts from the full countdown after selection.
- [ ] Existing and newly placed towers resolve acquired module effects through base → campaign → stage → run-module ordering.
- [ ] Emergency Salvage grants its one-time gold only when selected.
- [ ] Restart and map exit clear all temporary module state.
- [ ] Draft UI and acquired-module strip are snapshot-driven and fit 360×640.
- [ ] No-module behavior is unchanged.
- [ ] Stage 1 and one later stage receive a short human 1× product check before implementation completion.
- [ ] `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, and full `flutter test` pass.
