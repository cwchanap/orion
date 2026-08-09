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

The vertical slice therefore extends the existing flow instead of introducing a new game-state machine, event bus, effect-command engine, deterministic protocol, or persistence model.

## Goal

Ship six temporary Salvage Modules and three one-tap drafts after waves 2, 4, and 6. A selected module affects the remainder of the current run, is visibly understandable after selection, and is cleared on restart or stage exit.

The implementation preserves Orion's current ownership rules:

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
- a seven-stage release-certification or statistical seed-sweep program;
- a tower range-ring rendering subsystem.

## Approaches considered

### A. Store acquired module IDs and resolve their effects through one pure rules step — selected

`GameSession` stores acquired module IDs and the current offer. `TowerStatsResolver` receives those IDs and applies `RunModuleRules` after campaign and stage modifiers. Immediate economy effects are applied by `GameSession` when selection succeeds.

This is preferred because every resolution starts from `GameBalance`, so existing and newly placed towers are consistent and repeated refreshes cannot compound modifiers accidentally.

### B. Mutate live `TowerComponent.stats` directly when a card is selected — rejected

This is initially smaller but creates two correctness paths: already-existing towers are mutated while newly placed towers must reconstruct previous module effects. Repeated refreshes can also compound multipliers.

### C. Introduce a generic modifier/effect framework — rejected

A generic registry, semantic event bus, or command graph could support future triggered modules, but none of the six vertical-slice modules require it. Add a new rule seam only when a later accepted module has concrete player value that cannot fit the existing stat/economy pipeline.

## Module domain and single-source tuning

Create `lib/game/modules/run_module.dart`.

### IDs and affinity

```dart
enum RunModuleId {
  heavyCaliber,
  overclockRelay,
  longSight,
  emergencySalvage,
  cryoReservoir,
  rocketFusing,
}

enum RunModuleAffinity {
  universal('Universal'),
  cryo('Cryo'),
  rocket('Rocket');

  const RunModuleAffinity(this.label);
  final String label;
}
```

### Definition owns tuning

All player-facing magnitudes live in `RunModuleDefinition`. Do not repeat numeric tuning inside `RunModuleRules` or `GameSession`.

```dart
final class RunModuleDefinition {
  const RunModuleDefinition({
    required this.id,
    required this.title,
    required this.affinity,
    this.damageMultiplier = 1,
    this.fireIntervalMultiplier = 1,
    this.rangeMultiplier = 1,
    this.splashRadiusMultiplier = 1,
    this.slowDurationBonus = 0,
    this.immediateGold = 0,
  });

  final RunModuleId id;
  final String title;
  final RunModuleAffinity affinity;
  final double damageMultiplier;
  final double fireIntervalMultiplier;
  final double rangeMultiplier;
  final double splashRadiusMultiplier;
  final double slowDurationBonus;
  final int immediateGold;

  String get effectText;
}
```

`effectText` is derived from these fields for the six known module IDs so displayed percentages/gold cannot drift from applied math. The formatter remains local to the module domain; it is not a generalized localization or balance-description framework.

Initial tuning:

| Module | Definition values | Affinity |
| --- | --- | --- |
| Heavy Caliber | `damageMultiplier: 1.20`, `fireIntervalMultiplier: 1.10` | Universal |
| Overclock Relay | `fireIntervalMultiplier: 0.85`, `damageMultiplier: 0.92` | Universal |
| Long Sight | `rangeMultiplier: 1.15` | Universal |
| Emergency Salvage | `immediateGold: 90` | Universal |
| Cryo Reservoir | `slowDurationBonus: 0.60` | Cryo |
| Rocket Fusing | `splashRadiusMultiplier: 1.25`, `damageMultiplier: 0.90` | Rocket |

There are four universal modules, so a draft can remain viable even if tower-affinity eligibility changes later.

### Composition

Apply acquired stat modules in catalog order after existing stage resolution:

```text
GameBalance base
→ CampaignModifiers
→ StageModifierRules
→ RunModuleRules
```

`RunModuleRules` reads magnitudes from each definition. It does not own hard-coded balance numbers. Multiplicative effects compose multiplicatively; additive slow duration applies once because acquired IDs are unique. Emergency Salvage has neutral stat fields and only an immediate economy effect.

## Offer model and picker

Create an immutable `RunModuleOffer`:

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

The session stores the exact offer. Snapshot rebuilding, resizing, pausing, and foregrounding only re-project that stored value.

Use a tiny injectable picker under `lib/game/rules/module_offer_picker.dart`:

```dart
abstract interface class ModuleOfferPicker {
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count});
}
```

Production uses ordinary `dart:math Random`; tests inject scripted choices. No run seed, algorithm version, hash ranking, prior-offer history, or cross-platform byte-identity contract is introduced.

If fewer than three eligible candidates exist, throw `StateError`. With the fixed six-module catalog this is a developer-authored invariant failure, not a player recovery flow.

## Eligibility

Eligibility is pure and deliberately small:

1. exclude already acquired IDs;
2. universal modules are eligible;
3. Cryo-affinity modules are eligible when Cryo is unlocked;
4. Rocket-affinity modules are eligible when Rocket is unlocked.

"Currently buildable" means unlocked for current wave progression, not affordable with current gold. Unselected cards may reappear later. No complete offer-history structure is stored.

## Session state and lifecycle

Add run-only state to `GameSession`:

```dart
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _completedModuleDrafts = 0;
int _nextModuleOfferId = 1;
```

`_nextModuleOfferId` remains monotonic across `restart()` on the same session. Restart clears acquired modules, pending offer, and completed draft count but does not reuse old offer IDs.

### Draft schedule

`finishActiveWave()` remains the only opening boundary. After `_waveIndex` increments:

- terminal mission → enter `won`, no draft;
- otherwise enter `build`;
- completed wave count 2, 4, or 6 → generate and store one offer.

`GameSession.snapshot()` never invokes the picker.

### Selection

```dart
bool selectRunModule({
  required int offerId,
  required RunModuleId moduleId,
});
```

Selection succeeds only when the pending offer exists, IDs match, the module was offered, and it is not already acquired.

On success:

1. append the module ID;
2. read `runModuleDefinition(moduleId).immediateGold` and add it once when non-zero;
3. clear the pending offer;
4. increment completed drafts;
5. return `true`.

Stale, duplicate, and non-offered selection returns `false` with no mutation.

## Authoritative intermission gate

A pending offer remains `GamePhase.build`; do not add a fifth phase.

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Use it for placement, upgrade, specialization, sale, targeting-mode changes, and manual/automatic `startWave()`.

Presentation-layer blocking is secondary. Direct calls still fail closed.

When the game layer sees an action rejected specifically because a draft is pending, it should publish **`Choose a Salvage Module first.`** rather than the generic build-phase denial. Reuse the existing failure enums; do not add a module-specific `PlacementFailure`.

## Snapshot projection and player-visible feedback

Extend `GameSnapshot` with:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
final TowerStats? selectedTowerStats;
```

`GameSession.snapshot()` already receives the selected `PlacedTower`; when non-null it resolves `selectedTowerStats` using the same pipeline as combat:

```dart
TowerStatsResolver.resolve(
  selectedTower,
  campaignModifiers: campaignModifiers,
  stageModifiers: stage.modifiers,
  runModules: _acquiredRunModules,
)
```

This is intentionally a snapshot projection rather than calling `TowerStatsResolver` from Flutter. It fixes the product-observation gap without moving rule calculation into widgets.

`canStartWave` becomes false while a draft is pending.

### Why this feedback is part of the slice

The experiment asks whether selected modules are noticeable. Emergency Salvage is naturally visible in gold, but Long Sight is hard to perceive without any current range readout. Orion's selected-tower UI currently shows level/specialization and action costs, not resolved combat stats.

The slice therefore adds a compact selected-tower summary using `snapshot.selectedTowerStats`, showing at least:

- Damage;
- Fire interval;
- Range;
- type-relevant secondary value when present (`Slow` duration for Cryo or `Splash` radius for Rocket).

This makes Long Sight and the universal damage/cadence trade-offs inspectable without adding a range-ring renderer.

The acquired-module strip also shows both module title and effect text (compact two-line chip/card or tooltip/details presentation), so the player has a post-draft reminder of what changed.

## Runtime stat integration

Create `lib/game/rules/run_module_rules.dart` with two responsibilities:

1. eligibility for the current unlocked tower set;
2. applying definition-owned stat fields to an already campaign/stage-resolved `TowerStats`.

Extend `TowerStats.copyWith` only with fields used here:

```dart
double? range,
double? fireInterval,
double? splashRadius,
```

`TowerStatsResolver.resolve` gains:

```dart
Iterable<RunModuleId> runModules = const []
```

and applies `RunModuleRules` after stage modifiers.

`TowerComponent` stores the current immutable module list. `updateRunModules(...)` replaces it and re-resolves from the current `PlacedTower`; `updateTower(...)` continues to use the stored module list after upgrades/specializations.

`OrionDefenseGame` passes acquired IDs to newly created towers and refreshes every existing tower after successful selection.

## OrionDefenseGame pacing integration

Add:

```dart
void selectRunModule(int offerId, RunModuleId moduleId)
```

On success:

1. refresh existing towers;
2. start a fresh auto-start countdown if auto-start is enabled;
3. publish the snapshot.

When a draft opens:

- `_autoStartCountdownRemaining = null`;
- preserve `_autoStartEnabled`;
- do not start a replacement countdown.

Both pacing helpers explicitly guard pending offers:

- `_tickAutoStartCountdown(...)` clears/ignores countdown state when a module offer is pending;
- `_startAutoStartCountdownIfNeeded()` requires no pending offer.

This duplicates the session's authoritative `startWave()` guard intentionally at the pacing boundary so hidden countdown state cannot produce confusing feedback.

`onTapDown` returns early while an offer is pending so board selection cannot change beneath the modal intermission.

Pause and speed values are preserved; there is no active combat during the draft.

## UI design

Create `lib/game/ui/run_module_draft_panel.dart` rather than adding the complete feature UI to `orion_game_page.dart`.

The file contains:

- `RunModuleDraftPanel` — full-screen blocking intermission;
- `AcquiredRunModuleStrip` — compact read-only reminder including title + effect.

### Draft panel

`OrionGamePage` inserts the panel in the existing stage `Stack` above gameplay controls and below terminal end-state UI.

On a 360×640 surface it uses a scroll-safe vertical list of exactly three cards. Each card shows title, one-sentence effect, and affinity. Header copy is `Salvage Module N of 3`.

One tap calls `game.selectRunModule(offer.offerId, id)`. The session remains the one-shot guard; the widget owns no gameplay state.

### Acquired strip and selected tower summary

The acquired strip sits below the HUD and is hidden when empty. Each acquired entry includes its title and effect reminder.

When a tower is selected, `_TowerSummary` receives resolved `TowerStats` from the snapshot and displays the compact combat values described above. Existing upgrade/specialization costs may use the same resolved `TowerStats`; module fields do not alter costs.

No UI code calculates module magnitudes or eligibility.

## Test fixture strategy

The draft schedule is multi-wave, while many existing tests use one-wave custom stages. Add one small shared test helper under `test/game/game_test_fixtures.dart`:

```dart
StageDefinition stageWithWaveCount(int count)
```

It returns a valid custom stage with `count` empty waves and zero clear bonuses, suitable for deterministic session/orchestration tests.

Session tests may add a file-local `completeWave(session)` helper. Flame tests drive the empty-wave fixture through the real `OrionDefenseGame.update` path so draft opening and auto-start behavior are tested at the actual orchestration boundary rather than by exposing private session internals.

This is test support only, not a production abstraction.

## Testing strategy

### Catalog and picker

- fixed six IDs and initial definition magnitudes;
- effect text reflects definition-owned numbers;
- random picker returns distinct candidates without mutating input;
- insufficient candidate count throws.

### Pure rules

- universal/Cryo/Rocket eligibility;
- Heavy Caliber exact math;
- Overclock Relay exact math, including interval direction;
- Heavy Caliber + Overclock Relay composition (`damage × 1.20 × 0.92`, `fireInterval × 1.10 × 0.85`);
- Long Sight;
- Cryo-only and Rocket-only effects;
- empty module list preserves prior resolver output;
- campaign/stage values are resolved before run modules.

### Session

- drafts after waves 2/4/6 and nowhere else;
- same stored offer across repeated snapshots;
- acquired exclusion and distinct cards;
- valid selection once;
- stale/duplicate/non-offered selections no-op;
- Emergency Salvage reward comes from its definition and applies once;
- build actions and wave starts fail while pending;
- `selectedTowerStats` reflects acquired modules;
- restart clears temporary state but offer IDs remain monotonic.

### Flame orchestration

- auto-start countdown is cleared when draft opens;
- both countdown helpers remain inert while pending;
- valid selection starts a fresh full countdown;
- existing tower component stats refresh;
- towers placed afterward inherit modules;
- direct rejected action during a pending draft surfaces `Choose a Salvage Module first.`;
- board taps do not change selection under the modal state.

### Widget

At 360×640:

- header and exactly three cards fit/scroll without overflow;
- card title/effect/affinity render;
- callback fires once for a tapped card;
- acquired entries include effect reminders;
- selected tower summary displays resolved damage/fire interval/range and a relevant secondary stat;
- empty acquired strip stays hidden.

### Human validation

Play Stage 1 and one later main-path stage at 1×. Record:

1. draft comprehension;
2. pacing impact;
3. dead/mandatory choice observed;
4. selected-module effect noticeability.

If a balance value is changed after playtesting, edit the definition in `run_module.dart`, update the exact-value test, and rerun focused/full checks. No rules/copy hunting across multiple files.

## Acceptance criteria

- [ ] A normal mission presents exactly one stable three-card draft after waves 2, 4, and 6.
- [ ] Pending drafts authoritatively block all build mutations and wave starts.
- [ ] Stale/non-offered/duplicate selections do not mutate state.
- [ ] Acquired modules are unique and excluded from later offers.
- [ ] Existing and newly placed towers use base → campaign → stage → run-module resolution.
- [ ] Module tuning magnitudes have one source of truth in the catalog definitions.
- [ ] Emergency Salvage applies its definition-owned reward once.
- [ ] Auto-start cannot tick or start behind an intermission and resumes with a fresh full countdown.
- [ ] Player-facing draft cards and acquired reminders explain each selected effect.
- [ ] Selected-tower UI displays resolved combat stats from `GameSnapshot`, making Long Sight and universal stat trade-offs inspectable.
- [ ] Restart and stage exit discard run-only module state; no campaign save migration occurs.
- [ ] Stage 1 and one later-stage human run are recorded before catalog/progression expansion.
- [ ] Focused tests, formatting, analysis, and full `flutter test` pass during implementation.
