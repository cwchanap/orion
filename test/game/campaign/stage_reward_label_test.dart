import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_reward_label.dart';
import 'package:orion/game/models/game_models.dart';

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
