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
| Laser Tuning | +10% damage on `TowerType.laser` towers | 5 |
| Cryo Coolant | +0.3s slow duration on `TowerType.cryo` towers | 5 |

Three economy upgrades + two tower-stat upgrades. Gold/health/clear-bonus take effect at mission start and per-wave; laser/cryo take effect during combat.

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
  // NEW (tech tree):
  final double clearBonusMultiplier;   // +0.25 if Salvage Crew
  final double laserDamageMultiplier;  // +0.10 if Laser Tuning
  final double cryoSlowDurationBonus;  // +0.30 if Cryo Coolant

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

`fromProgress` accumulates HPA-94 side-stage rewards **and** tech-tree effects into the same fields:

- For each cleared side stage with `CampaignReward.bonusGold`: add `GameBalance.salvageRiftGoldBonus`. (Existing behavior.)
- For each cleared side stage with `CampaignReward.bonusHealth`: add `GameBalance.voidBastionHealthBonus`. (Existing behavior.)
- `hasChallengeBadge`: every side stage cleared. (Existing behavior.)
- If `techTree.isPurchased(CampaignTechUpgrade.solarCapacitors)`: add `GameBalance.solarCapacitorsGoldBonus` to `bonusGold`.
- If `techTree.isPurchased(CampaignTechUpgrade.hardenedCore)`: add `GameBalance.hardenedCoreHealthBonus` to `bonusHealth`.
- If `techTree.isPurchased(CampaignTechUpgrade.salvageCrew)`: set `clearBonusMultiplier = GameBalance.salvageCrewClearBonusMultiplier`.
- If `techTree.isPurchased(CampaignTechUpgrade.laserTuning)`: set `laserDamageMultiplier = GameBalance.laserTuningDamageMultiplier`.
- If `techTree.isPurchased(CampaignTechUpgrade.cryoCoolant)`: set `cryoSlowDurationBonus = GameBalance.cryoCoolantSlowDurationBonus`.

### `GameBalance` constants

Add to `GameBalance` in `lib/game/models/game_models.dart`:

```dart
// Tech-tree upgrade costs
static const int solarCapacitorsCost = 3;
static const int hardenedCoreCost     = 4;
static const int salvageCrewCost      = 4;
static const int laserTuningCost      = 5;
static const int cryoCoolantCost      = 5;

// Tech-tree upgrade magnitudes
static const int    solarCapacitorsGoldBonus        = 15;
static const int    hardenedCoreHealthBonus         = 3;
static const double salvageCrewClearBonusMultiplier = 0.25;
static const double laserTuningDamageMultiplier     = 0.10;
static const double cryoCoolantSlowDurationBonus    = 0.30;
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
_gold += (waveBonus * (1 + modifiers.clearBonusMultiplier)).round();
```

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

All four application sites (starting gold/health, wave-clear bonus) read from this stored field. `OrionDefenseGame`'s constructor passes the resolved modifiers through; existing tests that construct `GameSession.initial()` without modifiers continue to work (defaults to `CampaignModifiers.empty`).

### Laser damage and Cryo slow (new application points in `enemy_component.dart`)

`CombatEffects.resolveDamage` and `CombatEffects.mergeSlow` are **pure** and carry no tower-type awareness — they must remain pure and unit-testable. The laser/cryo tech-tree modifiers apply at the call site in `lib/game/components/enemy_component.dart` (lines 136 and 162 respectively), where the source tower type is already known via the projectile:

- **Laser damage** (`enemy_component.dart:136`, before constructing `DamageInput`): when the source projectile's tower type is `TowerType.laser`, multiply the incoming `damage` value by `(1 + modifiers.laserDamageMultiplier)`.
- **Cryo slow** (`enemy_component.dart:162`, when calling `mergeSlow`): when the source projectile's tower type is `TowerType.cryo`, add `modifiers.cryoSlowDurationBonus` to `incomingDuration`.

`EnemyComponent` reads the active modifiers via a `CampaignModifiers` getter on `OrionDefenseGame` (e.g., `game.modifiers`), which already holds the modifiers object. This avoids threading modifiers through every projectile.

### What stays unchanged

- `CombatEffects` API (pure, no tower-type awareness).
- HPA-94's `damageBase` clamp and `restart()` semantics (both use the session's effective `startingBaseHealth`).
- HPA-94's optimistic in-memory progress update with rollback on save failure.
- Side-stage reward activation (unlocks still derive from `isCleared`).
- `GameSession.initial`'s existing `gold` / `baseHealth` override parameters (kept for test back-compat; now default to the modifiers-derived values when omitted).

## Purchase Flow

1. UI invokes `techTree.purchase(upgrade, progress)` → returns a new immutable `CampaignTechTree` with the upgrade added (throws `ArgumentError` if `!canPurchase`).
2. UI calls the `onTechPurchased` callback on `OrionGamePage`.
3. `OrionGamePage` mirrors HPA-94's optimistic-save pattern:
   - Captures `priorTechTree = _techTree`.
   - `setState(() { _techTree = newTechTree; })`.
   - `await store.save(CampaignSave(progress: _progress, techTree: _techTree))` — the codec encodes both together (see Persistence).
   - On failure: if still mounted and the save generation is current, `setState(() { _techTree = priorTechTree; })` and show the existing save-failure feedback.
   - On success: no further state change needed (optimistic update already applied).

This reuses the exact rollback discipline HPA-94 established for `_progress` saves.

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

### Backward compatibility

The app has not launched (per HPA-94 spec), so there are no live v2 players to regression-test. The v2 → v3 migration is exercised by a codec unit test.

## UI

### New file: `lib/game/ui/tech_tree_view.dart`

A full-screen panel reached from the world map. Layout:

- **Header row:** "Campaign Tech Tree" title, medal-points bank (`Medal Points: 12` — the derived `unspentPoints(_progress)`), and a back button.
- **Body:** `ListView` of five `_UpgradeRow` widgets, one per `CampaignTechUpgrade`. Each row shows:
  - Name (`label`) and one-line `description`.
  - `effectLabel` (e.g., `+15 Starting Gold`, `+10% Laser Damage`).
  - Cost (e.g., `Cost: 3 pts`).
  - State badge and primary action:
    - **Purchased** — disabled chip, no action.
    - **Purchase** (affordable: `unspentPoints >= cost` and not yet purchased) — filled button; tap triggers the purchase flow.
    - **Locked** (`unspentPoints < cost`) — disabled button showing `Need N more points`.
- **Post-purchase:** the row re-renders as Purchased; the header bank decrements; subsequent rows re-evaluate their state. All updates flow through `ValueListenableBuilder` / `setState` on the parent — the panel itself remains stateless beyond the purchase callback.

### World map entry point

`WorldMapView` gains:

- A new `onOpenTechTree: VoidCallback?` parameter (wired by `OrionGamePage`).
- A "Tech Tree" button in the header (next to the campaign-complete banner, or directly below it). The button is always visible — the tech tree is open from the start of the campaign.

### Navigation state in `_OrionGamePageState`

The existing view-switching pattern (currently world-map vs. stage) extends to a third view:

```dart
bool _showWorldMap = true;
bool _showTechTree = false; // NEW
StageDefinition? _currentStage;
```

`_returnToMap()` resets both `_showTechTree = false` and `_currentStage = null`. The Tech Tree button's `onOpenTechTree` callback sets `_showWorldMap = false; _showTechTree = true;`. The Tech Tree panel's back button calls `_returnToMap()`.

The Tech Tree view receives `_progress`, `_techTree`, and a `onPurchase(CampaignTechUpgrade)` callback. It does not mutate state directly.

## Error Handling

- **New player** (empty `CampaignProgress`): `totalMedalRank == 0`, `unspentPoints == 0`, no upgrades affordable. Bank displays `0 / 0 earned`. Safe.
- **Corrupt `techPurchases` list** (unknown IDs): dropped silently on decode; known IDs preserved.
- **Save failure on purchase**: optimistic `_techTree` update rolled back to prior instance; existing save-failure feedback shown.
- **Overdrawn bank from a future cost tweak**: `unspentPoints` clamped at 0 via `max(0, ...)`. Player earns more medals to buy again. No auto-refund.
- **Missing `techPurchases` field on a v3 save**: treated as empty list.
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
- With `salvageCrew` purchased: `clearBonusMultiplier == salvageCrewClearBonusMultiplier`.
- With `laserTuning` purchased: `laserDamageMultiplier == laserTuningDamageMultiplier`.
- With `cryoCoolant` purchased: `cryoSlowDurationBonus == cryoCoolantSlowDurationBonus`.
- **Stacking:** side-stage reward (HPA-94) + matching tech-tree upgrade both add into the same `bonusGold` / `bonusHealth` field (e.g., Salvage Rift cleared + Solar Capacitors purchased → `bonusGold == 30 + 15 == 45`).
- Empty tech tree + empty progress → `CampaignModifiers.empty` (regression with HPA-94).
- Empty tech tree + Salvage Rift cleared → HPA-94 behavior unchanged (regression).

### `GameSession` application

- Starting gold/health reflect tech-tree bonuses via existing override path.
- **Wave-clear bonus** with `salvageCrew` purchased: clearing a wave credits `round(clearBonus * 1.25)` gold (e.g., 30 → 37, 40 → 50).
- **Wave-clear bonus** without `salvageCrew`: unchanged (regression).
- `restart()` preserves the session's modifiers (regression on HPA-94's restart boundary).
- `GameSession.modifiers` field exposes the stored modifiers for combat application.

### Combat application (`enemy_component.dart` call sites)

- Laser tower damage multiplied by `(1 + 0.10)` when `laserTuning` purchased and source tower type is `TowerType.laser`.
- Cryo tower slow duration extended by `+0.3` when `cryoCoolant` purchased and source tower type is `TowerType.cryo`.
- Non-affected tower types (`rocket`, `railgun`, `ionChain`, `nanite`, `gravityWell`, `droneBay`) unchanged when only `laserTuning` / `cryoCoolant` purchased.
- Empty modifiers (`CampaignModifiers.empty`) → combat behavior unchanged (regression).

These tests should target the call sites in `enemy_component.dart` directly, asserting the `DamageInput.damage` / `mergeSlow` `incomingDuration` values are adjusted before being passed to `CombatEffects`. `CombatEffects` itself is not modified and its existing tests remain green.

### Persistence

- **Codec v3 round-trip:** encode `CampaignSave(progress, techTree)` → decode → both `progress` and `techTree` fields match inputs.
- **v2 → v3 migration:** decode a v2-shaped JSON string → `techPurchases == []`, `stageResults` decoded correctly.
- **Unknown `techPurchases` IDs dropped:** encode with a future/unknown ID present → decode → unknown ID absent, known IDs preserved.
- **Missing `techPurchases` field** on a v3-shaped JSON: decode → empty tech tree.
- **Store round-trip** (`InMemoryCampaignProgressStore`): save a `CampaignSave` with both progress + tech tree → reload → verify both intact (covers the "persists across app restarts" acceptance criterion).

### Widget

- `TechTreeView` renders all five upgrade rows with correct name, effect, cost.
- Header bank displays the correct derived `unspentPoints` value.
- A purchased upgrade shows "Purchased" state (disabled).
- An affordable upgrade shows "Purchase" button (enabled).
- An unaffordable upgrade shows "Locked" with `Need N more points`.
- Tapping an affordable upgrade invokes the purchase callback; the bank decrements; the row re-renders as Purchased; subsequent rows re-evaluate affordability.
- World map shows the "Tech Tree" button; tapping it opens the panel.
- Tech Tree panel's back button returns to the world map.
- Existing widget tests pass when tech tree is empty (regression).

## Acceptance Criteria

Mapped to the issue:

- [x] **Persistent campaign tech-tree state in progress storage** — codec v3 adds `techPurchases`.
- [x] **At least three purchasable upgrades** — five shipped.
- [x] **Upgrades visibly affect mission start or tower stats** — three at mission start (gold, health, clear-bonus multiplier) and two in combat (laser damage, cryo slow).
- [x] **The player can view purchased and locked upgrades from the campaign map** — full-screen `TechTreeView` reached via a world-map header button.
- [x] **Upgrade purchases persist across app restarts** — codec v3 + `InMemoryCampaignProgressStore` round-trip test.
- [x] **Existing saved progress remains loadable** — v2 → v3 migration defaults `techPurchases = []`.
- [x] **Tests cover purchase validation, persistence, and application to gameplay** — pure-logic, persistence, session-application, combat-application, and widget tests specified above.

## References

- HPA-94 side-stage rewards spec: `docs/superpowers/specs/2026-07-11-orion-side-stage-campaign-rewards-design.md` (establishes `CampaignModifiers`, the optimistic-save-with-rollback pattern, the `startingBaseHealth` snapshot field, and the v2 codec).
- HPA-100 issue: https://linear.app/cwchanap/issue/HPA-100/add-campaign-wide-tech-tree
