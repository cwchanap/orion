import 'package:orion/game/models/game_models.dart';

class StageDefinition {
  const StageDefinition({
    required this.id,
    required this.name,
    required this.mapLabel,
    required this.description,
    required this.pathCells,
    required this.waves,
    this.unlockDependencies = const [],
    this.isMainPath = true,
    this.mainPathOrder,
    required this.mapColumn,
    required this.mapRow,
  });

  final String id;
  final String name;
  final String mapLabel;
  final String description;
  final List<GridPosition> pathCells;
  final List<WaveDefinition> waves;
  final List<String> unlockDependencies;
  final bool isMainPath;
  final int? mainPathOrder;
  final int mapColumn;
  final int mapRow;
}
