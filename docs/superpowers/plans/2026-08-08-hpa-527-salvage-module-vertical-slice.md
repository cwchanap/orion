# HPA-527 Salvage Module Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six temporary Salvage Modules with one stable three-card draft after waves 2, 4, and 6, authoritative intermission gating, run-stat integration through the existing resolver, and a portrait-mobile snapshot-driven picker UI.

**Architecture:** `GameSession` owns run-only module state, offer generation boundaries, selection, economy effects, and build/wave gating. `TowerStatsResolver` appends a pure `RunModuleRules` step after the existing base → campaign → stage pipeline, while `OrionDefenseGame` only refreshes Flame components and pacing. Flutter renders immutable `GameSnapshot` module data through a focused draft-panel widget.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- Keep `GamePhase` unchanged: a pending module offer is still `GamePhase.build`.
- Exactly six initial modules: Heavy Caliber, Overclock Relay, Long Sight, Emergency Salvage, Cryo Reservoir, Rocket Fusing.
- Initial tuning: Heavy Caliber `damage × 1.20`, `fireInterval × 1.10`; Overclock Relay `fireInterval × 0.85`, `damage × 0.92`; Long Sight `range × 1.15`; Emergency Salvage `+90` gold once; Cryo Reservoir `slowDuration + 0.60`; Rocket Fusing `splashRadius × 1.25`, `damage × 0.90`.
- Drafts open only after completed waves 2, 4, and 6.
- Each offer contains exactly three distinct eligible, non-acquired module IDs and is generated once.
- Unselected cards may reappear later; do not store complete offer history.
- Use ordinary randomness in production and an injectable picker in tests; do not add seeds, algorithm versions, hashes, fingerprints, or canonical serialization.
- Use one monotonic `offerId` for stale callback protection; do not add a run-identity model.
- Apply tower effects in order: base → campaign → stage → run modules.
- Keep all six effects on existing stat/economy seams; no generic event bus, effect command graph, generated attack, recursion, or cap framework.
- Run-only module state is never written to `CampaignSave`.
- UI remains snapshot-driven; widgets do not read mutable `GameSession` or Flame component collections.
- Do not add Mission Report, blueprint progression, Codex module pages, audio, haptics, rarity, rerolls, decks, inventories, or mid-run resume.
- Minimum mobile target is 360×640 logical pixels.
- Required final checks: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`.

## File Structure

### Create

- `lib/game/modules/run_module.dart` — run-module IDs, affinity, definitions, catalog, immutable offer value.
- `lib/game/rules/module_offer_picker.dart` — injectable three-card picker and production random implementation.
- `lib/game/rules/run_module_rules.dart` — eligibility and pure tower-stat module application.
- `lib/game/ui/run_module_draft_panel.dart` — blocking draft panel plus acquired-module strip.
- `test/game/module_offer_picker_test.dart` — picker contract.
- `test/game/run_module_rules_test.dart` — eligibility and exact effect math.
- `test/widget/run_module_draft_panel_test.dart` — 360×640 draft/strip behavior.

### Modify

- `lib/game/models/game_models.dart` — extend `TowerStats.copyWith`; add module data to `GameSnapshot`; make `canStartWave` pending-offer aware.
- `lib/game/rules/tower_stats_resolver.dart` — append `RunModuleRules` after stage resolution.
- `lib/game/rules/game_session.dart` — own offer/acquired state, schedule, selection, economy effect, and authoritative gating.
- `lib/game/components/tower_component.dart` — resolve and refresh with current run modules.
- `lib/game/orion_defense_game.dart` — bridge selection, refresh towers, pause/restart auto-start countdown, block board taps during offer.
- `lib/game/ui/orion_game_page.dart` — render acquired strip and blocking draft panel from snapshot.
- `test/game/tower_stats_resolver_test.dart` — pipeline-order and no-module regression coverage.
- `test/game/game_session_test.dart` — draft schedule, offer stability, selection, gating, restart.
- `test/game/orion_defense_game_test.dart` — component refresh and pacing integration.

---

### Task 1: Add the six-module catalog and injectable offer picker

**Files:**
- Create: `lib/game/modules/run_module.dart`
- Create: `lib/game/rules/module_offer_picker.dart`
- Create: `test/game/module_offer_picker_test.dart`

**Interfaces:**
- Produces `RunModuleId`, `RunModuleAffinity`, `RunModuleDefinition`, `RunModuleOffer`, `runModuleCatalog`, `runModuleDefinition(RunModuleId)`.
- Produces `ModuleOfferPicker.pick(List<RunModuleId>, {required int count})` and `RandomModuleOfferPicker`.
- Later tasks consume these types; this task must not import `game_models.dart` from `run_module.dart`.

- [ ] **Step 1: Write picker tests first**

Create `test/game/module_offer_picker_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/modules/run_module.dart';
import 'package:orion/game/rules/module_offer_picker.dart';

void main() {
  group('RandomModuleOfferPicker', () {
    test('returns the requested number of distinct candidates', () {
      final picker = RandomModuleOfferPicker(math.Random(7));
      final candidates = RunModuleId.values.toList();

      final result = picker.pick(candidates, count: 3);

      expect(result, hasLength(3));
      expect(result.toSet(), hasLength(3));
      expect(result.every(candidates.contains), isTrue);
    });

    test('does not mutate the caller candidate list', () {
      final picker = RandomModuleOfferPicker(math.Random(11));
      final candidates = RunModuleId.values.toList();
      final before = List<RunModuleId>.of(candidates);

      picker.pick(candidates, count: 3);

      expect(candidates, before);
    });

    test('throws when the requested offer cannot be filled', () {
      final picker = RandomModuleOfferPicker(math.Random(3));

      expect(
        () => picker.pick(
          const [RunModuleId.heavyCaliber, RunModuleId.longSight],
          count: 3,
        ),
        throwsStateError,
      );
    });
  });
}
```

- [ ] **Step 2: Run the new test and verify red**

Run:

```bash
flutter test test/game/module_offer_picker_test.dart
```

Expected: compile failure because `run_module.dart` / `module_offer_picker.dart` do not exist.

- [ ] **Step 3: Implement the module domain**

Create `lib/game/modules/run_module.dart` with these exact public shapes and catalog entries:

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

const runModuleCatalog = <RunModuleDefinition>[
  RunModuleDefinition(
    id: RunModuleId.heavyCaliber,
    title: 'Heavy Caliber',
    effectText: 'All towers deal 20% more damage but fire 10% slower.',
    affinity: RunModuleAffinity.universal,
  ),
  RunModuleDefinition(
    id: RunModuleId.overclockRelay,
    title: 'Overclock Relay',
    effectText: 'All towers fire 15% faster but deal 8% less damage.',
    affinity: RunModuleAffinity.universal,
  ),
  RunModuleDefinition(
    id: RunModuleId.longSight,
    title: 'Long Sight',
    effectText: 'All towers gain 15% range.',
    affinity: RunModuleAffinity.universal,
  ),
  RunModuleDefinition(
    id: RunModuleId.emergencySalvage,
    title: 'Emergency Salvage',
    effectText: 'Gain 90 gold immediately.',
    affinity: RunModuleAffinity.universal,
  ),
  RunModuleDefinition(
    id: RunModuleId.cryoReservoir,
    title: 'Cryo Reservoir',
    effectText: 'Cryo slows last 0.6 seconds longer.',
    affinity: RunModuleAffinity.cryo,
  ),
  RunModuleDefinition(
    id: RunModuleId.rocketFusing,
    title: 'Rocket Fusing',
    effectText: 'Rocket splash grows 25%, but direct damage drops 10%.',
    affinity: RunModuleAffinity.rocket,
  ),
];

RunModuleDefinition runModuleDefinition(RunModuleId id) =>
    runModuleCatalog.firstWhere((definition) => definition.id == id);
```

- [ ] **Step 4: Implement the picker without mutating input**

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
      throw StateError('Not enough eligible Salvage Modules for a $count-card offer.');
    }
    final shuffled = List<RunModuleId>.of(candidates)..shuffle(_random);
    return List.unmodifiable(shuffled.take(count));
  }
}
```

- [ ] **Step 5: Run picker tests green**

```bash
flutter test test/game/module_offer_picker_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add lib/game/modules/run_module.dart lib/game/rules/module_offer_picker.dart test/game/module_offer_picker_test.dart
git commit -m "feat: add salvage module catalog and picker (HPA-527)"
```

---

### Task 2: Add pure eligibility and tower-stat module rules

**Files:**
- Create: `lib/game/rules/run_module_rules.dart`
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/tower_stats_resolver.dart`
- Create: `test/game/run_module_rules_test.dart`
- Modify: `test/game/tower_stats_resolver_test.dart`

**Interfaces:**
- Consumes `RunModuleId`, `RunModuleDefinition`, `RunModuleAffinity` from Task 1.
- Produces `RunModuleRules.isEligible(...)` and `RunModuleRules.applyTowerStats(...)`.
- Extends `TowerStatsResolver.resolve(..., Iterable<RunModuleId> runModules = const [])`.

- [ ] **Step 1: Write exact rule tests**

Create `test/game/run_module_rules_test.dart` with a helper that starts from `GameBalance.towerStats` and verify:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/modules/run_module.dart';
import 'package:orion/game/rules/run_module_rules.dart';

void main() {
  group('RunModuleRules.isEligible', () {
    test('universal modules are always eligible', () {
      expect(
        RunModuleRules.isEligible(
          runModuleDefinition(RunModuleId.longSight),
          unlockedTowerTypes: const [],
        ),
        isTrue,
      );
    });

    test('tower affinity requires that family to be unlocked', () {
      final cryo = runModuleDefinition(RunModuleId.cryoReservoir);
      expect(
        RunModuleRules.isEligible(cryo, unlockedTowerTypes: const [TowerType.laser]),
        isFalse,
      );
      expect(
        RunModuleRules.isEligible(cryo, unlockedTowerTypes: const [TowerType.cryo]),
        isTrue,
      );
    });
  });

  group('RunModuleRules.applyTowerStats', () {
    test('Heavy Caliber and Long Sight compose from base values', () {
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final resolved = RunModuleRules.applyTowerStats(
        base,
        const [RunModuleId.heavyCaliber, RunModuleId.longSight],
      );

      expect(resolved.damage, closeTo(base.damage * 1.20, 1e-9));
      expect(resolved.fireInterval, closeTo(base.fireInterval * 1.10, 1e-9));
      expect(resolved.range, closeTo(base.range * 1.15, 1e-9));
    });

    test('Cryo Reservoir only changes Cryo', () {
      final cryo = GameBalance.towerStats(TowerType.cryo, level: 1);
      final laser = GameBalance.towerStats(TowerType.laser, level: 1);

      expect(
        RunModuleRules.applyTowerStats(cryo, const [RunModuleId.cryoReservoir]).slowDuration,
        closeTo(cryo.slowDuration + 0.60, 1e-9),
      );
      expect(
        RunModuleRules.applyTowerStats(laser, const [RunModuleId.cryoReservoir]).slowDuration,
        laser.slowDuration,
      );
    });

    test('Rocket Fusing only changes Rocket', () {
      final base = GameBalance.towerStats(TowerType.rocket, level: 1);
      final resolved = RunModuleRules.applyTowerStats(
        base,
        const [RunModuleId.rocketFusing],
      );

      expect(resolved.splashRadius, closeTo(base.splashRadius * 1.25, 1e-9));
      expect(resolved.damage, closeTo(base.damage * 0.90, 1e-9));
    });
  });
}
```

- [ ] **Step 2: Add resolver-order regression tests before implementation**

Append to `test/game/tower_stats_resolver_test.dart`:

```dart
test('applies run modules after campaign and stage modifiers', () {
  const placed = PlacedTower(
    id: 1,
    type: TowerType.laser,
    position: GridPosition(0, 0),
  );
  const campaign = CampaignModifiers(laserDamageFraction: 0.10);
  final base = GameBalance.towerStats(TowerType.laser, level: 1);

  final resolved = TowerStatsResolver.resolve(
    placed,
    campaignModifiers: campaign,
    runModules: const [RunModuleId.heavyCaliber],
  );

  expect(resolved.damage, closeTo(base.damage * 1.10 * 1.20, 1e-9));
});

test('empty run-module list preserves current resolver output', () {
  const placed = PlacedTower(
    id: 1,
    type: TowerType.gravityWell,
    position: GridPosition(0, 0),
  );

  final withoutArgument = TowerStatsResolver.resolve(
    placed,
    stageModifiers: const [StageModifier.amplifiedGravityWells],
  );
  final explicitEmpty = TowerStatsResolver.resolve(
    placed,
    stageModifiers: const [StageModifier.amplifiedGravityWells],
    runModules: const [],
  );

  expect(explicitEmpty.damage, withoutArgument.damage);
  expect(explicitEmpty.range, withoutArgument.range);
  expect(explicitEmpty.fieldRadius, withoutArgument.fieldRadius);
  expect(explicitEmpty.fieldDuration, withoutArgument.fieldDuration);
});
```

Add imports for `run_module.dart`.

- [ ] **Step 3: Run focused tests and verify red**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
```

Expected: compile failures for missing rules and new resolver/copy fields.

- [ ] **Step 4: Extend `TowerStats.copyWith` narrowly**

In `lib/game/models/game_models.dart`, add only:

```dart
double? range,
double? fireInterval,
double? splashRadius,
```

and wire them to the corresponding constructor arguments:

```dart
range: range ?? this.range,
fireInterval: fireInterval ?? this.fireInterval,
splashRadius: splashRadius ?? this.splashRadius,
```

Keep every other existing field unchanged.

- [ ] **Step 5: Implement `RunModuleRules`**

Create `lib/game/rules/run_module_rules.dart`. Use a catalog-ordered loop so composition remains explicit:

```dart
import '../models/game_models.dart';
import '../modules/run_module.dart';

abstract final class RunModuleRules {
  static bool isEligible(
    RunModuleDefinition definition, {
    required Iterable<TowerType> unlockedTowerTypes,
  }) {
    final unlocked = unlockedTowerTypes.toSet();
    return switch (definition.affinity) {
      RunModuleAffinity.universal => true,
      RunModuleAffinity.cryo => unlocked.contains(TowerType.cryo),
      RunModuleAffinity.rocket => unlocked.contains(TowerType.rocket),
    };
  }

  static TowerStats applyTowerStats(
    TowerStats resolvedStats,
    Iterable<RunModuleId> acquiredModules,
  ) {
    final acquired = acquiredModules.toSet();
    var stats = resolvedStats;

    for (final definition in runModuleCatalog) {
      if (!acquired.contains(definition.id)) continue;
      stats = switch (definition.id) {
        RunModuleId.heavyCaliber => stats.copyWith(
            damage: stats.damage * 1.20,
            fireInterval: stats.fireInterval * 1.10,
          ),
        RunModuleId.overclockRelay => stats.copyWith(
            fireInterval: stats.fireInterval * 0.85,
            damage: stats.damage * 0.92,
          ),
        RunModuleId.longSight => stats.copyWith(range: stats.range * 1.15),
        RunModuleId.cryoReservoir when stats.type == TowerType.cryo =>
          stats.copyWith(slowDuration: stats.slowDuration + 0.60),
        RunModuleId.rocketFusing when stats.type == TowerType.rocket =>
          stats.copyWith(
            splashRadius: stats.splashRadius * 1.25,
            damage: stats.damage * 0.90,
          ),
        RunModuleId.emergencySalvage ||
        RunModuleId.cryoReservoir ||
        RunModuleId.rocketFusing => stats,
      };
    }
    return stats;
  }
}
```

- [ ] **Step 6: Append run modules to `TowerStatsResolver`**

Import `run_module.dart` and `run_module_rules.dart`. Change `resolve` to accept:

```dart
Iterable<RunModuleId> runModules = const [],
```

Store the stage-adjusted value, then return:

```dart
final stageAdjusted = StageModifierRules.effectiveTowerStats(
  resolvedStats: campaignAdjusted,
  stageModifiers: stageModifiers,
);
return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
```

Update the resolver doc comment to `base → campaign → stage → run modules`.

- [ ] **Step 7: Run rule/resolver tests green**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
```

Expected: all pass.

- [ ] **Step 8: Commit Task 2**

```bash
git add lib/game/models/game_models.dart lib/game/rules/run_module_rules.dart lib/game/rules/tower_stats_resolver.dart test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git commit -m "feat: apply salvage modules to tower stats (HPA-527)"
```

---

### Task 3: Make `GameSession` own draft lifecycle, selection, economy, and gating

**Files:**
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `test/game/game_session_test.dart`

**Interfaces:**
- Consumes Task 1 picker/domain and Task 2 eligibility rules.
- Produces `GameSession.pendingRunModuleOffer`, `acquiredRunModules`, `selectRunModule(...)`.
- `GameSnapshot` gains `pendingRunModuleOffer` and `acquiredRunModules`.

- [ ] **Step 1: Add a fixed picker test double inside `game_session_test.dart`**

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
```

Import the module and picker files.

- [ ] **Step 2: Write draft schedule and stability tests**

Add tests that instantiate `GameSession.initial(offerPicker: ...)`, clear waves by calling `startWave()` / `finishActiveWave()`, and assert:

```dart
expect(session.pendingRunModuleOffer, isNull);
// after wave 1
expect(session.pendingRunModuleOffer, isNull);
// after wave 2
expect(session.pendingRunModuleOffer?.draftNumber, 1);
expect(session.pendingRunModuleOffer?.moduleIds, const [
  RunModuleId.heavyCaliber,
  RunModuleId.longSight,
  RunModuleId.emergencySalvage,
]);

final stored = session.pendingRunModuleOffer;
expect(session.snapshot().pendingRunModuleOffer, same(stored));
expect(session.snapshot().pendingRunModuleOffer, same(stored));
```

After selecting one card, continue and verify draft numbers 2 and 3 after waves 4 and 6, with no draft after any other wave.

- [ ] **Step 3: Write selection, acquired exclusion, and one-time gold tests**

Cover:

```dart
final offer = session.pendingRunModuleOffer!;
final beforeGold = session.gold;
expect(
  session.selectRunModule(
    offerId: offer.offerId,
    moduleId: RunModuleId.emergencySalvage,
  ),
  isTrue,
);
expect(session.gold, beforeGold + 90);
expect(session.acquiredRunModules, contains(RunModuleId.emergencySalvage));
expect(session.pendingRunModuleOffer, isNull);

expect(
  session.selectRunModule(
    offerId: offer.offerId,
    moduleId: RunModuleId.emergencySalvage,
  ),
  isFalse,
);
expect(session.gold, beforeGold + 90);
```

Also test wrong `offerId` and a module not present in the offer; both must return `false` without state changes.

- [ ] **Step 4: Write authoritative gating tests**

Reach the first pending draft with enough gold and a placed/upgraded-capable tower. While pending, assert:

```dart
expect(
  session.validatePlacement(const GridPosition(0, 0), TowerType.laser).failure,
  PlacementFailure.invalidPhase,
);
expect(session.upgradeTower(tower.id), isFalse);
expect(session.specializeTower(tower.id, TowerSpecialization.pulseLaser), isFalse);
expect(session.sellTower(tower.id), isNull);
expect(session.setTargetingMode(tower.id, TowerTargetingMode.strongest), isFalse);
expect(session.startWave(), isFalse);
```

After selecting a valid module, the same build-phase APIs become available again subject to their ordinary constraints.

- [ ] **Step 5: Write restart/offer-ID regression test**

Capture offer 1's ID, restart, replay to wave 2, and verify the new offer ID is larger rather than reused:

```dart
final oldOfferId = session.pendingRunModuleOffer!.offerId;
session.restart();
expect(session.acquiredRunModules, isEmpty);
expect(session.pendingRunModuleOffer, isNull);
// clear waves 1 and 2 again
expect(session.pendingRunModuleOffer!.offerId, greaterThan(oldOfferId));
```

- [ ] **Step 6: Run session tests and verify red**

```bash
flutter test test/game/game_session_test.dart
```

Expected: compile failures until new session/snapshot APIs exist.

- [ ] **Step 7: Extend `GameSnapshot`**

Import `../modules/run_module.dart` from `game_models.dart`. Add constructor inputs and fields:

```dart
this.pendingRunModuleOffer,
List<RunModuleId> acquiredRunModules = const [],
```

Store acquired IDs immutably:

```dart
acquiredRunModules = List.unmodifiable(acquiredRunModules)
```

Add:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;

bool get canStartWave =>
    phase == GamePhase.build && pendingRunModuleOffer == null;
```

- [ ] **Step 8: Inject the picker and add session state**

In `GameSession.initial`, add:

```dart
ModuleOfferPicker? offerPicker,
```

and pass `offerPicker ?? RandomModuleOfferPicker()` into the private constructor. Store:

```dart
final ModuleOfferPicker _offerPicker;
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _completedModuleDrafts = 0;
int _nextModuleOfferId = 1;

List<RunModuleId> get acquiredRunModules =>
    List.unmodifiable(_acquiredRunModules);
RunModuleOffer? get pendingRunModuleOffer => _pendingRunModuleOffer;
```

- [ ] **Step 9: Centralize build mutation gating**

Add:

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Replace build-phase-only checks in placement, upgrade, specialization, sale, targeting, and `startWave()` with `_canMutateBuild` while preserving every existing non-phase validation.

`PlacementFailure.invalidPhase` remains the result for blocked placement; do not add a module-specific failure enum.

- [ ] **Step 10: Open offers only from `finishActiveWave()`**

After incrementing `_waveIndex` and handling victory, set build phase and call a private helper:

```dart
void _openModuleDraftIfDue() {
  if (!const {2, 4, 6}.contains(_waveIndex)) return;

  final acquired = _acquiredRunModules.toSet();
  final candidates = runModuleCatalog
      .where((definition) => !acquired.contains(definition.id))
      .where(
        (definition) => RunModuleRules.isEligible(
          definition,
          unlockedTowerTypes: unlockedTowerTypes,
        ),
      )
      .map((definition) => definition.id)
      .toList(growable: false);

  final selected = _offerPicker.pick(candidates, count: 3);
  _pendingRunModuleOffer = RunModuleOffer(
    offerId: _nextModuleOfferId++,
    draftNumber: _completedModuleDrafts + 1,
    moduleIds: selected,
  );
}
```

Call it only after `_phase = GamePhase.build`.

- [ ] **Step 11: Implement atomic selection**

Add:

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
  if (moduleId == RunModuleId.emergencySalvage) {
    _gold += 90;
  }
  _pendingRunModuleOffer = null;
  _completedModuleDrafts += 1;
  return true;
}
```

- [ ] **Step 12: Project module state and clear it on restart**

Pass session module state into `GameSnapshot` from `snapshot()`.

In `restart()`:

```dart
_acquiredRunModules.clear();
_pendingRunModuleOffer = null;
_completedModuleDrafts = 0;
```

Do **not** reset `_nextModuleOfferId`.

- [ ] **Step 13: Run session tests green**

```bash
flutter test test/game/game_session_test.dart
```

Expected: all existing and new session tests pass.

- [ ] **Step 14: Commit Task 3**

```bash
git add lib/game/models/game_models.dart lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: add salvage module draft lifecycle (HPA-527)"
```

---

### Task 4: Refresh Flame tower stats and suspend auto-start during drafts

**Files:**
- Modify: `lib/game/components/tower_component.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- Consumes `GameSession.selectRunModule`, `acquiredRunModules`, and resolver `runModules` input.
- Produces `TowerComponent.updateRunModules(...)` and `OrionDefenseGame.selectRunModule(...)`.

- [ ] **Step 1: Write orchestration tests first**

In `test/game/orion_defense_game_test.dart`, use the existing test harness plus an injectable picker path on `OrionDefenseGame` (added below) and cover:

1. after wave 2 completes with auto-start enabled, `snapshot.pendingRunModuleOffer != null` and `autoStartCountdownRemaining == null`;
2. selecting a valid card clears the offer and sets `autoStartCountdownRemaining` to `OrionDefenseGame.autoStartCountdownSeconds`;
3. Heavy Caliber updates an already placed tower's resolved damage/fire interval;
4. a tower placed after Heavy Caliber selection receives the same modifiers.

If tests cannot inspect a component directly using the current harness, add one test-only getter consistent with existing tests rather than exposing mutable production collections.

- [ ] **Step 2: Run the orchestration tests and verify red**

```bash
flutter test test/game/orion_defense_game_test.dart
```

Expected: compile/assertion failures for missing module bridge and refresh behavior.

- [ ] **Step 3: Let `TowerComponent` carry current run modules**

Add an optional constructor argument:

```dart
Iterable<RunModuleId> runModules = const [],
```

Store:

```dart
List<RunModuleId> runModules;
```

Initialize with `List.unmodifiable(runModules)`, and pass it into every `TowerStatsResolver.resolve` call.

Add:

```dart
void updateRunModules(Iterable<RunModuleId> modules) {
  runModules = List.unmodifiable(modules);
  stats = TowerStatsResolver.resolve(
    placedTower,
    campaignModifiers: campaignModifiers,
    stageModifiers: stageModifiers,
    runModules: runModules,
  );
}
```

Keep `updateTower` resolving from base using the stored `runModules`.

- [ ] **Step 4: Allow `OrionDefenseGame` picker injection for tests**

Add constructor input:

```dart
ModuleOfferPicker? moduleOfferPicker,
```

and pass it to `GameSession.initial(offerPicker: moduleOfferPicker)`.

Production callers omit it.

- [ ] **Step 5: Pass modules to new tower components**

In `_addTowerComponent`, pass:

```dart
runModules: _session.acquiredRunModules,
```

No other component needs the module catalog.

- [ ] **Step 6: Add the selection bridge and refresh existing towers**

```dart
void selectRunModule(int offerId, RunModuleId moduleId) {
  if (!_session.selectRunModule(offerId: offerId, moduleId: moduleId)) {
    return;
  }

  for (final tower in _towerComponents.values) {
    tower.updateRunModules(_session.acquiredRunModules);
  }
  _startAutoStartCountdownIfNeeded();
  _publishSnapshot();
}
```

No feedback event framework is added.

- [ ] **Step 7: Suspend auto-start when `finishActiveWave` opens a draft**

Change `_finishWaveIfComplete()` after `_session.finishActiveWave()`:

```dart
final didWin = _session.phase == GamePhase.won;
final hasPendingModuleOffer = _session.pendingRunModuleOffer != null;
_resetWaveSpawnState();
if (didWin) {
  _resetPacing();
} else if (hasPendingModuleOffer) {
  _autoStartCountdownRemaining = null;
} else {
  _startAutoStartCountdownIfNeeded();
}
```

Preserve `_autoStartEnabled` when a draft opens.

Add `_session.pendingRunModuleOffer == null` to `_startAutoStartCountdownIfNeeded()` so no caller can start a hidden countdown during an offer.

- [ ] **Step 8: Prevent board-selection changes under the modal draft**

At the beginning of `onTapDown`, after terminal-state rejection, add:

```dart
if (_session.pendingRunModuleOffer != null) {
  return;
}
```

This is presentation hygiene; authoritative mutation blocking remains in `GameSession`.

- [ ] **Step 9: Run orchestration tests green**

```bash
flutter test test/game/orion_defense_game_test.dart
```

Expected: all pass.

- [ ] **Step 10: Run TowerComponent-related regressions**

```bash
flutter test test/game/tower_stats_resolver_test.dart test/game/orion_defense_game_test.dart
```

Expected: all pass.

- [ ] **Step 11: Commit Task 4**

```bash
git add lib/game/components/tower_component.dart lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: apply salvage modules in active missions (HPA-527)"
```

---

### Task 5: Add the snapshot-driven mobile draft panel and acquired strip

**Files:**
- Create: `lib/game/ui/run_module_draft_panel.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Create: `test/widget/run_module_draft_panel_test.dart`

**Interfaces:**
- Consumes immutable `RunModuleOffer`, acquired `RunModuleId` list, and `runModuleDefinition` lookup.
- `RunModuleDraftPanel` receives `RunModuleOffer offer` and `ValueChanged<RunModuleId> onSelected`.
- `AcquiredRunModuleStrip` receives `List<RunModuleId> moduleIds`.

- [ ] **Step 1: Write widget tests first**

Create `test/widget/run_module_draft_panel_test.dart` with a 360×640 `MediaQuery` harness and a fixed offer:

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

Cover:

```dart
expect(find.text('Salvage Module 2 of 3'), findsOneWidget);
expect(find.text('Heavy Caliber'), findsOneWidget);
expect(find.text('Emergency Salvage'), findsOneWidget);
expect(find.text('Cryo Reservoir'), findsOneWidget);
expect(find.text('Universal'), findsWidgets);
expect(find.text('Cryo'), findsOneWidget);
expect(tester.takeException(), isNull);
```

Tap `Heavy Caliber` and assert the callback receives `RunModuleId.heavyCaliber` exactly once.

Render `AcquiredRunModuleStrip` with two IDs and assert both titles appear; render with an empty list and assert it occupies no visible content.

- [ ] **Step 2: Run the widget test and verify red**

```bash
flutter test test/widget/run_module_draft_panel_test.dart
```

Expected: compile failure because the widget file does not exist.

- [ ] **Step 3: Implement `RunModuleDraftPanel`**

Create `lib/game/ui/run_module_draft_panel.dart` using `Material`, `SafeArea`, and `SingleChildScrollView`. The structure should be equivalent to:

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

Use an internal `_RunModuleCard` built from `FilledButton.tonal` or `Card` + `InkWell`. Keep title, effect sentence, and affinity visible without a confirmation dialog.

- [ ] **Step 4: Implement the acquired strip in the same focused file**

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
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(runModuleDefinition(id).title),
          ),
      ],
    );
  }
}
```

Keep it read-only.

- [ ] **Step 5: Wire both widgets into `OrionGamePage`**

Import the new file.

Inside the existing top HUD `Column`, after `_Hud` and before/after the next-wave panel as space allows, add:

```dart
if (snapshot.acquiredRunModules.isNotEmpty) ...[
  const SizedBox(height: 8),
  AcquiredRunModuleStrip(moduleIds: snapshot.acquiredRunModules),
],
```

Inside the stage `Stack`, after bottom controls and before `_EndStatePanel`, add:

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

Do not add module eligibility logic to the widget.

- [ ] **Step 6: Run widget tests green**

```bash
flutter test test/widget/run_module_draft_panel_test.dart
```

Expected: all pass, no overflow exception at 360×640.

- [ ] **Step 7: Run the existing top-level widget suite**

```bash
flutter test test/widget_test.dart test/widget/run_module_draft_panel_test.dart
```

Expected: all pass.

- [ ] **Step 8: Commit Task 5**

```bash
git add lib/game/ui/run_module_draft_panel.dart lib/game/ui/orion_game_page.dart test/widget/run_module_draft_panel_test.dart
git commit -m "feat: add salvage module intermission UI (HPA-527)"
```

---

### Task 6: Verify the full vertical slice and record the two human playtests

**Files:**
- Modify only if verification exposes a concrete defect in files already in scope.
- No new evidence framework or report file is required.

**Interfaces:**
- Consumes all previous tasks.
- Produces a verified implementation branch plus concise Stage 1 / later-stage observations in the implementation PR body or a PR comment.

- [ ] **Step 1: Run all focused module/session/game/widget tests**

```bash
flutter test \
  test/game/module_offer_picker_test.dart \
  test/game/run_module_rules_test.dart \
  test/game/tower_stats_resolver_test.dart \
  test/game/game_session_test.dart \
  test/game/orion_defense_game_test.dart \
  test/widget/run_module_draft_panel_test.dart
```

Expected: all pass.

- [ ] **Step 2: Run formatting and static analysis**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
```

Expected: both exit 0.

- [ ] **Step 3: Run the complete existing test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Manual Stage 1 playtest at 1×**

Play Outpost Alpha at 1× through the three drafts. Record four short observations in the implementation PR:

- draft comprehension in a few seconds: yes/no + note;
- pacing: improved / neutral / disruptive;
- any obviously dead or mandatory card;
- whether the selected module effects were noticeable.

Do not add telemetry or structured evidence export.

- [ ] **Step 5: Manual later-stage playtest at 1×**

Choose one unlocked later main-path stage and record the same four observations. Prefer a stage with enough enemy variety to notice Rocket/Cryo/general stat trade-offs.

If a value is obviously too weak/strong in both runs, adjust only the constants in `run_module_rules.dart` / catalog copy, update exact-value tests, and rerun Steps 1–3.

- [ ] **Step 6: Final acceptance walkthrough**

Check each item manually against the running app and tests:

- [ ] drafts occur after 2/4/6 only;
- [ ] each offer remains unchanged until selection;
- [ ] acquired cards do not reappear;
- [ ] stale/duplicate taps do not mutate state;
- [ ] build/upgrade/specialize/sell/retarget/start-wave are blocked while pending;
- [ ] auto-start resumes with a fresh full countdown;
- [ ] existing towers update immediately after a stat module;
- [ ] later-placed towers inherit the same modules;
- [ ] Emergency Salvage adds 90 gold once;
- [ ] restart clears temporary modules and pending offer;
- [ ] returning to the world map abandons the run-only state;
- [ ] 360×640 draft UI has no overflow;
- [ ] no save-schema or package dependency changed.

- [ ] **Step 7: Commit any verification-only correction**

Only if Steps 1–6 required a concrete code/tuning correction:

```bash
git add <only-the-files-changed-by-the-correction>
git commit -m "fix: address salvage module validation findings (HPA-527)"
```

If no correction was required, do not create an empty commit.

---

## Self-Review

**1. Spec coverage:** Tasks 1–2 implement the catalog, picker, eligibility, and base → campaign → stage → run-module stat pipeline. Task 3 owns the 2/4/6 lifecycle, stable offers, stale-tap protection, acquired exclusion, Emergency Salvage, authoritative gating, and restart cleanup. Task 4 handles existing/new tower consistency and auto-start pacing. Task 5 implements the blocking 360×640 snapshot-driven UI and acquired strip. Task 6 covers focused/full automated verification plus the two required human 1× checks. Every design acceptance criterion maps to a task.

**2. Placeholder scan:** No TBD/TODO/"implement later" steps. Every new public type and method used by a later task is defined earlier with a concrete signature. Manual validation asks for four exact observations rather than an undefined report.

**3. Type consistency:** `RunModuleId`, `RunModuleDefinition`, and `RunModuleOffer` originate in `run_module.dart`; `ModuleOfferPicker` originates in `module_offer_picker.dart`; `RunModuleRules` consumes those types; `GameSession` injects `ModuleOfferPicker`; `GameSnapshot` projects `RunModuleOffer` + `List<RunModuleId>`; `TowerStatsResolver` and `TowerComponent` both use `Iterable<RunModuleId>` inputs; `OrionDefenseGame.selectRunModule(int, RunModuleId)` matches `RunModuleDraftPanel`'s callback path.
