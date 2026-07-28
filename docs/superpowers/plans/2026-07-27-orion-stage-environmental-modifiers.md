# Orion Stage Environmental Modifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement HPA-101 so all six non-baseline campaign stages visibly advertise and apply their approved environmental modifiers while Outpost Alpha remains the mechanical baseline.

**Architecture:** Static `StageModifier` values live on `StageDefinition`; `StageModifierRules` resolves deterministic health, economy, spawn, enemy-profile, and tower-stat effects without stage-ID branching. `GameSession` owns starting-health and wave-reward resolution, `OrionDefenseGame` bridges resolved profiles/timing/rewards into Flame, and `GameSnapshot` is the only mission-UI source. A shared pure metadata mapping feeds both the world-map briefing and build-phase environment reminder.

**Tech Stack:** Dart SDK `^3.12.0`, Flutter, Flame `^1.37.0`, `flutter_test`, and `integration_test`.

**Design:** `docs/superpowers/specs/2026-07-27-orion-stage-environmental-modifiers-design.md`

## Global Constraints

- Keep `lib/game/rules/` free of Flame imports.
- Never branch on stage IDs in mission rules; compose behavior from `StageDefinition.modifiers`.
- `StageDefinition.modifiers` is the only intentionally unqualified modifier field. Persistent runtime values are always named `campaignModifiers`; environmental runtime values are always named `stageModifiers`.
- Keep `EnemyStats`, `WaveDefinition`, and campaign save payloads immutable. HPA-101 requires no persistence migration or codec version change.
- Put all twelve new tuning values in `GameBalance`; presentation metadata formats its numeric copy from those constants.
- Apply values in this order: `GameBalance` base value, persistent campaign reward/tech adjustment, then stage modifier.
- `EnemyLogic` receives a resolved `EnemyModifierProfile`, not raw `StageModifier` values.
- `GameSession.initial` is the single starting-health resolution boundary.
- Build-phase UI reads active modifiers only from `GameSnapshot`; modifier titles do not become part of `WavePreview`.
- Preserve player time-scale behavior: the stage speed multiplier changes enemy movement inside the already-scaled game tick.
- Use Conventional Commits with `(HPA-101)` in every implementation commit.
- At each task gate run the named focused tests and `flutter analyze`; run the complete suite in Task 9.

## File Structure

- **Modify** `lib/game/models/game_models.dart` — `StageModifier`, twelve `GameBalance` constants, `TowerStats.copyWith` field overrides, required immutable `GameSnapshot.stageModifiers`, and explicit wave-preview clear bonus.
- **Modify** `lib/game/campaign/stage_definition.dart` — immutable static modifier list.
- **Modify** `lib/game/campaign/orion_campaign.dart` — seven exact assignments and duplicate-modifier validation.
- **Create** `lib/game/campaign/stage_modifier_metadata.dart` — pure title/description mapping plus `Standard Conditions`.
- **Create** `lib/game/rules/stage_modifier_rules.dart` — pure modifier formulas, `ShieldRechargePolicy`, and `EnemyModifierProfile`.
- **Modify** `lib/game/rules/game_session.dart` — campaign/stage naming, centralized starting health, adjusted preview/payout, snapshot projection.
- **Modify** `lib/game/rules/enemy_logic.dart` — resolved armor/speed/shield behavior and damage-reset timing.
- **Modify** `lib/game/rules/tower_stats_resolver.dart` — campaign tech followed by stage Gravity Well adjustment.
- **Modify** `lib/game/components/tower_component.dart` — retain both modifier inputs across upgrades/specializations.
- **Modify** `lib/game/orion_defense_game.dart` — profiles for normal/minion spawns, pulse scheduling, kill bounty, stage tower modifiers.
- **Modify** `lib/game/ui/world_map_view.dart` — persistent-modifier naming only; locked/unlocked routing stays intact.
- **Modify** `lib/game/ui/orion_game_page.dart` — briefing flow and build-phase modifier titles.
- **Create** `test/game/stage_modifier_metadata_test.dart`.
- **Create** `test/game/stage_modifier_rules_test.dart`.
- **Modify** `test/game/game_balance_test.dart`, `test/game/orion_campaign_test.dart`, `test/game/game_session_test.dart`, `test/game/enemy_logic_test.dart`, `test/game/enemy_component_test.dart`, `test/game/tower_stats_resolver_test.dart`, `test/game/orion_defense_game_test.dart`, `test/widget_test.dart`, `test/widget/sell_button_test.dart`, and `integration_test/app_smoke_test.dart`.

---

### Task 1: Disambiguate Persistent Campaign Modifier APIs

**Files:**
- Modify: `lib/game/rules/game_session.dart:8-31`
- Modify: `lib/game/rules/tower_stats_resolver.dart:8-26`
- Modify: `lib/game/components/tower_component.dart:16-55`
- Modify: `lib/game/orion_defense_game.dart:37-55, 462-476`
- Modify: `lib/game/ui/orion_game_page.dart:137-153, 210-243`
- Modify: `lib/game/ui/world_map_view.dart:7-33, 105`
- Modify: `test/game/game_session_test.dart:877-934`
- Modify: `test/game/orion_defense_game_test.dart:726-916`
- Modify: `test/game/tower_stats_resolver_test.dart`

**Interfaces:**
- Produces: `GameSession.campaignModifiers`, `OrionDefenseGame.campaignModifiers`, `TowerComponent.campaignModifiers`, and `TowerStatsResolver.resolve(PlacedTower, {CampaignModifiers campaignModifiers})`.
- Preserves: all existing campaign reward and tech behavior; this task introduces no stage modifiers.

- [ ] **Step 1: Capture the refactor baseline**

Run:

```bash
flutter test test/game/game_session_test.dart test/game/tower_stats_resolver_test.dart test/game/orion_defense_game_test.dart
```

Expected: PASS before the rename.

- [ ] **Step 2: Rename the four runtime APIs and their callers**

Use named arguments for the resolver so the later environmental input cannot be confused with the campaign input:

```dart
class TowerStatsResolver {
  static TowerStats resolve(
    PlacedTower tower, {
    CampaignModifiers campaignModifiers = CampaignModifiers.empty,
  }) {
    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    if (tower.type == TowerType.laser &&
        campaignModifiers.laserDamageFraction > 0) {
      return base.copyWith(
        damage:
            base.damage * (1 + campaignModifiers.laserDamageFraction),
      );
    }
    if (tower.type == TowerType.cryo &&
        campaignModifiers.cryoSlowDurationBonus > 0) {
      return base.copyWith(
        slowDuration:
            base.slowDuration + campaignModifiers.cryoSlowDurationBonus,
      );
    }
    return base;
  }
}
```

Rename constructor parameters, fields, local variables, named arguments, test descriptions, and comments consistently:

```dart
GameSession.initial({
  StageDefinition? stage,
  CampaignModifiers campaignModifiers = CampaignModifiers.empty,
  int? gold,
  int? baseHealth,
})

final CampaignModifiers campaignModifiers;

OrionDefenseGame({
  StageDefinition? stage,
  this.campaignModifiers = CampaignModifiers.empty,
  this.onStageWon,
  this.onReturnToMap,
})

final CampaignModifiers campaignModifiers;

TowerComponent({
  required PlacedTower tower,
  required Vector2 center,
  required this.acquireTarget,
  required this.launchProjectile,
  this.spriteSheet,
  this.towerVarietySheet,
  this.campaignModifiers = CampaignModifiers.empty,
  double radius = 15,
  super.priority,
})
```

Also rename `WorldMapView.modifiers` to `campaignModifiers`; it always represents persistent campaign state.

- [ ] **Step 3: Prove no ambiguous runtime API remains**

Run:

```bash
rg -n "\bmodifiers\b" lib/game/rules/game_session.dart lib/game/rules/tower_stats_resolver.dart lib/game/components/tower_component.dart lib/game/orion_defense_game.dart lib/game/ui/orion_game_page.dart lib/game/ui/world_map_view.dart
```

Expected: no unqualified runtime field, constructor parameter, or local-variable name remains. Mentions inside `CampaignModifiers` type names are expected.

- [ ] **Step 4: Verify and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/game_session_test.dart test/game/tower_stats_resolver_test.dart test/game/orion_defense_game_test.dart test/widget_test.dart
```

Expected: formatting changes only from the rename, analyzer clean, all focused tests pass.

Commit:

```bash
git add lib/game test/game test/widget_test.dart
git commit -m "refactor: clarify campaign modifier APIs (HPA-101)"
```

---

### Task 2: Add Static Modifier Data, Tuning, Metadata, and Campaign Validation

**Files:**
- Modify: `lib/game/models/game_models.dart:40, 495-524`
- Modify: `lib/game/campaign/stage_definition.dart:5-35`
- Modify: `lib/game/campaign/orion_campaign.dart:10-104, 132-230`
- Create: `lib/game/campaign/stage_modifier_metadata.dart`
- Modify: `test/game/game_balance_test.dart`
- Modify: `test/game/orion_campaign_test.dart`
- Create: `test/game/stage_modifier_metadata_test.dart`

**Interfaces:**
- Produces: `enum StageModifier`; `StageDefinition.modifiers`; twelve `GameBalance` constants; `StageModifierMetadata.forModifier(StageModifier)`; `StageModifierMetadata.standardConditions`.
- Consumed by: every later task.

- [ ] **Step 1: Write failing model and campaign tests**

Add these expectations:

```dart
test('modifier lists are immutable', () {
  final stage = StageDefinition(
    id: 'test',
    name: 'Test',
    mapLabel: 'Test',
    description: 'Test stage',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [],
    modifiers: const [StageModifier.shieldRecharge],
    mapColumn: 0,
    mapRow: 0,
  );

  expect(
    () => stage.modifiers.add(StageModifier.swarmBounty),
    throwsUnsupportedError,
  );
});

test('campaign assigns exact environmental modifiers', () {
  expect(OrionCampaign.stageById('outpost-alpha').modifiers, isEmpty);
  expect(
    OrionCampaign.stageById('nebula-relay').modifiers,
    [StageModifier.shieldRecharge],
  );
  expect(
    OrionCampaign.stageById('salvage-rift').modifiers,
    [StageModifier.swarmBounty],
  );
  expect(
    OrionCampaign.stageById('asteroid-foundry').modifiers,
    [StageModifier.reinforcedArmor],
  );
  expect(
    OrionCampaign.stageById('aurora-gate').modifiers,
    [StageModifier.regenPressurePulses],
  );
  expect(
    OrionCampaign.stageById('void-bastion').modifiers,
    [
      StageModifier.reducedStartingHealth,
      StageModifier.enhancedClearBonus,
    ],
  );
  expect(
    OrionCampaign.stageById('singularity-core').modifiers,
    [
      StageModifier.enemySpeedSurge,
      StageModifier.amplifiedGravityWells,
    ],
  );
});
```

Add a duplicate validation case by replacing only Outpost Alpha:

```dart
test('validation rejects duplicate modifiers without campaign-specific rules', () {
  final source = OrionCampaign.stageOne;
  final duplicateStage = StageDefinition(
    id: source.id,
    name: source.name,
    mapLabel: source.mapLabel,
    description: source.description,
    pathCells: source.pathCells,
    waves: source.waves,
    unlockDependencies: source.unlockDependencies,
    isMainPath: source.isMainPath,
    mainPathOrder: source.mainPathOrder,
    reward: source.reward,
    mapColumn: source.mapColumn,
    mapRow: source.mapRow,
    modifiers: const [
      StageModifier.shieldRecharge,
      StageModifier.shieldRecharge,
    ],
  );
  final stages = [
    duplicateStage,
    ...OrionCampaign.stages.skip(1),
  ];

  expect(
    OrionCampaign.validateStages(stages),
    contains(
      'outpost-alpha contains duplicate modifier: shieldRecharge.',
    ),
  );
});

test('environmental modifier tuning matches the approved design', () {
  expect(GameBalance.shieldRechargeDelay, 3.0);
  expect(GameBalance.shieldRechargeRatePerSecond, 0.10);
  expect(GameBalance.swarmBountyMultiplier, 1.50);
  expect(GameBalance.reinforcedArmorBonus, 0.10);
  expect(GameBalance.regenPulseBurstSize, 3);
  expect(GameBalance.regenPulseInterval, 0.20);
  expect(GameBalance.regenPulseGap, 2.0);
  expect(GameBalance.reducedStartingHealthPenalty, 5);
  expect(GameBalance.enhancedClearBonusMultiplier, 1.50);
  expect(GameBalance.enemySpeedSurgeMultiplier, 1.15);
  expect(GameBalance.amplifiedGravityWellRadiusMultiplier, 1.20);
  expect(GameBalance.amplifiedGravityWellDurationMultiplier, 1.25);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
flutter test test/game/game_balance_test.dart test/game/orion_campaign_test.dart
```

Expected: FAIL because `StageModifier`, `StageDefinition.modifiers`, and the constants do not exist.

- [ ] **Step 3: Add the enum, tuning constants, immutable field, assignments, and validator**

Add beside `EnemyTrait`:

```dart
enum StageModifier {
  shieldRecharge,
  swarmBounty,
  reinforcedArmor,
  regenPressurePulses,
  reducedStartingHealth,
  enhancedClearBonus,
  enemySpeedSurge,
  amplifiedGravityWells,
}
```

Add all accepted constants to `GameBalance`:

```dart
static const double shieldRechargeDelay = 3.0;
static const double shieldRechargeRatePerSecond = 0.10;
static const double swarmBountyMultiplier = 1.50;
static const double reinforcedArmorBonus = 0.10;
static const int regenPulseBurstSize = 3;
static const double regenPulseInterval = 0.20;
static const double regenPulseGap = 2.0;
static const int reducedStartingHealthPenalty = 5;
static const double enhancedClearBonusMultiplier = 1.50;
static const double enemySpeedSurgeMultiplier = 1.15;
static const double amplifiedGravityWellRadiusMultiplier = 1.20;
static const double amplifiedGravityWellDurationMultiplier = 1.25;
```

Extend `StageDefinition`:

```dart
StageDefinition({
  required this.id,
  required this.name,
  required this.mapLabel,
  required this.description,
  required List<GridPosition> pathCells,
  required List<WaveDefinition> waves,
  List<String> unlockDependencies = const [],
  this.isMainPath = true,
  this.mainPathOrder,
  this.reward,
  required this.mapColumn,
  required this.mapRow,
  List<StageModifier> modifiers = const [],
}) : pathCells = List.unmodifiable(pathCells),
     waves = List.unmodifiable(waves),
     unlockDependencies = List.unmodifiable(unlockDependencies),
     modifiers = List.unmodifiable(modifiers);

final List<StageModifier> modifiers;
```

Assign the exact lists shown in Step 1. Inside the existing per-stage validation loop, add:

```dart
final seenModifiers = <StageModifier>{};
for (final modifier in stage.modifiers) {
  if (!seenModifiers.add(modifier)) {
    errors.add(
      '${stage.id} contains duplicate modifier: ${modifier.name}.',
    );
  }
}
```

- [ ] **Step 4: Add the shared metadata mapping and its failing-then-passing test**

Create `test/game/stage_modifier_metadata_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  test('every modifier has non-empty metadata', () {
    for (final modifier in StageModifier.values) {
      final metadata = StageModifierMetadata.forModifier(modifier);
      expect(metadata.title, isNotEmpty);
      expect(metadata.description, isNotEmpty);
    }
  });

  test('numeric copy matches GameBalance tuning', () {
    expect(
      StageModifierMetadata.forModifier(
        StageModifier.shieldRecharge,
      ).description,
      'Shielded enemies recharge 10% max shields per second after '
      '3 seconds without damage.',
    );
    expect(
      StageModifierMetadata.forModifier(
        StageModifier.amplifiedGravityWells,
      ).description,
      'Gravity Well fields gain 20% radius and 25% duration.',
    );
  });

  test('defines the standard-conditions fallback', () {
    expect(
      StageModifierMetadata.standardConditions.title,
      'Standard Conditions',
    );
    expect(
      StageModifierMetadata.standardConditions.description,
      'No environmental modifiers',
    );
  });
}
```

Create the pure mapping with no Flutter imports:

```dart
import '../models/game_models.dart';

class StageModifierMetadata {
  const StageModifierMetadata({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  static const standardConditions = StageModifierMetadata(
    title: 'Standard Conditions',
    description: 'No environmental modifiers',
  );

  static StageModifierMetadata forModifier(StageModifier modifier) {
    return switch (modifier) {
      StageModifier.shieldRecharge => StageModifierMetadata(
        title: 'Shield Recharge',
        description:
            'Shielded enemies recharge '
            '${_percent(GameBalance.shieldRechargeRatePerSecond)} max shields '
            'per second after '
            '${_number(GameBalance.shieldRechargeDelay)} seconds without damage.',
      ),
      StageModifier.swarmBounty => StageModifierMetadata(
        title: 'Swarm Bounty',
        description:
            'Swarm enemies grant '
            '${_percent(GameBalance.swarmBountyMultiplier - 1)} more kill gold, '
            'rounded to whole gold.',
      ),
      StageModifier.reinforcedArmor => StageModifierMetadata(
        title: 'Reinforced Armor',
        description:
            'Armored enemies gain '
            '${(GameBalance.reinforcedArmorBonus * 100).round()} percentage '
            'points of armor.',
      ),
      StageModifier.regenPressurePulses => StageModifierMetadata(
        title: 'Pressure Pulses',
        description:
            'Regen enemies arrive in bursts of '
            '${GameBalance.regenPulseBurstSize}.',
      ),
      StageModifier.reducedStartingHealth => StageModifierMetadata(
        title: 'Fragile Base',
        description:
            'Begin with ${GameBalance.reducedStartingHealthPenalty} less base health.',
      ),
      StageModifier.enhancedClearBonus => StageModifierMetadata(
        title: 'Salvage Reserves',
        description:
            'Wave clear bonuses are increased by '
            '${_percent(GameBalance.enhancedClearBonusMultiplier - 1)}.',
      ),
      StageModifier.enemySpeedSurge => StageModifierMetadata(
        title: 'Temporal Surge',
        description:
            'Enemies move '
            '${_percent(GameBalance.enemySpeedSurgeMultiplier - 1)} faster.',
      ),
      StageModifier.amplifiedGravityWells => StageModifierMetadata(
        title: 'Amplified Wells',
        description:
            'Gravity Well fields gain '
            '${_percent(GameBalance.amplifiedGravityWellRadiusMultiplier - 1)} '
            'radius and '
            '${_percent(GameBalance.amplifiedGravityWellDurationMultiplier - 1)} '
            'duration.',
      ),
    };
  }

  static String _percent(double value) => '${(value * 100).round()}%';

  static String _number(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }
}
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/game_balance_test.dart test/game/orion_campaign_test.dart test/game/stage_modifier_metadata_test.dart
```

Expected: analyzer clean and all model/campaign/metadata tests pass.

Commit:

```bash
git add lib/game/models/game_models.dart lib/game/campaign test/game/game_balance_test.dart test/game/orion_campaign_test.dart test/game/stage_modifier_metadata_test.dart
git commit -m "feat: define stage environmental modifiers (HPA-101)"
```

---

### Task 3: Implement the Pure Modifier Rules

**Files:**
- Modify: `lib/game/models/game_models.dart:115-243`
- Create: `lib/game/rules/stage_modifier_rules.dart`
- Create: `test/game/stage_modifier_rules_test.dart`
- Modify: `test/game/game_balance_test.dart`

**Interfaces:**
- Produces:
  - `ShieldRechargePolicy({required double delay, required double ratePerSecond})`.
  - `EnemyModifierProfile({double speedMultiplier = 1, double armorReductionBonus = 0, ShieldRechargePolicy? shieldRecharge})` and `EnemyModifierProfile.identity`.
  - `StageModifierRules.effectiveStartingBaseHealth(...)`.
  - `StageModifierRules.effectiveKillReward(...)`.
  - `StageModifierRules.enemyProfile(...)`.
  - `StageModifierRules.nextSpawnDelay(...)`.
  - `StageModifierRules.effectiveClearBonus(...)`.
  - `StageModifierRules.effectiveTowerStats(...)`.
  - `TowerStats.copyWith({double? damage, double? slowDuration, double? fieldRadius, double? fieldDuration})`.

- [ ] **Step 1: Write failing rule tests**

Create `test/game/stage_modifier_rules_test.dart` with these imports, and place
every following `test(...)` declaration inside `void main()`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/stage_modifier_rules.dart';

void main() {}
```

Use these test declarations:

```dart
test('empty modifiers are identity operations', () {
  const stats = EnemyStats(
    health: 10,
    speed: 20,
    baseDamage: 1,
    goldReward: 5,
    traits: {EnemyTrait.armored, EnemyTrait.shielded},
    shieldHealth: 100,
    armorReduction: 0.3,
  );

  expect(
    StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth: 20,
      stageModifiers: const [],
    ),
    20,
  );
  expect(
    StageModifierRules.effectiveKillReward(
      stats: stats,
      stageModifiers: const [],
    ),
    5,
  );
  final profile = StageModifierRules.enemyProfile(
    stats: stats,
    stageModifiers: const [],
  );
  expect(profile.speedMultiplier, 1);
  expect(profile.armorReductionBonus, 0);
  expect(profile.shieldRecharge, isNull);
});

test('swarm bounty rounds 5 gold to 8 and filters by trait', () {
  const swarm = EnemyStats(
    health: 1,
    speed: 1,
    baseDamage: 1,
    goldReward: 5,
    traits: {EnemyTrait.swarm},
  );
  const normal = EnemyStats(
    health: 1,
    speed: 1,
    baseDamage: 1,
    goldReward: 5,
  );
  const modifier = [StageModifier.swarmBounty];

  expect(
    StageModifierRules.effectiveKillReward(
      stats: swarm,
      stageModifiers: modifier,
    ),
    8,
  );
  expect(
    StageModifierRules.effectiveKillReward(
      stats: normal,
      stageModifiers: modifier,
    ),
    5,
  );
});

test('Salvage Rift current kill economy increases by 253 gold', () {
  final stage = OrionCampaign.stageById('salvage-rift');
  var delta = 0;
  for (final wave in stage.waves) {
    for (final group in wave.groups) {
      final adjusted = StageModifierRules.effectiveKillReward(
        stats: group.enemyStats,
        stageModifiers: stage.modifiers,
      );
      delta +=
          (adjusted - group.enemyStats.goldReward) * group.enemyCount;
    }
  }
  expect(delta, 253);
});

test('enemy profile composes speed armor and shield policy', () {
  const stats = EnemyStats(
    health: 10,
    speed: 10,
    baseDamage: 1,
    goldReward: 1,
    traits: {
      EnemyTrait.armored,
      EnemyTrait.shielded,
    },
    shieldHealth: 200,
    armorReduction: 0.7,
  );
  final profile = StageModifierRules.enemyProfile(
    stats: stats,
    stageModifiers: const [
      StageModifier.shieldRecharge,
      StageModifier.reinforcedArmor,
      StageModifier.enemySpeedSurge,
    ],
  );

  expect(profile.speedMultiplier, 1.15);
  expect(profile.armorReductionBonus, 0.10);
  expect(profile.shieldRecharge?.delay, 3);
  expect(profile.shieldRecharge?.ratePerSecond, 0.10);
});

test('regen pulses use intra-burst interval and inter-burst gap', () {
  const regen = EnemyStats(
    health: 1,
    speed: 1,
    baseDamage: 1,
    goldReward: 1,
    traits: {EnemyTrait.regen},
  );

  expect(_delay(regen, 1), 0.2);
  expect(_delay(regen, 2), 0.2);
  expect(_delay(regen, 3), 2.0);
  expect(_delay(regen, 4), 0.2);
});
```

Complete that test file with:

```dart
double _delay(EnemyStats stats, int spawnedInGroup) {
  return StageModifierRules.nextSpawnDelay(
    stats: stats,
    spawnedInGroup: spawnedInGroup,
    baseSpawnInterval: 1,
    stageModifiers: const [StageModifier.regenPressurePulses],
  );
}

test('pressure pulses produce the accepted six- and eight-enemy times', () {
  const regen = EnemyStats(
    health: 1,
    speed: 1,
    baseDamage: 1,
    goldReward: 1,
    traits: {EnemyTrait.regen},
  );

  List<double> timesFor(int count) {
    final times = <double>[0];
    for (var spawned = 1; spawned < count; spawned += 1) {
      times.add(times.last + _delay(regen, spawned));
    }
    return times;
  }

  for (final (actual, expected) in [
    (timesFor(6), [0, 0.2, 0.4, 2.4, 2.6, 2.8]),
    (timesFor(8), [0, 0.2, 0.4, 2.4, 2.6, 2.8, 4.8, 5.0]),
  ]) {
    expect(actual, hasLength(expected.length));
    for (var index = 0; index < expected.length; index += 1) {
      expect(actual[index], closeTo(expected[index], 0.0001));
    }
  }
});

test('pressure pulses leave non-regen intervals unchanged', () {
  const normal = EnemyStats(
    health: 1,
    speed: 1,
    baseDamage: 1,
    goldReward: 1,
  );
  expect(_delay(normal, 3), 1);
});

test('starting health and clear bonuses clamp and preserve zero', () {
  expect(
    StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth: 4,
      stageModifiers: const [StageModifier.reducedStartingHealth],
    ),
    1,
  );
  expect(
    StageModifierRules.effectiveClearBonus(
      campaignAdjustedClearBonus: 38,
      stageModifiers: const [StageModifier.enhancedClearBonus],
    ),
    57,
  );
  expect(
    StageModifierRules.effectiveClearBonus(
      campaignAdjustedClearBonus: 0,
      stageModifiers: const [StageModifier.enhancedClearBonus],
    ),
    0,
  );
});

test('modifier order does not change the resolved profile', () {
  const stats = EnemyStats(
    health: 10,
    speed: 10,
    baseDamage: 1,
    goldReward: 1,
    traits: {EnemyTrait.armored, EnemyTrait.shielded},
    shieldHealth: 100,
    armorReduction: 0.2,
  );
  final forward = StageModifierRules.enemyProfile(
    stats: stats,
    stageModifiers: const [
      StageModifier.shieldRecharge,
      StageModifier.reinforcedArmor,
      StageModifier.enemySpeedSurge,
    ],
  );
  final reverse = StageModifierRules.enemyProfile(
    stats: stats,
    stageModifiers: const [
      StageModifier.enemySpeedSurge,
      StageModifier.reinforcedArmor,
      StageModifier.shieldRecharge,
    ],
  );

  expect(reverse.speedMultiplier, forward.speedMultiplier);
  expect(reverse.armorReductionBonus, forward.armorReductionBonus);
  expect(reverse.shieldRecharge?.delay, forward.shieldRecharge?.delay);
  expect(
    reverse.shieldRecharge?.ratePerSecond,
    forward.shieldRecharge?.ratePerSecond,
  );
});

test('amplified wells affect every level and specialization only', () {
  final towers = <PlacedTower>[
    const PlacedTower(
      id: 1,
      type: TowerType.gravityWell,
      position: GridPosition(0, 0),
    ),
    const PlacedTower(
      id: 2,
      type: TowerType.gravityWell,
      position: GridPosition(0, 0),
      level: 2,
    ),
    const PlacedTower(
      id: 3,
      type: TowerType.gravityWell,
      position: GridPosition(0, 0),
      level: 3,
      specialization: TowerSpecialization.singularityWell,
    ),
    const PlacedTower(
      id: 4,
      type: TowerType.gravityWell,
      position: GridPosition(0, 0),
      level: 3,
      specialization: TowerSpecialization.crushWell,
    ),
  ];

  for (final tower in towers) {
    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    final adjusted = StageModifierRules.effectiveTowerStats(
      resolvedStats: base,
      stageModifiers: const [StageModifier.amplifiedGravityWells],
    );
    expect(adjusted.fieldRadius, closeTo(base.fieldRadius * 1.20, 0.001));
    expect(
      adjusted.fieldDuration,
      closeTo(base.fieldDuration * 1.25, 0.001),
    );
  }

  final laser = GameBalance.towerStats(TowerType.laser, level: 1);
  expect(
    StageModifierRules.effectiveTowerStats(
      resolvedStats: laser,
      stageModifiers: const [StageModifier.amplifiedGravityWells],
    ),
    same(laser),
  );
});
```

The single-enemy pulse bypass is an orchestration responsibility and is tested
in Task 6, where the caller knows whether another enemy remains.

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
flutter test test/game/stage_modifier_rules_test.dart
```

Expected: FAIL because the rule file and value types do not exist.

- [ ] **Step 3: Extend the narrow `TowerStats.copyWith` contract**

```dart
TowerStats copyWith({
  double? damage,
  double? slowDuration,
  double? fieldRadius,
  double? fieldDuration,
}) {
  return TowerStats(
    type: type,
    level: level,
    specialization: specialization,
    cost: cost,
    upgradeCost: upgradeCost,
    specializationCost: specializationCost,
    range: range,
    damage: damage ?? this.damage,
    fireInterval: fireInterval,
    projectileSpeed: projectileSpeed,
    splashRadius: splashRadius,
    slowMultiplier: slowMultiplier,
    slowDuration: slowDuration ?? this.slowDuration,
    pierceCount: pierceCount,
    pierceWidth: pierceWidth,
    chainCount: chainCount,
    chainRange: chainRange,
    chainFalloff: chainFalloff,
    corrosionDamagePerSecond: corrosionDamagePerSecond,
    corrosionDuration: corrosionDuration,
    armorShred: armorShred,
    fieldRadius: fieldRadius ?? this.fieldRadius,
    fieldDuration: fieldDuration ?? this.fieldDuration,
    fieldTickInterval: fieldTickInterval,
    droneCount: droneCount,
    droneLifetime: droneLifetime,
    droneDamage: droneDamage,
    droneAttackInterval: droneAttackInterval,
    maxActiveDrones: maxActiveDrones,
    shieldDamageMultiplier: shieldDamageMultiplier,
    armorDamageMultiplier: armorDamageMultiplier,
    slowedDamageMultiplier: slowedDamageMultiplier,
    prismSplitDamageMultiplier: prismSplitDamageMultiplier,
    prismSplitRange: prismSplitRange,
    clusterBurstCount: clusterBurstCount,
    clusterBurstDamageMultiplier: clusterBurstDamageMultiplier,
    clusterBurstRadius: clusterBurstRadius,
  );
}
```

Update `game_balance_test.dart` so the existing copy tests also prove the two new overrides and unchanged neighboring fields.

- [ ] **Step 4: Implement the complete pure rule surface**

Create `lib/game/rules/stage_modifier_rules.dart`:

```dart
import 'dart:math' as math;

import '../models/game_models.dart';

class ShieldRechargePolicy {
  const ShieldRechargePolicy({
    required this.delay,
    required this.ratePerSecond,
  });

  final double delay;
  final double ratePerSecond;
}

class EnemyModifierProfile {
  const EnemyModifierProfile({
    this.speedMultiplier = 1,
    this.armorReductionBonus = 0,
    this.shieldRecharge,
  });

  static const identity = EnemyModifierProfile();

  final double speedMultiplier;
  final double armorReductionBonus;
  final ShieldRechargePolicy? shieldRecharge;
}

class StageModifierRules {
  const StageModifierRules._();

  static int effectiveStartingBaseHealth({
    required int campaignAdjustedBaseHealth,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (!stageModifiers.contains(StageModifier.reducedStartingHealth)) {
      return campaignAdjustedBaseHealth;
    }
    return math.max(
      1,
      campaignAdjustedBaseHealth -
          GameBalance.reducedStartingHealthPenalty,
    );
  }

  static int effectiveKillReward({
    required EnemyStats stats,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (!stageModifiers.contains(StageModifier.swarmBounty) ||
        !stats.hasTrait(EnemyTrait.swarm)) {
      return stats.goldReward;
    }
    return (stats.goldReward * GameBalance.swarmBountyMultiplier).round();
  }

  static EnemyModifierProfile enemyProfile({
    required EnemyStats stats,
    required Iterable<StageModifier> stageModifiers,
  }) {
    final shieldRecharge =
        stageModifiers.contains(StageModifier.shieldRecharge) &&
            stats.hasTrait(EnemyTrait.shielded)
        ? const ShieldRechargePolicy(
            delay: GameBalance.shieldRechargeDelay,
            ratePerSecond: GameBalance.shieldRechargeRatePerSecond,
          )
        : null;
    return EnemyModifierProfile(
      speedMultiplier:
          stageModifiers.contains(StageModifier.enemySpeedSurge)
          ? GameBalance.enemySpeedSurgeMultiplier
          : 1,
      armorReductionBonus:
          stageModifiers.contains(StageModifier.reinforcedArmor) &&
              stats.hasTrait(EnemyTrait.armored)
          ? GameBalance.reinforcedArmorBonus
          : 0,
      shieldRecharge: shieldRecharge,
    );
  }

  static double nextSpawnDelay({
    required EnemyStats stats,
    required int spawnedInGroup,
    required double baseSpawnInterval,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (!stageModifiers.contains(StageModifier.regenPressurePulses) ||
        !stats.hasTrait(EnemyTrait.regen)) {
      return baseSpawnInterval;
    }
    return spawnedInGroup % GameBalance.regenPulseBurstSize == 0
        ? GameBalance.regenPulseGap
        : GameBalance.regenPulseInterval;
  }

  static int effectiveClearBonus({
    required int campaignAdjustedClearBonus,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (campaignAdjustedClearBonus <= 0 ||
        !stageModifiers.contains(StageModifier.enhancedClearBonus)) {
      return campaignAdjustedClearBonus;
    }
    return (campaignAdjustedClearBonus *
            GameBalance.enhancedClearBonusMultiplier)
        .round();
  }

  static TowerStats effectiveTowerStats({
    required TowerStats resolvedStats,
    required Iterable<StageModifier> stageModifiers,
  }) {
    if (resolvedStats.type != TowerType.gravityWell ||
        !stageModifiers.contains(StageModifier.amplifiedGravityWells)) {
      return resolvedStats;
    }
    return resolvedStats.copyWith(
      fieldRadius:
          resolvedStats.fieldRadius *
          GameBalance.amplifiedGravityWellRadiusMultiplier,
      fieldDuration:
          resolvedStats.fieldDuration *
          GameBalance.amplifiedGravityWellDurationMultiplier,
    );
  }
}
```

- [ ] **Step 5: Run pure tests and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/stage_modifier_rules_test.dart test/game/game_balance_test.dart
```

Expected: analyzer clean and all pure-rule/model tests pass.

Commit:

```bash
git add lib/game/models/game_models.dart lib/game/rules/stage_modifier_rules.dart test/game/stage_modifier_rules_test.dart test/game/game_balance_test.dart
git commit -m "feat: add pure stage modifier rules (HPA-101)"
```

---

### Task 4: Integrate Starting Health, Clear Bonuses, and Snapshot Projection

**Files:**
- Modify: `lib/game/models/game_models.dart:450-493, 859-883`
- Modify: `lib/game/rules/game_session.dart:7-102, 230-245`
- Modify: `lib/game/orion_defense_game.dart:37-55`
- Modify: `test/game/game_balance_test.dart:795-930, 1227`
- Modify: `test/game/game_session_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`
- Modify: `test/widget_test.dart:85, 179, 1670, 1724, 1774, 1829`
- Modify: `test/widget/sell_button_test.dart:145`

**Interfaces:**
- Produces: required immutable `GameSnapshot.stageModifiers`; `GameBalance.wavePreview(..., required int effectiveClearBonus)`; one private `GameSession._effectiveClearBonus(int)` used by preview and payout.
- Consumes: Task 3 starting-health and clear-bonus rules.

- [ ] **Step 1: Write failing `GameSession` tests**

Add cases for:

```dart
test('Void Bastion resolves campaign health then stage penalty', () {
  final session = GameSession.initial(
    stage: OrionCampaign.stageById('void-bastion'),
    campaignModifiers: const CampaignModifiers(bonusHealth: 5),
  );

  expect(session.startingBaseHealth, 20);
  expect(session.baseHealth, 20);
  session.startWave();
  session.damageBase(3);
  session.restart();
  expect(session.baseHealth, 20);
});

test('Void Bastion applies the stage penalty to an explicit override', () {
  final session = GameSession.initial(
    stage: OrionCampaign.stageById('void-bastion'),
    baseHealth: 4,
  );
  expect(session.startingBaseHealth, 1);
});

test('Void medal thresholds use resolved health and absolute Silver floor', () {
  final session = GameSession.initial(
    stage: OrionCampaign.stageById('void-bastion'),
    campaignModifiers: const CampaignModifiers(bonusHealth: 5),
  );
  expect(session.startingBaseHealth, 20);
  expect(
    StageResult.fromVictoryBaseHealth(
      20,
      startingBaseHealth: session.startingBaseHealth,
    ).medal,
    StageMedal.gold,
  );
  expect(
    StageResult.fromVictoryBaseHealth(
      10,
      startingBaseHealth: session.startingBaseHealth,
    ).medal,
    StageMedal.silver,
  );
  expect(
    StageResult.fromVictoryBaseHealth(
      9,
      startingBaseHealth: session.startingBaseHealth,
    ).medal,
    StageMedal.clear,
  );
});

test('snapshot and payout share tech then stage clear bonus', () {
  final stage = StageDefinition(
    id: 'clear-bonus-stage',
    name: 'Clear Bonus Stage',
    mapLabel: 'Bonus',
    description: 'Two empty waves',
    pathCells: const [
      GridPosition(0, 0),
      GridPosition(1, 0),
    ],
    waves: const [
      WaveDefinition(groups: [], clearBonus: 30),
      WaveDefinition(groups: [], clearBonus: 0),
    ],
    modifiers: const [StageModifier.enhancedClearBonus],
    mapColumn: 0,
    mapRow: 0,
  );
  final session = GameSession.initial(
    stage: stage,
    campaignModifiers: const CampaignModifiers(
      clearBonusFraction: 0.25,
    ),
  );

  expect(session.snapshot().nextWavePreview?.clearBonus, 57);
  final before = session.gold;
  session.startWave();
  session.finishActiveWave();
  expect(session.gold - before, 57);
});

test('snapshot stage modifier list cannot be mutated', () {
  final snapshot = GameSession.initial(
    stage: OrionCampaign.stageById('singularity-core'),
  ).snapshot();

  expect(
    () => snapshot.stageModifiers.add(StageModifier.shieldRecharge),
    throwsUnsupportedError,
  );
});

test('overrideFeedback republishes the active stage modifiers', () {
  final stage = OrionCampaign.stageById('singularity-core');
  final game = OrionDefenseGame(stage: stage);

  game.overrideFeedback('Modifier check');

  expect(game.snapshot.feedback, 'Modifier check');
  expect(game.snapshot.stageModifiers, stage.modifiers);
});

test('Salvage Crew preview is corrected on unmodified Outpost Alpha', () {
  final session = GameSession.initial(
    stage: OrionCampaign.stageOne,
    campaignModifiers: const CampaignModifiers(
      clearBonusFraction: 0.25,
    ),
  );
  final base = OrionCampaign.stageOne.waves.first.clearBonus;

  expect(
    session.snapshot().nextWavePreview?.clearBonus,
    (base * 1.25).round(),
  );
});
```

Place the `overrideFeedback` case in
`test/game/orion_defense_game_test.dart`; place the other cases in
`test/game/game_session_test.dart`.

Keep the existing final-wave zero-bonus test unchanged.

- [ ] **Step 2: Run the session tests to verify they fail**

Run:

```bash
flutter test test/game/game_session_test.dart test/game/orion_defense_game_test.dart
```

Expected: FAIL because health is not stage-adjusted and snapshots do not contain modifiers.

- [ ] **Step 3: Make `GameSession.initial` the sole health resolver**

Convert the constructor to a factory plus private constructor so stage and health are each resolved once:

```dart
factory GameSession.initial({
  StageDefinition? stage,
  CampaignModifiers campaignModifiers = CampaignModifiers.empty,
  int? gold,
  int? baseHealth,
}) {
  final resolvedStage = stage ?? OrionCampaign.stageOne;
  final resolvedGold = gold ?? campaignModifiers.adjustedStartingGold;
  final campaignAdjustedBaseHealth =
      baseHealth ?? campaignModifiers.adjustedStartingBaseHealth;
  final resolvedBaseHealth =
      StageModifierRules.effectiveStartingBaseHealth(
        campaignAdjustedBaseHealth: campaignAdjustedBaseHealth,
        stageModifiers: resolvedStage.modifiers,
      );
  return GameSession._(
    stage: resolvedStage,
    campaignModifiers: campaignModifiers,
    startingGold: resolvedGold,
    startingBaseHealth: resolvedBaseHealth,
  );
}

GameSession._({
  required this.stage,
  required this.campaignModifiers,
  required this.startingGold,
  required this.startingBaseHealth,
}) : _gold = startingGold,
     _baseHealth = startingBaseHealth {
  if (stage.waves.isEmpty) {
    throw ArgumentError.value(
      stage.id,
      'stage',
      'Stage must define at least one wave',
    );
  }
}
```

`OrionDefenseGame` now passes only `stage` and a non-null resolved `campaignModifiers`; remove its pre-resolved `gold` and `baseHealth` arguments.

- [ ] **Step 4: Share one effective-clear-bonus calculation**

Add:

```dart
int _effectiveClearBonus(int baseClearBonus) {
  final campaignAdjusted = (
    baseClearBonus * (1 + campaignModifiers.clearBonusFraction)
  ).round();
  return StageModifierRules.effectiveClearBonus(
    campaignAdjustedClearBonus: campaignAdjusted,
    stageModifiers: stage.modifiers,
  );
}
```

Use `_effectiveClearBonus(wave.clearBonus)` both in `finishActiveWave()` and when calling:

```dart
GameBalance.wavePreview(
  wave: wave,
  waveNumber: waveNumber,
  waveTotal: stage.waves.length,
  unlockedTowerTypes: unlockedTypes,
  effectiveClearBonus: _effectiveClearBonus(wave.clearBonus),
)
```

Change `GameBalance.wavePreview` to require `effectiveClearBonus` and assign it to `WavePreview.clearBonus`. Update its seven direct test call sites to pass `wave.clearBonus` unless a test exercises an adjusted value.

- [ ] **Step 5: Project immutable modifiers through every snapshot**

Add the required constructor input and immutable storage:

```dart
GameSnapshot({
  required this.phase,
  required this.gold,
  required this.baseHealth,
  required this.startingBaseHealth,
  required this.waveNumber,
  required this.waveTotal,
  required this.stageId,
  required this.stageName,
  required this.stageLabel,
  required List<TowerType> unlockedTowerTypes,
  required List<StageModifier> stageModifiers,
  this.nextWavePreview,
  required this.selectedCell,
  required this.selectedTower,
  required this.feedback,
  required this.isPaused,
  required this.speedMultiplier,
  required this.autoStartEnabled,
  required this.autoStartCountdownRemaining,
}) : unlockedTowerTypes = List.unmodifiable(unlockedTowerTypes),
     stageModifiers = List.unmodifiable(stageModifiers);

final List<StageModifier> stageModifiers;
```

Pass `stage.modifiers` from `GameSession.snapshot()`. Add `stageModifiers: const []` to the seven direct test-only `GameSnapshot` constructions. Do not special-case `overrideFeedback`; it already republishes through `GameSession.snapshot()`.

- [ ] **Step 6: Verify and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/game_balance_test.dart test/game/game_session_test.dart test/game/orion_defense_game_test.dart test/widget_test.dart test/widget/sell_button_test.dart
```

Expected: analyzer clean; health, medal, reward, preview, snapshot, and existing widget tests pass.

Commit:

```bash
git add lib/game/models/game_models.dart lib/game/rules/game_session.dart lib/game/orion_defense_game.dart test/game test/widget_test.dart test/widget/sell_button_test.dart
git commit -m "feat: apply session stage modifiers (HPA-101)"
```

---

### Task 5: Apply Resolved Enemy Profiles in `EnemyLogic`

**Files:**
- Modify: `lib/game/rules/enemy_logic.dart:1-279`
- Modify: `test/game/enemy_logic_test.dart`
- Modify: `test/game/enemy_component_test.dart`

**Interfaces:**
- Consumes: `EnemyModifierProfile` and optional `ShieldRechargePolicy` from Task 3.
- Produces: `EnemyLogic({required int enemyId, required EnemyStats stats, required List<Offset> waypoints, EnemyModifierProfile modifierProfile = EnemyModifierProfile.identity, double initialCompletedDistance = 0})`; profile-aware `armorReduction`, damage resolution, shield recharge, and movement.

- [ ] **Step 1: Write failing enemy-logic tests**

Add tests that cover:

```dart
test('reinforced armor getter and damage input agree after shred', () {
  final logic = EnemyLogic(
    enemyId: 1,
    stats: const EnemyStats(
      health: 100,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
      armorReduction: 0.7,
      traits: {EnemyTrait.armored},
    ),
    modifierProfile: const EnemyModifierProfile(
      armorReductionBonus: 0.1,
    ),
    waypoints: const [Offset(0, 0), Offset(100, 0)],
  );

  expect(logic.armorReduction, 0.75);
  logic.applyCorrosion(
    damagePerSecond: 1,
    duration: 5,
    armorShred: 0.2,
  );
  expect(logic.armorReduction, closeTo(0.6, 0.001));
  logic.applyDamage(100);
  expect(logic.health, closeTo(40, 0.001));
});

test('speed surge composes with slow state', () {
  final logic = EnemyLogic(
    enemyId: 1,
    stats: const EnemyStats(
      health: 10,
      speed: 10,
      baseDamage: 1,
      goldReward: 1,
    ),
    modifierProfile: const EnemyModifierProfile(speedMultiplier: 1.15),
    waypoints: const [Offset(0, 0), Offset(100, 0)],
  );
  logic.applySlow(multiplier: 0.5, duration: 2);
  logic.tick(1);
  expect(logic.position.dx, closeTo(5.75, 0.001));
});

test('shield recharge applies only after crossed delay portion', () {
  final logic = shieldLogic(maxShield: 200);
  logic.applyDamage(100);
  expect(logic.shield, 100);

  expect(logic.tick(2.5).overlayDirty, isFalse);
  final result = logic.tick(1);

  expect(logic.shield, closeTo(110, 0.001));
  expect(result.overlayDirty, isTrue);
});

EnemyLogic shieldLogic({required double maxShield}) {
  return EnemyLogic(
    enemyId: 1,
    stats: EnemyStats(
      health: 100,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
      shieldHealth: maxShield,
      traits: const {EnemyTrait.shielded},
    ),
    modifierProfile: const EnemyModifierProfile(
      shieldRecharge: ShieldRechargePolicy(
        delay: 3,
        ratePerSecond: 0.10,
      ),
    ),
    waypoints: const [Offset(0, 0), Offset(100, 0)],
  );
}

test('successful direct damage restarts the recharge delay', () {
  final logic = shieldLogic(maxShield: 200);
  logic.applyDamage(50);
  logic.tick(2.9);
  logic.applyDamage(10);
  logic.tick(0.2);
  expect(logic.shield, 140);
});

test('corrosion damage cannot recharge shield in the same tick', () {
  final logic = shieldLogic(maxShield: 200);
  logic.applyDamage(100);
  logic.applyCorrosion(
    damagePerSecond: 10,
    duration: 5,
    armorShred: 0.1,
  );
  logic.tick(4);
  expect(logic.shield, 60);
});

test('Shield Matriarch profile recharges 20 per second and clamps', () {
  final profile = StageModifierRules.enemyProfile(
    stats: GameBalance.shieldMatriarch,
    stageModifiers: const [StageModifier.shieldRecharge],
  );
  final logic = EnemyLogic(
    enemyId: 1,
    stats: GameBalance.shieldMatriarch,
    modifierProfile: profile,
    waypoints: const [Offset(0, 0), Offset(1000, 0)],
  );
  logic.applyDamage(100);
  logic.tick(4);
  expect(logic.shield, 120);
  logic.tick(10);
  expect(logic.shield, GameBalance.shieldMatriarch.shieldHealth);
});

test('full-shield and resolved enemies do not over-recharge', () {
  final full = shieldLogic(maxShield: 100);
  expect(full.tick(10).overlayDirty, isFalse);
  expect(full.shield, 100);

  final resolved = EnemyLogic(
    enemyId: 2,
    stats: const EnemyStats(
      health: 10,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
    ),
    modifierProfile: const EnemyModifierProfile(
      shieldRecharge: ShieldRechargePolicy(
        delay: 3,
        ratePerSecond: 0.10,
      ),
    ),
    waypoints: const [Offset(0, 0), Offset(100, 0)],
  );
  resolved.applyDamage(10);
  expect(resolved.tick(10).overlayDirty, isFalse);
});
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
flutter test test/game/enemy_logic_test.dart test/game/enemy_component_test.dart
```

Expected: FAIL because `EnemyLogic` has no modifier profile or recharge state.

- [ ] **Step 3: Add profile state and make armor/movement consume it**

Extend the constructor:

```dart
EnemyLogic({
  required this.enemyId,
  required this.stats,
  required List<Offset> waypoints,
  this.modifierProfile = EnemyModifierProfile.identity,
  double initialCompletedDistance = 0,
})

final EnemyModifierProfile modifierProfile;
double _timeSinceDamage = 0;

double get _stageAdjustedBaseArmor =>
    stats.armorReduction + modifierProfile.armorReductionBonus;

double get armorReduction =>
    (_stageAdjustedBaseArmor - armorShred).clamp(0, 0.75).toDouble();
```

Pass `_stageAdjustedBaseArmor` into `DamageInput.armorReduction`, continue passing shred separately, and change movement to:

```dart
var distanceRemaining =
    stats.speed * modifierProfile.speedMultiplier * slowMultiplier * dt;
```

- [ ] **Step 4: Reset damage timing and implement boundary-correct recharge**

In `applyDamage`, capture health/shield before resolution and reset `_timeSinceDamage` only if positive damage changes either. The complete modified resolution block is:

```dart
final previousHealth = health;
final previousShield = shield;
final result = CombatEffects.resolveDamage(
  DamageInput(
    health: health,
    maxHealth: maxHealth,
    shield: shield,
    damage: amount,
    armorReduction: _stageAdjustedBaseArmor,
    armorShred: math.max(this.armorShred, armorShred),
    shieldDamageMultiplier: shieldDamageMultiplier,
    armorDamageMultiplier: armorDamageMultiplier,
    bypassArmor: bypassArmor,
  ),
);
health = result.health;
shield = result.shield;
if (health != previousHealth || shield != previousShield) {
  _timeSinceDamage = 0;
}
```

At tick start capture the prior timer and advance it by non-negative `dt`. After corrosion and health regeneration, recharge only if corrosion did not change health/shield during this tick:

```dart
final elapsedBeforeTick = _timeSinceDamage;
_timeSinceDamage += math.max(0, dt);

// existing corrosion and regen

final policy = modifierProfile.shieldRecharge;
if (policy != null && !corrosionChangedState && shield < stats.shieldHealth) {
  final rechargeDuration =
      math.max(0, _timeSinceDamage - policy.delay) -
      math.max(0, elapsedBeforeTick - policy.delay);
  if (rechargeDuration > 0) {
    final previousShield = shield;
    shield = math.min(
      stats.shieldHealth,
      shield +
          stats.shieldHealth *
              policy.ratePerSecond *
              rechargeDuration,
    );
    if (shield != previousShield) {
      overlayDirty = true;
    }
  }
}
```

When corrosion changes state, `applyDamage` has already reset the timer; keep it at zero and skip recharge for that tick. Run this block before movement.

- [ ] **Step 5: Verify and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/enemy_logic_test.dart test/game/enemy_component_test.dart
```

Expected: all profile, armor, speed, shield, corrosion, and existing shell tests pass.

Commit:

```bash
git add lib/game/rules/enemy_logic.dart test/game/enemy_logic_test.dart test/game/enemy_component_test.dart
git commit -m "feat: apply enemy environmental profiles (HPA-101)"
```

---

### Task 6: Wire Enemy Profiles, Swarm Rewards, and Regen Pulses Through Flame

**Files:**
- Modify: `lib/game/orion_defense_game.dart:660-765`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- Consumes: `stage.modifiers` and all enemy/spawn/reward rules from Task 3.
- Produces: identical profile resolution for normal enemies and summoned minions; modifier-aware spawn delay and kill payout.

- [ ] **Step 1: Write failing game-layer integration tests**

Add synthetic-stage helpers whose waves use slow, durable enemies and at least two path cells. Cover:

```dart
StageDefinition modifierStage({
  required List<StageModifier> modifiers,
  required EnemyStats enemyStats,
  int enemyCount = 1,
  double spawnInterval = 1,
}) {
  return StageDefinition(
    id: 'modifier-stage',
    name: 'Modifier Stage',
    mapLabel: 'Modifier',
    description: 'Synthetic modifier integration stage',
    pathCells: const [
      GridPosition(0, 0),
      GridPosition(1, 0),
      GridPosition(2, 0),
      GridPosition(3, 0),
    ],
    waves: [
      WaveDefinition(
        groups: [
          WaveGroup(
            enemyCount: enemyCount,
            enemyStats: enemyStats,
            spawnInterval: spawnInterval,
          ),
        ],
        clearBonus: 0,
      ),
    ],
    modifiers: modifiers,
    mapColumn: 0,
    mapRow: 0,
  );
}

test('normal enemy receives selected stage profile', () {
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.enemySpeedSurge],
      enemyStats: const EnemyStats(
        health: 100,
        speed: 10,
        baseDamage: 1,
        goldReward: 1,
      ),
    ),
  );
  game.onGameResize(Vector2(800, 1200));
  game.startWave();
  game.update(0);

  final enemy = game.children.whereType<EnemyComponent>().single;
  expect(enemy.logic.modifierProfile.speedMultiplier, 1.15);
});

test('enemy speed surge composes with the player 3x time scale', () {
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.enemySpeedSurge],
      enemyStats: const EnemyStats(
        health: 100,
        speed: 10,
        baseDamage: 1,
        goldReward: 1,
      ),
    ),
  );
  game.onGameResize(Vector2(800, 1200));
  game.setSpeedMultiplier(3);
  game.startWave();
  game.update(0);
  game.update(1);

  final enemy = game.children.whereType<EnemyComponent>().single;
  expect(enemy.pathProgress, closeTo(34.5, 0.001));
});

test('swarm kill callback awards rounded stage bounty', () {
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.swarmBounty],
      enemyStats: const EnemyStats(
        health: 10,
        speed: 1,
        baseDamage: 1,
        goldReward: 5,
        traits: {EnemyTrait.swarm},
      ),
    ),
  );
  final startingGold = game.snapshot.gold;
  game.onGameResize(Vector2(800, 1200));
  game.startWave();
  game.update(0);
  game.children.whereType<EnemyComponent>().single.applyDamage(999);

  expect(game.snapshot.gold, startingGold + 8);
});

test('regen pressure pulses spawn at the accepted six-enemy cadence', () {
  const regen = EnemyStats(
    health: 1000,
    speed: 0,
    baseDamage: 1,
    goldReward: 1,
    traits: {EnemyTrait.regen},
  );
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.regenPressurePulses],
      enemyStats: regen,
      enemyCount: 6,
    ),
  );
  game.onGameResize(Vector2(800, 1200));
  game.startWave();

  game.update(0);
  expect(game.children.whereType<EnemyComponent>(), hasLength(1));
  game.update(0.201);
  expect(game.children.whereType<EnemyComponent>(), hasLength(2));
  game.update(0.201);
  expect(game.children.whereType<EnemyComponent>(), hasLength(3));
  game.update(1.999);
  expect(game.children.whereType<EnemyComponent>(), hasLength(3));
  game.update(0.002);
  expect(game.children.whereType<EnemyComponent>(), hasLength(4));
  game.update(0.201);
  expect(game.children.whereType<EnemyComponent>(), hasLength(5));
  game.update(0.201);
  expect(game.children.whereType<EnemyComponent>(), hasLength(6));
});

test('large dt crosses intra-burst intervals and one pulse gap', () {
  const regen = EnemyStats(
    health: 1000,
    speed: 0,
    baseDamage: 1,
    goldReward: 1,
    traits: {EnemyTrait.regen},
  );
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.regenPressurePulses],
      enemyStats: regen,
      enemyCount: 6,
    ),
  );
  game.onGameResize(Vector2(800, 1200));
  game.startWave();
  game.update(0);
  game.update(2.601);

  expect(game.children.whereType<EnemyComponent>(), hasLength(5));
});

test('non-regen groups retain their base interval', () {
  const normal = EnemyStats(
    health: 1000,
    speed: 0,
    baseDamage: 1,
    goldReward: 1,
  );
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.regenPressurePulses],
      enemyStats: normal,
      enemyCount: 2,
      spawnInterval: 1,
    ),
  );
  game.onGameResize(Vector2(800, 1200));
  game.startWave();
  game.update(0);
  game.update(0.5);
  expect(game.children.whereType<EnemyComponent>(), hasLength(1));
  game.update(0.501);
  expect(game.children.whereType<EnemyComponent>(), hasLength(2));
});

test('summoned minions inherit the synthetic stage profile', () {
  const minion = EnemyStats(
    health: 100,
    speed: 1,
    baseDamage: 1,
    goldReward: 1,
  );
  const boss = BossDefinition(
    health: 1000,
    speed: 0,
    baseDamage: 1,
    goldReward: 1,
    sprite: BossSprite.relayBreaker,
    name: 'Synthetic Summoner',
    summonMechanic: SummonMechanic(
      interval: 100,
      firstDelay: 0.1,
      count: 1,
      maxActive: 1,
      minionStats: minion,
    ),
  );
  final game = OrionDefenseGame(
    stage: modifierStage(
      modifiers: const [StageModifier.enemySpeedSurge],
      enemyStats: boss,
    ),
  );
  game.onGameResize(Vector2(800, 1200));
  game.startWave();
  game.update(0);
  game.update(0.101);
  game.update(0);

  final minionComponent = game.children
      .whereType<EnemyComponent>()
      .singleWhere((enemy) => enemy.minionOf != null);
  expect(minionComponent.logic.modifierProfile.speedMultiplier, 1.15);
});

test('Outpost Alpha keeps identity enemy profile', () {
  final game = OrionDefenseGame(stage: OrionCampaign.stageOne);
  game.onGameResize(Vector2(800, 1200));
  game.startWave();
  game.update(0);

  final enemy = game.children.whereType<EnemyComponent>().single;
  expect(enemy.logic.modifierProfile.speedMultiplier, 1);
  expect(enemy.logic.modifierProfile.armorReductionBonus, 0);
  expect(enemy.logic.modifierProfile.shieldRecharge, isNull);
});
```

Use one parameterized test for both group-completion shapes:

```dart
for (final firstGroupCount in [1, 3]) {
  test(
    'next-group initialDelay wins after $firstGroupCount regen enemies',
    () {
      const regen = EnemyStats(
        health: 1000,
        speed: 0,
        baseDamage: 1,
        goldReward: 1,
        traits: {EnemyTrait.regen},
      );
      const normal = EnemyStats(
        health: 1000,
        speed: 0,
        baseDamage: 1,
        goldReward: 1,
      );
      final stage = StageDefinition(
        id: 'group-transition',
        name: 'Group Transition',
        mapLabel: 'Transition',
        description: 'Synthetic group transition stage',
        pathCells: const [
          GridPosition(0, 0),
          GridPosition(1, 0),
          GridPosition(2, 0),
        ],
        waves: [
          WaveDefinition(
            groups: [
              WaveGroup(
                enemyCount: firstGroupCount,
                enemyStats: regen,
                spawnInterval: 1,
              ),
              const WaveGroup(
                enemyCount: 1,
                enemyStats: normal,
                initialDelay: 5,
              ),
            ],
            clearBonus: 0,
          ),
        ],
        modifiers: const [StageModifier.regenPressurePulses],
        mapColumn: 0,
        mapRow: 0,
      );
      final game = OrionDefenseGame(stage: stage);
      game.onGameResize(Vector2(800, 1200));
      game.startWave();
      game.update(0);
      if (firstGroupCount == 3) {
        game.update(0.201);
        game.update(0.201);
      }

      expect(
        game.children.whereType<EnemyComponent>(),
        hasLength(firstGroupCount),
      );
      game.update(4.996);
      expect(
        game.children.whereType<EnemyComponent>(),
        hasLength(firstGroupCount),
      );
      game.update(0.005);
      expect(
        game.children.whereType<EnemyComponent>(),
        hasLength(firstGroupCount + 1),
      );
    },
  );
}
```

- [ ] **Step 2: Run the integration tests to verify they fail**

Run:

```bash
flutter test test/game/orion_defense_game_test.dart
```

Expected: FAIL because spawn, reward, and profile paths still ignore stage modifiers.

- [ ] **Step 3: Resolve profiles at both spawn sites**

Add a private helper:

```dart
EnemyModifierProfile _enemyModifierProfile(EnemyStats stats) {
  return StageModifierRules.enemyProfile(
    stats: stats,
    stageModifiers: stage.modifiers,
  );
}
```

Pass `modifierProfile: _enemyModifierProfile(stats)` to `EnemyLogic` in both `_spawnEnemy` and `_spawnMinion`. Do not pass raw modifier lists into the logic object.

- [ ] **Step 4: Apply pulse scheduling and bounty resolution**

Replace only the within-group interval branch:

```dart
_spawnTimer += StageModifierRules.nextSpawnDelay(
  stats: group.enemyStats,
  spawnedInGroup: _spawnedInGroup,
  baseSpawnInterval: group.spawnInterval,
  stageModifiers: stage.modifiers,
);
```

Keep group completion and the following group's `initialDelay` branch unchanged. Replace the kill payout with:

```dart
_session.rewardKill(
  StageModifierRules.effectiveKillReward(
    stats: enemy.stats,
    stageModifiers: stage.modifiers,
  ),
);
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/orion_defense_game_test.dart test/game/enemy_logic_test.dart
```

Expected: all normal/minion profile, bounty, pulse, large-delta, and existing game tests pass.

Commit:

```bash
git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: wire enemy stage modifiers into missions (HPA-101)"
```

---

### Task 7: Apply Amplified Gravity Wells Across Placement and Progression

**Files:**
- Modify: `lib/game/rules/tower_stats_resolver.dart:8-26`
- Modify: `lib/game/components/tower_component.dart:16-55`
- Modify: `lib/game/orion_defense_game.dart` (`_addTowerComponent`)
- Modify: `test/game/tower_stats_resolver_test.dart`
- Modify: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- Produces: `TowerStatsResolver.resolve(PlacedTower, {CampaignModifiers campaignModifiers, Iterable<StageModifier> stageModifiers})`.
- Preserves: campaign laser/cryo tech runs first; stage Gravity Well adjustment runs second.

- [ ] **Step 1: Write failing resolver and component-path tests**

For each Gravity Well level and specialization, compare against `GameBalance.towerStats`:

```dart
test('amplifies Gravity Well radius and duration after base resolution', () {
  const tower = PlacedTower(
    id: 1,
    type: TowerType.gravityWell,
    position: GridPosition(0, 0),
  );
  final base = GameBalance.towerStats(TowerType.gravityWell, level: 1);
  final resolved = TowerStatsResolver.resolve(
    tower,
    stageModifiers: const [StageModifier.amplifiedGravityWells],
  );

  expect(resolved.fieldRadius, closeTo(base.fieldRadius * 1.20, 0.001));
  expect(
    resolved.fieldDuration,
    closeTo(base.fieldDuration * 1.25, 0.001),
  );
  expect(resolved.damage, base.damage);
  expect(resolved.range, base.range);
});
```

Add the non-Gravity-Well matrix:

```dart
test('amplified wells leave every other tower type unchanged', () {
  for (final type in TowerType.values.where(
    (type) => type != TowerType.gravityWell,
  )) {
    final tower = PlacedTower(
      id: type.index,
      type: type,
      position: const GridPosition(0, 0),
    );
    final base = GameBalance.towerStats(type, level: 1);
    final resolved = TowerStatsResolver.resolve(
      tower,
      stageModifiers: const [StageModifier.amplifiedGravityWells],
    );

    expect(resolved.fieldRadius, base.fieldRadius);
    expect(resolved.fieldDuration, base.fieldDuration);
    expect(resolved.damage, base.damage);
    expect(resolved.range, base.range);
  }
});
```

Change the existing `_gravityWellUnlockStage` test helper to accept
`List<StageModifier> modifiers = const []` and pass it into
`StageDefinition`. Then add:

```dart
for (final specialization in [
  TowerSpecialization.singularityWell,
  TowerSpecialization.crushWell,
]) {
  test(
    'tower component retains amplified stats through ${specialization.label}',
    () {
      final game = OrionDefenseGame(
        stage: _gravityWellUnlockStage(
          modifiers: const [StageModifier.amplifiedGravityWells],
        ),
        campaignModifiers: const CampaignModifiers(bonusGold: 1000),
      );
      game.onGameResize(Vector2(800, 1200));
      for (var wave = 0; wave < 4; wave += 1) {
        game.startWave();
        game.update(0);
      }
      _tapCell(game, const GridPosition(0, 1));
      game.placeTower(TowerType.gravityWell);

      var component = game.children.whereType<TowerComponent>().single;
      var base = GameBalance.towerStats(TowerType.gravityWell, level: 1);
      expect(
        component.stats.fieldRadius,
        closeTo(base.fieldRadius * 1.20, 0.001),
      );

      game.upgradeSelectedTower();
      component = game.children.whereType<TowerComponent>().single;
      base = GameBalance.towerStats(TowerType.gravityWell, level: 2);
      expect(
        component.stats.fieldDuration,
        closeTo(base.fieldDuration * 1.25, 0.001),
      );

      game.specializeSelectedTower(specialization);
      component = game.children.whereType<TowerComponent>().single;
      base = GameBalance.towerStats(
        TowerType.gravityWell,
        level: 3,
        specialization: specialization,
      );
      expect(
        component.stats.fieldRadius,
        closeTo(base.fieldRadius * 1.20, 0.001),
      );
      expect(
        component.stats.fieldDuration,
        closeTo(base.fieldDuration * 1.25, 0.001),
      );
    },
  );
}
```

- [ ] **Step 2: Run focused tests to verify they fail**

Run:

```bash
flutter test test/game/tower_stats_resolver_test.dart test/game/orion_defense_game_test.dart
```

Expected: FAIL because the resolver and component do not receive stage modifiers.

- [ ] **Step 3: Apply the stage rule after campaign tech**

Refactor the resolver so its existing branches assign `campaignAdjusted`, then return:

```dart
return StageModifierRules.effectiveTowerStats(
  resolvedStats: campaignAdjusted,
  stageModifiers: stageModifiers,
);
```

Use this signature:

```dart
static TowerStats resolve(
  PlacedTower tower, {
  CampaignModifiers campaignModifiers = CampaignModifiers.empty,
  Iterable<StageModifier> stageModifiers = const [],
})
```

In `TowerComponent`, store an immutable stage list:

```dart
TowerComponent({
  required PlacedTower tower,
  required Vector2 center,
  required this.acquireTarget,
  required this.launchProjectile,
  this.spriteSheet,
  this.towerVarietySheet,
  this.campaignModifiers = CampaignModifiers.empty,
  List<StageModifier> stageModifiers = const [],
  double radius = 15,
  super.priority,
}) : stageModifiers = List.unmodifiable(stageModifiers),
     placedTower = tower,
     stats = TowerStatsResolver.resolve(
       tower,
       campaignModifiers: campaignModifiers,
       stageModifiers: stageModifiers,
     ),
     super(
       radius: radius,
       anchor: Anchor.center,
       position: center.clone(),
       paint: Paint()..color = _towerColor(tower.type),
     );

final CampaignModifiers campaignModifiers;
final List<StageModifier> stageModifiers;
```

Call the same resolver with both inputs in the constructor and `updateTower`.

- [ ] **Step 4: Pass the selected stage modifiers from the game**

In `_addTowerComponent`, pass:

```dart
campaignModifiers: campaignModifiers,
stageModifiers: stage.modifiers,
```

No projectile or `GravityFieldComponent` change is needed; both already consume the resolved `TowerStats`.

- [ ] **Step 5: Verify and commit**

Run:

```bash
dart format .
flutter analyze
flutter test test/game/tower_stats_resolver_test.dart test/game/orion_defense_game_test.dart
```

Expected: every level/specialization remains amplified; non-Gravity-Well and campaign-tech tests remain unchanged.

Commit:

```bash
git add lib/game/rules/tower_stats_resolver.dart lib/game/components/tower_component.dart lib/game/orion_defense_game.dart test/game/tower_stats_resolver_test.dart test/game/orion_defense_game_test.dart
git commit -m "feat: amplify Singularity gravity wells (HPA-101)"
```

---

### Task 8: Add the Stage Briefing and Build-Phase Environment Reminder

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart:137-243, 617-684`
- Modify: `test/widget_test.dart`
- Modify: `test/widget/sell_button_test.dart`
- Modify: `integration_test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `StageModifierMetadata`, `StageDefinition.modifiers`, `CampaignProgress.resultFor`, and `GameSnapshot.stageModifiers`.
- Produces: `_showStageBriefing(StageDefinition)`, private `_StageBriefingSheet`, and `_NextWavePanel({required WavePreview preview, required List<String> modifierTitles})`.

- [ ] **Step 1: Add a shared widget-test stage-launch helper and migrate direct taps**

Add a helper to `test/widget_test.dart`:

```dart
Future<void> startStageFromBriefing(
  WidgetTester tester, {
  String mapLabel = 'Alpha',
  String actionLabel = 'Start Mission',
}) async {
  await tester.tap(find.text(mapLabel));
  await tester.pumpAndSettle();
  expect(find.text(actionLabel), findsOneWidget);
  await tester.tap(find.text(actionLabel));
  await tester.pump();
}
```

Replace the current 24 direct Outpost Alpha launch taps in `test/widget_test.dart` with this helper. Add the equivalent interaction to `test/widget/sell_button_test.dart` and update `integration_test/app_smoke_test.dart` to wait for the briefing and tap `Start Mission` before asserting `Build`.

- [ ] **Step 2: Write failing briefing tests**

Add widget tests for:

```dart
testWidgets('unlocked stage opens briefing before game creation', (
  tester,
) async {
  OrionDefenseGame? createdGame;
  await tester.pumpWidget(
    MaterialApp(
      home: OrionGamePage(
        progressStore: InMemoryCampaignProgressStore(
          knownStages: OrionCampaign.stages,
        ),
        onGameCreated: (game) => createdGame = game,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();

  expect(find.text('Outpost Alpha'), findsOneWidget);
  expect(find.text('Standard Conditions'), findsOneWidget);
  expect(find.text('No environmental modifiers'), findsOneWidget);
  expect(createdGame, isNull);

  await tester.tap(find.text('Start Mission'));
  await tester.pump();
  expect(createdGame?.stage.id, 'outpost-alpha');
});
```

Add this store helper:

```dart
Future<InMemoryCampaignProgressStore> storeWithResults(
  Map<String, StageResult> results,
) async {
  final store = InMemoryCampaignProgressStore(
    knownStages: OrionCampaign.stages,
  );
  await store.save(
    CampaignSave(
      progress: CampaignProgress(bestResultsByStageId: results),
      techTree: CampaignTechTree(),
    ),
  );
  return store;
}
```

Add dismissal and replay-result coverage:

```dart
testWidgets('dismiss does not launch and replay shows best result', (
  tester,
) async {
  final store = await storeWithResults({
    'outpost-alpha': const StageResult(
      medal: StageMedal.silver,
      bestBaseHealth: 14,
    ),
  });
  OrionDefenseGame? createdGame;
  await tester.pumpWidget(
    MaterialApp(
      home: OrionGamePage(
        progressStore: store,
        onGameCreated: (game) => createdGame = game,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Alpha'));
  await tester.pumpAndSettle();
  expect(find.text('Replay Mission'), findsOneWidget);
  expect(find.text('Best: Silver • 14 base health'), findsOneWidget);
  await tester.tap(find.text('Dismiss'));
  await tester.pumpAndSettle();
  expect(createdGame, isNull);
});
```

Cover all approved copy from one fully cleared map:

```dart
testWidgets('every modified stage shows its accepted briefing copy', (
  tester,
) async {
  final results = {
    for (final stage in OrionCampaign.stages)
      stage.id: const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 5,
      ),
  };
  final store = await storeWithResults(results);
  await tester.pumpWidget(
    MaterialApp(home: OrionGamePage(progressStore: store)),
  );
  await tester.pumpAndSettle();

  for (final stage in OrionCampaign.stages.skip(1)) {
    await tester.tap(find.text(stage.mapLabel));
    await tester.pumpAndSettle();
    for (final modifier in stage.modifiers) {
      final metadata = StageModifierMetadata.forModifier(modifier);
      expect(find.text(metadata.title), findsOneWidget);
      expect(find.text(metadata.description), findsOneWidget);
    }
    if (stage.id == 'salvage-rift') {
      expect(
        find.text(
          'Completion reward: +${GameBalance.salvageRiftGoldBonus} Gold',
        ),
        findsOneWidget,
      );
    }
    if (stage.id == 'void-bastion') {
      expect(
        find.text(
          'Completion reward: +${GameBalance.voidBastionHealthBonus} HP',
        ),
        findsOneWidget,
      );
    }
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
  }
});
```

Extend the existing locked-stage, in-flight save, and in-flight reset tests
with these assertions immediately after tapping a stage node:

```dart
expect(find.text('Start Mission'), findsNothing);
expect(find.text('Replay Mission'), findsNothing);
expect(createdGame, isNull);
```

Add compact-height and mission-reminder coverage:

```dart
testWidgets('briefing scrolls on a compact portrait surface', (tester) async {
  tester.view.physicalSize = const Size(390, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = await storeWithResults({
    for (final stage in OrionCampaign.stages)
      stage.id: const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 5,
      ),
  });
  await tester.pumpWidget(
    MaterialApp(home: OrionGamePage(progressStore: store)),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Core'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Replay Mission'));
  await tester.pump();

  expect(find.text('Replay Mission'), findsOneWidget);
  expect(tester.takeException(), isNull);
});

testWidgets('build intel shows snapshot modifier titles and hides in wave', (
  tester,
) async {
  final store = await storeWithResults({
    for (final stage in OrionCampaign.stages)
      stage.id: const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 5,
      ),
  });
  OrionDefenseGame? game;
  await tester.pumpWidget(
    MaterialApp(
      home: OrionGamePage(
        progressStore: store,
        onGameCreated: (value) => game = value,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Core'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Replay Mission'));
  await tester.pump();

  expect(
    find.text('Environment: Temporal Surge, Amplified Wells'),
    findsOneWidget,
  );
  game!.startWave();
  await tester.pump();
  expect(find.textContaining('Environment:'), findsNothing);
});
```

Keep the existing end-state panel tests and add
`expect(find.textContaining('Environment:'), findsNothing)` after their won
and lost snapshots are published.

- [ ] **Step 3: Run widget tests to verify the new behavior fails**

Run:

```bash
flutter test test/widget_test.dart test/widget/sell_button_test.dart
```

Expected: new briefing tests fail because stage selection still starts immediately.

- [ ] **Step 4: Route unlocked selection through a modal briefing**

Change:

```dart
onStageSelected: _showStageBriefing,
```

Add:

```dart
Future<void> _showStageBriefing(StageDefinition stage) async {
  final shouldStart = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _StageBriefingSheet(
      stage: stage,
      result: _progress.resultFor(stage.id),
    ),
  );

  if (shouldStart == true && mounted) {
    _startStage(stage);
  }
}
```

Keep `_startStage` guards unchanged so a state change while the sheet is open is still rejected safely. Leave `WorldMapView` locked-node routing unchanged.

- [ ] **Step 5: Implement the complete scrollable sheet**

Build `_StageBriefingSheet` with:

```dart
class _StageBriefingSheet extends StatelessWidget {
  const _StageBriefingSheet({
    required this.stage,
    required this.result,
  });

  final StageDefinition stage;
  final StageResult? result;

  @override
  Widget build(BuildContext context) {
    final metadata = stage.modifiers.isEmpty
        ? [StageModifierMetadata.standardConditions]
        : stage.modifiers
              .map(StageModifierMetadata.forModifier)
              .toList(growable: false);
    final actionLabel = result == null ? 'Start Mission' : 'Replay Mission';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stage.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(stage.description),
          const SizedBox(height: 16),
          for (final entry in metadata) ...[
            Text(
              entry.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(entry.description),
            const SizedBox(height: 12),
          ],
          if (stage.reward != null) Text(_briefingRewardLabel(stage.reward!)),
          if (result != null)
            Text(
              'Best: ${result!.medal.label} • '
              '${result!.bestBaseHealth} base health',
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
```

Implement `_briefingRewardLabel` with the existing values:

```dart
String _briefingRewardLabel(CampaignReward reward) {
  return switch (reward) {
    CampaignReward.bonusGold =>
      'Completion reward: +${GameBalance.salvageRiftGoldBonus} Gold',
    CampaignReward.bonusHealth =>
      'Completion reward: +${GameBalance.voidBastionHealthBonus} HP',
    CampaignReward.challengeBadge => 'Completion reward: Challenge Badge',
  };
}
```

- [ ] **Step 6: Add modifier titles to `_NextWavePanel`**

At the call site:

```dart
_NextWavePanel(
  preview: snapshot.nextWavePreview!,
  modifierTitles: snapshot.stageModifiers.isEmpty
      ? [StageModifierMetadata.standardConditions.title]
      : snapshot.stageModifiers
            .map(
              (modifier) =>
                  StageModifierMetadata.forModifier(modifier).title,
            )
            .toList(growable: false),
),
```

Extend the widget:

```dart
const _NextWavePanel({
  required this.preview,
  required this.modifierTitles,
});

final WavePreview preview;
final List<String> modifierTitles;
```

Render `Environment: ${modifierTitles.join(', ')}` above recommendations. Do not add modifiers to `WavePreview`.

- [ ] **Step 7: Verify widget and integration-test source**

Run:

```bash
dart format .
flutter analyze
flutter test test/widget_test.dart test/widget/sell_button_test.dart
```

Expected: all briefing, reminder, migrated launch, save/reset, and existing widget tests pass.

Commit:

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart test/widget/sell_button_test.dart integration_test/app_smoke_test.dart
git commit -m "feat: add stage modifier briefing UI (HPA-101)"
```

---

### Task 9: Whole-Feature Integration, Regression, and Balance Gate

**Files:**
- Modify if verification exposes a defect: the owning source/test file from Tasks 2-8.
- No new production abstraction is authorized in this task.

**Interfaces:**
- Verifies: all accepted spec behavior across pure rules, session, Flame, UI, and the real integration-test command.
- Produces: recorded manual results in the implementation handoff or pull-request description.

- [ ] **Step 1: Run formatting and static analysis**

Run:

```bash
dart format .
flutter analyze
```

Expected: zero formatting changes after the final format pass and `No issues found`.

- [ ] **Step 2: Run all unit and widget tests**

Run:

```bash
flutter test
```

Expected: all tests pass, including the exact campaign assignment, 253-gold Salvage Rift delta, Shield Matriarch 20 shield/second, Void preview/payout agreement, Aurora large-`dt`, boss-minion inheritance, Gravity Well progression, and briefing interaction coverage.

- [ ] **Step 3: Run the repository integration-test command**

Run:

```bash
flutter test integration_test
```

Expected: the smoke flow opens Outpost Alpha's briefing, taps `Start Mission`, reaches the build phase, starts a wave, and completes without failure.

- [ ] **Step 4: Verify architectural invariants**

Run:

```bash
rg -n "stage\\.id|stageId" lib/game/rules lib/game/components
rg -n "\bmodifiers\b" lib/game/rules/game_session.dart lib/game/rules/tower_stats_resolver.dart lib/game/components/tower_component.dart lib/game/orion_defense_game.dart
rg -n "StageModifier" lib/game/rules/enemy_logic.dart
```

Expected:

- Any stage-ID match is identity projection, validation, or persistence—not a
  modifier behavior branch.
- Any standalone `modifiers` match is the canonical `stage.modifiers` static
  field access—not an ambiguous runtime parameter or field.
- `EnemyLogic` contains no `StageModifier` reference.

- [ ] **Step 5: Run the manual clearability matrix at 1x**

Use the minimum campaign state required to unlock each stage, with no debug gold, health, or damage injection. Record stage, clear result, remaining base health, and observations:

| Stage | Required observation |
| --- | --- |
| Outpost Alpha | Baseline mechanics and clearability remain unchanged. |
| Nebula Relay | Shield recharge is visible, interruptible, and answerable. |
| Salvage Rift | Extra 253 available kill gold does not trivialize later waves. |
| Asteroid Foundry | Reinforced armor is noticeable and armor shred remains useful. |
| Aurora Gate | Bursts and the boss moving from 7.5s to 5.3s after the first regen spawn (2.2s earlier) remain readable and survivable. |
| Void Bastion | Reduced health and increased wave rewards form a viable trade-off. |
| Singularity Core | Faster enemies are controllable with the amplified Gravity Well tool. |

Expected: each stage clears at least once and its modifier materially changes play. If a stage fails, change only the relevant `GameBalance` constant, update the exact tuning/metadata expectation, rerun Steps 1-3, and replay that stage plus Outpost Alpha.

- [ ] **Step 6: Review the final diff and commit any verification-driven correction**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

If Step 5 required a tuning correction:

```bash
git add lib/game/models/game_models.dart test/game docs/superpowers/specs/2026-07-27-orion-stage-environmental-modifiers-design.md
git commit -m "fix: tune stage environmental modifiers (HPA-101)"
```

If no correction was required, leave the already-committed implementation unchanged and include the manual matrix results in the handoff.
