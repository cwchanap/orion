import 'package:orion/game/models/game_models.dart';

import 'stage_definition.dart';
import 'tech_tree.dart';

enum StageProgressStatus { locked, unlocked, cleared }

enum StageMedal {
  clear,
  silver,
  gold;

  int get rank {
    return switch (this) {
      StageMedal.clear => 1,
      StageMedal.silver => 2,
      StageMedal.gold => 3,
    };
  }

  String get label {
    return switch (this) {
      StageMedal.clear => 'Clear',
      StageMedal.silver => 'Silver',
      StageMedal.gold => 'Gold',
    };
  }

  String get serializedName {
    return switch (this) {
      StageMedal.clear => 'clear',
      StageMedal.silver => 'silver',
      StageMedal.gold => 'gold',
    };
  }

  static StageMedal? fromSerializedName(String value) {
    return switch (value) {
      'clear' => StageMedal.clear,
      'silver' => StageMedal.silver,
      'gold' => StageMedal.gold,
      _ => null,
    };
  }
}

class StageResult {
  const StageResult({required this.medal, required this.bestBaseHealth})
    : assert(bestBaseHealth >= 0, 'bestBaseHealth must be non-negative');

  final StageMedal medal;
  final int bestBaseHealth;

  factory StageResult.fromVictoryBaseHealth(
    int baseHealth, {
    required int startingBaseHealth,
  }) {
    final normalizedBaseHealth = baseHealth
        .clamp(0, startingBaseHealth)
        .toInt();
    final medal = baseHealth >= startingBaseHealth
        ? StageMedal.gold
        : normalizedBaseHealth >= GameBalance.silverMedalThreshold
        ? StageMedal.silver
        : StageMedal.clear;

    return StageResult(medal: medal, bestBaseHealth: normalizedBaseHealth);
  }

  bool isBetterThan(StageResult? other) {
    if (other == null) {
      return true;
    }
    if (medal.rank != other.medal.rank) {
      return medal.rank > other.medal.rank;
    }
    return bestBaseHealth > other.bestBaseHealth;
  }

  Map<String, Object> toJson() {
    return {'medal': medal.serializedName, 'bestBaseHealth': bestBaseHealth};
  }

  static StageResult? fromJson(Object? source) {
    if (source is! Map<String, Object?>) {
      return null;
    }

    final rawMedal = source['medal'];
    final rawBaseHealth = source['bestBaseHealth'];
    if (rawMedal is! String || rawBaseHealth is! int) {
      return null;
    }

    final medal = StageMedal.fromSerializedName(rawMedal);
    if (medal == null || rawBaseHealth < 0) {
      return null;
    }

    // Preserve the stored medal and base health rather than re-deriving them
    // from current `GameBalance` tuning. Re-deriving would couple persisted
    // state to the live `silverMedalThreshold` / `initialBaseHealth`, so a
    // future tuning pass would silently drop older saves whose values fall
    // outside the new bounds. Trusting the stored values keeps saves stable
    // across balance changes; the `< 0` check above still guards against
    // corrupt data.
    return StageResult(medal: medal, bestBaseHealth: rawBaseHealth);
  }

  @override
  bool operator ==(Object other) {
    return other is StageResult &&
        other.medal == medal &&
        other.bestBaseHealth == bestBaseHealth;
  }

  @override
  int get hashCode => Object.hash(medal, bestBaseHealth);

  @override
  String toString() {
    return 'StageResult(medal: $medal, bestBaseHealth: $bestBaseHealth)';
  }
}

class CampaignProgress {
  CampaignProgress({
    Map<String, StageResult> bestResultsByStageId =
        const <String, StageResult>{},
  }) : _bestResultsByStageId = Map.unmodifiable(bestResultsByStageId);

  final Map<String, StageResult> _bestResultsByStageId;

  Map<String, StageResult> get bestResultsByStageId => _bestResultsByStageId;

  StageResult? resultFor(String stageId) {
    return _bestResultsByStageId[stageId];
  }

  bool isCleared(String stageId) {
    return _bestResultsByStageId.containsKey(stageId);
  }

  bool isUnlocked(StageDefinition stage) {
    return stage.unlockDependencies.every(isCleared);
  }

  StageProgressStatus statusFor(StageDefinition stage) {
    if (isCleared(stage.id)) {
      return StageProgressStatus.cleared;
    }

    if (isUnlocked(stage)) {
      return StageProgressStatus.unlocked;
    }

    return StageProgressStatus.locked;
  }

  bool isCampaignComplete(Iterable<StageDefinition> stages) {
    final mainPathStages = stages.where((stage) => stage.isMainPath).toList();

    return mainPathStages.isNotEmpty &&
        mainPathStages.every((stage) => isCleared(stage.id));
  }

  CampaignProgress withoutUnknownStages(Iterable<StageDefinition> stages) {
    final knownStageIds = stages.map((stage) => stage.id).toSet();

    return CampaignProgress(
      bestResultsByStageId: Map.fromEntries(
        _bestResultsByStageId.entries.where(
          (entry) => knownStageIds.contains(entry.key),
        ),
      ),
    );
  }

  CampaignProgress recordResult(String stageId, StageResult result) {
    final savedResult = _bestResultsByStageId[stageId];
    if (!result.isBetterThan(savedResult)) {
      return this;
    }

    return CampaignProgress(
      bestResultsByStageId: {..._bestResultsByStageId, stageId: result},
    );
  }

  /// Returns a copy with [stageId]'s result set to [result], or removed when
  /// [result] is null. Used by the save-rollback path to undo a single stage
  /// result without clobbering concurrent optimistic updates to other stages.
  CampaignProgress withResult(String stageId, StageResult? result) {
    if (result == null) {
      if (!_bestResultsByStageId.containsKey(stageId)) {
        return this;
      }
      final updated = Map<String, StageResult>.from(_bestResultsByStageId);
      updated.remove(stageId);
      return CampaignProgress(bestResultsByStageId: updated);
    }
    return CampaignProgress(
      bestResultsByStageId: {..._bestResultsByStageId, stageId: result},
    );
  }
}

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
      cryoSlowDurationBonus:
          techTree.isPurchased(CampaignTechUpgrade.cryoCoolant)
          ? GameBalance.cryoCoolantSlowDurationBonus
          : 0,
    );
  }
}
