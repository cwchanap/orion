# HPA-527 Salvage Module Vertical Slice Design

## Context

HPA-527 is Orion's first implementation task for the simplified reward loop. The goal is to answer one product question quickly: **do three small mid-mission upgrade choices make an eight-wave mission more fun and replayable?**

The existing architecture already provides the necessary seams:

- `GameSession` owns mutable mission rules, economy, tower state, and wave progression.
- `GameSession.finishActiveWave()` is the authoritative wave-completion boundary.
- `GameSnapshot` is the immutable Flutter projection.
- `TowerStatsResolver` already composes base → campaign → stage stats.
- `OrionDefenseGame` owns Flame orchestration and pacing.
- `OrionGamePage` already renders full-screen overlays in the stage `Stack`.

The vertical slice therefore extends existing ownership instead of introducing a new phase system, event bus, deterministic protocol, persistence model, or generic effect engine.

## Goal

Ship six temporary Salvage Modules and one three-card draft after waves 2, 4, and 6. A selected module affects the remainder of the current run, remains understandable after selection, and disappears on restart or stage exit.

The implementation must preserve these boundaries:

- `GameSession` owns run state and authoritative action rules.
- `TowerStatsResolver` remains the pure stat-composition function.
- production Flutter reads immutable snapshot projections only.
- Flame components render/use resolved values but do not decide module eligibility.
- no run-only module data is persisted.

## Non-goals

This slice intentionally does **not** include:

- Mission Report changes;
- boss-blueprint progression or Codex module pages;
- sound, haptics, screen shake, or feedback settings;
- rarity, rerolls, decks, inventories, upgrades, or discard mechanics;
- shareable seeds, seeded replay, algorithm versions, hashes, or fingerprints;
- persistent run history or mid-run save/resume;
- generic combat-event routing, generated attacks, recursion infrastructure, or cap frameworks;
- a tower range-ring renderer;
- a seven-stage release-certification or statistical seed-sweep program;
- expanding the catalog beyond six modules before the vertical slice is playtested.

## Review resolution

The second review identified several concrete issues in the previous draft. The accepted changes are:

1. **Affinity relevance:** Cryo and Rocket both unlock at wave 1, so checking only `unlockedTowerTypes` cannot filter their cards. Affinity cards are now *preferred* only when that tower family is actually placed. Unlocked-but-unplaced affinity cards are fallback/pivot candidates only when fewer than three preferred candidates remain.
2. **One stat-resolution entry point:** `GameSession.resolveTowerStats(PlacedTower)` becomes the session-aware wrapper over `TowerStatsResolver`. `TowerComponent` receives that resolver callback instead of caching campaign, stage, and run modifier inputs independently. Snapshot selected-tower stats use the same method.
3. **Damage semantics:** global damage trade-offs affect `damage`, `corrosionDamagePerSecond`, and `droneDamage`. This keeps Heavy Caliber and Overclock Relay meaningful for Nanite and Drone Bay rather than silently changing only their launcher interval.
4. **Acquired-module reminder:** effect text is rendered inline. Tooltips are removed because the existing HUD column is inside `IgnorePointer` and tooltip-only copy is a poor touch-first affordance.
5. **Typed placement denial:** add `PlacementFailure.pendingModuleDraft`. Bool-returning action paths keep their existing APIs and share one game-layer helper for draft-blocked feedback.
6. **Test-fixture reuse:** extract the existing `_emptyWaveStage` helper from `orion_defense_game_test.dart` into a shared `test/game/game_test_fixtures.dart` helper rather than creating a duplicate.
7. **Draft counter simplification:** keep `RunModuleOffer.draftNumber` because the UI renders `Salvage Module N of 3`, but derive it from the configured draft schedule (`GameBalance.moduleDraftWaves.indexOf(wave) + 1`) so the displayed number stays in lockstep with the eligibility list. Do not store `_completedModuleDrafts`.
8. **Commit playability:** session lifecycle/stat plumbing lands before the authoritative gate; the gate and selectable UI land together so no committed step soft-locks the game after wave 2.
9. **Snapshot compatibility:** all new `GameSnapshot` fields default (`pendingRunModuleOffer = null`, `acquiredRunModules = const []`, `selectedTowerStats = null`) so existing literal test snapshots continue to compile.

Two review suggestions are intentionally **not** adopted:

- **Variable-size drafts:** the vertical slice contract remains exactly three cards. If preferred candidates are short, the session fills from unlocked affinity pivots, then from remaining non-acquired definitions as a final configuration-safe fallback. The player never receives a two-card draft and wave completion never needs to throw for catalog shortage.
- **Expanding to 8–9 modules now:** six modules remain the smallest experiment. Draft 3 has lower pool entropy, but still presents three actual choices; if playtests show repetition, HPA-526 is explicitly the catalog-expansion ticket.

`RunModuleAffinity` also remains a tiny module-domain enum rather than using `TowerType?` directly. Three affinity values are cheaper and clearer than splitting the catalog solely to remove that enum.

## Module domain and single-source tuning

The module domain (`RunModuleId`, `RunModuleAffinity`, `RunModuleDefinition`, `runModuleCatalog`, `runModuleDefinition`, `RunModuleOffer`) lives in `lib/game/models/game_models.dart`, the single source of truth for game data and tuning. Colocating it with `GameSnapshot` and `TowerType` keeps one model file and avoids a separate module file that would only re-export the same definitions.

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

All tuning values live on `RunModuleDefinition`. Rules and immediate economy effects read these values rather than duplicating magic numbers.

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

`effectText` derives copy from these fields using the existing formatting helpers in `lib/game/util/format.dart`, keeping tuning and displayed values aligned.

Initial values:

| Module | Definition values | Affinity |
| --- | --- | --- |
| Heavy Caliber | `damageMultiplier: 1.20`, `fireIntervalMultiplier: 1.10` | Universal |
| Overclock Relay | `fireIntervalMultiplier: 0.85`, `damageMultiplier: 0.92` | Universal |
| Long Sight | `rangeMultiplier: 1.15` | Universal |
| Emergency Salvage | `immediateGold: 90` | Universal |
| Cryo Reservoir | `slowDurationBonus: 0.60` | Cryo |
| Rocket Fusing | `splashRadiusMultiplier: 1.25`, `damageMultiplier: 0.90` | Rocket |

## Effect semantics

`RunModuleRules` applies acquired stat definitions after stage resolution:

```text
GameBalance base
→ CampaignModifiers
→ StageModifierRules
→ RunModuleRules
```

For a definition that applies to a tower:

- `damageMultiplier` multiplies `damage`, `corrosionDamagePerSecond`, and `droneDamage`;
- `fireIntervalMultiplier` multiplies the tower's `fireInterval`;
- `rangeMultiplier` multiplies `range`;
- `splashRadiusMultiplier` multiplies `splashRadius`;
- `slowDurationBonus` adds to `slowDuration`.

This makes the universal damage trade-offs truthful across Orion's current damage channels. Drone Bay still uses its existing drone launch/active-drone rules; no module modifies `droneAttackInterval` or invents new combat behavior.

Extend `TowerStats.copyWith` only with the five additional fields needed by this slice: `range`, `fireInterval`, `splashRadius`, `corrosionDamagePerSecond`, and `droneDamage`.

## Offer model and picker

```dart
final class RunModuleOffer {
  RunModuleOffer({
    required this.offerId,
    required this.draftNumber,
    required this.draftTotal,
    required List<RunModuleId> moduleIds,
  }) : moduleIds = List.unmodifiable(moduleIds);

  final int offerId;
  final int draftNumber;
  final int draftTotal;
  final List<RunModuleId> moduleIds;
}
```

The session stores the exact offer. Snapshot rebuilds, resize, pause, and foreground only re-project it.

Use one injectable picker:

```dart
abstract interface class ModuleOfferPicker {
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count});
}
```

Production copies/shuffles candidates with ordinary `dart:math Random`; tests inject scripted results. The picker still requires `candidates.length >= count`, but `GameSession` constructs a pool of at least three before calling it.

No run seed, algorithm version, hash ranking, fingerprint, or complete offer history is added.

## Relevance and candidate policy

Each draft excludes already acquired modules first.

Then build the candidate pool in three tiers, preserving catalog order before the random picker shuffles it:

1. **Preferred:** universal modules plus affinity modules whose tower family is currently placed.
2. **Pivot fallback:** if fewer than three preferred candidates remain, append affinity modules whose tower family is unlocked/buildable in this run.
3. **Configuration-safe fallback:** if still fewer than three remain, append any remaining non-acquired definitions.

The fallback tiers are only used to fill the pool to at least three; they do not create rarity or weighted ranking.

This produces useful behavior with the six-module catalog:

- a no-Cryo/no-Rocket build sees universal cards in early drafts rather than immediate dead affinity cards;
- later, when only two universals remain, one buildable affinity pivot may appear to keep a three-card choice;
- a placed Cryo or Rocket immediately makes its affinity module a preferred candidate.

The player always receives exactly three cards.

## Session state and draft lifecycle

`GameSession` owns:

```dart
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _nextModuleOfferId = 1;
```

No completed-draft counter is stored.

`finishActiveWave()` remains the only draft-opening boundary. After `_waveIndex` increments:

- final mission wave → `won`, no draft;
- otherwise → `build`;
- completed wave 2, 4, or 6 → generate/store one offer if none is already pending.

The offer's displayed number is derived from the configured draft schedule so it stays in lockstep with eligibility:

```dart
draftNumber: GameBalance.moduleDraftWaves.indexOf(_waveIndex) + 1,
```

`GameSession.snapshot()` never invokes the picker.

Selection API:

```dart
bool selectRunModule({required int offerId, required RunModuleId moduleId});
```

Selection succeeds only for the exact current offer and an offered, non-acquired ID. On success:

1. append the ID;
2. add `runModuleDefinition(moduleId).immediateGold` to gold;
3. clear the pending offer;
4. return `true`.

Stale, duplicate, wrong-offer, and non-offered calls return `false` without mutation.

Offer IDs stay monotonic across `restart()` on the same session. Restart clears acquired/pending state but does not reuse old IDs.

## One runtime stat-resolution path

`GameSession` becomes the single session-aware entry point:

```dart
TowerStats resolveTowerStats(PlacedTower tower) {
  return TowerStatsResolver.resolve(
    tower,
    campaignModifiers: campaignModifiers,
    stageModifiers: stage.modifiers,
    runModules: _acquiredRunModules,
  );
}
```

`TowerStatsResolver` remains framework-free and pure; `GameSession.resolveTowerStats` only supplies the active mission inputs.

`TowerComponent` receives a resolver callback:

```dart
typedef TowerStatsProvider = TowerStats Function(PlacedTower tower);
```

It no longer stores `campaignModifiers`, `stageModifiers`, or `runModules`. Constructor initialization and `updateTower(...)` both call the same provider. After module selection, `OrionDefenseGame` refreshes existing components by calling `updateTower(component.placedTower)`; newly placed towers resolve through the same callback automatically.

`DroneComponent` holds a mutable `TowerStats stats` field sourced from its owning tower's resolved stats. Because a damage-affecting module (e.g. `heavyCaliber`) changes `droneDamage`, surviving drones must be refreshed too. `DroneComponent.updateStats(TowerStats)` replaces only the combat stats; the drone's remaining lifetime and attack cooldown continue from their current values so a live drone is not restarted mid-run. After module selection, `OrionDefenseGame` iterates surviving `DroneComponent`s and calls `updateStats(ownerTower.stats)` for each drone whose owning tower still exists. Drones whose owner was sold/removed are left untouched (they expire on their own). Newly launched drones resolve through the owner tower's refreshed stats automatically, so no refresh is needed for them.

`GameSession.snapshot()` uses `resolveTowerStats(selectedTower)` for `selectedTowerStats`, so displayed combat values and active tower values share the same resolution path.

## Snapshot projection

Extend `GameSnapshot` with defaults to preserve existing literal constructors:

```dart
this.pendingRunModuleOffer,
List<RunModuleId> acquiredRunModules = const [],
this.selectedTowerStats,
```

Fields:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
final TowerStats? selectedTowerStats;
```

`acquiredRunModules` is copied to an unmodifiable list.

At the final UI/gating step, `canStartWave` becomes:

```dart
bool get canStartWave =>
    phase == GamePhase.build && pendingRunModuleOffer == null;
```

## Authoritative intermission gate

A pending offer remains `GamePhase.build`; no fifth phase is added.

At the final UI/gating task, add:

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Use it for upgrade, specialization, sale, targeting changes, and `startWave()`.

Placement has a typed distinction:

```dart
enum PlacementFailure {
  invalidPhase,
  pendingModuleDraft,
  ...
}
```

`validatePlacement()` returns `pendingModuleDraft` when build phase is active but a draft is pending.

For bool/null-returning game actions, `OrionDefenseGame` keeps one helper:

```dart
String? _draftBlockMessage() =>
    _session.pendingRunModuleOffer == null
        ? null
        : 'Choose a Salvage Module first.';
```

Existing action-specific copy remains unchanged when no draft is pending.

## Pacing integration

When a draft opens:

- clear `_autoStartCountdownRemaining`;
- preserve `_autoStartEnabled`;
- do not start a replacement countdown.

Both `_tickAutoStartCountdown(...)` and `_startAutoStartCountdownIfNeeded()` explicitly reject pending drafts.

After valid selection, auto-start starts the normal full countdown from scratch.

`onTapDown` returns early while a draft is pending so board selection does not change beneath the modal panel.

## UI design

Create `lib/game/ui/run_module_draft_panel.dart` with:

- `RunModuleDraftPanel` — full-screen blocking intermission;
- `AcquiredRunModuleStrip` — read-only compact reminder.

The draft panel always receives exactly three module IDs and renders three vertically stacked cards at 360×640. Each card shows title, one-sentence effect, and affinity. One tap calls `game.selectRunModule(offer.offerId, id)`; the widget owns no gameplay state.

The acquired strip renders compact **title + short effect text inline**. It requires no pointer interaction and may remain in the existing `IgnorePointer` HUD column.

The selected-tower panel renders `snapshot.selectedTowerStats`:

- damage;
- fire interval;
- range;
- Cryo slow duration or Rocket splash radius when relevant;
- Nanite corrosion DPS or Drone Bay drone damage when relevant.

No range-ring renderer is added.

## Test fixture reuse

The repository already has `_emptyWaveStage({int waveCount = 2})` in `test/game/orion_defense_game_test.dart`, used by the existing auto-start/pacing tests.

Extract it to `test/game/game_test_fixtures.dart` as:

```dart
StageDefinition stageWithWaveCount(int count)
```

Update all existing `_emptyWaveStage(...)` call sites to the shared helper, and reuse it from new session/orchestration tests. Do not leave the private duplicate behind.

## Task sequencing

Keep each committed step runnable:

1. catalog/picker;
2. pure stat rules;
3. session offer/selection state + shared stat-resolution bridge + Flame refresh/pacing, **without** authoritative build/start gating;
4. selectable intermission UI + authoritative gate + player-visible summaries in the **same commit**;
5. verification and human playtests.

This avoids a commit where wave 2 creates an invisible, unselectable draft that permanently blocks normal play.

## Testing strategy

### Catalog/picker

- six definitions and one-source magnitudes;
- effect copy reflects definition values;
- random picker returns three distinct candidates without mutating input;
- direct picker misuse with too-small input is tested, while session candidate construction guarantees that path is not used in production.

### Pure stat rules

- exact Overclock Relay behavior;
- Heavy Caliber × Overclock composition;
- Long Sight;
- Cryo Reservoir only on Cryo;
- Rocket Fusing only on Rocket;
- Heavy/Overclock modify Nanite `corrosionDamagePerSecond` and Drone Bay `droneDamage` as well as ordinary `damage`;
- empty run-module list preserves current behavior;
- campaign/stage values resolve before run modules.

### Session

Using the extracted eight-wave fixture:

- drafts after waves 2/4/6 only;
- `draftNumber` is 1/2/3 derived from `moduleDraftWaves` index;
- stored offer is stable across snapshots;
- early no-affinity builds prefer universal cards;
- pivot fallback still returns exactly three at draft 3;
- acquired exclusion and no duplicate IDs;
- stale/duplicate/non-offered selection no-op;
- Emergency Salvage uses definition-owned reward once;
- `selectedTowerStats` uses the same `resolveTowerStats` path;
- restart clears run-only state while offer IDs remain monotonic.

### Flame

- `TowerComponent` obtains stats only through its provided resolver callback;
- existing towers refresh after module selection;
- newly placed towers inherit the same active modules;
- auto-start countdown clears at draft open and both countdown helpers stay inert while pending;
- selection starts a fresh full countdown;
- board taps do not change selection under an active draft.

### UI/gating

At 360×640:

- exactly three draft cards render title/effect/affinity without overflow;
- acquired reminder shows title + effect inline without relying on tooltips;
- selected tower summary displays resolved combat values;
- placement returns `pendingModuleDraft` while pending;
- upgrade/specialize/sell/retarget/start-wave all fail authoritatively while pending;
- direct blocked actions surface `Choose a Salvage Module first.`;
- existing `GameSnapshot(...)` test literals continue compiling through defaulted fields.

### Human validation

Play Stage 1 and one later main-path stage at 1×. Record only:

1. draft comprehension;
2. pacing impact;
3. dead or mandatory card observed;
4. whether selected effects were noticeable.

If the six-card pool feels repetitive—especially the third draft—record that observation for HPA-526 rather than expanding the vertical slice preemptively.

## Acceptance criteria

- [ ] One stable three-card draft opens after waves 2, 4, and 6 only.
- [ ] Early offers prefer universal/current-build affinity and avoid unnecessary dead cards.
- [ ] Every production draft still contains exactly three cards.
- [ ] Pending drafts block all build mutations and wave starts authoritatively once the selectable UI exists.
- [ ] Stale/non-offered/duplicate selections no-op.
- [ ] Existing and new towers share one session-aware stat-resolution path.
- [ ] Heavy/Overclock affect ordinary, corrosion, and drone damage channels consistently.
- [ ] Tuning has one source of truth in module definitions.
- [ ] Auto-start cannot progress behind a draft and resumes with a fresh countdown after selection.
- [ ] Draft and acquired-module UI explain effects without tooltip-only interaction.
- [ ] Selected-tower UI shows resolved combat stats from `GameSnapshot`.
- [ ] Restart/stage exit discard run-only state; no save migration is added.
- [ ] Stage 1 and one later-stage human run are recorded before catalog expansion.
- [ ] Implementation passes focused tests, format, analyze, and full `flutter test`.
