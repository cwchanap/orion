import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/campaign_progress_store.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/flare_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  CampaignSave save({
    CampaignProgress? progress,
    Map<Character, int>? ownedLevels,
    List<Character>? squad,
    int scrip = 0,
  }) {
    return CampaignSave(
      progress: progress ?? CampaignProgress(),
      ownedLevels: ownedLevels ?? CampaignSave.starterOwnedLevels,
      squad: squad ?? CampaignSave.starterSquad,
      scrip: scrip,
    );
  }

  FlareDraw newDraw(Character character) =>
      FlareDraw(character: character, isNew: true, scripRefund: 0);

  FlareDraw duplicateDraw(Character character) => FlareDraw(
    character: character,
    isNew: false,
    scripRefund: GameBalance.flareDuplicateScripRefund[character.rank]!,
  );

  void expectFreshProfile(CampaignSave decoded) {
    expect(decoded.scrip, 0);
    expect(decoded.progress.bestResultsByStageId, isEmpty);
    expect(decoded.progress.endlessBestByStageId, isEmpty);
    expect(decoded.ownedLevels, CampaignSave.starterOwnedLevels);
    expect(decoded.squad, CampaignSave.starterSquad);
  }

  group('CampaignProgressCodec', () {
    test('encodes and decodes stage results with the character profile', () {
      final source = save(
        progress: CampaignProgress(
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
          endlessBestByStageId: const {'outpost-alpha': 11},
        ),
        ownedLevels: const {
          Character.haruto: 3,
          Character.mio: 2,
          Character.akane: 1,
        },
        squad: const [Character.akane, Character.haruto, Character.mio],
        scrip: 650,
      );

      final encoded = CampaignProgressCodec.encode(source);
      final decoded = CampaignProgressCodec.decode(
        encoded,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.scrip, 650);
      expect(
        decoded.progress.resultFor('outpost-alpha'),
        source.progress.resultFor('outpost-alpha'),
      );
      expect(
        decoded.progress.resultFor('nebula-relay'),
        source.progress.resultFor('nebula-relay'),
      );
      expect(decoded.progress.endlessBestByStageId, {'outpost-alpha': 11});
      expect(decoded.ownedLevels, source.ownedLevels);
      expect(decoded.squad, source.squad);
    });

    test('encodes sorted, character-named JSON at codec version four', () {
      final encoded = CampaignProgressCodec.encode(
        save(
          progress: CampaignProgress(
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
            endlessBestByStageId: const {
              'outpost-alpha': 11,
              'nebula-relay': 4,
            },
          ),
          ownedLevels: const {
            Character.mio: 2,
            Character.akane: 1,
            Character.haruto: 3,
          },
          squad: const [Character.akane, Character.mio],
          scrip: 320,
        ),
      );

      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final stageResults = decoded['stageResults'] as Map<String, Object?>;
      final endlessBest = decoded['endlessBest'] as Map<String, Object?>;
      final ownedCharacters =
          decoded['ownedCharacters'] as Map<String, Object?>;

      expect(decoded['version'], 4);
      expect(decoded['scrip'], 320);
      expect(decoded.containsKey('techPurchases'), isFalse);
      expect(stageResults.keys, ['nebula-relay', 'outpost-alpha']);
      expect(endlessBest.keys, ['nebula-relay', 'outpost-alpha']);
      // `Character.name` is the save key; owned entries encode sorted so the
      // payload is deterministic.
      expect(ownedCharacters.keys, ['akane', 'haruto', 'mio']);
      expect(ownedCharacters['haruto'], 3);
      expect(decoded['squad'], ['akane', 'mio']);
    });

    test('ignores unknown stage ids and invalid result entries', () {
      final decoded = CampaignProgressCodec.decode('''
{
  "version": 4,
  "stageResults": {
    "outpost-alpha": {"medal": "gold", "bestBaseHealth": 20},
    "missing": {"medal": "gold", "bestBaseHealth": 20},
    "nebula-relay": {"medal": "diamond", "bestBaseHealth": 18},
    "salvage-rift": {"medal": "gold", "bestBaseHealth": 1},
    "asteroid-foundry": {"medal": "silver", "bestBaseHealth": -1},
    "aurora-gate": {"medal": "clear", "bestBaseHealth": 20}
  }
}
''', knownStages: OrionCampaign.stages);

      // `missing` is an unknown stage id; `nebula-relay` has an unknown medal;
      // `asteroid-foundry` has a negative `bestBaseHealth`. The remaining
      // entries are preserved as-is — `salvage-rift` and `aurora-gate` carry
      // medals that no longer match what `bestBaseHealth` would derive under
      // the current threshold, but stored medals are trusted across tuning
      // changes.
      expect(decoded.progress.bestResultsByStageId.keys, {
        'outpost-alpha',
        'salvage-rift',
        'aurora-gate',
      });
      expect(
        decoded.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      expect(
        decoded.progress.resultFor('salvage-rift'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 1),
      );
      expect(
        decoded.progress.resultFor('aurora-gate'),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 20),
      );
    });

    test('drops invalid endlessBest entries on decode', () {
      const raw =
          '{"version":4,"stageResults":{},'
          '"endlessBest":{"outpost-alpha":9,"missing-stage":12,'
          '"nebula-relay":"high","salvage-rift":0,"void-bastion":-2,'
          '"aurora-gate":3.5}}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.progress.endlessBestByStageId, {'outpost-alpha': 9});
    });

    test('non-map endlessBest decodes to an empty map', () {
      const raw = '{"version":4,"stageResults":{},"endlessBest":[1,2,3]}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.progress.endlessBestByStageId, isEmpty);
    });

    test('malformed stageResults still decodes endlessBest', () {
      // A torn or hand-edited save must not lose committed endless records:
      // the next save writes the whole aggregate, so dropping them here would
      // permanently overwrite them.
      const raw =
          '{"version":4,"stageResults":[1,2,3],'
          '"endlessBest":{"outpost-alpha":9,"nebula-relay":4}}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.progress.bestResultsByStageId, isEmpty);
      expect(decoded.progress.endlessBestByStageId, {
        'outpost-alpha': 9,
        'nebula-relay': 4,
      });
    });

    test('encode writes only positive endless bests', () {
      final encoded = CampaignProgressCodec.encode(
        save(
          progress: CampaignProgress(
            endlessBestByStageId: const {
              'outpost-alpha': 5,
              'nebula-relay': 0,
              'salvage-rift': -3,
            },
          ),
        ),
      );

      final raw = jsonDecode(encoded) as Map<String, Object?>;

      expect(raw['endlessBest'], {'outpost-alpha': 5});
    });

    test('malformed character fields never destroy valid stage and endless '
        'progress', () {
      const raw =
          '{"version":4,'
          '"stageResults":{"outpost-alpha":'
          '{"medal":"gold","bestBaseHealth":20}},'
          '"endlessBest":{"outpost-alpha":9},'
          '"ownedCharacters":[1,2,3],'
          '"squad":"haruto"}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(
        decoded.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      expect(decoded.progress.endlessBestByStageId, {'outpost-alpha': 9});
      // The owned map decoded nothing valid, so the two starters return;
      // the squad field was malformed and decodes empty.
      expect(decoded.ownedLevels, CampaignSave.starterOwnedLevels);
      expect(decoded.squad, isEmpty);
    });

    test('a v4 record without scrip decodes to zero and keeps every other '
        'valid field', () {
      // Saves written before Scrip existed carry no wallet field: the codec
      // reads them as a 0-Scrip wallet rather than discarding the profile.
      const raw =
          '{"version":4,'
          '"stageResults":{"outpost-alpha":'
          '{"medal":"gold","bestBaseHealth":20}},'
          '"endlessBest":{"outpost-alpha":9},'
          '"ownedCharacters":{"haruto":4,"mio":2,"sayo":3},'
          '"squad":["sayo","haruto"]}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.scrip, 0);
      expect(
        decoded.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      expect(decoded.progress.endlessBestByStageId, {'outpost-alpha': 9});
      expect(decoded.ownedLevels, {
        Character.haruto: 4,
        Character.mio: 2,
        Character.sayo: 3,
      });
      expect(decoded.squad, [Character.sayo, Character.haruto]);
    });

    test(
      'invalid scrip decodes to zero without losing valid roster fields',
      () {
        const scripValues = [
          '"scrip":-50,',
          '"scrip":"rich",',
          '"scrip":12.5,',
          '"scrip":true,',
          '"scrip":null,',
          '"scrip":[500],',
        ];

        for (final scripField in scripValues) {
          final raw =
              '{"version":4,$scripField'
              '"stageResults":{"outpost-alpha":'
              '{"medal":"silver","bestBaseHealth":14}},'
              '"ownedCharacters":{"haruto":4,"mio":2},'
              '"squad":["haruto","mio"]}';

          final decoded = CampaignProgressCodec.decode(
            raw,
            knownStages: OrionCampaign.stages,
          );

          expect(decoded.scrip, 0, reason: scripField);
          expect(
            decoded.progress.resultFor('outpost-alpha'),
            const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
            reason: scripField,
          );
          expect(decoded.ownedLevels, {
            Character.haruto: 4,
            Character.mio: 2,
          }, reason: scripField);
          expect(decoded.squad, [
            Character.haruto,
            Character.mio,
          ], reason: scripField);
        }
      },
    );

    test('skips unknown character ids and invalid levels per entry', () {
      const raw =
          '{"version":4,"stageResults":{},'
          '"ownedCharacters":{"haruto":4,"mio":"high","akane":0,'
          '"ren":-2,"jin":99,"not-a-character":5,"kaito":2.5},'
          '"squad":["haruto"]}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      // Only `haruto` survives: `mio` is not an int, `akane`/`ren` fall below
      // 1, `jin` exceeds `GameBalance.characterMaxLevel`, `kaito` is not an
      // int and `not-a-character` is an unknown id.
      expect(decoded.ownedLevels, {Character.haruto: 4});
      expect(decoded.squad, [Character.haruto]);
    });

    test('restores both starters when the owned map decodes empty', () {
      const raw =
          '{"version":4,"stageResults":{},'
          '"ownedCharacters":{"not-a-character":5},'
          '"squad":["mio","not-a-character"]}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.ownedLevels, CampaignSave.starterOwnedLevels);
      // `mio` is valid and owned once the starters are restored.
      expect(decoded.squad, [Character.mio]);
    });

    test('missing ownedCharacters restores the starters', () {
      const raw = '{"version":4,"stageResults":{}}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.ownedLevels, CampaignSave.starterOwnedLevels);
      expect(decoded.squad, isEmpty);
    });

    test('skips duplicated, unknown, and unowned squad members', () {
      const raw =
          '{"version":4,"stageResults":{},'
          '"ownedCharacters":{"haruto":1,"mio":1,"akane":3},'
          '"squad":["haruto","mio","haruto","not-a-character","elena",'
          '"akane",7]}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      // Order is preserved; the second `haruto`, the unknown id, the unowned
      // `elena`, and the non-string `7` are each skipped individually.
      expect(decoded.squad, [Character.haruto, Character.mio, Character.akane]);
    });

    test('caps the squad at six members', () {
      const raw =
          '{"version":4,"stageResults":{},'
          '"ownedCharacters":{"hikari":1,"jin":1,"akane":1,"ren":1,'
          '"elena":1,"shiori":1,"rin":1,"kaito":1},'
          '"squad":["hikari","jin","akane","ren","elena","shiori",'
          '"rin","kaito"]}';

      final decoded = CampaignProgressCodec.decode(
        raw,
        knownStages: OrionCampaign.stages,
      );

      expect(decoded.squad, [
        Character.hikari,
        Character.jin,
        Character.akane,
        Character.ren,
        Character.elena,
        Character.shiori,
      ]);
    });

    test('non-v4 payloads are discarded as a fresh starter profile', () {
      // Versions 1–3 carried cleared-stage ids or tech purchases that predate
      // the character profile. They are never migrated: the whole payload —
      // progress included — resets to a fresh two-starter profile.
      const payloads = [
        '{"version":1,"clearedStageIds":["outpost-alpha"]}',
        '{"version":2,"stageResults":{"outpost-alpha":'
            '{"medal":"gold","bestBaseHealth":20}}}',
        '{"version":3,"stageResults":{"outpost-alpha":'
            '{"medal":"gold","bestBaseHealth":20}},'
            '"endlessBest":{"outpost-alpha":9},'
            '"techPurchases":["solar-capacitors"]}',
        '{"version":99,"stageResults":{"outpost-alpha":'
            '{"medal":"gold","bestBaseHealth":20}}}',
        '{"version":"4","stageResults":{}}',
        '{"stageResults":{"outpost-alpha":'
            '{"medal":"gold","bestBaseHealth":20}}}',
      ];

      for (final raw in payloads) {
        final decoded = CampaignProgressCodec.decode(
          raw,
          knownStages: OrionCampaign.stages,
        );
        expectFreshProfile(decoded);
      }
    });

    test('falls back to a fresh starter profile for corrupt data', () {
      for (final raw in [null, '', 'not-json', '[]', '42', '"a string"']) {
        final decoded = CampaignProgressCodec.decode(
          raw,
          knownStages: OrionCampaign.stages,
        );
        expectFreshProfile(decoded);
      }
    });

    test('in-memory store saves, loads, and resets the whole save', () async {
      final store = InMemoryCampaignProgressStore(
        knownStages: OrionCampaign.stages,
      );

      await store.save(
        save(
          progress: CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 4,
              ),
            },
          ),
          ownedLevels: const {Character.haruto: 5, Character.mio: 1},
          squad: const [Character.mio],
          scrip: 410,
        ),
      );
      final loaded = await store.load();
      expect(loaded.scrip, 410);
      expect(
        loaded.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 4),
      );
      expect(loaded.ownedLevels, {Character.haruto: 5, Character.mio: 1});
      expect(loaded.squad, [Character.mio]);

      await store.reset();
      expectFreshProfile(await store.load());
    });
  });

  group('CampaignSave transforms', () {
    test('the constructor rejects a negative Scrip wallet', () {
      // A negative wallet is never a valid profile: it must fail at
      // construction, not persist and then silently decode to zero on the
      // next load.
      expect(
        () => CampaignSave(
          progress: CampaignProgress(),
          ownedLevels: CampaignSave.starterOwnedLevels,
          squad: CampaignSave.starterSquad,
          scrip: -1,
        ),
        throwsArgumentError,
      );
    });

    test('copyWith rejects a negative Scrip wallet', () {
      // copyWith is the only write path — routing it through the validating
      // constructor means no transform can mint a negative save either.
      expect(() => save(scrip: 300).copyWith(scrip: -1), throwsArgumentError);
    });

    test('copyWith replaces only the given fields and keeps the wallet', () {
      final source = save(
        progress: CampaignProgress(
          bestResultsByStageId: const {
            'outpost-alpha': StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
          },
        ),
        ownedLevels: const {Character.haruto: 4, Character.mio: 2},
        squad: const [Character.mio],
        scrip: 275,
      );

      final changed = source.copyWith(squad: const [Character.haruto]);

      expect(changed.scrip, 275);
      expect(changed.squad, [Character.haruto]);
      expect(changed.ownedLevels, {Character.haruto: 4, Character.mio: 2});
      expect(
        changed.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
      // Transforms are pure — the source save is never mutated in place.
      expect(source.squad, [Character.mio]);
    });

    test('withSquad keeps Scrip and the rest of the profile', () {
      final changed = save(scrip: 180).withSquad(const [Character.mio]);

      expect(changed.scrip, 180);
      expect(changed.squad, [Character.mio]);
      expect(changed.ownedLevels, CampaignSave.starterOwnedLevels);
      expect(changed.progress.bestResultsByStageId, isEmpty);
    });

    group('withLevelUp', () {
      test('spends the level cost and raises the owned level', () {
        final changed = save(
          ownedLevels: const {Character.haruto: 1, Character.mio: 2},
          squad: const [Character.haruto],
          scrip: 200,
        ).withLevelUp(Character.haruto);

        // GameBalance.levelUpCost(1) == 60.
        expect(changed.scrip, 200 - GameBalance.levelUpCost(1)!);
        expect(changed.ownedLevels, {Character.haruto: 2, Character.mio: 2});
        expect(changed.squad, [Character.haruto]);
      });

      test('charges the scaled cost for a mid-band level', () {
        final changed = save(
          ownedLevels: const {Character.haruto: 4, Character.mio: 1},
          scrip: 200,
        ).withLevelUp(Character.haruto);

        // GameBalance.levelUpCost(4) == 180.
        expect(changed.scrip, 200 - GameBalance.levelUpCost(4)!);
        expect(changed.ownedLevels[Character.haruto], 5);
      });

      test('rejects an unowned character without touching the save', () {
        final source = save(scrip: 500);

        expect(() => source.withLevelUp(Character.sayo), throwsStateError);
        expect(source.scrip, 500);
        expect(source.ownedLevels, CampaignSave.starterOwnedLevels);
      });

      test('rejects a purchase the wallet cannot cover', () {
        final source = save(scrip: GameBalance.levelUpCost(1)! - 1);

        expect(() => source.withLevelUp(Character.haruto), throwsStateError);
        expect(source.scrip, GameBalance.levelUpCost(1)! - 1);
        expect(source.ownedLevels[Character.haruto], 1);
      });

      test('rejects a character at the level cap', () {
        final source = save(
          ownedLevels: const {Character.haruto: GameBalance.characterMaxLevel},
          scrip: 9999,
        );

        expect(() => source.withLevelUp(Character.haruto), throwsStateError);
        expect(
          source.ownedLevels[Character.haruto],
          GameBalance.characterMaxLevel,
        );
        expect(source.scrip, 9999);
      });
    });

    group('withFlareBatch', () {
      test('charges the pack and recruits a new character at level 1', () {
        final changed = save(
          scrip: 150,
        ).withFlareBatch(FlareBatch([newDraw(Character.sayo)]));

        expect(changed.scrip, 150 - GameBalance.flareCost);
        expect(changed.ownedLevels, {
          ...CampaignSave.starterOwnedLevels,
          Character.sayo: 1,
        });
      });

      test('refunds a duplicate draw at the configured rank rate', () {
        final changed = save(
          scrip: 100,
        ).withFlareBatch(FlareBatch([duplicateDraw(Character.haruto)]));

        // haruto is rank E → 10 Scrip back on the 100-cost single pull.
        expect(changed.scrip, 10);
        expect(changed.ownedLevels, CampaignSave.starterOwnedLevels);
      });

      test('replays a ten-pull: in-batch recruits count as owned', () {
        // The first sayo recruits; the second sayo is an in-batch duplicate
        // — the honest classification `FlareRules.roll` would have produced.
        final batch = FlareBatch([
          newDraw(Character.sayo),
          duplicateDraw(Character.sayo),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
        ]);

        final changed = save(scrip: 1000).withFlareBatch(batch);

        expect(changed.scrip, 1000 - batch.cost + batch.totalScripRefund);
        expect(changed.ownedLevels, {
          ...CampaignSave.starterOwnedLevels,
          Character.sayo: 1,
        });
      });

      test('rejects pack counts outside the allowed sizes', () {
        for (final count in [0, 2, 5, 9, 11]) {
          final batch = FlareBatch([
            for (var index = 0; index < count; index += 1)
              duplicateDraw(Character.haruto),
          ]);
          expect(
            () => save(scrip: 100000).withFlareBatch(batch),
            throwsStateError,
            reason: 'count $count',
          );
        }
      });

      test('rejects a stale batch even when the wallet can afford it', () {
        // haruto is already owned — a NEW flag cannot be honest.
        expect(
          () => save(
            scrip: 100,
          ).withFlareBatch(FlareBatch([newDraw(Character.haruto)])),
          throwsStateError,
        );
        // sayo is unowned — a DUPLICATE flag has nothing to refund against.
        expect(
          () => save(
            scrip: 100,
          ).withFlareBatch(FlareBatch([duplicateDraw(Character.sayo)])),
          throwsStateError,
        );
      });

      test('rejects a misclassified in-batch duplicate', () {
        // The second sayo must read DUPLICATE; claiming NEW is stale.
        final batch = FlareBatch([
          newDraw(Character.sayo),
          newDraw(Character.sayo),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
          duplicateDraw(Character.haruto),
          duplicateDraw(Character.mio),
        ]);

        expect(() => save(scrip: 2000).withFlareBatch(batch), throwsStateError);
      });

      test('rejects a refund that does not match the configured rank rate', () {
        // Duplicate haruto (rank E) must refund 10 — not 999.
        expect(
          () => save(scrip: 100).withFlareBatch(
            FlareBatch([
              const FlareDraw(
                character: Character.haruto,
                isNew: false,
                scripRefund: 999,
              ),
            ]),
          ),
          throwsStateError,
        );
        // A new recruit declares no refund — a nonzero claim is invalid.
        expect(
          () => save(scrip: 100).withFlareBatch(
            FlareBatch([
              const FlareDraw(
                character: Character.sayo,
                isNew: true,
                scripRefund: 5,
              ),
            ]),
          ),
          throwsStateError,
        );
      });

      test('rejects a pack the wallet cannot cover', () {
        final source = save(scrip: GameBalance.flareCost - 1);

        expect(
          () => source.withFlareBatch(FlareBatch([newDraw(Character.sayo)])),
          throwsStateError,
        );
        expect(source.scrip, GameBalance.flareCost - 1);
        expect(source.ownedLevels, CampaignSave.starterOwnedLevels);
      });
    });

    group('withMissionWin', () {
      const result = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);

      test('records the best result and credits the award', () {
        final changed = save(
          ownedLevels: const {Character.haruto: 3, Character.mio: 1},
          squad: const [Character.mio],
          scrip: 40,
        ).withMissionWin('outpost-alpha', result, 1050);

        expect(changed.scrip, 1090);
        expect(changed.progress.resultFor('outpost-alpha'), result);
        expect(changed.ownedLevels, {Character.haruto: 3, Character.mio: 1});
        expect(changed.squad, [Character.mio]);
      });

      test('a non-improving result still credits the captured award', () {
        const prior = StageResult(medal: StageMedal.gold, bestBaseHealth: 20);
        const worse = StageResult(medal: StageMedal.clear, bestBaseHealth: 3);
        final changed = save(
          progress: CampaignProgress(
            bestResultsByStageId: const {'outpost-alpha': prior},
          ),
          scrip: 40,
        ).withMissionWin('outpost-alpha', worse, 125);

        // Best stays gold/20; the wallet still gains the replay award.
        expect(changed.progress.resultFor('outpost-alpha'), prior);
        expect(changed.scrip, 165);
      });

      test('rejects a negative award without recording anything', () {
        final source = save(scrip: 40);

        expect(
          () => source.withMissionWin('outpost-alpha', result, -1),
          throwsStateError,
        );
        expect(source.scrip, 40);
        expect(source.progress.resultFor('outpost-alpha'), isNull);
      });

      test('a zero award records the result without touching the wallet', () {
        final changed = save(
          scrip: 40,
        ).withMissionWin('outpost-alpha', result, 0);

        expect(changed.scrip, 40);
        expect(changed.progress.resultFor('outpost-alpha'), result);
      });
    });
  });

  group('SharedPreferencesCampaignProgressStore', () {
    const key = 'test.campaign.progress';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves and loads the whole save through the configured key', () async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCampaignProgressStore(
        preferences: preferences,
        knownStages: OrionCampaign.stages,
        key: key,
      );

      await store.save(
        save(
          progress: CampaignProgress(
            bestResultsByStageId: {
              'outpost-alpha': const StageResult(
                medal: StageMedal.clear,
                bestBaseHealth: 4,
              ),
            },
          ),
          ownedLevels: const {Character.haruto: 2, Character.mio: 1},
          squad: const [Character.haruto, Character.mio],
        ),
      );

      expect(preferences.getString(key), isNotNull);
      final loaded = await store.load();
      expect(
        loaded.progress.resultFor('outpost-alpha'),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 4),
      );
      expect(loaded.ownedLevels, {Character.haruto: 2, Character.mio: 1});
      expect(loaded.squad, [Character.haruto, Character.mio]);
    });

    test('reset clears progress', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: CampaignProgressCodec.encode(
          save(
            progress: CampaignProgress(
              bestResultsByStageId: {
                'outpost-alpha': const StageResult(
                  medal: StageMedal.clear,
                  bestBaseHealth: 4,
                ),
              },
            ),
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
      expectFreshProfile(await store.load());
    });

    test('malformed stored state falls back to a fresh profile', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{key: 42});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCampaignProgressStore(
        preferences: preferences,
        knownStages: OrionCampaign.stages,
        key: key,
      );

      expectFreshProfile(await store.load());
    });
  });

  group('CampaignModifiers', () {
    test(
      'side-stage results persist and produce correct campaign modifiers',
      () async {
        final store = InMemoryCampaignProgressStore(
          knownStages: OrionCampaign.stages,
        );

        final progress = CampaignProgress(
          bestResultsByStageId: {
            'outpost-alpha': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'nebula-relay': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'salvage-rift': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
            'void-bastion': const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        );

        await store.save(save(progress: progress));

        final loaded = await store.load();
        final modifiers = CampaignModifiers.fromProgress(
          loaded.progress,
          OrionCampaign.stages,
        );

        expect(modifiers.bonusGold, GameBalance.salvageRiftGoldBonus);
        expect(modifiers.bonusHealth, GameBalance.voidBastionHealthBonus);
        expect(modifiers.hasChallengeBadge, isTrue);
      },
    );
  });
}
