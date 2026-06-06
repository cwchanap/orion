import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';

void main() {
  group('CampaignProgressCodec', () {
    test('encodes and decodes versioned progress', () {
      final progress = CampaignProgress(
        clearedStageIds: {'outpost-alpha', 'nebula-relay'},
      );

      final encoded = CampaignProgressCodec.encode(progress);
      final decoded = CampaignProgressCodec.decode(
        encoded,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.clearedStageIds, {'outpost-alpha', 'nebula-relay'});
    });

    test('ignores unknown and duplicate stage ids', () {
      final decoded = CampaignProgressCodec.decode(
        '{"version":1,"clearedStageIds":["outpost-alpha","missing","outpost-alpha"]}',
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.clearedStageIds, {'outpost-alpha'});
    });

    test('falls back to empty progress for corrupt data', () {
      final decoded = CampaignProgressCodec.decode(
        'not-json',
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.clearedStageIds, isEmpty);
    });

    test('in-memory store saves, loads, and resets progress', () async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );

      await store.save(CampaignProgress(clearedStageIds: {'outpost-alpha'}));
      expect((await store.load()).clearedStageIds, {'outpost-alpha'});

      await store.reset();
      expect((await store.load()).clearedStageIds, isEmpty);
    });
  });
}
