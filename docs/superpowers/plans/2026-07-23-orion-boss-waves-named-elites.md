# Boss Waves & Named Elite Enemies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a named boss enemy to the finale (wave 8) of every campaign stage; Relay Breaker (Outpost Alpha) gets a deterministic periodic minion-summon mechanic end-to-end, the other six ship as stat-block bosses with distinct art.

**Architecture:** `BossDefinition extends EnemyStats` (inheritance hybrid) so bosses ride the existing `WaveGroup → _spawnEnemy → EnemyComponent` path with zero spawn-loop changes. Boss-only fields (`name`, `sprite`, `summonMechanic`) live in the subclass. A minion summon is a timer tick in `EnemyComponent` that fires a callback `(EnemyComponent source, int count)`; `OrionDefenseGame` owns cap enforcement, minion registry bookkeeping, and spawning. A new dedicated `GameBossSheet` provides art.

**Tech Stack:** Flutter + Flame (`flame: ^1.37.0`), Dart SDK `^3.12.0`. Pure logic in `lib/game/models` + `lib/game/rules`; Flame layer in `lib/game/components` + `lib/game/orion_defense_game.dart`.

## Global Constraints

- Dart SDK `^3.12.0`, Flutter `>=3.44.0`, `flame: ^1.37.0` (see `pubspec.yaml`).
- Lint via `flutter analyze`; format via `dart format .`. No comments unless asked.
- Logic/render split: combat/spawn math must remain pure and unit-testable; Flame imports only in `components/` and `orion_defense_game.dart`.
- Trait/defense pairing rule: `shieldHealth > 0` ⇒ `EnemyTrait.shielded`; `armorReduction > 0` ⇒ `armored`; `regenPerSecond > 0` ⇒ `regen`.
- `orion_boss_sheet.png` is a hard load dependency — the PNG must exist and be listed in `pubspec.yaml` or `onLoad` throws.
- Verify after each task: `flutter analyze` clean and the task's `flutter test` green before committing.

## File Structure

- **Modify** `lib/game/models/game_models.dart` — add `BossSprite`, `BossDefinition`, `SummonMechanic`; 7 boss constants + `bosses` accessor in `GameBalance`; boss guard in `_enemyLabelForStats`; append Relay Breaker to `waves[7]`.
- **Modify** `lib/game/campaign/orion_campaign.dart` — `_waves()` gains `finaleBoss`; 6 stages pass their boss; `validateStages` boss-shape invariant.
- **Create** `lib/game/assets/game_boss_sheet.dart` — `GameBossSheet` loader (mirrors `GameTowerVarietySheet`).
- **Modify** `lib/game/rules/enemy_overlay_state.dart` — `EnemyOverlayData.isBoss` (4 sites); `fromData` force flags.
- **Modify** `lib/game/components/enemy_overlay.dart` — `render(..., {String? name})` draws the boss name.
- **Modify** `lib/game/components/enemy_component.dart` — boss fields, `initialCompletedDistance`, `residualWaypointsFromHere()`, summon tick.
- **Modify** `lib/game/orion_defense_game.dart` — `_bossSheet` field/load, `_spawnEnemy` radius+sheet, `_spawnMinion`, summon callback.
- **Modify** `pubspec.yaml` — declare `orion_boss_sheet.png`.
- **Create** `assets/images/orion_boss_sheet.png` — 4×2 sprite sheet (7 cells).
- **Tests:** modify `game_balance_test.dart`, `enemy_component_test.dart`, `orion_campaign_test.dart`, `orion_defense_game_test.dart`; create `game_boss_sheet_test.dart`.

---

### Task 1: Boss data-model types

**Files:**
- Modify: `lib/game/models/game_models.dart` (add types beside `EnemyStats`, ~line 267)
- Test: `test/game/game_balance_test.dart` (new `group('BossDefinition')`)

**Interfaces:**
- Produces: `enum BossSprite`, `class BossDefinition extends EnemyStats`, `class SummonMechanic` — consumed by Tasks 2, 4, 5, 8.

- [ ] **Step 1: Write failing tests** for `SummonMechanic` invariants. Append to `test/game/game_balance_test.dart` inside `main()`:

```dart
group('SummonMechanic', () {
  test('rejects non-positive interval', () {
    expect(
      () => SummonMechanic(
        interval: 0,
        minionStats: const EnemyStats(
          health: 1,
          speed: 1,
          baseDamage: 1,
          goldReward: 1,
        ),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('rejects negative firstDelay and non-positive count', () {
    const stats = EnemyStats(
      health: 1,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
    );
    expect(
      () => SummonMechanic(interval: 1, minionStats: stats, firstDelay: -1),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => SummonMechanic(interval: 1, minionStats: stats, count: 0),
      throwsA(isA<AssertionError>()),
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/game_balance_test.dart --name "SummonMechanic"`
Expected: FAIL — `SummonMechanic` / `BossDefinition` undefined.

- [ ] **Step 3: Add the types** in `lib/game/models/game_models.dart`, immediately after the `EnemyStats` class (after its closing `}` around line 267):

```dart
enum BossSprite {
  relayBreaker,
  shieldMatriarch,
  swarmQueen,
  armoredExcavator,
  regenWarden,
  siegeCarrier,
  singularityCore,
}

class BossDefinition extends EnemyStats {
  const BossDefinition({
    required super.health,
    required super.speed,
    required super.baseDamage,
    required super.goldReward,
    super.traits,
    super.shieldHealth,
    super.armorReduction,
    super.regenPerSecond,
    required this.sprite,
    required this.name,
    this.summonMechanic,
  });

  final BossSprite sprite;
  final String name;
  final SummonMechanic? summonMechanic;
}

class SummonMechanic {
  const SummonMechanic({
    required this.interval,
    required this.minionStats,
    this.firstDelay = 3.0,
    this.count = 3,
    this.maxActive = 9,
  }) : assert(interval > 0, 'interval must be positive'),
       assert(firstDelay >= 0, 'firstDelay must be non-negative'),
       assert(count > 0, 'count must be positive'),
       assert(maxActive >= 0, 'maxActive must be non-negative');

  final double interval;
  final EnemyStats minionStats;
  final double firstDelay;
  final int count;
  final int maxActive;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/game_balance_test.dart --name "SummonMechanic"`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: add BossDefinition and SummonMechanic data types (HPA-99)"
```

---

### Task 2: Boss constants in GameBalance

**Files:**
- Modify: `lib/game/models/game_models.dart` — `GameBalance` (beside the private enemy stats, ~line 476; accessor near `enemyArchetype`, ~line 699)
- Test: `test/game/game_balance_test.dart`

**Interfaces:**
- Consumes: `BossDefinition`, `SummonMechanic`, `BossSprite` (Task 1), private `_basicDrone`.
- Produces: `GameBalance.relayBreaker` (+ 6 constants), `GameBalance.bosses` — consumed by Tasks 3, 4.

- [ ] **Step 1: Write failing tests.** Append a `group('BossDefinition constants')`:

```dart
group('BossDefinition constants', () {
  test('defines seven bosses in stage order', () {
    expect(GameBalance.bosses, hasLength(7));
    expect(
      GameBalance.bosses.map((b) => b.sprite),
      BossSprite.values,
    );
  });

  test('only Relay Breaker has a summon mechanic', () {
    final summoners = GameBalance.bosses.where((b) => b.summonMechanic != null);
    expect(summoners, hasLength(1));
    expect(summoners.single.name, 'Relay Breaker');
  });

  test('Relay Breaker pairs shield and armor with their traits', () {
    final boss = GameBalance.relayBreaker;
    expect(boss.shieldHealth, greaterThan(0));
    expect(boss.traits, contains(EnemyTrait.shielded));
    expect(boss.traits, contains(EnemyTrait.armored));
    expect(boss.traits, contains(EnemyTrait.heavy));
  });

  test('every defense is paired with its trait', () {
    for (final boss in GameBalance.bosses) {
      if (boss.shieldHealth > 0) {
        expect(boss.traits, contains(EnemyTrait.shielded),
            reason: '${boss.name} has shield without shielded trait');
      }
      if (boss.armorReduction > 0) {
        expect(boss.traits, contains(EnemyTrait.armored),
            reason: '${boss.name} has armor without armored trait');
      }
      if (boss.regenPerSecond > 0) {
        expect(boss.traits, contains(EnemyTrait.regen),
            reason: '${boss.name} has regen without regen trait');
      }
    }
  });

  test('Relay Breaker summons basic drones', () {
    final minionStats = GameBalance.relayBreaker.summonMechanic!.minionStats;
    expect(minionStats, same(GameBalance.enemyArchetype(EnemyArchetype.basicDrone)));
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/game_balance_test.dart --name "BossDefinition constants"`
Expected: FAIL — `GameBalance.bosses` / `relayBreaker` undefined.

- [ ] **Step 3: Add the constants** in `GameBalance`, after the existing private enemy stats (after `_regenHeavyDrone`, ~line 541):

```dart
static const BossDefinition relayBreaker = BossDefinition(
  name: 'Relay Breaker',
  sprite: BossSprite.relayBreaker,
  health: 640,
  speed: 46,
  baseDamage: 4,
  goldReward: 120,
  traits: {EnemyTrait.armored, EnemyTrait.shielded, EnemyTrait.heavy},
  armorReduction: 0.40,
  shieldHealth: 100,
  summonMechanic: SummonMechanic(
    interval: 8.0,
    firstDelay: 4.0,
    count: 3,
    maxActive: 9,
    minionStats: _basicDrone,
  ),
);
static const BossDefinition shieldMatriarch = BossDefinition(
  name: 'Shield Matriarch',
  sprite: BossSprite.shieldMatriarch,
  health: 520,
  speed: 50,
  baseDamage: 4,
  goldReward: 120,
  traits: {EnemyTrait.shielded, EnemyTrait.heavy},
  shieldHealth: 200,
);
static const BossDefinition swarmQueen = BossDefinition(
  name: 'Swarm Queen',
  sprite: BossSprite.swarmQueen,
  health: 480,
  speed: 52,
  baseDamage: 3,
  goldReward: 110,
  traits: {EnemyTrait.swarm, EnemyTrait.regen},
  regenPerSecond: 4.0,
);
static const BossDefinition armoredExcavator = BossDefinition(
  name: 'Armored Excavator',
  sprite: BossSprite.armoredExcavator,
  health: 700,
  speed: 44,
  baseDamage: 4,
  goldReward: 130,
  traits: {EnemyTrait.armored, EnemyTrait.heavy},
  armorReduction: 0.45,
);
static const BossDefinition regenWarden = BossDefinition(
  name: 'Regen Warden',
  sprite: BossSprite.regenWarden,
  health: 560,
  speed: 48,
  baseDamage: 4,
  goldReward: 120,
  traits: {EnemyTrait.regen, EnemyTrait.heavy},
  regenPerSecond: 6.0,
);
static const BossDefinition siegeCarrier = BossDefinition(
  name: 'Siege Carrier',
  sprite: BossSprite.siegeCarrier,
  health: 800,
  speed: 42,
  baseDamage: 5,
  goldReward: 140,
  traits: {EnemyTrait.armored, EnemyTrait.heavy},
  armorReduction: 0.35,
);
static const BossDefinition singularityCore = BossDefinition(
  name: 'Singularity Core',
  sprite: BossSprite.singularityCore,
  health: 900,
  speed: 40,
  baseDamage: 5,
  goldReward: 150,
  traits: {
    EnemyTrait.armored,
    EnemyTrait.shielded,
    EnemyTrait.regen,
    EnemyTrait.heavy,
  },
  armorReduction: 0.40,
  shieldHealth: 150,
  regenPerSecond: 5.0,
);
```

Then add an accessor near `enemyArchetype` (~line 711):

```dart
static List<BossDefinition> get bosses => const [
      relayBreaker,
      shieldMatriarch,
      swarmQueen,
      armoredExcavator,
      regenWarden,
      siegeCarrier,
      singularityCore,
    ];
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/game/game_balance_test.dart --name "BossDefinition constants"`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: add seven boss stat constants to GameBalance (HPA-99)"
```

---

### Task 3: Wave-preview boss label

**Files:**
- Modify: `lib/game/models/game_models.dart` — `_enemyLabelForStats` (~line 762)
- Test: `test/game/game_balance_test.dart`

**Interfaces:**
- Consumes: `BossDefinition` (Task 1), `GameBalance.relayBreaker` (Task 2).

- [ ] **Step 1: Write failing test.** Append to the `BossDefinition constants` group:

```dart
test('wave preview labels a boss by name', () {
  final preview = GameBalance.wavePreview(
    wave: WaveDefinition(
      groups: [
        WaveGroup(
          enemyCount: 1,
          enemyStats: GameBalance.relayBreaker,
        ),
      ],
      clearBonus: 0,
    ),
    waveNumber: 8,
    waveTotal: 8,
    unlockedTowerTypes: const [],
  );
  expect(preview.groups.last.label, 'Relay Breaker');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/game_balance_test.dart --name "wave preview labels a boss by name"`
Expected: FAIL — label is `'Drones'` (the `identical` checks miss the boss, falling through to the adjective fallback).

- [ ] **Step 3: Add the guard.** In `_enemyLabelForStats`, make the FIRST line of the method body:

```dart
if (stats is BossDefinition) return stats.name;
```

(`stats` is a parameter here, so it promotes after the `is` check — no cast.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/game/game_balance_test.dart --name "wave preview labels a boss by name"`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: label boss groups by name in wave preview (HPA-99)"
```

---

### Task 4: Wave integration + campaign invariant

**Files:**
- Modify: `lib/game/models/game_models.dart` — append Relay Breaker to `waves[7]` (~line 623)
- Modify: `lib/game/campaign/orion_campaign.dart` — `_waves()` gains `finaleBoss`; 6 stages pass it; `validateStages` invariant
- Test: `test/game/game_balance_test.dart`, `test/game/orion_campaign_test.dart`

**Interfaces:**
- Consumes: `GameBalance.relayBreaker` + the 6 constants (Task 2).
- Produces: every stage's wave 8 ends in a single boss group.

- [ ] **Step 1: Write failing tests.** In `game_balance_test.dart`, in the "approved enemy counts" test, change the last expected row from `enemyCount: 46` to `47`. Then in `orion_campaign_test.dart` add:

```dart
test('every stage wave 8 ends in a single boss with enemyCount 1', () {
  for (final stage in OrionCampaign.stages) {
    final wave = stage.waves.last;
    expect(wave.groups, isNotEmpty);
    final last = wave.groups.last;
    expect(last.enemyStats, isA<BossDefinition>(),
        reason: '${stage.id} wave 8 must end in a boss');
    expect(last.enemyCount, 1, reason: '${stage.id} boss group must be count 1');
    for (var i = 0; i < wave.groups.length - 1; i++) {
      expect(wave.groups[i].enemyStats, isNot(isA<BossDefinition>()),
          reason: '${stage.id} has a non-final boss group');
    }
    for (var w = 0; w < stage.waves.length - 1; w++) {
      for (final g in stage.waves[w].groups) {
        expect(g.enemyStats, isNot(isA<BossDefinition>()),
            reason: '${stage.id} has a boss before wave 8');
      }
    }
  }
});
```

Also add a malformed-data test using a hand-built stage list that violates the shape and asserting `OrionCampaign.validateStages(...)` reports an error. (Reuse the existing pattern in `orion_campaign_test.dart` that calls `validateStages` with custom definitions.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/orion_campaign_test.dart`
Expected: FAIL — no stage ends in a boss yet.

- [ ] **Step 3: Append Relay Breaker to Outpost Alpha wave 8.** In `GameBalance.waves`, the 8th `WaveDefinition` (the one with `clearBonus: 0`, ~line 623) currently has 5 groups. Add a 6th group inside its `groups:` list, before the closing `],`:

```dart
        WaveGroup(
          enemyCount: 1,
          enemyStats: relayBreaker,
          initialDelay: 2.5,
        ),
```

- [ ] **Step 4: Extend `_waves()` in `orion_campaign.dart` (~line 473).** Replace the helper with:

```dart
List<WaveDefinition> _waves(
  List<WaveGroup> singleGroups, {
  BossDefinition? finaleBoss,
  double bossInitialDelay = 2.5,
}) {
  const clearBonuses = [30, 40, 50, 65, 80, 95, 115, 0];
  return List.unmodifiable([
    for (var index = 0; index < singleGroups.length; index += 1)
      WaveDefinition(
        groups: List.unmodifiable(
          index == singleGroups.length - 1 && finaleBoss != null
              ? [
                  singleGroups[index],
                  WaveGroup(
                    enemyCount: 1,
                    enemyStats: finaleBoss,
                    initialDelay: bossInitialDelay,
                  ),
                ]
              : [singleGroups[index]],
        ),
        clearBonus: clearBonuses[index],
      ),
  ]);
}
```

Then pass each stage's boss to its `_waves(...)` call (the six `_xxxWaves` definitions ~lines 407–471). For example:

```dart
final _nebulaRelayWaves = _waves([
  _group(10, EnemyArchetype.basicDrone),
  _group(6, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.basicDrone),
  _group(8, EnemyArchetype.shieldedDrone),
  _group(18, EnemyArchetype.swarmDrone),
  _group(10, EnemyArchetype.shieldedDrone),
  _group(8, EnemyArchetype.regenDrone),
  _group(6, EnemyArchetype.regenHeavyDrone),
], finaleBoss: GameBalance.shieldMatriarch);
```

Mapping: nebula-relay→`shieldMatriarch`, salvage-rift→`swarmQueen`, asteroid-foundry→`armoredExcavator`, aurora-gate→`regenWarden`, void-bastion→`siegeCarrier`, singularity-core→`singularityCore`.

- [ ] **Step 5: Add the `validateStages` invariant.** In the per-stage loop (the `for (final stage in stageList)` block ~line 183, after the existing `waves.length != 8` check), add boss-shape checks. Inside that loop, after the path-cell checks:

```dart
final bossGroups = <int>[];
for (var w = 0; w < stage.waves.length; w++) {
  for (final g in stage.waves[w].groups) {
    if (g.enemyStats is BossDefinition) bossGroups.add(w);
  }
}
if (bossGroups.length != 1) {
  errors.add('${stage.id} must have exactly one boss group; found ${bossGroups.length}.');
} else if (bossGroups.single != stage.waves.length - 1) {
  errors.add('${stage.id} boss must be in the final wave.');
} else {
  final lastGroup = stage.waves.last.groups.last;
  if (lastGroup.enemyStats is! BossDefinition) {
    errors.add('${stage.id} boss must be the final group of the final wave.');
  } else if (lastGroup.enemyCount != 1) {
    errors.add('${stage.id} boss group must have enemyCount 1.');
  }
}
```

- [ ] **Step 6: Run all affected tests**

Run: `flutter test test/game/orion_campaign_test.dart test/game/game_balance_test.dart`
Expected: PASS (including the updated `enemyCount: 47`).

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
git add lib/game/models/game_models.dart lib/game/campaign/orion_campaign.dart test/
git commit -m "feat: append a boss to every stage wave 8 + validate invariant (HPA-99)"
```

---

### Task 5: GameBossSheet loader

**Files:**
- Create: `lib/game/assets/game_boss_sheet.dart`
- Create: `test/game/game_boss_sheet_test.dart`
- Modify: `pubspec.yaml` (assets list, ~line 66)

**Interfaces:**
- Consumes: `BossSprite` (Task 1).
- Produces: `GameBossSheet` class — consumed by Tasks 8, 9.

- [ ] **Step 1: Write failing test.** Create `test/game/game_boss_sheet_test.dart` (mirror `game_tower_variety_sheet` test conventions):

```dart
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameBossSheet', () {
    test('sourceRect maps each BossSprite left-to-right, top-to-bottom', () {
      // 4 columns x 2 rows. Index 0..3 => row 0; 4..6 => row 1.
      final r0 = GameBossSheet.sourceRectFor(BossSprite.relayBreaker,
          imageWidth: 400, imageHeight: 200);
      expect(r0.left, 0);
      expect(r0.top, 0);
      expect(r0.width, 100);
      expect(r0.height, 100);

      final r4 = GameBossSheet.sourceRectFor(BossSprite.regenWarden,
          imageWidth: 400, imageHeight: 200);
      expect(r4.left, 0);
      expect(r4.top, 100); // second row
    });

    test('fileName and assetPath are stable', () {
      expect(GameBossSheet.fileName, 'orion_boss_sheet.png');
      expect(GameBossSheet.assetPath, 'assets/images/orion_boss_sheet.png');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/game_boss_sheet_test.dart`
Expected: FAIL — `GameBossSheet` undefined.

- [ ] **Step 3: Create the loader.** Create `lib/game/assets/game_boss_sheet.dart`, copying the exact shape of `GameTowerVarietySheet`:

```dart
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

class GameBossSheet {
  GameBossSheet._(this._sprites);

  static const String fileName = 'orion_boss_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 2; // 8 cells; BossSprite has 7 values

  final Map<BossSprite, Sprite> _sprites;

  static Future<GameBossSheet> load(Images images) async {
    final image = await images.load(fileName);
    return GameBossSheet.fromImage(image);
  }

  static GameBossSheet fromImage(ui.Image image) {
    final sprites = <BossSprite, Sprite>{};
    for (final sprite in BossSprite.values) {
      final sourceRect = sourceRectFor(
        sprite,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      sprites[sprite] = Sprite(
        image,
        srcPosition: Vector2(sourceRect.left, sourceRect.top),
        srcSize: Vector2(sourceRect.width, sourceRect.height),
      );
    }
    return GameBossSheet._(sprites);
  }

  Sprite sprite(BossSprite sprite) => _sprites[sprite]!;

  static ui.Rect sourceRectFor(
    BossSprite sprite, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final index = sprite.index;
    final cellWidth = imageWidth / columns;
    final cellHeight = imageHeight / rows;
    final column = index % columns;
    final row = index ~/ columns;
    return ui.Rect.fromLTWH(
      column * cellWidth,
      row * cellHeight,
      cellWidth,
      cellHeight,
    );
  }
}
```

- [ ] **Step 4: Declare the asset in `pubspec.yaml`.** Add to the `assets:` list (~line 66):

```yaml
    - assets/images/orion_boss_sheet.png
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/game/game_boss_sheet_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/game/assets/game_boss_sheet.dart test/game/game_boss_sheet_test.dart pubspec.yaml
git commit -m "feat: add GameBossSheet loader and asset declaration (HPA-99)"
```

---

### Task 6: Overlay `isBoss` forces always-on health bar

**Files:**
- Modify: `lib/game/rules/enemy_overlay_state.dart` — `EnemyOverlayData` (factory ~line 13, private ctor ~line 38, field, `copyWith` ~line 60) and `EnemyOverlayState.fromData` (~line 127)
- Test: `test/game/enemy_component_test.dart`

**Interfaces:**
- Consumes: nothing new (a bool).
- Produces: `EnemyOverlayData.isBoss` + forced `shouldRender`/`showHealthBar` — consumed by Task 8.

- [ ] **Step 1: Write failing test.** Append to `test/game/enemy_component_test.dart`:

```dart
test('boss overlay always shows health bar at full health', () {
  final state = EnemyOverlayState.fromData(
    EnemyOverlayData(
      isResolved: false,
      isInspected: false,
      health: 100,
      maxHealth: 100,
      shield: 0,
      maxShield: 0,
      traits: const {},
      isSlowed: false,
      isCorroded: false,
      isBoss: true,
    ),
  );
  expect(state.shouldRender, isTrue);
  expect(state.showHealthBar, isTrue);
});

test('non-boss overlay renders nothing at full health with no traits', () {
  final state = EnemyOverlayState.fromData(
    EnemyOverlayData(
      isResolved: false,
      isInspected: false,
      health: 100,
      maxHealth: 100,
      shield: 0,
      maxShield: 0,
      traits: const {},
      isSlowed: false,
      isCorroded: false,
    ),
  );
  expect(state.shouldRender, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/enemy_component_test.dart --name "boss overlay always shows health bar"`
Expected: FAIL — `isBoss` named param undefined.

- [ ] **Step 3: Add `isBoss` to `EnemyOverlayData` (four sites).** Factory: add `this.isBoss = false` to the param list. Private ctor `._({...})`: add `required this.isBoss`. Field declaration: add `final bool isBoss;`. `copyWith`: add `bool? isBoss` param and `isBoss: isBoss ?? this.isBoss` in the forwarded call.

- [ ] **Step 4: Force the flags in `fromData`.** In `EnemyOverlayState.fromData` (~line 149–176), change:

```dart
final isNotable =
    isDamaged ||
    hasShieldState ||
    hasHighSignalTrait ||
    data.isSlowed ||
    data.isCorroded;
final shouldRender = data.isInspected || isNotable;
```

to:

```dart
final isNotable =
    isDamaged ||
    hasShieldState ||
    hasHighSignalTrait ||
    data.isSlowed ||
    data.isCorroded;
final shouldRender = data.isBoss || data.isInspected || isNotable;
```

and the `showHealthBar:` line to:

```dart
showHealthBar:
    shouldRender && (data.isBoss || data.isInspected || isDamaged || hasShieldState),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/game/enemy_component_test.dart --name "overlay"`
Expected: PASS both.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze
git add lib/game/rules/enemy_overlay_state.dart test/game/enemy_component_test.dart
git commit -m "feat: force always-on health bar for boss overlays (HPA-99)"
```

---

### Task 7: Boss name label in the overlay renderer

**Files:**
- Modify: `lib/game/components/enemy_overlay.dart` — `EnemyOverlayRenderer.render` (~line 25)
- Test: `test/game/enemy_component_test.dart` (smoke: render does not throw with a name)

**Interfaces:**
- Consumes: `EnemyOverlayLayout` (local to `render`), the `name` passed by `EnemyComponent.render` (Task 8).
- Produces: an optional `name` render param.

- [ ] **Step 1: Write failing test.** Append to `test/game/enemy_component_test.dart`:

```dart
test('EnemyOverlayRenderer.render accepts and draws a boss name', () {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final renderer = EnemyOverlayRenderer();
  final state = EnemyOverlayState.fromData(
    EnemyOverlayData(
      isResolved: false,
      isBoss: true,
      health: 100,
      maxHealth: 100,
      shield: 0,
      maxShield: 0,
      traits: const {},
      isSlowed: false,
      isCorroded: false,
    ),
  );
  // Must not throw; the name is drawn above the layout origin.
  renderer.render(canvas, state: state, radius: 20, name: 'Relay Breaker');
  expect(recorder.endRecording(), isNotNull);
});
```

(Add `import 'dart:ui' as ui;` if not present — it already is at the top of the file.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/enemy_component_test.dart --name "draws a boss name"`
Expected: FAIL — `render` has no `name` param.

- [ ] **Step 3: Add the `name` param + draw.** In `EnemyOverlayRenderer.render`, add `String? name` to the signature and, after the bars are drawn (end of method, before closing `}`), add:

```dart
final label = name;
if (label != null) {
  final tp = ui.TextPainter(
    text: ui.TextSpan(
      text: label,
      style: const ui.TextStyle(
        color: ui.Color(0xFFFFFFFF),
        fontSize: 12,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  // originY is component-local (negative = above center); draw the label
  // just above the overlay's top edge.
  tp.paint(canvas, ui.Offset(radius - tp.width / 2, layout.originY - tp.height - 2));
}
```

Add `import 'dart:ui' as ui;` at the top of `enemy_overlay.dart` if not present (it uses `ui` already via `Rect`/`Color`? — check imports; add if needed).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/game/enemy_component_test.dart --name "draws a boss name"`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze
git add lib/game/components/enemy_overlay.dart test/game/enemy_component_test.dart
git commit -m "feat: render boss name above the overlay layout (HPA-99)"
```

---

### Task 8: EnemyComponent boss support + summon timer

**Files:**
- Modify: `lib/game/components/enemy_component.dart` — constructor (~line 18), new fields, `residualWaypointsFromHere()`, summon tick in `update`
- Test: `test/game/enemy_component_test.dart`

**Interfaces:**
- Consumes: `GameBossSheet` (Task 5), `BossDefinition`/`SummonMechanic` (Task 1), `EnemyOverlayData.isBoss` (Task 6).
- Produces: `EnemyComponent` boss fields, `residualWaypointsFromHere()`, `initialCompletedDistance` — consumed by Task 9.

- [ ] **Step 1: Write failing tests.** Append to `test/game/enemy_component_test.dart`:

```dart
test('summon callback fires after firstDelay then every interval', () {
  final sources = <EnemyComponent>[];
  final counts = <int>[];
  final boss = EnemyComponent(
    enemyId: 1,
    stats: GameBalance.relayBreaker,
    waypoints: [Vector2(0, 0), Vector2(10000, 0)],
    onKilled: (_) {},
    onReachedBase: (_) {},
    onSummonMinions: (source, count) {
      sources.add(source);
      counts.add(count);
    },
  );
  // firstDelay = 4.0
  boss.update(4.0);
  expect(counts, [3]);
  boss.update(8.0);
  expect(counts, [3, 3]);
  expect(sources.first, same(boss));
});

test('data-slot boss never summons', () {
  var fired = 0;
  final boss = EnemyComponent(
    enemyId: 1,
    stats: GameBalance.shieldMatriarch,
    waypoints: [Vector2(0, 0), Vector2(10000, 0)],
    onKilled: (_) {},
    onReachedBase: (_) {},
    onSummonMinions: (_, __) => fired += 1,
  );
  boss.update(100);
  expect(fired, 0);
});

test('residualWaypointsFromHere starts at current position', () {
  final boss = EnemyComponent(
    enemyId: 1,
    stats: GameBalance.relayBreaker,
    waypoints: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)],
    onKilled: (_) {},
    onReachedBase: (_) {},
  );
  boss.update(1.0); // moves ~46 units along x, clamped to path
  final residual = boss.residualWaypointsFromHere();
  expect(residual.first, equals(boss.position));
  expect(residual.length, greaterThanOrEqualTo(2));
});

test('initialCompletedDistance seeds pathProgress', () {
  final boss = EnemyComponent(
    enemyId: 1,
    stats: const EnemyStats(health: 10, speed: 0, baseDamage: 1, goldReward: 1),
    waypoints: [Vector2(0, 0), Vector2(100, 0)],
    initialCompletedDistance: 50,
    onKilled: (_) {},
    onReachedBase: (_) {},
  );
  expect(boss.pathProgress, closeTo(50, 0.001));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/game/enemy_component_test.dart --name "summon callback"`
Expected: FAIL — `onSummonMinions`/`residualWaypointsFromHere`/`initialCompletedDistance` undefined.

- [ ] **Step 3: Update the constructor + fields.** Replace the constructor (~lines 18–39) with:

```dart
EnemyComponent({
  required this.enemyId,
  required EnemyStats stats,
  required List<Vector2> waypoints,
  required this.onKilled,
  required this.onReachedBase,
  this.spriteSheet,
  this.towerVarietySheet,
  this.bossSheet,
  this.onSummonMinions,
  this.minionOf,
  this.initialCompletedDistance = 0,
  double radius = 11,
  super.priority,
}) : stats = stats,
     waypoints = List.unmodifiable(waypoints.map((point) => point.clone())),
     health = stats.health,
     _completedDistance = initialCompletedDistance,
     _summonRemaining = _initialSummonDelay(stats),
     assert(
       waypoints.length >= 2,
       'EnemyComponent requires at least two waypoints',
     ),
     super(
       radius: radius,
       anchor: Anchor.center,
       position: waypoints.first.clone(),
       paint: Paint()..color = const Color(0xFFE35D6A),
     );
```

Add imports: `import '../assets/game_boss_sheet.dart';` and ensure `BossDefinition` is reachable (it's in `game_models.dart`, already imported).

Add the new fields + change `_completedDistance`/add `_summonRemaining` (remove the `= 0` from `_completedDistance`'s declaration since it's now set in the initializer list):

```dart
final GameSpriteSheet? spriteSheet;       // unchanged
final GameTowerVarietySheet? towerVarietySheet; // unchanged
final GameBossSheet? bossSheet;
final void Function(EnemyComponent source, int count)? onSummonMinions;
final int? minionOf;
final double initialCompletedDistance;

double _completedDistance;
double _summonRemaining;

static double _initialSummonDelay(EnemyStats stats) {
  if (stats is BossDefinition) {
    final mechanic = stats.summonMechanic;
    if (mechanic != null) return mechanic.firstDelay;
  }
  return 0;
}
```

- [ ] **Step 4: Set `isBoss` in the overlay getter.** In the `overlayState` getter's `EnemyOverlayData(...)` (~line 82), add `isBoss: stats is BossDefinition,`.

- [ ] **Step 5: Add `residualWaypointsFromHere()`.** Add a public method:

```dart
List<Vector2> residualWaypointsFromHere() =>
    [position.clone(), ...waypoints.sublist(_targetWaypointIndex)];
```

- [ ] **Step 6: Add the summon tick in `update`.** At the end of `update(dt)` (after `_tickSlow(dt);`), add:

```dart
final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
final mechanic = bossDef?.summonMechanic;
if (mechanic != null && onSummonMinions != null) {
  _summonRemaining -= dt;
  while (_summonRemaining <= 0) {
    _summonRemaining += mechanic.interval;
    onSummonMinions!(this, mechanic.count);
  }
}
```

- [ ] **Step 7: Update `render` to pass the boss name + use the boss sheet.** In `render` (~line 192), replace the sprite block:

```dart
final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
if (bossDef != null && bossSheet != null) {
  bossSheet!.sprite(bossDef.sprite).render(
    canvas,
    position: Vector2(radius, radius),
    size: Vector2.all(radius * 2.4),
    anchor: Anchor.center,
  );
} else if (spriteSheet != null) {
  spriteSheet!
      .sprite(GameSpriteSheet.spriteForEnemy(stats))
      .render(
        canvas,
        position: Vector2(radius, radius),
        size: Vector2.all(radius * 2.4),
        anchor: Anchor.center,
      );
} else {
  super.render(canvas);
}

_overlayRenderer.render(
  canvas,
  state: overlayState,
  radius: radius,
  towerVarietySheet: towerVarietySheet,
  name: bossDef?.name,
);
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/game/enemy_component_test.dart`
Expected: PASS (all boss tests + existing tests green).

- [ ] **Step 9: Analyze + commit**

```bash
flutter analyze
git add lib/game/components/enemy_component.dart test/game/enemy_component_test.dart
git commit -m "feat: EnemyComponent boss fields, summon timer, name render (HPA-99)"
```

---

### Task 9: OrionDefenseGame wiring (_bossSheet, _spawnMinion, summon callback)

**Files:**
- Modify: `lib/game/orion_defense_game.dart` — `onLoad`, `_spawnEnemy` (~line 651), new `_spawnMinion`, summon callback, fields
- Test: `test/game/orion_defense_game_test.dart`

**Interfaces:**
- Consumes: `GameBossSheet` (Task 5), boss `EnemyComponent` fields (Task 8).
- Produces: end-to-end boss + minion gameplay.

- [ ] **Step 1: Write failing tests.** Append to `test/game/orion_defense_game_test.dart`. These drive a wave to the boss and assert minion behavior. Use the existing pattern of advancing the game with `update(dt)` and querying `game.children.whereType<EnemyComponent>()`:

```dart
test('boss summons minions that path from its position and block completion', () {
  final game = OrionDefenseGame();
  game.onLoad(); // not awaited in unit tests is unsafe; instead use the
  // existing test helper in this file that builds a ready game (follow the
  // pattern already used by the wave-spawn tests in this file).
  // NOTE: mirror the exact setup the surrounding tests use to obtain a
  // loaded game (they construct OrionDefenseGame and call update() in a
  // FlameGame test harness). See an existing passing wave test for the
  // harness call.
}, skip: 'wire to the existing game-test harness in this file');
```

Because game-layer render/spawn tests need the Flame test harness used by the surrounding tests, the implementer MUST mirror the exact harness setup of an existing passing wave test in `orion_defense_game_test.dart` (construct the game, pump `update()` until the boss spawns, then assert). Replace the `skip:` placeholder with a real test that: (a) starts wave 8, pumps until the boss appears, pumps past `firstDelay`, asserts `game.children.whereType<EnemyComponent>().where((e) => e.minionOf != null)` is non-empty and each minion's `pathProgress` is within a small epsilon of the boss's; (b) kills the boss and asserts minions remain and the wave is not complete until they are cleared.

- [ ] **Step 2: Implement the wiring.** Add a field near the other sheet fields:

```dart
GameBossSheet? _bossSheet;
```

In `onLoad` (~line 101), after `_towerVarietySheet = await GameTowerVarietySheet.load(images);`, add:

```dart
_bossSheet = await GameBossSheet.load(images);
```

Add the import: `import 'assets/game_boss_sheet.dart';`.

- [ ] **Step 3: Update `_spawnEnemy`.** Replace `_spawnEnemy` (~line 651) so a boss gets radius 20, the boss sheet, and an `onSummonMinions` callback:

```dart
void _spawnEnemy(EnemyStats stats) {
  final bossDef = stats is BossDefinition ? stats as BossDefinition : null;
  final enemy = EnemyComponent(
    enemyId: _nextEnemyId,
    stats: stats,
    waypoints: _pathWaypoints(),
    spriteSheet: _spriteSheet,
    towerVarietySheet: _towerVarietySheet,
    bossSheet: _bossSheet,
    onKilled: _handleEnemyKilled,
    onReachedBase: _handleEnemyReachedBase,
    onSummonMinions: bossDef == null ? null : _handleSummonMinions,
    radius: bossDef == null ? 11 : 20,
    priority: 20,
  );
  _nextEnemyId += 1;
  _activeEnemyComponents[enemy.enemyId] = enemy;
  add(enemy);
}
```

- [ ] **Step 4: Add `_spawnMinion` + the summon callback.** Add (import `dart:math` as `math` if not already):

```dart
void _handleSummonMinions(EnemyComponent source, int count) {
  final mechanic = (source.stats as BossDefinition).summonMechanic;
  if (mechanic == null) return;
  final active = _activeEnemyComponents.values
      .where((e) => e.minionOf == source.enemyId && e.isAlive)
      .length;
  final toSpawn = math.max(0, math.min(count, mechanic.maxActive - active));
  for (var i = 0; i < toSpawn; i++) {
    _spawnMinion(source, mechanic.minionStats);
  }
}

void _spawnMinion(EnemyComponent boss, EnemyStats stats) {
  final residual = boss.residualWaypointsFromHere();
  if (residual.length < 2) return; // boss effectively at base; skip
  final enemy = EnemyComponent(
    enemyId: _nextEnemyId,
    stats: stats,
    waypoints: residual,
    initialCompletedDistance: boss.pathProgress,
    spriteSheet: _spriteSheet,
    towerVarietySheet: _towerVarietySheet,
    minionOf: boss.enemyId,
    onKilled: _handleEnemyKilled,
    onReachedBase: _handleEnemyReachedBase,
    priority: 20,
  );
  _nextEnemyId += 1;
  _activeEnemyComponents[enemy.enemyId] = enemy;
  add(enemy);
}
```

- [ ] **Step 5: Fill in the placeholder test** using the existing game-test harness (remove `skip:`). Assert minions spawn after `firstDelay`, path from the boss, honor `maxActive`, and survive the boss's death.

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/game/orion_defense_game_test.dart && flutter analyze`
Expected: PASS, analyze clean.

- [ ] **Step 7: Commit**

```bash
flutter analyze
git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: wire boss sheet, minion spawning, and summon callback (HPA-99)"
```

---

### Task 10: Generate the boss sprite sheet art

**Files:**
- Create: `assets/images/orion_boss_sheet.png` (4 columns × 2 rows; 7 cells in `BossSprite` order)

**Interfaces:**
- Consumes: `GameBossSheet` (Task 5) — the PNG must match its 4×2 grid.

- [ ] **Step 1: Invoke the generating-images-with-cli skill** (load `generating-images-with-cli`) to drive a CLI generator producing a single 1024×512 (or 800×400) PNG with 7 boss sprites in `BossSprite` order (relayBreaker, shieldMatriarch, swarmQueen, armoredExcavator, regenWarden, siegeCarrier, singularityCore), matching the existing `orion_sprite_sheet.png` art style. Scratch work under `tmp/`.

- [ ] **Step 2: Place the final PNG** at `assets/images/orion_boss_sheet.png`.

- [ ] **Step 3: Smoke-test the full app**

Run: `flutter run` (or the integration test), start Outpost Alpha, reach wave 8, and confirm: Relay Breaker spawns with boss art + name label + always-on health bar, summons minions after ~4s, and the wave completes only when boss + minions are cleared.

- [ ] **Step 4: Commit**

```bash
git add assets/images/orion_boss_sheet.png
git commit -m "feat: add boss sprite sheet art (HPA-99)"
```

---

## Self-Review

**Spec coverage:** every spec section maps to a task — data model (T1), constants (T2), preview label (T3), wave integration + invariant (T4), sheet loader (T5), overlay isBoss (T6), name label (T7), component boss support + summon timer + pathProgress seed + residual waypoints (T8), game wiring + minion bookkeeping + cap (T9), art (T10). Acceptance criteria: model (T1), ≥1 e2e boss (T8+T9+T10), distinct render (T6+T7+T8+T10), defeat completes wave (T9, unchanged completion path), deterministic mechanics (T8 fake-clock tests), non-boss waves unchanged (T4 augment-only, asserted in T4 tests).

**Type consistency:** `onSummonMinions` is `(EnemyComponent, int)` in T8 and T9 (matched). `initialCompletedDistance` ctor param in T8, set from `boss.pathProgress` in T9 (matched). `GameBossSheet.sprite(BossSprite)` in T5, used in T8 (matched). `EnemyOverlayData.isBoss` in T6, set in T8's overlay getter (matched). `render(..., name:)` in T7, passed in T8 (matched).

**Placeholder scan:** T9 Step 1/5 contains a `skip:` placeholder for the game-test harness — this is deliberate and flagged for the implementer to mirror the existing harness (game-layer Flame tests require the specific harness already used in that file; fabricating it blind would be wrong). All other steps contain real code.
