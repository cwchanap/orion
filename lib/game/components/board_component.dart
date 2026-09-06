import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_path_tiles.dart';
import '../assets/game_sprite_sheet.dart';
import '../models/game_models.dart';
import '../rules/board_layout.dart';

class BoardComponent extends PositionComponent {
  BoardComponent({
    required this.cellSize,
    required this.pathCells,
    this.selectedCell,
    this.spriteSheet,
    this.terrainImage,
    this.pathTiles,
    super.position,
    super.priority,
  }) : assert(pathCells.isNotEmpty, 'BoardComponent requires path cells.'),
       super(
         size: Vector2(
           BoardLayout.columns * cellSize,
           BoardLayout.rows * cellSize,
         ),
       );

  final double cellSize;
  final List<GridPosition> pathCells;
  final GameSpriteSheet? spriteSheet;
  final Image? terrainImage;
  final GamePathTiles? pathTiles;
  GridPosition? selectedCell;

  // Placement-preview presentation only (scene 1e). The board owns no
  // placement logic; the game resolves candidate validity and range.
  bool previewActive = false;
  GridPosition? previewCandidate;
  bool previewAllowed = false;
  double previewRange = 0;

  /// Whether the normal selected-cell highlight may paint. Preview rendering
  /// replaces it while a placement preview is active — never both.
  bool get showsSelectionHighlight => selectedCell != null && !previewActive;

  final Paint _backgroundPaint = Paint()..color = const Color(0xFF17202A);
  final Paint _gridPaint = Paint()
    ..color = const Color(0x6636454F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _pathPaint = Paint()..color = const Color(0xFF56616B);
  final Paint _buildableSelectionPaint = Paint()
    ..color = const Color(0x663DDC84)
    ..style = PaintingStyle.fill;
  final Paint _blockedSelectionPaint = Paint()
    ..color = const Color(0x66E35D6A)
    ..style = PaintingStyle.fill;
  final Paint _selectionStrokePaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _spawnPaint = Paint()..color = const Color(0xFF58C4F6);
  final Paint _basePaint = Paint()..color = const Color(0xFFFFD166);
  final Paint _pathDangerPaint = Paint()
    ..color = const Color(0x66E35D6A)
    ..style = PaintingStyle.fill;
  final Paint _rangeRingPaint = Paint()
    ..color = const Color(0xB3FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  Rect cellRect(GridPosition position) {
    return Rect.fromLTWH(
      position.column * cellSize,
      position.row * cellSize,
      cellSize,
      cellSize,
    );
  }

  Offset cellCenter(GridPosition position) {
    return Offset(
      (position.column + 0.5) * cellSize,
      (position.row + 0.5) * cellSize,
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final terrainImage = this.terrainImage;
    if (terrainImage == null) {
      canvas.drawRect(Offset.zero & size.toSize(), _backgroundPaint);
    } else {
      canvas.drawImageRect(
        terrainImage,
        Rect.fromLTWH(
          0,
          0,
          terrainImage.width.toDouble(),
          terrainImage.height.toDouble(),
        ),
        Offset.zero & size.toSize(),
        Paint(),
      );
    }

    final pathTiles = this.pathTiles;
    for (final pathCell in pathCells) {
      final rect = cellRect(pathCell).deflate(1);
      if (pathTiles == null) {
        canvas.drawRect(rect, _pathPaint);
      } else {
        final tile = GamePathTiles.tileForCell(pathCell, pathCells);
        pathTiles.sprite(tile).renderRect(canvas, rect);
      }
    }

    // While a placement preview is active its rendering replaces the normal
    // selected-cell paint: danger wash over the path, then the candidate
    // cell, then the resolved range ring on an allowed candidate.
    if (previewActive) {
      for (final pathCell in pathCells) {
        canvas.drawRect(cellRect(pathCell).deflate(1), _pathDangerPaint);
      }
    }

    final candidate = previewCandidate;
    if (previewActive && candidate != null) {
      final paint = previewAllowed
          ? _buildableSelectionPaint
          : _blockedSelectionPaint;
      final rect = cellRect(candidate).deflate(2);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, _selectionStrokePaint);
      if (previewAllowed && previewRange > 0) {
        canvas.drawCircle(cellCenter(candidate), previewRange, _rangeRingPaint);
      }
    } else if (showsSelectionHighlight) {
      final activeSelection = selectedCell!;
      final paint =
          BoardLayout.isBuildableCell(activeSelection, pathCells: pathCells)
          ? _buildableSelectionPaint
          : _blockedSelectionPaint;
      final rect = cellRect(activeSelection).deflate(2);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, _selectionStrokePaint);
    }

    _renderMarker(
      canvas,
      pathCells.first,
      _spawnPaint,
      innerRadiusFactor: 0.22,
      sprite: GameSprite.spawnGate,
    );
    _renderMarker(
      canvas,
      pathCells.last,
      _basePaint,
      innerRadiusFactor: 0.3,
      sprite: GameSprite.baseReactor,
    );

    _renderGrid(canvas);
  }

  void _renderGrid(Canvas canvas) {
    final boardWidth = BoardLayout.columns * cellSize;
    final boardHeight = BoardLayout.rows * cellSize;

    for (var column = 0; column <= BoardLayout.columns; column += 1) {
      final x = column * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, boardHeight), _gridPaint);
    }

    for (var row = 0; row <= BoardLayout.rows; row += 1) {
      final y = row * cellSize;
      canvas.drawLine(Offset(0, y), Offset(boardWidth, y), _gridPaint);
    }
  }

  void _renderMarker(
    Canvas canvas,
    GridPosition position,
    Paint paint, {
    required double innerRadiusFactor,
    required GameSprite sprite,
  }) {
    final spriteSheet = this.spriteSheet;
    if (spriteSheet != null) {
      final rect = cellRect(position).deflate(cellSize * 0.12);
      spriteSheet.sprite(sprite).renderRect(canvas, rect);
      return;
    }

    final center = cellCenter(position);
    canvas.drawCircle(center, cellSize * 0.38, paint);
    canvas.drawCircle(center, cellSize * innerRadiusFactor, _backgroundPaint);
  }
}
