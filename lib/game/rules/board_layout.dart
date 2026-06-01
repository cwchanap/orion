import 'dart:ui';

import '../models/game_models.dart';

class BoardLayout {
  static const int columns = 8;
  static const int rows = 12;

  static const List<GridPosition> pathCells = [
    GridPosition(0, 1),
    GridPosition(1, 1),
    GridPosition(2, 1),
    GridPosition(3, 1),
    GridPosition(3, 2),
    GridPosition(3, 3),
    GridPosition(3, 4),
    GridPosition(4, 4),
    GridPosition(5, 4),
    GridPosition(6, 4),
    GridPosition(6, 5),
    GridPosition(6, 6),
    GridPosition(5, 6),
    GridPosition(4, 6),
    GridPosition(3, 6),
    GridPosition(2, 6),
    GridPosition(2, 7),
    GridPosition(2, 8),
    GridPosition(2, 9),
    GridPosition(3, 9),
    GridPosition(4, 9),
    GridPosition(5, 9),
    GridPosition(6, 9),
    GridPosition(7, 9),
    GridPosition(7, 10),
  ];

  static bool isInBounds(GridPosition position) {
    return position.column >= 0 &&
        position.column < columns &&
        position.row >= 0 &&
        position.row < rows;
  }

  static bool isPathCell(GridPosition position) {
    return pathCells.contains(position);
  }

  static bool isBuildableCell(GridPosition position) {
    return isInBounds(position) && !isPathCell(position);
  }

  static Offset cellCenter(
    GridPosition position, {
    required double cellSize,
    required Offset boardOrigin,
  }) {
    return Offset(
      boardOrigin.dx + (position.column + 0.5) * cellSize,
      boardOrigin.dy + (position.row + 0.5) * cellSize,
    );
  }

  static GridPosition? cellAt(
    Offset point, {
    required double cellSize,
    required Offset boardOrigin,
  }) {
    final local = point - boardOrigin;
    final boardWidth = columns * cellSize;
    final boardHeight = rows * cellSize;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx >= boardWidth ||
        local.dy >= boardHeight) {
      return null;
    }

    final column = local.dx ~/ cellSize;
    final row = local.dy ~/ cellSize;
    final position = GridPosition(column, row);
    return isInBounds(position) ? position : null;
  }
}
