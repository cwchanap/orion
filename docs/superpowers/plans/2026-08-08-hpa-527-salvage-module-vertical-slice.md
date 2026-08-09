# HPA-527 Salvage Module Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six temporary Salvage Modules with stable three-card drafts after waves 2, 4, and 6, authoritative intermission gating, player-visible resolved effects, and a portrait-mobile snapshot-driven picker UI.

**Architecture:** `GameSession` owns run-only module state, offer generation, selection, one-time economy effects, and build/wave gating. `TowerStatsResolver` appends one pure `RunModuleRules` step after the existing base → campaign → stage pipeline, while `OrionDefenseGame` refreshes Flame components and pacing. Flutter renders immutable module data and resolved selected-tower stats from `GameSnapshot`.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- Keep `GamePhase` unchanged: a pending module offer is still `GamePhase.build`.
- Exactly six initial modules: Heavy Caliber, Overclock Relay, Long Sight, Emergency Salvage, Cryo Reservoir, Rocket Fusing.
- Definition-owned initial tuning: Heavy Caliber `damage × 1.20`, `fireInterval × 1.10`; Overclock Relay `fireInterval × 0.85`, `damage × 0.92`; Long Sight `range × 1.15`; Emergency Salvage `+90` gold once; Cryo Reservoir `slowDuration + 0.60`; Rocket Fusing `splashRadius × 1.25`, `damage × 0.90`.
- Balance magnitudes live only in `RunModuleDefinition`; `RunModuleRules` and `GameSession` read them instead of repeating magic numbers.
- Drafts open only after completed waves 2, 4, and 6.
- Each offer contains exactly three distinct eligible, non-acquired module IDs and is generated once.
- Unselected cards may reappear later; do not store complete offer history.
- Use ordinary randomness in production and an injectable picker in tests; do not add seeds, algorithm versions, hashes, fingerprints, or canonical serialization.
- Use one monotonic `offerId` for stale callback protection; do not add a run-identity model.
- Apply tower effects in order: base → campaign → stage → run modules.
- Keep all six effects on existing stat/economy seams; no generic event bus, effect-command graph, generated attacks, recursion, or cap framework.
- Run-only module state is never written to `CampaignSave`.
- UI remains snapshot-driven; widgets do not invoke module eligibility/rule logic or inspect mutable Flame collections.
- Selected-tower combat stats are projected through `GameSnapshot` so Long Sight and damage/cadence trade-offs are inspectable without adding a range-ring subsystem.
- Do not add Mission Report, blueprint progression, Codex module pages, audio, haptics, rarity, rerolls, decks, inventories, or mid-run resume.
- Minimum mobile target is 360×640 logical pixels.
- Required final checks: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`.

## File Structure

### Create

- `lib/game/modules/run_module.dart` — IDs, affinity, single-source tuning, derived effect copy, catalog, immutable offer.
- `lib/game/rules/module_offer_picker.dart` — injectable three-card picker and production random implementation.
- `lib/game/rules/run_module_rules.dart` — eligibility and pure tower-stat application from definition values.
- `lib/game/ui/run_module_draft_panel.dart` — blocking draft panel plus acquired-module reminder strip.
- `test/game/game_test_fixtures.dart` — small multi-wave empty-stage fixture shared by session/Flame tests.
- `test/game/module_offer_picker_test.dart` — picker contract.
- `test/game/run_module_rules_test.dart` — eligibility, exact tuning application, and composition.
- `test/widget/run_module_draft_panel_test.dart` — 360×640 draft/strip behavior.

### Modify

- `lib/game/models/game_models.dart` — extend `TowerStats.copyWith`; add module and resolved selected-tower data to `GameSnapshot`; make `canStartWave` pending-offer aware.
- `lib/game/rules/tower_stats_resolver.dart` — append `RunModuleRules` after stage resolution.
- `lib/game/rules/game_session.dart` — own offer/acquired state, schedule, selection, economy effect, snapshot-resolved selected tower, gating, restart.
- `lib/game/components/tower_component.dart` — resolve and refresh with current run modules.
- `lib/game/orion_defense_game.dart` — bridge selection, refresh towers, suspend/restart auto-start, block board taps, publish clear draft-block feedback.
- `lib/game/ui/orion_game_page.dart` — render acquired reminders, blocking draft panel, and resolved tower summary from snapshot.
- `test/game/tower_stats_resolver_test.dart` — pipeline-order and no-module regression coverage.
- `test/game/game_session_test.dart` — draft schedule, offer stability, selection, gating, resolved summary, restart.
- `test/game/orion_defense_game_test.dart` — component refresh, auto-start guards, direct denial feedback.
- Existing selected-tower widget tests under `test/widget/` as required by compiler failures — update their `GameSnapshot` fixtures with `selectedTowerStats` rather than adding UI-side rule calculation.

---

### Task 1: Add the single-source module catalog and injectable offer picker

**Files:**
- Create: `lib/game/modules/run_module.dart`
- Create: `lib/game/rules/module_offer_picker.dart`
- Create: `test/game/module_offer_picker_test.dart`

**Interfaces:**
- Produces `RunModuleId`, `RunModuleAffinity`, `RunModuleDefinition`, `RunModuleOffer`, `runModuleCatalog`, `runModuleDefinition(RunModuleId)`.
- Produces `ModuleOfferPicker.pick(List<RunModuleId>, {required int count})` and `RandomModuleOfferPicker`.
- `run_module.dart` may import `../util/format.dart` but must not import `game_models.dart`.

- [ ] **Step 1: Write picker tests first**

Create `test/game/module_offer_picker_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/modules/run_module.dart';
import 'package:orion/game/rules/module_offer_picker.dart';

void main() {
  group('RandomModuleOfferPicker', () {
    test('returns requested distinct candidates without mutating input', () {
      final picker = RandomModuleOfferPicker(math.Random(7));
      final candidates = RunModuleId.values.toList();
      final before = List<RunModuleId>.of(candidates);

      final result = picker.pick(candidates, count: 3);

      expect(result, hasLength(3));
      expect(result.toSet(), hasLength(3));
      expect(result.every(candidates.contains), isTrue);
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

- [ ] **Step 2: Run the picker test and verify red**

```bash
flutter test test/game/module_offer_picker_test.dart
```

Expected: compile failure because the module domain and picker do not exist.

- [ ] **Step 3: Implement definition-owned tuning and derived copy**

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
      'All towers deal ${percent(damageMultiplier - 1)} more damage; '
      'attacks take ${percent(fireIntervalMultiplier - 1)} longer.',
    RunModuleId.overclockRelay =>
      'All towers attack ${percent(1 - fireIntervalMultiplier)} sooner; '
      'damage drops ${percent(1 - damageMultiplier)}.',
    RunModuleId.longSight =>
      'All towers gain ${percent(rangeMultiplier - 1)} range.',
    RunModuleId.emergencySalvage =>
      'Gain $immediateGold gold immediately.',
    RunModuleId.cryoReservoir =>
      'Cryo slows last ${number(slowDurationBonus)} seconds longer.',
    RunModuleId.rocketFusing =>
      'Rocket splash grows ${percent(splashRadiusMultiplier - 1)}; '
      'direct damage drops ${percent(1 - damageMultiplier)}.',
  };
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

RunModuleDefinition runModuleDefinition(RunModuleId id) =>
    runModuleCatalog.firstWhere((definition) => definition.id == id);
```

Add a small catalog test group to `module_offer_picker_test.dart` asserting the six IDs, the current Overclock/Salvage values, and derived copy:

```dart
test('catalog owns tuning used by player copy', () {
  final overclock = runModuleDefinition(RunModuleId.overclockRelay);
  final salvage = runModuleDefinition(RunModuleId.emergencySalvage);

  expect(overclock.fireIntervalMultiplier, 0.85);
  expect(overclock.damageMultiplier, 0.92);
  expect(overclock.effectText, contains('15%'));
  expect(overclock.effectText, contains('8%'));
  expect(salvage.immediateGold, 90);
  expect(salvage.effectText, contains('90 gold'));
});
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

- [ ] **Step 5: Run Task 1 green**

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

### Task 2: Apply definition-owned module tuning through the existing resolver

**Files:**
- Create: `lib/game/rules/run_module_rules.dart`
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/tower_stats_resolver.dart`
- Create: `test/game/run_module_rules_test.dart`
- Modify: `test/game/tower_stats_resolver_test.dart`

**Interfaces:**
- Consumes `RunModuleDefinition` tuning from Task 1.
- Produces `RunModuleRules.isEligible(...)` and `RunModuleRules.applyTowerStats(...)`.
- Extends `TowerStatsResolver.resolve(..., Iterable<RunModuleId> runModules = const [])`.

- [ ] **Step 1: Write exact rule tests, including Overclock and composition**

Create `test/game/run_module_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/modules/run_module.dart';
import 'package:orion/game/rules/run_module_rules.dart';

void main() {
  group('RunModuleRules.isEligible', () {
    test('universal is always eligible and affinity requires unlock', () {
      expect(
        RunModuleRules.isEligible(
          runModuleDefinition(RunModuleId.longSight),
          unlockedTowerTypes: const [],
        ),
        isTrue,
      );
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
    test('Overclock Relay applies exact interval and damage multipliers', () {
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final definition = runModuleDefinition(RunModuleId.overclockRelay);

      final resolved = RunModuleRules.applyTowerStats(
        base,
        const [RunModuleId.overclockRelay],
      );

      expect(
        resolved.fireInterval,
        closeTo(base.fireInterval * definition.fireIntervalMultiplier, 1e-9),
      );
      expect(
        resolved.damage,
        closeTo(base.damage * definition.damageMultiplier, 1e-9),
      );
    });

    test('Heavy Caliber and Overclock Relay compose multiplicatively', () {
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
      final overclock = runModuleDefinition(RunModuleId.overclockRelay);

      final resolved = RunModuleRules.applyTowerStats(
        base,
        const [RunModuleId.heavyCaliber, RunModuleId.overclockRelay],
      );

      expect(
        resolved.damage,
        closeTo(
          base.damage * heavy.damageMultiplier * overclock.damageMultiplier,
          1e-9,
        ),
      );
      expect(
        resolved.fireInterval,
        closeTo(
          base.fireInterval *
              heavy.fireIntervalMultiplier *
              overclock.fireIntervalMultiplier,
          1e-9,
        ),
      );
    });

    test('Long Sight, Cryo Reservoir, and Rocket Fusing use definitions', () {
      final laser = GameBalance.towerStats(TowerType.laser, level: 1);
      final cryo = GameBalance.towerStats(TowerType.cryo, level: 1);
      final rocket = GameBalance.towerStats(TowerType.rocket, level: 1);
      final sight = runModuleDefinition(RunModuleId.longSight);
      final reservoir = runModuleDefinition(RunModuleId.cryoReservoir);
      final fusing = runModuleDefinition(RunModuleId.rocketFusing);

      expect(
        RunModuleRules.applyTowerStats(
          laser,
          const [RunModuleId.longSight],
        ).range,
        closeTo(laser.range * sight.rangeMultiplier, 1e-9),
      );
      expect(
        RunModuleRules.applyTowerStats(
          cryo,
          const [RunModuleId.cryoReservoir],
        ).slowDuration,
        closeTo(cryo.slowDuration + reservoir.slowDurationBonus, 1e-9),
      );
      final rocketResolved = RunModuleRules.applyTowerStats(
        rocket,
        const [RunModuleId.rocketFusing],
      );
      expect(
        rocketResolved.splashRadius,
        closeTo(rocket.splashRadius * fusing.splashRadiusMultiplier, 1e-9),
      );
      expect(
        rocketResolved.damage,
        closeTo(rocket.damage * fusing.damageMultiplier, 1e-9),
      );
    });
  });
}
```

- [ ] **Step 2: Add resolver-order regression tests**

In `test/game/tower_stats_resolver_test.dart`, add imports and:

```dart
test('applies run modules after campaign modifiers', () {
  const placed = PlacedTower(
    id: 1,
    type: TowerType.laser,
    position: GridPosition(0, 0),
  );
  const campaign = CampaignModifiers(laserDamageFraction: 0.10);
  final base = GameBalance.towerStats(TowerType.laser, level: 1);
  final heavy = runModuleDefinition(RunModuleId.heavyCaliber);

  final resolved = TowerStatsResolver.resolve(
    placed,
    campaignModifiers: campaign,
    runModules: const [RunModuleId.heavyCaliber],
  );

  expect(
    resolved.damage,
    closeTo(base.damage * 1.10 * heavy.damageMultiplier, 1e-9),
  );
});

test('empty run modules preserve current resolver output', () {
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

- [ ] **Step 3: Run rule/resolver tests red**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
```

Expected: compile failure for missing rules and new resolver/copy fields.

- [ ] **Step 4: Extend `TowerStats.copyWith` narrowly**

Add only:

```dart
double? range,
double? fireInterval,
double? splashRadius,
```

and wire them to the returned `TowerStats` with `?? this.<field>`.

- [ ] **Step 5: Implement data-driven `RunModuleRules`**

Create `lib/game/rules/run_module_rules.dart`:

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
      if (!acquired.contains(definition.id) ||
          !_appliesToTower(definition.affinity, stats.type)) {
        continue;
      }
      stats = stats.copyWith(
        damage: stats.damage * definition.damageMultiplier,
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

  static bool _appliesToTower(RunModuleAffinity affinity, TowerType type) {
    return switch (affinity) {
      RunModuleAffinity.universal => true,
      RunModuleAffinity.cryo => type == TowerType.cryo,
      RunModuleAffinity.rocket => type == TowerType.rocket,
    };
  }
}
```

- [ ] **Step 6: Append run modules to `TowerStatsResolver`**

Extend `resolve` with `Iterable<RunModuleId> runModules = const []`, retain the existing base/campaign/stage code, then:

```dart
final stageAdjusted = StageModifierRules.effectiveTowerStats(
  resolvedStats: campaignAdjusted,
  stageModifiers: stageModifiers,
);
return RunModuleRules.applyTowerStats(stageAdjusted, runModules);
```

Update its comment to `base → campaign → stage → run modules`.

- [ ] **Step 7: Run Task 2 green and commit**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git add lib/game/models/game_models.dart lib/game/rules/run_module_rules.dart lib/game/rules/tower_stats_resolver.dart test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git commit -m "feat: apply salvage modules to tower stats (HPA-527)"
```

---

### Task 3: Add multi-wave fixtures and make `GameSession` own the draft lifecycle

**Files:**
- Create: `test/game/game_test_fixtures.dart`
- Modify: `lib/game/models/game_models.dart`
- Modify: `lib/game/rules/game_session.dart`
- Modify: `test/game/game_session_test.dart`

**Interfaces:**
- Produces `stageWithWaveCount(int count)` for session/Flame tests.
- Produces `GameSession.pendingRunModuleOffer`, `GameSession.acquiredRunModules`, `GameSession.selectRunModule(...)`.
- `GameSnapshot` gains `pendingRunModuleOffer`, `acquiredRunModules`, and `selectedTowerStats`.

- [ ] **Step 1: Add the shared empty-wave stage fixture**

Create `test/game/game_test_fixtures.dart`:

```dart
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

StageDefinition stageWithWaveCount(int count) {
  if (count <= 0) throw ArgumentError.value(count, 'count');
  return StageDefinition(
    id: 'test-$count-waves',
    name: 'Test $count Waves',
    mapLabel: 'Test',
    description: 'Deterministic empty-wave test stage',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      count,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    mapColumn: 0,
    mapRow: 0,
  );
}
```

- [ ] **Step 2: Add a fixed picker and explicit wave helper in session tests**

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

Use `stageWithWaveCount(8)` for every schedule/restart test instead of inventing ad hoc stages.

- [ ] **Step 3: Write schedule, stability, selection, and gating tests**

Cover waves 1–8 using the helper. After wave 2:

```dart
final offer = session.pendingRunModuleOffer!;
expect(offer.draftNumber, 1);
expect(session.snapshot().pendingRunModuleOffer, same(offer));
expect(session.snapshot().pendingRunModuleOffer, same(offer));
```

Select one offered ID, complete waves 3–4, repeat for draft 2, then waves 5–6 for draft 3. Assert no draft after 1/3/5/7/8.

For Emergency Salvage, read the expected reward from the definition:

```dart
final reward = runModuleDefinition(RunModuleId.emergencySalvage).immediateGold;
final beforeGold = session.gold;
expect(
  session.selectRunModule(
    offerId: offer.offerId,
    moduleId: RunModuleId.emergencySalvage,
  ),
  isTrue,
);
expect(session.gold, beforeGold + reward);
```

Repeat the same selection and verify `false` with no second reward. Add wrong-offer and non-offered no-op cases.

While a draft is pending, assert placement, upgrade, specialization, sale, retarget, and `startWave` are all rejected. After selection they recover.

- [ ] **Step 4: Write resolved selected-tower projection test**

Place a Laser, reach draft 1 with a fixed Long Sight offer, select it, then:

```dart
final tower = session.towers.single;
final snapshot = session.snapshot(selectedTower: tower);
final base = GameBalance.towerStats(TowerType.laser, level: 1);
final sight = runModuleDefinition(RunModuleId.longSight);

expect(
  snapshot.selectedTowerStats!.range,
  closeTo(base.range * sight.rangeMultiplier, 1e-9),
);
```

This proves the UI can display resolved module effects without invoking rules itself.

- [ ] **Step 5: Write restart/monotonic offer-ID test**

Capture a draft offer ID, call `restart()`, verify acquired/pending/draft-count state clears, then reopen draft 1 and assert the new offer ID is greater than the old one.

- [ ] **Step 6: Run session tests red**

```bash
flutter test test/game/game_session_test.dart
```

Expected: compile/assertion failures until the new APIs exist.

- [ ] **Step 7: Extend `GameSnapshot`**

Import the module domain in `game_models.dart`. Add optional constructor/fields:

```dart
this.pendingRunModuleOffer,
List<RunModuleId> acquiredRunModules = const [],
this.selectedTowerStats,
```

Store acquired IDs with `List.unmodifiable` and add:

```dart
final RunModuleOffer? pendingRunModuleOffer;
final List<RunModuleId> acquiredRunModules;
final TowerStats? selectedTowerStats;

bool get canStartWave =>
    phase == GamePhase.build && pendingRunModuleOffer == null;
```

- [ ] **Step 8: Inject picker and add session-owned state**

Add `ModuleOfferPicker? offerPicker` to `GameSession.initial`, default to `RandomModuleOfferPicker()`, and store:

```dart
final ModuleOfferPicker _offerPicker;
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _completedModuleDrafts = 0;
int _nextModuleOfferId = 1;
```

Expose immutable acquired IDs and the pending offer.

- [ ] **Step 9: Centralize authoritative build gating**

```dart
bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Use it for placement validation, upgrade, specialization, sale, targeting changes, and `startWave()`. Preserve every existing non-phase validation.

- [ ] **Step 10: Open drafts only from `finishActiveWave()`**

After incrementing `_waveIndex`, process victory first, then build phase, then:

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

  final ids = _offerPicker.pick(candidates, count: 3);
  _pendingRunModuleOffer = RunModuleOffer(
    offerId: _nextModuleOfferId++,
    draftNumber: _completedModuleDrafts + 1,
    moduleIds: ids,
  );
}
```

- [ ] **Step 11: Implement atomic selection using definition-owned reward**

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
  _completedModuleDrafts += 1;
  return true;
}
```

Neutral definitions have `immediateGold == 0`.

- [ ] **Step 12: Project module state and resolved selected-tower stats**

Import `tower_stats_resolver.dart` in `game_session.dart`. In `snapshot(...)`:

```dart
final resolvedSelectedTower = selectedTower == null
    ? null
    : TowerStatsResolver.resolve(
        selectedTower,
        campaignModifiers: campaignModifiers,
        stageModifiers: stage.modifiers,
        runModules: _acquiredRunModules,
      );
```

Pass `pendingRunModuleOffer`, `acquiredRunModules`, and `selectedTowerStats: resolvedSelectedTower` into `GameSnapshot`.

- [ ] **Step 13: Clear temporary state on restart without reusing IDs**

Add to `restart()`:

```dart
_acquiredRunModules.clear();
_pendingRunModuleOffer = null;
_completedModuleDrafts = 0;
```

Do not reset `_nextModuleOfferId`.

- [ ] **Step 14: Run Task 3 green and commit**

```bash
flutter test test/game/game_session_test.dart
git add test/game/game_test_fixtures.dart lib/game/models/game_models.dart lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: add salvage module draft lifecycle (HPA-527)"
```

---

### Task 4: Refresh Flame stats and make auto-start inert during drafts

**Files:**
- Modify: `lib/game/components/tower_component.dart`
- Modify: `lib/game/orion_defense_game.dart`
- Modify: `test/game/orion_defense_game_test.dart`
- Read/reuse: `test/game/game_test_fixtures.dart`

**Interfaces:**
- Consumes `GameSession.selectRunModule`, `acquiredRunModules`, and resolver `runModules`.
- Produces `TowerComponent.updateRunModules(...)` and `OrionDefenseGame.selectRunModule(...)`.

- [ ] **Step 1: Write multi-wave orchestration tests using the shared fixture**

Use `stageWithWaveCount(8)` plus a fixed picker. Drive empty waves through the real game update path rather than exposing `_session`.

Cover:

1. After wave 2 completes with auto-start enabled, `pendingRunModuleOffer != null` and countdown is null.
2. Calling `game.update(...)` while the offer is pending does not recreate/tick a countdown.
3. Selecting a card starts a fresh `OrionDefenseGame.autoStartCountdownSeconds` countdown when auto-start remains enabled.
4. Heavy Caliber refreshes an existing Laser `TowerComponent`.
5. A Laser placed after selection receives the same definition-owned multipliers.
6. Calling `game.startWave()` while pending keeps the offer and publishes `Choose a Salvage Module first.`.

For runtime stats:

```dart
final component = game.children.whereType<TowerComponent>().single;
final base = GameBalance.towerStats(TowerType.laser, level: 1);
final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
expect(
  component.stats.damage,
  closeTo(base.damage * heavy.damageMultiplier, 1e-9),
);
```

- [ ] **Step 2: Run orchestration test red**

```bash
flutter test test/game/orion_defense_game_test.dart
```

Expected: compile/assertion failures for missing picker injection, bridge, refresh, and pacing guards.

- [ ] **Step 3: Let `TowerComponent` carry current run modules**

Add constructor input `Iterable<RunModuleId> runModules = const []`, store `List.unmodifiable`, and pass it to every `TowerStatsResolver.resolve` call.

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

Update `updateTower(...)` to include stored run modules.

- [ ] **Step 4: Inject picker through `OrionDefenseGame` and new towers**

Add optional constructor input `ModuleOfferPicker? moduleOfferPicker` and pass it to `GameSession.initial(offerPicker: moduleOfferPicker)`.

In `_addTowerComponent` add:

```dart
runModules: _session.acquiredRunModules,
```

- [ ] **Step 5: Add selection bridge and refresh existing towers**

```dart
void selectRunModule(int offerId, RunModuleId moduleId) {
  if (!_session.selectRunModule(offerId: offerId, moduleId: moduleId)) return;

  for (final tower in _towerComponents.values) {
    tower.updateRunModules(_session.acquiredRunModules);
  }
  _startAutoStartCountdownIfNeeded();
  _publishSnapshot();
}
```

- [ ] **Step 6: Suspend auto-start at all pacing boundaries**

In `_finishWaveIfComplete()` after session completion:

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

At the top of `_tickAutoStartCountdown`:

```dart
if (_session.pendingRunModuleOffer != null) {
  _autoStartCountdownRemaining = null;
  return false;
}
```

Add `_session.pendingRunModuleOffer == null` to `_startAutoStartCountdownIfNeeded()`.

- [ ] **Step 7: Block board taps and make direct denial feedback accurate**

At the start of `onTapDown` after terminal-state rejection:

```dart
if (_session.pendingRunModuleOffer != null) return;
```

Add one private constant/helper:

```dart
static const String _moduleDraftBlockingMessage =
    'Choose a Salvage Module first.';
```

For `startWave()` and any build-action feedback method reached while a draft is pending, prefer this message before the existing generic build-phase message. Do **not** add a new failure enum.

- [ ] **Step 8: Run Task 4 green and commit**

```bash
flutter test test/game/orion_defense_game_test.dart test/game/tower_stats_resolver_test.dart
git add lib/game/components/tower_component.dart lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: apply salvage modules in active missions (HPA-527)"
```

---

### Task 5: Add the mobile draft UI, effect reminders, and resolved tower summary

**Files:**
- Create: `lib/game/ui/run_module_draft_panel.dart`
- Modify: `lib/game/ui/orion_game_page.dart`
- Create: `test/widget/run_module_draft_panel_test.dart`
- Modify existing selected-tower widget fixtures when required by compilation.

**Interfaces:**
- Consumes immutable `RunModuleOffer`, acquired `RunModuleId`, catalog copy, and `GameSnapshot.selectedTowerStats`.
- Produces `RunModuleDraftPanel` and `AcquiredRunModuleStrip`.
- UI does not call `RunModuleRules` or `TowerStatsResolver`.

- [ ] **Step 1: Write 360×640 draft/strip tests first**

Create `test/widget/run_module_draft_panel_test.dart` with a fixed 360×640 harness and:

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

Assert title/effect/affinity text for all three cards, no overflow, and one callback after tapping Heavy Caliber.

Render `AcquiredRunModuleStrip` with Heavy Caliber and Long Sight. Assert both titles exist and `find.byTooltip(runModuleDefinition(id).effectText)` finds each reminder. Empty input renders no module title.

- [ ] **Step 2: Add a resolved selected-tower UI regression**

In the appropriate existing selected-tower widget test, construct a snapshot with:

```dart
selectedTower: tower,
selectedTowerStats: TowerStatsResolver.resolve(
  tower,
  runModules: const [RunModuleId.longSight],
),
acquiredRunModules: const [RunModuleId.longSight],
```

Assert the selected-tower panel renders a range value equal to the resolved `selectedTowerStats.range`, not the raw base range.

The resolver call is test-fixture construction only. Production Flutter code reads the snapshot field.

- [ ] **Step 3: Run widget tests red**

```bash
flutter test test/widget/run_module_draft_panel_test.dart test/widget_test.dart
```

Expected: compile/assertion failures until the UI widgets/summary exist.

- [ ] **Step 4: Implement `RunModuleDraftPanel`**

Create `lib/game/ui/run_module_draft_panel.dart` with `Material` + `SafeArea` + `SingleChildScrollView`. Render exactly three cards from `offer.moduleIds`. Each card displays:

- `definition.title`;
- `definition.effectText`;
- `definition.affinity.label`.

One tap invokes `onSelected(id)`. Do not add confirmation, reroll, rarity, or local gameplay state.

- [ ] **Step 5: Implement compact acquired reminders using tooltips**

Use title-only chips wrapped in effect tooltips to avoid expanding the HUD vertically:

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
          Tooltip(
            message: runModuleDefinition(id).effectText,
            child: Chip(
              visualDensity: VisualDensity.compact,
              label: Text(runModuleDefinition(id).title),
            ),
          ),
      ],
    );
  }
}
```

This preserves compact portrait layout while keeping effect text available after selection.

- [ ] **Step 6: Render resolved selected-tower combat stats**

Reuse `lib/game/util/format.dart` (`number`, `cadence`). Change `_TowerSummary` to accept `TowerStats stats` and render, beneath level/specialization:

```dart
Text(
  'Damage ${number(stats.damage)} • '
  'Fire ${cadence(stats.fireInterval)}s • '
  'Range ${number(stats.range)}',
),
```

Add one type-relevant line only when meaningful:

```dart
if (tower.type == TowerType.cryo && stats.slowDuration > 0)
  Text('Slow ${number(stats.slowDuration)}s'),
if (tower.type == TowerType.rocket && stats.splashRadius > 0)
  Text('Splash ${number(stats.splashRadius)}'),
```

In `_UpgradePanel`, use:

```dart
final stats = snapshot.selectedTowerStats ??
    GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
```

The fallback keeps manually built legacy test snapshots compiling; live game snapshots supply resolved stats from `GameSession`.

Pass `stats` into `_TowerSummary`. Do not invoke the resolver in production UI.

- [ ] **Step 7: Wire strip and blocking panel into the existing stage stack**

Below `_Hud`:

```dart
if (snapshot.acquiredRunModules.isNotEmpty) ...[
  const SizedBox(height: 8),
  AcquiredRunModuleStrip(moduleIds: snapshot.acquiredRunModules),
],
```

Above terminal end-state overlay:

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

- [ ] **Step 8: Run Task 5 green and commit**

```bash
flutter test test/widget/run_module_draft_panel_test.dart test/widget_test.dart
```

Then run any selected-tower widget file that compiler/test output identified, and only after all focused widget tests pass:

```bash
git add lib/game/ui/run_module_draft_panel.dart lib/game/ui/orion_game_page.dart test/widget/run_module_draft_panel_test.dart test/widget
git commit -m "feat: add salvage module intermission UI (HPA-527)"
```

Before staging, inspect `git status --short` and stage only selected-tower widget test files actually changed; do not stage unrelated `test/widget` changes.

---

### Task 6: Verify the vertical slice and record two human playtests

**Files:**
- No new evidence/report file.
- If verification exposes a defect, change only the source/test file that owns that behavior and rerun its focused test before continuing.

**Interfaces:**
- Consumes all previous tasks.
- Produces a verified implementation branch plus concise Stage 1 and later-stage observations in the implementation PR body/comment.

- [ ] **Step 1: Run all focused automated tests**

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

- [ ] **Step 2: Run format and analysis**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
```

Expected: both exit 0.

- [ ] **Step 3: Run full suite**

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 4: Play Outpost Alpha at 1×**

Record exactly:

1. Draft comprehension: yes/no + one sentence.
2. Mission pacing: improved / neutral / disruptive + one sentence.
3. Dead or mandatory card: module name or `none`.
4. Selected-module effect noticeable: yes/no + one sentence; explicitly inspect the resolved selected-tower summary for Long Sight/Heavy/Overclock when selected.

- [ ] **Step 5: Play one later main-path stage at 1×**

Record the same four observations, preferring a stage with enough enemy variety to notice Rocket/Cryo trade-offs.

If tuning changes, edit the relevant `RunModuleDefinition` fields in `run_module.dart`, update its exact catalog expectation, rerun Steps 1–3, and record the reason. `RunModuleRules`, session reward code, and effect copy must not need a balance-number edit.

- [ ] **Step 6: Walk the acceptance checklist**

Verify:

- [ ] drafts occur after waves 2, 4, and 6 only;
- [ ] each stored offer remains unchanged until selection;
- [ ] acquired cards do not reappear and offers contain three distinct IDs;
- [ ] stale, duplicate, and non-offered selections do not mutate state;
- [ ] build, upgrade, specialize, sell, retarget, and start-wave are blocked while pending;
- [ ] direct blocked action feedback says `Choose a Salvage Module first.`;
- [ ] auto-start cannot tick/recreate a countdown while pending and resumes with a fresh full countdown;
- [ ] existing towers refresh immediately and future towers inherit modules;
- [ ] Emergency Salvage uses its definition-owned 90-gold value exactly once;
- [ ] acquired reminders expose effect text;
- [ ] selected-tower summary shows resolved module-modified damage/fire interval/range and relevant Cryo/Rocket secondary stat;
- [ ] restart clears temporary state while offer IDs remain monotonic;
- [ ] returning to the world map abandons run-only state with the game instance;
- [ ] 360×640 draft UI has no overflow;
- [ ] no save-schema, package dependency, event bus, seed protocol, or range-ring subsystem was added.

Do not claim implementation completion until every automated command has fresh passing output and both human observations are recorded.

---

## Self-Review

**Spec coverage:** Task 1 makes the catalog the single source for tuning/copy and supplies the injectable picker. Task 2 covers eligibility and exact application, including Overclock and Heavy×Overclock composition. Task 3 supplies reusable multi-wave fixtures, the 2/4/6 session lifecycle, stale selection protection, definition-owned gold, authoritative gating, resolved selected-tower snapshot data, and restart cleanup. Task 4 covers existing/future tower consistency, both auto-start guards, board blocking, and accurate direct-denial copy. Task 5 makes module effects player-inspectable without putting rules in UI or adding a range renderer. Task 6 runs focused/full verification and two human checks.

**Placeholder scan:** No TBD/TODO or undefined implementation step remains. The only conditional staging instruction explicitly requires inspecting changed files and staging exact paths rather than `git add -A`.

**Type consistency:** `RunModuleDefinition` owns all tuning. `RunModuleRules` consumes definitions. `GameSession` injects `ModuleOfferPicker` and projects `RunModuleOffer`, `List<RunModuleId>`, and resolved `TowerStats`. `TowerStatsResolver`/`TowerComponent` consume `Iterable<RunModuleId>`. `OrionDefenseGame.selectRunModule(int, RunModuleId)` matches the draft callback. Production UI reads `GameSnapshot.selectedTowerStats`; it does not resolve game rules itself.
