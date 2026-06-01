import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  group('BoardLayout', () {
    test('uses a portrait-friendly 8 by 12 grid', () {
      expect(BoardLayout.columns, 8);
      expect(BoardLayout.rows, 12);
    });

    test('recognizes in-bounds and out-of-bounds cells', () {
      expect(BoardLayout.isInBounds(const GridPosition(0, 0)), isTrue);
      expect(BoardLayout.isInBounds(const GridPosition(7, 11)), isTrue);
      expect(BoardLayout.isInBounds(const GridPosition(-1, 0)), isFalse);
      expect(BoardLayout.isInBounds(const GridPosition(8, 0)), isFalse);
      expect(BoardLayout.isInBounds(const GridPosition(0, 12)), isFalse);
    });

    test('defines a continuous fixed path from spawn to base', () {
      expect(BoardLayout.pathCells.first, const GridPosition(0, 1));
      expect(BoardLayout.pathCells.last, const GridPosition(7, 10));

      for (var index = 1; index < BoardLayout.pathCells.length; index += 1) {
        final previous = BoardLayout.pathCells[index - 1];
        final current = BoardLayout.pathCells[index];
        expect(previous.distanceTo(current), 1);
      }
    });

    test('distinguishes path and buildable cells', () {
      expect(BoardLayout.isPathCell(const GridPosition(3, 4)), isTrue);
      expect(BoardLayout.isBuildableCell(const GridPosition(3, 4)), isFalse);
      expect(BoardLayout.isBuildableCell(const GridPosition(0, 0)), isTrue);
      expect(BoardLayout.isBuildableCell(const GridPosition(7, 11)), isTrue);
    });

    test('maps points to cells only inside board bounds', () {
      const cellSize = 32.0;
      const boardOrigin = Offset(10, 20);

      expect(
        BoardLayout.cellAt(
          const Offset(95, 125),
          cellSize: cellSize,
          boardOrigin: boardOrigin,
        ),
        const GridPosition(2, 3),
      );
      expect(
        BoardLayout.cellAt(
          const Offset(9, 20),
          cellSize: cellSize,
          boardOrigin: boardOrigin,
        ),
        isNull,
      );
      expect(
        BoardLayout.cellAt(
          const Offset(10, 19),
          cellSize: cellSize,
          boardOrigin: boardOrigin,
        ),
        isNull,
      );
      expect(
        BoardLayout.cellAt(
          const Offset(266, 20),
          cellSize: cellSize,
          boardOrigin: boardOrigin,
        ),
        isNull,
      );
      expect(
        BoardLayout.cellAt(
          const Offset(10, 404),
          cellSize: cellSize,
          boardOrigin: boardOrigin,
        ),
        isNull,
      );
    });
  });
}
