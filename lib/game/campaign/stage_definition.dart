import 'package:orion/game/models/game_models.dart';

class StageDefinition {
  StageDefinition({
    required this.id,
    required this.name,
    required this.mapLabel,
    required this.description,
    required List<GridPosition> pathCells,
    required List<WaveDefinition> waves,
    List<String> unlockDependencies = const [],
    this.isMainPath = true,
    this.mainPathOrder,
    required this.mapColumn,
    required this.mapRow,
  }) : pathCells = List.unmodifiable(pathCells),
       waves = List.unmodifiable(waves),
       unlockDependencies = List.unmodifiable(unlockDependencies);

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
