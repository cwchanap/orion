# HPA-527 Salvage Module Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six temporary Salvage Modules with stable three-card drafts after waves 2, 4, and 6, authoritative intermission gating, player-visible resolved effects, and a portrait-mobile snapshot-driven picker UI.

**Architecture:** `GameSession` owns run-only module state, offer generation, selection, immediate economy effects, and build/wave gating. `TowerStatsResolver` appends one pure `RunModuleRules` step after base → campaign → stage. `OrionDefenseGame` refreshes Flame components/pacing; Flutter renders immutable module data and resolved selected-tower stats from `GameSnapshot`.

**Tech Stack:** Dart 3.12+, Flutter 3.44+, Flame 1.37+, `flutter_test`; no new packages.

## Global Constraints

- Keep `GamePhase` unchanged; pending draft == build phase plus an authoritative gate.
- Initial modules: Heavy Caliber, Overclock Relay, Long Sight, Emergency Salvage, Cryo Reservoir, Rocket Fusing.
- Initial values live only on `RunModuleDefinition`: Heavy `damage ×1.20`, `fireInterval ×1.10`; Overclock `fireInterval ×0.85`, `damage ×0.92`; Long Sight `range ×1.15`; Emergency Salvage `+90` gold; Cryo Reservoir `slowDuration +0.60`; Rocket Fusing `splashRadius ×1.25`, `damage ×0.90`.
- Drafts only after completed waves 2/4/6; exactly three distinct eligible non-acquired IDs.
- Production randomness is ordinary `Random`; tests inject a picker. No seed/version/hash/fingerprint/history protocol.
- One monotonic `offerId` is the stale-callback guard.
- Stat order is base → campaign → stage → run modules.
- No event bus, generic effect engine, persistence migration, Mission Report, blueprint system, Codex modules, audio/haptics, rarity/rerolls/decks, mid-run resume, range-ring subsystem, seed sweep, or seven-stage certification.
- UI remains snapshot-driven; production widgets do not invoke module rules/resolver.
- Target 360×640 logical pixels.
- Final gates: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, focused tests, full `flutter test`, two human 1× runs.

## Review Resolution Incorporated

- Player-visible effect feedback is added without moving resolver calls into production Flutter: `GameSession.snapshot()` projects `selectedTowerStats`, and `_TowerSummary` renders those resolved values.
- The acquired strip keeps compact title chips and exposes exact `effectText` through tooltips.
- Definition-owned tuning is the single source for rules, immediate gold, and copy.
- Multi-wave schedule/orchestration tests share `stageWithWaveCount(int)`.
- Rule tests explicitly cover Overclock Relay and Heavy Caliber × Overclock composition.
- Both auto-start helpers guard pending drafts.
- Direct blocked actions use `Choose a Salvage Module first.` while preserving existing failure enums.

## File Map

**Create**
- `lib/game/modules/run_module.dart`
- `lib/game/rules/module_offer_picker.dart`
- `lib/game/rules/run_module_rules.dart`
- `lib/game/ui/run_module_draft_panel.dart`
- `test/game/game_test_fixtures.dart`
- `test/game/module_offer_picker_test.dart`
- `test/game/run_module_rules_test.dart`
- `test/widget/run_module_draft_panel_test.dart`

**Modify**
- `lib/game/models/game_models.dart`
- `lib/game/rules/tower_stats_resolver.dart`
- `lib/game/rules/game_session.dart`
- `lib/game/components/tower_component.dart`
- `lib/game/orion_defense_game.dart`
- `lib/game/ui/orion_game_page.dart`
- `test/game/tower_stats_resolver_test.dart`
- `test/game/game_session_test.dart`
- `test/game/orion_defense_game_test.dart`
- `test/widget/sell_button_test.dart`

---

### Task 1: Catalog + single-source tuning + picker

**Files:** create `run_module.dart`, `module_offer_picker.dart`, `module_offer_picker_test.dart`.

**Produces:** `RunModuleId`, `RunModuleAffinity`, `RunModuleDefinition`, `RunModuleOffer`, `runModuleCatalog`, `runModuleDefinition`, `ModuleOfferPicker`, `RandomModuleOfferPicker`.

- [ ] **Step 1: Write failing picker/catalog tests**

```dart
final picker = RandomModuleOfferPicker(math.Random(7));
final candidates = RunModuleId.values.toList();
final before = List<RunModuleId>.of(candidates);
final result = picker.pick(candidates, count: 3);
expect(result, hasLength(3));
expect(result.toSet(), hasLength(3));
expect(candidates, before);

final overclock = runModuleDefinition(RunModuleId.overclockRelay);
expect(overclock.fireIntervalMultiplier, 0.85);
expect(overclock.damageMultiplier, 0.92);
expect(overclock.effectText, contains('15%'));
expect(overclock.effectText, contains('8%'));
expect(runModuleDefinition(RunModuleId.emergencySalvage).immediateGold, 90);
```

Also expect `StateError` when requesting 3 from a 2-candidate list.

- [ ] **Step 2: Verify red**

```bash
flutter test test/game/module_offer_picker_test.dart
```

- [ ] **Step 3: Implement the module domain**

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
    RunModuleId.emergencySalvage => 'Gain $immediateGold gold immediately.',
    RunModuleId.cryoReservoir =>
      'Cryo slows last ${number(slowDurationBonus)} seconds longer.',
    RunModuleId.rocketFusing =>
      'Rocket splash grows ${percent(splashRadiusMultiplier - 1)}; '
      'direct damage drops ${percent(1 - damageMultiplier)}.',
  };
}
```

Define the six const entries with the values from Global Constraints. Define immutable `RunModuleOffer(offerId, draftNumber, moduleIds)`.

- [ ] **Step 4: Implement picker**

```dart
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

- [ ] **Step 5: Green + commit**

```bash
flutter test test/game/module_offer_picker_test.dart
git add lib/game/modules/run_module.dart lib/game/rules/module_offer_picker.dart test/game/module_offer_picker_test.dart
git commit -m "feat: add salvage module catalog and picker (HPA-527)"
```

---

### Task 2: Pure eligibility + stat rules + resolver

**Files:** create `run_module_rules.dart`, `run_module_rules_test.dart`; modify `game_models.dart`, `tower_stats_resolver.dart`, `tower_stats_resolver_test.dart`.

**Produces:** `RunModuleRules.isEligible`, `RunModuleRules.applyTowerStats`, `TowerStatsResolver.resolve(..., runModules:)`.

- [ ] **Step 1: Write failing rule tests**

Cover universal/Cryo/Rocket eligibility, then exact Overclock and Heavy×Overclock composition:

```dart
final base = GameBalance.towerStats(TowerType.laser, level: 1);
final overclock = runModuleDefinition(RunModuleId.overclockRelay);
final single = RunModuleRules.applyTowerStats(
  base,
  const [RunModuleId.overclockRelay],
);
expect(
  single.fireInterval,
  closeTo(base.fireInterval * overclock.fireIntervalMultiplier, 1e-9),
);
expect(single.damage, closeTo(base.damage * overclock.damageMultiplier, 1e-9));

final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
final composed = RunModuleRules.applyTowerStats(
  base,
  const [RunModuleId.heavyCaliber, RunModuleId.overclockRelay],
);
expect(
  composed.damage,
  closeTo(base.damage * heavy.damageMultiplier * overclock.damageMultiplier, 1e-9),
);
expect(
  composed.fireInterval,
  closeTo(
    base.fireInterval *
        heavy.fireIntervalMultiplier *
        overclock.fireIntervalMultiplier,
    1e-9,
  ),
);
```

Also cover Long Sight, Cryo-only slow bonus, Rocket-only splash/damage.

- [ ] **Step 2: Add resolver-order regression**

```dart
final resolved = TowerStatsResolver.resolve(
  placedLaser,
  campaignModifiers: const CampaignModifiers(laserDamageFraction: 0.10),
  runModules: const [RunModuleId.heavyCaliber],
);
expect(
  resolved.damage,
  closeTo(base.damage * 1.10 * heavy.damageMultiplier, 1e-9),
);
```

Add an empty-run-module regression comparing the existing stage-modified result with explicit `runModules: const []`.

- [ ] **Step 3: Verify red**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
```

- [ ] **Step 4: Extend `TowerStats.copyWith` only for this slice**

Add nullable `range`, `fireInterval`, `splashRadius` and copy them with `?? this.<field>`.

- [ ] **Step 5: Implement data-driven rules**

```dart
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
          !_appliesToTower(definition.affinity, stats.type)) continue;
      stats = stats.copyWith(
        damage: stats.damage * definition.damageMultiplier,
        fireInterval: stats.fireInterval * definition.fireIntervalMultiplier,
        range: stats.range * definition.rangeMultiplier,
        splashRadius: stats.splashRadius * definition.splashRadiusMultiplier,
        slowDuration: stats.slowDuration + definition.slowDurationBonus,
      );
    }
    return stats;
  }
}
```

Implement `_appliesToTower` by affinity only; no per-ID tuning switch.

- [ ] **Step 6: Append to resolver**

Add `Iterable<RunModuleId> runModules = const []`, resolve current stage output first, then return `RunModuleRules.applyTowerStats(stageAdjusted, runModules)`.

- [ ] **Step 7: Green + commit**

```bash
flutter test test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git add lib/game/models/game_models.dart lib/game/rules/run_module_rules.dart lib/game/rules/tower_stats_resolver.dart test/game/run_module_rules_test.dart test/game/tower_stats_resolver_test.dart
git commit -m "feat: apply salvage modules to tower stats (HPA-527)"
```

---

### Task 3: Shared multi-wave fixture + session lifecycle + snapshot projection

**Files:** create `test/game/game_test_fixtures.dart`; modify `game_models.dart`, `game_session.dart`, `game_session_test.dart`.

**Produces:** `stageWithWaveCount`, `pendingRunModuleOffer`, `acquiredRunModules`, `selectRunModule`, `GameSnapshot.selectedTowerStats`.

- [ ] **Step 1: Add reusable eight-wave fixture**

```dart
StageDefinition stageWithWaveCount(int count) {
  if (count <= 0) throw ArgumentError.value(count, 'count');
  return StageDefinition(
    id: 'test-$count-waves',
    name: 'Test $count Waves',
    mapLabel: 'Test',
    description: 'Deterministic empty-wave test stage',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List.generate(
      count,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    mapColumn: 0,
    mapRow: 0,
  );
}
```

- [ ] **Step 2: Add fixed picker + wave helper in `game_session_test.dart`**

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

- [ ] **Step 3: Write failing session tests**

Using `stageWithWaveCount(8)`, verify drafts after 2/4/6 only, repeated snapshots return the same offer, acquired IDs are excluded, offers are distinct, stale/wrong/non-offered selections no-op, and all build mutations + `startWave()` reject while pending.

Emergency Salvage expected value comes from the definition:

```dart
final reward = runModuleDefinition(RunModuleId.emergencySalvage).immediateGold;
final before = session.gold;
expect(
  session.selectRunModule(
    offerId: offer.offerId,
    moduleId: RunModuleId.emergencySalvage,
  ),
  isTrue,
);
expect(session.gold, before + reward);
```

Add restart test: temporary state clears but the next offer ID is greater than the pre-restart ID.

- [ ] **Step 4: Add failing resolved selected-tower projection test**

```dart
final snapshot = session.snapshot(selectedTower: tower);
final base = GameBalance.towerStats(TowerType.laser, level: 1);
final sight = runModuleDefinition(RunModuleId.longSight);
expect(
  snapshot.selectedTowerStats!.range,
  closeTo(base.range * sight.rangeMultiplier, 1e-9),
);
```

- [ ] **Step 5: Verify red**

```bash
flutter test test/game/game_session_test.dart
```

- [ ] **Step 6: Extend `GameSnapshot`**

Add optional `pendingRunModuleOffer`, immutable `acquiredRunModules`, optional `selectedTowerStats`; make `canStartWave` require no pending offer.

- [ ] **Step 7: Add session-owned state and gating**

```dart
final ModuleOfferPicker _offerPicker;
final List<RunModuleId> _acquiredRunModules = [];
RunModuleOffer? _pendingRunModuleOffer;
int _completedModuleDrafts = 0;
int _nextModuleOfferId = 1;

bool get _canMutateBuild =>
    _phase == GamePhase.build && _pendingRunModuleOffer == null;
```

Inject `ModuleOfferPicker? offerPicker` in `GameSession.initial`, defaulting to `RandomModuleOfferPicker()`. Use `_canMutateBuild` for placement/upgrade/specialize/sell/retarget/start-wave.

- [ ] **Step 8: Open drafts from `finishActiveWave()` only**

After `_waveIndex++`, handle win first; otherwise set build phase and call `_openModuleDraftIfDue()`. The helper filters acquired definitions, applies `RunModuleRules.isEligible`, asks the picker for 3, and stores one `RunModuleOffer(offerId: _nextModuleOfferId++, draftNumber: _completedModuleDrafts + 1, ...)` for waves 2/4/6.

- [ ] **Step 9: Implement atomic selection from definition data**

```dart
bool selectRunModule({required int offerId, required RunModuleId moduleId}) {
  final offer = _pendingRunModuleOffer;
  if (offer == null ||
      offer.offerId != offerId ||
      !offer.moduleIds.contains(moduleId) ||
      _acquiredRunModules.contains(moduleId)) return false;

  _acquiredRunModules.add(moduleId);
  _gold += runModuleDefinition(moduleId).immediateGold;
  _pendingRunModuleOffer = null;
  _completedModuleDrafts += 1;
  return true;
}
```

- [ ] **Step 10: Project resolved selected tower**

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

Pass it plus module state into `GameSnapshot`.

- [ ] **Step 11: Restart cleanup, green, commit**

Clear acquired/pending/completed-draft state in `restart()`, but do not reset `_nextModuleOfferId`.

```bash
flutter test test/game/game_session_test.dart
git add test/game/game_test_fixtures.dart lib/game/models/game_models.dart lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: add salvage module draft lifecycle (HPA-527)"
```

---

### Task 4: Flame refresh + complete auto-start guards + clear denial feedback

**Files:** modify `tower_component.dart`, `orion_defense_game.dart`, `orion_defense_game_test.dart`; reuse `game_test_fixtures.dart`.

**Produces:** `TowerComponent.updateRunModules`, `OrionDefenseGame.selectRunModule`.

- [ ] **Step 1: Write failing orchestration tests with `stageWithWaveCount(8)`**

Drive empty waves through the real `OrionDefenseGame.update` path. Verify:

- after wave 2 with auto-start enabled: pending offer exists and countdown is null;
- `game.update(...)` while pending does not recreate/tick countdown;
- selection starts a fresh full countdown;
- Heavy Caliber refreshes an existing Laser component;
- a Laser placed afterward inherits the same multipliers;
- `game.startWave()` while pending leaves the offer and publishes `Choose a Salvage Module first.`.

- [ ] **Step 2: Verify red**

```bash
flutter test test/game/orion_defense_game_test.dart
```

- [ ] **Step 3: Carry module IDs in `TowerComponent`**

Add constructor `Iterable<RunModuleId> runModules = const []`, store an immutable list, pass it to every resolver call, and add:

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

- [ ] **Step 4: Inject picker and bridge selection**

Add optional `ModuleOfferPicker? moduleOfferPicker` to `OrionDefenseGame`; pass it to `GameSession.initial`. New `TowerComponent`s receive `_session.acquiredRunModules`.

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

- [ ] **Step 5: Guard both auto-start helpers**

When a draft opens, clear countdown but preserve `_autoStartEnabled`.

```dart
if (_session.pendingRunModuleOffer != null) {
  _autoStartCountdownRemaining = null;
  return false;
}
```

Put that at the top of `_tickAutoStartCountdown`. Add `&& _session.pendingRunModuleOffer == null` to `_startAutoStartCountdownIfNeeded()`.

- [ ] **Step 6: Block board taps and specialize direct feedback**

Return early from `onTapDown` while pending. Reuse one constant:

```dart
static const _moduleDraftBlockingMessage = 'Choose a Salvage Module first.';
```

When `startWave` or a build-action feedback path is rejected because the session has a pending offer, publish that text before generic build-phase copy. Keep existing failure enums.

- [ ] **Step 7: Green + commit**

```bash
flutter test test/game/orion_defense_game_test.dart test/game/tower_stats_resolver_test.dart
git add lib/game/components/tower_component.dart lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: apply salvage modules in active missions (HPA-527)"
```

---

### Task 5: Draft UI + acquired effect reminder + resolved tower summary

**Files:** create `run_module_draft_panel.dart`, `run_module_draft_panel_test.dart`; modify `orion_game_page.dart`, `sell_button_test.dart`.

**Consumes:** immutable offer/acquired IDs and `GameSnapshot.selectedTowerStats`. Production UI does not resolve rules.

- [ ] **Step 1: Write failing 360×640 draft/strip test**

Use an offer containing Heavy Caliber, Emergency Salvage, Cryo Reservoir. Assert header, each title/effect/affinity, no overflow, and one callback on tap. For acquired Heavy + Long Sight, assert titles plus effect tooltips:

```dart
expect(
  find.byTooltip(runModuleDefinition(RunModuleId.longSight).effectText),
  findsOneWidget,
);
```

- [ ] **Step 2: Add failing resolved-summary test to existing `sell_button_test.dart`**

Reuse `_pumpStageWithSelectedTower`. Extend it with optional `TowerStats? selectedTowerStats`, pass that field into the fake `GameSnapshot`, then add:

```dart
final tower = const PlacedTower(
  id: 1,
  type: TowerType.laser,
  position: GridPosition(0, 0),
);
final resolved = TowerStatsResolver.resolve(
  tower,
  runModules: const [RunModuleId.longSight],
);
await _pumpStageWithSelectedTower(
  tester,
  tower,
  selectedTowerStats: resolved,
);
expect(find.textContaining('Range ${number(resolved.range)}'), findsOneWidget);
```

Resolver use here is test-fixture construction only.

- [ ] **Step 3: Verify red**

```bash
flutter test test/widget/run_module_draft_panel_test.dart test/widget/sell_button_test.dart
```

- [ ] **Step 4: Implement draft panel**

`RunModuleDraftPanel` uses `Material` + `SafeArea` + `SingleChildScrollView`; exactly three cards render `definition.title`, `definition.effectText`, `definition.affinity.label`, and invoke `onSelected(id)`. No confirmation/reroll/local gameplay state.

- [ ] **Step 5: Implement compact acquired reminder**

```dart
class AcquiredRunModuleStrip extends StatelessWidget {
  const AcquiredRunModuleStrip({super.key, required this.moduleIds});
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

- [ ] **Step 6: Render snapshot-resolved combat stats in `_TowerSummary`**

Reuse `number`/`cadence` from `lib/game/util/format.dart`.

```dart
final stats = snapshot.selectedTowerStats ??
    GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
```

Pass `stats` into `_TowerSummary`, then render:

```dart
Text(
  'Damage ${number(stats.damage)} • '
  'Fire ${cadence(stats.fireInterval)}s • '
  'Range ${number(stats.range)}',
),
if (tower.type == TowerType.cryo && stats.slowDuration > 0)
  Text('Slow ${number(stats.slowDuration)}s'),
if (tower.type == TowerType.rocket && stats.splashRadius > 0)
  Text('Splash ${number(stats.splashRadius)}'),
```

The fallback is only for manually constructed snapshots; live snapshots provide resolved stats from `GameSession`.

- [ ] **Step 7: Wire stage stack**

Below HUD, show `AcquiredRunModuleStrip` when non-empty. Above terminal overlay, show full-screen `RunModuleDraftPanel` when pending and call `game.selectRunModule(offer.offerId, id)`.

- [ ] **Step 8: Green + commit exact files only**

```bash
flutter test test/widget/run_module_draft_panel_test.dart test/widget/sell_button_test.dart test/widget_test.dart
git add lib/game/ui/run_module_draft_panel.dart lib/game/ui/orion_game_page.dart test/widget/run_module_draft_panel_test.dart test/widget/sell_button_test.dart
git commit -m "feat: add salvage module intermission UI (HPA-527)"
```

---

### Task 6: Full verification + two human runs

- [ ] **Step 1: Focused tests**

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

- [ ] **Step 2: Format + analyze**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
```

- [ ] **Step 3: Full suite**

```bash
flutter test
```

- [ ] **Step 4: Outpost Alpha 1× human run**

Record in implementation PR:
1. Draft comprehension — yes/no + one sentence.
2. Pacing — improved/neutral/disruptive + one sentence.
3. Dead/mandatory card — module or `none`.
4. Selected effect noticeable — yes/no + one sentence; inspect resolved tower stats for Long Sight/Heavy/Overclock when selected.

- [ ] **Step 5: One later main-path 1× run**

Record the same four observations, preferring a stage where Rocket/Cryo trade-offs are relevant.

If tuning changes, edit only `RunModuleDefinition` values, update exact catalog expectations, rerun Steps 1–3, and record why. Do not edit numeric balance values in rules/session/copy.

- [ ] **Step 6: Acceptance walk**

Confirm with fresh evidence:
- drafts only 2/4/6 and stored until selection;
- three distinct eligible non-acquired IDs;
- stale/duplicate/non-offered selections no-op;
- all build mutations and starts blocked while pending;
- direct denial text is `Choose a Salvage Module first.`;
- auto-start cannot tick/recreate behind draft; selection gets fresh full countdown;
- existing/future towers share resolved module effects;
- Emergency Salvage reads definition-owned reward once;
- acquired reminders expose effect text;
- selected tower shows resolved damage/fire/range plus Cryo/Rocket secondary value;
- restart clears temporary state but IDs remain monotonic;
- route exit discards run state with game instance;
- 360×640 has no overflow;
- no save schema/package/event bus/seed protocol/range ring added.

Do not claim implementation completion until all automated commands have fresh passing output and both human observations are recorded.

---

## Self-Review

- **Spec coverage:** Task 1 fixes tuning/copy single-source; Task 2 adds Overclock and dual-universal composition coverage; Task 3 adds reusable multi-wave fixture and resolved snapshot projection; Task 4 adds both pacing guards and clear draft-block feedback; Task 5 makes effects inspectable without rules in UI or a range renderer; Task 6 validates the product experiment.
- **Placeholder scan:** no TBD/TODO, wildcard staging, or unknown test paths remain.
- **Type consistency:** definitions own tuning; rules consume definitions; session owns offer/acquired/reward and projects resolved `TowerStats`; components/resolver consume module IDs; Flutter reads snapshot values only.
