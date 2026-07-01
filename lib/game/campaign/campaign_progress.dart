import 'package:orion/game/models/game_models.dart';

import 'stage_definition.dart';

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
  const StageResult({required this.medal, required this.bestBaseHealth});

  final StageMedal medal;
  final int bestBaseHealth;

  factory StageResult.fromVictoryBaseHealth(int baseHealth) {
    final normalizedBaseHealth = baseHealth
        .clamp(0, GameBalance.initialBaseHealth)
        .toInt();
    final medal = switch (normalizedBaseHealth) {
      GameBalance.initialBaseHealth => StageMedal.gold,
      >= GameBalance.silverMedalThreshold => StageMedal.silver,
      _ => StageMedal.clear,
    };

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
    if (medal == null ||
        rawBaseHealth < 0 ||
        rawBaseHealth > GameBalance.initialBaseHealth) {
      return null;
    }

    final result = StageResult.fromVictoryBaseHealth(rawBaseHealth);
    if (result.medal != medal) {
      return null;
    }

    return result;
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
}
