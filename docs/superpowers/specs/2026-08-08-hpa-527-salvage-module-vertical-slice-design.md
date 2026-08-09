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

## Review decisions

The external review was technically sound on five points and directionally sound on the sixth:

1. **Player-visible feedback:** accepted, but not by calling `TowerStatsResolver` from Flutter. Current `_UpgradePanel` uses raw `GameBalance` stats for action costs and `_TowerSummary` does not display combat stats. The design instead projects resolved selected-tower stats through `GameSnapshot`, keeping production UI snapshot-only. Long Sight becomes inspectable numerically; no range-ring subsystem is added.
2. **Single-source tuning:** accepted. Magnitudes live on `RunModuleDefinition`; rules, immediate gold, and effect copy read those values.
3. **Multi-wave test fixture:** accepted. Add one shared empty-wave stage fixture used by session and Flame orchestration tests.
4. **Overclock/composition coverage:** accepted. Add exact Overclock and Heavy Caliber × Overclock tests.
5. **Auto-start pending guard:** accepted. Guard both `_tickAutoStartCountdown` and `_startAutoStartCountdownIfNeeded`.
6. **Draft-block feedback copy:** accepted. Reuse existing failure enums but publish `Choose a Salvage Module first.` when the game layer knows a draft is pending.

No review item justifies a new phase, event bus, seed protocol, persistence work, or generalized effect architecture.

## Chosen architecture

`GameSession` stores acquired module IDs and the current offer. `TowerStatsResolver` receives acquired IDs and applies `RunModuleRules` after campaign and stage modifiers. Immediate economy effects are applied by `GameSession` when selection succeeds.

This is preferred over mutating live `TowerComponent.stats`: every resolution starts from `GameBalance`, so existing and newly placed towers are consistent and repeated refreshes cannot compound modifiers accidentally.

A generic modifier/effect framework is intentionally deferred. None of the six vertical-slice modules require it.

## Module domain and single-source tuning

Create `lib/game/modules/run_module.dart`.

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

`effectText` derives its numeric copy from these fields and reuses `util/format.dart` so displayed values cannot drift from applied math.

Initial values:

| Module | Definition values | Affinity |
| --- | --- | --- |
| Heavy Caliber | `damageMultiplier: 1.20`, `fireIntervalMultiplier: 1.10` | Universal |
| Overclock Relay | `fireIntervalMultiplier: 0.85`, `damageMultiplier: 0.92` | Universal |
| Long Sight | `rangeMultiplier: 1.15` | Universal |
| Emergency Salvage | `immediateGold: 90` | Universal |
| Cryo Reservoir | `slowDurationBonus: 0.60` | Cryo |
| Rocket Fusing | `splashRadiusMultiplier: 1.25`, `damageMultiplier: 0.90` | Rocket |

Apply acquired stat modules in catalog order:

```text
GameBalance base
→ CampaignModifiers
→ StageModifierRules
→ RunModuleRules
```

`RunModuleRules` reads definition fields rather than owning balance numbers.

## Offer model and picker

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

The session stores the exact offer. Snapshot rebuild, resize, pause, and foreground only re-project it.

Use a tiny injectable picker:

```dart
abstract interface class ModuleOfferPicker {
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count});
}
```

Production uses ordinary `dart:math Random`; tests inject scripted choices. No seed/version/hash/history contract.

If fewer than three eligible candidates exist, throw `StateError`; this is a developer-authored invariant failure for the fixed catalog.

## Eligibility

1. Exclude acquired IDs.
2. Universal modules are eligible.
3. Cryo-affinity requires Cryo unlocked.
4. Rocket-affinity requires Rocket unlocked.

Eligibility is based on unlock state, not current affordability. Unselected cards may reappear later. No complete offer history.

## Session state and lifecycle

```dart
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _completedModuleDrafts = 0;
int _nextModuleOfferId = 1;
```

Offer IDs remain monotonic across `restart()` on the same session. Restart clears acquired/pending/completed-draft state but does not reuse IDs.

`finishActiveWave()` is the only draft-opening boundary. After `_waveIndex` increments:

- terminal mission → `won`, no draft;
- otherwise → `build`;
- completed wave count 2, 4, or 6 → generate/store one offer.

`GameSession.snapshot()` never invokes the picker.

Selection API:

```dart
bool selectRunModule({required int offerId, required RunModuleId moduleId});
```

Selection succeeds only for the exact current offer and a non-acquired offered ID. On success, append ID, apply `runModuleDefinition(moduleId).immediateGold`, clear pending offer, increment completed drafts. Stale/duplicate/non-offered calls no-op.

## Authoritative intermission gate

Pending offer remains `GamePhase.build`.

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Use this for placement, upgrade, specialization, sale, targeting changes, and `startWave()`.

When the game layer knows a rejection is caused by a pending draft, publish **`Choose a Salvage Module first.`** rather than generic build-phase copy. Keep existing failure enums.

## Snapshot projection and player-visible feedback

Extend `GameSnapshot` with:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
final TowerStats? selectedTowerStats;
```

When `selectedTower != null`, `GameSession.snapshot()` resolves it with the same combat pipeline:

```dart
TowerStatsResolver.resolve(
  selectedTower,
  campaignModifiers: campaignModifiers,
  stageModifiers: stage.modifiers,
  runModules: _acquiredRunModules,
)
```

Production Flutter reads this projection; it does not call the resolver.

`canStartWave` becomes false while a draft is pending.

The selected-tower panel adds a compact combat summary:

- damage;
- fire interval;
- range;
- Cryo slow duration or Rocket splash radius when applicable.

This makes Long Sight and universal stat trade-offs inspectable without adding a range-ring renderer.

The acquired strip keeps title chips compact and exposes exact effect copy through tooltips.

## Runtime stat integration

Create `RunModuleRules` for only two responsibilities:

1. eligibility;
2. applying definition-owned stat fields to already campaign/stage-resolved `TowerStats`.

Extend `TowerStats.copyWith` only with `range`, `fireInterval`, and `splashRadius`.

`TowerStatsResolver.resolve` gains `Iterable<RunModuleId> runModules = const []` and applies run rules after stage modifiers.

`TowerComponent` stores an immutable current module list. `updateRunModules(...)` re-resolves from its `PlacedTower`; `updateTower(...)` retains those module IDs after upgrades/specialization.

`OrionDefenseGame` passes acquired IDs to newly created towers and refreshes existing towers after selection.

## Pacing integration

`OrionDefenseGame.selectRunModule(int offerId, RunModuleId moduleId)` refreshes towers, starts a fresh auto-start countdown if enabled, and publishes the snapshot.

When a draft opens:

- clear `_autoStartCountdownRemaining`;
- preserve `_autoStartEnabled`;
- do not start a replacement countdown.

Both helpers explicitly guard pending offers:

- `_tickAutoStartCountdown(...)` clears/ignores countdown state while pending;
- `_startAutoStartCountdownIfNeeded()` requires no pending offer.

`onTapDown` returns early during a pending draft so board selection does not change underneath the modal panel.

## UI design

Create `lib/game/ui/run_module_draft_panel.dart` containing:

- `RunModuleDraftPanel` — full-screen blocking intermission;
- `AcquiredRunModuleStrip` — compact title chips with effect tooltips.

The draft panel is inserted in the existing stage `Stack`, uses a scroll-safe vertical layout at 360×640, and shows title/effect/affinity for exactly three cards. One tap calls `game.selectRunModule(offer.offerId, id)`; the widget owns no gameplay state.

The acquired strip sits below the HUD and hides when empty.

`_TowerSummary` renders `snapshot.selectedTowerStats`; upgrade/specialization costs may use the same resolved object because modules do not alter costs.

## Test fixture strategy

Add `test/game/game_test_fixtures.dart` with:

```dart
StageDefinition stageWithWaveCount(int count)
```

It returns a valid custom stage with `count` empty waves and zero clear bonuses. Session tests add a file-local `completeWave(session)` helper. Flame tests drive the empty-wave fixture through the real `OrionDefenseGame.update` path.

## Testing strategy

### Catalog/picker
- six IDs and definition magnitudes;
- effect text reflects definition values;
- picker returns distinct candidates without mutating input;
- insufficient candidates throw.

### Pure rules
- universal/Cryo/Rocket eligibility;
- exact Overclock Relay behavior;
- Heavy Caliber × Overclock composition (`damage ×1.20×0.92`, `fireInterval ×1.10×0.85`);
- Long Sight, Cryo Reservoir, Rocket Fusing;
- empty module list preserves current output;
- campaign/stage values resolve before run modules.

### Session
- drafts after 2/4/6 only;
- stored offer stable across snapshots;
- acquired exclusion/distinct IDs;
- stale/duplicate/non-offered selection no-op;
- Emergency Salvage uses definition-owned reward once;
- authoritative build/start gating;
- `selectedTowerStats` reflects modules;
- restart clears temporary state but ID remains monotonic.

### Flame
- countdown cleared at draft open;
- both countdown helpers inert while pending;
- selection starts fresh full countdown;
- existing/future towers share module effects;
- direct rejected action shows `Choose a Salvage Module first.`;
- board taps ignored under draft.

### Widget
At 360×640:
- exactly three draft cards render title/effect/affinity without overflow;
- acquired title chips expose effect tooltips;
- selected tower summary displays resolved damage/fire/range and relevant secondary stat;
- empty strip stays hidden.

### Human validation
Play Stage 1 and one later main-path stage at 1× and record draft comprehension, pacing impact, dead/mandatory choice, and effect noticeability.

If tuning changes, edit `RunModuleDefinition`, update exact catalog expectations, and rerun focused/full tests. Rules/session/copy should not need numeric edits.

## Acceptance criteria

- [ ] Exactly one stable three-card draft after waves 2, 4, and 6.
- [ ] Pending drafts block all build mutations and wave starts authoritatively.
- [ ] Stale/non-offered/duplicate selections no-op.
- [ ] Acquired modules are unique and excluded from later offers.
- [ ] Existing/new towers use base → campaign → stage → run-module resolution.
- [ ] Tuning has one source of truth in catalog definitions.
- [ ] Emergency Salvage applies its definition-owned reward once.
- [ ] Auto-start cannot tick/start behind draft and resumes with a fresh full countdown.
- [ ] Draft cards and acquired reminders explain effects.
- [ ] Selected-tower UI shows resolved combat stats from `GameSnapshot`.
- [ ] Restart/stage exit discard run-only state; no save migration.
- [ ] Stage 1 and one later-stage human run are recorded before expansion.
- [ ] Focused tests, format, analyze, and full `flutter test` pass during implementation.
