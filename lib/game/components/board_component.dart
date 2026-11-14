import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

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
    ..color = const Color(0x1246E6FF)
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
  // systemCyan @ 14%
  final Paint _laneGlowPaint = Paint()
    ..color = const Color(0x3846E6FF)
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
    ..color = const Color(0xBF46E6FF)
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

    for (final spec in _markerSpecs) {
      _renderMarker(canvas, spec);
    }

    if (showsPlacementGrid) {
      _renderGrid(canvas);
    }
  }

  static const double _kitCellSize = 46.75;

  /// The artboard's lane fractions, against its 49.125px cell.
  static const double _laneRimWidthFactor = 0.8;
  static const double _laneChannelWidthFactor = 0.72; // 0.570
  static const double _laneCoreWidthFactor = 0.5; // 0.069
  static const double _spawnMarkerFactor = 1.35 / 2;
  static const double _coreMarkerFactor = 1.45 / 2;

  /// The artboard's lane: a wide, faint, continuous channel with a thin
  /// bright dashed core running down it. Every dimension scales with
  /// [cellSize] so the rhythm holds on any board size.
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

  Image? _laneHaloImage;

  Image _rasterizeLaneHalo(Path centreLine) {
    final kit = cellSize / _kitCellSize;
    _laneGlowPaint
      ..strokeWidth = cellSize * 0.92
      ..color = const Color(0x3846E6FF)
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

  final Map<GameSprite, (Image, Offset)> _markerShadowCache = {};
  final Map<GameSprite, int> _markerRenderFailures = {};

  Future<void>? _markerShadowBake;
  bool _markerShadowsRemoved = false;
  int _markerShadowEpoch = 0;

  @override
  void onMount() {
    super.onMount();
    _markerShadowsRemoved = false;
    // Baking acquires GPU images disposed in onRemove, which Flame only calls
    // for mounted components; starting the bake here keeps every cached image
    // paired with a removal callback.
    unawaited(_bakeMarkerShadows());
  }

  @visibleForTesting
  Future<void> ensureMarkerShadows() => _bakeMarkerShadows();

  Future<void> _bakeMarkerShadows() {
    if (_markerShadowsRemoved) return Future.value();
    return _markerShadowBake ??= _bakeMarkerShadowsAsync(_markerShadowEpoch);
  }

  Future<void> _bakeMarkerShadowsAsync(int epoch) async {
    final sheet = spriteSheet;
    if (sheet == null) {
      return;
    }
    for (final spec in _markerSpecs) {
      if (_markerShadowsRemoved || epoch != _markerShadowEpoch) return;
      if (_markerShadowCache.containsKey(spec.sprite)) {
        continue;
      }
      for (var attempt = 1; attempt <= 2; attempt++) {
        if (_markerShadowsRemoved || epoch != _markerShadowEpoch) return;
        try {
          final shadow = await _rasterizeMarkerShadow(
            sheet.sprite(spec.sprite),
            Rect.fromCircle(
              center: cellCenter(spec.position),
              radius: cellSize * spec.outerRadiusFactor,
            ),
            spec.shadowColor,
            spec.shadowSigma,
            epoch,
          );
          if (_markerShadowsRemoved || epoch != _markerShadowEpoch) {
            shadow?.$1.dispose();
            return;
          }
          if (shadow == null) return;
          _markerShadowCache[spec.sprite] = shadow;
          break;
        } catch (error, stack) {
          _reportMarkerError(
            'shadow ${spec.sprite} attempt $attempt',
            error,
            stack,
          );
          if (_markerShadowsRemoved || epoch != _markerShadowEpoch) return;
        }
      }
    }
  }

  void _reportMarkerError(String operation, Object error, StackTrace stack) {
    debugPrint('Marker $operation failed: $error');
    developer.log(
      'Marker $operation failed',
      name: 'orion.marker_shadow',
      error: error,
      stackTrace: stack,
    );
  }

  List<_MarkerSpec> get _markerSpecs => [
    _MarkerSpec(
      position: pathCells.first,
      fallbackPaint: _spawnPaint,
      outerRadiusFactor: _spawnMarkerFactor,
      innerRadiusFactor: 0.30,
      sprite: GameSprite.spawnGate,
      shadowColor: const Color(0xE646E6FF),
      shadowSigma: 12,
    ),
    _MarkerSpec(
      position: pathCells.last,
      fallbackPaint: _basePaint,
      outerRadiusFactor: _coreMarkerFactor,
      innerRadiusFactor: 0.38,
      sprite: GameSprite.baseReactor,
      shadowColor: const Color(0xF2FFC857),
      shadowSigma: 16,
    ),
  ];

  void _renderFlowChevrons(Canvas canvas) {
    final kit = cellSize / _kitCellSize;
    _laneChevronPaint
      ..color = previewActive
          ? const Color(0x5946E6FF)
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
      final count = math.max(1, (length / cellSize).round()); // 0.326
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

  void _renderMarker(Canvas canvas, _MarkerSpec spec) {
    final spriteSheet = this.spriteSheet;
    if (spriteSheet != null && (_markerRenderFailures[spec.sprite] ?? 0) < 2) {
      final rect = Rect.fromCircle(
        center: cellCenter(spec.position),
        radius: cellSize * spec.outerRadiusFactor,
      );
      Sprite? flameSprite;
      try {
        flameSprite = spriteSheet.sprite(spec.sprite);
      } catch (error, stack) {
        final failures = (_markerRenderFailures[spec.sprite] ?? 0) + 1;
        _markerRenderFailures[spec.sprite] = failures;
        _reportMarkerError(
          'render ${spec.sprite} attempt $failures',
          error,
          stack,
        );
      }
      if (flameSprite != null) {
        final shadow = _markerShadowCache[spec.sprite];
        if (shadow == null) {
          unawaited(_bakeMarkerShadows());
        } else {
          canvas.drawImage(shadow.$1, shadow.$2, Paint());
        }
        flameSprite.renderRect(canvas, rect);
        return;
      }
    }

    final center = cellCenter(spec.position);
    canvas.drawCircle(
      center,
      cellSize * spec.outerRadiusFactor,
      spec.fallbackPaint,
    );
    canvas.drawCircle(
      center,
      cellSize * spec.innerRadiusFactor,
      _backgroundPaint,
    );
  }

  Future<(Image, Offset)?> _rasterizeMarkerShadow(
    Sprite flameSprite,
    Rect rect,
    Color shadowColor,
    double shadowSigma,
    int epoch,
  ) async {
    final sigma = shadowSigma * cellSize / _kitCellSize;
    final rawBounds = rect.inflate(sigma * 3 + 1);
    final bounds = Rect.fromLTRB(
      rawBounds.left.floorToDouble(),
      rawBounds.top.floorToDouble(),
      rawBounds.right.ceilToDouble(),
      rawBounds.bottom.ceilToDouble(),
    );
    final width = bounds.width.toInt();
    final height = bounds.height.toInt();
    if (width <= 0 || height <= 0 || sigma <= 0) return null;

    final recorder = PictureRecorder();
    Picture? picture;
    late Image silhouette;
    try {
      final offscreen = Canvas(recorder, Offset.zero & bounds.size)
        ..translate(-bounds.left, -bounds.top);
      offscreen.drawImageRect(
        flameSprite.image,
        flameSprite.src,
        rect,
        Paint()..colorFilter = ColorFilter.mode(shadowColor, BlendMode.srcIn),
      );
      picture = recorder.endRecording();
      silhouette = picture.toImageSync(width, height);
    } finally {
      (picture ?? (recorder.isRecording ? recorder.endRecording() : null))
          ?.dispose();
    }

    ByteData? pixels;
    try {
      pixels = await silhouette.toByteData(format: ImageByteFormat.rawRgba);
    } finally {
      silhouette.dispose();
    }
    if (_markerShadowsRemoved || epoch != _markerShadowEpoch) return null;
    if (pixels == null) {
      throw StateError('Marker shadow readback returned null');
    }

    final rgba = Uint8List.sublistView(pixels);
    final red = (shadowColor.r * 255).round();
    final green = (shadowColor.g * 255).round();
    final blue = (shadowColor.b * 255).round();
    final blurred = await Isolate.run(
      () => _blurAlphaPixels(rgba, width, height, sigma, red, green, blue),
    );
    if (_markerShadowsRemoved || epoch != _markerShadowEpoch) return null;

    final image = await _decodeRgbaImage(blurred, width, height);
    if (_markerShadowsRemoved || epoch != _markerShadowEpoch) {
      image.dispose();
      return null;
    }
    return (image, bounds.topLeft);
  }

  static Future<Image> _decodeRgbaImage(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final completer = Completer<Image>();
    decodeImageFromPixels(
      pixels,
      width,
      height,
      PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Uint8List _blurAlphaPixels(
    Uint8List pixels,
    int width,
    int height,
    double sigma,
    int red,
    int green,
    int blue,
  ) {
    final radius = math.max(1, (sigma * 3).ceil());
    final kernel = Float64List(radius * 2 + 1);
    var kernelSum = 0.0;
    for (var i = -radius; i <= radius; i += 1) {
      final weight = math.exp(-0.5 * (i / sigma) * (i / sigma));
      kernel[i + radius] = weight;
      kernelSum += weight;
    }
    for (var i = 0; i < kernel.length; i += 1) {
      kernel[i] /= kernelSum;
    }

    final horizontal = Float64List(width * height);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k += 1) {
          final xx = x + k;
          if (xx < 0 || xx >= width) continue;
          acc += kernel[k + radius] * pixels[(y * width + xx) * 4 + 3];
        }
        horizontal[y * width + x] = acc;
      }
    }

    final blurred = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k += 1) {
          final yy = y + k;
          if (yy < 0 || yy >= height) continue;
          acc += kernel[k + radius] * horizontal[yy * width + x];
        }
        final alpha = acc.round().clamp(0, 255);
        final index = (y * width + x) * 4;
        blurred[index] = red * alpha ~/ 255;
        blurred[index + 1] = green * alpha ~/ 255;
        blurred[index + 2] = blue * alpha ~/ 255;
        blurred[index + 3] = alpha;
      }
    }
    return blurred;
  }

  @override
  void onRemove() {
    _markerShadowsRemoved = true;
    _markerShadowEpoch += 1;
    _markerShadowBake = null;
    _laneHaloImage?.dispose();
    _laneHaloImage = null;
    for (final (image, _) in _markerShadowCache.values) {
      image.dispose();
    }
    _markerShadowCache.clear();
    super.onRemove();
  }
}

class _MarkerSpec {
  const _MarkerSpec({
    required this.position,
    required this.fallbackPaint,
    required this.outerRadiusFactor,
    required this.innerRadiusFactor,
    required this.sprite,
    required this.shadowColor,
    required this.shadowSigma,
  });

  final GridPosition position;
  final Paint fallbackPaint;
  final double outerRadiusFactor;
  final double innerRadiusFactor;
  final GameSprite sprite;
  final Color shadowColor;
  final double shadowSigma;
}
