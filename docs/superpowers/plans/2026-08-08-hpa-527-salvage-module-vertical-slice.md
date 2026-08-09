# HPA-527 Salvage Module Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six temporary Salvage Modules with one stable three-card draft after waves 2, 4, and 6, authoritative intermission gating, run-stat integration through the existing resolver, and a portrait-mobile snapshot-driven picker UI.

**Architecture:** `GameSession` owns run-only module state, offer generation boundaries, selection, economy effects, and build/wave gating. `TowerStatsResolver` appends one pure `RunModuleRules` step after the existing base → campaign → stage pipeline, while `OrionDefenseGame` only refreshes Flame components and pacing. Flutter renders immutable `GameSnapshot` module data through a focused draft-panel widget.

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
- Keep all six effects on existing stat/economy seams; no generic event bus, effect-command graph, generated attacks, recursion, or cap framework.
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
- `lib/game/orion_defense_game.dart` — bridge selection, refresh towers, suspend/restart auto-start countdown, block board taps during offer.
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
- `run_module.dart` must not import `game_models.dart`; later rules map affinity to `TowerType`.

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

```bash
flutter test test/game/module_offer_picker_test.dart
```

Expected: compile failure because the module domain and picker do not exist yet.

- [ ] **Step 3: Implement the module domain**

Create `lib/game/modules/run_module.dart` with these public shapes:

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
```

Define `const runModuleCatalog` in exactly this order and expose `runModuleDefinition(id)` using `firstWhere`:

```dart
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
      throw StateError(
        'Not enough eligible Salvage Modules for a $count-card offer.',
      );
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
- Consumes module-domain types from Task 1.
- Produces `RunModuleRules.isEligible(...)` and `RunModuleRules.applyTowerStats(...)`.
- Extends `TowerStatsResolver.resolve(..., Iterable<RunModuleId> runModules = const [])`.

- [ ] **Step 1: Write exact rule tests**

Create `test/game/run_module_rules_test.dart`:

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
        RunModuleRules.isEligible(
          cryo,
          unlockedTowerTypes: const [TowerType.laser],
        ),
        isFalse,
      );
      expect(
        RunModuleRules.isEligible(
          cryo,
          unlockedTowerTypes: const [TowerType.cryo],
        ),
        isTrue,
      );
    });
  });

  group('RunModuleRules.applyTowerStats', () {
    test('Heavy Caliber and Long Sight compose from resolved values', () {
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
        RunModuleRules.applyTowerStats(
          cryo,
          const [RunModuleId.cryoReservoir],
        ).slowDuration,
        closeTo(cryo.slowDuration + 0.60, 1e-9),
      );
      expect(
        RunModuleRules.applyTowerStats(
          laser,
          const [RunModuleId.cryoReservoir],
        ).slowDuration,
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

- [ ] **Step 2: Add resolver-order regression tests**

Import `run_module.dart` in `test/game/tower_stats_resolver_test.dart`, then add:

```dart
test('applies run modules after campaign modifiers', () {
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

  final current = TowerStatsResolver.resolve(
    placed,
    stageModifiers: const [StageModifier.amplifiedGravityWells],
  );
  final explicitEmpty = TowerStatsResolver.resolve(
    placed,
    stageModifiers: const [StageModifier.amplifiedGravityWells],
    runModules: const [],
  );

  expect(explicitEmpty.damage, current.damage);
  expect(explicitEmpty.range, current.range);
  expect(explicitEmpty.fieldRadius, current.fieldRadius);
  expect(explicitEmpty.fieldDuration, current.fieldDuration);
});
```

- [ ] **Step 3: Run focused tests and verify red**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
```

Expected: compile failures for missing rules and new resolver/copy fields.

- [ ] **Step 4: Extend `TowerStats.copyWith` narrowly**

In `lib/game/models/game_models.dart`, add only these nullable inputs to the existing method:

```dart
double? range,
double? fireInterval,
double? splashRadius,
```

Wire them into the returned `TowerStats`:

```dart
range: range ?? this.range,
fireInterval: fireInterval ?? this.fireInterval,
splashRadius: splashRadius ?? this.splashRadius,
```

Keep every other existing copy field unchanged.

- [ ] **Step 5: Implement `RunModuleRules`**

Create `lib/game/rules/run_module_rules.dart`. `isEligible` maps affinity to currently unlocked tower types. `applyTowerStats` loops over `runModuleCatalog` order, skips unacquired definitions, and uses these transformations:

```dart
switch (definition.id) {
  case RunModuleId.heavyCaliber:
    stats = stats.copyWith(
      damage: stats.damage * 1.20,
      fireInterval: stats.fireInterval * 1.10,
    );
  case RunModuleId.overclockRelay:
    stats = stats.copyWith(
      fireInterval: stats.fireInterval * 0.85,
      damage: stats.damage * 0.92,
    );
  case RunModuleId.longSight:
    stats = stats.copyWith(range: stats.range * 1.15);
  case RunModuleId.cryoReservoir:
    if (stats.type == TowerType.cryo) {
      stats = stats.copyWith(slowDuration: stats.slowDuration + 0.60);
    }
  case RunModuleId.rocketFusing:
    if (stats.type == TowerType.rocket) {
      stats = stats.copyWith(
        splashRadius: stats.splashRadius * 1.25,
        damage: stats.damage * 0.90,
      );
    }
  case RunModuleId.emergencySalvage:
    break;
}
```

Use a `Set<RunModuleId>` locally to avoid applying duplicate IDs if a caller ever passes them twice.

- [ ] **Step 6: Append run modules to `TowerStatsResolver`**

Import `run_module.dart` and `run_module_rules.dart`. Extend `resolve`:

```dart
static TowerStats resolve(
  PlacedTower tower, {
  CampaignModifiers campaignModifiers = CampaignModifiers.empty,
  Iterable<StageModifier> stageModifiers = const [],
  Iterable<RunModuleId> runModules = const [],
})
```

Replace the direct stage-rule return with:

```dart
final stageAdjusted = StageModifierRules.effectiveTowerStats(
  resolvedStats: campaignAdjusted,
  stageModifiers: stageModifiers,
);
return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
```

Update the resolver comment to state `base → campaign → stage → run modules`.

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
- Produces `GameSession.pendingRunModuleOffer`, `GameSession.acquiredRunModules`, and `GameSession.selectRunModule(...)`.
- `GameSnapshot` gains `pendingRunModuleOffer` and `acquiredRunModules`.

- [ ] **Step 1: Add a fixed picker test double**

In `test/game/game_session_test.dart`, import the module and picker files and add:

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

- [ ] **Step 2: Write draft schedule and snapshot-stability tests**

Use `GameSession.initial(offerPicker: picker)`, clear waves via `startWave()` / `finishActiveWave()`, and assert:

```dart
expect(session.pendingRunModuleOffer, isNull);

expect(session.startWave(), isTrue);
session.finishActiveWave();
expect(session.pendingRunModuleOffer, isNull);

expect(session.startWave(), isTrue);
session.finishActiveWave();
final firstOffer = session.pendingRunModuleOffer!;
expect(firstOffer.draftNumber, 1);
expect(firstOffer.moduleIds, const [
  RunModuleId.heavyCaliber,
  RunModuleId.longSight,
  RunModuleId.emergencySalvage,
]);
expect(session.snapshot().pendingRunModuleOffer, same(firstOffer));
expect(session.snapshot().pendingRunModuleOffer, same(firstOffer));
```

After selecting one card, continue through waves 4 and 6 and verify drafts 2 and 3. Verify no offer after waves 1, 3, 5, 7, or terminal wave 8.

- [ ] **Step 3: Write selection and one-time economy tests**

For a fixed offer containing Emergency Salvage:

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

Add separate assertions for a wrong `offerId` and a module not present in the offer; both return `false` and leave gold/acquired/pending state unchanged.

- [ ] **Step 4: Write acquired-exclusion and no-duplicate offer tests**

After selecting a module from draft 1, advance to draft 2 and assert:

```dart
expect(session.pendingRunModuleOffer!.moduleIds, isNot(contains(selectedId)));
expect(
  session.pendingRunModuleOffer!.moduleIds.toSet(),
  hasLength(session.pendingRunModuleOffer!.moduleIds.length),
);
```

The fixed picker must only request candidates supplied by the session, proving acquired IDs were filtered before selection.

- [ ] **Step 5: Write authoritative gating tests**

Reach a pending draft with a placed tower and enough gold. While pending, assert:

```dart
expect(
  session.validatePlacement(const GridPosition(0, 0), TowerType.laser).failure,
  PlacementFailure.invalidPhase,
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
```

After a valid module selection, verify `startWave()` can succeed again and ordinary build validations return to their previous behavior.

- [ ] **Step 6: Write restart and monotonic-offer-ID regression**

Capture the first offer ID, restart, clear waves 1 and 2 again with enough fixed-picker entries, then assert:

```dart
final oldOfferId = session.pendingRunModuleOffer!.offerId;
session.restart();
expect(session.acquiredRunModules, isEmpty);
expect(session.pendingRunModuleOffer, isNull);

// Clear waves 1 and 2 again.
expect(session.pendingRunModuleOffer!.offerId, greaterThan(oldOfferId));
```

- [ ] **Step 7: Run session tests and verify red**

```bash
flutter test test/game/game_session_test.dart
```

Expected: compile failures until the new session/snapshot APIs exist.

- [ ] **Step 8: Extend `GameSnapshot`**

Import `../modules/run_module.dart` from `game_models.dart`. Add constructor inputs:

```dart
this.pendingRunModuleOffer,
List<RunModuleId> acquiredRunModules = const [],
```

Store acquired IDs with `List.unmodifiable`, add fields:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
```

and change:

```dart
bool get canStartWave =>
    phase == GamePhase.build && pendingRunModuleOffer == null;
```

- [ ] **Step 9: Inject the picker and add session-owned module state**

Add `ModuleOfferPicker? offerPicker` to `GameSession.initial`, default it to `RandomModuleOfferPicker()`, and store:

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

- [ ] **Step 10: Centralize build mutation gating**

Add:

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Use `_canMutateBuild` for placement validation, upgrade, specialization, sale, targeting-mode changes, and `startWave()`. Preserve every existing validation after the phase/intermission gate. Placement continues to report `PlacementFailure.invalidPhase` rather than adding a module-specific failure enum.

- [ ] **Step 11: Generate offers only from `finishActiveWave()`**

After `_waveIndex` increments, handle terminal victory first. Otherwise set `_phase = GamePhase.build` and call:

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

`GameSession.snapshot()` only projects `_pendingRunModuleOffer`; it never calls the picker.

- [ ] **Step 12: Implement atomic selection**

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

- [ ] **Step 13: Project state and clear temporary data on restart**

Pass `pendingRunModuleOffer` and `acquiredRunModules` into `GameSnapshot` from `snapshot()`.

In `restart()` add:

```dart
_acquiredRunModules.clear();
_pendingRunModuleOffer = null;
_completedModuleDrafts = 0;
```

Do not reset `_nextModuleOfferId`.

- [ ] **Step 14: Run session tests green**

```bash
flutter test test/game/game_session_test.dart
```

Expected: all existing and new tests pass.

- [ ] **Step 15: Commit Task 3**

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

In `test/game/orion_defense_game_test.dart`, add an injectable fixed `ModuleOfferPicker` and cover these behaviors:

1. After wave 2 completes with auto-start enabled, `snapshot.pendingRunModuleOffer != null` and `autoStartCountdownRemaining == null`.
2. Selecting a valid card clears the offer and sets `autoStartCountdownRemaining` to `OrionDefenseGame.autoStartCountdownSeconds`.
3. Heavy Caliber updates an already placed tower's runtime damage and fire interval.
4. A tower placed after Heavy Caliber selection receives the same modifiers.

Inspect tower components through the existing Flame child tree rather than exposing a new mutable collection:

```dart
final component = game.children.whereType<TowerComponent>().single;
final base = GameBalance.towerStats(TowerType.laser, level: 1);
expect(component.stats.damage, closeTo(base.damage * 1.20, 1e-9));
```

- [ ] **Step 2: Run orchestration tests and verify red**

```bash
flutter test test/game/orion_defense_game_test.dart
```

Expected: compile/assertion failures for missing picker injection, module bridge, and refresh behavior.

- [ ] **Step 3: Let `TowerComponent` carry current run modules**

Add constructor input:

```dart
Iterable<RunModuleId> runModules = const [],
```

Store an immutable list and pass it into every `TowerStatsResolver.resolve` call. Add:

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

Update `updateTower(...)` so it also passes the stored `runModules` when re-resolving after upgrades/specialization.

- [ ] **Step 4: Allow `OrionDefenseGame` picker injection for tests**

Add optional constructor input:

```dart
ModuleOfferPicker? moduleOfferPicker,
```

and pass it to `GameSession.initial(offerPicker: moduleOfferPicker)`. Production callers omit it.

- [ ] **Step 5: Pass acquired modules to newly created tower components**

In `_addTowerComponent`, add:

```dart
runModules: _session.acquiredRunModules,
```

No other Flame component receives module-domain state.

- [ ] **Step 6: Add selection bridge and refresh existing tower components**

Add:

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

Do not introduce feedback events or component-side eligibility decisions.

- [ ] **Step 7: Suspend auto-start when a draft opens**

In `_finishWaveIfComplete()` after `_session.finishActiveWave()`:

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

Also add `_session.pendingRunModuleOffer == null` to `_startAutoStartCountdownIfNeeded()` so no caller can create a hidden countdown during an intermission.

- [ ] **Step 8: Prevent board selection changes beneath the modal panel**

At the start of `onTapDown`, after terminal-state rejection, add:

```dart
if (_session.pendingRunModuleOffer != null) {
  return;
}
```

This is presentation hygiene; `GameSession` remains the authoritative mutation gate.

- [ ] **Step 9: Run orchestration and resolver regressions green**

```bash
flutter test test/game/orion_defense_game_test.dart test/game/tower_stats_resolver_test.dart
```

Expected: all pass.

- [ ] **Step 10: Commit Task 4**

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
- Produces `RunModuleDraftPanel({required RunModuleOffer offer, required ValueChanged<RunModuleId> onSelected})`.
- Produces `AcquiredRunModuleStrip({required List<RunModuleId> moduleIds})`.

- [ ] **Step 1: Write 360×640 widget tests first**

Create `test/widget/run_module_draft_panel_test.dart` with a fixed 360×640 `MediaQuery` harness and:

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

```dart
expect(find.text('Salvage Module 2 of 3'), findsOneWidget);
expect(find.text('Heavy Caliber'), findsOneWidget);
expect(find.text('Emergency Salvage'), findsOneWidget);
expect(find.text('Cryo Reservoir'), findsOneWidget);
expect(find.text('Universal'), findsWidgets);
expect(find.text('Cryo'), findsOneWidget);
expect(tester.takeException(), isNull);
```

Tap `Heavy Caliber` and assert the callback receives `RunModuleId.heavyCaliber` once. Render `AcquiredRunModuleStrip` with two IDs and assert both titles appear; render it with an empty list and assert no module title appears.

- [ ] **Step 2: Run widget test and verify red**

```bash
flutter test test/widget/run_module_draft_panel_test.dart
```

Expected: compile failure because the widget file does not exist.

- [ ] **Step 3: Implement `RunModuleDraftPanel`**

Create `lib/game/ui/run_module_draft_panel.dart` using `Material`, `SafeArea`, and `SingleChildScrollView`. The public widget must follow this structure:

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

Implement `_RunModuleCard` as a `FilledButton.tonal` or `Card` + `InkWell` containing title, one-sentence effect, and affinity label. Do not add confirmation, reroll, rarity, or independent gameplay state.

- [ ] **Step 4: Implement `AcquiredRunModuleStrip` in the same focused file**

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

- [ ] **Step 5: Wire both widgets into `OrionGamePage`**

Import `run_module_draft_panel.dart`.

Inside the existing top HUD `Column`, add after `_Hud`:

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

Do not add eligibility or effect calculations to the UI.

- [ ] **Step 6: Run widget tests green**

```bash
flutter test test/widget/run_module_draft_panel_test.dart test/widget_test.dart
```

Expected: all pass with no overflow exception at 360×640.

- [ ] **Step 7: Commit Task 5**

```bash
git add lib/game/ui/run_module_draft_panel.dart lib/game/ui/orion_game_page.dart test/widget/run_module_draft_panel_test.dart
git commit -m "feat: add salvage module intermission UI (HPA-527)"
```

---

### Task 6: Verify the complete vertical slice and record two human playtests

**Files:**
- No new report or evidence file.
- If verification exposes a defect, make the smallest correction in the task-owned source/test files that caused it and rerun that task's focused checks before continuing.

**Interfaces:**
- Consumes all previous tasks.
- Produces a verified implementation branch plus concise Stage 1 and later-stage observations in the implementation PR body or a PR comment.

- [ ] **Step 1: Run all focused tests**

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

- [ ] **Step 3: Run the full existing test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Manual Stage 1 playtest at 1×**

Play Outpost Alpha through all three drafts and record exactly these four observations in the implementation PR:

1. Draft comprehension: yes/no, plus one sentence.
2. Mission pacing: improved / neutral / disruptive, plus one sentence.
3. Dead or mandatory card observed: module name or `none`.
4. Selected-module effect noticeable: yes/no, plus one sentence.

Do not add telemetry or structured evidence export.

- [ ] **Step 5: Manual later-stage playtest at 1×**

Choose one unlocked later main-path stage and record the same four observations. Prefer a stage with enough enemy variety to notice universal, Rocket, and Cryo trade-offs.

If both human runs reveal an obviously weak or overpowering constant, edit only the relevant constants/copy in `run_module_rules.dart` / `run_module.dart`, update its exact-value test, rerun Steps 1–3, and include that tuning change in the implementation commit that owns the rule.

- [ ] **Step 6: Walk the acceptance checklist**

Verify each item against tests and the two playthroughs:

- [ ] drafts occur after waves 2, 4, and 6 only;
- [ ] each offer remains unchanged until selection;
- [ ] acquired cards do not reappear;
- [ ] each offer contains three distinct IDs;
- [ ] stale, duplicate, and non-offered selections do not mutate state;
- [ ] build, upgrade, specialize, sell, retarget, and start-wave are blocked while pending;
- [ ] auto-start resumes with a fresh full countdown;
- [ ] existing towers update immediately after a stat module;
- [ ] towers placed after selection inherit the same modules;
- [ ] Emergency Salvage adds 90 gold once;
- [ ] restart clears temporary modules and pending offer;
- [ ] returning to the world map abandons run-only state with the game instance;
- [ ] 360×640 draft UI has no overflow;
- [ ] no save-schema or package dependency changed.

Do not claim completion until every automated check has fresh passing output and the two human observations are recorded.

---

## Self-Review

**1. Spec coverage:** Tasks 1–2 implement the catalog, picker, eligibility, and base → campaign → stage → run-module stat pipeline. Task 3 owns the 2/4/6 lifecycle, stable offers, stale-tap protection, acquired exclusion, Emergency Salvage, authoritative gating, and restart cleanup. Task 4 handles existing/new tower consistency and auto-start pacing. Task 5 implements the blocking 360×640 snapshot-driven UI and acquired strip. Task 6 covers focused/full automated verification plus the two required human 1× checks. Every design acceptance criterion maps to a task.

**2. Placeholder scan:** No TBD/TODO markers or symbolic shell paths remain. Every new public type and method used by a later task is defined earlier with a concrete signature. Human validation asks for four exact observations rather than an undefined report.

**3. Type consistency:** `RunModuleId`, `RunModuleDefinition`, and `RunModuleOffer` originate in `run_module.dart`; `ModuleOfferPicker` originates in `module_offer_picker.dart`; `RunModuleRules` consumes those types; `GameSession` injects `ModuleOfferPicker`; `GameSnapshot` projects `RunModuleOffer` plus `List<RunModuleId>`; `TowerStatsResolver` and `TowerComponent` both use `Iterable<RunModuleId>` inputs; `OrionDefenseGame.selectRunModule(int, RunModuleId)` matches `RunModuleDraftPanel`'s callback path.
