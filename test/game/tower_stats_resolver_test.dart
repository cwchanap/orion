import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/tower_stats_resolver.dart';

void main() {
  // Use the simplest possible PlacedTower fixtures. The resolver reads the
  // member identity (and persistent level) off the tower itself, so position
  // is irrelevant. Unscaled assertions use rank-e members whose factor is 1.
  PlacedTower tower(Character character) => PlacedTower(
    id: 1,
    character: character,
    position: const GridPosition(0, 0),
  );

  group('TowerStatsResolver.resolve', () {
    test('base stats are unchanged by campaign progress modifiers', () {
      // Campaign modifiers now carry only side-stage rewards (starting
      // gold/health, Challenge Badge) — nothing that touches tower stats.
      const mods = CampaignModifiers(bonusGold: 15, bonusHealth: 3);
      final stats = TowerStatsResolver.resolve(
        tower(Character.haruto),
        campaignModifiers: mods,
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(stats.damage, base.damage);
      expect(stats.slowDuration, base.slowDuration);
    });

    test('applies run modules after character scaling', () {
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final factor = GameBalance.characterScalingFactor(
        Character.hikari.rank,
        1,
      );
      final resolved = TowerStatsResolver.resolve(
        tower(Character.hikari),
        runModules: const [RunModuleId.heavyCaliber],
      );
      expect(
        resolved.damage,
        closeTo(
          base.damage *
              factor *
              runModuleDefinition(RunModuleId.heavyCaliber).damageMultiplier,
          1e-9,
        ),
      );
    });

    test('laser damage unchanged for an unscaled starter member', () {
      // Haruto is rank e with a 1.0 base multiplier, so the persistent
      // character pipeline leaves his tier-1 damage at the style base.
      final stats = TowerStatsResolver.resolve(
        tower(Character.haruto),
        campaignModifiers: CampaignModifiers.empty,
      );
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      expect(stats.damage, base.damage);
    });

    test(
      'amplifies Gravity Well radius and duration after base resolution',
      () {
        const tower = PlacedTower(
          id: 1,
          character: Character.ren,
          position: GridPosition(0, 0),
        );
        final base = GameBalance.towerStats(TowerType.gravityWell, level: 1);
        final unamplified = TowerStatsResolver.resolve(tower);

        final resolved = TowerStatsResolver.resolve(
          tower,
          stageModifiers: const [StageModifier.amplifiedGravityWells],
        );

        expect(resolved.fieldRadius, closeTo(base.fieldRadius * 1.20, 0.001));
        expect(
          resolved.fieldDuration,
          closeTo(base.fieldDuration * 1.25, 0.001),
        );
        expect(resolved.damage, unamplified.damage);
        expect(resolved.range, unamplified.range);
      },
    );

    test(
      'amplified gravity stage and Gravity Echo compose multiplicatively',
      () {
        const tower = PlacedTower(
          id: 1,
          character: Character.ren,
          position: GridPosition(0, 0),
        );
        final base = GameBalance.towerStats(TowerType.gravityWell, level: 1);
        final unamplified = TowerStatsResolver.resolve(tower);

        final resolved = TowerStatsResolver.resolve(
          tower,
          stageModifiers: const [StageModifier.amplifiedGravityWells],
          runModules: const [RunModuleId.gravityEcho],
        );

        // Gravity Echo grows the post-modifier (stage-amplified) radius.
        expect(
          resolved.fieldRadius,
          closeTo(base.fieldRadius * 1.20 * 1.15, 1e-9),
        );
        expect(
          resolved.fieldDuration,
          closeTo(base.fieldDuration * 1.25, 1e-9),
        );
        expect(resolved.damage, unamplified.damage);
        expect(resolved.range, unamplified.range);
      },
    );

    test('character scaling then Aurora Focus compose in order', () {
      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final factor = GameBalance.characterScalingFactor(
        Character.hikari.rank,
        1,
      );
      final resolved = TowerStatsResolver.resolve(
        tower(Character.hikari),
        runModules: const [RunModuleId.auroraFocus],
      );
      expect(resolved.damage, closeTo(base.damage * factor, 1e-9));
      expect(resolved.fireInterval, closeTo(base.fireInterval * 0.88, 1e-9));
      expect(resolved.range, base.range);
    });

    test('Siege Rounds pierce bonus survives stage and module composition', () {
      final base = GameBalance.towerStats(TowerType.railgun, level: 1);
      final memberFactor = GameBalance.characterScalingFactor(
        Character.sayo.rank,
        1,
      );
      final resolved = TowerStatsResolver.resolve(
        tower(Character.sayo),
        stageModifiers: StageModifier.values,
        runModules: const [RunModuleId.siegeRounds, RunModuleId.heavyCaliber],
      );
      expect(resolved.pierceCount, base.pierceCount + 1);
      expect(resolved.damage, closeTo(base.damage * memberFactor * 1.20, 1e-9));
    });

    test('amplified wells leave every other tower type unchanged', () {
      for (final character in Character.values.where(
        (character) => character.style != TowerType.gravityWell,
      )) {
        final tower = PlacedTower(
          id: character.index,
          character: character,
          position: const GridPosition(0, 0),
        );
        final unamplified = TowerStatsResolver.resolve(tower);
        final resolved = TowerStatsResolver.resolve(
          tower,
          stageModifiers: const [StageModifier.amplifiedGravityWells],
        );

        expect(resolved.fieldRadius, unamplified.fieldRadius);
        expect(resolved.fieldDuration, unamplified.fieldDuration);
        expect(resolved.damage, unamplified.damage);
        expect(resolved.range, unamplified.range);
      }
    });

    test(
      'explicit empty run modules preserve character and stage modifiers',
      () {
        final laserDefault = TowerStatsResolver.resolve(
          tower(Character.hikari),
        );
        final laserExplicitEmpty = TowerStatsResolver.resolve(
          tower(Character.hikari),
          runModules: const [],
        );
        expect(laserExplicitEmpty.damage, laserDefault.damage);

        final cryoDefault = TowerStatsResolver.resolve(tower(Character.jin));
        final cryoExplicitEmpty = TowerStatsResolver.resolve(
          tower(Character.jin),
          runModules: const [],
        );
        expect(cryoExplicitEmpty.slowDuration, cryoDefault.slowDuration);

        final gravityDefault = TowerStatsResolver.resolve(
          tower(Character.ren),
          stageModifiers: const [StageModifier.amplifiedGravityWells],
        );
        final gravityExplicitEmpty = TowerStatsResolver.resolve(
          tower(Character.ren),
          stageModifiers: const [StageModifier.amplifiedGravityWells],
          runModules: const [],
        );
        expect(gravityExplicitEmpty.fieldRadius, gravityDefault.fieldRadius);
        expect(
          gravityExplicitEmpty.fieldDuration,
          gravityDefault.fieldDuration,
        );
      },
    );

    test('all modifiers preserve base progression costs', () {
      const campaignModifiers = CampaignModifiers(
        bonusGold: 15,
        bonusHealth: 3,
      );

      for (final character in Character.values) {
        final type = character.style;
        for (final tier in [1, 2, 3]) {
          final tower = PlacedTower(
            id: 1,
            character: character,
            position: const GridPosition(0, 0),
            level: tier,
          );
          final base = GameBalance.towerStats(
            type,
            level: tier,
            specialization: tier == 3 ? character.signature : null,
          );
          final resolved = TowerStatsResolver.resolve(
            tower,
            campaignModifiers: campaignModifiers,
            stageModifiers: StageModifier.values,
            runModules: RunModuleId.values,
          );

          expect(resolved.cost, base.cost, reason: '$type tier $tier');
          expect(
            resolved.upgradeCost,
            base.upgradeCost,
            reason: '$type tier $tier',
          );
          expect(
            resolved.specializationCost,
            base.specializationCost,
            reason: '$type tier $tier',
          );
        }
      }
    });
  });

  group('character-aware resolution', () {
    // The tower carries its member identity and persistent level; tier 3
    // derives the member's fixed signature automatically.
    PlacedTower characterTower(
      Character character, {
      int tier = 1,
      int level = 1,
    }) {
      return PlacedTower(
        id: 1,
        character: character,
        characterLevel: level,
        position: const GridPosition(0, 0),
        level: tier,
      );
    }

    TowerStats baseStats(Character character, {int tier = 1}) =>
        GameBalance.towerStats(
          character.style,
          level: tier,
          specialization: tier == 3 ? character.signature : null,
        );

    test(
      'every roster member scales all three damage channels at levels 1 and 40',
      () {
        for (final character in Character.values) {
          for (final level in [1, 40]) {
            final factor = GameBalance.characterScalingFactor(
              character.rank,
              level,
            );
            for (final tier in [1, 2, 3]) {
              final reason = '${character.name} level $level tier $tier';
              final base = baseStats(character, tier: tier);
              final resolved = TowerStatsResolver.resolve(
                characterTower(character, tier: tier, level: level),
              );

              expect(
                resolved.damage,
                closeTo(base.damage * factor, 1e-9),
                reason: reason,
              );
              expect(
                resolved.corrosionDamagePerSecond,
                closeTo(base.corrosionDamagePerSecond * factor, 1e-9),
                reason: reason,
              );
              expect(
                resolved.droneDamage,
                closeTo(base.droneDamage * factor, 1e-9),
                reason: reason,
              );
            }
          }
        }
      },
    );

    test('Shiori corrosion scales with rank and level', () {
      final base = baseStats(Character.shiori);
      final resolved = TowerStatsResolver.resolve(
        characterTower(Character.shiori, level: 40),
      );

      expect(
        resolved.corrosionDamagePerSecond,
        closeTo(base.corrosionDamagePerSecond * 1.6 * 1.975, 1e-9),
      );
      expect(resolved.damage, closeTo(base.damage * 1.6 * 1.975, 1e-9));
      expect(resolved.armorShred, base.armorShred);
      expect(resolved.corrosionDuration, base.corrosionDuration);
    });

    test('Tetsuo drone damage scales with rank and level', () {
      final base = baseStats(Character.tetsuo, tier: 3);
      final resolved = TowerStatsResolver.resolve(
        characterTower(Character.tetsuo, tier: 3, level: 40),
      );

      expect(
        resolved.droneDamage,
        closeTo(base.droneDamage * 1.2 * 1.975, 1e-9),
      );
      expect(resolved.droneCount, base.droneCount);
      expect(resolved.maxActiveDrones, base.maxActiveDrones);
      expect(resolved.droneAttackInterval, base.droneAttackInterval);
    });

    test('character scaling applies before run modules', () {
      final base = baseStats(Character.tetsuo);
      final factor = GameBalance.characterScalingFactor(
        Character.tetsuo.rank,
        40,
      );
      final heavy = runModuleDefinition(RunModuleId.heavyCaliber);

      final resolved = TowerStatsResolver.resolve(
        characterTower(Character.tetsuo, level: 40),
        runModules: const [RunModuleId.heavyCaliber],
      );

      expect(
        resolved.droneDamage,
        closeTo(base.droneDamage * factor * heavy.damageMultiplier, 1e-9),
      );
      expect(
        resolved.fireInterval,
        closeTo(base.fireInterval * heavy.fireIntervalMultiplier, 1e-9),
      );
    });

    test('character scaling composes with stage field amplification', () {
      final base = baseStats(Character.ren);
      final factor = GameBalance.characterScalingFactor(Character.ren.rank, 40);

      final resolved = TowerStatsResolver.resolve(
        characterTower(Character.ren, level: 40),
        stageModifiers: const [StageModifier.amplifiedGravityWells],
        runModules: const [RunModuleId.gravityEcho],
      );

      // The rank/level factor never leaks into field channels; stage then
      // module multipliers compose on top of the untouched base radius.
      expect(
        resolved.fieldRadius,
        closeTo(base.fieldRadius * 1.20 * 1.15, 1e-9),
      );
      expect(resolved.fieldDuration, closeTo(base.fieldDuration * 1.25, 1e-9));
      expect(resolved.damage, closeTo(base.damage * factor, 1e-9));
    });

    test('non-damage effects survive character scaling at every tier', () {
      final jinBase = baseStats(Character.jin, tier: 3);
      final jin = TowerStatsResolver.resolve(
        characterTower(Character.jin, tier: 3, level: 40),
      );
      expect(jin.slowDuration, jinBase.slowDuration);
      expect(jin.slowMultiplier, jinBase.slowMultiplier);

      final rinBase = baseStats(Character.rin, tier: 3);
      final rin = TowerStatsResolver.resolve(
        characterTower(Character.rin, tier: 3, level: 40),
      );
      expect(rin.slowedDamageMultiplier, rinBase.slowedDamageMultiplier);
      expect(rin.damage, closeTo(rinBase.damage * 1.4 * 1.975, 1e-9));

      final sayoBase = baseStats(Character.sayo, tier: 3);
      final sayo = TowerStatsResolver.resolve(
        characterTower(Character.sayo, tier: 3, level: 1),
      );
      expect(sayo.pierceCount, sayoBase.pierceCount);
      expect(sayo.pierceWidth, sayoBase.pierceWidth);

      final kaitoBase = baseStats(Character.kaito, tier: 3);
      final kaito = TowerStatsResolver.resolve(
        characterTower(Character.kaito, tier: 3, level: 40),
      );
      expect(kaito.chainCount, kaitoBase.chainCount);
      expect(kaito.chainRange, kaitoBase.chainRange);
      expect(kaito.chainFalloff, kaitoBase.chainFalloff);
    });

    test(
      'character calls scale damage and leave non-damage channels at base',
      () {
        final hikariBase = baseStats(Character.hikari);
        final hikari = TowerStatsResolver.resolve(
          characterTower(Character.hikari),
        );
        expect(hikari.damage, closeTo(hikariBase.damage * 2.0, 1e-9));

        final jinBase = baseStats(Character.jin);
        final jin = TowerStatsResolver.resolve(characterTower(Character.jin));
        expect(jin.slowDuration, jinBase.slowDuration);
      },
    );

    test('character scaling preserves style-based prices and tier costs', () {
      for (final character in Character.values) {
        for (final tier in [1, 2, 3]) {
          final base = baseStats(character, tier: tier);
          final resolved = TowerStatsResolver.resolve(
            characterTower(character, tier: tier),
          );

          expect(resolved.cost, base.cost, reason: character.name);
          expect(
            resolved.upgradeCost,
            base.upgradeCost,
            reason: character.name,
          );
          expect(
            resolved.specializationCost,
            base.specializationCost,
            reason: character.name,
          );
          expect(
            resolved.nextUpgradeCost,
            base.nextUpgradeCost,
            reason: character.name,
          );
        }
      }
    });

    test('level input clamps to the 1-40 band', () {
      final at40 = TowerStatsResolver.resolve(characterTower(Character.hikari));
      final at99 = TowerStatsResolver.resolve(characterTower(Character.hikari));
      final at0 = TowerStatsResolver.resolve(characterTower(Character.hikari));
      final at1 = TowerStatsResolver.resolve(characterTower(Character.hikari));

      expect(at99.damage, at40.damage);
      expect(at0.damage, at1.damage);
    });
  });
}
