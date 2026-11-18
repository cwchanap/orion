import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
import 'package:orion/game/campaign/stage_reward_label.dart';
import 'package:orion/game/codex/codex_data.dart';
import 'package:orion/game/models/game_models.dart';

/// The four combat variants with no playable member: they may stay in the
/// internal enums but must never surface in the Codex.
const _unusedSignatures = {
  TowerSpecialization.hunterBay,
  TowerSpecialization.overloadRelay,
  TowerSpecialization.replicatorNanites,
  TowerSpecialization.crushWell,
};

void main() {
  group('characters', () {
    test('covers every roster member in Character.values order', () {
      expect(
        CodexData.characters.map((entry) => entry.character).toList(),
        Character.values,
      );
      for (final entry in CodexData.characters) {
        expect(entry.label, entry.character.displayName);
      }
    });

    test('each entry exposes exactly its fixed signature', () {
      for (final entry in CodexData.characters) {
        expect(entry.signature.specialization, entry.character.signature);
        expect(entry.signature.label, entry.character.signatureName);
        expect(entry.signature.description, entry.character.signature.role);
        expect(
          entry.signature.specializedStats,
          GameBalance.towerStats(
            entry.character.style,
            level: 3,
            specialization: entry.character.signature,
          ),
        );
      }
    });

    test('style costs come from the level-1 style stats', () {
      for (final entry in CodexData.characters) {
        final base = GameBalance.towerStats(entry.character.style, level: 1);
        expect(entry.baseStats, base);
        expect(entry.deployCost, base.cost);
        expect(entry.upgradeCost, base.upgradeCost);
        expect(entry.signatureCost, base.specializationCost);
      }
    });

    test('no unused combat variant appears anywhere in the roster data', () {
      final playable = Character.values
          .map((member) => member.signature)
          .toSet();
      expect(
        playable.toSet().intersection(_unusedSignatures),
        isEmpty,
        reason: 'fixture: unused variants must stay unsigned',
      );
      for (final entry in CodexData.characters) {
        expect(entry.signature.specialization, isIn(playable));
        for (final term in entry.searchTerms) {
          for (final spec in _unusedSignatures) {
            expect(term, isNot(contains(spec.label)), reason: spec.name);
          }
        }
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

    test('relations enumerate playable members, deduped', () {
      for (final e in CodexData.effects) {
        // An effect may legitimately map to zero members today.
        expect(
          e.relatedCharacters,
          equals(e.relatedCharacters.toSet().toList()),
          reason: '${e.id} repeats a member',
        );
        for (final member in e.relatedCharacters) {
          expect(member, isIn(Character.values));
        }
      }
    });

    test('derived member sets match the signature signal fields', () {
      bool hasSlow(Character member) =>
          GameBalance.towerStats(
            member.style,
            level: 3,
            specialization: member.signature,
          ).slowMultiplier <
          1;
      final slowMembers = Character.values.where(hasSlow).toSet();
      expect(
        CodexData.effects
            .firstWhere((e) => e.id == 'slow')
            .relatedCharacters
            .toSet(),
        slowMembers,
      );
      expect(slowMembers, isNotEmpty);
    });

    test('no unused specialization can appear as a Used-by relation', () {
      // The relations are built from Character.values + fixed signatures, so
      // Hunter Bay / Overload Relay / Replicator Nanites / Crush Well can
      // never leak in — verify against every effect AND its search terms.
      for (final e in CodexData.effects) {
        for (final spec in _unusedSignatures) {
          expect(
            e.relatedCharacters.map((member) => member.signature),
            isNot(contains(spec)),
            reason: '${e.id} advertises ${spec.label}',
          );
          expect(
            e.searchTerms.join(' '),
            isNot(contains(spec.label)),
            reason: '${e.id} search terms mention ${spec.label}',
          );
        }
      }
      // A spot check: drones resolve to Tetsuo's Interceptor Bay only —
      // never Hunter Bay.
      expect(
        CodexData.effects.firstWhere((e) => e.id == 'drones').relatedCharacters,
        [Character.tetsuo],
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
        CodexData.characters.first.searchTerms,
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
      final haruto = CodexData.characters
          .firstWhere((c) => c.character == Character.haruto)
          .searchTerms;
      expect(codexMatches('STEADY VOLLEY', haruto), isTrue);
      expect(codexMatches('  steady volley  ', haruto), isTrue);
      // A mid-term fragment matches: substring, not exact equality.
      expect(codexMatches('teady volle', haruto), isTrue);
      // The query must occur contiguously; token matching is not allowed.
      expect(codexMatches('volley steady', haruto), isFalse);
      // The whole query must occur inside a term; extra characters break it.
      expect(codexMatches('steady volleyz', haruto), isFalse);
      expect(codexMatches('intergalactic toaster', haruto), isFalse);
    });

    test('each signature name or role description finds its member', () {
      for (final entry in CodexData.characters) {
        expect(
          codexMatches(entry.character.signatureName, entry.searchTerms),
          isTrue,
          reason: entry.character.name,
        );
        expect(
          codexMatches(entry.signature.description, entry.searchTerms),
          isTrue,
          reason: entry.character.name,
        );
      }
    });

    test('querying "Steady Volley" finds exactly Haruto', () {
      final hits = CodexData.characters
          .where((c) => codexMatches('Steady Volley', c.searchTerms))
          .toList();
      expect(hits, hasLength(1));
      expect(hits.single.character, Character.haruto);
    });

    test('an unused specialization name finds nothing', () {
      for (final spec in _unusedSignatures) {
        expect(
          CodexData.characters
              .where((c) => codexMatches(spec.label, c.searchTerms))
              .toList(),
          isEmpty,
          reason: spec.name,
        );
      }
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

    test('effect titles, descriptions, and related member names match', () {
      for (final effect in CodexData.effects) {
        expect(codexMatches(effect.title, effect.searchTerms), isTrue);
        expect(codexMatches(effect.description, effect.searchTerms), isTrue);
        for (final member in effect.relatedCharacters) {
          expect(
            codexMatches(member.displayName, effect.searchTerms),
            isTrue,
            reason: '${effect.id} / ${member.name}',
          );
          expect(
            codexMatches(member.signatureName, effect.searchTerms),
            isTrue,
            reason: '${effect.id} / ${member.name}',
          );
        }
      }
    });

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
