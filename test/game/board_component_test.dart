import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/board_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

Path _line(double length) => Path()
  ..moveTo(0, 0)
  ..lineTo(length, 0);

double _totalLength(Path path) =>
    path.computeMetrics().fold<double>(0, (sum, metric) => sum + metric.length);

Future<Image> _rasterize(
  int width,
  int height,
  void Function(Canvas) draw,
) async {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<List<int>> _rgbaAt(Image image, int x, int y) async {
  final data = await image.toByteData(format: ImageByteFormat.rawRgba);
  final index = (y * image.width + x) * 4;
  return [
    data!.getUint8(index),
    data.getUint8(index + 1),
    data.getUint8(index + 2),
    data.getUint8(index + 3),
  ];
}

void main() {
  group('BoardComponent.dashed', () {
    test('cuts a line into dash/gap segments', () {
      final result = BoardComponent.dashed(_line(100), dash: 10, gap: 10);

      // 100 units at a 20-unit period: dashes at 0, 20, 40, 60, 80.
      expect(result.computeMetrics().length, 5);
      expect(_totalLength(result), closeTo(50, 0.01));
    });

    test('clips the trailing dash to the end of the line', () {
      final result = BoardComponent.dashed(_line(25), dash: 10, gap: 10);

      // Dashes at 0-10 and 20-25: the last one is cut short, not extended.
      expect(result.computeMetrics().length, 2);
      expect(_totalLength(result), closeTo(15, 0.01));
    });

    test('returns the undashed line for a non-positive dash', () {
      // A zero dash would advance the walk by nothing and never terminate.
      final result = BoardComponent.dashed(_line(100), dash: 0, gap: 0);

      expect(_totalLength(result), closeTo(100, 0.01));
    });
  });

  group('BoardComponent lane rendering', () {
    void renderTo(BoardComponent board) {
      final recorder = PictureRecorder();
      board.render(Canvas(recorder));
      recorder.endRecording();
    }

    test('renders a multi-cell path', () {
      final board = BoardComponent(
        cellSize: 32,
        pathCells: const [
          GridPosition(0, 0),
          GridPosition(1, 0),
          GridPosition(1, 1),
        ],
      );

      expect(() => renderTo(board), returnsNormally);
    });

    test('renders a single-cell path, which has no lane to draw', () {
      final board = BoardComponent(
        cellSize: 32,
        pathCells: const [GridPosition(0, 0)],
      );

      expect(() => renderTo(board), returnsNormally);
    });

    test('renders a degenerate board before the first resize', () {
      final board = BoardComponent(
        cellSize: 0,
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
      );

      expect(() => renderTo(board), returnsNormally);
    });
  });

  group('BoardComponent range ring', () {
    BoardComponent previewBoard() =>
        BoardComponent(
            cellSize: 32,
            pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
          )
          ..previewActive = true
          ..previewCandidate = const GridPosition(4, 4)
          ..previewAllowed = true
          ..previewRange = 90;

    void renderTo(BoardComponent board) {
      final recorder = PictureRecorder();
      board.render(Canvas(recorder));
      recorder.endRecording();
    }

    test('is dashed, not a solid circle', () {
      const radius = 90.0;
      final board = previewBoard();

      final ring = board.rangeRingPath(Offset.zero, radius);

      // Equal dash and gap, so about half the circumference survives. The
      // slack absorbs what computeMetrics loses walking a polyline
      // approximation of the oval.
      const circumference = 2 * math.pi * radius;
      expect(
        _totalLength(ring),
        closeTo(circumference / 2, 0.1 * circumference / 2),
      );
      expect(ring.computeMetrics().length, greaterThan(20));
    });

    test('is the artboard\'s naniteGreen, at full-strength 2px', () {
      final board = previewBoard();

      renderTo(board);

      // The ring belongs to the allowed state, so it matches the buildable
      // cell's green rather than the dragged tower's own colour.
      expect(
        board.rangeRingPaint.color.toARGB32(),
        const Color(0xB37BE495).toARGB32(),
      );
      expect(board.rangeRingPaint.strokeWidth, 2);
    });

    test('renders without throwing over a blocked candidate', () {
      final board = previewBoard()..previewAllowed = false;

      expect(() => renderTo(board), returnsNormally);
    });
  });

  group('BoardComponent placement grid', () {
    void renderTo(BoardComponent board) {
      final recorder = PictureRecorder();
      board.render(Canvas(recorder));
      recorder.endRecording();
    }

    BoardComponent board() => BoardComponent(
      cellSize: 32,
      pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    );

    test('is hidden at rest and shown while a placement is armed', () {
      // The artboard draws cell lines only while armed; at rest the board is
      // its own art.
      expect(board().showsPlacementGrid, isFalse);

      final armed = board()
        ..previewActive = true
        ..previewCandidate = const GridPosition(4, 4);

      expect(armed.showsPlacementGrid, isTrue);
      expect(() => renderTo(armed), returnsNormally);
    });

    test('is naniteGreen at the artboard alpha, not grey chrome', () {
      expect(
        board().gridPaint.color.toARGB32(),
        const Color(0x2E7BE495).toARGB32(),
      );
    });

    test('a selected cell alone does not arm the grid', () {
      // Selecting a cell shows its highlight; only a placement shows the grid.
      final selected = board()..selectedCell = const GridPosition(2, 2);

      expect(selected.showsSelectionHighlight, isTrue);
      expect(selected.showsPlacementGrid, isFalse);
    });
  });

  group('BoardComponent board.js readability (HPA-699)', () {
    const cell = 40.0;

    BoardComponent board() =>
        BoardComponent(cellSize: cell, pathCells: BoardLayout.pathCells);

    Future<Image> renderBoard() => _rasterize(
      (BoardLayout.columns * cell).ceil(),
      (BoardLayout.rows * cell).ceil(),
      board().render,
    );

    test('the lane corridor paints a dark channel inside the rim', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.82 * cell).round(),
      );
      expect(pixel[0], lessThan(0x30));
      expect(pixel[1], lessThan(0x45));
      expect(pixel[2], lessThan(0x50));
    });

    test('the lane keeps a steel-cyan rim around the channel', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.88 * cell).round(),
      );
      expect(pixel[0], lessThan(0x45));
      expect(pixel[2], greaterThan(pixel[0]));
    });

    test('the centre line carries chevrons, not a cyan stripe', () async {
      final image = await renderBoard();
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final y = (1.5 * cell).round();
      var cyanish = 0;
      var samples = 0;
      for (var x = (0.6 * cell).round(); x < (3.4 * cell).round(); x++) {
        final index = (y * image.width + x) * 4;
        final r = data!.getUint8(index);
        final g = data.getUint8(index + 1);
        final b = data.getUint8(index + 2);
        final a = data.getUint8(index + 3);
        if (a > 0) {
          samples += 1;
          if (g > 150 && b > 150 && r < 100) cyanish += 1;
        }
      }
      expect(samples, greaterThan(0));
      expect(
        cyanish / samples,
        lessThan(0.4),
        reason:
            'flow chevrons are sparse glyphs, so most of the centre line '
            'stays the dark channel',
      );
    });

    test('a faint always-on grid borders every cell', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(image, cell.round(), (8.5 * cell).round());
      expect(pixel[3], greaterThan(0));
      expect(pixel[2], greaterThanOrEqualTo(pixel[0]));
    });

    test('the spawn marker reads larger than its cell', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (0.5 * cell).round(),
        (1.0 * cell).round(),
      );
      expect(pixel[3], greaterThan(0));
    });

    test('the core marker reads larger than its cell', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (6.95 * cell).round(),
        (10.5 * cell).round(),
      );
      expect(pixel[3], greaterThan(0));
    });

    test('cell geometry stays aligned with BoardLayout after the repaint', () {
      final component = board();
      for (final position in BoardLayout.pathCells) {
        expect(
          component.cellCenter(position),
          BoardLayout.cellCenter(
            position,
            cellSize: cell,
            boardOrigin: Offset.zero,
          ),
        );
        expect(
          component.cellRect(position).contains(component.cellCenter(position)),
          isTrue,
        );
      }
    });

    test('the lane rim is the kit steel-cyan at the kit band', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.88 * cell).round(),
      );
      expect(
        pixel[0],
        closeTo(0x2C, 4),
        reason: 'board.js strokes the rim #2C6F86, not a fabricated hue',
      );
      expect(pixel[1], closeTo(0x6F, 4));
      expect(pixel[2], closeTo(0x86, 4));
    });

    test('the lane channel is the kit dark blue at the kit band', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.80 * cell).round(),
      );
      expect(pixel[0], closeTo(0x08, 3));
      expect(pixel[1], closeTo(0x12, 3));
      expect(pixel[2], closeTo(0x1B, 3));
    });

    test(
      'the lane centre carries the kit core line between chevrons',
      () async {
        final image = await renderBoard();
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final y = (1.5 * cell).round();
        var matching = 0;
        var samples = 0;
        for (var x = (1.0 * cell).round(); x < (3.0 * cell).round(); x++) {
          final index = (y * image.width + x) * 4;
          final r = data!.getUint8(index);
          final g = data.getUint8(index + 1);
          final b = data.getUint8(index + 2);
          final a = data.getUint8(index + 3);
          if (a == 0 || (g > 150 && b > 150 && r < 100)) continue;
          samples += 1;
          if ((r - 0x0E).abs() <= 4 &&
              (g - 0x22).abs() <= 4 &&
              (b - 0x30).abs() <= 4) {
            matching += 1;
          }
        }
        expect(samples, greaterThan(10));
        expect(
          matching / samples,
          greaterThan(0.8),
          reason:
              'board.js runs a #0E2230 lane core at C*.5 under the chevrons; '
              'the bare centreline must read that value, not the channel',
        );
      },
    );

    test(
      'the field grid is the kit cyan at seven percent, not opaque',
      () async {
        final image = await renderBoard();
        final pixel = await _rgbaAt(image, cell.round(), (8.5 * cell).round());
        expect(
          pixel[3],
          allOf(greaterThan(4), lessThan(64)),
          reason:
              'rgba(70,230,255,.07) composites to a faint line; an opaque '
              'grid tile is off-kit',
        );
        expect(pixel[2], greaterThanOrEqualTo(pixel[0]));
        expect(pixel[1], greaterThan(pixel[0]));
      },
    );

    test('flow chevrons land one per cell along a straight run', () async {
      final image = await renderBoard();
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final y = (1.5 * cell).round();
      final runs = <int>[];
      var inRun = false;
      for (var x = (0.6 * cell).round(); x < (3.4 * cell).round(); x++) {
        final index = (y * image.width + x) * 4;
        final r = data!.getUint8(index);
        final g = data.getUint8(index + 1);
        final b = data.getUint8(index + 2);
        final a = data.getUint8(index + 3);
        final cyanish = a > 0 && g > 150 && b > 150 && r < 100;
        if (cyanish && !inRun) {
          runs.add(x);
          inRun = true;
        } else if (!cyanish) {
          inRun = false;
        }
      }
      expect(
        runs.length,
        3,
        reason:
            'board.js places one chevron per cell of segment length; '
            '${runs.length} clusters on a 3-cell run is off-kit',
      );
      for (var i = 1; i < runs.length; i++) {
        expect(
          runs[i] - runs[i - 1],
          closeTo(cell.round(), (0.3 * cell).round()),
          reason: 'chevron pitch must be ~one cell, not a fabricated rhythm',
        );
      }
    });

    test('the spawn marker fills the kit 1.35C disc and no more', () async {
      final image = await renderBoard();
      final covered = await _rgbaAt(
        image,
        (0.5 * cell).round(),
        (0.84 * cell).round(),
      );
      expect(
        covered[3],
        greaterThan(0),
        reason:
            'the kit spawn rift spans C*1.35; 0.66C from centre must still '
            'be inside the disc',
      );
      final outside = await _rgbaAt(
        image,
        (0.5 * cell).round(),
        (0.78 * cell).round(),
      );
      expect(
        outside[3],
        0,
        reason:
            '0.72C from centre is outside a 1.35C marker; covering it '
            'means the spawn inherited the core\'s larger size',
      );
    });

    test('the core marker fills the kit 1.45C disc and no more', () async {
      final image = await renderBoard();
      final covered = await _rgbaAt(
        image,
        (6.80 * cell).round(),
        (10.5 * cell).round(),
      );
      expect(
        covered[3],
        greaterThan(0),
        reason:
            'the kit core spans C*1.45; 0.70C from centre must still be '
            'inside the disc',
      );
      final outside = await _rgbaAt(
        image,
        (6.69 * cell).round(),
        (10.5 * cell).round(),
      );
      expect(
        outside[3],
        0,
        reason: '0.81C from centre is outside a 1.45C marker',
      );
    });
  });
}
