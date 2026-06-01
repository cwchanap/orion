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
    final pathSet = pathCells.toSet();
    final hasNorth = pathSet.contains(
      GridPosition(position.column, position.row - 1),
    );
    final hasEast = pathSet.contains(
      GridPosition(position.column + 1, position.row),
    );
    final hasSouth = pathSet.contains(
      GridPosition(position.column, position.row + 1),
    );
    final hasWest = pathSet.contains(
      GridPosition(position.column - 1, position.row),
    );
    final neighborCount = [
      hasNorth,
      hasEast,
      hasSouth,
      hasWest,
    ].where((hasNeighbor) => hasNeighbor).length;

    if (neighborCount == 1) {
      return position == pathCells.first
          ? GamePathTile.startCap
          : GamePathTile.endCap;
    }
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
      'Path cell $position does not map to a supported path tile',
    );
  }
}
