import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('StageResult', () {
    test('calculates medal thresholds from victory base health', () {
      expect(
        StageResult.fromVictoryBaseHealth(GameBalance.initialBaseHealth),
        const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: GameBalance.initialBaseHealth,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(10),
        const StageResult(medal: StageMedal.silver, bestBaseHealth: 10),
      );
      expect(
        StageResult.fromVictoryBaseHealth(9),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 9),
      );
    });

    test('clamps victory base health into the supported range', () {
      expect(
        StageResult.fromVictoryBaseHealth(GameBalance.initialBaseHealth + 1),
        const StageResult(
          medal: StageMedal.gold,
          bestBaseHealth: GameBalance.initialBaseHealth,
        ),
      );
      expect(
        StageResult.fromVictoryBaseHealth(-1),
        const StageResult(medal: StageMedal.clear, bestBaseHealth: 0),
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
        StageResult.fromJson({'medal': 'silver', 'bestBaseHealth': 21}),
        isNull,
      );
      expect(
        StageResult.fromJson({'medal': 'platinum', 'bestBaseHealth': 12}),
        isNull,
      );
      expect(
        StageResult.fromJson({'medal': 'gold', 'bestBaseHealth': 19}),
        isNull,
      );
      expect(
        StageResult.fromJson({'medal': 'silver', 'bestBaseHealth': 9}),
        isNull,
      );
      expect(
        StageResult.fromJson({'medal': 'clear', 'bestBaseHealth': 10}),
        isNull,
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
}

StageDefinition _stage({
  required String id,
  List<String> dependencies = const [],
  bool isMainPath = true,
  int? mainPathOrder,
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
    mapColumn: mainPathOrder ?? 0,
    mapRow: isMainPath ? 1 : 0,
  );
}
