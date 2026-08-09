import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';

StageDefinition stageWithWaveCount(int count) {
  if (count <= 0) throw ArgumentError.value(count, 'count');
  return StageDefinition(
    id: 'empty-wave-stage-$count',
    name: 'Empty Wave Stage',
    mapLabel: 'Empty',
    description: 'Stage with empty waves for timing tests',
    pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    waves: List<WaveDefinition>.generate(
      count,
      (_) => const WaveDefinition(groups: [], clearBonus: 0),
      growable: false,
    ),
    unlockDependencies: const [],
    isMainPath: true,
    mainPathOrder: 1,
    mapColumn: 0,
    mapRow: 0,
  );
}
