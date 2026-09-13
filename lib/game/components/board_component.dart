import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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
  final GamePathTiles? pathTiles;
  GridPosition? selectedCell;
  double selectedRange = 0;

  // Placement-preview presentation only (scene 1e). The board owns no
  // placement logic; the game resolves candidate validity and range.
  bool previewActive = false;
  Set<GridPosition> previewBuildableCells = const {};
  GridPosition? previewCandidate;
  bool previewAllowed = false;
  double previewRange = 0;

  /// Whether the normal selected-cell highlight may paint. Preview rendering
  /// replaces it while a placement preview is active — never both.
  bool get showsSelectionHighlight => selectedCell != null && !previewActive;

  /// Whether the cell grid paints. At rest the board is its own art, as in
  /// the artboard; the grid appears only to answer a placement in progress.
  bool get showsPlacementGrid => previewActive;

  /// Only the marker fallback's inner cut-out; the board's ground belongs
  /// to BoardBackdropComponent.
  final Paint _backgroundPaint = Paint()..color = const Color(0xFF17202A);
  // The armed-placement grid. The artboard shows cell lines only while a
  // placement is armed -- `s.armed ? ... : {display:'none'}` -- and draws
  // them in naniteGreen, so the grid reads as "here is where this can go"
  // rather than as permanent chrome over the board art.
  final Paint _gridPaint = Paint()
    ..color =
        const Color(0x2E7BE495) // naniteGreen @ 18%
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _pathPaint = Paint()..color = const Color(0xFF56616B);
  // systemCyan. The lane is the one board element the artboard draws in the
  // accent, and it is drawn rather than tiled: the path tile art is a
  // full-cell panel with the channel baked in, so on any board skin the
  // route reads as grey-on-grey and the player cannot see where enemies go.
  //
  // The artboard draws it as two polylines, and the split matters -- a single
  // fat dashed stroke reads as a pipe, not a route:
  //
  //   bed   stroke rgba(70,230,255,.14)  width 28    (no dash)
  //   core  stroke #46E6FF               width 3.4   dasharray 16 16
  //         plus drop-shadow(0 0 4px #46E6FF)
  //
  // Against the artboard's 49.125px cell those are the _lane* fractions
  // below. The bed is continuous: it is the channel the dashes travel down.
  final Paint _laneBedPaint = Paint()
    ..color =
        const Color(0x2446E6FF) // systemCyan @ 14%
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _lanePaint = Paint()
    ..color = const Color(0xFF46E6FF)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _laneGlowPaint = Paint()
    ..color = const Color(0x9946E6FF)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  // The 1e artboard's placement palette, in tokens: naniteGreen for an
  // allowed cell, dangerRed for a blocked one, each a light wash under a
  // full-strength stroke. The previous fills were #3DDC84 and #E35D6A --
  // a near-green and a near-red belonging to no token.
  final Paint _buildableSelectionPaint = Paint()
    ..color =
        const Color(0x297BE495) // naniteGreen @ 16%
    ..style = PaintingStyle.fill;
  final Paint _blockedSelectionPaint = Paint()
    ..color =
        const Color(0x24FF5D6C) // dangerRed @ 14%
    ..style = PaintingStyle.fill;
  final Paint _selectionStrokePaint = Paint()
    ..color =
        const Color(0xFF7BE495) // naniteGreen
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _spawnPaint = Paint()..color = const Color(0xFF58C4F6);
  final Paint _basePaint = Paint()..color = const Color(0xFFFFD166);
  final Paint _pathDangerPaint = Paint()
    ..color =
        const Color(0x24FF5D6C) // dangerRed @ 14%
    ..style = PaintingStyle.fill;
  // The range ring belongs to the allowed state, not to the tower: the
  // artboard strokes it in the same naniteGreen as the buildable cell it
  // surrounds, and draws no ring at all over a blocked candidate.
  final Paint _rangeRingPaint = Paint()
    ..color =
        const Color(0xB37BE495) // naniteGreen @ 70%
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final Paint _rangeWashPaint = Paint()..style = PaintingStyle.fill;
  final Paint _deniedGlyphPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

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
      for (final cell in previewBuildableCells) {
        canvas.drawRect(cellRect(cell).deflate(1), _buildableSelectionPaint);
        canvas.drawRect(cellRect(cell).deflate(1), _gridPaint);
      }
    }

    // After the danger wash: the lane is the board's primary legibility
    // element and must not be tinted by a transient preview overlay.
    _renderLane(canvas);

    final candidate = previewCandidate;
    if (previewActive && candidate != null) {
      final paint = previewAllowed
          ? _buildableSelectionPaint
          : _blockedSelectionPaint;
      final rect = cellRect(candidate).deflate(2);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, _selectionStrokePaint);
      if (previewAllowed && previewRange > 0) {
        _renderRangeRing(canvas, cellCenter(candidate), previewRange);
      }
      if (!previewAllowed) {
        _renderDeniedGlyph(canvas, candidate);
      }
    } else if (showsSelectionHighlight) {
      final activeSelection = selectedCell!;
      if (selectedRange > 0) {
        _renderRangeRing(canvas, cellCenter(activeSelection), selectedRange);
      }
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

    if (showsPlacementGrid) {
      _renderGrid(canvas);
    }
  }

  /// The artboard's lane fractions, against its 49.125px cell.
  @visibleForTesting
  static const double laneBedWidth = 28 / 49.125; // 0.570
  @visibleForTesting
  static const double laneCoreWidth = 3.4 / 49.125; // 0.069
  @visibleForTesting
  static const double laneDash = 16 / 49.125; // 0.326

  /// The artboard's lane: a wide, faint, continuous channel with a thin
  /// bright dashed core running down it. Every dimension scales with
  /// [cellSize] so the rhythm holds on any board size.
  void _renderLane(Canvas canvas) {
    if (pathCells.length < 2) {
      return;
    }

    final centreLine = Path()
      ..moveTo(cellCenter(pathCells.first).dx, cellCenter(pathCells.first).dy);
    for (final cell in pathCells.skip(1)) {
      final centre = cellCenter(cell);
      centreLine.lineTo(centre.dx, centre.dy);
    }

    final dashLength = cellSize * laneDash;
    final core = dashed(centreLine, dash: dashLength, gap: dashLength);

    // A hairline core would disappear on a small board, so hold a floor.
    final coreWidth = math.max(cellSize * laneCoreWidth, 1.5);
    _laneBedPaint.color = previewActive
        ? const Color(0x40FF5D6C)
        : const Color(0x2446E6FF);
    _lanePaint.color = previewActive
        ? const Color(0xFFFF5D6C)
        : const Color(0xFF46E6FF);
    _laneGlowPaint.color = previewActive
        ? const Color(0x66FF5D6C)
        : const Color(0x9946E6FF);
    _laneBedPaint.strokeWidth = cellSize * laneBedWidth;
    _laneGlowPaint.strokeWidth = coreWidth * 2;
    _lanePaint.strokeWidth = coreWidth;
    canvas
      ..drawPath(centreLine, _laneBedPaint)
      ..drawPath(core, _laneGlowPaint)
      ..drawPath(core, _lanePaint);
  }

  /// [source] cut into [dash]-long segments separated by [gap].
  ///
  /// A non-positive [dash] would advance the walk by nothing and never
  /// terminate, and a negative [gap] can cancel the advance entirely, so
  /// degenerate input (a zero [cellSize] board before the first resize)
  /// yields the undashed line rather than a hang.
  @visibleForTesting
  static Path dashed(Path source, {required double dash, required double gap}) {
    if (dash <= 0 || gap < 0) {
      return source;
    }
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + dash, metric.length);
        result.addPath(metric.extractPath(start, end), Offset.zero);
        start = end + gap;
      }
    }
    return result;
  }

  /// The artboard's range ring: a naniteGreen wash fading out at 70% of the
  /// radius, under a dashed ring.
  void _renderRangeRing(Canvas canvas, Offset centre, double radius) {
    _rangeWashPaint.shader = Gradient.radial(
      centre,
      radius,
      const <Color>[
        Color(0x247BE495), // naniteGreen @ 14%
        Color(0x007BE495),
        Color(0x007BE495),
      ],
      const <double>[0, 0.7, 1],
    );
    canvas
      ..drawCircle(centre, radius, _rangeWashPaint)
      ..drawPath(rangeRingPath(centre, radius), _rangeRingPaint);
  }

  /// The dashed ring the preview strokes at [radius] around [centre].
  @visibleForTesting
  Path rangeRingPath(Offset centre, double radius) => dashed(
    Path()..addOval(Rect.fromCircle(center: centre, radius: radius)),
    dash: cellSize * 0.17,
    gap: cellSize * 0.17,
  );

  /// The range ring's stroke paint as the last render configured it.
  @visibleForTesting
  Paint get rangeRingPaint => _rangeRingPaint;

  /// The placement grid's stroke paint.
  @visibleForTesting
  Paint get gridPaint => _gridPaint;

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

  /// Non-color-only denied affordance: a small ✗ glyph over the blocked
  /// candidate fill, mirroring the mock's crosshair, so denial does not rely
  /// on the red fill alone.
  void _renderDeniedGlyph(Canvas canvas, GridPosition position) {
    final rect = cellRect(position).deflate(cellSize * 0.3);
    canvas
      ..drawLine(rect.topLeft, rect.bottomRight, _deniedGlyphPaint)
      ..drawLine(rect.topRight, rect.bottomLeft, _deniedGlyphPaint);
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
