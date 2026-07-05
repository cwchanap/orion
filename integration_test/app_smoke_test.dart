import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('places a tower and starts a wave', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const OrionApp());
    });

    // 1. World map is showing with the first stage ("Alpha").
    await _pumpUntil(tester, () => tester.any(find.text('Orion Sector Map')));
    expect(find.text('Alpha'), findsOneWidget);

    // 2. Enter the first stage.
    await tester.tap(find.text('Alpha'));
    await _pumpUntil(tester, () => tester.any(find.text('Outpost Alpha')));
    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);

    final startingGold = GameBalance.startingGold;
    final laserCost = GameBalance.towerStats(TowerType.laser, level: 1).cost;

    // 3. Tap the center of a known buildable cell to open the tower picker.
    //    Cell (0,0) is never on the enemy path (see BoardLayout.pathCells).
    final cellCenter = _cellCenter(tester, const GridPosition(0, 0));
    final tapDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (!tester.any(find.text('Build Tower')) &&
        DateTime.now().isBefore(tapDeadline)) {
      await tester.tapAt(cellCenter);
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!tester.any(find.text('Build Tower'))) {
      fail(
        'Tapping buildable cell (0,0) did not open the tower picker within the timeout.',
      );
    }
    expect(find.text('Build Tower'), findsOneWidget);

    // 4. Place a Laser tower; gold decreases and the picker closes.
    await tester.tap(find.text('Laser $laserCost'));
    await _pumpUntil(
      tester,
      () =>
          tester.any(find.text('Gold ${startingGold - laserCost}')) &&
          !tester.any(find.text('Build Tower')),
    );
    expect(find.text('Gold ${startingGold - laserCost}'), findsOneWidget);
    expect(find.text('Build Tower'), findsNothing);

    // 5. Start a wave; the phase chip flips from Build to Wave Active.
    await tester.tap(find.text('Start Wave'));
    await _pumpUntil(tester, () => tester.any(find.text('Wave Active')));
    expect(find.text('Wave Active'), findsOneWidget);
    expect(find.text('Build'), findsNothing);
  });
}

Offset _cellCenter(WidgetTester tester, GridPosition cell) {
  // The GameWidget fills the SafeArea; the board is centered inside it.
  final boardRect = tester.getRect(find.bySubtype<GameWidget>());
  final cellSize = (boardRect.width / BoardLayout.columns).clamp(
    0.0,
    boardRect.height / BoardLayout.rows,
  );
  final boardWidth = BoardLayout.columns * cellSize;
  final boardHeight = BoardLayout.rows * cellSize;
  final origin = Offset(
    boardRect.left + (boardRect.width - boardWidth) / 2,
    boardRect.top + (boardRect.height - boardHeight) / 2,
  );
  return Offset(
    origin.dx + (cell.column + 0.5) * cellSize,
    origin.dy + (cell.row + 0.5) * cellSize,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Condition was not met within $timeout.');
}
