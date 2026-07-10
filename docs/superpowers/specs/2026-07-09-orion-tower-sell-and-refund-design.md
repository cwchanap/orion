# Orion Tower Sell and Refund Design

## Context

HPA-98 lets players sell placed towers during build phase for a partial gold refund, so experimenting with builds between waves is less punishing. Orion is a Flutter + Flame tower-defense game with a deliberate split between pure mission rules (`lib/game/rules/`, `lib/game/models/`) and the Flame rendering layer (`lib/game/components/`, `lib/game/orion_defense_game.dart`). Mission state flows from `GameSession` through immutable `GameSnapshot`s into `OrionGamePage`; the UI reads only snapshots.

Today `GameSession` owns mutable tower state in `_towersByPosition` and exposes `placeTower`, `upgradeTower`, `specializeTower`, and `setTargetingMode` — all gated to `GamePhase.build`. Each reads its cost from `GameBalance.towerStats(...)`, subtracts from `_gold`, and mutates the tower entry. `OrionDefenseGame` mirrors these as thin wrappers (e.g. `upgradeSelectedTower`) that mutate the session, sync the matching `TowerComponent`, update `_selectedTower`, and publish a snapshot. The selected-tower panel (`_UpgradePanel` → `_UpgradeActions`) renders the Upgrade / Specialize / Max actions from the snapshot.

Every `TowerStats` carries three cost fields — `cost` (level 1), `upgradeCost` (1→2), `specializationCost` (2→3) — all populated from the private `_towerCosts(type)` table regardless of which level the stats describe. So the total gold invested in any `PlacedTower` is fully derivable from its `type`, `level`, and `specialization`; no new persistent field is needed.

## Goal

Let a player sell a selected placed tower during build phase and receive a flat 70% of the gold invested in it, rounded down. Selling removes the tower from session state and the board, refunds the gold, clears the selection, and shows a feedback message stating the refund amount.

## Refund calculation

Invested gold and refund are pure functions of the tower's state:

```
invested = towerStats(type, level: 1).cost
         + (level >= 2 ? towerStats(type, level: 1).upgradeCost : 0)
         + (level == 3 ? towerStats(type, level: 1).specializationCost : 0)
refund   = invested * sellRefundPercent ~/ 100
```

Where `sellRefundPercent` is a new `static const int = 70` on `GameBalance`, placed beside `startingGold` and `initialBaseHealth` so the rate is a single tunable knob.

- Flat rate regardless of tower level: one predictable rule for the player.
- **Integer arithmetic (`* 70 ~/ 100`), not a `double` rate:** `(invested * 0.70).floor()` suffers floating-point error because 0.7 is not exactly representable in IEEE-754. Verified: `(90 * 0.70).floor()` = 62 (should be 63), `(180 * 0.70).floor()` = 125 (should be 126), `(330 * 0.70).floor()` = 230 (should be 231). `invested * 70 ~/ 100` is exact for all current tower totals. The `~/ 100` integer division truncates, so a refund never returns *more* than exactly 70% on a fractional total. Example: an Ion Chain tower specialized to Storm Relay has invested 95 + 130 + 190 = 415; 415 * 70 ~/ 100 = 29050 ~/ 100 = 290.

Concrete refund reference values:

| Tower (state)          | Invested | Refund (70%, truncated) |
|------------------------|----------|-------------------------|
| Laser L1               | 50       | 35                      |
| Laser L2               | 120      | 84                      |
| Laser L3 pulseLaser    | 240      | 168                     |
| Rocket L1              | 80       | 56                      |
| Nanite L1              | 90       | 63                      |
| Rocket L3 siegeRocket  | 330      | 231                     |
| DroneBay L3 hunterBay  | 540      | 378                     |
| IonChain L3 stormRelay | 415      | 290                     |

## Scope

In scope:

- A `GameBalance.refundValue(PlacedTower tower)` static method and a `GameBalance.sellRefundPercent` constant.
- A `GameSession.sellTower(int towerId)` method returning the refund (or `null` when rejected).
- An `OrionDefenseGame.sellSelectedTower()` wrapper that removes the `TowerComponent`, despawns the tower's live drones, clears selection, and publishes feedback.
- A Sell button in the selected-tower panel, visible at every tower level, disabled outside build phase, showing the refund amount.
- Pure-rule, balance, game-layer, and widget tests covering refund values, session behavior, component removal/selection/feedback, and UI state.

Out of scope (non-goals from the issue):

- Tower moving / repositioning.
- Undo history.
- A confirmation dialog before selling (the refund is generous and selling is build-phase only, so the touch flow stays snappy).
- Any economy, wave, or stat rebalance beyond the new constant.

## Design

### `lib/game/models/game_models.dart`

Add the tuning constant next to the other economy constants:

```dart
static const int sellRefundPercent = 70;
```

Add the pure refund function. It reads costs from level-1 stats (which always carry all three cost fields), so it never throws on level/specialization combination:

```dart
static int refundValue(PlacedTower tower) {
  final base = towerStats(tower.type, level: 1);
  var invested = base.cost;
  if (tower.level >= 2) {
    invested += base.upgradeCost;
  }
  if (tower.level == 3) {
    invested += base.specializationCost;
  }
  return invested * sellRefundPercent ~/ 100;
}
```

No change to `PlacedTower`, `TowerStats`, or `GameSnapshot`.

### `lib/game/rules/game_session.dart`

Add `sellTower`, mirroring the `upgradeTower` / `specializeTower` shape (same build-phase gate, same `_findTowerEntry` helper, same direct `_gold` mutation):

```dart
int? sellTower(int towerId) {
  if (_phase != GamePhase.build) {
    return null;
  }
  final entry = _findTowerEntry(towerId);
  if (entry == null) {
    return null;
  }
  final refund = GameBalance.refundValue(entry.value);
  _towersByPosition.remove(entry.key);
  _gold += refund;
  return refund;
}
```

Returns `int?` rather than `bool` because the orchestrator needs the refund amount to show "Sold for N" feedback, and `null` cleanly signals rejection (wrong phase or unknown id) versus a successful sale.

### `lib/game/orion_defense_game.dart`

Add `sellSelectedTower`, following the `upgradeSelectedTower` wiring:

```dart
void sellSelectedTower() {
  final tower = _selectedTower;
  if (tower == null) {
    _publishSnapshot(feedback: 'Select a tower first.');
    return;
  }
  final refund = _session.sellTower(tower.id);
  if (refund == null) {
    _publishSnapshot(feedback: 'Sell towers between waves.');
    return;
  }
  final component = _towerComponents.remove(tower.id);
  component?.removeFromParent();
  for (final drone
      in children.whereType<DroneComponent>().where((d) => d.ownerTowerId == tower.id).toList()) {
    drone.removeFromParent();
  }
  _activeDronesByTower.remove(tower.id);
  _clearSelection();
  _publishSnapshot(feedback: 'Sold for $refund gold.');
}
```

- Removes the `TowerComponent` from `_towerComponents` and the scene (mirrors `_clearCombatComponents`'s tower-removal path).
- **Despawns the tower's live drones, then clears the bookkeeping.** Drones can survive a wave's end (their `_finishWaveIfComplete` only checks `_activeEnemyComponents`, not drones) and live up to `droneLifetime` (5.4s for hunterBay). Removing only `_activeDronesByTower[tower.id]` would leave orphaned `DroneComponent`s flying, attacking the next wave's enemies while excluded from the active-drone count. Selling the tower despawns its drones outright — consistent with "the tower and its effects are gone" — matching the player's expectation.
- `_clearSelection()` clears `_selectedTower`, `_selectedCell`, and the board highlight, satisfying the "selling clears selection" criterion.

### `lib/game/ui/orion_game_page.dart`

In `_UpgradeActions.build`, the existing branch produces one action widget (Upgrade button, Specialize chips, or Max label). Wrap that action in a `Wrap` with a Sell button appended so the sell action is present at every tower level:

```dart
final Widget primary;
if (tower.canUpgrade) {
  primary = /* existing Upgrade button */;
} else if (tower.canSpecialize) {
  primary = /* existing Specialize chips */;
} else {
  primary = /* existing Max label */;
}

return Wrap(
  alignment: alignment,
  spacing: 8,
  runSpacing: 8,
  children: [
    primary,
    FilledButton.tonalIcon(
      onPressed: snapshot.phase == GamePhase.build
          ? game.sellSelectedTower
          : null,
      icon: const Icon(Icons.sell),
      label: Text('Sell +${GameBalance.refundValue(tower)}'),
    ),
  ],
);
```

- The label shows the refund up front (`Sell +35`) so the player knows the payoff before tapping.
- `onPressed` is `null` (disabled) outside `GamePhase.build`, satisfying the "disabled during waves/won/lost" criterion.
- A tonal button reads as a secondary action without being alarming. `Icons.sell` is the chosen glyph.

The existing specialize branch already returns a `Wrap`; combining it with the sell button into a single `Wrap` keeps the layout consistent across all three tower states.

## Testing

Pure-rule, balance, game-layer, and widget tests are all required. Session and balance tests cannot verify component removal, drone despawn, selection clearing, feedback messages, or UI state — those need the game-layer and widget suites.

### `test/game/game_balance_test.dart`

Add a `refundValue` test covering level-1, upgraded, and specialized towers, plus the floating-point-error regression cases (these guard against reverting to a `double` rate):

- L1 Laser → 35.
- L2 Laser → 84.
- L3 Laser pulseLaser → 168.
- L1 Rocket → 56.
- L1 Nanite (90) → 63 (would be 62 under `double`).
- L3 Rocket siegeRocket (330) → 231 (would be 230 under `double`).
- L3 DroneBay hunterBay → 378.
- L3 IonChain stormRelay (415) → 290 (truncated from 290.5).

### `test/game/game_session_test.dart`

Add a `sellTower` group mirroring the existing upgrade/specialize tests:

- Removes the tower from `session.towers`, increases gold by the refund, and returns the refund amount.
- Frees the cell for re-placement (a subsequent `placeTower` on the same cell succeeds).
- Returns `null` outside build phase (after `startWave`).
- Returns `null` for an unknown tower id.

### `test/game/orion_defense_game_test.dart` (required)

The existing suite covers pacing/snapshots but has no upgrade/specialize wiring tests. Add a `sellSelectedTower` group — this is net-new game-layer coverage, required because the session tests cannot verify the Flame component tree:

- The `TowerComponent` for the sold tower is removed from the scene (no `DroneComponent`/`TowerComponent` with that id remains).
- Selling a drone bay despawns its live `DroneComponent`s (assert no `DroneComponent` with `ownerTowerId == soldId` remains after sell).
- `_selectedTower` is cleared (snapshot `selectedTower` is `null`).
- The snapshot carries the refund feedback (`Sold for N gold.`).
- Calling sell with no tower selected publishes the "Select a tower first." feedback.

If asserting component-tree state requires a running Flame game (i.e. `onLoad` has run and components are attached), these tests build the game through its load lifecycle rather than constructing a bare instance.

### `test/widget/` — widget tests (required)

Add widget tests for the selected-tower panel, covering the UI behaviors the lower layers cannot:

- The Sell button renders with the correct refund in its label (e.g. `Sell +35` for an L1 Laser).
- The Sell button is enabled during `GamePhase.build` and disabled (null `onPressed`) during wave / won / lost.
- Tapping Sell invokes `game.sellSelectedTower` (verify via a spy/stub game or by observing the resulting snapshot).
- Narrow layout (`maxWidth < 440`) stacks the summary and actions without overflow.

These establish UI test coverage that does not yet exist for the upgrade panel; place them under `test/widget/` (or `test/game/ui/` following the suite's existing conventions — confirm the chosen location during implementation).

## Verification

- `flutter analyze` passes.
- `flutter test` passes, including the new `refundValue`, `sellTower`, `sellSelectedTower`, and widget cases.
