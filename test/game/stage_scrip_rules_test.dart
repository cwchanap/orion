import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/stage_scrip_rules.dart';

void main() {
  group('StageScripRules.award', () {
    test('pays the approved totals for all seven campaign stages', () {
      const expected = <String, ({int firstClear, int replay})>{
        'outpost-alpha': (firstClear: 1000, replay: 100),
        'nebula-relay': (firstClear: 300, replay: 120),
        'salvage-rift': (firstClear: 360, replay: 140),
        'asteroid-foundry': (firstClear: 400, replay: 160),
        'aurora-gate': (firstClear: 500, replay: 200),
        'void-bastion': (firstClear: 600, replay: 220),
        'singularity-core': (firstClear: 700, replay: 260),
      };

      for (final stage in OrionCampaign.stages) {
        final stageExpected = expected[stage.id]!;
        expect(
          StageScripRules.award(stage, StageMedal.clear, firstClear: true),
          stageExpected.firstClear,
          reason: '${stage.id} first Clear-medal clear',
        );
        expect(
          StageScripRules.award(stage, StageMedal.clear, firstClear: false),
          stageExpected.replay,
          reason: '${stage.id} Clear-medal replay',
        );
      }
    });

    test('scales the replay base by the earned medal percent', () {
      final stageOne = OrionCampaign.stageOne;
      expect(
        StageScripRules.award(stageOne, StageMedal.clear, firstClear: false),
        100,
      );
      expect(
        StageScripRules.award(stageOne, StageMedal.silver, firstClear: false),
        125,
      );
      expect(
        StageScripRules.award(stageOne, StageMedal.gold, firstClear: false),
        150,
      );
      expect(
        StageScripRules.award(stageOne, StageMedal.clear, firstClear: true),
        1000,
      );
      expect(
        StageScripRules.award(stageOne, StageMedal.silver, firstClear: true),
        1025,
      );
      expect(
        StageScripRules.award(stageOne, StageMedal.gold, firstClear: true),
        1050,
      );

      final stageTwo = OrionCampaign.stageById('nebula-relay');
      expect(
        StageScripRules.award(stageTwo, StageMedal.clear, firstClear: true),
        300,
      );
      expect(
        StageScripRules.award(stageTwo, StageMedal.silver, firstClear: true),
        330,
      );
      expect(
        StageScripRules.award(stageTwo, StageMedal.gold, firstClear: false),
        180,
      );
    });

    test('first-clear bonus applies only on the first clear', () {
      final stage = OrionCampaign.stageById('aurora-gate');

      expect(
        StageScripRules.award(stage, StageMedal.gold, firstClear: true),
        300 + 300,
      );
      expect(
        StageScripRules.award(stage, StageMedal.gold, firstClear: false),
        300,
      );
    });

    test('floors fractional medal payouts', () {
      final stage = _scripStage(firstClearScrip: 7, replayScrip: 101);

      expect(
        StageScripRules.award(stage, StageMedal.silver, firstClear: false),
        126,
      );
      expect(
        StageScripRules.award(stage, StageMedal.gold, firstClear: false),
        151,
      );
      expect(
        StageScripRules.award(stage, StageMedal.silver, firstClear: true),
        133,
      );
    });

    test('zero-default test stages award nothing without throwing', () {
      final stage = StageDefinition(
        id: 'zero-scrip',
        name: 'Zero Scrip',
        mapLabel: 'Zero',
        description: 'Fixture stage without Scrip fields',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: const [],
        mapColumn: 0,
        mapRow: 0,
      );

      expect(stage.firstClearScrip, 0);
      expect(stage.replayScrip, 0);
      expect(
        StageScripRules.award(stage, StageMedal.gold, firstClear: true),
        0,
      );
      expect(
        StageScripRules.award(stage, StageMedal.clear, firstClear: false),
        0,
      );
    });

    test('stage one first clear funds the ten-flare onboarding guarantee', () {
      final award = StageScripRules.award(
        OrionCampaign.stageOne,
        StageMedal.clear,
        firstClear: true,
      );

      expect(award, greaterThanOrEqualTo(10 * GameBalance.flareCost));
      expect(award, 1000);
    });
  });
}

StageDefinition _scripStage({
  required int firstClearScrip,
  required int replayScrip,
}) {
  return StageDefinition(
    id: 'scrip-fixture',
    name: 'Scrip Fixture',
    mapLabel: 'Fixture',
    description: 'Fixture stage with custom Scrip fields',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: const [],
    firstClearScrip: firstClearScrip,
    replayScrip: replayScrip,
    mapColumn: 0,
    mapRow: 0,
  );
}
