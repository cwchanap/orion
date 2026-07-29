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
