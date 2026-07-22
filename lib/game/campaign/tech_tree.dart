import '../models/game_models.dart';
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
    cost: GameBalance.solarCapacitorsCost,
    label: 'Solar Capacitors',
    description: 'Start each mission with extra gold.',
  ),
  hardenedCore(
    id: 'hardened-core',
    cost: GameBalance.hardenedCoreCost,
    label: 'Hardened Core',
    description: 'Start each mission with extra base health.',
  ),
  salvageCrew(
    id: 'salvage-crew',
    cost: GameBalance.salvageCrewCost,
    label: 'Salvage Crew',
    description: 'Earn more gold from wave clears.',
  ),
  laserTuning(
    id: 'laser-tuning',
    cost: GameBalance.laserTuningCost,
    label: 'Laser Tuning',
    description: 'Laser towers deal more damage.',
  ),
  cryoCoolant(
    id: 'cryo-coolant',
    cost: GameBalance.cryoCoolantCost,
    label: 'Cryo Coolant',
    description: 'Cryo towers slow enemies longer.',
  );

  const CampaignTechUpgrade({
    required this.id,
    required this.cost,
    required this.label,
    required this.description,
  });

  /// Stable identifier used in persistence. Never reuse an id after removing
  /// an upgrade (decode silently drops unknown ids; reuse would resurrect
  /// stale purchases).
  final String id;
  final int cost;
  final String label;
  final String description;

  /// Human-readable effect summary, derived from [GameBalance] constants so
  /// it stays in sync with the actual tuning values.
  String get effectLabel {
    switch (this) {
      case CampaignTechUpgrade.solarCapacitors:
        return '+${GameBalance.solarCapacitorsGoldBonus} Starting Gold';
      case CampaignTechUpgrade.hardenedCore:
        return '+${GameBalance.hardenedCoreHealthBonus} Starting Health';
      case CampaignTechUpgrade.salvageCrew:
        final percent = (GameBalance.salvageCrewClearBonusFraction * 100)
            .round();
        return '+$percent% Wave Clear Gold';
      case CampaignTechUpgrade.laserTuning:
        final percent = (GameBalance.laserTuningDamageFraction * 100).round();
        return '+$percent% Laser Damage';
      case CampaignTechUpgrade.cryoCoolant:
        return '+${GameBalance.cryoCoolantSlowDurationBonus.toStringAsFixed(1)}s Cryo Slow';
    }
  }

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
    return progress.bestResultsByStageId.values.fold(
      0,
      (sum, result) => sum + result.medal.rank,
    );
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
  CampaignTechTree purchase(
    CampaignTechUpgrade upgrade,
    CampaignProgress progress,
  ) {
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
