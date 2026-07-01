import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CampaignProgressCodec', () {
    test('encodes and decodes versioned stage results', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'outpost-alpha': const StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
          'nebula-relay': const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 14,
          ),
        },
      );

      final encoded = CampaignProgressCodec.encode(progress);
      final decoded = CampaignProgressCodec.decode(
        encoded,
        knownStages: OrionCampaign.stages,
      );

      expect(
        decoded.resultFor('outpost-alpha'),
        progress.resultFor('outpost-alpha'),
      );
      expect(
        decoded.resultFor('nebula-relay'),
        progress.resultFor('nebula-relay'),
      );
    });

    test('encodes sorted version two stage result JSON', () {
      final encoded = CampaignProgressCodec.encode(
        CampaignProgress(
          bestResultsByStageId: {
            'nebula-relay': const StageResult(
              medal: StageMedal.silver,
              bestBaseHealth: 14,
            ),
            'outpost-alpha': const StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
          },
        ),
      );

      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final stageResults = decoded['stageResults'] as Map<String, Object?>;

      expect(decoded['version'], 2);
      expect(stageResults.keys, ['nebula-relay', 'outpost-alpha']);
      expect(stageResults['outpost-alpha'], {
        'medal': 'gold',
        'bestBaseHealth': 20,
      });
      expect(stageResults['nebula-relay'], {
        'medal': 'silver',
        'bestBaseHealth': 14,
      });
    });

    test('ignores unknown stage ids and invalid result entries', () {
      final decoded = CampaignProgressCodec.decode('''
{
  "version": 2,
  "stageResults": {
    "outpost-alpha": {"medal": "gold", "bestBaseHealth": 20},
    "missing": {"medal": "gold", "bestBaseHealth": 20},
    "nebula-relay": {"medal": "diamond", "bestBaseHealth": 18},
    "asteroid-foundry": {"medal": "silver", "bestBaseHealth": 99}
  }
}
''', knownStages: OrionCampaign.stages);

      expect(decoded.bestResultsByStageId.keys, {'outpost-alpha'});
      expect(
        decoded.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
    });

    test('unsupported version one cleared ids decode empty', () {
      final decoded = CampaignProgressCodec.decode(
        '{"version":1,"clearedStageIds":["outpost-alpha"]}',
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.bestResultsByStageId, isEmpty);
    });

    test('falls back to empty progress for corrupt data', () {
      final decoded = CampaignProgressCodec.decode(
        'not-json',
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.bestResultsByStageId, isEmpty);
    });

    test('in-memory store saves, loads, and resets progress', () async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );

      await store.save(
        CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 4,
            ),
          },
        ),
      );
      expect(
        (await store.load()).resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 4),
      );

      await store.reset();
      expect((await store.load()).bestResultsByStageId, isEmpty);
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

      await store.save(
        CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 4,
            ),
          },
        ),
      );

      expect(preferences.getString(key), isNotNull);
      expect(
        (await store.load()).resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 4),
      );
    });

    test('reset clears progress', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: CampaignProgressCodec.encode(
          CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 4,
              ),
            },
          ),
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
      expect((await store.load()).bestResultsByStageId, isEmpty);
    });

    test('malformed stored state falls back to empty progress', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{key: 42});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCampaignProgressStore(
        preferences: preferences,
        knownStages: OrionCampaign.stages,
        key: key,
      );

      expect((await store.load()).bestResultsByStageId, isEmpty);
    });
  });
}
