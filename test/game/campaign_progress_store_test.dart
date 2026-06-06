import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('SharedPreferencesCampaignProgressStore', () {
    const key = 'test.campaign.progress';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves and loads progress through the configured key', () async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCampaignProgressStore(
        preferences: preferences,
        knownStages: OrionCampaign.stages,
        key: key,
      );

      await store.save(CampaignProgress(clearedStageIds: {'outpost-alpha'}));

      expect(preferences.getString(key), isNotNull);
      expect((await store.load()).clearedStageIds, {'outpost-alpha'});
    });

    test('reset clears progress', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: CampaignProgressCodec.encode(
          CampaignProgress(clearedStageIds: {'outpost-alpha'}),
        ),
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCampaignProgressStore(
        preferences: preferences,
        knownStages: OrionCampaign.stages,
        key: key,
      );

      await store.reset();

      expect(preferences.getString(key), isNull);
      expect((await store.load()).clearedStageIds, isEmpty);
    });

    test('malformed stored state falls back to empty progress', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{key: 42});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCampaignProgressStore(
        preferences: preferences,
        knownStages: OrionCampaign.stages,
        key: key,
      );

      expect((await store.load()).clearedStageIds, isEmpty);
    });
  });
}
