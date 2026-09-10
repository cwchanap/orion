import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/board_component.dart';
import 'package:orion/game/models/game_models.dart';

Path _line(double length) => Path()
  ..moveTo(0, 0)
  ..lineTo(length, 0);

double _totalLength(Path path) =>
    path.computeMetrics().fold<double>(0, (sum, metric) => sum + metric.length);

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
}
