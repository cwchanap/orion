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
refund   = (invested * sellRefundRate).floor()
```

Where `sellRefundRate` is a new `static const double = 0.70` on `GameBalance`, placed beside `startingGold` and `initialBaseHealth` so the rate is a single tunable knob.

- Flat rate regardless of tower level: one predictable rule for the player.
- `.floor()` (truncate): a refund never returns *more* than exactly 70%, so fractional amounts round down. Example: an Ion Chain tower specialized to Storm Relay has invested 95 + 130 + 190 = 415; 415 × 0.70 = 290.5 → refunds 290.

Concrete refund reference values:

| Tower (state)        | Invested | Refund (70%, floored) |
|----------------------|----------|-----------------------|
| Laser L1             | 50       | 35                    |
| Laser L2             | 120      | 84                    |
| Laser L3 pulseLaser  | 240      | 168                   |
| Rocket L1            | 80       | 56                    |
| DroneBay L3 hunterBay| 540      | 378                   |
| IonChain L3 stormRelay | 415    | 290                   |

## Scope

In scope:

- A `GameBalance.refundValue(PlacedTower tower)` static method and a `GameBalance.sellRefundRate` constant.
- A `GameSession.sellTower(int towerId)` method returning the refund (or `null` when rejected).
- An `OrionDefenseGame.sellSelectedTower()` wrapper that removes the `TowerComponent`, clears selection, and publishes feedback.
- A Sell button in the selected-tower panel, visible at every tower level, disabled outside build phase, showing the refund amount.
- Pure-rule and balance tests covering level-1, upgraded, and specialized refund values, plus session behavior.

Out of scope (non-goals from the issue):

- Tower moving / repositioning.
- Undo history.
- A confirmation dialog before selling (the refund is generous and selling is build-phase only, so the touch flow stays snappy).
- Any economy, wave, or stat rebalance beyond the new constant.

## Design

### `lib/game/models/game_models.dart`

Add the tuning constant next to the other economy constants:

```dart
static const double sellRefundRate = 0.70;
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
  return (invested * sellRefundRate).floor();
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
  _activeDronesByTower.remove(tower.id);
  _clearSelection();
  _publishSnapshot(feedback: 'Sold for $refund gold.');
}
```

- Removes the `TowerComponent` from `_towerComponents` and the scene (mirrors `_clearCombatComponents`'s tower-removal path).
- Clears any `_activeDronesByTower` bookkeeping entry for the tower (a drone bay sold mid-build otherwise leaves a stale counter).
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

No new test files — existing files cover the right surfaces.

### `test/game/game_balance_test.dart`

Add a `refundValue` test covering level-1, upgraded, and specialized towers, plus a `.5` floor case:

- L1 Laser → 35.
- L2 Laser → 84.
- L3 Laser pulseLaser → 168.
- L1 Rocket → 56.
- L3 DroneBay hunterBay → 378.
- L3 IonChain stormRelay (415 × 0.7 = 290.5) → 290 (floor).

### `test/game/game_session_test.dart`

Add a `sellTower` group mirroring the existing upgrade/specialize tests:

- Removes the tower from `session.towers`, increases gold by the refund, and returns the refund amount.
- Frees the cell for re-placement (a subsequent `placeTower` on the same cell succeeds).
- Returns `null` outside build phase (after `startWave`).
- Returns `null` for an unknown tower id.

### `test/game/orion_defense_game_test.dart`

If the existing suite covers upgrade/specialize wiring at the game layer, add a parallel sell test asserting the `TowerComponent` is removed and the snapshot carries the refund feedback. (If that suite only covers pure-rule wiring, the session tests are sufficient.)

## Verification

- `flutter analyze` passes.
- `flutter test` passes, including the new `refundValue` and `sellTower` cases.
