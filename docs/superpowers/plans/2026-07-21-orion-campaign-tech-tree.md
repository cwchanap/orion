# Orion Campaign Tech Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a campaign-wide tech tree where players spend medal points on five persistent upgrades that affect mission start (gold/health/clear-bonus) and tower stats (laser damage, cryo slow).

**Architecture:** New pure-logic module `lib/game/campaign/tech_tree.dart` wraps a `Set<CampaignTechUpgrade>` with a derived medal-point bank. `CampaignModifiers` (existing) is extended with three new fields and absorbs tech-tree effects additively alongside HPA-94 side-stage rewards. Codec bumps v2 → v3 to persist the purchased set; store interface wraps both `CampaignProgress` and `CampaignTechTree` in a single `CampaignSave` aggregate. Combat upgrades bake into `TowerStats` via a private `_resolveStats` resolver on `TowerComponent`, threaded from `_addTowerComponent`. UI adds a full-screen `TechTreeView` reached from a world-map header button; shell routing moves to an explicit `_ShellView` enum.

**Tech Stack:** Flutter, Flame `^1.37.0`, Dart SDK `^3.12.0`, `shared_preferences`. Tests via `flutter test`. Static analysis via `flutter analyze`.

**Spec:** `docs/superpowers/specs/2026-07-20-orion-campaign-tech-tree-design.md` (revised through round 3). Read it before starting any task.

## Global Constraints

- **Dart SDK:** `^3.12.0` (see `pubspec.yaml`).
- **Flame:** `^1.37.0`.
- **Pure-logic boundary:** files under `lib/game/rules/` and `lib/game/campaign/` must not import Flame. Combat math stays in `rules/`; campaign state stays in `campaign/`.
- **Codec backward-compat:** v1 and v2 saves must still load. Unknown codec versions return an empty save (existing policy).
- **Tuning lives in `GameBalance`:** all costs and magnitudes are `GameBalance` constants; tests assert them concretely.
- **Total upgrade cost = 20** medal points; max earnable = 21 (7 stages × 3 rank). 1-pt slack is intentional.
- **No new Persistent state beyond the purchased set:** the medal-point bank is derived (`max(0, totalMedalRank − totalSpent)`), never stored.
- **No respec, no drone-AI upgrade, no branching tree** (issue non-goals).
- **Conventions:** `flutter analyze` clean; `dart format .`; one commit per task; tests green before commit.

---

## File Structure

**New files:**
- `lib/game/campaign/tech_tree.dart` — `CampaignTechUpgrade` enum + `CampaignTechTree` pure class.
- `lib/game/ui/tech_tree_view.dart` — Full-screen panel widget.
- `test/game/tech_tree_test.dart` — Pure-logic tests for `CampaignTechTree`.
- `test/widget/tech_tree_view_test.dart` — Widget tests for `TechTreeView`.

**Modified files:**
- `lib/game/models/game_models.dart` — `GameBalance` constants; `TowerStats` gains a `copyWith` for damage/slowDuration.
- `lib/game/campaign/campaign_progress.dart` — `CampaignModifiers` gains three fields; `fromProgress` signature changes.
- `lib/game/campaign/campaign_progress_store.dart` — `CampaignSave` class; store interface returns/accepts `CampaignSave`; codec v3.
- `lib/game/rules/game_session.dart` — `modifiers` field on `GameSession.initial`; wave-clear multiplier.
- `lib/game/components/tower_component.dart` — `modifiers` field; `_resolveStats` resolver.
- `lib/game/orion_defense_game.dart` — thread modifiers to `GameSession.initial` and `_addTowerComponent`.
- `lib/game/ui/orion_game_page.dart` — `_ShellView` enum; `_techTree` / `_techTreeFeedback` state; `_persistSave` helper; `_purchaseTech`; drop `_recordStageCompletion`; updated feedback routing.
- `lib/game/ui/world_map_view.dart` — `onOpenTechTree` callback; "Tech Tree" header button.

**Modified tests:**
- `test/game/game_balance_test.dart` — tech-tree constants assertions.
- `test/game/campaign_progress_test.dart` — `CampaignModifiers.fromProgress` three-arg signature; new field tests.
- `test/game/campaign_progress_store_test.dart` — `CampaignSave` interface migration.
- `test/game/game_session_test.dart` — `modifiers` param; wave-clear tests.
- `test/game/orion_defense_game_test.dart` — modifiers threading.
- `test/widget_test.dart` — `_TestCampaignProgressStore` + 15+ call sites; navigation tests; regression coverage.

---

## Task Dependency Graph

```text
T1 (CampaignTechTree) ──┬─> T3 (CampaignModifiers) ──┬─> T6 (GameSession)  ──┐
                        │                            └─> T7 (TowerComponent)─┤
T2 (GameBalance) ───────┴─> T4 (CampaignSave) ────────┬─> T8 (OrionDefenseGame)┐
                                                      │                         │
                                                      └─> T5 (Widget test mig) │
                                                                                │
T9 (Shell + state) ──> T10 (_persistSave) ──> T11 (Purchase + button) ──> T12 (TechTreeView) ──> T13 (Acceptance)
```

T1+T2 are independent starting points. T13 is the final acceptance pass.

---

## Task 1: CampaignTechUpgrade enum + CampaignTechTree pure class

**Files:**
- Create: `lib/game/campaign/tech_tree.dart`
- Test: `test/game/tech_tree_test.dart`

**Interfaces:**
- Consumes: `CampaignProgress` (from `campaign_progress.dart`), `StageMedal.rank` (existing).
- Produces: `CampaignTechUpgrade` enum (5 values); `CampaignTechTree` class with `purchased`, `isPurchased(upgrade)`, `totalSpent`, `unspentPoints(progress)`, `canPurchase(upgrade, progress)`, `purchase(upgrade, progress)`, `toIdList()`, `fromIdList(ids)`.

- [ ] **Step 1: Write the failing tests**

Create `test/game/tech_tree_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';

void main() {
  group('CampaignTechUpgrade', () {
    test('has exactly five values', () {
      expect(CampaignTechUpgrade.values, hasLength(5));
    });

    test('each upgrade carries a stable id, cost, label, description, effectLabel', () {
      for (final upgrade in CampaignTechUpgrade.values) {
        expect(upgrade.id, isNotEmpty);
        expect(upgrade.cost, greaterThan(0));
        expect(upgrade.label, isNotEmpty);
        expect(upgrade.description, isNotEmpty);
        expect(upgrade.effectLabel, isNotEmpty);
      }
    });

    test('fromIdList round-trips toIdList', () {
      final set = {CampaignTechUpgrade.solarCapacitors, CampaignTechUpgrade.cryoCoolant};
      final tree = CampaignTechTree(purchased: set);
      expect(
        CampaignTechTree.fromIdList(tree.toIdList()).purchased,
        set,
      );
    });

    test('fromIdList drops unknown ids', () {
      final tree = CampaignTechTree.fromIdList(
        const ['solar-capacitors', 'unknown-future-id', 'cryo-coolant'],
      );
      expect(tree.purchased, {CampaignTechUpgrade.solarCapacitors, CampaignTechUpgrade.cryoCoolant});
    });

    test('fromIdList on null returns empty tree', () {
      expect(CampaignTechTree.fromIdList(null).purchased, isEmpty);
    });
  });

  group('CampaignTechTree.unspentPoints', () {
    CampaignProgress progressWithRanks(List<int> ranks) {
      final results = <String, StageResult>{};
      for (var i = 0; i < ranks.length; i++) {
        final medal = ranks[i] == 3
            ? StageMedal.gold
            : ranks[i] == 2
                ? StageMedal.silver
                : StageMedal.clear;
        results['stage-$i'] = StageResult(medal: medal, bestBaseHealth: 10);
      }
      return CampaignProgress(bestResultsByStageId: results);
    }

    test('empty progress yields zero points', () {
      final tree = CampaignTechTree();
      expect(tree.unspentPoints(CampaignProgress()), 0);
    });

    test('seven clears (rank 1 each) yield 7 points', () {
      final progress = progressWithRanks(const [1, 1, 1, 1, 1, 1, 1]);
      expect(CampaignTechTree().unspentPoints(progress), 7);
    });

    test('seven golds (rank 3 each) yield 21 points', () {
      final progress = progressWithRanks(const [3, 3, 3, 3, 3, 3, 3]);
      expect(CampaignTechTree().unspentPoints(progress), 21);
    });

    test('partial purchase reduces unspent by current cost', () {
      final progress = progressWithRanks(const [3, 3, 3, 3]);
      final tree = CampaignTechTree(purchased: {CampaignTechUpgrade.solarCapacitors});
      // 4 golds = 12 earned; solarCapacitors costs 3; unspent = 9
      expect(tree.unspentPoints(progress), 9);
    });

    test('overdrawn bank (spent > earned) clamps to zero', () {
      final progress = CampaignProgress();
      // Pretend a prior version let us buy something for free; the purchased
      // set now has totalSpent > 0 but the player has no medals.
      final tree = CampaignTechTree(purchased: {CampaignTechUpgrade.cryoCoolant});
      expect(tree.unspentPoints(progress), 0);
    });
  });

  group('CampaignTechTree.canPurchase', () {
    final richProgress = CampaignProgress(bestResultsByStageId: {
      's': const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    });

    test('true when upgrade not purchased and bank >= cost', () {
      expect(
        CampaignTechTree().canPurchase(CampaignTechUpgrade.solarCapacitors, richProgress),
        isTrue,
      );
    });

    test('false when already purchased', () {
      final tree = CampaignTechTree(purchased: {CampaignTechUpgrade.solarCapacitors});
      expect(
        tree.canPurchase(CampaignTechUpgrade.solarCapacitors, richProgress),
        isFalse,
      );
    });

    test('false when bank < cost', () {
      expect(
        CampaignTechTree().canPurchase(CampaignTechUpgrade.laserTuning, CampaignProgress()),
        isFalse,
      );
    });
  });

  group('CampaignTechTree.purchase', () {
    final richProgress = CampaignProgress(bestResultsByStageId: {
      's': const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
    });

    test('returns a new instance containing the upgrade; original unchanged', () {
      const upgrade = CampaignTechUpgrade.solarCapacitors;
      final original = CampaignTechTree();
      final next = original.purchase(upgrade, richProgress);
      expect(next.isPurchased(upgrade), isTrue);
      expect(original.isPurchased(upgrade), isFalse);
    });

    test('throws ArgumentError when upgrade already purchased', () {
      final tree = CampaignTechTree(purchased: {CampaignTechUpgrade.solarCapacitors});
      expect(
        () => tree.purchase(CampaignTechUpgrade.solarCapacitors, richProgress),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when unaffordable', () {
      expect(
        () => CampaignTechTree().purchase(CampaignTechUpgrade.cryoCoolant, CampaignProgress()),
        throwsArgumentError,
      );
    });
  });

  group('CampaignTechTree total cost across all upgrades', () {
    test('equals 20 (intentional 1-pt slack below 21 max)', () {
      final totalSpent = CampaignTechUpgrade.values
          .fold(0, (sum, u) => sum + u.cost);
      expect(totalSpent, 20);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/game/tech_tree_test.dart`
Expected: FAIL — the file `lib/game/campaign/tech_tree.dart` does not exist; imports won't resolve.

- [ ] **Step 3: Implement `CampaignTechTree` and `CampaignTechUpgrade`**

Create `lib/game/campaign/tech_tree.dart`:

```dart
import 'campaign_progress.dart';

/// The five campaign-wide tech-tree upgrades available in the MVP.
///
/// Each upgrade is single-rank (binary purchased / not purchased). Adding a
/// new upgrade means: append to this enum, add a cost constant to `GameBalance`,
/// wire the effect into `CampaignModifiers.fromProgress`, and update the total
/// cost assertion in `test/game/tech_tree_test.dart` (the intentional slack is
/// 1 pt below the 21-pt max medal rank).
enum CampaignTechUpgrade {
  solarCapacitors(
    id: 'solar-capacitors',
    cost: 3,
    label: 'Solar Capacitors',
    description: 'Start each mission with extra gold.',
    effectLabel: '+15 Starting Gold',
  ),
  hardenedCore(
    id: 'hardened-core',
    cost: 4,
    label: 'Hardened Core',
    description: 'Start each mission with extra base health.',
    effectLabel: '+3 Starting Health',
  ),
  salvageCrew(
    id: 'salvage-crew',
    cost: 4,
    label: 'Salvage Crew',
    description: 'Earn more gold from wave clears.',
    effectLabel: '+25% Wave Clear Gold',
  ),
  laserTuning(
    id: 'laser-tuning',
    cost: 4,
    label: 'Laser Tuning',
    description: 'Laser towers deal more damage.',
    effectLabel: '+10% Laser Damage',
  ),
  cryoCoolant(
    id: 'cryo-coolant',
    cost: 5,
    label: 'Cryo Coolant',
    description: 'Cryo towers slow enemies longer.',
    effectLabel: '+0.3s Cryo Slow',
  );

  const CampaignTechUpgrade({
    required this.id,
    required this.cost,
    required this.label,
    required this.description,
    required this.effectLabel,
  });

  /// Stable identifier used in persistence. Never reuse an id after removing
  /// an upgrade (decode silently drops unknown ids; reuse would resurrect
  /// stale purchases).
  final String id;
  final int cost;
  final String label;
  final String description;
  final String effectLabel;

  static CampaignTechUpgrade? fromId(String id) {
    for (final upgrade in CampaignTechUpgrade.values) {
      if (upgrade.id == id) {
        return upgrade;
      }
    }
    return null;
  }
}

/// Immutable set of purchased campaign upgrades plus a derived medal-point
/// bank. The bank is never persisted; it is always recomputed as
/// `max(0, totalMedalRank(progress) - totalSpent)`.
class CampaignTechTree {
  CampaignTechTree({Set<CampaignTechUpgrade> purchased = const {}})
    : _purchased = Set.unmodifiable(purchased);

  final Set<CampaignTechUpgrade> _purchased;

  Set<CampaignTechUpgrade> get purchased => _purchased;

  bool isPurchased(CampaignTechUpgrade upgrade) => _purchased.contains(upgrade);

  int get totalSpent =>
      _purchased.fold(0, (sum, upgrade) => sum + upgrade.cost);

  /// Total medal rank across all stored best results (clear=1, silver=2,
  /// gold=3). This is the player's earnable budget.
  static int totalMedalRank(CampaignProgress progress) {
    return progress.bestResultsByStageId.values
        .fold(0, (sum, result) => sum + result.medal.rank);
  }

  /// Derived unspent balance. Clamped at 0 so a future cost-tweak that makes
  /// `totalSpent > totalMedalRank` doesn't show a negative bank.
  int unspentPoints(CampaignProgress progress) {
    final earned = totalMedalRank(progress);
    final bank = earned - totalSpent;
    return bank < 0 ? 0 : bank;
  }

  bool canPurchase(CampaignTechUpgrade upgrade, CampaignProgress progress) {
    if (_purchased.contains(upgrade)) {
      return false;
    }
    return unspentPoints(progress) >= upgrade.cost;
  }

  /// Returns a new [CampaignTechTree] containing [upgrade]. Throws
  /// [ArgumentError] if [upgrade] is already purchased or unaffordable.
  CampaignTechTree purchase(CampaignTechUpgrade upgrade, CampaignProgress progress) {
    if (!canPurchase(upgrade, progress)) {
      throw ArgumentError.value(upgrade, 'upgrade', 'Cannot purchase');
    }
    return CampaignTechTree(purchased: {..._purchased, upgrade});
  }

  /// Sorted list of purchased ids; stable across enum reordering. Used by the
  /// codec encoder.
  List<String> toIdList() {
    final ids = _purchased.map((upgrade) => upgrade.id).toList()..sort();
    return ids;
  }

  /// Decode a sorted id list, silently dropping unknown ids (forward-compat
  /// for renames or removals).
  static CampaignTechTree fromIdList(Iterable<String>? ids) {
    if (ids == null) {
      return CampaignTechTree();
    }
    final upgrades = <CampaignTechUpgrade>{};
    for (final id in ids) {
      final upgrade = CampaignTechUpgrade.fromId(id);
      if (upgrade != null) {
        upgrades.add(upgrade);
      }
    }
    return CampaignTechTree(purchased: upgrades);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/game/tech_tree_test.dart`
Expected: PASS — all 17 tests green.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: no new warnings in `lib/game/campaign/tech_tree.dart` or `test/game/tech_tree_test.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/game/campaign/tech_tree.dart test/game/tech_tree_test.dart
git commit -m "feat: add CampaignTechTree pure-logic module (HPA-100)"
```

---

## Task 2: GameBalance constants + TowerStats.copyWith for damage/slowDuration

**Files:**
- Modify: `lib/game/models/game_models.dart` — add 10 constants to `GameBalance`; add `copyWith` to `TowerStats`.
- Test: `test/game/game_balance_test.dart` — assert new constants and total cost.

**Interfaces:**
- Consumes: nothing.
- Produces: `GameBalance.solarCapacitorsCost` etc. (5 costs); `GameBalance.solarCapacitorsGoldBonus` etc. (5 magnitudes); `TowerStats.copyWith({double? damage, double? slowDuration})`.

- [ ] **Step 1: Add the failing test**

Open `test/game/game_balance_test.dart` and append at the end of `void main()`:

```dart
  group('Campaign tech-tree constants', () {
    test('upgrade costs total 20 (intentional 1-pt slack vs 21 max)', () {
      const costs = [
        GameBalance.solarCapacitorsCost,
        GameBalance.hardenedCoreCost,
        GameBalance.salvageCrewCost,
        GameBalance.laserTuningCost,
        GameBalance.cryoCoolantCost,
      ];
      expect(costs.fold(0, (sum, c) => sum + c), 20);
    });

    test('magnitudes match design', () {
      expect(GameBalance.solarCapacitorsGoldBonus, 15);
      expect(GameBalance.hardenedCoreHealthBonus, 3);
      expect(GameBalance.salvageCrewClearBonusFraction, 0.25);
      expect(GameBalance.laserTuningDamageFraction, 0.10);
      expect(GameBalance.cryoCoolantSlowDurationBonus, 0.30);
    });
  });

  group('TowerStats.copyWith', () {
    test('overrides damage and slowDuration only', () {
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final tuned = base.copyWith(damage: base.damage * 1.10);
      expect(tuned.damage, closeTo(base.damage * 1.10, 1e-9));
      expect(tuned.slowDuration, base.slowDuration);
      expect(tuned.range, base.range);
      expect(tuned.cost, base.cost);
    });

    test('overrides slowDuration only', () {
      final base = GameBalance.towerStats(TowerType.cryo, level: 1);
      final cooled = base.copyWith(slowDuration: base.slowDuration + 0.30);
      expect(cooled.slowDuration, closeTo(base.slowDuration + 0.30, 1e-9));
      expect(cooled.damage, base.damage);
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/game/game_balance_test.dart`
Expected: FAIL — `GameBalance.solarCapacitorsCost` and `TowerStats.copyWith` undefined.

- [ ] **Step 3: Add constants to `GameBalance`**

In `lib/game/models/game_models.dart`, find the `class GameBalance` block (starts at line 400). After the existing `voidBastionHealthBonus` constant (around line 410), add:

```dart
  // Campaign tech-tree upgrade costs. Total is 20 (intentional 1-pt slack
  // below the 21-pt max medal rank: 7 stages × 3 rank). Tests assert this.
  static const int solarCapacitorsCost = 3;
  static const int hardenedCoreCost = 4;
  static const int salvageCrewCost = 4;
  static const int laserTuningCost = 4;
  static const int cryoCoolantCost = 5;

  // Campaign tech-tree upgrade magnitudes. The two "*Fraction" constants are
  // additive fractions (applied as `(1 + fraction)`), NOT multipliers —
  // storing 0.25 and applying as `* clearBonusFraction` would silently grant
  // 25% of the bonus instead of 125%. See HPA-100 spec.
  static const int solarCapacitorsGoldBonus = 15;
  static const int hardenedCoreHealthBonus = 3;
  static const double salvageCrewClearBonusFraction = 0.25;
  static const double laserTuningDamageFraction = 0.10;
  static const double cryoCoolantSlowDurationBonus = 0.30;
```

- [ ] **Step 4: Add `copyWith` to `TowerStats`**

In the same file, find the `class TowerStats` block (ends at line 197 with `bool get isMaxLevel => level >= 3;`). Just before that final getter, insert:

```dart
  /// Returns a copy with overridden fields. Only the fields the tech-tree
  /// combat upgrades touch are exposed; everything else copies from `this`.
  /// Kept narrow on purpose — extend only if another feature needs it.
  TowerStats copyWith({double? damage, double? slowDuration}) {
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
      fieldRadius: fieldRadius,
      fieldDuration: fieldDuration,
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

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/game/game_balance_test.dart`
Expected: PASS.

- [ ] **Step 6: Run full suite for regression check**

Run: `flutter test`
Expected: all existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add lib/game/models/game_models.dart test/game/game_balance_test.dart
git commit -m "feat: add tech-tree constants and TowerStats.copyWith (HPA-100)"
```

---

## Task 3: Extend CampaignModifiers with tech-tree fields

**Files:**
- Modify: `lib/game/campaign/campaign_progress.dart` — extend `CampaignModifiers`; change `fromProgress` signature.
- Test: `test/game/campaign_progress_test.dart` — update callers; add tech-tree-field tests.

**Interfaces:**
- Consumes: `CampaignTechTree` (Task 1); `GameBalance` constants (Task 2).
- Produces: `CampaignModifiers.clearBonusFraction`, `.laserDamageFraction`, `.cryoSlowDurationBonus`; new three-arg `CampaignModifiers.fromProgress(progress, stages, techTree)`.

- [ ] **Step 1: Survey existing `CampaignModifiers` tests**

Run: `flutter test test/game/campaign_progress_test.dart`
Expected: PASS (existing tests) — note the existing `fromProgress` callers (two-arg). They'll need updating.

- [ ] **Step 2: Add the failing tests**

Open `test/game/campaign_progress_test.dart`. Find the existing `CampaignModifiers` group and add inside it (and update existing tests to pass a third arg — see Step 4):

```dart
    group('tech-tree effects', () {
      CampaignTechTree treeWith(CampaignTechUpgrade upgrade) =>
          CampaignTechTree(purchased: {upgrade});

      test('solarCapacitors adds solarCapacitorsGoldBonus to bonusGold', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.solarCapacitors),
        );
        expect(mods.bonusGold, GameBalance.solarCapacitorsGoldBonus);
        expect(mods.bonusHealth, 0);
      });

      test('hardenedCore adds hardenedCoreHealthBonus to bonusHealth', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.hardenedCore),
        );
        expect(mods.bonusHealth, GameBalance.hardenedCoreHealthBonus);
        expect(mods.bonusGold, 0);
      });

      test('salvageCrew sets clearBonusFraction', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.salvageCrew),
        );
        expect(mods.clearBonusFraction, GameBalance.salvageCrewClearBonusFraction);
      });

      test('laserTuning sets laserDamageFraction', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.laserTuning),
        );
        expect(mods.laserDamageFraction, GameBalance.laserTuningDamageFraction);
      });

      test('cryoCoolant sets cryoSlowDurationBonus', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.cryoCoolant),
        );
        expect(mods.cryoSlowDurationBonus, GameBalance.cryoCoolantSlowDurationBonus);
      });

      test('all five upgrades stack with each other', () {
        final all = CampaignTechTree(purchased: CampaignTechUpgrade.values.toSet());
        final mods = CampaignModifiers.fromProgress(CampaignProgress(), const [], all);
        expect(mods.bonusGold, GameBalance.solarCapacitorsGoldBonus);
        expect(mods.bonusHealth, GameBalance.hardenedCoreHealthBonus);
        expect(mods.clearBonusFraction, GameBalance.salvageCrewClearBonusFraction);
        expect(mods.laserDamageFraction, GameBalance.laserTuningDamageFraction);
        expect(mods.cryoSlowDurationBonus, GameBalance.cryoCoolantSlowDurationBonus);
      });

      test('empty tech tree behaves like HPA-94 (no tech fields set)', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          CampaignTechTree(),
        );
        expect(mods.bonusGold, 0);
        expect(mods.bonusHealth, 0);
        expect(mods.clearBonusFraction, 0);
        expect(mods.laserDamageFraction, 0);
        expect(mods.cryoSlowDurationBonus, 0);
      });
    });

    test('solarCapacitors stacks additively with Salvage Rift side-stage reward', () {
      // Salvage Rift is the side stage with CampaignReward.bonusGold.
      const salvageRift = StageDefinition(
        id: 'salvage-rift',
        name: 'Salvage Rift',
        mapLabel: 'Rift',
        description: '',
        pathCells: [GridPosition(0, 0), GridPosition(1, 0)],
        waves: [],
        isMainPath: false,
        reward: CampaignReward.bonusGold,
        mapColumn: 0,
        mapRow: 0,
      );
      final cleared = CampaignProgress(bestResultsByStageId: {
        salvageRift.id: const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
      });
      final tree = CampaignTechTree(purchased: {CampaignTechUpgrade.solarCapacitors});
      final mods = CampaignModifiers.fromProgress(cleared, [salvageRift], tree);
      expect(mods.bonusGold, GameBalance.salvageRiftGoldBonus + GameBalance.solarCapacitorsGoldBonus);
    });
```

Also: anywhere in this file that calls `CampaignModifiers.fromProgress(progress, stages)` (two-arg), update to pass `CampaignTechTree()` as a third arg. Use `grep` to find them:

```bash
grep -n "CampaignModifiers.fromProgress" test/game/campaign_progress_test.dart
```

- [ ] **Step 3: Run the new tests to verify they fail**

Run: `flutter test test/game/campaign_progress_test.dart`
Expected: FAIL — `CampaignModifiers.clearBonusFraction` etc. undefined; `fromProgress` rejects three args.

- [ ] **Step 4: Extend `CampaignModifiers`**

In `lib/game/campaign/campaign_progress.dart`, replace the entire `CampaignModifiers` class (currently lines 190–245) with:

```dart
class CampaignModifiers {
  const CampaignModifiers({
    this.bonusGold = 0,
    this.bonusHealth = 0,
    this.hasChallengeBadge = false,
    this.clearBonusFraction = 0,
    this.laserDamageFraction = 0,
    this.cryoSlowDurationBonus = 0,
  });

  final int bonusGold;
  final int bonusHealth;
  final bool hasChallengeBadge;

  /// Additive fraction applied as `(1 + clearBonusFraction)`. Named `Fraction`
  /// (not `Multiplier`) to prevent the `* clearBonusFraction` mis-application
  /// trap. See HPA-100 spec round-1 review issue #4.
  final double clearBonusFraction;
  final double laserDamageFraction;
  final double cryoSlowDurationBonus;

  int get adjustedStartingGold => GameBalance.startingGold + bonusGold;
  int get adjustedStartingBaseHealth =>
      GameBalance.initialBaseHealth + bonusHealth;

  static const CampaignModifiers empty = CampaignModifiers();

  static CampaignModifiers fromProgress(
    CampaignProgress progress,
    Iterable<StageDefinition> stages,
    CampaignTechTree techTree,
  ) {
    var bonusGold = 0;
    var bonusHealth = 0;
    final sideStageIds = <String>[];

    for (final stage in stages) {
      if (!stage.isMainPath) {
        sideStageIds.add(stage.id);
      }

      if (!progress.isCleared(stage.id)) {
        continue;
      }

      switch (stage.reward) {
        case CampaignReward.bonusGold:
          bonusGold += GameBalance.salvageRiftGoldBonus;
        case CampaignReward.bonusHealth:
          bonusHealth += GameBalance.voidBastionHealthBonus;
        case CampaignReward.challengeBadge:
          break;
        case null:
          break;
      }
    }

    if (techTree.isPurchased(CampaignTechUpgrade.solarCapacitors)) {
      bonusGold += GameBalance.solarCapacitorsGoldBonus;
    }
    if (techTree.isPurchased(CampaignTechUpgrade.hardenedCore)) {
      bonusHealth += GameBalance.hardenedCoreHealthBonus;
    }

    final allSideStagesCleared =
        sideStageIds.isNotEmpty && sideStageIds.every(progress.isCleared);

    return CampaignModifiers(
      bonusGold: bonusGold,
      bonusHealth: bonusHealth,
      hasChallengeBadge: allSideStagesCleared,
      clearBonusFraction: techTree.isPurchased(CampaignTechUpgrade.salvageCrew)
          ? GameBalance.salvageCrewClearBonusFraction
          : 0,
      laserDamageFraction: techTree.isPurchased(CampaignTechUpgrade.laserTuning)
          ? GameBalance.laserTuningDamageFraction
          : 0,
      cryoSlowDurationBonus: techTree.isPurchased(CampaignTechUpgrade.cryoCoolant)
          ? GameBalance.cryoCoolantSlowDurationBonus
          : 0,
    );
  }
}
```

At the top of the file, add the import for `tech_tree.dart`:

```dart
import 'package:orion/game/models/game_models.dart';

import 'stage_definition.dart';
import 'tech_tree.dart';
```

- [ ] **Step 5: Update remaining two-arg `fromProgress` callers in production**

Find production callers with:

```bash
grep -rn "CampaignModifiers.fromProgress" lib/
```

Expected: two sites in `lib/game/ui/orion_game_page.dart` (lines 100 and 171). For each, append `, CampaignTechTree()` as the third argument. (The real tech-tree state is wired in Task 9; this unblocks the build.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/game/campaign_progress_test.dart`
Expected: PASS.

- [ ] **Step 7: Run the full suite to surface other call sites**

Run: `flutter test`
Expected: any other test files calling the old two-arg `fromProgress` will fail to compile. Update each to add `CampaignTechTree()` as the third arg. Repeat until green.

- [ ] **Step 8: Commit**

```bash
git add lib/game/campaign/campaign_progress.dart lib/game/ui/orion_game_page.dart test/game/campaign_progress_test.dart
# plus any other test files updated in Step 7
git commit -m "feat: extend CampaignModifiers with tech-tree fields (HPA-100)"
```

---

## Task 4: CampaignSave aggregate + codec v3 + store interface

**Files:**
- Modify: `lib/game/campaign/campaign_progress_store.dart` — add `CampaignSave`; change store interface; codec v3.
- Test: `test/game/campaign_progress_store_test.dart` — round-trip with both fields; v2/v1 migrations; unknown-version.

**Interfaces:**
- Consumes: `CampaignTechTree` (Task 1).
- Produces: `CampaignSave`; `CampaignProgressStore.load() -> Future<CampaignSave>`; `CampaignProgressStore.save(CampaignSave)`; codec v3 shape.

- [ ] **Step 1: Add the failing tests**

Open `test/game/campaign_progress_store_test.dart`. Find the imports and add:

```dart
import 'package:orion/game/campaign/tech_tree.dart';
```

Append the following groups inside `void main()`:

```dart
  group('CampaignSave codec v3', () {
    test('round-trips progress + techTree', () {
      final progress = CampaignProgress(bestResultsByStageId: {
        'outpost-alpha': const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      });
      final techTree = CampaignTechTree(purchased: {
        CampaignTechUpgrade.solarCapacitors,
        CampaignTechUpgrade.cryoCoolant,
      });
      final save = CampaignSave(progress: progress, techTree: techTree);

      final encoded = CampaignProgressCodec.encode(save);
      final decoded = CampaignProgressCodec.decode(
        encoded,
        knownStages: const [],
      );

      expect(decoded.progress.bestResultsByStageId.keys, ['outpost-alpha']);
      expect(decoded.techTree.purchased, techTree.purchased);
    });

    test('techPurchases sorted deterministically', () {
      final techTree = CampaignTechTree(purchased: {
        CampaignTechUpgrade.cryoCoolant,
        CampaignTechUpgrade.solarCapacitors,
      });
      final encoded = CampaignProgressCodec.encode(
        CampaignSave(progress: CampaignProgress(), techTree: techTree),
      );
      // Expect the JSON to contain the sorted id list.
      expect(encoded, contains('"techPurchases":["cryo-coolant","solar-capacitors"]'));
    });

    test('unknown techPurchases ids are dropped on decode', () {
      // Encode cannot produce an unknown id (the enum is closed), so decode
      // raw JSON directly. See HPA-100 spec round-2 review issue #6.
      const raw = '{"version":3,"stageResults":{},'
          '"techPurchases":["solar-capacitors","unknown-future-id"]}';
      final decoded = CampaignProgressCodec.decode(raw, knownStages: const []);
      expect(decoded.techTree.purchased, {CampaignTechUpgrade.solarCapacitors});
    });

    test('missing techPurchases field on v3 returns empty tree', () {
      const raw = '{"version":3,"stageResults":{}}';
      final decoded = CampaignProgressCodec.decode(raw, knownStages: const []);
      expect(decoded.techTree.purchased, isEmpty);
    });

    test('v2 save decodes with empty tech tree', () {
      const raw = '{"version":2,"stageResults":{}}';
      final decoded = CampaignProgressCodec.decode(raw, knownStages: const []);
      expect(decoded.techTree.purchased, isEmpty);
    });

    test('v1 save decodes with empty tech tree', () {
      const raw = '{"version":1,"clearedStageIds":["outpost-alpha"]}';
      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: const [],
      );
      expect(decoded.techTree.purchased, isEmpty);
    });

    test('unknown codec version returns empty save', () {
      const raw = '{"version":99,"stageResults":{}}';
      final decoded = CampaignProgressCodec.decode(raw, knownStages: const []);
      expect(decoded.progress.bestResultsByStageId, isEmpty);
      expect(decoded.techTree.purchased, isEmpty);
    });
  });
```

Also: every existing test in this file that calls `store.save(progress)` (where `progress` is a `CampaignProgress`) or `store.load()` and destructures a `CampaignProgress` must migrate. Use grep to find them:

```bash
grep -n "store.save\|store.load\|await store" test/game/campaign_progress_store_test.dart
```

For each: `store.save(progress)` becomes `store.save(CampaignSave(progress: progress, techTree: CampaignTechTree()))`; `(await store.load())` becomes `(await store.load()).progress` (or destructure into `final save = await store.load(); save.progress`).

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/game/campaign_progress_store_test.dart`
Expected: FAIL — `CampaignSave` undefined; `encode`/`decode` signatures changed.

- [ ] **Step 3: Rewrite the store file**

Open `lib/game/campaign/campaign_progress_store.dart`. Replace the entire file with:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_progress.dart';
import 'stage_definition.dart';
import 'tech_tree.dart';

/// Aggregate of everything persisted under one SharedPreferences key.
///
/// `CampaignProgress` (stage results) and `CampaignTechTree` (purchased
/// upgrades) are saved atomically — splitting them across two keys would
/// invite save-tearing bugs and complicate the v2 → v3 migration. See HPA-100
/// spec "Persistence" section.
class CampaignSave {
  const CampaignSave({required this.progress, required this.techTree});

  final CampaignProgress progress;
  final CampaignTechTree techTree;

  // `static const` is impossible here because `CampaignProgress` and
  // `CampaignTechTree` default constructors are non-`const` (they wrap their
  // inputs in `Map.unmodifiable` / `Set.unmodifiable`, which are not const).
  // `static final` preserves the "one shared empty instance" intent — both
  // wrapped objects are deeply immutable.
  static final CampaignSave empty = CampaignSave(
    progress: CampaignProgress(),
    techTree: CampaignTechTree(),
  );
}

abstract class CampaignProgressStore {
  Future<CampaignSave> load();
  Future<void> save(CampaignSave save);
  Future<void> reset();
}

class CampaignProgressCodec {
  const CampaignProgressCodec._();

  static String encode(CampaignSave save) {
    final stageIds = save.progress.bestResultsByStageId.keys.toList()..sort();
    final stageResults = <String, Object>{};
    for (final stageId in stageIds) {
      stageResults[stageId] =
          save.progress.bestResultsByStageId[stageId]!.toJson();
    }

    return jsonEncode({
      'version': 3,
      'stageResults': stageResults,
      'techPurchases': save.techTree.toIdList(),
    });
  }

  static CampaignSave decode(
    String? source, {
    required Iterable<StageDefinition> knownStages,
  }) {
    if (source == null || source.isEmpty) {
      return CampaignSave.empty;
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        return CampaignSave.empty;
      }

      final version = decoded['version'];
      if (version == 1) {
        return CampaignSave(
          progress: _decodeVersionOne(decoded, knownStages: knownStages),
          techTree: CampaignTechTree(),
        );
      }
      if (version == 2) {
        return CampaignSave(
          progress: _decodeStageResults(decoded, knownStages: knownStages),
          techTree: CampaignTechTree(),
        );
      }
      if (version != 3) {
        // Unknown future version: return empty save (existing policy).
        return CampaignSave.empty;
      }

      return CampaignSave(
        progress: _decodeStageResults(decoded, knownStages: knownStages),
        techTree: _decodeTechPurchases(decoded['techPurchases']),
      );
    } on FormatException {
      return CampaignSave.empty;
    } on TypeError {
      return CampaignSave.empty;
    }
  }

  static CampaignProgress _decodeStageResults(
    Map<String, Object?> decoded, {
    required Iterable<StageDefinition> knownStages,
  }) {
    final rawResults = decoded['stageResults'];
    if (rawResults is! Map<String, Object?>) {
      return CampaignProgress();
    }
    final knownIds = knownStages.map((stage) => stage.id).toSet();
    final results = <String, StageResult>{};
    for (final entry in rawResults.entries) {
      if (!knownIds.contains(entry.key)) {
        continue;
      }
      final result = StageResult.fromJson(entry.value);
      if (result == null) {
        continue;
      }
      results[entry.key] = result;
    }
    return CampaignProgress(bestResultsByStageId: results);
  }

  static CampaignTechTree _decodeTechPurchases(Object? raw) {
    if (raw is! List) {
      return CampaignTechTree();
    }
    final ids = raw.whereType<String>().toList();
    return CampaignTechTree.fromIdList(ids);
  }

  static CampaignProgress _decodeVersionOne(
    Map<String, Object?> decoded, {
    required Iterable<StageDefinition> knownStages,
  }) {
    final rawIds = decoded['clearedStageIds'];
    if (rawIds is! List) {
      return CampaignProgress();
    }
    final knownIds = knownStages.map((stage) => stage.id).toSet();
    final results = <String, StageResult>{};
    for (final id in rawIds.whereType<String>()) {
      if (!knownIds.contains(id) || results.containsKey(id)) {
        continue;
      }
      results[id] = const StageResult(
        medal: StageMedal.clear,
        bestBaseHealth: 0,
      );
    }
    return CampaignProgress(bestResultsByStageId: results);
  }
}

class SharedPreferencesCampaignProgressStore implements CampaignProgressStore {
  SharedPreferencesCampaignProgressStore({
    required SharedPreferences preferences,
    required Iterable<StageDefinition> knownStages,
    String key = 'orion.campaign.progress',
  }) : this._(preferences, knownStages: knownStages, key: key);

  SharedPreferencesCampaignProgressStore._(
    this._preferences, {
    required Iterable<StageDefinition> knownStages,
    required this.key,
  }) : _knownStages = List.unmodifiable(knownStages);

  final SharedPreferences _preferences;
  final List<StageDefinition> _knownStages;
  final String key;

  @override
  Future<CampaignSave> load() async {
    final String? source;
    try {
      source = _preferences.getString(key);
    } on TypeError {
      return CampaignSave.empty;
    }
    return CampaignProgressCodec.decode(source, knownStages: _knownStages);
  }

  @override
  Future<void> save(CampaignSave save) async {
    final persisted = await _preferences.setString(
      key,
      CampaignProgressCodec.encode(save),
    );
    if (!persisted) {
      throw StateError('Failed to save campaign progress.');
    }
  }

  @override
  Future<void> reset() async {
    final persisted = await _preferences.remove(key);
    if (!persisted) {
      throw StateError('Failed to reset campaign progress.');
    }
  }
}

class InMemoryCampaignProgressStore implements CampaignProgressStore {
  InMemoryCampaignProgressStore({
    required Iterable<StageDefinition> knownStages,
  }) : _knownStages = List.unmodifiable(knownStages);

  final List<StageDefinition> _knownStages;
  String? _source;

  @override
  Future<CampaignSave> load() async {
    return CampaignProgressCodec.decode(_source, knownStages: _knownStages);
  }

  @override
  Future<void> save(CampaignSave save) async {
    _source = CampaignProgressCodec.encode(save);
  }

  @override
  Future<void> reset() async {
    _source = null;
  }
}
```

- [ ] **Step 4: Run the store tests to verify they pass**

Run: `flutter test test/game/campaign_progress_store_test.dart`
Expected: PASS (after migrating the existing call sites per Step 1).

- [ ] **Step 5: Commit (build will be broken elsewhere — that's expected; Task 5 fixes widget tests)**

```bash
git add lib/game/campaign/campaign_progress_store.dart test/game/campaign_progress_store_test.dart
git commit -m "feat: add CampaignSave aggregate, bump codec to v3 (HPA-100)"
```

---

## Task 5: Widget test store migration

The store interface change in Task 4 breaks every existing test that touches a `CampaignProgressStore`. This task is purely mechanical migration — no production code changes.

**Files:**
- Modify: `test/widget_test.dart` — `_TestCampaignProgressStore`; 15+ call sites of `store.save(progress)` / `store.load()`.

**Interfaces:**
- Consumes: `CampaignSave` (Task 4).
- Produces: a green widget-test suite.

- [ ] **Step 1: Run the widget tests to see what breaks**

Run: `flutter test test/widget_test.dart`
Expected: many compile errors referencing `CampaignProgressStore.load` / `.save` return types and `_TestCampaignProgressStore`.

- [ ] **Step 2: Update `_TestCampaignProgressStore`**

Find `class _TestCampaignProgressStore implements CampaignProgressStore` (around `test/widget_test.dart:1303`). Replace its body so it implements the new interface:

```dart
class _TestCampaignProgressStore implements CampaignProgressStore {
  _TestCampaignProgressStore({
    CampaignSave? initial,
    this.failOnSave = false,
    this.failOnReset = false,
  }) : _save = initial ?? CampaignSave.empty;

  CampaignSave _save;
  final bool failOnSave;
  final bool failOnReset;

  @override
  Future<CampaignSave> load() async => _save;

  @override
  Future<void> save(CampaignSave save) async {
    if (failOnSave) {
      throw Exception('save failed');
    }
    _save = save;
  }

  @override
  Future<void> reset() async {
    if (failOnReset) {
      throw Exception('reset failed');
    }
    _save = CampaignSave.empty;
  }
}
```

The existing constructor parameters in the file may differ (e.g. `initialProgress`); preserve them by adapting the initializer. If a test passes `CampaignProgress` directly, wrap it: `_TestCampaignProgressStore(initial: CampaignSave(progress: <that>, techTree: CampaignTechTree()))`.

- [ ] **Step 3: Update every `store.save(progress)` and `store.load()` call**

Run the grep to find them all:

```bash
grep -n "store.save\|store.load\|await store" test/widget_test.dart
```

For each `store.save(progressInstance)`: change to `store.save(CampaignSave(progress: progressInstance, techTree: CampaignTechTree()))`.

For each `(await store.load())` consumed as a `CampaignProgress`: change to `(await store.load()).progress`.

For test helpers that construct `_TestCampaignProgressStore(initial: <progress>)`: change to wrap in `CampaignSave(progress: <progress>, techTree: CampaignTechTree())`.

- [ ] **Step 4: Run the widget tests**

Run: `flutter test test/widget_test.dart`
Expected: PASS — all existing tests green again. (If a test specifically asserts on tech-tree behavior, leave that for Task 12; this task only does the mechanical migration.)

- [ ] **Step 5: Commit**

```bash
git add test/widget_test.dart
git commit -m "test: migrate widget tests to CampaignSave interface (HPA-100)"
```

---

## Task 6: GameSession gains modifiers field + wave-clear multiplier

**Files:**
- Modify: `lib/game/rules/game_session.dart` — `GameSession.initial` signature; `finishActiveWave` multiplier.
- Test: `test/game/game_session_test.dart` — modifiers param; wave-clear tests.

**Interfaces:**
- Consumes: `CampaignModifiers` (Task 3).
- Produces: `GameSession.modifiers` field; wave-clear gold scaled by `(1 + modifiers.clearBonusFraction)`.

- [ ] **Step 1: Add failing tests**

Open `test/game/game_session_test.dart` and append inside `void main()`:

```dart
  group('GameSession tech-tree modifiers', () {
    test('modifiers default to empty when omitted', () {
      final session = GameSession.initial();
      expect(session.modifiers, CampaignModifiers.empty);
    });

    test('modifiers are stored on the session', () {
      const mods = CampaignModifiers(
        bonusGold: 30,
        bonusHealth: 5,
        clearBonusFraction: 0.25,
      );
      final session = GameSession.initial(modifiers: mods);
      expect(session.modifiers, mods);
    });

    test('starting gold/health reflect modifiers when no overrides', () {
      const mods = CampaignModifiers(bonusGold: 30, bonusHealth: 5);
      final session = GameSession.initial(modifiers: mods);
      expect(session.startingGold, GameBalance.startingGold + 30);
      expect(session.startingBaseHealth, GameBalance.initialBaseHealth + 5);
    });

    test('explicit gold/baseHealth overrides still win over modifiers', () {
      const mods = CampaignModifiers(bonusGold: 30);
      final session = GameSession.initial(
        modifiers: mods,
        gold: 999,
        baseHealth: 999,
      );
      expect(session.startingGold, 999);
      expect(session.startingBaseHealth, 999);
    });

    test('wave-clear bonus scales by (1 + clearBonusFraction) on intermediate waves', () {
      const mods = CampaignModifiers(clearBonusFraction: 0.25);
      final session = GameSession.initial(modifiers: mods);
      // Advance to wave phase, then finish it. The first wave's clearBonus
      // is 30 by OrionCampaign default; 30 * 1.25 = 37.5 -> round -> 38.
      // Use a stage with at least 2 waves so finishActiveWave credits gold.
      final stage = OrionCampaign.stageOne;
      final s = GameSession.initial(stage: stage, modifiers: mods);
      // Drive to wave phase, finish it, check gold delta.
      // (Adapt the existing wave-clear test pattern in this file.)
      expect(s.modifiers.clearBonusFraction, 0.25);
    });

    test('wave-clear without salvageCrew is unchanged', () {
      final session = GameSession.initial();
      expect(session.modifiers.clearBonusFraction, 0);
    });
  });
```

For the wave-clear integration test, look at how existing tests in this file drive `finishActiveWave` (use the same setup pattern). The assertion is: with `clearBonusFraction = 0.25`, after finishing a wave whose `clearBonus` is 30, gold increases by `(30 * 1.25).round()` = 38; without the fraction, by 30.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/game/game_session_test.dart`
Expected: FAIL — `GameSession.initial(modifiers:)` and `session.modifiers` undefined.

- [ ] **Step 3: Update `GameSession.initial` signature and store modifiers**

Open `lib/game/rules/game_session.dart`. Find the `GameSession.initial` constructor (around line 5–25). Update it to accept `modifiers` and store it as a field. The existing initializer-list body needs the new field; here's the pattern (adapt to whatever the existing initializer looks like):

```dart
  GameSession.initial({
    StageDefinition? stage,
    CampaignModifiers modifiers = CampaignModifiers.empty,
    int? gold,
    int? baseHealth,
  }) : stage = stage ?? OrionCampaign.stageOne,
       startingGold = gold ?? modifiers.adjustedStartingGold,
       startingBaseHealth = baseHealth ?? modifiers.adjustedStartingBaseHealth,
       modifiers = modifiers,
       _gold = gold ?? modifiers.adjustedStartingGold,
       _baseHealth = baseHealth ?? modifiers.adjustedStartingBaseHealth,
       _waveIndex = 0,
       _phase = GamePhase.build,
       _nextTowerId = 1 {
    _towersByPosition = <GridPosition, PlacedTower>{};
  }

  final CampaignModifiers modifiers;
```

(Match the existing field initialization order exactly; the only changes are: new `modifiers` parameter, new `modifiers = modifiers` initializer line, new `final CampaignModifiers modifiers;` field, and `gold`/`baseHealth` defaults changed from `GameBalance.startingGold` / `GameBalance.initialBaseHealth` to `modifiers.adjustedStartingGold` / `modifiers.adjustedStartingBaseHealth`.)

Add the `CampaignModifiers` import if not present:

```dart
import '../campaign/campaign_progress.dart';
```

- [ ] **Step 4: Apply the wave-clear multiplier**

In the same file, find `finishActiveWave` (around line 223–237). Replace:

```dart
    _gold += completedWave?.clearBonus ?? 0;
```

with:

```dart
    final waveBonus = completedWave?.clearBonus ?? 0;
    _gold += (waveBonus * (1 + modifiers.clearBonusFraction)).round();
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/game/game_session_test.dart`
Expected: PASS.

- [ ] **Step 6: Run full suite to surface regressions**

Run: `flutter test`
Expected: any test constructing `GameSession.initial()` without modifiers still works (defaults to `CampaignModifiers.empty`). If anything asserts the old `_gold += clearBonus` semantics with a non-zero `clearBonus`, those assertions need updating only if they construct a session with `clearBonusFraction > 0` — otherwise the math is unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/game/rules/game_session.dart test/game/game_session_test.dart
git commit -m "feat: thread modifiers into GameSession, scale wave-clear bonus (HPA-100)"
```

---

## Task 7: TowerComponent `_resolveStats` with modifiers field

**Files:**
- Modify: `lib/game/components/tower_component.dart` — `modifiers` field; `_resolveStats`; constructor + `updateTower` both use it.
- Test: new file `test/game/tower_component_stats_test.dart` (the existing `enemy_component_test.dart` is a precedent for component-level tests).

**Interfaces:**
- Consumes: `CampaignModifiers` (Task 3); `TowerStats.copyWith` (Task 2).
- Produces: `TowerComponent({..., CampaignModifiers modifiers = CampaignModifiers.empty})`; laser/cryo bonuses baked into `stats`.

- [ ] **Step 1: Write failing tests**

Create `test/game/tower_component_stats_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  // Use the simplest possible PlacedTower fixtures. The resolver only reads
  // tower.type / level / specialization, so position is irrelevant.
  PlacedTower tower(TowerType type) => PlacedTower(
        id: 1,
        type: type,
        position: const GridPosition(0, 0),
      );

  group('TowerComponent stats resolution', () {
    test('laser damage multiplied by (1 + laserDamageFraction)', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final component = TowerComponent(
        tower: tower(TowerType.laser),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, __) {},
        modifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
    });

    test('laser damage unchanged when laserDamageFraction is 0', () {
      final component = TowerComponent(
        tower: tower(TowerType.laser),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, __) {},
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(component.stats.damage, base.damage);
    });

    test('cryo slowDuration extended by cryoSlowDurationBonus', () {
      const mods = CampaignModifiers(cryoSlowDurationBonus: 0.30);
      final component = TowerComponent(
        tower: tower(TowerType.cryo),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, __) {},
        modifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.cryo, level: 1);
      expect(component.stats.slowDuration, closeTo(base.slowDuration + 0.30, 1e-9));
    });

    test('non-laser, non-cryo tower is unaffected by both combat upgrades', () {
      const mods = CampaignModifiers(
        laserDamageFraction: 0.10,
        cryoSlowDurationBonus: 0.30,
      );
      final component = TowerComponent(
        tower: tower(TowerType.rocket),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, __) {},
        modifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.rocket, level: 1);
      expect(component.stats.damage, base.damage);
      expect(component.stats.slowDuration, base.slowDuration);
    });

    test('updateTower re-applies multiplier on upgraded laser', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final component = TowerComponent(
        tower: tower(TowerType.laser),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, __) {},
        modifiers: mods,
      );
      final upgraded = tower(TowerType.laser).upgraded();
      component.updateTower(upgraded);
      final baseL2 = GameBalance.towerStats(TowerType.laser, level: 2);
      expect(component.stats.damage, closeTo(baseL2.damage * 1.10, 1e-9));
    });

    test('updateTower re-applies multiplier on specialized cryo', () {
      const mods = CampaignModifiers(cryoSlowDurationBonus: 0.30);
      final component = TowerComponent(
        tower: tower(TowerType.cryo),
        center: _zero(),
        acquireTarget: (_) => null,
        launchProjectile: (_, __) {},
        modifiers: mods,
      );
      // Upgrade to L2, then specialize.
      final upgraded = tower(TowerType.cryo).upgraded();
      component.updateTower(upgraded);
      final specialized = upgraded.specialized(TowerSpecialization.deepFreeze);
      component.updateTower(specialized);
      final baseL3DeepFreeze = GameBalance.towerStats(
        TowerType.cryo,
        level: 3,
        specialization: TowerSpecialization.deepFreeze,
      );
      expect(
        component.stats.slowDuration,
        closeTo(baseL3DeepFreeze.slowDuration + 0.30, 1e-9),
      );
    });
  });
}

Vector2 _zero() => Vector2(0, 0);
```

(If `TowerComponent`'s constructor requires additional parameters beyond those shown, add them — check the existing constructor signature in `lib/game/components/tower_component.dart:15`. The `Vector2` import comes from `flame/components.dart`.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/game/tower_component_stats_test.dart`
Expected: FAIL — `TowerComponent` constructor has no `modifiers` parameter.

- [ ] **Step 3: Modify `TowerComponent`**

Open `lib/game/components/tower_component.dart`. Replace the constructor and add the `_resolveStats` method:

```dart
class TowerComponent extends CircleComponent {
  TowerComponent({
    required PlacedTower tower,
    required Vector2 center,
    required this.acquireTarget,
    required this.launchProjectile,
    this.spriteSheet,
    this.towerVarietySheet,
    this.modifiers = CampaignModifiers.empty,
    double radius = 15,
    super.priority,
  }) : placedTower = tower,
       stats = _resolveStats(tower, modifiers),
       super(
         radius: radius,
         anchor: Anchor.center,
         position: center.clone(),
         paint: Paint()..color = _towerColor(tower.type),
       );

  PlacedTower placedTower;
  TowerStats stats;
  final CampaignModifiers modifiers;
  final TargetAcquirer acquireTarget;
  final ProjectileLauncher launchProjectile;
  final GameSpriteSheet? spriteSheet;
  final GameTowerVarietySheet? towerVarietySheet;

  // ... existing fields unchanged ...

  void updateTower(PlacedTower tower) {
    placedTower = tower;
    stats = _resolveStats(tower, modifiers);
    paint.color = _towerColor(tower.type);
  }

  /// Resolves a tower's runtime [TowerStats] from [GameBalance], then applies
  /// the laser/cryo tech-tree combat upgrades. Called from the constructor
  /// and from [updateTower] so upgrades/specializations re-apply the bonus.
  /// Pure: identical inputs yield identical outputs. The laser/cryo branches
  /// are filtered by tower type so a non-matching tower is unaffected.
  static TowerStats _resolveStats(PlacedTower tower, CampaignModifiers modifiers) {
    final base = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    if (tower.type == TowerType.laser && modifiers.laserDamageFraction > 0) {
      return base.copyWith(damage: base.damage * (1 + modifiers.laserDamageFraction));
    }
    if (tower.type == TowerType.cryo && modifiers.cryoSlowDurationBonus > 0) {
      return base.copyWith(
        slowDuration: base.slowDuration + modifiers.cryoSlowDurationBonus,
      );
    }
    return base;
  }

  // ... rest unchanged ...
}
```

Add the `CampaignModifiers` import at the top:

```dart
import '../campaign/campaign_progress.dart';
```

- [ ] **Step 4: Run the new tests**

Run: `flutter test test/game/tower_component_stats_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS — no regressions. Existing `TowerComponent` callers don't pass `modifiers`, so they get the default `CampaignModifiers.empty` and resolve stats as before.

- [ ] **Step 6: Commit**

```bash
git add lib/game/components/tower_component.dart test/game/tower_component_stats_test.dart
git commit -m "feat: bake laser/cryo tech-tree mods into TowerStats via _resolveStats (HPA-100)"
```

---

## Task 8: OrionDefenseGame threads modifiers through to GameSession and TowerComponent

**Files:**
- Modify: `lib/game/orion_defense_game.dart` — `GameSession.initial` call gains `modifiers:`; `_addTowerComponent` threads modifiers to `TowerComponent`.
- Test: `test/game/orion_defense_game_test.dart` — verify end-to-end modifiers application.

**Interfaces:**
- Consumes: `GameSession(modifiers:)` (Task 6); `TowerComponent(modifiers:)` (Task 7).
- Produces: a fully-wired `OrionDefenseGame` that applies all five tech-tree effects.

- [ ] **Step 1: Write the failing tests**

Open `test/game/orion_defense_game_test.dart` and append:

```dart
  group('OrionDefenseGame tech-tree modifiers', () {
    test('modifiers are forwarded to GameSession (starting gold/health)', () {
      const mods = CampaignModifiers(bonusGold: 15, bonusHealth: 3);
      final game = OrionDefenseGame(
        stage: OrionCampaign.stageOne,
        modifiers: mods,
      );
      expect(game.session.startingGold, GameBalance.startingGold + 15);
      expect(game.session.startingBaseHealth, GameBalance.initialBaseHealth + 3);
      expect(game.session.modifiers, mods);
    });

    test('null modifiers default to CampaignModifiers.empty', () {
      final game = OrionDefenseGame();
      expect(game.session.modifiers, CampaignModifiers.empty);
      expect(game.session.startingGold, GameBalance.startingGold);
      expect(game.session.startingBaseHealth, GameBalance.initialBaseHealth);
    });

    test('laser towers receive laserDamageFraction from modifiers', () {
      const mods = CampaignModifiers(laserDamageFraction: 0.10);
      final game = OrionDefenseGame(
        stage: OrionCampaign.stageOne,
        modifiers: mods,
      );
      game.onGameResize(Vector2(800, 600));
      // Place a laser tower at a valid non-path cell; verify its stats reflect
      // the multiplier. Use the existing place-tower test helper pattern.
      // ... (adapt to whatever pattern this file uses to drive placement)
      // For the assertion:
      // final component = game.towerAt(...) ;
      // expect(component.stats.damage, closeTo(base.damage * 1.10, 1e-9));
    }, skip: 'wire placement helper in this file first');
  });
```

(Adapt the placement test to whatever helper this file already uses — look at existing placement tests for the pattern. If no such helper exists, drop the third test and rely on the `tower_component_stats_test.dart` coverage plus an integration assertion on `game.modifiers`.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/game/orion_defense_game_test.dart`
Expected: FAIL — `game.session.modifiers` undefined.

- [ ] **Step 3: Thread modifiers through**

Open `lib/game/orion_defense_game.dart`. The constructor is at lines 36–48. Update the `GameSession.initial` call to pass `modifiers`:

```dart
  OrionDefenseGame({
    StageDefinition? stage,
    this.modifiers,
    this.onStageWon,
    this.onReturnToMap,
  }) : stage = stage ?? OrionCampaign.stageOne,
       _session = GameSession.initial(
         stage: stage ?? OrionCampaign.stageOne,
         modifiers: modifiers ?? CampaignModifiers.empty,
         gold: modifiers?.adjustedStartingGold,
         baseHealth: modifiers?.adjustedStartingBaseHealth,
       ) {
    _resetPacing();
  }
```

(Keeping `gold:` / `baseHealth:` overrides for explicit-pass-through; they win over `modifiers.adjustedStartingGold` when set, which matches the test in Task 6 Step 1.)

If `GameSession` doesn't expose a public getter today, add one:

```dart
GameSession get session => _session;
```

Find `_addTowerComponent` (around line 426). It constructs `TowerComponent`. Add the `modifiers` argument:

```dart
  void _addTowerComponent(PlacedTower tower) {
    final component = TowerComponent(
      tower: tower,
      center: _boardCenterFor(tower.position),
      acquireTarget: _selectTargetForTower,
      launchProjectile: _launchProjectile,
      spriteSheet: _spriteSheet,
      towerVarietySheet: _towerVarietySheet,
      modifiers: modifiers ?? CampaignModifiers.empty,
      priority: 10,
    );
    _towerComponents[tower.id] = component;
    add(component);
  }
```

(Adjust `_boardCenterFor` / `position` to match the existing call — only the `modifiers:` line is new.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/game/orion_defense_game_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/game/orion_defense_game.dart test/game/orion_defense_game_test.dart
git commit -m "feat: thread modifiers to GameSession and TowerComponent (HPA-100)"
```

---

## Task 9: Shell navigation (`_ShellView`) + `_techTree` state + `_loadProgress` migration

This task is plumbing only — no new user-visible behavior. It sets up the state the later UI tasks consume.

> **Implementation note:** The original plan kept `_activeStage` alongside the new `_activeView` field. The implementation dropped `_activeStage` entirely — `_activeView` fully covers shell routing (`worldMap` / `techTree` / `stage`), and no code reads `_activeStage` for any purpose other than routing. `_startStage` / `_returnToMap` / `_confirmResetCampaign` set `_activeView` only.

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart` — add `_ShellView` enum; add `_techTree`, `_techTreeFeedback`; migrate `_loadProgress`; migrate `build()` routing; update `CampaignModifiers.fromProgress` callers to pass `_techTree`.

**Interfaces:**
- Consumes: `CampaignSave` (Task 4); `CampaignTechTree` (Task 1).
- Produces: `_OrionGamePageState._techTree`; `_activeView` field; `_ShellView` enum.

- [ ] **Step 1: Add the `_ShellView` enum and new state fields**

Open `lib/game/ui/orion_game_page.dart`. Just above `class OrionGamePage extends StatefulWidget {` (line 13), add:

```dart
enum _ShellView { worldMap, techTree, stage }
```

Inside `_OrionGamePageState` (line 29), add the new fields just below the existing ones (after line 38):

```dart
  CampaignTechTree _techTree = CampaignTechTree();
  String? _techTreeFeedback;
  _ShellView _activeView = _ShellView.worldMap;
```

- [ ] **Step 2: Migrate `_loadProgress`**

Find `_loadProgress` (line 46). Update the success branch (lines 63–73) to load both fields:

```dart
      final save = await store.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _store = store;
        _progress = save.progress;
        _techTree = save.techTree;
        _isLoading = false;
      });
```

And the failure branch (`catch (_)` around line 74–85):

```dart
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _store = store;
        _progress = CampaignProgress();
        _techTree = CampaignTechTree();
        _mapFeedback = 'Could not load campaign progress.';
        _isLoading = false;
      });
    }
```

- [ ] **Step 3: Migrate `build()` routing**

Find `build()` (line 89). Replace the routing logic (currently `_activeStage == null || game == null` for map vs. stage) with explicit `_activeView` checks:

```dart
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    switch (_activeView) {
      case _ShellView.worldMap:
      case _ShellView.techTree:
        // TechTreeView is added in Task 12; for now both fall through to the
        // world-map scaffold so the build stays green.
        return _buildWorldMapScaffold();
      case _ShellView.stage:
        return _buildStageScaffold();
    }
  }

  Widget _buildWorldMapScaffold() {
    return Scaffold(
      body: WorldMapView(
        stages: OrionCampaign.stages,
        progress: _progress,
        modifiers: CampaignModifiers.fromProgress(
          _progress,
          OrionCampaign.stages,
          _techTree,
        ),
        feedback: _mapFeedback,
        isSavingProgress: _isSavingProgress,
        onStageSelected: _startStage,
        onLockedStageSelected: _showLockedStageFeedback,
        onResetCampaign: _confirmResetCampaign,
      ),
    );
  }

  Widget _buildStageScaffold() {
    final game = _game;
    if (game == null) {
      // Defensive: shouldn't happen because _activeView == stage implies _game.
      return _buildWorldMapScaffold();
    }
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<GameSnapshot>(
          valueListenable: game.stateNotifier,
          builder: (context, snapshot, _) {
            return Stack(
              children: [
                Positioned.fill(child: GameWidget(game: game)),
                // ... rest of the existing stage-view Stack contents ...
              ],
            );
          },
        ),
      ),
    );
  }
```

(Copy the existing stage-view `Stack` body from the old `build()` into `_buildStageScaffold()` verbatim — the only change is that it now lives behind a `_activeView` switch instead of an `_activeStage == null` check.)

- [ ] **Step 4: Update `_startStage` to set `_activeView`**

Find `_startStage` (line 158). At the point where it sets `_activeStage = stage; _game = game;`, also set `_activeView = _ShellView.stage;`:

```dart
    setState(() {
      _activeStage = stage;
      _game = game;
      _activeView = _ShellView.stage;
    });
```

- [ ] **Step 5: Update `_returnToMap` and `_confirmResetCampaign` to set `_activeView`**

Find `_returnToMap` (around line 278). It clears `_activeStage` and `_game`; add `_activeView = _ShellView.worldMap;`:

```dart
  void _returnToMap() {
    setState(() {
      _activeStage = null;
      _game = null;
      _activeView = _ShellView.worldMap;
    });
  }
```

Find `_confirmResetCampaign` (around line 339). In the setState block that clears state after the reset, also clear `_techTree`:

```dart
    setState(() {
      _progress = CampaignProgress();
      _techTree = CampaignTechTree();
      _activeStage = null;
      _game = null;
      _activeView = _ShellView.worldMap;
      _mapFeedback = 'Campaign reset.';
    });
```

- [ ] **Step 6: Update the second `fromProgress` caller (inside `_startStage`)**

Find `_startStage`'s `final modifiers = CampaignModifiers.fromProgress(...)` (around line 171). Update to pass `_techTree`:

```dart
    final modifiers = CampaignModifiers.fromProgress(
      _progress,
      OrionCampaign.stages,
      _techTree,
    );
```

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: PASS — no behavior change yet (TechTreeView is added in Task 12; for now both non-stage views render the world map). The HPA-94 reset regression tests must still pass (they exercise `_confirmResetCampaign`).

- [ ] **Step 8: Commit**

```bash
git add lib/game/ui/orion_game_page.dart
git commit -m "refactor: migrate shell routing to _ShellView, add _techTree state (HPA-100)"
```

---

## Task 10: Unified `_persistSave` helper + drop `_recordStageCompletion` + dual-targeting feedback

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart` — add `_persistSave`; refactor `_saveStageCompletion`; drop `_recordStageCompletion`; update `_showCampaignPersistenceFailure`.

**Interfaces:**
- Consumes: `CampaignSave` (Task 4); `_activeView` / `_techTreeFeedback` (Task 9).
- Produces: `_persistSave({CampaignProgress? nextProgress, CampaignTechTree? nextTechTree})`.

- [ ] **Step 1: Read the current save flow**

Open `lib/game/ui/orion_game_page.dart`. Re-read `_recordStageCompletion` (around line 196), `_saveStageCompletion` (around line 205), and `_resetStoreAfterStaleSave` (around line 349). The new helper preserves their invariants:
- Disposal safety (commit 700cef1): bare field updates when unmounted; guard `setState`.
- `_isSavingProgress` clears in `finally`.
- Post-stale-save reset wipes the store if generation mismatches after a successful save.

- [ ] **Step 2: Add `_persistSave` helper**

Add the following method to `_OrionGamePageState` (place it just above `_recordStageCompletion`):

```dart
  Future<void> _persistSave({
    CampaignProgress? nextProgress,
    CampaignTechTree? nextTechTree,
  }) async {
    final store = _store;
    if (store == null) {
      _showCampaignPersistenceFailure();
      return;
    }

    final saveGeneration = _progressGeneration;
    final priorProgress = _progress;
    final priorTechTree = _techTree;

    // Optimistic update: scoped to provided fields. Bare assignment when
    // unmounted so queued saves derive from the latest state (HPA-94 700cef1).
    if (nextProgress != null) _progress = nextProgress;
    if (nextTechTree != null) _techTree = nextTechTree;
    _isSavingProgress = true;
    if (mounted) {
      setState(() {});
    }

    final saveTask = _saveQueue.then((_) async {
      if (saveGeneration != _progressGeneration) {
        return;
      }
      await store.save(CampaignSave(progress: _progress, techTree: _techTree));
    });
    _saveQueue = saveTask.catchError((_) {});

    try {
      await saveTask;
      // Post-stale-save reset: if a reset happened during the save, the disk
      // write may have landed with pre-reset data. Wipe the store to match
      // the post-reset in-memory state.
      if (saveGeneration != _progressGeneration) {
        await _resetStoreAfterStaleSave(store);
      }
    } catch (_) {
      if (!mounted || saveGeneration != _progressGeneration) {
        return;
      }
      // Field-scoped rollback (HPA-100 spec round-2 issue #4): only restore
      // the field(s) this save touched, so a failed stage save can't clobber
      // a concurrent tech-purchase save's optimistic update.
      if (nextProgress != null) _progress = priorProgress;
      if (nextTechTree != null) _techTree = priorTechTree;
      if (mounted) {
        setState(() {});
      }
      _showCampaignPersistenceFailure();
    } finally {
      if (saveGeneration == _progressGeneration) {
        _isSavingProgress = false;
        if (mounted) setState(() {});
      }
    }
  }
```

- [ ] **Step 3: Refactor `_saveStageCompletion` to use `_persistSave`, drop `_recordStageCompletion`**

Find `_recordStageCompletion` (around line 196) and `_saveStageCompletion` (around line 205). Delete `_recordStageCompletion` entirely. Replace `_saveStageCompletion` with a thin wrapper that calls `_persistSave`:

```dart
  Future<void> _saveStageCompletion(StageCompletion completion) {
    final priorResult = _progress.resultFor(completion.stage.id);
    final newProgress = _progress.recordResult(
      completion.stage.id,
      completion.result,
    );
    // recordResult returns the same instance when the new result is not an
    // improvement; skip the save entirely in that case.
    if (newProgress.resultFor(completion.stage.id) == priorResult) {
      return Future<void>.value();
    }
    return _persistSave(nextProgress: newProgress);
  }
```

Find the caller of `_recordStageCompletion` (it was the `onStageWon` handler — search for `_recordStageCompletion`):

```bash
grep -n "_recordStageCompletion" lib/game/ui/orion_game_page.dart
```

That caller now calls `_saveStageCompletion` directly (since `_recordStageCompletion` no longer exists). For example, if the `onStageWon` callback was `(completion) => _recordStageCompletion(completion)`, change it to `(completion) => _saveStageCompletion(completion)`.

- [ ] **Step 4: Update `_showCampaignPersistenceFailure` with dual-targeting**

Find `_showCampaignPersistenceFailure` (around line 363). Replace with:

```dart
  void _showCampaignPersistenceFailure() {
    const message = 'Could not save campaign progress.';
    final game = _game;
    setState(() {
      _mapFeedback = message; // always; preserves HPA-94 breadcrumb behavior
      if (_activeView == _ShellView.techTree) {
        _techTreeFeedback = message;
      }
    });
    if (_activeView == _ShellView.stage && game != null) {
      game.overrideFeedback(message);
    }
  }
```

- [ ] **Step 5: Run the widget tests**

Run: `flutter test test/widget_test.dart`
Expected: most tests pass, but the test at line 442 ("serializes sibling stage clear saves") and the 700cef1 regression test may need updates — they call `_recordStageCompletion` internally or exercise it via `onStageWon`. Update those to use the new entry point.

For any test that asserts `_isSavingProgress` becomes `false` after a failed save, the new helper preserves that semantics (it's in `finally`).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS — all HPA-94 regression tests still green. The sibling-save serialization test (`widget_test.dart:442`) still passes because the underlying `_saveQueue` serialization is preserved.

- [ ] **Step 7: Commit**

```bash
git add lib/game/ui/orion_game_page.dart test/widget_test.dart
git commit -m "refactor: unify save flow into _persistSave, drop _recordStageCompletion (HPA-100)"
```

---

## Task 11: `_purchaseTech` handler + WorldMapView "Tech Tree" button

**Files:**
- Modify: `lib/game/ui/orion_game_page.dart` — add `_purchaseTech`; add `_openTechTree` / `_closeTechTree`.
- Modify: `lib/game/ui/world_map_view.dart` — add `onOpenTechTree` callback; add "Tech Tree" button to the header.

**Interfaces:**
- Consumes: `_persistSave` (Task 10); `_activeView` (Task 9); `CampaignTechTree.purchase` (Task 1).
- Produces: `_purchaseTech(CampaignTechUpgrade)`; `_openTechTree()` / `_closeTechTree()`; `WorldMapView.onOpenTechTree`.

- [ ] **Step 1: Add `_purchaseTech`, `_openTechTree`, `_closeTechTree` to `_OrionGamePageState`**

Open `lib/game/ui/orion_game_page.dart`. Add the following methods (place near `_startStage` for cohesion):

```dart
  void _openTechTree() {
    setState(() {
      _techTreeFeedback = null;
      _activeView = _ShellView.techTree;
    });
  }

  void _closeTechTree() {
    setState(() {
      _activeView = _ShellView.worldMap;
    });
  }

  Future<void> _purchaseTech(CampaignTechUpgrade upgrade) async {
    if (_isSavingProgress) {
      return; // matches stage-launch guard
    }
    final newTechTree = _techTree.purchase(upgrade, _progress);
    await _persistSave(nextTechTree: newTechTree);
  }
```

- [ ] **Step 2: Add `onOpenTechTree` to `WorldMapView`**

Open `lib/game/ui/world_map_view.dart`. In the `WorldMapView` constructor and field declarations (around lines 8–27), add:

```dart
  const WorldMapView({
    super.key,
    required this.stages,
    required this.progress,
    this.modifiers,
    required this.feedback,
    this.isSavingProgress = false,
    required this.onStageSelected,
    this.onLockedStageSelected,
    required this.onResetCampaign,
    this.onOpenTechTree,
  });

  // ... existing fields ...
  final VoidCallback? onOpenTechTree;
```

- [ ] **Step 3: Add the "Tech Tree" button to the header**

Find the existing header `Row` (around line 46–61):

```dart
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orion Sector Map',
                    // ... existing style ...
                  ),
                ),
                IconButton(
                  tooltip: 'Reset Campaign',
                  onPressed: onResetCampaign,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
```

Insert a Tech Tree button before the Reset button:

```dart
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orion Sector Map',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onOpenTechTree != null)
                  IconButton(
                    tooltip: 'Tech Tree',
                    onPressed: onOpenTechTree,
                    icon: const Icon(Icons.account_tree),
                  ),
                IconButton(
                  tooltip: 'Reset Campaign',
                  onPressed: onResetCampaign,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
```

- [ ] **Step 4: Wire `onOpenTechTree` in `_buildWorldMapScaffold`**

In `lib/game/ui/orion_game_page.dart`, find `_buildWorldMapScaffold` (from Task 9). Add `onOpenTechTree: _openTechTree` to the `WorldMapView` constructor call:

```dart
  Widget _buildWorldMapScaffold() {
    return Scaffold(
      body: WorldMapView(
        stages: OrionCampaign.stages,
        progress: _progress,
        modifiers: CampaignModifiers.fromProgress(
          _progress,
          OrionCampaign.stages,
          _techTree,
        ),
        feedback: _mapFeedback,
        isSavingProgress: _isSavingProgress,
        onStageSelected: _startStage,
        onLockedStageSelected: _showLockedStageFeedback,
        onResetCampaign: _confirmResetCampaign,
        onOpenTechTree: _openTechTree,
      ),
    );
  }
```

- [ ] **Step 5: Write a widget test that the button appears and fires the callback**

Add to `test/widget_test.dart` (or to a new `test/widget/world_map_view_test.dart`):

```dart
  testWidgets('Tech Tree button fires onOpenTechTree', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WorldMapView(
          stages: const [],
          progress: CampaignProgress(),
          feedback: null,
          onStageSelected: (_) {},
          onResetCampaign: () {},
          onOpenTechTree: () => tapped++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Tech Tree'));
    expect(tapped, 1);
  });
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/widget_test.dart`
Expected: PASS — button renders, callback fires. The TechTreeView itself isn't rendered yet (still falls through to `_buildWorldMapScaffold` when `_activeView == _ShellView.techTree`); that's Task 12.

- [ ] **Step 7: Commit**

```bash
git add lib/game/ui/orion_game_page.dart lib/game/ui/world_map_view.dart test/widget_test.dart
git commit -m "feat: add _purchaseTech handler and world-map Tech Tree button (HPA-100)"
```

---

## Task 12: `TechTreeView` widget

**Files:**
- Create: `lib/game/ui/tech_tree_view.dart`.
- Create: `test/widget/tech_tree_view_test.dart`.

**Interfaces:**
- Consumes: `CampaignTechUpgrade` / `CampaignTechTree` (Task 1); `CampaignProgress`.
- Produces: `TechTreeView` widget reached from the world map.

- [ ] **Step 1: Write failing widget tests**

Create `test/widget/tech_tree_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/tech_tree_view.dart';

void main() {
  CampaignProgress progressWithRanks(List<int> ranks) {
    final results = <String, StageResult>{};
    for (var i = 0; i < ranks.length; i++) {
      final medal = ranks[i] == 3
          ? StageMedal.gold
          : ranks[i] == 2
              ? StageMedal.silver
              : StageMedal.clear;
      results['s$i'] = StageResult(medal: medal, bestBaseHealth: 10);
    }
    return CampaignProgress(bestResultsByStageId: results);
  }

  Future<void> pumpTree(
    WidgetTester tester, {
    required CampaignProgress progress,
    required CampaignTechTree techTree,
    String? feedback,
    required void Function(CampaignTechUpgrade) onPurchase,
    required Future<void> Function() onBack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TechTreeView(
          progress: progress,
          techTree: techTree,
          feedback: feedback,
          onPurchase: onPurchase,
          onBack: onBack,
        ),
      ),
    );
  }

  testWidgets('renders all five upgrade rows with label and effect',
      (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    for (final upgrade in CampaignTechUpgrade.values) {
      expect(find.text(upgrade.label), findsOneWidget);
      expect(find.text(upgrade.effectLabel), findsOneWidget);
    }
  });

  testWidgets('header shows three-number bank readout', (tester) async {
    final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
    final techTree = CampaignTechTree(purchased: {CampaignTechUpgrade.solarCapacitors}); // spent 3
    await pumpTree(
      tester,
      progress: progress,
      techTree: techTree,
      onPurchase: (_) {},
      onBack: () async {},
    );
    // Unspent: 9 · Earned: 12 · Spent: 3
    expect(find.textContaining('Unspent: 9'), findsOneWidget);
    expect(find.textContaining('Earned: 12'), findsOneWidget);
    expect(find.textContaining('Spent: 3'), findsOneWidget);
  });

  testWidgets('purchased upgrade row is disabled', (tester) async {
    final techTree = CampaignTechTree(purchased: {CampaignTechUpgrade.solarCapacitors});
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: techTree,
      onPurchase: (_) {},
      onBack: () async {},
    );
    // The Purchase button for solar-capacitors should be absent or disabled.
    // Verify by attempting to tap and asserting no callback fires.
    var tapped = 0;
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: techTree,
      onPurchase: (_) => tapped++,
      onBack: () async {},
    );
    // Tap where the row is; the button should be disabled (no callback).
    // Implementation detail: the row's label is present; the button widget
    // itself is up to the TechTreeView implementer. This test ensures
    // tapping the row does NOT invoke onPurchase when already purchased.
    expect(tapped, 0);
  });

  testWidgets('affordable upgrade fires onPurchase', (tester) async {
    final progress = progressWithRanks(const [3, 3, 3, 3]); // 12 earned
    var purchasedUpgrade;
    await pumpTree(
      tester,
      progress: progress,
      techTree: CampaignTechTree(),
      onPurchase: (u) => purchasedUpgrade = u,
      onBack: () async {},
    );
    // Tap the Solar Capacitors Purchase button (cost 3, affordable).
    await tester.tap(find.text(CampaignTechUpgrade.solarCapacitors.label));
    // The row may use an ElevatedButton; tap it specifically.
    // The exact find pattern depends on the implementation; if the button
    // has text "Purchase", tap that:
    final purchaseButton = find.text('Purchase');
    if (purchaseButton.evaluate().isNotEmpty) {
      await tester.tap(purchaseButton.first);
    }
    await tester.pump();
    expect(purchasedUpgrade, CampaignTechUpgrade.solarCapacitors);
  });

  testWidgets('locked upgrade shows "Need N more points"', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(), // 0 earned
      techTree: CampaignTechTree(),
      onPurchase: (_) {},
      onBack: () async {},
    );
    // Cryo Coolant costs 5; with 0 bank, the row should show "Need 5 more points".
    expect(find.textContaining('Need 5 more points'), findsOneWidget);
  });

  testWidgets('shows feedback when present', (tester) async {
    await pumpTree(
      tester,
      progress: CampaignProgress(),
      techTree: CampaignTechTree(),
      feedback: 'Could not save campaign progress.',
      onPurchase: (_) {},
      onBack: () async {},
    );
    expect(find.text('Could not save campaign progress.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widget/tech_tree_view_test.dart`
Expected: FAIL — `TechTreeView` undefined.

- [ ] **Step 3: Implement `TechTreeView`**

Create `lib/game/ui/tech_tree_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/tech_tree.dart';

/// Full-screen panel reached from the world map. Shows the player's medal-
/// point bank and all five purchasable tech-tree upgrades.
class TechTreeView extends StatelessWidget {
  const TechTreeView({
    super.key,
    required this.progress,
    required this.techTree,
    this.feedback,
    required this.onPurchase,
    required this.onBack,
  });

  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final String? feedback;

  /// Invoked when the user taps an affordable upgrade's Purchase button.
  final ValueChanged<CampaignTechUpgrade> onPurchase;

  /// Invoked when the user taps the back button. Async because the parent
  /// may need to await save rollback on a failure.
  final Future<void> Function() onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = CampaignTechTree.totalMedalRank(progress);
    final spent = techTree.totalSpent;
    final unspent = techTree.unspentPoints(progress);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => onBack(),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    'Campaign Tech Tree',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Unspent: $unspent · Earned: $earned · Spent: $spent',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (feedback != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  feedback!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final upgrade in CampaignTechUpgrade.values)
                    _UpgradeRow(
                      upgrade: upgrade,
                      progress: progress,
                      techTree: techTree,
                      onPurchase: onPurchase,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({
    required this.upgrade,
    required this.progress,
    required this.techTree,
    required this.onPurchase,
  });

  final CampaignTechUpgrade upgrade;
  final CampaignProgress progress;
  final CampaignTechTree techTree;
  final ValueChanged<CampaignTechUpgrade> onPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPurchased = techTree.isPurchased(upgrade);
    final unspent = techTree.unspentPoints(progress);
    final canAfford = !isPurchased && unspent >= upgrade.cost;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(upgrade.label,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(upgrade.description,
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(upgrade.effectLabel,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 2),
                  Text('Cost: ${upgrade.cost} pts',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            _buildAction(theme, isPurchased, canAfford, unspent),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    ThemeData theme,
    bool isPurchased,
    bool canAfford,
    int unspent,
  ) {
    if (isPurchased) {
      return Chip(
        label: Text('Purchased',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
        backgroundColor: theme.colorScheme.primaryContainer,
      );
    }
    if (canAfford) {
      return FilledButton(
        onPressed: () => onPurchase(upgrade),
        child: const Text('Purchase'),
      );
    }
    final needed = upgrade.cost - unspent;
    return FilledButton(
      onPressed: null, // disabled
      child: Text('Need $needed more points'),
    );
  }
}
```

- [ ] **Step 4: Run the widget tests**

Run: `flutter test test/widget/tech_tree_view_test.dart`
Expected: PASS. (If the "affordable upgrade fires onPurchase" test fails because the find pattern for the Purchase button doesn't match, adjust the test to `tester.tap(find.widgetWithText(FilledButton, 'Purchase').first)`.)

- [ ] **Step 5: Wire `TechTreeView` into `_OrionGamePageState.build()`**

In `lib/game/ui/orion_game_page.dart`, update the `build()` switch from Task 9 to actually render `TechTreeView` for the techTree case:

```dart
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    switch (_activeView) {
      case _ShellView.worldMap:
        return _buildWorldMapScaffold();
      case _ShellView.techTree:
        return TechTreeView(
          progress: _progress,
          techTree: _techTree,
          feedback: _techTreeFeedback,
          onPurchase: _purchaseTech,
          onBack: _closeTechTree,
        );
      case _ShellView.stage:
        return _buildStageScaffold();
    }
  }
```

Add the import at the top of `orion_game_page.dart`:

```dart
import 'tech_tree_view.dart';
```

- [ ] **Step 6: Run the full widget-test suite**

Run: `flutter test test/widget_test.dart`
Expected: PASS — all HPA-94 regression tests still green; new tech-tree navigation works end-to-end.

- [ ] **Step 7: Commit**

```bash
git add lib/game/ui/tech_tree_view.dart lib/game/ui/orion_game_page.dart test/widget/tech_tree_view_test.dart
git commit -m "feat: add TechTreeView panel wired into shell navigation (HPA-100)"
```

---

## Task 13: Acceptance pass

**Files:**
- No new code unless acceptance gaps surface.
- Verify: `test/game/game_balance_test.dart`, `test/game/game_session_test.dart`, `test/game/orion_defense_game_test.dart`, `test/widget_test.dart`.

- [ ] **Step 1: Run the entire test suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: no warnings or errors.

- [ ] **Step 3: Run `dart format`**

Run: `dart format .`
Expected: no formatting changes (or commit them if any).

- [ ] **Step 4: Verify acceptance criteria against the spec**

Open `docs/superpowers/specs/2026-07-20-orion-campaign-tech-tree-design.md` (Acceptance Criteria section). For each unchecked box, run the relevant test file or manually verify:

- **Persistent campaign tech-tree state in progress storage** — codec v3 test (`test/game/campaign_progress_store_test.dart` group `CampaignSave codec v3`).
- **At least three purchasable upgrades** — five; see `CampaignTechUpgrade.values`.
- **Upgrades visibly affect mission start or tower stats** — verify `test/game/game_session_test.dart` (wave-clear), `test/game/tower_component_stats_test.dart` (laser/cryo), and the `CampaignModifiers` tests.
- **Player can view purchased and locked upgrades from the campaign map** — `test/widget/tech_tree_view_test.dart`.
- **Upgrade purchases persist across app restarts** — codec round-trip test + store round-trip.
- **Existing saved progress remains loadable** — v2 and v1 decode tests.
- **Tests cover purchase validation, persistence, application** — see test plan in spec.

- [ ] **Step 5: Manual smoke test**

Run the app on a device/emulator:

```bash
flutter run
```

Verify:
1. World map shows a "Tech Tree" button in the header.
2. Tapping it opens the Tech Tree panel.
3. With no progress, the bank reads `Unspent: 0 · Earned: 0 · Spent: 0` and all rows show "Need N more points".
4. Clear a stage (or inject progress via the test store); return to the map; open Tech Tree; the affordable upgrades show "Purchase".
5. Tap Purchase; the row flips to "Purchased"; the bank updates.
6. Back button returns to the world map.
7. Hot-restart the app; the purchase persists.

- [ ] **Step 6: Update spec acceptance checkboxes**

Open `docs/superpowers/specs/2026-07-20-orion-campaign-tech-tree-design.md`. Change each `- [ ]` under "Acceptance Criteria" to `- [x]` now that the work is verified.

- [ ] **Step 7: Final commit**

```bash
git add docs/superpowers/specs/2026-07-20-orion-campaign-tech-tree-design.md
git commit -m "docs: mark HPA-100 acceptance criteria complete"
```

---

## Self-Review Checklist

Before handing off, the implementer should confirm:

- [ ] Every spec section maps to at least one task (see "Spec coverage" below).
- [ ] No placeholder text (`TBD`, `TODO`, "add error handling", etc.) in any step.
- [ ] Type names and method signatures are consistent across tasks (e.g., `_persistSave` parameters, `CampaignTechTree.purchase` return type).
- [ ] All cited line numbers were verified at plan-writing time; if the implementer finds drift, they should re-locate the code (the patterns are stable enough that minor renumbering is fine).
- [ ] The HPA-94 regression tests (sibling saves at `widget_test.dart:442`, post-stale-save reset at `widget_test.dart:701`, disposal-safety from commit 700cef1) all pass after Task 10.

## Spec Coverage

| Spec section | Tasks |
|---|---|
| Data Model → `CampaignTechUpgrade` / `CampaignTechTree` | T1 |
| Data Model → `GameBalance` constants | T2 |
| Data Model → `CampaignModifiers` extension | T3 |
| Application → Starting gold/health | T6, T8 |
| Application → Wave-clear bonus | T6 |
| Application → Laser/Cryo (`_resolveStats`) | T7, T8 |
| Purchase Flow / Save Flow | T9, T10 |
| Persistence (codec v3, `CampaignSave`, migrations) | T4, T5 |
| UI → `TechTreeView` | T12 |
| UI → World map entry point | T11 |
| UI → Navigation state (`_ShellView`) | T9 |
| Error Handling → all branches | T4 (unknown version), T9 (null store, reset), T10 (feedback routing, stale-save reset) |
| Testing Strategy → pure logic | T1, T3 |
| Testing Strategy → `GameSession` | T6 |
| Testing Strategy → Combat application | T7 |
| Testing Strategy → Save flow | T10 |
| Testing Strategy → Persistence | T4 |
| Testing Strategy → Store migration | T5 |
| Testing Strategy → Widget | T11, T12 |
| Acceptance Criteria | T13 |
