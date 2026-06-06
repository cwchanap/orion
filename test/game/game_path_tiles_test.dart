import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_path_tiles.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
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

    test('uses route order when stage path cells touch out of sequence', () {
      final pathCells = OrionCampaign.stageById('aurora-gate').pathCells;

      expect(
        GamePathTiles.tileForCell(const GridPosition(5, 10), pathCells),
        isA<GamePathTile>(),
      );
    });

    test(
      'ignores adjacent path cells that are not ordered route neighbors',
      () {
        const pathCells = [
          GridPosition(1, 1),
          GridPosition(2, 1),
          GridPosition(2, 2),
          GridPosition(1, 2),
          GridPosition(0, 2),
          GridPosition(0, 1),
          GridPosition(0, 0),
          GridPosition(1, 0),
        ];

        expect(
          GamePathTiles.tileForCell(const GridPosition(1, 1), pathCells),
          GamePathTile.startCap,
        );
        expect(
          GamePathTiles.tileForCell(const GridPosition(1, 0), pathCells),
          GamePathTile.endCap,
        );
      },
    );

    test('selects a tile for every shipped campaign path cell', () {
      for (final stage in OrionCampaign.stages) {
        for (final pathCell in stage.pathCells) {
          expect(
            () => GamePathTiles.tileForCell(pathCell, stage.pathCells),
            returnsNormally,
            reason: '${stage.id} path cell $pathCell should map to a tile',
          );
        }
      }
    });
  });
}
