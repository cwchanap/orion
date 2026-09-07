import 'dart:ui' show Rect;

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

    // 2. Enter the first stage: the briefing opens first (scene 1b), its
    //    launch action is "Start Mission", and Dismiss must return to the
    //    map without launching.
    await tester.tap(find.text('Alpha'));
    await _pumpUntil(tester, () => tester.any(find.text('Start Mission')));
    // The briefing is a full-height modal sheet (scene 1b): its entrance
    // animation only advances with real frames, and until it settles the
    // bottom action row is still below the screen edge. Let it finish in
    // real time before tapping near-sheet-bottom controls.
    await _settleSheetEntrance(tester);
    expect(find.text('Outpost Alpha'), findsOneWidget);
    expect(find.text('Standard Conditions'), findsOneWidget);
    expect(find.text('No environmental modifiers'), findsOneWidget);
    await tester.ensureVisible(find.text('Dismiss'));
    await tester.pump();
    await tester.tap(find.text('Dismiss'));
    // The modal sheet slides out over an animation window during which the
    // map is already visible beneath it; wait for the sheet to leave too.
    await _pumpUntil(
      tester,
      () =>
          tester.any(find.text('ORION SECTOR')) &&
          !tester.any(find.text('Start Mission')),
    );
    expect(find.text('Alpha'), findsOneWidget);

    // 3. Re-enter and start for real.
    await tester.tap(find.text('Alpha'));
    await _pumpUntil(tester, () => tester.any(find.text('Start Mission')));
    await _settleSheetEntrance(tester);
    await tester.ensureVisible(find.text('Start Mission'));
    await tester.pump();
    await tester.tap(find.text('Start Mission'));
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
    final game =
        (tester.state(find.bySubtype<GameWidget>())
                as GameWidgetState<OrionDefenseGame>)
            .currentGame;
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('New wave preview available')),
      findsOneWidget,
    );
    // The mission HUD is driven by real GameSession snapshots: its credits
    // label must equal the campaign-adjusted starting gold, not canned data.
    expect(find.byKey(const ValueKey('mission-status-hud')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Credits ${GameBalance.startingGold}'),
      findsOneWidget,
    );

    final startingGold = GameBalance.startingGold;
    final laserCost = GameBalance.towerStats(TowerType.laser, level: 1).cost;

    // 4. Tap the center of a known buildable cell to open the tower picker.
    //    Cell (0,0) is never on the enemy path (see BoardLayout.pathCells)
    //    and is a former regression guard: the interactive top-flow controls
    //    once consumed taps over the top board rows, so this tap proves the
    //    command-deck overlay keeps row 0 tappable.
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

    // 5. Place a Laser tower via TAP — tap placement must keep working
    //    alongside the drag path; gold decreases and the picker closes.
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

    // 6. Tap the top-RIGHT buildable cell (7,0) to verify the scanner overlay
    //    does not swallow taps on the upper-right board area. Cell (7,0) is
    //    buildable (not on the enemy path) and sits directly beneath where
    //    the collapsed scanner is positioned on short viewports: taps that
    //    land on a buildable cell are forwarded to the game by the scanner's
    //    tap arbiter, so this tap reaches the cell and switches the dock to
    //    the build rail.
    const topRightCell = GridPosition(7, 0);
    await _tapUntil(
      tester,
      () => tester.tapAt(_cellCenter(tester, topRightCell)),
      () => tester.any(find.byKey(const ValueKey('command-dock-build'))),
      timeoutMessage:
          'Tapping buildable cell (7,0) did not open the tower '
          'picker within the timeout. The scanner overlay may be '
          'intercepting taps on the upper-right board area.',
    );

    // 6b. Long-press drag from the build rail with an OFF-BOARD release must
    //     cancel (scene 1e wiring): the DROP TO BUILD preview appears while
    //     airborne, but releasing over a non-board point places nothing and
    //     spends nothing — the no-fallback contract.
    await _dragLaserCard(tester, dropPoint: _pointAboveBoard(tester));
    expect(find.text('DROP TO BUILD'), findsNothing);
    expect(
      find.bySemanticsLabel('Credits ${startingGold - laserCost}'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('command-dock-build')), findsOneWidget);

    // 6c. A valid long-press drag/drop onto the selected buildable cell
    //     (7,0) places EXACTLY ONCE: gold drops by exactly one laser cost
    //     and the successful placement clears the selection, leaving the
    //     build rail.
    await _dragLaserCard(tester, dropPoint: _cellCenter(tester, topRightCell));
    expect(find.text('DROP TO BUILD'), findsNothing);
    await _pumpUntil(
      tester,
      () => tester.any(
        find.bySemanticsLabel('Credits ${startingGold - 2 * laserCost}'),
      ),
    );
    expect(
      find.bySemanticsLabel('Credits ${startingGold - 2 * laserCost}'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('command-dock-build')), findsNothing);

    // 6d. Deselect the cell so the idle dock restores the pacing controls.
    //     Nothing interactive then hovers over board row 1, so every buildable
    //     cell there must be tappable. Speed selection stays live in the build
    //     phase while no cell or tower is selected.
    await _tapUntil(
      tester,
      () => tester.tapAt(_pointAboveBoard(tester)),
      () => tester.any(find.byKey(const ValueKey('command-dock-idle'))),
      timeoutMessage:
          'Could not dismiss the build rail to restore the idle dock.',
    );
    expect(find.byKey(const ValueKey('command-dock-idle')), findsOneWidget);
    await tester.tap(find.text('2x'));
    await _pumpUntil(tester, () => game.speedMultiplier == 2);
    // The game field flips synchronously but the SegmentedButton only learns
    // its new selection on the next frame; without this pump the next tap
    // lands on the segment the button still considers selected and is
    // silently dropped (onSelectionChanged is not called for it).
    await tester.pump();
    await tester.tap(find.text('3x'));
    await _pumpUntil(tester, () => game.speedMultiplier == 3);
    await tester.pump();
    await tester.tap(find.text('1x'));
    await _pumpUntil(tester, () => game.speedMultiplier == 1);
    await tester.pump();
    for (final cell in const [
      GridPosition(4, 1),
      GridPosition(5, 1),
      GridPosition(6, 1),
      GridPosition(7, 1),
    ]) {
      // Deselect first so every probe starts from the idle dock.
      await tester.tapAt(_pointAboveBoard(tester));
      await tester.pump(const Duration(milliseconds: 150));
      await _tapUntil(
        tester,
        () => tester.tapAt(_cellCenter(tester, cell)),
        () => tester.any(find.byKey(const ValueKey('command-dock-build'))),
        timeoutMessage:
            'Tapping buildable cell $cell did not open the tower picker '
            'within the timeout.',
      );
    }

    // 6e. Bottom-left buildable cell (0,11): the lower board must stay
    //     reachable past the bottom chrome. Deselect first so the idle dock
    //     (whose dead space forwards board taps) is active, not the build
    //     rail whose tower cards would consume the tap.
    await tester.tapAt(_pointAboveBoard(tester));
    await tester.pump(const Duration(milliseconds: 150));
    await _tapUntil(
      tester,
      () => tester.tapAt(_cellCenter(tester, const GridPosition(0, 11))),
      () => tester.any(find.byKey(const ValueKey('command-dock-build'))),
      timeoutMessage:
          'Tapping buildable cell (0,11) did not open the tower picker '
          'within the timeout.',
    );

    // 7. Dismiss the cell selection by tapping outside the board so the idle
    //    dock (with Start Wave) returns.
    await _tapUntil(
      tester,
      () => tester.tapAt(_pointAboveBoard(tester)),
      () => !tester.any(find.byKey(const ValueKey('command-dock-build'))),
      timeoutMessage:
          'Could not dismiss the build rail to return to the idle dock.',
    );

    // 8. Select the placed Laser: tapping its cell now opens the tower
    //    inspector, and a targeting change hits the real game session.
    await _tapUntil(
      tester,
      () => tester.tapAt(_cellCenter(tester, targetCell)),
      () => tester.any(find.byKey(const ValueKey('command-dock-tower'))),
      timeoutMessage:
          'Tapping the placed tower at (0,0) did not open the tower '
          'inspector within the timeout.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('tower-target-strongest')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tower-target-strongest')));
    await _pumpUntil(
      tester,
      () =>
          game.stateNotifier.value.selectedTower?.targetingMode ==
          TowerTargetingMode.strongest,
    );

    // 9. Return to idle and toggle auto-start on and off.
    await _tapUntil(
      tester,
      () => tester.tapAt(_pointAboveBoard(tester)),
      () => tester.any(find.byKey(const ValueKey('command-dock-idle'))),
      timeoutMessage: 'Could not dismiss the tower inspector.',
    );
    await tester.tap(find.byTooltip('Auto-start waves'));
    await _pumpUntil(tester, () => game.autoStartEnabled);
    await tester.pump();
    await tester.tap(find.byTooltip('Auto-start waves'));
    await _pumpUntil(tester, () => !game.autoStartEnabled);
    await tester.pump();

    // 10. Open and close the next-wave scanner.
    await tester.tap(find.byKey(const ValueKey('next-wave-scanner-collapsed')));
    await _pumpUntil(
      tester,
      () =>
          tester.any(find.byKey(const ValueKey('next-wave-scanner-expanded'))),
    );
    await tester.tap(find.byKey(const ValueKey('next-wave-scanner-expanded')));
    await _pumpUntil(
      tester,
      () =>
          !tester.any(find.byKey(const ValueKey('next-wave-scanner-expanded'))),
    );
    expect(
      find.byKey(const ValueKey('next-wave-scanner-collapsed')),
      findsOneWidget,
    );

    // 11. Run one wave at 3x: the phase chip flips from Build to Wave
    //     Active, pause/resume both hit the live loop, and the wave clears
    //     back into the build phase (two towers cannot lose wave 1: eight
    //     leaking drones deal at most 8 of 20 base damage).
    await tester.tap(find.text('3x'));
    await _pumpUntil(tester, () => game.speedMultiplier == 3);
    await tester.pump();
    await tester.tap(find.text('Start Wave'));
    await _pumpUntil(tester, () => tester.any(find.text('Wave Active')));
    expect(find.text('Wave Active'), findsOneWidget);
    expect(find.text('Build'), findsNothing);
    expect(find.textContaining('Environment:'), findsNothing);
    await _tapUntil(
      tester,
      () => tester.tap(find.byTooltip('Pause')),
      () => game.isPaused,
      timeoutMessage: 'Tapping Pause did not pause the active wave.',
    );
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume'));
    await _pumpUntil(tester, () => !game.isPaused);
    // The tap flips the game field synchronously, but the HUD label only
    // updates on the next rendered frame.
    await tester.pump();
    expect(find.text('Paused'), findsNothing);
    expect(find.text('Wave Active'), findsOneWidget);
    await _runUntil(
      tester,
      () =>
          game.stateNotifier.value.phase == GamePhase.build ||
          game.stateNotifier.value.isEnded,
    );
    await _takeFirstDraftOffer(tester, game);

    // 12. Return to the map while the mission is in its build phase — the
    //     only phase where the World Map action is enabled.
    await _tapUntil(
      tester,
      () => tester.tap(find.byKey(const ValueKey('world-map-action'))),
      () => tester.any(find.text('ORION SECTOR')),
      timeoutMessage:
          'Tapping the World Map action in the build phase did not return '
          'to the sector map.',
    );
    expect(find.text('Alpha'), findsOneWidget);

    // 13. Tech Tree: open from the world map rail, verify the real
    //     medal-point bank gates purchases on a fresh campaign (zero points
    //     earned, so every purchase is refused), then go back.
    await tester.tap(find.byTooltip('Tech Tree'));
    await _pumpUntil(
      tester,
      () => tester.any(find.byKey(const ValueKey('tech-bank-bar'))),
    );
    expect(find.textContaining('Unspent: 0'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('tech-node-solar-capacitors')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tech-node-solar-capacitors')));
    await _pumpUntil(tester, () => tester.any(find.text('Need 3 more points')));
    expect(find.text('Need 3 more points'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await _pumpUntil(tester, () => tester.any(find.text('ORION SECTOR')));

    // 14. Mission Report representative action path: run a fresh defense
    //     with no towers, let leaked waves destroy the base, and return to
    //     the map from the loss report.
    await tester.tap(find.text('Alpha'));
    await _pumpUntil(tester, () => tester.any(find.text('Start Mission')));
    await _settleSheetEntrance(tester);
    await tester.ensureVisible(find.text('Start Mission'));
    await tester.pump();
    await tester.tap(find.text('Start Mission'));
    await _pumpUntil(tester, () => tester.any(find.text('Build')));
    await _pumpUntil(tester, () {
      final lossRunGame =
          (tester.state(find.bySubtype<GameWidget>())
                  as GameWidgetState<OrionDefenseGame>)
              .currentGame;
      return lossRunGame.isAttached &&
          lossRunGame.children.whereType<MultiTapDispatcher>().isNotEmpty;
    });
    final lossRunGame =
        (tester.state(find.bySubtype<GameWidget>())
                as GameWidgetState<OrionDefenseGame>)
            .currentGame;
    await tester.tap(find.text('3x'));
    await _pumpUntil(tester, () => lossRunGame.speedMultiplier == 3);
    await tester.pump();

    // Each wave leaks damage and each wave clear interrupts with a Salvage
    // Module draft; take the first offer and keep starting waves — every
    // enemy leaks with no towers up, so the base (20 hp) is destroyed within
    // a few waves and the loss report appears.
    await tester.tap(find.text('Start Wave'));
    await _pumpUntil(tester, () => tester.any(find.text('Wave Active')));
    while (!lossRunGame.stateNotifier.value.isEnded) {
      await _runUntil(
        tester,
        () =>
            lossRunGame.stateNotifier.value.phase == GamePhase.build ||
            lossRunGame.stateNotifier.value.isEnded,
      );
      if (lossRunGame.stateNotifier.value.isEnded) {
        break;
      }
      await _takeFirstDraftOffer(tester, lossRunGame);
      await tester.tap(find.text('Start Wave'));
      await _pumpUntil(tester, () => tester.any(find.text('Wave Active')));
    }
    expect(lossRunGame.stateNotifier.value.phase, GamePhase.lost);
    await _pumpUntil(tester, () => tester.any(find.text('Mission Failed')));
    expect(find.text('Mission Failed'), findsOneWidget);
    await _tapUntil(
      tester,
      () => tester.tap(find.text('World Map')),
      () => tester.any(find.text('ORION SECTOR')),
      timeoutMessage:
          'Tapping the loss report World Map action did not return to the '
          'sector map.',
    );
    expect(find.text('Alpha'), findsOneWidget);
  });
}

/// Long-press drags the Laser build card to [dropPoint]. The hold runs in
/// real time inside [WidgetTester.runAsync] so it reliably exceeds
/// kLongPressTimeout on the simulator (the established pattern from prior
/// tasks for gesture-recognizer timeouts), then approaches the drop point in
/// hops so the placement preview tracks the pointer.
Future<void> _dragLaserCard(
  WidgetTester tester, {
  required Offset dropPoint,
}) async {
  final cardCenter = tester.getCenter(
    find.byKey(const ValueKey('tower-card-laser')),
  );
  await tester.runAsync(() async {
    final gesture = await tester.startGesture(cardCenter);
    // kLongPressTimeout is 500ms, but on the simulator each synthetic
    // pointer event takes real wall time to dispatch, so poll for the drag
    // actually starting (the rail overlay flips to DROP TO BUILD) instead of
    // assuming a fixed hold is enough.
    final dragStarted = DateTime.now().add(const Duration(seconds: 5));
    while (!tester.any(find.text('DROP TO BUILD')) &&
        DateTime.now().isBefore(dragStarted)) {
      // The binding's frame policy is onlyPumps: real delays let the
      // 500ms long-press timer fire, and each pump draws the frame that
      // materializes the resulting drag overlay.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    expect(
      tester.any(find.text('DROP TO BUILD')),
      isTrue,
      reason:
          'Holding the Laser card did not start the placement drag; the '
          'long-press gesture never began.',
    );
    final hop = (dropPoint - cardCenter) / 3;
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(hop);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    }
    await gesture.up();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  await tester.pump();
}

/// Accepts the pending Salvage Module draft (offered after each wave clear)
/// by taking its first option, so the mission dock — and with it Start Wave
/// and the World Map action — becomes reachable again.
Future<void> _takeFirstDraftOffer(
  WidgetTester tester,
  OrionDefenseGame game,
) async {
  final offer = game.stateNotifier.value.pendingRunModuleOffer;
  if (offer == null) {
    return;
  }
  final firstTitle = runModuleDefinition(offer.moduleIds.first).title;
  await _pumpUntil(
    tester,
    () => tester.any(find.text(firstTitle)),
    timeoutMessage:
        'A draft offer ("$firstTitle") was pending but its sheet never '
        'appeared, leaving the mission dock blocked.',
  );
  await tester.tap(find.text(firstTitle));
  await _pumpUntil(
    tester,
    () => game.stateNotifier.value.pendingRunModuleOffer == null,
    timeoutMessage:
        'Tapping "$firstTitle" did not clear the pending draft offer; the '
        'tap was swallowed and the dock stays blocked.',
  );
  await tester.pump();
}

/// Polls [predicate] against the live game loop. The binding's frame policy
/// is onlyPumps, so each iteration yields real wall time (letting timers
/// fire and the Flame ticker accumulate delta) and then pumps an actual
/// frame — the simulation only advances on frames.
Future<void> _runUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (predicate()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    }
  });
  if (!predicate()) {
    fail('Condition was not met within $timeout.');
  }
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

Offset _pointAboveBoard(WidgetTester tester) {
  // A point inside the GameWidget but above the centered board, so tapping
  // it clears the selection (cellAt returns null).
  final boardRect = tester.getRect(find.bySubtype<GameWidget>());
  final cellSize = (boardRect.width / BoardLayout.columns).clamp(
    0.0,
    boardRect.height / BoardLayout.rows,
  );
  final boardHeight = BoardLayout.rows * cellSize;
  final boardTop = boardRect.top + (boardRect.height - boardHeight) / 2;
  return Offset(
    boardRect.center.dx,
    boardRect.top + (boardTop - boardRect.top) / 2,
  );
}

/// Waits for the modal briefing sheet's entrance to settle by polling for
/// the action row being fully on-screen and stationary — no blind sleep.
/// The full-height briefing sheet (scene 1b) slides up over ~300ms of real
/// frames; until it settles, its bottom action row sits below the screen
/// edge and taps there are lost to the barrier.
Future<void> _settleSheetEntrance(WidgetTester tester) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    Rect? previous;
    while (DateTime.now().isBefore(deadline)) {
      final action = find.text('Start Mission');
      if (tester.any(action)) {
        final rect = tester.getRect(action);
        final onScreen =
            rect.top >= 0 &&
            rect.bottom <=
                tester.view.physicalSize.height / tester.view.devicePixelRatio;
        if (onScreen && previous == rect) {
          return;
        }
        previous = rect;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  });
  if (!tester.any(find.text('Start Mission'))) {
    fail('Briefing sheet action row never settled on-screen.');
  }
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 15),
  String? timeoutMessage,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(timeoutMessage ?? 'Condition was not met within $timeout.');
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
