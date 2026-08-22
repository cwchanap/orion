import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/orion_defense_game.dart';
import 'package:orion/game/rules/board_layout.dart';
import 'package:orion/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('places a tower and starts a wave', (tester) async {
    await tester.runAsync(() async {
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesFeedbackPreferencesStore(
        preferences: preferences,
      );
      // Capture the user's real feedback preferences so they can be
      // restored after the test overwrites them with the disabled set.
      final originalPreferences = await store.load();
      addTearDown(() => store.save(originalPreferences));
      await store.save(
        const FeedbackPreferences(
          soundEffectsEnabled: false,
          hapticsEnabled: false,
        ),
      );
      await tester.pumpWidget(const OrionApp());
    });

    // 1. World map is showing with the first stage ("Alpha").
    await _pumpUntil(tester, () => tester.any(find.text('ORION SECTOR')));
    expect(find.text('Alpha'), findsOneWidget);

    // 2. Enter the first stage.
    await tester.tap(find.text('Alpha'));
    await _pumpUntil(tester, () => tester.any(find.text('Launch Mission')));
    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Standard Conditions'), findsOneWidget);
    expect(find.text('No environmental modifiers'), findsOneWidget);
    await tester.ensureVisible(find.text('Launch Mission'));
    await tester.pump();
    await tester.tap(find.text('Launch Mission'));
    await _pumpUntil(tester, () => tester.any(find.text('Build')));
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
    await _pumpUntil(tester, () {
      final game =
          (tester.state(find.bySubtype<GameWidget>())
                  as GameWidgetState<OrionDefenseGame>)
              .currentGame;
      return game.isAttached &&
          game.children.whereType<MultiTapDispatcher>().isNotEmpty;
    });
    await tester.pump();
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('New wave preview available')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mission-status-hud')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Credits ${GameBalance.startingGold}'),
      findsOneWidget,
    );

    final startingGold = GameBalance.startingGold;
    final laserCost = GameBalance.towerStats(TowerType.laser, level: 1).cost;

    // 3. Tap the center of a known buildable cell to open the tower picker.
    //    Cell (0,0) is never on the enemy path (see BoardLayout.pathCells)
    //    and is a former regression guard: the interactive top-flow controls
    //    once consumed taps over the top board rows, so this tap proves the
    //    reserved command-deck chrome keeps row 0 tappable.
    //    cellCenter is recomputed inside the action closure on each retry so a
    //    mid-loop resize (e.g. async board layout settling) can't tap a stale
    //    coordinate.
    const targetCell = GridPosition(0, 0);
    await _tapUntil(
      tester,
      () => tester.tapAt(_cellCenter(tester, targetCell)),
      () => tester.any(find.byKey(const ValueKey('command-dock-build'))),
      timeoutMessage:
          'Tapping buildable cell (0,0) did not open the tower '
          'picker within the timeout.',
    );

    // 4. Place a Laser tower; gold decreases and the picker closes.
    await tester.tap(find.byKey(const ValueKey('tower-card-laser')));
    await _pumpUntil(
      tester,
      () =>
          tester.any(
            find.bySemanticsLabel('Credits ${startingGold - laserCost}'),
          ) &&
          !tester.any(find.byKey(const ValueKey('command-dock-build'))),
    );
    expect(
      find.bySemanticsLabel('Credits ${startingGold - laserCost}'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('command-dock-build')), findsNothing);

    // 5. Start a wave; the phase chip flips from Build to Wave Active.
    await tester.tap(find.text('Start Wave'));
    await _pumpUntil(tester, () => tester.any(find.text('Wave Active')));
    expect(find.text('Wave Active'), findsOneWidget);
    expect(find.text('Build'), findsNothing);
    expect(find.textContaining('Environment:'), findsNothing);
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

Future<void> _tapUntil(
  WidgetTester tester,
  Future<void> Function() action,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 15),
  required String timeoutMessage,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await action();
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(timeoutMessage);
}
