import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../campaign/campaign_progress_store.dart';
import '../campaign/orion_campaign.dart';
import '../models/game_models.dart';
import 'camp_view.dart';
import 'orion_theme_data.dart';
import 'stage_briefing_sheet.dart';

/// Shared chrome for the task-6 roster previews: the widgets resolve Orion
/// theme values and Material ancestors exactly the way the app's
/// `MaterialApp(theme: orionThemeData)` provides them.
Widget orionRosterPreviewHome(Widget child) =>
    MaterialApp(theme: orionThemeData, home: child);

@Preview(
  name: 'Camp roster — starter profile',
  group: 'Last Hearth roster (HPA-922)',
  size: Size(390, 844),
  wrapper: orionRosterPreviewHome,
)
Widget campRosterStarterPreview() => const CampView(
  ownedLevels: CampaignSave.starterOwnedLevels,
  squad: CampaignSave.starterSquad,
);

@Preview(
  name: 'Camp roster — veteran profile',
  group: 'Last Hearth roster (HPA-922)',
  size: Size(390, 844),
  wrapper: orionRosterPreviewHome,
)
Widget campRosterVeteranPreview() => const CampView(
  ownedLevels: {
    Character.haruto: 12,
    Character.mio: 9,
    Character.sayo: 4,
    Character.jin: 2,
  },
  squad: [Character.mio, Character.sayo, Character.haruto],
);

@Preview(
  name: 'Stage briefing — squad draft',
  group: 'Last Hearth roster (HPA-922)',
  size: Size(390, 844),
  wrapper: orionRosterPreviewHome,
)
Widget stageBriefingSquadDraftPreview() => StageBriefingSheet(
  stage: OrionCampaign.stageOne,
  result: null,
  startingGold: GameBalance.startingGold,
  startingBaseHealth: GameBalance.initialBaseHealth,
  squad: CampaignSave.starterSquad,
  ownedLevels: CampaignSave.starterOwnedLevels,
  onLaunch: (mode, draft) async => true,
);
