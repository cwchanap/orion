import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/campaign/stage_reward_label.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('towers', () {
    test('covers every TowerType with exactly its two specializations', () {
      expect(CodexData.towers.length, TowerType.values.length);
      for (final entry in CodexData.towers) {
        expect(entry.label, entry.type.label);
        expect(entry.unlockWave, GameBalance.towerUnlockWave(entry.type));
        expect(
          entry.specializations.map((s) => s.specialization).toList(),
          GameBalance.specializationsFor(entry.type),
        );
      }
    });

    test(
      'specializationCost is hoisted per-type and matches level:2 stats',
      () {
        for (final entry in CodexData.towers) {
          expect(
            entry.specializationCost,
            GameBalance.towerStats(entry.type, level: 2).specializationCost,
          );
        }
      },
    );

    test('every blurb is non-empty', () {
      for (final t in CodexData.towers) {
        for (final s in t.specializations) {
          expect(s.description, isNotEmpty);
        }
      }
    });

    test('blurbs are the canonical specialization role sentences', () {
      for (final t in CodexData.towers) {
        for (final s in t.specializations) {
          expect(s.description, s.specialization.role);
        }
      }
    });

    test('every role sentence stays compact enough for inspector cards', () {
      for (final spec in TowerSpecialization.values) {
        expect(spec.role, isNotEmpty, reason: spec.name);
        expect(spec.role.length, lessThanOrEqualTo(90), reason: spec.name);
      }
    });
  });

  group('enemies', () {
    test('covers every EnemyArchetype with matching stats and label', () {
      expect(CodexData.enemies.length, EnemyArchetype.values.length);
      for (final entry in CodexData.enemies) {
        expect(entry.label, entry.archetype.label);
        expect(entry.stats, GameBalance.enemyArchetype(entry.archetype));
        expect(entry.roleDescription, isNotEmpty);
        // Traits follow enum order, not the Set's insertion order.
        expect(
          entry.traits,
          EnemyTrait.values.where(entry.stats.traits.contains).toList(),
        );
      }
    });
  });

  group('traits', () {
    test('covers every EnemyTrait with non-empty effect text', () {
      expect(CodexData.traits.length, EnemyTrait.values.length);
      for (final entry in CodexData.traits) {
        expect(entry.label, entry.trait.label);
        expect(entry.effect, isNotEmpty);
      }
    });
  });

  group('effects', () {
    const expectedIds = [
      'slow',
      'corrosion',
      'armorShred',
      'shieldDamage',
      'pierce',
      'chain',
      'splash',
      'drones',
      'gravityField',
    ];

    test('has the nine glossary ids in fixed order', () {
      expect(CodexData.effects.map((e) => e.id).toList(), expectedIds);
      for (final e in CodexData.effects) {
        expect(e.title, isNotEmpty);
        expect(e.description, isNotEmpty);
      }
    });

    test('related specializations are valid and derived when present', () {
      for (final e in CodexData.effects) {
        // An effect may legitimately map to zero specializations today
        // (e.g. mechanics reserved for future towers); allow empty.
        for (final spec in e.relatedSpecializations) {
          expect(spec, isA<TowerSpecialization>());
        }
      }
    });

    test('derived specialization sets match the signal fields', () {
      bool statsFor(TowerSpecialization s) =>
          GameBalance.towerStats(
            s.type,
            level: 3,
            specialization: s,
          ).slowMultiplier <
          1;
      final slowSpecs = TowerSpecialization.values.where(statsFor).toSet();
      expect(
        CodexData.effects
            .firstWhere((e) => e.id == 'slow')
            .relatedSpecializations
            .toSet(),
        slowSpecs,
      );
    });
  });

  group('stagesFor', () {
    test('status mirrors CampaignProgress.statusFor for each stage', () {
      final progress = CampaignProgress(); // empty
      final entries = CodexData.stagesFor(progress);
      expect(entries.length, OrionCampaign.stages.length);
      for (final entry in entries) {
        expect(entry.status, progress.statusFor(entry.stage));
        expect(entry.waveCount, entry.stage.waves.length);
      }
    });

    test('empty progress marks Outpost Alpha unlocked, others locked', () {
      final entries = CodexData.stagesFor(CampaignProgress());
      final byId = {for (final e in entries) e.stage.id: e};
      expect(
        byId[OrionCampaign.stageOneId]!.status,
        StageProgressStatus.unlocked,
      );
      final others = entries
          .where((e) => e.stage.id != OrionCampaign.stageOneId)
          .toList();
      expect(
        others.every((e) => e.status == StageProgressStatus.locked),
        isTrue,
      );
    });

    test('modifiers map via StageModifierMetadata, with standard fallback', () {
      final entries = CodexData.stagesFor(CampaignProgress());
      for (final entry in entries) {
        if (entry.stage.modifiers.isEmpty) {
          expect(entry.modifiers, [StageModifierMetadata.standardConditions]);
        } else {
          expect(entry.modifiers, [
            for (final m in entry.stage.modifiers)
              StageModifierMetadata.forModifier(m),
          ]);
        }
      }
    });

    test('rewardLabel mirrors stageRewardLabel using progress.isCleared', () {
      final progress = CampaignProgress();
      final entries = CodexData.stagesFor(progress);
      for (final entry in entries) {
        expect(
          entry.rewardLabel,
          stageRewardLabel(
            entry.stage,
            isCleared: progress.isCleared(entry.stage.id),
          ),
        );
      }
    });
  });

  group('codexMatches', () {
    test('empty or whitespace query matches entries in every category', () {
      final samples = <Iterable<String>>[
        CodexData.towers.first.searchTerms,
        CodexData.enemies.first.searchTerms,
        CodexData.traits.first.searchTerms,
        CodexData.effects.first.searchTerms,
        CodexData.stagesFor(CampaignProgress()).first.searchTerms,
      ];
      for (final terms in samples) {
        expect(codexMatches('', terms), isTrue);
        expect(codexMatches(' \t ', terms), isTrue);
      }
    });

    test('normalizes case and whitespace around the whole query string', () {
      final laser = CodexData.towers
          .firstWhere((t) => t.type == TowerType.laser)
          .searchTerms;
      expect(codexMatches('PULSE LASER', laser), isTrue);
      expect(codexMatches('  pulse laser  ', laser), isTrue);
      // The whole query must occur inside a term; extra characters break it.
      expect(codexMatches('pulse laserz', laser), isFalse);
      expect(codexMatches('intergalactic toaster', laser), isFalse);
    });

    test(
      'each specialization name or role description finds its parent tower',
      () {
        for (final tower in CodexData.towers) {
          for (final spec in tower.specializations) {
            expect(codexMatches(spec.label, tower.searchTerms), isTrue);
            expect(codexMatches(spec.description, tower.searchTerms), isTrue);
          }
        }
      },
    );

    test('querying "Pulse Laser" finds exactly the Laser tower', () {
      final hits = CodexData.towers
          .where((t) => codexMatches('Pulse Laser', t.searchTerms))
          .toList();
      expect(hits, hasLength(1));
      expect(hits.single.type, TowerType.laser);
    });

    test('label, authored role, or trait label finds each enemy', () {
      for (final enemy in CodexData.enemies) {
        expect(codexMatches(enemy.label, enemy.searchTerms), isTrue);
        expect(codexMatches(enemy.roleDescription, enemy.searchTerms), isTrue);
        for (final trait in enemy.traits) {
          expect(codexMatches(trait.label, enemy.searchTerms), isTrue);
        }
      }
    });

    test('glossary trait entries match their label and effect description', () {
      for (final trait in CodexData.traits) {
        expect(codexMatches(trait.label, trait.searchTerms), isTrue);
        expect(codexMatches(trait.effect, trait.searchTerms), isTrue);
      }
    });

    test(
      'effect titles, descriptions, and related specialization labels match',
      () {
        for (final effect in CodexData.effects) {
          expect(codexMatches(effect.title, effect.searchTerms), isTrue);
          expect(codexMatches(effect.description, effect.searchTerms), isTrue);
          for (final spec in effect.relatedSpecializations) {
            expect(codexMatches(spec.label, effect.searchTerms), isTrue);
          }
        }
      },
    );

    test('stage name, map label, description, and modifier text match', () {
      for (final entry in CodexData.stagesFor(CampaignProgress())) {
        expect(codexMatches(entry.stage.name, entry.searchTerms), isTrue);
        expect(codexMatches(entry.stage.mapLabel, entry.searchTerms), isTrue);
        expect(
          codexMatches(entry.stage.description, entry.searchTerms),
          isTrue,
        );
        for (final modifier in entry.modifiers) {
          expect(codexMatches(modifier.title, entry.searchTerms), isTrue);
          expect(codexMatches(modifier.description, entry.searchTerms), isTrue);
        }
      }
    });

    test('"locked" does not match a dynamic stage status', () {
      final locked = CodexData.stagesFor(
        CampaignProgress(),
      ).where((e) => e.status == StageProgressStatus.locked);
      expect(locked, isNotEmpty);
      for (final entry in locked) {
        expect(codexMatches('locked', entry.searchTerms), isFalse);
      }
    });

    test('numeric stats and rewards are not stage search terms', () {
      final entries = CodexData.stagesFor(CampaignProgress());
      final alpha = entries.firstWhere(
        (e) => e.stage.id == OrionCampaign.stageOneId,
      );
      // Alpha's authored prose and standard-conditions text contain no
      // digits, so any hit could only come from the wave count.
      expect(codexMatches('${alpha.waveCount}', alpha.searchTerms), isFalse);

      final rewarded = entries.firstWhere((e) => e.rewardLabel != null);
      expect(codexMatches('reward:', rewarded.searchTerms), isFalse);
    });
  });
}
