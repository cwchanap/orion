import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

enum GamePathTile {
  horizontal,
  vertical,
  cornerNorthEast,
  cornerNorthWest,
  cornerSouthEast,
  cornerSouthWest,
  startCap,
  endCap,
}

class GamePathTiles {
  GamePathTiles._(this._sprites);

  static const String fileName = 'orion_path_tiles.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 2;

  final Map<GamePathTile, Sprite> _sprites;

  static Future<GamePathTiles> load(Images images) async {
    final image = await images.load(fileName);
    return GamePathTiles.fromImage(image);
  }

  static GamePathTiles fromImage(ui.Image image) {
    final sprites = <GamePathTile, Sprite>{};
    for (final tile in GamePathTile.values) {
      final sourceRect = sourceRectFor(
        tile,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      sprites[tile] = Sprite(
        image,
        srcPosition: Vector2(sourceRect.left, sourceRect.top),
        srcSize: Vector2(sourceRect.width, sourceRect.height),
      );
    }
    return GamePathTiles._(sprites);
  }

  Sprite sprite(GamePathTile tile) => _sprites[tile]!;

  static ui.Rect sourceRectFor(
    GamePathTile tile, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final index = tile.index;
    final cellWidth = imageWidth / columns;
    final cellHeight = imageHeight / rows;
    final column = index % columns;
    final row = index ~/ columns;
    return ui.Rect.fromLTWH(
      column * cellWidth,
      row * cellHeight,
      cellWidth,
      cellHeight,
    );
  }

  static GamePathTile tileForCell(
    GridPosition position,
    Iterable<GridPosition> pathCells,
  ) {
    final orderedPath = pathCells.toList(growable: false);
    final index = orderedPath.indexOf(position);
    if (index == -1) {
      throw StateError('Path cell $position is not in the ordered path');
    }

    final neighbors = [
      if (index > 0) orderedPath[index - 1],
      if (index < orderedPath.length - 1) orderedPath[index + 1],
    ];

    if (neighbors.length == 1) {
      if (index == 0) {
        return GamePathTile.startCap;
      }
      if (index == orderedPath.length - 1) {
        return GamePathTile.endCap;
      }
    }

    final hasNorth = neighbors.contains(
      GridPosition(position.column, position.row - 1),
    );
    final hasEast = neighbors.contains(
      GridPosition(position.column + 1, position.row),
    );
    final hasSouth = neighbors.contains(
      GridPosition(position.column, position.row + 1),
    );
    final hasWest = neighbors.contains(
      GridPosition(position.column - 1, position.row),
    );

    if (hasEast && hasWest) {
      return GamePathTile.horizontal;
    }
    if (hasNorth && hasSouth) {
      return GamePathTile.vertical;
    }
    if (hasNorth && hasEast) {
      return GamePathTile.cornerNorthEast;
    }
    if (hasNorth && hasWest) {
      return GamePathTile.cornerNorthWest;
    }
    if (hasSouth && hasEast) {
      return GamePathTile.cornerSouthEast;
    }
    if (hasSouth && hasWest) {
      return GamePathTile.cornerSouthWest;
    }

    throw StateError(
      'Path cell $position does not map to a supported ordered path tile',
    );
  }
}
