import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
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
      expect(progress.isUnlocked(stages[0]), isTrue);
      expect(progress.isUnlocked(stages[1]), isFalse);
      expect(progress.statusFor(stages[0]), StageProgressStatus.unlocked);
      expect(progress.statusFor(stages[1]), StageProgressStatus.locked);
    });

    test('unlocks main path and side stages from cleared milestones', () {
      final progress = CampaignProgress(
        clearedStageIds: {'stage-1', 'stage-2', 'stage-3', 'stage-4'},
      );

      expect(progress.isUnlocked(stages[4]), isTrue);
      expect(progress.isUnlocked(stages[5]), isTrue);
      expect(progress.isUnlocked(stages[6]), isTrue);
      expect(progress.statusFor(stages[0]), StageProgressStatus.cleared);
    });

    test('completes campaign when all main stages are cleared', () {
      final withoutSideStages = CampaignProgress(
        clearedStageIds: {
          'stage-1',
          'stage-2',
          'stage-3',
          'stage-4',
          'stage-5',
        },
      );

      expect(withoutSideStages.isCampaignComplete(stages), isTrue);
    });

    test('completes campaign from a non-list iterable of main stages', () {
      final progress = CampaignProgress(
        clearedStageIds: {
          'stage-1',
          'stage-2',
          'stage-3',
          'stage-4',
          'stage-5',
        },
      );

      expect(
        progress.isCampaignComplete(stages.where((stage) => stage.isMainPath)),
        isTrue,
      );
    });

    test('incomplete main path returns false', () {
      final progress = CampaignProgress(
        clearedStageIds: {'stage-1', 'stage-2', 'stage-3', 'stage-4'},
      );

      expect(progress.isCampaignComplete(stages), isFalse);
    });

    test('empty stage collection returns false', () {
      final progress = CampaignProgress();

      expect(progress.isCampaignComplete(const <StageDefinition>[]), isFalse);
    });

    test('side-only stage collection returns false even when cleared', () {
      final sideStage = _stage(id: 'side-only', isMainPath: false);
      final progress = CampaignProgress(clearedStageIds: {'side-only'});

      expect(progress.isCampaignComplete([sideStage]), isFalse);
    });

    test('markCleared returns normalized immutable progress', () {
      final progress = CampaignProgress(clearedStageIds: {'stage-1'});

      final updated = progress.markCleared('stage-2');

      expect(updated.clearedStageIds, {'stage-1', 'stage-2'});
      expect(progress.clearedStageIds, {'stage-1'});
      expect(
        () => updated.clearedStageIds.add('stage-3'),
        throwsUnsupportedError,
      );
    });

    test('withoutUnknownStages filters unknown ids', () {
      final progress = CampaignProgress(
        clearedStageIds: {'stage-1', 'side-a', 'unknown-stage'},
      );

      final filtered = progress.withoutUnknownStages(stages.take(2));

      expect(filtered.clearedStageIds, {'stage-1'});
      expect(progress.clearedStageIds, {'stage-1', 'side-a', 'unknown-stage'});
      expect(
        () => filtered.clearedStageIds.add('stage-2'),
        throwsUnsupportedError,
      );
    });

    test('constructor defensively copies mutable input', () {
      final clearedStageIds = {'stage-1'};
      final progress = CampaignProgress(clearedStageIds: clearedStageIds);

      clearedStageIds.add('stage-2');

      expect(progress.clearedStageIds, {'stage-1'});
      expect(progress.isCleared('stage-2'), isFalse);
      expect(
        () => progress.clearedStageIds.add('stage-3'),
        throwsUnsupportedError,
      );
    });

    test('cleared stage with unmet dependencies is not unlocked', () {
      final dependentStage = _stage(
        id: 'dependent-stage',
        dependencies: ['missing-stage'],
      );
      final progress = CampaignProgress(clearedStageIds: {'dependent-stage'});

      expect(progress.isUnlocked(dependentStage), isFalse);
      expect(progress.statusFor(dependentStage), StageProgressStatus.cleared);
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
