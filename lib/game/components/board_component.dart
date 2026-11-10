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
  final Paint _fieldGridPaint = Paint()
    ..color =
        const Color(0x1246E6FF) // rgba(70,230,255,.07)
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
  // board.js's lane is one stroked path drawn four times, widest to
  // narrowest: a gaussian-blurred cyan halo under a steel rim under the
  // dark channel under the core line, then the flow chevrons on top.
  final Paint _laneGlowPaint = Paint()
    ..color =
        const Color(0x3846E6FF) // #46E6FF @ 22%
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _laneRimPaint = Paint()
    ..color = const Color(0xFF2C6F86)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _laneChannelPaint = Paint()
    ..color = const Color(0xFF08121B)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _laneCorePaint = Paint()
    ..color = const Color(0xFF0E2230)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _laneChevronPaint = Paint()
    ..color =
        const Color(0xBF46E6FF) // #46E6FF @ 75%
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
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

    _renderFieldGrid(canvas);

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
      outerRadiusFactor: _spawnMarkerFactor,
      innerRadiusFactor: 0.30,
      sprite: GameSprite.spawnGate,
      // board.js: drop-shadow(0 0 12px rgba(70,230,255,.9)).
      shadowColor: const Color(0xE646E6FF),
      shadowSigma: 12,
    );
    _renderMarker(
      canvas,
      pathCells.last,
      _basePaint,
      outerRadiusFactor: _coreMarkerFactor,
      innerRadiusFactor: 0.38,
      sprite: GameSprite.baseReactor,
      // board.js: drop-shadow(0 0 16px rgba(255,200,87,.95)).
      shadowColor: const Color(0xF2FFC857),
      shadowSigma: 16,
    );

    if (showsPlacementGrid) {
      _renderGrid(canvas);
    }
  }

  static const double _kitCellSize = 46.75;

  /// The artboard's lane fractions, against its 49.125px cell.
  static const double _laneRimWidthFactor = 0.8;
  static const double _laneChannelWidthFactor = 0.72;
  static const double _laneCoreWidthFactor = 0.5;
  static const double _spawnMarkerFactor = 1.35 / 2;
  static const double _coreMarkerFactor = 1.45 / 2;

  /// The artboard's lane: a wide, faint, continuous channel with a thin
  /// bright dashed core running down it. Every dimension scales with
  /// [cellSize] so the rhythm holds on any board size.
  /// board.js strokes the whole route four times, widest to narrowest, and
  /// leads it in from the left edge. Its widest pass is the .92C / .22 glow
  /// under `feGaussianBlur stdDeviation=6` — rasterized once into a
  /// board-sized layer ([_laneHaloImage]) and composited per frame, so the
  /// mask filter never runs inside render.
  void _renderLane(Canvas canvas) {
    if (pathCells.length < 2) {
      return;
    }

    final first = cellCenter(pathCells.first);
    final centreLine = Path()
      ..moveTo(-cellSize * 0.2, first.dy)
      ..lineTo(first.dx, first.dy);
    for (final cell in pathCells.skip(1)) {
      final centre = cellCenter(cell);
      centreLine.lineTo(centre.dx, centre.dy);
    }

    if (cellSize > 0) {
      final halo = _laneHaloImage ??= _rasterizeLaneHalo(centreLine);
      canvas.drawImage(halo, Offset.zero, Paint());
    }
    _laneRimPaint.strokeWidth = cellSize * _laneRimWidthFactor;
    _laneChannelPaint.strokeWidth = cellSize * _laneChannelWidthFactor;
    _laneCorePaint.strokeWidth = cellSize * _laneCoreWidthFactor;
    canvas
      ..drawPath(centreLine, _laneRimPaint)
      ..drawPath(centreLine, _laneChannelPaint)
      ..drawPath(centreLine, _laneCorePaint);
    _renderFlowChevrons(canvas);
  }

  /// The lane halo layer: the kit's .92C / .22 stroke under its actual
  /// σ=6 Gaussian (scaled by the board's cell size), baked into an image
  /// the geometry of which never changes. Compositing the layer each frame
  /// is a blit, so nothing blurs per frame.
  Image? _laneHaloImage;

  Image _rasterizeLaneHalo(Path centreLine) {
    final kit = cellSize / _kitCellSize;
    _laneGlowPaint
      ..strokeWidth = cellSize * 0.92
      ..color =
          const Color(0x3846E6FF) // #46E6FF @ 22%
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * kit);
    final recorder = PictureRecorder();
    Canvas(recorder).drawPath(centreLine, _laneGlowPaint);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (BoardLayout.columns * cellSize).ceil(),
      (BoardLayout.rows * cellSize).ceil(),
    );
    picture.dispose();
    return image;
  }

  /// Cached drop-shadow layers for the two markers: a blurred silhouette
  /// of the sprite's own alpha, tinted to the kit shadow color, keyed by
  /// sprite (each marker uses a distinct sprite at a fixed cell). Like the
  /// halo, each shadow blurs once and composites as a blit.
  final Map<GameSprite, (Image, Offset)> _markerShadowCache = {};

  /// board.js's flow chevrons: `M -5 -7 L 4 0 L -5 7`, one per cell of each
  /// straight segment, rotated to the segment's direction and dimmed to 35%
  /// while a placement preview is armed (its `dimLane` flag).
  void _renderFlowChevrons(Canvas canvas) {
    final kit = cellSize / _kitCellSize;
    _laneChevronPaint
      ..color = previewActive
          ? const Color(0x5946E6FF) // #46E6FF @ 35%
          : const Color(0xBF46E6FF)
      // A hairline core would disappear on a small board, so hold a floor.
      ..strokeWidth = math.max(2.6 * kit, 1.5);
    final lead = 4 * kit;
    final back = 5 * kit;
    final arm = 7 * kit;
    for (var i = 0; i + 1 < pathCells.length; i += 1) {
      final a = cellCenter(pathCells[i]);
      final b = cellCenter(pathCells[i + 1]);
      final length = (b - a).distance;
      if (length <= 0) {
        continue;
      }
      final count = math.max(1, (length / cellSize).round());
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      for (var k = 0; k < count; k += 1) {
        final t = (k + 0.5) / count;
        final x = a.dx + (b.dx - a.dx) * t;
        final y = a.dy + (b.dy - a.dy) * t;
        final tip = Offset(x + lead * cos, y + lead * sin);
        final armA = Offset(
          x - back * cos + arm * sin,
          y - back * sin - arm * cos,
        );
        final armB = Offset(
          x - back * cos - arm * sin,
          y - back * sin + arm * cos,
        );
        canvas
          ..drawLine(tip, armA, _laneChevronPaint)
          ..drawLine(tip, armB, _laneChevronPaint);
      }
    }
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

  /// board.js borders every inner cell boundary only — the board edge stays
  /// the backdrop's skin, not a stroked frame.
  void _renderFieldGrid(Canvas canvas) {
    final boardWidth = BoardLayout.columns * cellSize;
    final boardHeight = BoardLayout.rows * cellSize;

    for (var column = 1; column < BoardLayout.columns; column += 1) {
      final x = column * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, boardHeight), _fieldGridPaint);
    }

    for (var row = 1; row < BoardLayout.rows; row += 1) {
      final y = row * cellSize;
      canvas.drawLine(Offset(0, y), Offset(boardWidth, y), _fieldGridPaint);
    }
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
    required double outerRadiusFactor,
    required double innerRadiusFactor,
    required GameSprite sprite,
    required Color shadowColor,
    required double shadowSigma,
  }) {
    final spriteSheet = this.spriteSheet;
    if (spriteSheet != null) {
      final rect = Rect.fromCircle(
        center: cellCenter(position),
        radius: cellSize * outerRadiusFactor,
      );
      final flameSprite = spriteSheet.sprite(sprite);
      final (shadow, shadowOffset) = _markerShadowCache.putIfAbsent(
        sprite,
        () => _rasterizeMarkerShadow(rect, shadowColor, shadowSigma),
      );
      canvas.drawImage(shadow, shadowOffset, Paint());
      flameSprite.renderRect(canvas, rect);
      return;
    }

    final center = cellCenter(position);
    canvas.drawCircle(center, cellSize * outerRadiusFactor, paint);
    canvas.drawCircle(center, cellSize * innerRadiusFactor, _backgroundPaint);
  }

  /// The marker drop-shadow layer: a solid [shadowColor] silhouette of the
  /// marker art — the kit sprites are round, so a disc the size of the
  /// sprite rect is their silhouette — blurred at the kit radius scaled to
  /// the board's cell size. The raster bounds the marker rect plus a 3σ
  /// reach so the tail is not clipped.
  (Image, Offset) _rasterizeMarkerShadow(
    Rect rect,
    Color shadowColor,
    double shadowSigma,
  ) {
    final sigma = shadowSigma * cellSize / _kitCellSize;
    final bounds = rect.inflate(sigma * 3 + 1);
    final recorder = PictureRecorder();
    // The cull rect is in the canvas's local (pre-translate) space: cull to
    // the raster bounds, then shift the absolute-coord draw back to the
    // image origin so compositing at [bounds.topLeft] lands the shadow over
    // the marker again.
    final offscreen = Canvas(recorder, Offset.zero & bounds.size)
      ..translate(-bounds.left, -bounds.top);
    offscreen.drawCircle(
      rect.center,
      rect.shortestSide / 2,
      Paint()
        ..color = shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      bounds.width.ceil(),
      bounds.height.ceil(),
    );
    picture.dispose();
    return (image, bounds.topLeft);
  }

  @override
  void onRemove() {
    _laneHaloImage?.dispose();
    for (final (image, _) in _markerShadowCache.values) {
      image.dispose();
    }
    super.onRemove();
  }
}
