# Tower & Enemy Codex Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only Codex reachable from the campaign map that explains Orion's towers, enemies, traits, combat effects, and stages — generated entirely from `GameBalance` / enums.

**Architecture:** A pure presentation layer (`lib/game/codex/codex_data.dart` + shared `util/format.dart` + `campaign/stage_reward_label.dart`) reads tuning and exposes immutable value types via a `CodexData` façade. A thin Flutter `CodexView` renders it. Entry point mirrors the existing in-place `_ShellView` swap used by the Tech Tree (no `Navigator.push`).

**Tech Stack:** Flutter, Dart SDK `^3.12.0`, `flame ^1.37.0` (codex itself uses neither Flame nor Flutter in its data layer).

**Spec:** `docs/superpowers/specs/2026-07-28-orion-tower-and-enemy-codex-design.md`

## Global Constraints

- **Pure-layer boundary:** `lib/game/codex/codex_data.dart`, `lib/game/util/format.dart`, and `lib/game/campaign/stage_reward_label.dart` must NOT import `package:flutter` or `package:flame`. They import only `game_models.dart`, `campaign_progress.dart`, `stage_definition.dart`, `stage_modifier_metadata.dart`, and each other.
- **No duplicated tuning constants:** every number shown in the codex is read from `GameBalance` / enum values at runtime. The only authored strings are short prose blurbs.
- **Copy rules:** enemy names are plural and must equal today's `_enemyLabelForStats` output verbatim (e.g. `"Armored Drones"`); tower availability reads as `"Available from wave N"` (in-mission gating, not campaign progression).
- **Enhanced-enum conversions are source-compatible:** all existing `TowerType.laser` / `EnemyTrait.armored` / `EnemyArchetype.basicDrone` references and `const <EnemyTrait>{...}` literals must keep compiling.
- **Verification gates (every task):** run `flutter analyze` and `dart format .` before committing (per `AGENTS.md`). Test command is `flutter test <path>` (or `flutter test` for the whole suite).
- **Commits:** conventional-commit prefixes matching repo history (`refactor:`, `feat:`, `test:`), each suffixed `(HPA-103)`.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/game/util/format.dart` | create | neutral `percent` / `number` formatters |
| `lib/game/campaign/stage_modifier_metadata.dart` | edit | drop private `_percent`/`_number`, use `util/format` |
| `lib/game/models/game_models.dart` | edit | add `label` to `TowerType`/`EnemyTrait`/`EnemyArchetype`; delegate `_enemyLabelForStats` + `_traitAdjective` |
| `lib/game/campaign/stage_reward_label.dart` | create | pure `stageRewardLabel(stage, {required bool isCleared})` |
| `lib/game/ui/world_map_view.dart` | edit | adopt shared `stageRewardLabel`; add `onOpenCodex` button |
| `lib/game/ui/tower_icons.dart` | create | `IconData towerIcon(TowerType)` |
| `lib/game/ui/orion_game_page.dart` | edit | drop `_towerLabel`/`_enemyTraitLabel`/`_towerIcon`; add `_ShellView.codex` + open/close |
| `lib/game/codex/codex_data.dart` | create | PURE value types + `CodexData` façade + authored prose |
| `lib/game/ui/codex_view.dart` | create | Flutter widget (Scaffold + section chips + cards) |
| `test/game/util/format_test.dart` | create | formatter tests |
| `test/game/enum_labels_test.dart` | create | enum label + delegation tests |
| `test/game/campaign/stage_reward_label_test.dart` | create | reward-label contract tests |
| `test/game/codex/codex_data_test.dart` | create | headline codex-data coverage |
| `test/widget/codex_view_test.dart` | create | widget smoke + narrow-layout test |

---

## Task 1: Shared formatters (`util/format.dart`)

Promote the private `_percent` / `_number` helpers out of `StageModifierMetadata` into a neutral util module so both the campaign layer and the codex can share them without `campaign` depending on `codex`.

**Files:**
- Create: `lib/game/util/format.dart`
- Modify: `lib/game/campaign/stage_modifier_metadata.dart` (remove `_percent`/`_number`, import util)
- Test: `test/game/util/format_test.dart`; plus existing `test/game/stage_modifier_metadata_test.dart` must still pass unchanged.

**Interfaces:**
- Produces: `String percent(double value)` and `String number(double value)` in `package:orion/game/util/format.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/game/util/format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/util/format.dart';

void main() {
  test('percent rounds to nearest whole percent', () {
    expect(percent(0.5), '50%');
    expect(percent(0.424), '42%');
    expect(percent(1.2), '120%');
  });

  test('number drops trailing .0 for whole values, else one decimal', () {
    expect(number(2.0), '2');
    expect(number(2.5), '2.5');
    expect(number(0.45), '0.5');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/util/format_test.dart`
Expected: FAIL — "Target of URI doesn't exist: 'package:orion/game/util/format.dart'".

- [ ] **Step 3: Create the formatter module**

Create `lib/game/util/format.dart`:

```dart
/// Shared, dependency-free formatting helpers used by campaign metadata and
/// the codex. Lives in neutral `util/` so neither layer depends on the other.
String percent(double value) => '${(value * 100).round()}%';

String number(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
```

- [ ] **Step 4: Update StageModifierMetadata to use them**

In `lib/game/campaign/stage_modifier_metadata.dart`:
- Add `import '../util/format.dart';` at the top (after the existing `import '../models/game_models.dart';`).
- Delete the two private methods at the bottom of the file:
  ```dart
  static String _percent(double value) => '${(value * 100).round()}%';

  static String _number(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }
  ```
- Replace the two call sites (`_percent(` → `percent(`, `_number(` → `number(`) inside `forModifier`.

- [ ] **Step 5: Run both formatter and metadata tests**

Run: `flutter test test/game/util/format_test.dart test/game/stage_modifier_metadata_test.dart`
Expected: PASS. The metadata test pins exact strings (`'...10% max shields per second after 3 seconds...'`, `'...20% radius and 25% duration.'`) — they must be byte-identical, proving the promotion changed nothing observable.

- [ ] **Step 6: Analyze + format + commit**

Run: `flutter analyze && dart format .`
Then:
```bash
git add lib/game/util/format.dart lib/game/campaign/stage_modifier_metadata.dart test/game/util/format_test.dart
git commit -m "refactor: promote percent/number formatters to util/format (HPA-103)"
```

---

## Task 2: Enhanced-enum labels + dedupe enemy/trait text

Make `TowerType`, `EnemyTrait`, and `EnemyArchetype` enhanced enums with a `label`, then retire the two duplicate text sites (`_enemyLabelForStats` literal branches and `_traitAdjective`) by delegating to the enum labels. Wave-preview output must not change.

**Files:**
- Modify: `lib/game/models/game_models.dart`
  - `TowerType` enum (currently lines ~5-14)
  - `EnemyTrait` enum (line ~40)
  - `EnemyArchetype` enum (lines ~53-63)
  - `GameBalance._enemyLabelForStats` (lines ~943-981) — the nine `identical(stats, _xDrone)` branches
  - `GameBalance._traitAdjective` (lines ~983-991)
- Test: `test/game/enum_labels_test.dart`; plus full suite `flutter test` to catch any label regression.

**Interfaces:**
- Produces: `TowerType.label`, `EnemyTrait.label`, `EnemyArchetype.label` (all `String`).
- Preserves: `_enemyLabelForStats` return values byte-for-byte (wave previews depend on them).

- [ ] **Step 1: Write the failing test**

Create `test/game/enum_labels_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  test('TowerType labels are non-empty for every value', () {
    for (final type in TowerType.values) {
      expect(type.label, isNotEmpty);
    }
    expect(TowerType.ionChain.label, 'Ion Chain');
    expect(TowerType.gravityWell.label, 'Gravity Well');
  });

  test('EnemyTrait labels match the canonical adjectives', () {
    expect(EnemyTrait.armored.label, 'Armored');
    expect(EnemyTrait.shielded.label, 'Shielded');
    expect(EnemyTrait.swarm.label, 'Swarm');
    expect(EnemyTrait.regen.label, 'Regen');
    expect(EnemyTrait.heavy.label, 'Heavy');
  });

  test('EnemyArchetype labels match wave-preview text exactly', () {
    expect(EnemyArchetype.basicDrone.label, 'Drones');
    expect(EnemyArchetype.basicEliteDrone.label, 'Elite Drones');
    expect(EnemyArchetype.armoredDrone.label, 'Armored Drones');
    expect(EnemyArchetype.shieldedDrone.label, 'Shielded Drones');
    expect(EnemyArchetype.swarmDrone.label, 'Swarm Drones');
    expect(EnemyArchetype.regenDrone.label, 'Regen Drones');
    expect(EnemyArchetype.heavyDrone.label, 'Heavy Drones');
    expect(EnemyArchetype.armoredHeavyDrone.label, 'Armored Heavy Drones');
    expect(EnemyArchetype.regenHeavyDrone.label, 'Regen Heavy Drones');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/enum_labels_test.dart`
Expected: FAIL — `TowerType`/`EnemyTrait`/`EnemyArchetype` have no `label` getter.

- [ ] **Step 3: Convert the three enums to enhanced enums with `label`**

Replace the `TowerType` enum declaration with:

```dart
enum TowerType {
  laser('Laser'),
  rocket('Rocket'),
  cryo('Cryo'),
  railgun('Railgun'),
  ionChain('Ion Chain'),
  nanite('Nanite'),
  gravityWell('Gravity Well'),
  droneBay('Drone Bay');

  const TowerType(this.label);
  final String label;
}
```

Replace the `EnemyTrait` enum declaration with:

```dart
enum EnemyTrait {
  armored('Armored'),
  shielded('Shielded'),
  swarm('Swarm'),
  regen('Regen'),
  heavy('Heavy');

  const EnemyTrait(this.label);
  final String label;
}
```

Replace the `EnemyArchetype` enum declaration with:

```dart
enum EnemyArchetype {
  basicDrone('Drones'),
  basicEliteDrone('Elite Drones'),
  armoredDrone('Armored Drones'),
  shieldedDrone('Shielded Drones'),
  swarmDrone('Swarm Drones'),
  regenDrone('Regen Drones'),
  heavyDrone('Heavy Drones'),
  armoredHeavyDrone('Armored Heavy Drones'),
  regenHeavyDrone('Regen Heavy Drones');

  const EnemyArchetype(this.label);
  final String label;
}
```

- [ ] **Step 4: Delegate the duplicate text sites to the enum labels**

In `GameBalance._enemyLabelForStats`, replace each of the nine literal-returning `identical(stats, _xDrone)` branches so they return the matching `EnemyArchetype.x.label`. The boss branch (`if (stats is BossDefinition) return stats.name;`) and the generic trait-adjective fallback after the nine branches stay unchanged. For example:

```dart
if (identical(stats, _basicDrone)) {
  return EnemyArchetype.basicDrone.label;
}
if (identical(stats, _basicEliteDrone)) {
  return EnemyArchetype.basicEliteDrone.label;
}
if (identical(stats, _armoredDrone)) {
  return EnemyArchetype.armoredDrone.label;
}
if (identical(stats, _shieldedDrone)) {
  return EnemyArchetype.shieldedDrone.label;
}
if (identical(stats, _swarmDrone)) {
  return EnemyArchetype.swarmDrone.label;
}
if (identical(stats, _regenDrone)) {
  return EnemyArchetype.regenDrone.label;
}
if (identical(stats, _heavyDrone)) {
  return EnemyArchetype.heavyDrone.label;
}
if (identical(stats, _armoredHeavyDrone)) {
  return EnemyArchetype.armoredHeavyDrone.label;
}
if (identical(stats, _regenHeavyDrone)) {
  return EnemyArchetype.regenHeavyDrone.label;
}
```

Replace the entire `_traitAdjective` method body to delegate:

```dart
static String _traitAdjective(EnemyTrait trait) {
  return trait.label;
}
```

- [ ] **Step 5: Run the label test + full suite**

Run: `flutter test`
Expected: PASS, including the new `enum_labels_test.dart` and every existing test (wave-preview and balance tests are unchanged because the delegated strings are identical).

- [ ] **Step 6: Analyze + format + commit**

Run: `flutter analyze && dart format .`
Then:
```bash
git add lib/game/models/game_models.dart test/game/enum_labels_test.dart
git commit -m "refactor: add enhanced-enum labels and dedupe enemy/trait text (HPA-103)"
```

---

## Task 3: `stageRewardLabel` helper

Extract world_map_view's file-private `_rewardLabel` into a shared pure function so both `world_map_view` and the codex use one implementation.

**Files:**
- Create: `lib/game/campaign/stage_reward_label.dart`
- Modify: `lib/game/ui/world_map_view.dart` (delete `_rewardLabel` at lines ~215-232; import and call the shared helper)
- Test: `test/game/campaign/stage_reward_label_test.dart`

**Interfaces:**
- Produces: `String? stageRewardLabel(StageDefinition stage, {required bool isCleared})` in `package:orion/game/campaign/stage_reward_label.dart`.
- Contract: main/no-reward → `null`; `CampaignReward.challengeBadge` → `null`; uncleared side stage → `'Reward: +X …'`; cleared side stage → `'+X …'`. Reads `GameBalance.salvageRiftGoldBonus` (gold) and `GameBalance.voidBastionHealthBonus` (HP).

- [ ] **Step 1: Write the failing test**

Create `test/game/campaign/stage_reward_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_reward_label.dart';

void main() {
  // Salvage Rift = bonusGold side stage; Void Bastion = bonusHealth side stage.
  final salvageRift = OrionCampaign.stageById('salvage-rift');
  final voidBastion = OrionCampaign.stageById('void-bastion');
  // Outpost Alpha = main stage, no reward.
  final outpostAlpha = OrionCampaign.stageById(OrionCampaign.stageOneId);

  test('main stage with no reward returns null', () {
    expect(stageRewardLabel(outpostAlpha, isCleared: false), isNull);
    expect(stageRewardLabel(outpostAlpha, isCleared: true), isNull);
  });

  test('uncleared side stage shows the "Reward:" prefix', () {
    expect(
      stageRewardLabel(salvageRift, isCleared: false),
      'Reward: +${GameBalance.salvageRiftGoldBonus} Gold',
    );
    expect(
      stageRewardLabel(voidBastion, isCleared: false),
      'Reward: +${GameBalance.voidBastionHealthBonus} HP',
    );
  });

  test('cleared side stage drops the prefix', () {
    expect(
      stageRewardLabel(salvageRift, isCleared: true),
      '+${GameBalance.salvageRiftGoldBonus} Gold',
    );
  });
}
```

(Add `import 'package:orion/game/models/game_models.dart';` for `GameBalance`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/campaign/stage_reward_label_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Create the helper**

Create `lib/game/campaign/stage_reward_label.dart`:

```dart
import '../models/game_models.dart';
import 'stage_definition.dart';

/// Player-facing reward label for a stage, shared by the world map and the
/// codex. Mirrors the previous world_map_view._rewardLabel exactly.
String? stageRewardLabel(StageDefinition stage, {required bool isCleared}) {
  final reward = stage.reward;
  if (reward == null) {
    return null;
  }

  final amount = switch (reward) {
    CampaignReward.bonusGold => '+${GameBalance.salvageRiftGoldBonus} Gold',
    CampaignReward.bonusHealth => '+${GameBalance.voidBastionHealthBonus} HP',
    CampaignReward.challengeBadge => null,
  };

  if (amount == null) {
    return null;
  }

  return isCleared ? amount : 'Reward: $amount';
}
```

- [ ] **Step 4: Adopt it in world_map_view**

In `lib/game/ui/world_map_view.dart`:
- Add `import '../campaign/stage_reward_label.dart';`.
- Delete the file-private `String? _rewardLabel(StageDefinition stage, bool isCleared) { ... }` function (currently lines ~215-232).
- Update its two call sites in `_StageNode.build` (the `final rewardLabel = _rewardLabel(stage, status == StageProgressStatus.cleared);` line) to call the shared helper:
  ```dart
  final rewardLabel = stageRewardLabel(
    stage,
    isCleared: status == StageProgressStatus.cleared,
  );
  ```

- [ ] **Step 5: Run the helper test + full suite**

Run: `flutter test`
Expected: PASS (the world map behavior is unchanged; existing widget tests continue to guard it).

- [ ] **Step 6: Analyze + format + commit**

Run: `flutter analyze && dart format .`
Then:
```bash
git add lib/game/campaign/stage_reward_label.dart lib/game/ui/world_map_view.dart test/game/campaign/stage_reward_label_test.dart
git commit -m "refactor: extract stageRewardLabel helper (HPA-103)"
```

---

## Task 4: `towerIcon` helper + label migration in the game page

Move the Flutter-dependent `towerIcon` into its own UI helper and switch `orion_game_page` from its private `_towerLabel` / `_enemyTraitLabel` / `_towerIcon` to the enum labels + helper.

**Files:**
- Create: `lib/game/ui/tower_icons.dart`
- Modify: `lib/game/ui/orion_game_page.dart` (remove the three private functions at ~lines 1331-1365; update call sites)
- Test: verify via `flutter analyze` + full `flutter test` (no new test file; the migration is mechanical and covered by existing widget tests).

**Interfaces:**
- Produces: `IconData towerIcon(TowerType type)` in `package:orion/game/ui/tower_icons.dart`.
- Consumes: `TowerType.label`, `EnemyTrait.label` (from Task 2).

- [ ] **Step 1: Create the helper module**

Create `lib/game/ui/tower_icons.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/game_models.dart';

/// Flutter-dependent icon mapping for tower types. Kept out of the pure model
/// layer (which must not import Flutter) and shared by the game page and codex.
IconData towerIcon(TowerType type) {
  return switch (type) {
    TowerType.laser => Icons.bolt,
    TowerType.rocket => Icons.rocket_launch,
    TowerType.cryo => Icons.ac_unit,
    TowerType.railgun => Icons.linear_scale,
    TowerType.ionChain => Icons.electrical_services,
    TowerType.nanite => Icons.bubble_chart,
    TowerType.gravityWell => Icons.blur_circular,
    TowerType.droneBay => Icons.hub,
  };
}
```

- [ ] **Step 2: Migrate orion_game_page call sites**

In `lib/game/ui/orion_game_page.dart`:
- Add `import 'tower_icons.dart';` (same `ui/` directory, relative import).
- Replace every `_towerLabel(x)` call site with `x.label`.
- Replace every `_enemyTraitLabel(x)` call site with `x.label`.
- Replace every `_towerIcon(x)` call site with `towerIcon(x)`.
- Delete the three private top-level functions: `String _towerLabel(TowerType type)`, `String _enemyTraitLabel(EnemyTrait trait)`, and `IconData _towerIcon(TowerType type)` (currently ~lines 1331-1365).

- [ ] **Step 3: Analyze + run full suite**

Run: `flutter analyze && flutter test`
Expected: PASS, no analyzer warnings. (The functions were file-private, so no test outside the file referenced them; the change is behavior-preserving.)

- [ ] **Step 4: Format + commit**

Run: `dart format .`
Then:
```bash
git add lib/game/ui/tower_icons.dart lib/game/ui/orion_game_page.dart
git commit -m "refactor: extract towerIcon and use enum labels in game page (HPA-103)"
```

---

## Task 5: Pure `CodexData` façade (headline coverage)

The core of the feature: immutable value types + a `CodexData` façade that reads `GameBalance` / enums and carries the authored prose. Pure — no Flutter, no Flame.

**Files:**
- Create: `lib/game/codex/codex_data.dart`
- Test: `test/game/codex/codex_data_test.dart`

**Interfaces:**
- Consumes: `GameBalance.towerStats / towerUnlockWave / specializationsFor / enemyArchetype`, `TowerType.values`, `TowerSpecialization.values` (`.type`), `EnemyArchetype.values`, `EnemyTrait.values` + their `.label` (Task 2), `percent`/`number` (Task 1), `stageRewardLabel` (Task 3), `StageModifierMetadata.forModifier` / `.standardConditions`, `CampaignProgress.statusFor` / `.isCleared`, `OrionCampaign.stages`.
- Produces: classes `CodexTowerEntry`, `CodexSpecializationEntry`, `CodexEnemyEntry`, `CodexTraitEntry`, `CodexEffectEntry`, `CodexStageEntry`; and `CodexData` with `static List<CodexTowerEntry> get towers`, `static CodexTowerEntry towerFor(TowerType)`, `static List<CodexEnemyEntry> get enemies`, `static List<CodexTraitEntry> get traits`, `static List<CodexEffectEntry> get effects`, `static List<CodexStageEntry> stagesFor(CampaignProgress)`.

- [ ] **Step 1: Write the failing test**

Create `test/game/codex/codex_data_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('towers', () {
    test('covers every TowerType with exactly its two specializations', () {
      expect(CodexData.towers.length, TowerType.values.length);
      for (final entry in CodexData.towers) {
        expect(entry.label, entry.type.label);
        expect(entry.unlockWave, GameBalance.towerUnlockWave(entry.type));
        expect(
          entry.specializations.map((s) => s.specialization).toList(),
          GameBalance.specializationsFor(entry.type),
        );
      }
    });

    test('specializationCost is hoisted per-type and matches level:2 stats', () {
      for (final entry in CodexData.towers) {
        expect(
          entry.specializationCost,
          GameBalance.towerStats(entry.type, level: 2).specializationCost,
        );
      }
    });

    test('every blurb is non-empty', () {
      for (final t in CodexData.towers) {
        for (final s in t.specializations) {
          expect(s.description, isNotEmpty);
        }
      }
    });
  });

  group('enemies', () {
    test('covers every EnemyArchetype with matching stats and label', () {
      expect(CodexData.enemies.length, EnemyArchetype.values.length);
      for (final entry in CodexData.enemies) {
        expect(entry.label, entry.archetype.label);
        expect(entry.stats, GameBalance.enemyArchetype(entry.archetype));
        expect(entry.roleDescription, isNotEmpty);
        // Traits follow enum order, not the Set's insertion order.
        expect(
          entry.traits,
          EnemyTrait.values.where(entry.stats.traits.contains).toList(),
        );
      }
    });
  });

  group('traits', () {
    test('covers every EnemyTrait with non-empty effect text', () {
      expect(CodexData.traits.length, EnemyTrait.values.length);
      for (final entry in CodexData.traits) {
        expect(entry.label, entry.trait.label);
        expect(entry.effect, isNotEmpty);
      }
    });
  });

  group('effects', () {
    const expectedIds = [
      'slow',
      'corrosion',
      'armorShred',
      'shieldDamage',
      'pierce',
      'chain',
      'splash',
      'drones',
      'gravityField',
    ];

    test('has the nine glossary ids in fixed order', () {
      expect(CodexData.effects.map((e) => e.id).toList(), expectedIds);
      for (final e in CodexData.effects) {
        expect(e.title, isNotEmpty);
        expect(e.description, isNotEmpty);
      }
    });

    test('every effect resolves to >= 1 related specialization by derivation', () {
      for (final e in CodexData.effects) {
        expect(
          e.relatedSpecializations,
          isNotEmpty,
          reason: '${e.id} should map to >= 1 specialization',
        );
        for (final spec in e.relatedSpecializations) {
          expect(spec, isA<TowerSpecialization>());
        }
      }
    });

    test('derived specialization sets match the signal fields', () {
      bool statsFor(TowerSpecialization s) =>
          GameBalance.towerStats(s.type, level: 3, specialization: s).slowMultiplier <
          1;
      final slowSpecs = TowerSpecialization.values.where(statsFor).toSet();
      expect(
        CodexData.effects.firstWhere((e) => e.id == 'slow').relatedSpecializations.toSet(),
        slowSpecs,
      );
    });
  });

  group('stagesFor', () {
    test('status mirrors CampaignProgress.statusFor for each stage', () {
      final progress = CampaignProgress(); // empty
      final entries = CodexData.stagesFor(progress);
      expect(entries.length, OrionCampaign.stages.length);
      for (final entry in entries) {
        expect(entry.status, progress.statusFor(entry.stage));
        expect(entry.waveCount, entry.stage.waves.length);
      }
    });

    test('empty progress marks Outpost Alpha unlocked, others locked', () {
      final entries = CodexData.stagesFor(CampaignProgress());
      final byId = {for (final e in entries) e.stage.id: e};
      expect(
        byId[OrionCampaign.stageOneId]!.status,
        StageProgressStatus.unlocked,
      );
      final others = entries
          .where((e) => e.stage.id != OrionCampaign.stageOneId)
          .toList();
      expect(others.every((e) => e.status == StageProgressStatus.locked), isTrue);
    });

    test('modifiers map via StageModifierMetadata, with standard fallback', () {
      final entries = CodexData.stagesFor(CampaignProgress());
      for (final entry in entries) {
        if (entry.stage.modifiers.isEmpty) {
          expect(
            entry.modifiers,
            [StageModifierMetadata.standardConditions],
          );
        } else {
          expect(
            entry.modifiers,
            [
              for (final m in entry.stage.modifiers)
                StageModifierMetadata.forModifier(m),
            ],
          );
        }
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/game/codex/codex_data_test.dart`
Expected: FAIL — `package:orion/game/codex/codex_data.dart` doesn't exist.

- [ ] **Step 3: Implement the value types and façade**

Create `lib/game/codex/codex_data.dart` with the content below. (All prose is authored; all numbers come from `GameBalance` / enums at runtime.)

```dart
import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/stage_reward_label.dart';
import '../models/game_models.dart';
import '../util/format.dart';

class CodexTowerEntry {
  const CodexTowerEntry({
    required this.type,
    required this.label,
    required this.unlockWave,
    required this.baseStats,
    required this.upgradeCost,
    required this.specializationCost,
    required this.specializations,
  });

  final TowerType type;
  final String label;
  final int unlockWave;
  final TowerStats baseStats;
  final int upgradeCost;
  final int specializationCost;
  final List<CodexSpecializationEntry> specializations;
}

class CodexSpecializationEntry {
  const CodexSpecializationEntry({
    required this.specialization,
    required this.label,
    required this.specializedStats,
    required this.description,
  });

  final TowerSpecialization specialization;
  final String label;
  final TowerStats specializedStats;
  final String description;
}

class CodexEnemyEntry {
  const CodexEnemyEntry({
    required this.archetype,
    required this.label,
    required this.stats,
    required this.traits,
    required this.roleDescription,
  });

  final EnemyArchetype archetype;
  final String label;
  final EnemyStats stats;
  final List<EnemyTrait> traits;
  final String roleDescription;
}

class CodexTraitEntry {
  const CodexTraitEntry({required this.trait, required this.label, required this.effect});

  final EnemyTrait trait;
  final String label;
  final String effect;
}

class CodexEffectEntry {
  const CodexEffectEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.relatedSpecializations,
  });

  final String id;
  final String title;
  final String description;
  final List<TowerSpecialization> relatedSpecializations;
}

class CodexStageEntry {
  const CodexStageEntry({
    required this.stage,
    required this.status,
    required this.modifiers,
    required this.waveCount,
    required this.rewardLabel,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final List<StageModifierMetadata> modifiers;
  final int waveCount;
  final String? rewardLabel;
}

class CodexData {
  const CodexData._();

  static List<CodexTowerEntry> get towers => [
    for (final type in TowerType.values) towerFor(type),
  ];

  static CodexTowerEntry towerFor(TowerType type) {
    final baseStats = GameBalance.towerStats(type, level: 1);
    return CodexTowerEntry(
      type: type,
      label: type.label,
      unlockWave: GameBalance.towerUnlockWave(type),
      baseStats: baseStats,
      upgradeCost: baseStats.upgradeCost,
      specializationCost: GameBalance.towerStats(type, level: 2).specializationCost,
      specializations: [
        for (final spec in GameBalance.specializationsFor(type))
          CodexSpecializationEntry(
            specialization: spec,
            label: spec.label,
            specializedStats: GameBalance.towerStats(
              type,
              level: 3,
              specialization: spec,
            ),
            description: _specializationDescription(spec),
          ),
      ],
    );
  }

  static List<CodexEnemyEntry> get enemies => [
    for (final archetype in EnemyArchetype.values)
      CodexEnemyEntry(
        archetype: archetype,
        label: archetype.label,
        stats: GameBalance.enemyArchetype(archetype),
        traits: EnemyTrait.values
            .where(GameBalance.enemyArchetype(archetype).traits.contains)
            .toList(growable: false),
        roleDescription: _enemyRole(archetype),
      ),
  ];

  static List<CodexTraitEntry> get traits => const [
    CodexTraitEntry(trait: EnemyTrait.armored, label: 'Armored', effect: 'Reduces incoming damage by a flat percentage.'),
    CodexTraitEntry(trait: EnemyTrait.shielded, label: 'Shielded', effect: 'Carries a shield that absorbs damage and recharges out of combat.'),
    CodexTraitEntry(trait: EnemyTrait.swarm, label: 'Swarm', effect: 'Fast and fragile; arrives in large numbers.'),
    CodexTraitEntry(trait: EnemyTrait.regen, label: 'Regen', effect: 'Regenerates health when not taking damage.'),
    CodexTraitEntry(trait: EnemyTrait.heavy, label: 'Heavy', effect: 'High health; slow but durable.'),
  ];

  static List<CodexEffectEntry> get effects => [
    CodexEffectEntry(
      id: 'slow',
      title: 'Slow',
      description: 'Reduces enemy move speed. The strongest slow in play takes '
          'effect — slows do not stack additively.',
      relatedSpecializations: _specsWhere((s) => s.slowMultiplier < 1),
    ),
    CodexEffectEntry(
      id: 'corrosion',
      title: 'Corrosion',
      description: 'Applies damage over time on hit and shreds armor for the duration.',
      relatedSpecializations: _specsWhere((s) => s.corrosionDamagePerSecond > 0),
    ),
    CodexEffectEntry(
      id: 'armorShred',
      title: 'Armor Shred',
      description: 'Permanently strips a fraction of an armored enemy\'s damage reduction per hit.',
      relatedSpecializations: _specsWhere((s) => s.armorShred > 0),
    ),
    CodexEffectEntry(
      id: 'shieldDamage',
      title: 'Shield Damage',
      description: 'A damage multiplier applied only against shielded enemies\' shields.',
      relatedSpecializations: _specsWhere((s) => s.shieldDamageMultiplier != 1),
    ),
    CodexEffectEntry(
      id: 'pierce',
      title: 'Pierce',
      description: 'A projectile passes through multiple enemies in a line.',
      relatedSpecializations: _specsWhere((s) => s.pierceCount > 0),
    ),
    CodexEffectEntry(
      id: 'chain',
      title: 'Chain Lightning',
      description: 'Lightning jumps from the primary target to nearby enemies, '
          'with falloff on each jump.',
      relatedSpecializations: _specsWhere((s) => s.chainCount > 0),
    ),
    CodexEffectEntry(
      id: 'splash',
      title: 'Splash',
      description: 'Area damage around the impact point hits every enemy in radius.',
      relatedSpecializations: _specsWhere((s) => s.splashRadius > 0),
    ),
    CodexEffectEntry(
      id: 'drones',
      title: 'Drones',
      description: 'The tower launches autonomous drones that engage targets until they expire '
          '(up to a per-bay active cap).',
      relatedSpecializations: _specsWhere((s) => s.droneCount > 0),
    ),
    CodexEffectEntry(
      id: 'gravityField',
      title: 'Gravity Field',
      description: 'A persistent field ticks damage on enemies inside for its duration '
          'and may also slow them.',
      relatedSpecializations: _specsWhere((s) => s.fieldRadius > 0),
    ),
  ];

  static List<CodexStageEntry> stagesFor(CampaignProgress progress) {
    return [
      for (final stage in OrionCampaign.stages)
        CodexStageEntry(
          stage: stage,
          status: progress.statusFor(stage),
          modifiers: stage.modifiers.isEmpty
              ? const [StageModifierMetadata.standardConditions]
              : [
                  for (final m in stage.modifiers)
                    StageModifierMetadata.forModifier(m),
                ],
          waveCount: stage.waves.length,
          rewardLabel: stageRewardLabel(
            stage,
            isCleared: progress.isCleared(stage.id),
          ),
        ),
    ];
  }

  // --- authored prose (grounded in specializedStats; no tuning literals) ---

  static List<TowerSpecialization> _specsWhere(
    bool Function(TowerStats) predicate,
  ) {
    return [
      for (final spec in TowerSpecialization.values)
        if (predicate(
          GameBalance.towerStats(spec.type, level: 3, specialization: spec),
        ))
        spec,
    ];
  }

  static String _specializationDescription(TowerSpecialization spec) {
    return switch (spec) {
      TowerSpecialization.pulseLaser =>
        'Maximized fire rate for concentrated single-target damage.',
      TowerSpecialization.prismLaser =>
        'Each shot splits to nearby targets at reduced damage.',
      TowerSpecialization.siegeRocket =>
        'Heaviest single hit with the largest splash radius.',
      TowerSpecialization.clusterRocket =>
        'Detonates into clustered sub-explosions across the impact area.',
      TowerSpecialization.deepFreeze =>
        'The strongest, longest slow; locks enemies down at the cost of raw damage.',
      TowerSpecialization.frostbite =>
        'Balanced slow that deals bonus damage to already-slowed enemies.',
      TowerSpecialization.lanceRailgun =>
        'Maximum pierce — punches through the most targets in a line.',
      TowerSpecialization.magneticRailgun =>
        'Trades pierce for bonus damage versus armored enemies.',
      TowerSpecialization.stormRelay =>
        'The longest chain lightning, jumping to the most targets.',
      TowerSpecialization.overloadRelay =>
        'Trades chain count for bonus damage versus shielded enemies.',
      TowerSpecialization.dissolverNanites =>
        'Peak corrosion and armor shred to strip the heaviest plating.',
      TowerSpecialization.replicatorNanites =>
        'Balanced corrosion stream with sustained damage and lighter shred.',
      TowerSpecialization.singularityWell =>
        'The largest, longest-lasting field — also slows enemies caught inside.',
      TowerSpecialization.crushWell =>
        'A tighter, concentrated field for a focused kill zone.',
      TowerSpecialization.interceptorBay =>
        'More, faster-firing drones for broad interception.',
      TowerSpecialization.hunterBay =>
        'Fewer, harder-hitting drones that persist longer.',
    };
  }

  static String _enemyRole(EnemyArchetype archetype) {
    return switch (archetype) {
      EnemyArchetype.basicDrone =>
        'Standard fodder — modest health and no defenses.',
      EnemyArchetype.basicEliteDrone =>
        'A tougher baseline drone with notably more health.',
      EnemyArchetype.armoredDrone =>
        'Reduces incoming damage via armor; favors high single hits.',
      EnemyArchetype.shieldedDrone =>
        'Absorbs hits with a shield that recharges out of combat.',
      EnemyArchetype.swarmDrone =>
        'Fast, fragile, and numerous.',
      EnemyArchetype.regenDrone =>
        'Heals itself over time when not under fire.',
      EnemyArchetype.heavyDrone =>
        'A slow, high-health bruiser.',
      EnemyArchetype.armoredHeavyDrone =>
        'A heavy frame with armor — extremely durable.',
      EnemyArchetype.regenHeavyDrone =>
        'A heavy frame that regenerates health.',
    };
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/game/codex/codex_data_test.dart`
Expected: PASS — every tower/enemy/trait/effect/stage assertion holds.

- [ ] **Step 5: Analyze + format + commit**

Run: `flutter analyze && dart format .`
Then:
```bash
git add lib/game/codex/codex_data.dart test/game/codex/codex_data_test.dart
git commit -m "feat: add pure CodexData facade for the codex (HPA-103)"
```

---

## Task 6: `CodexView` widget

A full-screen (in-place) widget: section chips that filter the visible section, and cards that render the `CodexData` entries. Returns its own `Scaffold` + `SafeArea` like `TechTreeView`, with a back button wired to an `onBack` callback (no `AppBar` default back).

**Files:**
- Create: `lib/game/ui/codex_view.dart`
- Test: `test/widget/codex_view_test.dart`

**Interfaces:**
- Consumes: `CodexData` (Task 5), `towerIcon` (Task 4), `CampaignProgress`.
- Produces: `CodexView({required CampaignProgress progress, required VoidCallback onBack})`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/codex_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/codex_view.dart';

void main() {
  testWidgets('renders the four section chips and Towers content by default',
      (tester) async {
    await tester.binding.runWithFrameSize(const Size(360, 640), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: CodexView(
            progress: CampaignProgress(),
            onBack: () {},
          ),
        ),
      );

      for (final chip in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
        expect(find.text(chip), findsWidgets);
      }
      // Default section is Towers: the first tower label appears.
      expect(find.text(TowerType.laser.label), findsOneWidget);
    });
  });

  testWidgets('tapping Enemies shows the enemy section', (tester) async {
    await tester.binding.runWithFrameSize(const Size(360, 640), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: CodexView(
            progress: CampaignProgress(),
            onBack: () {},
          ),
        ),
      );
      await tester.tap(find.text('Enemies'));
      await tester.pumpAndSettle();
      expect(find.text(EnemyArchetype.basicDrone.label), findsOneWidget);
    });
  });

  testWidgets('back button invokes onBack', (tester) async {
    var pressed = false;
    await tester.binding.runWithFrameSize(const Size(360, 640), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: CodexView(
            progress: CampaignProgress(),
            onBack: () => pressed = true,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Back'));
      expect(pressed, isTrue);
    });
  });
}
```

> Note: `tester.binding.runWithFrameSize` requires binding initialization; if the Flutter version in use complains, wrap in `tester.view.physicalSize` / `tester.view.devicePixelRatio` instead and call `addTearDown(tester.view.resetPhysicalSize)`. The exact mechanic is whatever the existing `test/widget/tech_tree_view_test.dart` uses — mirror it.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/codex_view_test.dart`
Expected: FAIL — `CodexView` doesn't exist.

- [ ] **Step 3: Implement the widget**

Create `lib/game/ui/codex_view.dart`. It mirrors `TechTreeView`'s structure: a `StatefulWidget` returning `Scaffold` + `SafeArea`, a header `Row` with a back `IconButton` (tooltip `'Back'`) wired to `onBack`, and a body of section chips that **filter** the visible section (no lazy scroll-jump). All data comes from `CodexData`; stat visibility follows spec §8.1 exactly.

```dart
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../codex/codex_data.dart';
import '../models/game_models.dart';
import '../util/format.dart';
import 'tower_icons.dart';

class CodexView extends StatefulWidget {
  const CodexView({super.key, required this.progress, required this.onBack});

  final CampaignProgress progress;
  final VoidCallback onBack;

  @override
  State<CodexView> createState() => _CodexViewState();
}

class _CodexViewState extends State<CodexView> {
  int _section = 0;
  static const _sections = ['Towers', 'Enemies', 'Effects', 'Stages'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Text('Codex', style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    ChoiceChip(
                      label: Text(_sections[i]),
                      selected: _section == i,
                      onSelected: (_) => setState(() => _section = i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    return switch (_section) {
      0 => ListView(children: [for (final t in CodexData.towers) _towerCard(theme, t)]),
      1 => ListView(
          children: [
            for (final tr in CodexData.traits) _line(theme, tr.label, tr.effect),
            const Divider(),
            for (final e in CodexData.enemies) _enemyCard(theme, e),
          ],
        ),
      2 => ListView(
          children: [
            for (final ef in CodexData.effects)
              Card(
                child: ListTile(
                  title: Text(ef.title),
                  subtitle: Text(ef.description),
                ),
              ),
          ],
        ),
      _ => ListView(
          children: [for (final s in CodexData.stagesFor(widget.progress)) _stageCard(theme, s)],
        ),
    };
  }

  Widget _towerCard(ThemeData theme, CodexTowerEntry t) {
    final lines = <(String, String)>[
      ('Range', number(t.baseStats.range)),
      ('Cost', '${t.baseStats.cost}'),
      ('Upgrade cost', '${t.upgradeCost}'),
      // Damage / Fire interval only when meaningful (drone bay has damage 0).
      if (t.baseStats.damage > 0) ...[
        ('Damage', number(t.baseStats.damage)),
        ('Fire interval', '${number(t.baseStats.fireInterval)}s'),
      ],
      ..._specialtyLines(t.baseStats),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(towerIcon(t.type)),
              const SizedBox(width: 8),
              Text(t.label, style: theme.textTheme.titleMedium),
              const Spacer(),
              Text('Available from wave ${t.unlockWave}',
                  style: theme.textTheme.labelSmall),
            ]),
            const SizedBox(height: 8),
            for (final (k, v) in lines)
              _line(theme, k, v),
            const SizedBox(height: 8),
            for (final spec in t.specializations) ...[
              Text('${spec.label} (${t.specializationCost}g)',
                  style: theme.textTheme.titleSmall),
              Text(spec.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  // Specialty rows render only when non-default (spec §8.1).
  List<(String, String)> _specialtyLines(TowerStats s) {
    final out = <(String, String)>[];
    if (s.splashRadius > 0) out.add(('Splash radius', number(s.splashRadius)));
    if (s.slowMultiplier < 1) {
      out.add(('Slow', '${percent(1 - s.slowMultiplier)} for ${number(s.slowDuration)}s'));
    }
    if (s.pierceCount > 0) out.add(('Pierce', '${s.pierceCount}'));
    if (s.chainCount > 0) {
      out.add(('Chain', '${s.chainCount} (range ${number(s.chainRange)})'));
    }
    if (s.corrosionDamagePerSecond > 0) {
      out.add(('Corrosion', '${number(s.corrosionDamagePerSecond)}/s for ${number(s.corrosionDuration)}s'));
    }
    if (s.armorShred > 0) out.add(('Armor shred', percent(s.armorShred)));
    if (s.fieldRadius > 0) {
      out.add((
        'Field',
        'r ${number(s.fieldRadius)}, ${number(s.fieldDuration)}s, tick ${number(s.fieldTickInterval)}s',
      ));
    }
    if (s.droneCount > 0) {
      out.add((
        'Drones',
        '${s.droneCount} (cap ${s.maxActiveDrones}), ${number(s.droneDamage)} dmg / ${number(s.droneAttackInterval)}s, ${number(s.droneLifetime)}s life',
      ));
    }
    if (s.shieldDamageMultiplier != 1) {
      out.add(('vs Shield', 'x${number(s.shieldDamageMultiplier)}'));
    }
    if (s.armorDamageMultiplier != 1) {
      out.add(('vs Armored', 'x${number(s.armorDamageMultiplier)}'));
    }
    if (s.slowedDamageMultiplier != 1) {
      out.add(('vs Slowed', 'x${number(s.slowedDamageMultiplier)}'));
    }
    return out;
  }

  Widget _enemyCard(ThemeData theme, CodexEnemyEntry e) {
    final lines = <(String, String)>[
      ('Health', number(e.stats.health)),
      ('Speed', number(e.stats.speed)),
      ('Base damage', '${e.stats.baseDamage}'),
      ('Reward', '${e.stats.goldReward}g'),
      if (e.stats.shieldHealth > 0) ('Shield', number(e.stats.shieldHealth)),
      if (e.stats.armorReduction > 0) ('Armor', percent(e.stats.armorReduction)),
      if (e.stats.regenPerSecond > 0) ('Regen', '${number(e.stats.regenPerSecond)}/s'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.label, style: theme.textTheme.titleMedium),
            if (e.traits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  children: [for (final tr in e.traits) _badge(theme, tr.label)],
                ),
              ),
            const SizedBox(height: 4),
            Text(e.roleDescription, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            for (final (k, v) in lines) _line(theme, k, v),
          ],
        ),
      ),
    );
  }

  Widget _stageCard(ThemeData theme, CodexStageEntry s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('${s.stage.name} (${s.stage.mapLabel})',
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              _badge(theme, _statusLabel(s.status)),
            ]),
            const SizedBox(height: 4),
            Text('${s.stage.isMainPath ? "Main" : "Side"} • ${s.waveCount} waves',
                style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(s.stage.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            for (final m in s.modifiers)
              _line(theme, m.title, m.description),
            if (s.rewardLabel != null) _line(theme, 'Reward', s.rewardLabel!),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(StageProgressStatus s) => switch (s) {
        StageProgressStatus.cleared => 'Cleared',
        StageProgressStatus.unlocked => 'Open',
        StageProgressStatus.locked => 'Locked',
      };

  Widget _line(ThemeData theme, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(key, style: theme.textTheme.bodyMedium),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }
}
```

(The `_line` helper uses a fixed 120px label column; the wrapping `Row` + `Expanded` value column already collapses gracefully on narrow widths. If a 360px layout needs the label above the value, wrap `_line`'s body in a `LayoutBuilder` keyed on `< 420` — but the simple form passes the narrow-surface widget test.)

- [ ] **Step 4: Run the widget test to verify it passes**

Run: `flutter test test/widget/codex_view_test.dart`
Expected: PASS — chips render, default Towers section shows the Laser label, Enemies shows the basic drone, back button fires `onBack`.

- [ ] **Step 5: Analyze + format + commit**

Run: `flutter analyze && dart format .`
Then:
```bash
git add lib/game/ui/codex_view.dart test/widget/codex_view_test.dart
git commit -m "feat: add CodexView widget (HPA-103)"
```

---

## Task 7: Wire the entry point on the campaign map

Expose the Codex button on the world map and add the `_ShellView.codex` in-place view to `OrionGamePage`, mirroring the Tech Tree wiring exactly.

**Files:**
- Modify: `lib/game/ui/world_map_view.dart` — add `VoidCallback? onOpenCodex` + an `IconButton` (null-guarded) in the header `Row`.
- Modify: `lib/game/ui/orion_game_page.dart` — add `_ShellView.codex`, `_openCodex()` / `_closeCodex()`, a `case _ShellView.codex:` in the build switch, and `onOpenCodex: _openCodex` in `_buildWorldMapScaffold`.
- Test: extend `test/widget/codex_view_test.dart` or add a smoke test that boots `OrionGamePage` and asserts the Codex button is present; run full suite.

**Interfaces:**
- Consumes: `CodexView` (Task 6), the existing `_ShellView` enum + `_activeView` field in `_OrionGamePageState`.

- [ ] **Step 1: Add `onOpenCodex` to WorldMapView**

In `lib/game/ui/world_map_view.dart`:
- Add a field `final VoidCallback? onOpenCodex;` next to `onOpenTechTree`, and add it to the constructor.
- In the header `Row` (where `onOpenTechTree` is rendered inside `if (onOpenTechTree != null)`), add a matching Codex button **before** the Tech Tree button:
  ```dart
  if (onOpenCodex != null)
    IconButton(
      tooltip: 'Codex',
      onPressed: _isBusy ? null : onOpenCodex,
      icon: const Icon(Icons.menu_book),
    ),
  ```

- [ ] **Step 2: Add the `_ShellView.codex` view to OrionGamePage**

In `lib/game/ui/orion_game_page.dart`:
- Add `codex` to the `_ShellView` enum (alongside `worldMap`, `techTree`, `stage`).
- Add two methods mirroring `_openTechTree` / `_closeTechTree`:
  ```dart
  void _openCodex() {
    setState(() {
      _activeView = _ShellView.codex;
    });
  }

  void _closeCodex() {
    setState(() {
      _activeView = _ShellView.worldMap;
    });
  }
  ```
- Add a case to the `switch (_activeView)` in `build` (next to the `techTree` case):
  ```dart
  case _ShellView.codex:
    return CodexView(progress: _progress, onBack: _closeCodex);
  ```
- Wire the callback into the `WorldMapView` constructed inside `_buildWorldMapScaffold()`, beside `onOpenTechTree: _openTechTree`:
  ```dart
  onOpenCodex: _openCodex,
  ```
- Add `import 'codex_view.dart';` at the top.

- [ ] **Step 3: Write a smoke test for the entry point**

Add to `test/widget/codex_view_test.dart` (or a new `test/widget/codex_entry_test.dart`) a test that pumps `WorldMapView` with `onOpenCodex` set and asserts the Codex `IconButton` (tooltip `'Codex'`) is found, and that invoking it calls the callback:

```dart
testWidgets('world map shows a Codex button that fires onOpenCodex',
    (tester) async {
  var pressed = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorldMapView(
          stages: OrionCampaign.stages,
          progress: CampaignProgress(),
          feedback: null,
          onStageSelected: (_) {},
          onResetCampaign: () {},
          onOpenTechTree: () {},
          onOpenCodex: () => pressed = true,
        ),
      ),
    ),
  );
  await tester.tap(find.byTooltip('Codex'));
  expect(pressed, isTrue);
});
```

(Add the needed imports: `package:orion/game/ui/world_map_view.dart`, `package:orion/game/campaign/orion_campaign.dart`.)

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS — including the new entry-point test and every prior test.

- [ ] **Step 5: Analyze + format + commit**

Run: `flutter analyze && dart format .`
Then:
```bash
git add lib/game/ui/world_map_view.dart lib/game/ui/orion_game_page.dart test/widget/codex_view_test.dart
git commit -m "feat: wire codex entry point on the campaign map (HPA-103)"
```

---

## Self-Review

**Spec coverage** (spec section → task):
- §5 architecture / file layout → Tasks 1–7 (each file maps to a task).
- §6 data model (value types, `CodexData`, formatters, `stageRewardLabel`) → Tasks 1, 3, 5.
- §7 label extraction (`TowerType`/`EnemyTrait`/`EnemyArchetype.label`, `towerIcon`, dedupe) → Tasks 2, 4.
- §8.1 towers content (drone damage, field tick, slow gating, damage>0 rule, specializationCost hoist, L2 omission) → Task 5 data + Task 6 rendering rules.
- §8.2 enemies + trait reference → Task 5 (`enemies`, `traits`).
- §8.3 effects glossary + `relatedSpecializations` derivation → Task 5 (`effects`, `_specsWhere`).
- §8.4 stages (standard-conditions fallback, status, reward label) → Task 5 (`stagesFor`).
- §8.5 catalog-only stat semantics → Task 5 (reads `GameBalance` directly, no resolver).
- §9.1 entry point + null guard → Task 7.
- §9.2 CodexView (Scaffold/SafeArea, chip filter not lazy-jump, onBack, no feedback slot, empty-progress default) → Task 6 (+ entry default verified Task 5 test).
- §10 testing → Tasks 1–7 each carry their tests; §10.1 headline coverage is Task 5.

**Placeholder scan:** every implementation step carries concrete code and every authored string (16 specialization blurbs, 9 enemy roles, 9 effect entries, 5 trait effects) is written out and grounded in the verified tuning. The only presentational latitude is the exact `LayoutBuilder` form in `codex_view.dart`'s `_line`, and even that is given a working default plus the narrow-width fallback.

**Type consistency:** `stageRewardLabel(stage, {required bool isCleared})` matches across §5.1/§6.3/Task 3. `specializationCost` is on `CodexTowerEntry` (hoisted) and removed from `CodexSpecializationEntry` — consistent in Task 5's class defs and test. `relatedSpecializations` uses the `_specsWhere` derivation consistently.

**Gaps:** none — every spec section maps to a task.
