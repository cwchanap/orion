import 'dart:ui';

import 'package:flame/components.dart';

import '../assets/game_sprite_sheet.dart';
import '../models/game_models.dart';
import '../rules/board_layout.dart';

class BoardComponent extends PositionComponent {
  BoardComponent({
    required this.cellSize,
    this.selectedCell,
    this.spriteSheet,
    super.position,
    super.priority,
  }) : super(
         size: Vector2(
           BoardLayout.columns * cellSize,
           BoardLayout.rows * cellSize,
         ),
       );

  final double cellSize;
  final GameSpriteSheet? spriteSheet;
  GridPosition? selectedCell;

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

    canvas.drawRect(Offset.zero & size.toSize(), _backgroundPaint);

    for (final pathCell in BoardLayout.pathCells) {
      canvas.drawRect(cellRect(pathCell).deflate(1), _pathPaint);
    }

    final activeSelection = selectedCell;
    if (activeSelection != null) {
      final paint = BoardLayout.isBuildableCell(activeSelection)
          ? _buildableSelectionPaint
          : _blockedSelectionPaint;
      final rect = cellRect(activeSelection).deflate(2);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, _selectionStrokePaint);
    }

    _renderMarker(
      canvas,
      BoardLayout.pathCells.first,
      _spawnPaint,
      innerRadiusFactor: 0.22,
      sprite: GameSprite.spawnGate,
    );
    _renderMarker(
      canvas,
      BoardLayout.pathCells.last,
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
