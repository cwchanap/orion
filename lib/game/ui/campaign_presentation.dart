import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';
import 'orion_ui_theme.dart';

Color medalColor(OrionUiTheme uiTheme, StageMedal medal) {
  return switch (medal) {
    StageMedal.clear => uiTheme.naniteGreen,
    StageMedal.silver => uiTheme.textMuted,
    StageMedal.gold => uiTheme.creditGold,
  };
}

IconData medalIcon(StageMedal medal) {
  return switch (medal) {
    StageMedal.clear => Icons.check_circle,
    StageMedal.silver => Icons.military_tech,
    StageMedal.gold => Icons.emoji_events,
  };
}

IconData rewardIcon(CampaignReward reward) {
  return switch (reward) {
    CampaignReward.bonusGold => Icons.savings_rounded,
    CampaignReward.bonusHealth => Icons.favorite_rounded,
    CampaignReward.challengeBadge => Icons.stars_rounded,
  };
}
