# Orion Campaign Tech Tree Design (HPA-100)

## Context

Orion's campaign layer (under `lib/game/campaign/`) tracks per-stage best results in `CampaignProgress`, derives stage-unlock/clear state, and — as of HPA-94 — derives campaign-wide modifiers from side-stage clears via `CampaignModifiers.fromProgress` (Salvage Rift → +30 gold, Void Bastion → +5 health, both side stages → challenge badge). Stage medals (`StageMedal.clear/silver/gold` with ranks 1/2/3) are already stored per stage.

HPA-100 adds a **separate, purchased** upgrade system layered on top: players spend medal points on persistent upgrades that apply to every future mission. It is deliberately lightweight — a flat list of five upgrades, no branching tree, no respec — matching the issue's non-goal of avoiding a large multi-branch skill-tree UI in the first pass.

The codec is currently at version 2. This work bumps it to version 3 to carry the purchased-upgrade set.

## Goal

Introduce a campaign tech tree where players spend medal points on persistent upgrades that visibly affect mission start (gold/health/clear-bonus) and tower stats (laser damage, cryo slow duration). Upgrades persist across app restarts; existing v2 saves remain loadable.

## Scope

Five upgrades shipped in the MVP:

| Upgrade | Effect | Cost |
|---|---|---|
| Solar Capacitors | +15 starting gold | 3 |
| Hardened Core | +3 starting base health | 4 |
| Salvage Crew | +25% wave-clear bonus gold | 4 |
| Laser Tuning | +10% damage on `TowerType.laser` towers | 4 |
| Cryo Coolant | +0.3s slow duration on `TowerType.cryo` towers | 5 |

Three economy upgrades + two tower-stat upgrades. Gold/health/clear-bonus take effect at mission start and per-wave; laser/cryo take effect during combat.

**Total cost: 20 medal points.** Max earnable across the seven-stage campaign is 21 (all gold). The 1-point slack is intentional: a player who earns silver instead of gold on exactly one stage can still complete the tree. Balance tests should assert the total stays at 20 unless the slack is deliberately revisited.

## Out of Scope

- A branching multi-path skill tree (issue non-goal).
- Drone AI upgrade (drone launch logic is fiddly; deferred).
- Respec / refund (purchases are permanent in MVP).
- New side stages, new tower types, new enemies, wave/economy rebalancing.
- Migration of pre-launch v1 saves beyond the existing v1→v2 path (no live players).

## Data Model

### New file: `lib/game/campaign/tech_tree.dart`

```dart
enum CampaignTechUpgrade {
  solarCapacitors,
  hardenedCore,
  salvageCrew,
  laserTuning,
  cryoCoolant;

  String   get id;          // serialized name, stable across enum reordering
  int      get cost;        // delegates to GameBalance
  String   get label;       // display name
  String   get description; // one-line description
  String   get effectLabel; // e.g. "+15 Starting Gold"

  static CampaignTechUpgrade? fromId(String id);
}

class CampaignTechTree {
  CampaignTechTree({Set<CampaignTechUpgrade> purchased = const {}});
  final Set<CampaignTechUpgrade> purchased; // unmodifiable

  bool isPurchased(CampaignTechUpgrade upgrade);
  int  get totalSpent;                          // Σ current costs of purchased
  int  unspentPoints(CampaignProgress progress); // see "Derived bank" below
  bool canPurchase(CampaignTechUpgrade upgrade, CampaignProgress progress);
  CampaignTechTree purchase(CampaignTechUpgrade upgrade, CampaignProgress progress);

  List<String> toIdList();                     // sorted, stable
  static CampaignTechTree fromIdList(Iterable<String>? ids);
}
```

### Medal-point source

The bank is funded by **existing** `StageMedal.rank` values (clear=1, silver=2, gold=3), summed across all stored best results:

```
totalMedalRank(progress) = Σ progress.bestResultsByStageId.values.map((r) => r.medal.rank)
```

Range: 0 (no clears) to 21 (all seven stages gold-medaled). No new persistent state is added to track earned points — they are always recomputed from current medal ranks.

### Derived bank (recommended approach)

The unspent-points balance is **derived**, not stored:

```
unspentPoints(progress) = max(0, totalMedalRank(progress) − totalSpent)
```

- `totalSpent` recomputes from the **current** `GameBalance` costs of the purchased set.
- A future cost-tweak that makes `totalSpent > totalMedalRank` clamps the bank at 0; the player earns more medals to buy again. **No auto-refund machinery** (would require transaction history we deliberately avoid persisting).
- Medal-rank tuning changes propagate cleanly to existing saves (a future bump from rank 3 to 4 for gold retroactively grants a point).
- Only the **purchased set** is persisted (one list of IDs), keeping the new state surface minimal.

### Extended `CampaignModifiers`

`CampaignModifiers` (in `campaign_progress.dart`) gains three fields for the tower-stat / economy upgrades. Side-stage rewards and tech-tree bonuses continue to add into the existing `bonusGold` / `bonusHealth` fields (stackable):

```dart
class CampaignModifiers {
  final int bonusGold;            // HPA-94 side-stage + Solar Capacitors
  final int bonusHealth;          // HPA-94 side-stage + Hardened Core
  final bool hasChallengeBadge;   // HPA-94 only
  // NEW (tech tree) — additive fractions, NOT multipliers:
  final double clearBonusFraction;   // +0.25 if Salvage Crew
  final double laserDamageFraction;  // +0.10 if Laser Tuning
  final double cryoSlowDurationBonus; // +0.30 if Cryo Coolant

  int get adjustedStartingGold       => GameBalance.startingGold       + bonusGold;
  int get adjustedStartingBaseHealth => GameBalance.initialBaseHealth  + bonusHealth;

  static const CampaignModifiers empty = CampaignModifiers();

  static CampaignModifiers fromProgress(
    CampaignProgress progress,
    Iterable<StageDefinition> stages,
    CampaignTechTree techTree,        // NEW required parameter
  );
}
```

The first two new fields are named `*Fraction` (not `*Multiplier`) because they are additive fractions applied as `(1 + fraction)`, not standalone multipliers. This avoids the mis-application trap of writing `* clearBonusMultiplier` and silently getting 0.25× gold. `cryoSlowDurationBonus` keeps its name because it is an additive duration, not a fraction.

`fromProgress` accumulates HPA-94 side-stage rewards **and** tech-tree effects into the same fields:

- For each cleared side stage with `CampaignReward.bonusGold`: add `GameBalance.salvageRiftGoldBonus`. (Existing behavior.)
- For each cleared side stage with `CampaignReward.bonusHealth`: add `GameBalance.voidBastionHealthBonus`. (Existing behavior.)
- `hasChallengeBadge`: every side stage cleared. (Existing behavior.)
- If `techTree.isPurchased(CampaignTechUpgrade.solarCapacitors)`: add `GameBalance.solarCapacitorsGoldBonus` to `bonusGold`.
- If `techTree.isPurchased(CampaignTechUpgrade.hardenedCore)`: add `GameBalance.hardenedCoreHealthBonus` to `bonusHealth`.
- If `techTree.isPurchased(CampaignTechUpgrade.salvageCrew)`: set `clearBonusFraction = GameBalance.salvageCrewClearBonusFraction`.
- If `techTree.isPurchased(CampaignTechUpgrade.laserTuning)`: set `laserDamageFraction = GameBalance.laserTuningDamageFraction`.
- If `techTree.isPurchased(CampaignTechUpgrade.cryoCoolant)`: set `cryoSlowDurationBonus = GameBalance.cryoCoolantSlowDurationBonus`.

### `GameBalance` constants

Add to `GameBalance` in `lib/game/models/game_models.dart`:

```dart
// Tech-tree upgrade costs (total = 20; max medal rank = 21, intentional 1-pt slack)
static const int solarCapacitorsCost = 3;
static const int hardenedCoreCost     = 4;
static const int salvageCrewCost      = 4;
static const int laserTuningCost      = 4;
static const int cryoCoolantCost      = 5;

// Tech-tree upgrade magnitudes (fractions are additive, not multipliers)
static const int    solarCapacitorsGoldBonus         = 15;
static const int    hardenedCoreHealthBonus          = 3;
static const double salvageCrewClearBonusFraction    = 0.25;
static const double laserTuningDamageFraction        = 0.10;
static const double cryoCoolantSlowDurationBonus     = 0.30;
```

These follow the existing "all tuning lives in `GameBalance`" convention.

## Application of Upgrades

### Starting gold / health (existing path, no new plumbing)

`OrionDefenseGame` already accepts `CampaignModifiers?` and threads `adjustedStartingGold` / `adjustedStartingBaseHealth` into `GameSession.initial(gold:, baseHealth:)`. Solar Capacitors and Hardened Core ride this existing path; HPA-94's `damageBase` clamp and `restart()` boundary (which already use `startingBaseHealth`) keep working without further changes.

### Wave-clear bonus (new application point)

At `game_session.dart:235`, wave-clear gold is credited:

```dart
_gold += completedWave?.clearBonus ?? 0;
```

This becomes:

```dart
final waveBonus = completedWave?.clearBonus ?? 0;
_gold += (waveBonus * (1 + modifiers.clearBonusFraction)).round();
```

**Scope note (issue #8 from review):** `finishActiveWave` returns early when transitioning to `GamePhase.won` (line 230–233), so the `clearBonus` credit only runs on waves 1–7. Wave 8's `clearBonus` is already 0 by design (`orion_campaign.dart:474`). Salvage Crew therefore affects intermediate waves only — this is the intended scope. Tests should assert the multiplier applies to a wave-3 (or similar) clear, not the final wave.

### `GameSession` signature change

`GameSession.initial` currently accepts optional `gold` / `baseHealth` overrides (HPA-94) but discards the modifiers object after computing starting values. It gains the modifiers object as a first-class field:

```dart
GameSession.initial({
  StageDefinition? stage,
  CampaignModifiers modifiers = CampaignModifiers.empty, // NEW
  int? gold,        // kept for test back-compat; defaults to modifiers.adjustedStartingGold
  int? baseHealth,  // kept for test back-compat; defaults to modifiers.adjustedStartingBaseHealth
}) : stage = stage ?? OrionCampaign.stageOne,
     startingGold = gold ?? modifiers.adjustedStartingGold,
     startingBaseHealth = baseHealth ?? modifiers.adjustedStartingBaseHealth,
     modifiers = modifiers { ... }

final CampaignModifiers modifiers;
```

Both application sites (starting gold/health, wave-clear bonus) read from this stored field. `OrionDefenseGame`'s constructor passes the resolved modifiers through; existing tests that construct `GameSession.initial()` without modifiers continue to work (defaults to `CampaignModifiers.empty`).

### Laser damage and Cryo slow (baked into `TowerStats`)

`CombatEffects.resolveDamage` and `CombatEffects.mergeSlow` are **pure** and must stay pure. The damage path today is:

```
ProjectileComponent / GravityFieldComponent / DroneComponent
  → enemy.applyDamage(stats.damage) / applySlow(...)
  → CombatEffects.resolveDamage / mergeSlow
```

The enemy-side `applyDamage(amount)` / `applySlow({multiplier, duration})` APIs (verified at `enemy_component.dart:125, 157`) carry **no source-tower-type information**. There are many damage call sites — direct projectile hits, splash, pierce, chain, prism-split, cluster-burst, gravity-field ticks, drone attacks (`projectile_component.dart` alone has ~9 branches). Filtering "when source is laser/cryo" at each call site would scatter the modifier logic across half a dozen branches and miss any future damage path.

**Decision: bake the laser/cryo tech-tree modifiers into `TowerStats` at the runtime-stats resolution site, NOT on the `PlacedTower` record.** This covers every damage path automatically because they all read from the same resolved `TowerStats`.

**Correction from review (issue #1, round 2):** `PlacedTower` (defined at `game_models.dart:287-302`) is a pure data record with fields `id`, `type`, `position`, `level`, `specialization`, `targetingMode` — it has **no `stats` field**. The runtime `TowerStats` live on `TowerComponent.stats` (and are passed by reference to `ProjectileComponent.stats`, `GravityFieldComponent.stats`, `DroneComponent.stats`). Combat code reads `tower.stats` where `tower` is a `TowerComponent` — never a `PlacedTower`.

**Concrete mechanism (issue #3, round 3):** `TowerComponent` resolves `GameBalance.towerStats(...)` in **two** places today — the constructor (`tower_component.dart:25`) and `updateTower` (`tower_component.dart:53`, hit by upgrade at `orion_defense_game.dart:204`, specialize at `:225`, targeting-mode change at `:282`). Neither has access to `CampaignModifiers`. The plan:

1. Add a `final CampaignModifiers modifiers` field to `TowerComponent` (defaults to `CampaignModifiers.empty`).
2. Both resolution sites call a new private method `_resolveStats(PlacedTower tower)`:
   ```dart
   TowerStats _resolveStats(PlacedTower tower) {
     final base = GameBalance.towerStats(
       tower.type,
       level: tower.level,
       specialization: tower.specialization,
     );
     if (tower.type == TowerType.laser && modifiers.laserDamageFraction > 0) {
       return base.copyWith(
         damage: base.damage * (1 + modifiers.laserDamageFraction),
       );
     }
     if (tower.type == TowerType.cryo && modifiers.cryoSlowDurationBonus > 0) {
       return base.copyWith(
         slowDuration: base.slowDuration + modifiers.cryoSlowDurationBonus,
       );
     }
     return base;
   }
   ```
   (`TowerStats.copyWith` already exists at `game_models.dart:343` for `targetingMode`; extend it to cover `damage` and `slowDuration`, or construct a fresh `TowerStats` via the existing private factory — implementation-plan call.)
3. `_addTowerComponent` (`orion_defense_game.dart:426`) threads the active modifiers into the `TowerComponent` constructor: `modifiers: modifiers ?? CampaignModifiers.empty` (the game's `modifiers` field is nullable — see "Nullability" below).
4. `updateTower` re-runs `_resolveStats` on the new `PlacedTower`, so upgrading or specializing a laser/cryo tower re-applies the multiplier to the new base stats.

The bonus applies for the tower's lifetime. Specializing or upgrading re-resolves stats and re-applies the bonus. `PlacedTower` is unchanged.

**Why not at projectile/enemy call sites:** the reviewer's Option B (apply in `ProjectileComponent` before `applyDamage`) requires touching every damage branch and would miss gravity-field ticks and drone attacks. Option C (pass `TowerType` into `applyDamage`) pollutes a general enemy API. Baking into the resolved `TowerStats` via a `_resolveStats` resolver is the only option that covers all damage paths (projectile direct/splash/pierce/chain, prism-split, cluster-burst, gravity ticks, drone) with one resolver called from two sites.

**Nullability (issue #4, round 3):** `OrionDefenseGame.modifiers` is `CampaignModifiers?` (declared at `orion_defense_game.dart:51`). The new `GameSession.initial({CampaignModifiers modifiers = CampaignModifiers.empty})` parameter is non-null. The pass-through at the `OrionDefenseGame` constructor must coerce: `GameSession.initial(modifiers: modifiers ?? CampaignModifiers.empty, ...)`. The same coercion happens at `_addTowerComponent` when threading into `TowerComponent`.

### What stays unchanged

- `CombatEffects` API (pure, no tower-type awareness).
- HPA-94's `damageBase` clamp and `restart()` semantics (both use the session's effective `startingBaseHealth`).
- HPA-94's optimistic in-memory progress update with rollback on save failure.
- Side-stage reward activation (unlocks still derive from `isCleared`).
- `GameSession.initial`'s existing `gold` / `baseHealth` override parameters (kept for test back-compat; now default to the modifiers-derived values when omitted).
- `EnemyComponent.applyDamage` / `applySlow` signatures (no new parameters).

## Save Flow

HPA-94 established a save pipeline in `_OrionGamePageState` with three pieces of machinery: `_saveQueue` (serializes saves), `_progressGeneration` (rejects stale saves after a reset), and `_isSavingProgress` (blocks stage launch while a save is in flight). It also established two non-obvious invariants that any unified helper **must** preserve (verified against the current `_saveStageCompletion` at `orion_game_page.dart:196-275`):

1. **`_isSavingProgress` clears in a `finally` block, not inside the success branch.** Otherwise a generation-mismatch early return leaves `_isSavingProgress = true` forever and permanently locks stage launch and purchases.
2. **A successful save that hits a generation mismatch must trigger `_resetStoreAfterStaleSave(store)`.** The generation check only guards in-memory state — the disk write may still have completed with pre-reset data, so the store must be reset to match the post-reset in-memory state. Failure to do this leaks stale data across resets.

Tech-tree purchases **must** reuse this same pipeline. Running a parallel save chain for purchases would race with stage-completion saves, restore a stale `_techTree` after a failed save, or let a mission start while a purchase is still rolling back.

### Field-scoped unified helper

The helper takes **optional** `nextProgress` and `nextTechTree`. Each call touches only the field(s) it provides; the other field passes through unchanged. This is the key to safe rollback when stage-completion and tech-purchase saves are queued behind each other (issue #4, round 2).

```dart
Future<void> _persistSave({
  CampaignProgress? nextProgress,
  CampaignTechTree? nextTechTree,
}) async {
  final store = _store;
  if (store == null) {
    _showCampaignPersistenceFailure(); // view-routed; see Feedback routing below
    return;
  }

  final saveGeneration = _progressGeneration;
  final priorProgress = _progress;     // captured BEFORE optimistic update
  final priorTechTree = _techTree;     // captured BEFORE optimistic update

  // Optimistic update scoped to provided fields. Disposal-safety: HPA-94
  // (commit 700cef1) established that stage-win callbacks can fire after the
  // page is disposed; bare fields must still update so queued saves derive
  // from current state, but setState must be guarded. The same regression
  // test (widget_test.dart around the queued-save-after-disposal case)
  // covers the new helper.
  if (nextProgress != null) _progress = nextProgress;
  if (nextTechTree != null) _techTree = nextTechTree;
  _isSavingProgress = true;
  if (mounted) {
    setState(() {});
  }

  final saveTask = _saveQueue.then((_) async {
    if (saveGeneration != _progressGeneration) {
      return; // stale; do not write
    }
    await store.save(CampaignSave(progress: _progress, techTree: _techTree));
  });
  _saveQueue = saveTask.catchError((_) {});

  try {
    await saveTask;
    // Post-stale-save reset (issue #3, round 2): if a reset happened during
    // the save, the disk write may have landed with pre-reset data. Wipe the
    // store to match the post-reset in-memory state. Preserves the existing
    // _resetStoreAfterStaleSave behavior and its failed-reset feedback path.
    if (saveGeneration != _progressGeneration) {
      await _resetStoreAfterStaleSave(store);
    }
  } catch (_) {
    if (!mounted || saveGeneration != _progressGeneration) {
      return;
    }
    // Scoped rollback (issue #4, round 2): only the field(s) this save
    // provided are restored. A stage-completion save does not clobber a
    // concurrent tech-purchase save's optimistic update, and vice versa.
    if (nextProgress != null) _progress = priorProgress;
    if (nextTechTree != null) _techTree = priorTechTree;
    if (mounted) {
      setState(() {});
    }
    _showCampaignPersistenceFailure();
  } finally {
    // _isSavingProgress MUST clear in finally (issue #2, round 2). The
    // generation check prevents stomping a newer save's flag.
    if (saveGeneration == _progressGeneration) {
      _isSavingProgress = false;
      if (mounted) setState(() {});
    }
  }
}
```

**Why field-scoped rollback is safe:** saves serialize through `_saveQueue`, so writes are totally ordered. The disk's final state is whatever the last successful write produced. Each save's optimistic update applies immediately at call time, but the actual `store.save` captures in-memory state at fire time — so a queued save behind another picks up the earlier save's optimistic update. On failure, rolling back only the field this save touched leaves any newer queued save's update intact.

### Single queueing point (issue #2, round 3)

The helper does its own `_saveQueue.then(...)` internally, so it is the **sole** queueing point. The HPA-94 `_recordStageCompletion` wrapper (which also wrapped `_saveQueue.then(...)`) is dropped — stage completion calls `_persistSave(nextProgress:)` directly from the `onStageWon` handler. Layering the two would double-queue the stage write and produce inconsistent optimistic-update timing (call-time vs fire-time) between writers. The sibling-save serialization behavior tested at `widget_test.dart:442` is preserved because the underlying `_saveQueue` serialization still holds; the test's setup migrates from `_recordStageCompletion` to the new entry point.

### All `CampaignSave` writers

After the store API change, every save site writes a `CampaignSave` aggregate. There are exactly four writers:

1. **Load (app start / `initState`):** `final save = await store.load(); _progress = save.progress; _techTree = save.techTree;`. Decodes both pieces from one JSON blob.
2. **Stage completion (`_saveStageCompletion`, ~line 205):** the existing `_recordStageCompletion` queueing wrapper is dropped (see "Single queueing point" above); the `onStageWon` handler calls `_persistSave(nextProgress: newProgress)` directly. No `nextTechTree`, so `_techTree` is untouched and a failed stage save cannot roll back a concurrent tech purchase.
3. **Tech-tree purchase (`_purchaseTech`):** `_persistSave(nextTechTree: newTechTree);` — no `nextProgress`, so a failed purchase cannot roll back a concurrent stage-completion save.
4. **Campaign reset (`_confirmResetCampaign`, ~line 339):** `_progressGeneration++;` then `await store.reset();` then `setState(() { _progress = CampaignProgress(); _techTree = CampaignTechTree(); _activeView = _ShellView.worldMap; _activeStage = null; _game = null; });`. Reset intentionally clears both progress and tech tree (the player is wiping the whole campaign). The generation bump invalidates any in-flight save from either writer; the post-stale-save reset (issue #3) wipes any disk write that races with the reset. Failed-reset feedback path preserved (`_resetStoreAfterStaleSave` → `_mapFeedback = 'Could not reset campaign progress.'`).

### Tech-tree purchase handler

```dart
void _purchaseTech(CampaignTechUpgrade upgrade) {
  if (_isSavingProgress) {
    return; // block concurrent saves; matches stage-launch guard
  }
  final newTechTree = _techTree.purchase(upgrade, _progress);
  _persistSave(nextTechTree: newTechTree);
}
```

The optimistic `setState` inside `_persistSave` updates `_techTree` before the await; scoped rollback restores `priorTechTree` on failure.

### Feedback routing (issue #5, round 2; issue #4, round 3)

`_store` is nullable (`CampaignProgressStore? _store` at `orion_game_page.dart:32`) — the helper must guard. The existing `_showCampaignPersistenceFailure` (`orion_game_page.dart:363-374`) **always** sets `_mapFeedback`, and **additionally** calls `game.overrideFeedback(message)` when a stage is active. This dual-targeting is deliberate: a save failure during stage play leaves a breadcrumb on the map for when the player returns, and shows the feedback in the active game immediately. The tech tree view needs the same dual-targeting when a purchase save fails.

The new router preserves the existing map-always-gets-a-breadcrumb behavior and adds tech-tree routing:

```dart
void _showCampaignPersistenceFailure() {
  const message = 'Could not save campaign progress.';
  final game = _game;
  setState(() {
    _mapFeedback = message; // always; preserves HPA-94 behavior
    if (_activeView == _ShellView.techTree) {
      _techTreeFeedback = message; // immediate feedback in the tech tree panel
    }
  });
  if (_activeView == _ShellView.stage && game != null) {
    game.overrideFeedback(message); // immediate feedback in the active game
  }
}
```

A new `_techTreeFeedback` field on `_OrionGamePageState` is consumed by `TechTreeView`. The field clears on the next successful purchase or on navigation away from the tech tree view. The map breadcrumb behavior is unchanged from HPA-94 — no existing test regresses.

The optimistic update inside `_persistSave` updates `_techTree` before the await; scoped rollback restores `priorTechTree` on failure. This reuses the exact discipline HPA-94 established for `_progress` saves.

## Persistence

### Codec version 3

`CampaignProgressCodec.encode` / `decode` (in `campaign_progress_store.dart`) bumps to version 3:

```json
{
  "version": 3,
  "stageResults": { "outpost-alpha": {"medal": "gold", "bestBaseHealth": 20}, ... },
  "techPurchases": ["cryo-coolant", "laser-tuning", "solar-capacitors"]
}
```

- `techPurchases` is a sorted list of upgrade IDs. Sorted for deterministic output; IDs are stable across enum reordering (the enum carries `id` getters, not ordinal-based encoding).
- The store API changes to carry both pieces of state together:

  ```dart
  abstract class CampaignProgressStore {
    Future<CampaignSave> load();
    Future<void> save(CampaignSave save);
    Future<void> reset();
  }

  class CampaignSave {
    final CampaignProgress progress;
    final CampaignTechTree techTree;
    const CampaignSave({required this.progress, required this.techTree});
  }
  ```

  Both `SharedPreferencesCampaignProgressStore` and `InMemoryCampaignProgressStore` update. `OrionGamePage` reads/writes via `CampaignSave`. The aggregate is the right call because the two are saved atomically under one SharedPreferences key and the codec already produces one JSON blob — keeping two separate load/save methods would invite save-tearing bugs.

### Migration

- `version == 3`: decode `stageResults` (unchanged from v2) and `techPurchases` (drop unknown IDs silently for forward-compat).
- `version == 2`: decode `stageResults`, default `techPurchases = []`.
- `version == 1`: existing v1 path (clearedStageIds → `StageResult.clear` with `bestBaseHealth: 0`); `techPurchases = []`.
- Missing `techPurchases` field on an otherwise-v3 save: treated as empty list.
- **Any other version (future v4+, or corrupt data):** return an empty `CampaignSave` (both progress and tech tree empty). This is the existing policy for unknown versions and is preserved.

### Backward compatibility

The app has not launched (per HPA-94 spec), so there are no live v2 players to regression-test. The v2 → v3 migration is exercised by a codec unit test.

## UI

### New file: `lib/game/ui/tech_tree_view.dart`

A full-screen panel reached from the world map. Layout:

- **Header row:** "Campaign Tech Tree" title, medal-points bank readout, and a back button. The bank readout shows all three numbers so the derived-bank model (and the cost-tweak clamp) is legible:

  ```
  Unspent: 9 · Earned: 12 · Spent: 3
  ```

  `Earned` is `totalMedalRank(_progress)`; `Spent` is `_techTree.totalSpent`; `Unspent` is `_techTree.unspentPoints(_progress)` (i.e. `max(0, earned − spent)`). When `spent > earned` (only possible after a cost-tweak in a future release), `Unspent` shows 0 and the player can read why from the other two numbers.
- **Body:** `ListView` of five `_UpgradeRow` widgets, one per `CampaignTechUpgrade`. Each row shows:
  - Name (`label`) and one-line `description`.
  - `effectLabel` (e.g., `+15 Starting Gold`, `+10% Laser Damage`).
  - Cost (e.g., `Cost: 4 pts`).
  - State badge and primary action:
    - **Purchased** — disabled chip, no action.
    - **Purchase** (affordable: `unspentPoints >= cost` and not yet purchased) — filled button; tap triggers the purchase flow.
    - **Locked** (`unspentPoints < cost`) — disabled button showing `Need N more points`.
- **Post-purchase:** the row re-renders as Purchased; the header bank decrements; subsequent rows re-evaluate their state. All updates flow through `setState` on the parent — the panel itself remains stateless beyond the purchase callback.

### Visibility of combat upgrades (issue #9 from review)

Solar Capacitors, Hardened Core, and Salvage Crew produce numbers the player sees immediately (starting gold/HP HUD; per-wave clear bonus). Laser Tuning and Cryo Coolant produce per-shot damage/slow deltas that are easy to miss in the heat of combat.

For MVP scope, visibility of the two combat upgrades is satisfied by:
- The `effectLabel` in the tech-tree panel row (`+10% Laser Damage`, `+0.3s Cryo Slow`).
- The pure-logic and combat-application tests that assert the modifier changes the resolved `TowerStats`.

No in-mission HUD indicator (e.g. "Active upgrades" chip) ships in MVP. If playtesting finds the combat upgrades feel invisible, that's a follow-up.

### World map entry point

`WorldMapView` gains:

- A new `onOpenTechTree: VoidCallback?` parameter (wired by `OrionGamePage`).
- A "Tech Tree" button in the header (next to the campaign-complete banner, or directly below it). The button is always visible — the tech tree is open from the start of the campaign.

### Navigation state in `_OrionGamePageState`

The existing shell routes on `_activeStage == null` (world map) vs `_activeStage != null` (mission). Extending with a third view via a parallel `_showWorldMap` flag would desync from `_activeStage` and `_game`. Instead, replace the implicit routing with an explicit enum:

```dart
enum _ShellView { worldMap, techTree, stage }

_ShellView _activeView = _ShellView.worldMap;
StageDefinition? _activeStage;     // non-null iff _activeView == _ShellView.stage
OrionDefenseGame? _game;            // non-null iff _activeView == _ShellView.stage
```

- World-map "Tech Tree" button: `setState(() { _activeView = _ShellView.techTree; });`.
- Tech-tree panel back button: `setState(() { _activeView = _ShellView.worldMap; });`.
- Stage launch (`_startStage`): `setState(() { _activeStage = stage; _game = game; _activeView = _ShellView.stage; });`.
- Return-to-map (`_returnToMap`, restart-with-different-stage): `setState(() { _activeStage = null; _game = null; _activeView = _ShellView.worldMap; });`.
- Reset (`_confirmResetCampaign`): as above after `store.reset()`.
- `build()` switches on `_activeView`. The existing `_activeStage != null` checks migrate to `_activeView == _ShellView.stage` (or simply `_activeStage != null && _game != null` if the test surface depends on it — the migration is mechanical).

The Tech Tree view receives `_progress`, `_techTree`, and an `onPurchase(CampaignTechUpgrade)` callback. It does not mutate state directly.

## Error Handling

- **New player** (empty `CampaignProgress`): `totalMedalRank == 0`, `unspentPoints == 0`, no upgrades affordable. Bank readout shows `Unspent: 0 · Earned: 0 · Spent: 0`. Safe.
- **Corrupt `techPurchases` list** (unknown IDs): dropped silently on decode; known IDs preserved.
- **Save failure on purchase or stage completion:** the unified `_persistSave` helper rolls back both `_progress` and `_techTree` to their prior values; existing save-failure feedback shown. The generation check prevents a stale save from overwriting fresh state after a reset.
- **Race between purchase and stage completion:** both writers go through `_persistSave` → `_saveQueue`, so saves serialize. `_isSavingProgress` blocks stage launch and further purchases while a save is in flight.
- **Overdrawn bank from a future cost tweak:** `unspentPoints` clamped at 0 via `max(0, ...)`. Bank readout still shows the true `Earned` and `Spent` so the player can see why. Player earns more medals to buy again. No auto-refund.
- **Missing `techPurchases` field on a v3 save:** treated as empty list.
- **Unknown codec version** (future v4+ or corrupt): empty `CampaignSave` returned (existing policy).
- **Empty `CampaignTechTree`** passed to `CampaignModifiers.fromProgress`: behaves exactly like HPA-94 (regression-safe — `fromProgress` defaults the new fields to 0).
- **Invalid persisted progress**: still discarded safely by the existing codec.

## Testing Strategy

### Pure logic — `CampaignTechTree`

- `unspentPoints` for empty progress = 0.
- `unspentPoints` for all-clear (7 stages × rank 1) = 7.
- `unspentPoints` for all-gold (7 stages × rank 3) = 21.
- `unspentPoints` reflects partial purchases (e.g., 12 earned − 3 spent = 9).
- `canPurchase` returns `false` when upgrade already purchased.
- `canPurchase` returns `false` when `unspentPoints < cost`.
- `canPurchase` returns `true` when affordable and not yet purchased.
- `purchase` returns a new instance containing the upgrade; original unchanged.
- `purchase` on an unaffordable upgrade throws `ArgumentError`.
- **Overdrawn edge case:** constructing a `CampaignTechTree.fromIdList` whose `totalSpent > totalMedalRank(progress)` returns `unspentPoints == 0` (clamped).
- Serialization round-trip: `toIdList` → `fromIdList` preserves the set; unknown IDs dropped; order normalized.

### Pure logic — `CampaignModifiers.fromProgress`

- With `solarCapacitors` purchased: `bonusGold` includes `+solarCapacitorsGoldBonus` (15) on top of any side-stage bonus.
- With `hardenedCore` purchased: `bonusHealth` includes `+hardenedCoreHealthBonus` (3) on top of any side-stage bonus.
- With `salvageCrew` purchased: `clearBonusFraction == salvageCrewClearBonusFraction` (0.25).
- With `laserTuning` purchased: `laserDamageFraction == laserTuningDamageFraction` (0.10).
- With `cryoCoolant` purchased: `cryoSlowDurationBonus == cryoCoolantSlowDurationBonus` (0.30).
- **Stacking:** side-stage reward (HPA-94) + matching tech-tree upgrade both add into the same `bonusGold` / `bonusHealth` field (e.g., Salvage Rift cleared + Solar Capacitors purchased → `bonusGold == 30 + 15 == 45`).
- Empty tech tree + empty progress → `CampaignModifiers.empty` (regression with HPA-94).
- Empty tech tree + Salvage Rift cleared → HPA-94 behavior unchanged (regression).

### `GameSession` application

- Starting gold/health reflect tech-tree bonuses via existing override path.
- **Wave-clear bonus** with `salvageCrew` purchased: clearing an intermediate wave credits `round(clearBonus * (1 + 0.25))` gold (e.g., 30 → 38, 40 → 50, 65 → 81). Test against a wave-3 clear, **not** the final wave — `finishActiveWave` returns early on the last wave before crediting `clearBonus`, and wave 8's `clearBonus` is already 0 (issue #8 from review).
- **Wave-clear bonus** without `salvageCrew`: unchanged (regression).
- `restart()` preserves the session's modifiers (regression on HPA-94's restart boundary).
- `GameSession.modifiers` field exposes the stored modifiers for combat application.

### Combat application (`_resolveStats` resolver — round-2 issue #1; round-3 issue #3)

Because the laser/cryo modifiers are baked into the resolved `TowerStats` via a single `_resolveStats` method on `TowerComponent` (see "Laser damage and Cryo slow" under Application of Upgrades), the combat-application tests target both call sites of the resolver — the constructor and `updateTower` — plus end-to-end damage verification:

- **Place a laser tower** with `laserTuning` purchased → resolved `TowerStats.damage == baseDamage * (1 + 0.10)`. Without `laserTuning` → `damage == baseDamage` (regression).
- **Place a cryo tower** with `cryoCoolant` purchased → resolved `TowerStats.slowDuration == baseSlowDuration + 0.30`. Without `cryoCoolant` → `slowDuration == baseSlowDuration` (regression).
- **Upgrade a laser tower** (level 1 → 2, exercises `updateTower`) with `laserTuning` purchased → the re-resolved `damage` includes the `(1 + 0.10)` multiplier on top of the new base.
- **Specialize a laser tower** (e.g. into `pulseLaser`, exercises `updateTower`) with `laserTuning` purchased → specialization re-resolves stats and the multiplier is reapplied.
- **Retarget a laser tower** (change `targetingMode`, the third `updateTower` call site at `orion_defense_game.dart:282`) with `laserTuning` purchased → multiplier still applied (no regression from the targeting-mode change).
- **Place a non-laser, non-cryo tower** (`rocket`, `railgun`, `ionChain`, `nanite`, `gravityWell`, `droneBay`) with both combat upgrades purchased → `damage` and `slowDuration` unchanged (only the matching tower type is affected).
- **End-to-end damage verification:** with `laserTuning` purchased, a laser-tower projectile's `stats.damage` (read inside `ProjectileComponent` / `GravityFieldComponent` / `DroneComponent`) carries the multiplier; the enemy's resolved health after `applyDamage` reflects it.
- **Modifiers field default:** constructing `TowerComponent` without a modifiers argument → behavior identical to today (regression). The default `CampaignModifiers.empty` is a no-op in `_resolveStats`.
- **Nullability coercion:** `OrionDefenseGame(modifiers: null)` → `GameSession.initial` receives `CampaignModifiers.empty`; `_addTowerComponent` threads `CampaignModifiers.empty` to `TowerComponent` (round-3 issue #4).

`CombatEffects` itself is not modified and its existing tests remain green. The damage-path components (`ProjectileComponent`, `GravityFieldComponent`, `DroneComponent`) are unchanged — they read `stats.damage` / `stats.slowDuration` as today; the bonus is already baked in at `_resolveStats`.

### Save flow (`_persistSave` unified helper — round-2 review issues #2, #3, #4; round-3 issues #1, #2)

- **Stage completion save:** trigger a stage win → `_progress` and `_techTree` both persisted; reload returns both intact. A pre-existing tech tree is not wiped by a stage win.
- **Tech-tree purchase save:** trigger a purchase → `_techTree` persists; reload returns the new tree. A pre-existing progress is not wiped by a purchase.
- **Race serialization (regression of HPA-94 test at `widget_test.dart:442`):** fire a stage-completion save and a tech-purchase save in quick succession → both serialize through `_saveQueue`; final reloaded state matches the last write; **sibling queued saves do not roll each other back** (issue #4 round 2). The test setup migrates from `_recordStageCompletion` to `_persistSave(nextProgress:)` (issue #2 round 3 — the old wrapper is dropped, single queueing point).
- **Cross-writer rollback:** queue a stage save, then queue a tech-purchase save; inject failure in the stage save only → `_progress` rolls back to its prior, `_techTree` remains at the new value (not clobbered by the stage save's field-scoped rollback).
- **Disposal safety (regression of HPA-94 commit 700cef1, round-3 issue #1):** dispose the page while a save is in flight → bare `_progress` / `_techTree` / `_isSavingProgress` still update (no `setState after dispose` throw); the queued save derives from the latest in-memory state; reload returns the latest values. Verified by the existing 700cef1 regression test, extended to cover a tech-purchase save.
- **`_isSavingProgress` clears on generation mismatch (issue #2 round 2):** trigger a reset mid-save; verify `_isSavingProgress` returns to `false` afterward (no permanent UI lock).
- **`_isSavingProgress` blocks:** while a save is in flight, stage launch (`_startStage`) and further purchases (`_purchaseTech`) are rejected (verify via a flag check, not by actual race timing).
- **Save failure on purchase:** inject a failing store → `_techTree` rolls back to prior instance; `_mapFeedback` AND `_techTreeFeedback` both set (dual-targeting, round-3 issue #4).
- **Save failure on stage completion:** inject a failing store → `_progress` rolls back to prior instance (regression of HPA-94 behavior); `_mapFeedback` always set, `_game.overrideFeedback` additionally called when stage view is active.
- **Stale-save reset (regression of HPA-94 test at `widget_test.dart:701`, issue #3 round 2):** start a save, then trigger `_confirmResetCampaign` → in-flight save succeeds on disk with pre-reset data → post-stale-save reset wipes the store → reloaded returns empty progress AND empty tech tree.
- **Reset failure:** inject a failing `store.reset()` → `_mapFeedback = 'Could not reset campaign progress.'` (preserve existing behavior).
- **Null store:** `_store == null` → `_persistSave` shows persistence failure and returns without throwing.

### Persistence

- **Codec v3 round-trip:** encode `CampaignSave(progress, techTree)` → decode → both `progress` and `techTree` fields match inputs.
- **v2 → v3 migration:** decode a v2-shaped JSON string → `techPurchases == []`, `stageResults` decoded correctly.
- **v1 path regression:** decode a v1-shaped JSON string → `techPurchases == []`, v1 stage-id migration intact.
- **Unknown `techPurchases` IDs dropped:** decode a raw JSON string containing a future/unknown ID alongside known IDs → unknown ID absent, known IDs preserved. (Encode-via-enum cannot produce an unknown ID since the enum is closed; the test must construct raw JSON and pass it to `CampaignProgressCodec.decode` directly.)
- **Missing `techPurchases` field** on a v3-shaped JSON: decode → empty tech tree.
- **Unknown codec version (e.g. 99):** decode → empty `CampaignSave` (both fields empty).
- **Store round-trip** (`InMemoryCampaignProgressStore`): save a `CampaignSave` with both progress + tech tree → reload → verify both intact (covers the "persists across app restarts" acceptance criterion).

### Store interface migration (issue #11 from review)

The `CampaignProgressStore` signature change touches every implementor and caller. The implementation plan must update all of these — not just the codec tests:

- `CampaignProgressStore` (abstract interface) — `load()` returns `CampaignSave`; `save(CampaignSave)`.
- `SharedPreferencesCampaignProgressStore` — encode/decode `CampaignSave`.
- `InMemoryCampaignProgressStore` — hold a `CampaignSave` (or the source string, decoded on load).
- `_TestCampaignProgressStore` in `test/widget_test.dart` (line 1303) — implement against the new interface.
- All `store.save(progress)` call sites in `test/widget_test.dart` (15+ uses of `_TestCampaignProgressStore` and `InMemoryCampaignProgressStore`).
- All `store.save(progress)` / `store.load()` call sites in `test/game/campaign_progress_store_test.dart` (lines 140, 175, 261, 1129, 1195, 1229, etc.).
- `_OrionGamePageState` in `lib/game/ui/orion_game_page.dart` — read/write via `CampaignSave` through the unified `_persistSave` helper.

The migration is mechanical (wrap/unwrap `CampaignSave`) but high-touch; the implementation plan should sequence it before the new application logic so the build stays green at each step.

### Widget

- `TechTreeView` renders all five upgrade rows with correct name, effect, cost.
- Header bank displays the correct three-number readout: `Unspent: X · Earned: Y · Spent: Z`.
- A purchased upgrade shows "Purchased" state (disabled).
- An affordable upgrade shows "Purchase" button (enabled).
- An unaffordable upgrade shows "Locked" with `Need N more points`.
- Tapping an affordable upgrade invokes the purchase callback; the bank decrements; the row re-renders as Purchased; subsequent rows re-evaluate affordability.
- World map shows the "Tech Tree" button; tapping it sets `_activeView = _ShellView.techTree`.
- Tech Tree panel's back button sets `_activeView = _ShellView.worldMap`.
- Existing widget tests pass when tech tree is empty (regression). Any test that asserted on `_activeStage != null` for shell routing migrates to `_activeView == _ShellView.stage`.

## Acceptance Criteria

Mapped to the issue. These describe the end state after implementation:

- [x] **Persistent campaign tech-tree state in progress storage** — codec v3 adds `techPurchases`.
- [x] **At least three purchasable upgrades** — five shipped.
- [x] **Upgrades visibly affect mission start or tower stats** — three at mission start (gold, health, clear-bonus multiplier) and two via resolved `TowerStats` (laser damage, cryo slow). Combat-upgrade visibility is satisfied by panel `effectLabel`s + combat-application tests; no in-mission HUD chip ships in MVP.
- [x] **The player can view purchased and locked upgrades from the campaign map** — full-screen `TechTreeView` reached via a world-map header button.
- [x] **Upgrade purchases persist across app restarts** — codec v3 + `InMemoryCampaignProgressStore` round-trip test.
- [x] **Existing saved progress remains loadable** — v2 → v3 migration defaults `techPurchases = []`.
- [x] **Tests cover purchase validation, persistence, and application to gameplay** — pure-logic, persistence, save-flow (including sibling stage/purchase saves and stale-save reset), session-application, combat-application, and widget tests specified above.

## References

- HPA-94 side-stage rewards spec: `docs/superpowers/specs/2026-07-11-orion-side-stage-campaign-rewards-design.md` (establishes `CampaignModifiers`, the optimistic-save-with-rollback pattern, the `startingBaseHealth` snapshot field, and the v2 codec).
- HPA-100 issue: https://linear.app/cwchanap/issue/HPA-100/add-campaign-wide-tech-tree
