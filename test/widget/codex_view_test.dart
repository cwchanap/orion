import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/codex_view.dart';

void main() {
  testWidgets('renders the four section chips and Towers content by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );

    for (final chip in const ['Towers', 'Enemies', 'Effects', 'Stages']) {
      expect(find.text(chip), findsWidgets);
    }
    // Default section is Towers: the first tower label appears.
    expect(find.text(TowerType.laser.label), findsOneWidget);
  });

  testWidgets('tapping Enemies shows the enemy section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(progress: CampaignProgress(), onBack: () {}),
      ),
    );
    await tester.tap(find.text('Enemies'));
    await tester.pumpAndSettle();
    expect(find.text(EnemyArchetype.basicDrone.label), findsOneWidget);
  });

  testWidgets('back button invokes onBack', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CodexView(
          progress: CampaignProgress(),
          onBack: () => pressed = true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(pressed, isTrue);
  });
}
