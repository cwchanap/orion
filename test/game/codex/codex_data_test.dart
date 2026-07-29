import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_modifier_metadata.dart';
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

    test(
      'every effect resolves to >= 1 related specialization by derivation',
      () {
        for (final e in CodexData.effects) {
          expect(
            e.relatedSpecializations,
            isNotEmpty,
            reason: '${e.id} should map to >= 1 specialization',
          );
          for (final spec in e.relatedSpecializations) {
            expect(spec, isA<TowerSpecialization>());
          }
        }
      },
    );

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
  });
}
