import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/campaign/tech_tree.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('StageResult', () {
    test('calculates medal thresholds from victory base health', () {
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.initialBaseHealth,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: GameBalance.initialBaseHealth,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.silverMedalThreshold,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.silver,
          bestBaseHealth: GameBalance.silverMedalThreshold,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.silverMedalThreshold - 1,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: GameBalance.silverMedalThreshold - 1,
        ),
      );
    });

    test('clamps victory base health into the supported range', () {
      expect(
        StageResult.fromVictoryBaseHealth(
          GameBalance.initialBaseHealth + 1,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: GameBalance.initialBaseHealth,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(
          -1,
          startingBaseHealth: GameBalance.initialBaseHealth,
        ),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 0),
      );
    });

    test('medal thresholds scale with bonus starting health', () {
      const bonusHealth = 25;

      expect(
        StageResult.fromVictoryBaseHealth(25, startingBaseHealth: bonusHealth),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 25),
      );
      expect(
        StageResult.fromVictoryBaseHealth(23, startingBaseHealth: bonusHealth),
        const StageResult(medal: StageMedal.silver, bestBaseHealth: 23),
      );
      expect(
        StageResult.fromVictoryBaseHealth(9, startingBaseHealth: bonusHealth),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 9),
      );
    });

    test('compares by medal first and base health second', () {
      const clearNine = StageResult(medal: StageMedal.clear, bestBaseHealth: 9);
      const silverTen = StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 10,
      );
      const silverFourteen = StageResult(
        medal: StageMedal.silver,
        bestBaseHealth: 14,
      );
      const goldTwenty = StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      );

      expect(clearNine.isBetterThan(null), isTrue);
      expect(silverTen.isBetterThan(clearNine), isTrue);
      expect(silverFourteen.isBetterThan(silverTen), isTrue);
      expect(silverTen.isBetterThan(silverFourteen), isFalse);
      expect(goldTwenty.isBetterThan(silverFourteen), isTrue);
      expect(silverFourteen.isBetterThan(goldTwenty), isFalse);
    });

    test('serializes and rejects invalid payloads', () {
      const result = StageResult(medal: StageMedal.silver, bestBaseHealth: 12);

      expect(StageMedal.silver.rank, 2);
      expect(StageMedal.silver.label, 'Silver');
      expect(StageMedal.silver.serializedName, 'silver');
      expect(StageMedal.fromSerializedName('silver'), StageMedal.silver);
      expect(StageMedal.fromSerializedName('platinum'), isNull);
      expect(result.toJson(), {'medal': 'silver', 'bestBaseHealth': 12});
      expect(StageResult.fromJson(result.toJson()), result);
      expect(
        StageResult.fromJson({'medal': 'silver', 'bestBaseHealth': -1}),
        isNull,
      );
      expect(
        StageResult.fromJson({'medal': 'platinum', 'bestBaseHealth': 12}),
        isNull,
      );
    });

    test('fromJson preserves the stored medal without re-deriving it', () {
      // Saved medals must survive even if `bestBaseHealth` no longer maps to
      // the same medal under the current `silverMedalThreshold`. This keeps
      // persisted state stable across tuning changes.
      expect(
        StageResult.fromJson({'medal': 'gold', 'bestBaseHealth': 19}),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 19),
      );
      expect(
        StageResult.fromJson({'medal': 'silver', 'bestBaseHealth': 9}),
        const StageResult(medal: StageMedal.silver, bestBaseHealth: 9),
      );
      expect(
        StageResult.fromJson({'medal': 'clear', 'bestBaseHealth': 10}),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 10),
      );
    });
  });

  group('CampaignProgress', () {
    final stages = [
      _stage(id: 'stage-1', mainPathOrder: 1),
      _stage(id: 'stage-2', dependencies: ['stage-1'], mainPathOrder: 2),
      _stage(id: 'stage-3', dependencies: ['stage-2'], mainPathOrder: 3),
      _stage(id: 'stage-4', dependencies: ['stage-3'], mainPathOrder: 4),
      _stage(id: 'stage-5', dependencies: ['stage-4'], mainPathOrder: 5),
      _stage(id: 'side-a', dependencies: ['stage-2'], isMainPath: false),
      _stage(id: 'side-b', dependencies: ['stage-4'], isMainPath: false),
    ];

    test('unlocks stage one by default and derives locked stages', () {
      final progress = CampaignProgress();

      expect(progress.isCleared('stage-1'), isFalse);
      expect(progress.resultFor('stage-1'), isNull);
      expect(progress.isUnlocked(stages[0]), isTrue);
      expect(progress.isUnlocked(stages[1]), isFalse);
      expect(progress.statusFor(stages[0]), StageProgressStatus.unlocked);
      expect(progress.statusFor(stages[1]), StageProgressStatus.locked);
    });

    test('unlocks main path and side stages from completed results', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'stage-1': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 5,
          ),
          'stage-2': const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 12,
          ),
          'stage-3': const StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
          'stage-4': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 3,
          ),
        },
      );

      expect(progress.isUnlocked(stages[4]), isTrue);
      expect(progress.isUnlocked(stages[5]), isTrue);
      expect(progress.isUnlocked(stages[6]), isTrue);
      expect(progress.statusFor(stages[0]), StageProgressStatus.cleared);
      expect(progress.resultFor('stage-2')!.medal, StageMedal.silver);
    });

    test('completes campaign when all main stages have results', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          for (final id in [
            'stage-1',
            'stage-2',
            'stage-3',
            'stage-4',
            'stage-5',
          ])
            id: const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
        },
      );

      expect(progress.isCampaignComplete(stages), isTrue);
      expect(
        progress.isCampaignComplete(stages.where((stage) => stage.isMainPath)),
        isTrue,
      );
    });

    test('incomplete, empty, and side-only collections are not complete', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'stage-1': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );
      final sideProgress = CampaignProgress(
        bestResultsByStageId: {
          'side-only': const StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
        },
      );

      expect(progress.isCampaignComplete(stages), isFalse);
      expect(progress.isCampaignComplete(const <StageDefinition>[]), isFalse);
      expect(
        sideProgress.isCampaignComplete([
          _stage(id: 'side-only', isMainPath: false),
        ]),
        isFalse,
      );
    });

    test('recordResult improves but never downgrades a saved result', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'stage-1': const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 10,
          ),
        },
      );

      final worse = progress.recordResult(
        'stage-1',
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 9),
      );
      final sameMedalBetter = progress.recordResult(
        'stage-1',
        const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      final betterMedal = sameMedalBetter.recordResult(
        'stage-1',
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );

      expect(worse.resultFor('stage-1'), progress.resultFor('stage-1'));
      expect(
        sameMedalBetter.resultFor('stage-1'),
        const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
      );
      expect(
        betterMedal.resultFor('stage-1'),
        const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      );
    });

    test('withoutUnknownStages filters unknown results', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'stage-1': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
          'side-a': const StageResult(
            medal: StageMedal.silver,
            bestBaseHealth: 11,
          ),
          'unknown-stage': const StageResult(
            medal: StageMedal.gold,
            bestBaseHealth: 20,
          ),
        },
      );

      final filtered = progress.withoutUnknownStages(stages.take(2));

      expect(filtered.bestResultsByStageId.keys, {'stage-1'});
      expect(progress.bestResultsByStageId.keys, {
        'stage-1',
        'side-a',
        'unknown-stage',
      });
      expect(
        () => filtered.bestResultsByStageId['stage-2'] = const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
        throwsUnsupportedError,
      );
    });

    test('constructor defensively copies mutable input', () {
      final results = {
        'stage-1': const StageResult(
          medal: StageMedal.clear,
          bestBaseHealth: 1,
        ),
      };
      final progress = CampaignProgress(bestResultsByStageId: results);

      results['stage-2'] = const StageResult(
        medal: StageMedal.gold,
        bestBaseHealth: 20,
      );

      expect(progress.bestResultsByStageId.keys, {'stage-1'});
      expect(progress.isCleared('stage-2'), isFalse);
      expect(
        () => progress.bestResultsByStageId.clear(),
        throwsUnsupportedError,
      );
    });

    test('cleared stage with unmet dependencies is still completed', () {
      final dependentStage = _stage(
        id: 'dependent-stage',
        dependencies: ['missing-stage'],
      );
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'dependent-stage': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      expect(progress.isUnlocked(dependentStage), isFalse);
      expect(progress.statusFor(dependentStage), StageProgressStatus.cleared);
    });

    group('withResult (save-rollback helper)', () {
      test('removes a stage result when passed null', () {
        final progress = CampaignProgress(
          bestResultsByStageId: {
            'alpha': const StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
            'relay': const StageResult(
              medal: StageMedal.silver,
              bestBaseHealth: 14,
            ),
          },
        );

        final rolled = progress.withResult('alpha', null);

        expect(rolled.bestResultsByStageId.keys, {'relay'});
        expect(rolled.resultFor('alpha'), isNull);
        // Other stages are untouched.
        expect(
          rolled.resultFor('relay'),
          const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
        );
      });

      test('restores a prior result without touching other stages', () {
        final progress = CampaignProgress(
          bestResultsByStageId: {
            'alpha': const StageResult(
              medal: StageMedal.gold,
              bestBaseHealth: 20,
            ),
            'relay': const StageResult(
              medal: StageMedal.silver,
              bestBaseHealth: 14,
            ),
          },
        );

        final rolled = progress.withResult(
          'alpha',
          const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
        );

        expect(
          rolled.resultFor('alpha'),
          const StageResult(medal: StageMedal.clear, bestBaseHealth: 1),
        );
        expect(
          rolled.resultFor('relay'),
          const StageResult(medal: StageMedal.silver, bestBaseHealth: 14),
        );
      });

      test('returns same instance when removing a missing stage', () {
        final progress = CampaignProgress();
        expect(
          identical(progress.withResult('absent', null), progress),
          isTrue,
        );
      });
    });
  });

  group('StageDefinition', () {
    test('defensively copies mutable input lists', () {
      final pathCells = [const GridPosition(0, 0), const GridPosition(1, 0)];
      final waves = GameBalance.waves.toList();
      final dependencies = ['stage-1'];

      final stage = StageDefinition(
        id: 'stage-2',
        name: 'stage-2',
        mapLabel: 'stage-2',
        description: 'stage-2',
        pathCells: pathCells,
        waves: waves,
        unlockDependencies: dependencies,
        mapColumn: 2,
        mapRow: 1,
      );

      pathCells.add(const GridPosition(2, 0));
      waves.removeLast();
      dependencies.add('stage-unknown');

      expect(stage.pathCells, const [GridPosition(0, 0), GridPosition(1, 0)]);
      expect(stage.waves, GameBalance.waves);
      expect(stage.unlockDependencies, ['stage-1']);
    });

    test('list fields are not externally mutable', () {
      final stage = _stage(id: 'stage-1', dependencies: ['intro']);

      expect(
        () => stage.pathCells.add(const GridPosition(2, 0)),
        throwsUnsupportedError,
      );
      expect(
        () => stage.waves.add(GameBalance.waves.first),
        throwsUnsupportedError,
      );
      expect(
        () => stage.unlockDependencies.add('stage-2'),
        throwsUnsupportedError,
      );
    });
  });

  group('CampaignModifiers', () {
    final stages = [
      _stage(id: 'stage-1', mainPathOrder: 1),
      _stage(id: 'stage-2', dependencies: ['stage-1'], mainPathOrder: 2),
      _stage(id: 'stage-3', dependencies: ['stage-2'], mainPathOrder: 3),
      _stage(id: 'stage-4', dependencies: ['stage-3'], mainPathOrder: 4),
      _stage(id: 'stage-5', dependencies: ['stage-4'], mainPathOrder: 5),
      _stage(
        id: 'side-a',
        dependencies: ['stage-2'],
        isMainPath: false,
        reward: CampaignReward.bonusGold,
      ),
      _stage(
        id: 'side-b',
        dependencies: ['stage-4'],
        isMainPath: false,
        reward: CampaignReward.bonusHealth,
      ),
    ];

    test('empty progress yields zero modifiers', () {
      const modifiers = CampaignModifiers.empty;

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
      expect(modifiers.adjustedStartingGold, GameBalance.startingGold);
      expect(
        modifiers.adjustedStartingBaseHealth,
        GameBalance.initialBaseHealth,
      );
    });

    test('fromProgress with no clears returns empty modifiers', () {
      final modifiers = CampaignModifiers.fromProgress(
        CampaignProgress(),
        stages,
        CampaignTechTree(),
      );

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
    });

    test('fromProgress with only bonusGold stage cleared grants gold', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'side-a': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(
        progress,
        stages,
        CampaignTechTree(),
      );

      expect(modifiers.bonusGold, GameBalance.salvageRiftGoldBonus);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
      expect(
        modifiers.adjustedStartingGold,
        GameBalance.startingGold + GameBalance.salvageRiftGoldBonus,
      );
    });

    test('fromProgress with only bonusHealth stage cleared grants health', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'side-b': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(
        progress,
        stages,
        CampaignTechTree(),
      );

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, GameBalance.voidBastionHealthBonus);
      expect(modifiers.hasChallengeBadge, isFalse);
      expect(
        modifiers.adjustedStartingBaseHealth,
        GameBalance.initialBaseHealth + GameBalance.voidBastionHealthBonus,
      );
    });

    test('fromProgress with both side stages cleared grants badge', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          'side-a': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
          'side-b': const StageResult(
            medal: StageMedal.clear,
            bestBaseHealth: 1,
          ),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(
        progress,
        stages,
        CampaignTechTree(),
      );

      expect(modifiers.bonusGold, GameBalance.salvageRiftGoldBonus);
      expect(modifiers.bonusHealth, GameBalance.voidBastionHealthBonus);
      expect(modifiers.hasChallengeBadge, isTrue);
    });

    test('fromProgress ignores main stage clears for badge', () {
      final progress = CampaignProgress(
        bestResultsByStageId: {
          for (final id in [
            'stage-1',
            'stage-2',
            'stage-3',
            'stage-4',
            'stage-5',
          ])
            id: const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
        },
      );

      final modifiers = CampaignModifiers.fromProgress(
        progress,
        stages,
        CampaignTechTree(),
      );

      expect(modifiers.bonusGold, 0);
      expect(modifiers.bonusHealth, 0);
      expect(modifiers.hasChallengeBadge, isFalse);
    });

    group('tech-tree effects', () {
      CampaignTechTree treeWith(CampaignTechUpgrade upgrade) =>
          CampaignTechTree(purchased: {upgrade});

      test('solarCapacitors adds solarCapacitorsGoldBonus to bonusGold', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.solarCapacitors),
        );
        expect(mods.bonusGold, GameBalance.solarCapacitorsGoldBonus);
        expect(mods.bonusHealth, 0);
      });

      test('hardenedCore adds hardenedCoreHealthBonus to bonusHealth', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.hardenedCore),
        );
        expect(mods.bonusHealth, GameBalance.hardenedCoreHealthBonus);
        expect(mods.bonusGold, 0);
      });

      test('salvageCrew sets clearBonusFraction', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.salvageCrew),
        );
        expect(
          mods.clearBonusFraction,
          GameBalance.salvageCrewClearBonusFraction,
        );
      });

      test('laserTuning sets laserDamageFraction', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.laserTuning),
        );
        expect(mods.laserDamageFraction, GameBalance.laserTuningDamageFraction);
      });

      test('cryoCoolant sets cryoSlowDurationBonus', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          treeWith(CampaignTechUpgrade.cryoCoolant),
        );
        expect(
          mods.cryoSlowDurationBonus,
          GameBalance.cryoCoolantSlowDurationBonus,
        );
      });

      test('all five upgrades stack with each other', () {
        final all = CampaignTechTree(
          purchased: CampaignTechUpgrade.values.toSet(),
        );
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          all,
        );
        expect(mods.bonusGold, GameBalance.solarCapacitorsGoldBonus);
        expect(mods.bonusHealth, GameBalance.hardenedCoreHealthBonus);
        expect(
          mods.clearBonusFraction,
          GameBalance.salvageCrewClearBonusFraction,
        );
        expect(mods.laserDamageFraction, GameBalance.laserTuningDamageFraction);
        expect(
          mods.cryoSlowDurationBonus,
          GameBalance.cryoCoolantSlowDurationBonus,
        );
      });

      test('empty tech tree behaves like HPA-94 (no tech fields set)', () {
        final mods = CampaignModifiers.fromProgress(
          CampaignProgress(),
          const [],
          CampaignTechTree(),
        );
        expect(mods.bonusGold, 0);
        expect(mods.bonusHealth, 0);
        expect(mods.clearBonusFraction, 0);
        expect(mods.laserDamageFraction, 0);
        expect(mods.cryoSlowDurationBonus, 0);
      });
    });

    test(
      'solarCapacitors stacks additively with Salvage Rift side-stage reward',
      () {
        // Salvage Rift is the side stage with CampaignReward.bonusGold.
        final salvageRift = StageDefinition(
          id: 'salvage-rift',
          name: 'Salvage Rift',
          mapLabel: 'Rift',
          description: '',
          pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
          waves: const [],
          isMainPath: false,
          reward: CampaignReward.bonusGold,
          mapColumn: 0,
          mapRow: 0,
        );
        final cleared = CampaignProgress(
          bestResultsByStageId: {
            salvageRift.id: const StageResult(
              medal: StageMedal.clear,
              bestBaseHealth: 1,
            ),
          },
        );
        final tree = CampaignTechTree(
          purchased: {CampaignTechUpgrade.solarCapacitors},
        );
        final mods = CampaignModifiers.fromProgress(cleared, [
          salvageRift,
        ], tree);
        expect(
          mods.bonusGold,
          GameBalance.salvageRiftGoldBonus +
              GameBalance.solarCapacitorsGoldBonus,
        );
      },
    );
  });
}

StageDefinition _stage({
  required String id,
  List<String> dependencies = const [],
  bool isMainPath = true,
  int? mainPathOrder,
  CampaignReward? reward,
}) {
  return StageDefinition(
    id: id,
    name: id,
    mapLabel: id,
    description: id,
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: GameBalance.waves,
    unlockDependencies: dependencies,
    isMainPath: isMainPath,
    mainPathOrder: mainPathOrder,
    reward: reward,
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}
