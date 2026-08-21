import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/ui/campaign_presentation.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

void main() {
  const theme = OrionUiTheme.dark;

  test('medalColor maps all StageMedal values to theme colors', () {
    expect(medalColor(theme, StageMedal.clear), theme.naniteGreen);
    expect(medalColor(theme, StageMedal.silver), theme.textMuted);
    expect(medalColor(theme, StageMedal.gold), theme.creditGold);
  });

  test('medalIcon maps all StageMedal values to distinct icons', () {
    expect(medalIcon(StageMedal.clear), Icons.check_circle);
    expect(medalIcon(StageMedal.silver), Icons.military_tech);
    expect(medalIcon(StageMedal.gold), Icons.emoji_events);
  });

  test('rewardIcon maps all CampaignReward values to distinct icons', () {
    expect(rewardIcon(CampaignReward.bonusGold), Icons.savings_rounded);
    expect(rewardIcon(CampaignReward.bonusHealth), Icons.favorite_rounded);
    expect(rewardIcon(CampaignReward.challengeBadge), Icons.stars_rounded);
  });
}
