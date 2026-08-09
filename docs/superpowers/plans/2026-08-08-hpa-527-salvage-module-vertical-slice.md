# HPA-527 Salvage Module Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six temporary Salvage Modules with stable three-card drafts after waves 2, 4, and 6, one session-aware tower-stat resolution path, authoritative intermission gating, and a touch-first snapshot-driven UI.

**Architecture:** `GameSession` owns run-only offer/acquired state and exposes `resolveTowerStats(PlacedTower)` as the single session-aware wrapper over the pure `TowerStatsResolver`. `TowerComponent` receives that resolver as a callback instead of caching campaign/stage/run modifier inputs. The first three tasks keep the app runnable without an invisible hard gate; Task 4 lands the selectable UI and authoritative gate together.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- Keep `GamePhase` unchanged; pending draft remains build phase plus a gate.
- Keep exactly six initial modules: Heavy Caliber, Overclock Relay, Long Sight, Emergency Salvage, Cryo Reservoir, Rocket Fusing.
- Keep exactly three cards per production draft.
- Initial values live only on `RunModuleDefinition`: Heavy `damage ×1.20`, `fireInterval ×1.10`; Overclock `fireInterval ×0.85`, `damage ×0.92`; Long Sight `range ×1.15`; Emergency Salvage `+90` gold; Cryo Reservoir `slowDuration +0.60`; Rocket Fusing `splashRadius ×1.25`, `damage ×0.90`.
- Global damage multipliers affect `damage`, `corrosionDamagePerSecond`, and `droneDamage`.
- Drafts open only after completed waves 2, 4, and 6.
- Prefer universal modules and affinity modules for tower families currently placed. Use unlocked affinity modules only as pivot fallback when fewer than three preferred candidates remain.
- Production randomness is ordinary `Random`; tests inject a picker. No seed/version/hash/fingerprint/history protocol.
- Use one monotonic `offerId` for stale callback protection.
- Derive `draftNumber` from completed wave progress; do not store a completed-draft counter.
- Stat order stays base → campaign → stage → run modules.
- No event bus, generic effect engine, persistence migration, Mission Report, blueprint system, Codex module section, audio/haptics, rarity/rerolls/decks, mid-run resume, range-ring subsystem, seed sweep, or seven-stage certification.
- Production Flutter reads snapshot values only; it does not invoke `TowerStatsResolver` or module rules.
- New `GameSnapshot` fields must have defaults so existing literal test snapshots continue to compile.
- Target 360×640 logical pixels.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`, plus two human 1× runs.

## Review Decisions Incorporated

- Replace unlock-only affinity filtering with placed-family preference + buildable pivot fallback.
- Keep exactly three cards; do not change the experiment to variable-size drafts.
- Make `GameSession.resolveTowerStats` the one session-aware resolution path and inject it into `TowerComponent`.
- Apply Heavy/Overclock damage trade-offs to Drone Bay `droneDamage` and Nanite `corrosionDamagePerSecond` as well as ordinary `damage`.
- Render acquired effect copy inline; no tooltip dependency under the HUD `IgnorePointer`.
- Add `PlacementFailure.pendingModuleDraft`; use one `_draftBlockMessage()` helper for bool/null action feedback.
- Extract the existing `_emptyWaveStage` helper instead of duplicating it.
- Keep `RunModuleOffer.draftNumber` because the UI displays it; remove `_completedModuleDrafts` and derive the number from `_waveIndex ~/ 2`.
- Land selectable UI and authoritative gate in the same task so no commit soft-locks the app after wave 2.
- Keep six modules; use HPA-526 for expansion if the third draft feels repetitive in playtest.

## File Map

### Create

- `lib/game/modules/run_module.dart` — module IDs, affinity, single-source definitions, offer value.
- `lib/game/rules/module_offer_picker.dart` — injectable random picker.
- `lib/game/rules/run_module_rules.dart` — pure stat application only.
- `lib/game/ui/run_module_draft_panel.dart` — blocking three-card panel + read-only acquired reminder.
- `test/game/game_test_fixtures.dart` — extracted shared empty-wave stage fixture.
- `test/game/module_offer_picker_test.dart` — catalog/picker tests.
- `test/game/run_module_rules_test.dart` — exact stat-effect tests.
- `test/widget/run_module_draft_panel_test.dart` — 360×640 draft/reminder tests.

### Modify

- `lib/game/models/game_models.dart` — `TowerStats.copyWith`, `PlacementFailure`, defaulted snapshot module/resolved-stat fields, final `canStartWave` gate.
- `lib/game/rules/tower_stats_resolver.dart` — append run-module rules.
- `lib/game/rules/game_session.dart` — offer lifecycle, candidate policy, selection, `resolveTowerStats`, final action gate.
- `lib/game/components/tower_component.dart` — inject one `TowerStatsProvider`; remove cached campaign/stage modifier inputs.
- `lib/game/orion_defense_game.dart` — picker injection, module selection bridge, component refresh, pacing, draft feedback, board-tap blocking.
- `lib/game/ui/orion_game_page.dart` — render intermission, acquired effects, resolved tower summary.
- `test/game/tower_stats_resolver_test.dart` — resolver order/regression tests.
- `test/game/game_session_test.dart` — draft lifecycle/candidate/selection/resolution/gating tests.
- `test/game/orion_defense_game_test.dart` — extract `_emptyWaveStage` call sites; module refresh/pacing/feedback tests.
- `test/widget/sell_button_test.dart` — defaulted snapshot compatibility + resolved summary regression fixture.
- `test/widget_test.dart` — existing literal `GameSnapshot` constructors remain green through defaults; stage-level intermission integration.

---

### Task 1: Add the catalog, single-source tuning, and injectable picker

**Files:**
- Create: `lib/game/modules/run_module.dart`
- Create: `lib/game/rules/module_offer_picker.dart`
- Create: `test/game/module_offer_picker_test.dart`

**Interfaces:**
- Produces `RunModuleId`, `RunModuleAffinity`, `RunModuleDefinition`, `RunModuleOffer`, `runModuleCatalog`, `runModuleDefinition`.
- Produces `ModuleOfferPicker.pick(List<RunModuleId>, {required int count})` and `RandomModuleOfferPicker`.
- `run_module.dart` does not import `game_models.dart`; this avoids a model cycle when `GameSnapshot` later references module IDs/offers.

- [ ] **Step 1: Write the failing catalog/picker tests**

Create `test/game/module_offer_picker_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/modules/run_module.dart';
import 'package:orion/game/rules/module_offer_picker.dart';

void main() {
  test('catalog exposes six single-source module definitions', () {
    expect(runModuleCatalog, hasLength(6));
    expect(runModuleCatalog.map((definition) => definition.id).toSet(), hasLength(6));

    final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
    expect(heavy.damageMultiplier, 1.20);
    expect(heavy.fireIntervalMultiplier, 1.10);
    expect(heavy.effectText, contains('20%'));
    expect(heavy.effectText, contains('10%'));

    final salvage = runModuleDefinition(RunModuleId.emergencySalvage);
    expect(salvage.immediateGold, 90);
    expect(salvage.effectText, contains('90'));
  });

  test('picker returns distinct cards without mutating candidates', () {
    final picker = RandomModuleOfferPicker(math.Random(7));
    final candidates = RunModuleId.values.toList();
    final before = List<RunModuleId>.of(candidates);

    final result = picker.pick(candidates, count: 3);

    expect(result, hasLength(3));
    expect(result.toSet(), hasLength(3));
    expect(result.every(candidates.contains), isTrue);
    expect(candidates, before);
  });

  test('picker rejects direct misuse with too few candidates', () {
    final picker = RandomModuleOfferPicker(math.Random(3));
    expect(
      () => picker.pick(
        const [RunModuleId.heavyCaliber, RunModuleId.longSight],
        count: 3,
      ),
      throwsStateError,
    );
  });
}
```

- [ ] **Step 2: Run the new test and verify red**

```bash
flutter test test/game/module_offer_picker_test.dart
```

Expected: compile failure because the module domain and picker do not exist.

- [ ] **Step 3: Implement the module domain**

Create `lib/game/modules/run_module.dart`:

```dart
import '../util/format.dart';

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

  String get effectText => switch (id) {
    RunModuleId.heavyCaliber =>
      'All tower damage rises ${percent(damageMultiplier - 1)}; '
      'attack interval rises ${percent(fireIntervalMultiplier - 1)}.',
    RunModuleId.overclockRelay =>
      'Attack interval drops ${percent(1 - fireIntervalMultiplier)}; '
      'all tower damage drops ${percent(1 - damageMultiplier)}.',
    RunModuleId.longSight =>
      'All towers gain ${percent(rangeMultiplier - 1)} range.',
    RunModuleId.emergencySalvage => 'Gain $immediateGold gold immediately.',
    RunModuleId.cryoReservoir =>
      'Cryo slows last ${number(slowDurationBonus)} seconds longer.',
    RunModuleId.rocketFusing =>
      'Rocket splash grows ${percent(splashRadiusMultiplier - 1)}; '
      'damage drops ${percent(1 - damageMultiplier)}.',
  };
}
```

Define `const runModuleCatalog` in this order with the exact Global Constraint values:

```dart
const runModuleCatalog = <RunModuleDefinition>[
  RunModuleDefinition(
    id: RunModuleId.heavyCaliber,
    title: 'Heavy Caliber',
    affinity: RunModuleAffinity.universal,
    damageMultiplier: 1.20,
    fireIntervalMultiplier: 1.10,
  ),
  RunModuleDefinition(
    id: RunModuleId.overclockRelay,
    title: 'Overclock Relay',
    affinity: RunModuleAffinity.universal,
    fireIntervalMultiplier: 0.85,
    damageMultiplier: 0.92,
  ),
  RunModuleDefinition(
    id: RunModuleId.longSight,
    title: 'Long Sight',
    affinity: RunModuleAffinity.universal,
    rangeMultiplier: 1.15,
  ),
  RunModuleDefinition(
    id: RunModuleId.emergencySalvage,
    title: 'Emergency Salvage',
    affinity: RunModuleAffinity.universal,
    immediateGold: 90,
  ),
  RunModuleDefinition(
    id: RunModuleId.cryoReservoir,
    title: 'Cryo Reservoir',
    affinity: RunModuleAffinity.cryo,
    slowDurationBonus: 0.60,
  ),
  RunModuleDefinition(
    id: RunModuleId.rocketFusing,
    title: 'Rocket Fusing',
    affinity: RunModuleAffinity.rocket,
    splashRadiusMultiplier: 1.25,
    damageMultiplier: 0.90,
  ),
];
```

Add:

```dart
RunModuleDefinition runModuleDefinition(RunModuleId id) =>
    runModuleCatalog.firstWhere((definition) => definition.id == id);

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

- [ ] **Step 4: Implement the picker**

Create `lib/game/rules/module_offer_picker.dart`:

```dart
import 'dart:math' as math;

import '../modules/run_module.dart';

abstract interface class ModuleOfferPicker {
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count});
}

final class RandomModuleOfferPicker implements ModuleOfferPicker {
  RandomModuleOfferPicker([math.Random? random]) : _random = random ?? math.Random();

  final math.Random _random;

  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    if (count < 0 || candidates.length < count) {
      throw StateError('Not enough eligible Salvage Modules.');
    }
    final shuffled = List<RunModuleId>.of(candidates)..shuffle(_random);
    return List.unmodifiable(shuffled.take(count));
  }
}
```

- [ ] **Step 5: Run green and commit**

```bash
flutter test test/game/module_offer_picker_test.dart
git add lib/game/modules/run_module.dart lib/game/rules/module_offer_picker.dart test/game/module_offer_picker_test.dart
git commit -m "feat: add salvage module catalog and picker (HPA-527)"
```

---

### Task 2: Apply module stats across Orion's actual damage channels

**Files:**
- Create: `lib/game/rules/run_module_rules.dart`
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/tower_stats_resolver.dart`
- Create: `test/game/run_module_rules_test.dart`
- Modify: `test/game/tower_stats_resolver_test.dart`

**Interfaces:**
- Produces `RunModuleRules.applyTowerStats(TowerStats, Iterable<RunModuleId>)`.
- Extends `TowerStatsResolver.resolve(..., Iterable<RunModuleId> runModules = const [])`.
- Extends `TowerStats.copyWith` only for `range`, `fireInterval`, `splashRadius`, `corrosionDamagePerSecond`, and `droneDamage` in addition to its existing fields.

- [ ] **Step 1: Write failing exact-effect tests**

Create `test/game/run_module_rules_test.dart` and include:

```dart
final laser = GameBalance.towerStats(TowerType.laser, level: 1);
final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
final overclock = runModuleDefinition(RunModuleId.overclockRelay);

final overclocked = RunModuleRules.applyTowerStats(
  laser,
  const [RunModuleId.overclockRelay],
);
expect(
  overclocked.fireInterval,
  closeTo(laser.fireInterval * overclock.fireIntervalMultiplier, 1e-9),
);
expect(
  overclocked.damage,
  closeTo(laser.damage * overclock.damageMultiplier, 1e-9),
);

final composed = RunModuleRules.applyTowerStats(
  laser,
  const [RunModuleId.heavyCaliber, RunModuleId.overclockRelay],
);
expect(
  composed.damage,
  closeTo(laser.damage * heavy.damageMultiplier * overclock.damageMultiplier, 1e-9),
);
expect(
  composed.fireInterval,
  closeTo(
    laser.fireInterval *
        heavy.fireIntervalMultiplier *
        overclock.fireIntervalMultiplier,
    1e-9,
  ),
);
```

Add channel-specific tests:

```dart
final nanite = GameBalance.towerStats(TowerType.nanite, level: 1);
final heavyNanite = RunModuleRules.applyTowerStats(
  nanite,
  const [RunModuleId.heavyCaliber],
);
expect(
  heavyNanite.corrosionDamagePerSecond,
  closeTo(nanite.corrosionDamagePerSecond * heavy.damageMultiplier, 1e-9),
);

final drone = GameBalance.towerStats(TowerType.droneBay, level: 1);
final heavyDrone = RunModuleRules.applyTowerStats(
  drone,
  const [RunModuleId.heavyCaliber],
);
expect(heavyDrone.damage, 0);
expect(
  heavyDrone.droneDamage,
  closeTo(drone.droneDamage * heavy.damageMultiplier, 1e-9),
);
expect(
  heavyDrone.fireInterval,
  closeTo(drone.fireInterval * heavy.fireIntervalMultiplier, 1e-9),
);

final overclockDrone = RunModuleRules.applyTowerStats(
  drone,
  const [RunModuleId.overclockRelay],
);
expect(
  overclockDrone.droneDamage,
  closeTo(drone.droneDamage * overclock.damageMultiplier, 1e-9),
);
expect(
  overclockDrone.fireInterval,
  closeTo(drone.fireInterval * overclock.fireIntervalMultiplier, 1e-9),
);
```

Also test Long Sight, Cryo Reservoir only on Cryo, and Rocket Fusing only on Rocket.

- [ ] **Step 2: Add resolver-order and no-module regressions**

In `test/game/tower_stats_resolver_test.dart`:

```dart
final base = GameBalance.towerStats(TowerType.laser, level: 1);
final resolved = TowerStatsResolver.resolve(
  const PlacedTower(
    id: 1,
    type: TowerType.laser,
    position: GridPosition(0, 0),
  ),
  campaignModifiers: const CampaignModifiers(laserDamageFraction: 0.10),
  runModules: const [RunModuleId.heavyCaliber],
);
expect(
  resolved.damage,
  closeTo(
    base.damage *
        1.10 *
        runModuleDefinition(RunModuleId.heavyCaliber).damageMultiplier,
    1e-9,
  ),
);
```

Compare existing stage-modified output with `runModules: const []` and assert equality for every stat field touched by current campaign/stage rules.

- [ ] **Step 3: Verify red**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
```

Expected: compile failures for missing rules/resolver inputs/copy fields.

- [ ] **Step 4: Extend `TowerStats.copyWith` narrowly**

Add nullable parameters:

```dart
double? range,
double? fireInterval,
double? splashRadius,
double? corrosionDamagePerSecond,
double? droneDamage,
```

Wire each as `value ?? this.value`. Update the existing method comment to list the new run-module fields; do not add unrelated `TowerStats` fields.

- [ ] **Step 5: Implement data-driven `RunModuleRules`**

Create `lib/game/rules/run_module_rules.dart`:

```dart
import '../models/game_models.dart';
import '../modules/run_module.dart';

abstract final class RunModuleRules {
  static TowerStats applyTowerStats(
    TowerStats resolvedStats,
    Iterable<RunModuleId> acquiredModules,
  ) {
    final acquired = acquiredModules.toSet();
    var stats = resolvedStats;

    for (final definition in runModuleCatalog) {
      if (!acquired.contains(definition.id) ||
          !_appliesToTower(definition.affinity, stats.type)) {
        continue;
      }

      stats = stats.copyWith(
        damage: stats.damage * definition.damageMultiplier,
        corrosionDamagePerSecond:
            stats.corrosionDamagePerSecond * definition.damageMultiplier,
        droneDamage: stats.droneDamage * definition.damageMultiplier,
        fireInterval:
            stats.fireInterval * definition.fireIntervalMultiplier,
        range: stats.range * definition.rangeMultiplier,
        splashRadius:
            stats.splashRadius * definition.splashRadiusMultiplier,
        slowDuration: stats.slowDuration + definition.slowDurationBonus,
      );
    }

    return stats;
  }

  static bool _appliesToTower(
    RunModuleAffinity affinity,
    TowerType towerType,
  ) => switch (affinity) {
    RunModuleAffinity.universal => true,
    RunModuleAffinity.cryo => towerType == TowerType.cryo,
    RunModuleAffinity.rocket => towerType == TowerType.rocket,
  };
}
```

No per-module numeric switch belongs here.

- [ ] **Step 6: Append run modules to `TowerStatsResolver`**

Add `Iterable<RunModuleId> runModules = const []`. Resolve campaign, then stage, then:

```dart
return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
```

Update its comment to `base → campaign → stage → run modules`.

- [ ] **Step 7: Run green and commit**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git add lib/game/models/game_models.dart lib/game/rules/run_module_rules.dart lib/game/rules/tower_stats_resolver.dart test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git commit -m "feat: apply salvage modules to tower stats (HPA-527)"
```

---

### Task 3: Add draft lifecycle, one resolution path, Flame refresh, and pacing

**Files:**
- Create: `test/game/game_test_fixtures.dart`
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/components/tower_component.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- Produces `GameSession.pendingRunModuleOffer`, `GameSession.acquiredRunModules`, `GameSession.selectRunModule(...)`, and `GameSession.resolveTowerStats(...)`.
- Produces defaulted `GameSnapshot.pendingRunModuleOffer`, `acquiredRunModules`, and `selectedTowerStats`.
- Produces `TowerStatsProvider` callback consumed by `TowerComponent`.
- Produces `OrionDefenseGame.selectRunModule(int, RunModuleId)`.
- Does **not** add the authoritative build/start gate yet; Task 4 lands that with the UI.

- [ ] **Step 1: Extract the existing empty-wave fixture**

Move `_emptyWaveStage({int waveCount = 2})` from `test/game/orion_defense_game_test.dart` into `test/game/game_test_fixtures.dart` as:

```dart
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

StageDefinition stageWithWaveCount(int count) {
  if (count <= 0) throw ArgumentError.value(count, 'count');
  return StageDefinition(
    id: 'empty-wave-stage-$count',
    name: 'Empty Wave Stage',
    mapLabel: 'Empty',
    description: 'Stage with empty waves for timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      count,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
```

Replace every existing `_emptyWaveStage()` with `stageWithWaveCount(2)` and `_emptyWaveStage(waveCount: 1)` with `stageWithWaveCount(1)`. Delete the private helper.

- [ ] **Step 2: Add fixed picker + session wave helper**

In `test/game/game_session_test.dart`:

```dart
final class _FixedModuleOfferPicker implements ModuleOfferPicker {
  _FixedModuleOfferPicker(this.offers);

  final List<List<RunModuleId>> offers;
  int _index = 0;

  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    final requested = offers[_index++];
    expect(requested, hasLength(count));
    expect(requested.every(candidates.contains), isTrue);
    return List.unmodifiable(requested);
  }
}

void completeWave(GameSession session) {
  expect(session.startWave(), isTrue);
  session.finishActiveWave();
}
```

- [ ] **Step 3: Write failing schedule, relevance, and selection tests**

Use `stageWithWaveCount(8)` and a fixed picker. Assert:

- no offer after waves 1/3/5/7;
- offers after 2/4/6;
- `draftNumber` is 1/2/3;
- repeated snapshots return the same stored offer;
- acquired IDs are absent from later candidate lists;
- stale/wrong/non-offered selection leaves state unchanged;
- Emergency Salvage adds `runModuleDefinition(...).immediateGold` once;
- restart clears acquired/pending state but the next offer ID is greater.

For relevance, use a Laser-only build. On draft 1 the fixed picker must be able to request only universal IDs. After selecting universals in drafts 1 and 2, assert the draft-3 candidate list also contains Cryo/Rocket fallback IDs and still has at least three candidates.

- [ ] **Step 4: Write failing selected-tower resolution test**

After selecting Long Sight:

```dart
final stats = session.resolveTowerStats(tower);
final snapshot = session.snapshot(selectedTower: tower);
expect(snapshot.selectedTowerStats, isNotNull);
expect(snapshot.selectedTowerStats!.range, stats.range);
expect(
  stats.range,
  closeTo(
    GameBalance.towerStats(TowerType.laser, level: 1).range *
        runModuleDefinition(RunModuleId.longSight).rangeMultiplier,
    1e-9,
  ),
);
```

- [ ] **Step 5: Run session/fixture tests red**

```bash
flutter test test/game/game_session_test.dart test/game/orion_defense_game_test.dart
```

- [ ] **Step 6: Add defaulted snapshot fields**

Import `../modules/run_module.dart` from `game_models.dart`. Extend `GameSnapshot` constructor with:

```dart
this.pendingRunModuleOffer,
List<RunModuleId> acquiredRunModules = const [],
this.selectedTowerStats,
```

Store:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
final TowerStats? selectedTowerStats;
```

Copy `acquiredRunModules` with `List.unmodifiable`. **Do not change `canStartWave` in this task.** Existing literal `GameSnapshot(...)` calls remain source-compatible through defaults.

- [ ] **Step 7: Add session state and one tower-stat resolver entry point**

Add optional `ModuleOfferPicker? offerPicker` to `GameSession.initial`, defaulting to `RandomModuleOfferPicker()`.

Store:

```dart
final ModuleOfferPicker _offerPicker;
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _nextModuleOfferId = 1;
```

Expose immutable getters.

Add:

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

When `snapshot(selectedTower: ...)` is called, populate `selectedTowerStats` with this method.

- [ ] **Step 8: Implement preferred + fallback candidate construction**

In `GameSession`, add a small private mapper:

```dart
TowerType? _affinityTower(RunModuleAffinity affinity) => switch (affinity) {
  RunModuleAffinity.universal => null,
  RunModuleAffinity.cryo => TowerType.cryo,
  RunModuleAffinity.rocket => TowerType.rocket,
};
```

Build candidates:

```dart
List<RunModuleId> _moduleCandidates() {
  final acquired = _acquiredRunModules.toSet();
  final placedTypes = _towersByPosition.values.map((tower) => tower.type).toSet();
  final unlockedTypes = unlockedTowerTypes.toSet();
  final remaining = runModuleCatalog
      .where((definition) => !acquired.contains(definition.id))
      .toList(growable: false);
  final candidates = <RunModuleId>[];

  void addMatching(bool Function(RunModuleDefinition definition) matches) {
    for (final definition in remaining) {
      if (matches(definition) && !candidates.contains(definition.id)) {
        candidates.add(definition.id);
      }
    }
  }

  addMatching((definition) {
    final tower = _affinityTower(definition.affinity);
    return tower == null || placedTypes.contains(tower);
  });

  if (candidates.length < 3) {
    addMatching((definition) {
      final tower = _affinityTower(definition.affinity);
      return tower != null && unlockedTypes.contains(tower);
    });
  }

  if (candidates.length < 3) {
    addMatching((_) => true);
  }

  return candidates;
}
```

- [ ] **Step 9: Open offers only from wave completion and never crash the mission**

After `_waveIndex += 1`, handle terminal victory first. Otherwise enter build and:

```dart
void _openModuleDraftIfDue() {
  if (_pendingRunModuleOffer != null ||
      !const {2, 4, 6}.contains(_waveIndex)) {
    return;
  }

  final candidates = _moduleCandidates();
  if (candidates.length < 3) {
    return; // configuration guard: do not throw from wave completion
  }

  _pendingRunModuleOffer = RunModuleOffer(
    offerId: _nextModuleOfferId++,
    draftNumber: _waveIndex ~/ 2,
    moduleIds: _offerPicker.pick(candidates, count: 3),
  );
}
```

No `_completedModuleDrafts` field is added.

- [ ] **Step 10: Implement atomic selection from definition-owned values**

```dart
bool selectRunModule({
  required int offerId,
  required RunModuleId moduleId,
}) {
  final offer = _pendingRunModuleOffer;
  if (offer == null ||
      offer.offerId != offerId ||
      !offer.moduleIds.contains(moduleId) ||
      _acquiredRunModules.contains(moduleId)) {
    return false;
  }

  _acquiredRunModules.add(moduleId);
  _gold += runModuleDefinition(moduleId).immediateGold;
  _pendingRunModuleOffer = null;
  return true;
}
```

Restart clears acquired/pending state but does not reset `_nextModuleOfferId`.

- [ ] **Step 11: Replace `TowerComponent` modifier caches with one provider callback**

In `tower_component.dart` remove the `CampaignModifiers` import, `TowerStatsResolver` import, `campaignModifiers`, and `stageModifiers` fields.

Add:

```dart
typedef TowerStatsProvider = TowerStats Function(PlacedTower tower);
```

Constructor:

```dart
TowerComponent({
  required PlacedTower tower,
  required Vector2 center,
  required this.resolveStats,
  required this.acquireTarget,
  required this.launchProjectile,
  ...
}) : placedTower = tower,
     stats = resolveStats(tower),
     ...;

final TowerStatsProvider resolveStats;
```

Update:

```dart
void updateTower(PlacedTower tower) {
  placedTower = tower;
  stats = resolveStats(tower);
  paint.color = _towerColor(tower.type);
}
```

- [ ] **Step 12: Wire the provider and module selection through `OrionDefenseGame`**

Allow test picker injection:

```dart
OrionDefenseGame({
  ...,
  ModuleOfferPicker? moduleOfferPicker,
}) : ...,
     _session = GameSession.initial(
       ...,
       offerPicker: moduleOfferPicker,
     );
```

In `_addTowerComponent` replace campaign/stage resolver inputs with:

```dart
resolveStats: _session.resolveTowerStats,
```

Add:

```dart
void selectRunModule(int offerId, RunModuleId moduleId) {
  if (!_session.selectRunModule(offerId: offerId, moduleId: moduleId)) return;

  for (final component in _towerComponents.values) {
    component.updateTower(component.placedTower);
  }
  _startAutoStartCountdownIfNeeded();
  _publishSnapshot();
}
```

- [ ] **Step 13: Suspend auto-start around a pending offer**

In `_finishWaveIfComplete`, after session completion:

```dart
final didWin = _session.phase == GamePhase.won;
final hasPendingDraft = _session.pendingRunModuleOffer != null;
_resetWaveSpawnState();
if (didWin) {
  _resetPacing();
} else if (hasPendingDraft) {
  _autoStartCountdownRemaining = null;
} else {
  _startAutoStartCountdownIfNeeded();
}
```

At the top of `_tickAutoStartCountdown`:

```dart
if (_session.pendingRunModuleOffer != null) {
  _autoStartCountdownRemaining = null;
  return false;
}
```

Add `_session.pendingRunModuleOffer == null` to `_startAutoStartCountdownIfNeeded()`.

**Do not block manual `startWave()` or build mutations yet.** That gate lands with selectable UI in Task 4.

- [ ] **Step 14: Write/finish Flame tests for one resolver path and pacing**

Using `stageWithWaveCount(8)` and a fixed picker, verify:

- wave 2 opens an offer and clears auto-start countdown;
- valid `game.selectRunModule` starts a fresh full countdown;
- an existing Laser component changes after Heavy Caliber selection;
- a tower placed after selection gets the same resolved values;
- Drone Bay Heavy/Overclock behavior reflects the Task 2 rules;
- `TowerComponent.updateTower` re-resolves through the provided callback.

- [ ] **Step 15: Run green and commit**

```bash
flutter test test/game/game_session_test.dart test/game/orion_defense_game_test.dart test/game/tower_stats_resolver_test.dart
git add test/game/game_test_fixtures.dart test/game/game_session_test.dart test/game/orion_defense_game_test.dart lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/components/tower_component.dart lib/game/orion_defense_game.dart
git commit -m "feat: add salvage module mission lifecycle (HPA-527)"
```

---

### Task 4: Land selectable intermission UI and authoritative gating together

**Files:**
- Create: `lib/game/ui/run_module_draft_panel.dart`
- Create: `test/widget/run_module_draft_panel_test.dart`
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`
- Modify: `test/widget/sell_button_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces final `GameSnapshot.canStartWave` pending-draft behavior.
- Produces `PlacementFailure.pendingModuleDraft` and session `_canMutateBuild` gating.
- Produces `RunModuleDraftPanel` and `AcquiredRunModuleStrip`.
- Uses `GameSnapshot.selectedTowerStats` for combat summary; production UI performs no stat resolution.

- [ ] **Step 1: Write the failing authoritative gate tests**

Extend `game_session_test.dart`. Reach a pending draft with a placed Level-2 tower and enough gold, then assert:

```dart
expect(
  session.validatePlacement(const GridPosition(0, 0), TowerType.laser).failure,
  PlacementFailure.pendingModuleDraft,
);
expect(session.upgradeTower(tower.id), isFalse);
expect(
  session.specializeTower(tower.id, TowerSpecialization.pulseLaser),
  isFalse,
);
expect(session.sellTower(tower.id), isNull);
expect(
  session.setTargetingMode(tower.id, TowerTargetingMode.strongest),
  isFalse,
);
expect(session.startWave(), isFalse);
expect(session.snapshot().canStartWave, isFalse);
```

After selecting a valid card, assert ordinary build/start behavior returns.

- [ ] **Step 2: Write game-layer feedback and board-tap tests**

In `orion_defense_game_test.dart`, while a draft is pending:

- call `startWave()` and expect `snapshot.feedback == 'Choose a Salvage Module first.'`;
- invoke a blocked selected-tower action and expect the same shared copy;
- attempt `onTapDown` on another board cell and assert selection does not change.

- [ ] **Step 3: Write 360×640 draft/reminder widget tests**

Create `test/widget/run_module_draft_panel_test.dart` with a 360×640 harness and:

```dart
final offer = RunModuleOffer(
  offerId: 4,
  draftNumber: 2,
  moduleIds: const [
    RunModuleId.heavyCaliber,
    RunModuleId.emergencySalvage,
    RunModuleId.cryoReservoir,
  ],
);
```

Assert:

- `Salvage Module 2 of 3`;
- all three titles;
- all three `effectText` values visible;
- affinity labels visible;
- tapping Heavy Caliber calls the callback exactly once;
- no overflow exception.

For `AcquiredRunModuleStrip`, assert both **title and effect text** are in the widget tree with no tooltip requirement. Empty input renders no module copy.

- [ ] **Step 4: Add selected-tower summary regression to the existing fixture**

Use `test/widget/sell_button_test.dart`'s existing selected-tower snapshot harness. Supply `selectedTowerStats` and verify the panel renders resolved fields. For a Drone Bay fixture, assert `Drone dmg` is rendered; for Laser, assert Damage/Fire/Range.

Run `test/widget_test.dart` unchanged as a compatibility check for its existing literal `GameSnapshot(...)` constructors.

- [ ] **Step 5: Verify red**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart \
  test/widget/run_module_draft_panel_test.dart \
  test/widget/sell_button_test.dart \
  test/widget_test.dart
```

- [ ] **Step 6: Add `PlacementFailure.pendingModuleDraft` and final session gate**

Extend the enum with `pendingModuleDraft`.

In `GameSession`:

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

For placement:

```dart
if (_phase != GamePhase.build) {
  return const PlacementResult.denied(PlacementFailure.invalidPhase);
}
if (_pendingRunModuleOffer != null) {
  return const PlacementResult.denied(PlacementFailure.pendingModuleDraft);
}
```

Use `_canMutateBuild` for upgrade, specialization, sale, targeting changes, and `startWave()`.

Change `GameSnapshot.canStartWave` to:

```dart
bool get canStartWave =>
    phase == GamePhase.build && pendingRunModuleOffer == null;
```

- [ ] **Step 7: Centralize game-layer blocked feedback**

Add:

```dart
String? _draftBlockMessage() =>
    _session.pendingRunModuleOffer == null
        ? null
        : 'Choose a Salvage Module first.';
```

Add the typed placement arm:

```dart
PlacementFailure.pendingModuleDraft => 'Choose a Salvage Module first.',
```

For bool/null-returning action failures, check `_draftBlockMessage()` in the existing action-specific message helpers/call sites before falling back to ordinary build-phase/affordability copy. Do not add result wrapper types solely for this ticket.

At the start of `onTapDown`, after terminal-state rejection:

```dart
if (_session.pendingRunModuleOffer != null) return;
```

- [ ] **Step 8: Implement the blocking draft panel**

Create `lib/game/ui/run_module_draft_panel.dart`:

```dart
class RunModuleDraftPanel extends StatelessWidget {
  const RunModuleDraftPanel({
    super.key,
    required this.offer,
    required this.onSelected,
  });

  final RunModuleOffer offer;
  final ValueChanged<RunModuleId> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.scrim.withValues(alpha: 0.84),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Salvage Module ${offer.draftNumber} of 3',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              for (final id in offer.moduleIds) ...[
                _RunModuleCard(
                  definition: runModuleDefinition(id),
                  onPressed: () => onSelected(id),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

`_RunModuleCard` renders title, full one-sentence `effectText`, and `affinity.label` in a `FilledButton.tonal` or `Card` + `InkWell`. No confirmation, reroll, rarity, or widget-owned gameplay state.

- [ ] **Step 9: Implement a read-only acquired reminder with inline effect copy**

In the same file:

```dart
class AcquiredRunModuleStrip extends StatelessWidget {
  const AcquiredRunModuleStrip({
    super.key,
    required this.moduleIds,
  });

  final List<RunModuleId> moduleIds;

  @override
  Widget build(BuildContext context) {
    if (moduleIds.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in moduleIds)
          _AcquiredModuleLabel(definition: runModuleDefinition(id)),
      ],
    );
  }
}
```

`_AcquiredModuleLabel` is non-interactive and renders `Title — effectText` with compact typography and at most two lines. Do not use `Tooltip`; the HUD container is intentionally `IgnorePointer`.

- [ ] **Step 10: Wire draft + reminder into `OrionGamePage`**

Inside the existing HUD column, after `_Hud`, add the read-only acquired strip when non-empty.

Inside the stage `Stack`, above normal controls and below terminal state:

```dart
if (snapshot.pendingRunModuleOffer case final offer?)
  Positioned.fill(
    child: RunModuleDraftPanel(
      offer: offer,
      onSelected: (moduleId) =>
          game.selectRunModule(offer.offerId, moduleId),
    ),
  ),
```

The modal barrier blocks pointer delivery to the board; the session remains the authoritative gate.

- [ ] **Step 11: Render resolved selected-tower stats from the snapshot**

Do **not** call `TowerStatsResolver` from Flutter.

Change `_TowerSummary` to accept `TowerStats? stats` from `snapshot.selectedTowerStats`. Render a compact line:

```text
Damage <n> • Fire <seconds>s • Range <n>
```

using existing `number`/`cadence` helpers.

Render one secondary field when relevant:

- Cryo: `Slow <seconds>s`;
- Rocket: `Splash <radius>`;
- Nanite: `Corrosion <damage>/s`;
- Drone Bay: `Drone dmg <damage>`.

Keep upgrade/specialization/sell costs sourced from existing balance/cost logic; modules do not change costs.

- [ ] **Step 12: Run green and commit**

```bash
flutter test \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart \
  test/widget/run_module_draft_panel_test.dart \
  test/widget/sell_button_test.dart \
  test/widget_test.dart

git add lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/orion_defense_game.dart lib/game/ui/run_module_draft_panel.dart lib/game/ui/orion_game_page.dart test/game/game_session_test.dart test/game/orion_defense_game_test.dart test/widget/run_module_draft_panel_test.dart test/widget/sell_button_test.dart test/widget_test.dart
git commit -m "feat: add salvage module intermission (HPA-527)"
```

---

### Task 5: Verify the vertical slice and record the two product checks

**Files:**
- No new evidence framework or report file.
- Fix only concrete defects found by verification in their owning source/test files.

**Interfaces:**
- Consumes Tasks 1–4.
- Produces a verified implementation branch and concise human observations in the implementation PR body/comment.

- [ ] **Step 1: Run all focused tests**

```bash
flutter test \
  test/game/module_offer_picker_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/tower_stats_resolver_test.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart \
  test/widget/run_module_draft_panel_test.dart \
  test/widget/sell_button_test.dart
```

Expected: all pass.

- [ ] **Step 2: Run format and analysis**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
```

Expected: both exit 0.

- [ ] **Step 3: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass, including existing `test/widget_test.dart` literal snapshot callers.

- [ ] **Step 4: Manual Stage 1 playtest at 1×**

Play Outpost Alpha through all three drafts. Record exactly:

1. Draft comprehension — yes/no + one sentence.
2. Mission pacing — improved/neutral/disruptive + one sentence.
3. Dead or mandatory card — module name or `none`.
4. Selected effects noticeable — yes/no + one sentence.

Pay specific attention to whether the third draft feels repetitive with the six-card pool. Record the observation; do not expand the catalog inside HPA-527.

- [ ] **Step 5: Manual later-stage playtest at 1×**

Choose one unlocked later main-path stage and record the same four observations. Prefer a run using Nanite or Drone Bay so Heavy Caliber/Overclock's expanded damage semantics get a human sanity check.

- [ ] **Step 6: Walk the acceptance checklist**

- [ ] drafts occur after waves 2/4/6 only;
- [ ] each production offer contains exactly three distinct IDs;
- [ ] early no-Cryo/no-Rocket builds prefer universal cards;
- [ ] pivot fallback keeps draft 3 at three cards;
- [ ] acquired cards do not reappear;
- [ ] stale/duplicate/non-offered selection does not mutate state;
- [ ] build/upgrade/specialize/sell/retarget/start-wave are blocked while pending;
- [ ] placement reports `pendingModuleDraft`;
- [ ] auto-start cannot tick behind a draft and resumes from a fresh full countdown;
- [ ] existing/new tower components resolve through the same session provider;
- [ ] Heavy/Overclock affect ordinary, corrosion, and drone damage channels consistently;
- [ ] Emergency Salvage uses its definition-owned gold reward once;
- [ ] acquired reminder shows inline effect copy;
- [ ] selected tower summary shows resolved combat stats;
- [ ] restart clears temporary module state but does not reuse offer IDs;
- [ ] route exit discards run-only state with the game instance;
- [ ] 360×640 draft UI has no overflow;
- [ ] no save schema, package, seed protocol, or event framework was introduced.

Do not claim completion until the automated checks have fresh passing output and both human observations are recorded.

---

## Self-Review

**Spec coverage:** Task 1 owns catalog/picker/tuning. Task 2 owns the actual stat semantics, including Drone Bay/Nanite channels. Task 3 owns offer lifecycle, preferred/fallback candidates, selection, snapshot defaults, one session-aware stat path, Flame refresh, and auto-start suspension while leaving the app manually playable. Task 4 lands selectable UI and the authoritative gate together, plus typed placement denial and player-visible resolved effects. Task 5 covers all automated and human acceptance gates.

**Placeholder scan:** No TBD/TODO or undefined implementation steps remain. Every public type/method consumed by a later task is defined earlier with a concrete signature.

**Type consistency:** `RunModuleId`/`RunModuleOffer` originate in `run_module.dart`; `ModuleOfferPicker` feeds `GameSession`; `TowerStatsResolver` consumes module IDs; `GameSession.resolveTowerStats` supplies current campaign/stage/run inputs; `TowerComponent` consumes one `TowerStatsProvider`; `GameSnapshot` defaults all new fields and carries selected resolved stats; `OrionDefenseGame.selectRunModule(int, RunModuleId)` matches the draft panel callback.

**Scope check:** The catalog stays at six, drafts stay at three, and no new subsystem was introduced. Catalog repetition is explicitly deferred to HPA-526 unless the two human runs prove it is already a blocker.
