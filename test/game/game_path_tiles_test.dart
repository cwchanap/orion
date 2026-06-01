import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_path_tiles.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

void main() {
  group('GamePathTiles', () {
    test('maps the 4x2 path tile atlas cells in stable order', () {
      expect(GamePathTiles.columns, 4);
      expect(GamePathTiles.rows, 2);
      expect(GamePathTiles.fileName, 'orion_path_tiles.png');
      expect(GamePathTiles.assetPath, 'assets/images/orion_path_tiles.png');

      final horizontalRect = GamePathTiles.sourceRectFor(
        GamePathTile.horizontal,
        imageWidth: 1024,
        imageHeight: 512,
      );
      expect(horizontalRect.left, 0);
      expect(horizontalRect.top, 0);
      expect(horizontalRect.width, 256);
      expect(horizontalRect.height, 256);

      final endRect = GamePathTiles.sourceRectFor(
        GamePathTile.endCap,
        imageWidth: 1024,
        imageHeight: 512,
      );
      expect(endRect.left, 768);
      expect(endRect.top, 256);
      expect(endRect.width, 256);
      expect(endRect.height, 256);
    });

    test('selects route tiles from neighboring path cells', () {
      final pathCells = BoardLayout.pathCells;

      expect(
        GamePathTiles.tileForCell(const GridPosition(0, 1), pathCells),
        GamePathTile.startCap,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(1, 1), pathCells),
        GamePathTile.horizontal,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(3, 2), pathCells),
        GamePathTile.vertical,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(3, 1), pathCells),
        GamePathTile.cornerSouthWest,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(3, 4), pathCells),
        GamePathTile.cornerNorthEast,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(6, 6), pathCells),
        GamePathTile.cornerNorthWest,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(2, 6), pathCells),
        GamePathTile.cornerSouthEast,
      );
      expect(
        GamePathTiles.tileForCell(const GridPosition(7, 10), pathCells),
        GamePathTile.endCap,
      );
    });
  });
}
