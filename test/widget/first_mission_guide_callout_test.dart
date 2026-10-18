import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orion/game/onboarding/first_mission_guide.dart';
import 'package:orion/game/ui/first_mission_guide_callout.dart';
import 'package:orion/game/ui/orion_theme_data.dart';

const _viewport = Size(360, 640);
const _safePadding = EdgeInsets.all(24);
final Rect _safeArea = Rect.fromLTRB(
  _safePadding.left,
  _safePadding.top,
  _viewport.width - _safePadding.right,
  _viewport.height - _safePadding.bottom,
);
const _bubbleKey = ValueKey('first-mission-guide-callout-bubble');

/// Binding copy from the design spec — asserted verbatim.
final Map<FirstMissionGuideStep, String> _copyByStep = {
  FirstMissionGuideStep.buildCell: 'Tap an empty cell to build here.',
  FirstMissionGuideStep.towerCard: 'Pick a tower.',
  FirstMissionGuideStep.startWave:
      "Start the wave when you're ready. Towers fire on their own.",
  FirstMissionGuideStep.upgrade: 'Tap a tower, then Upgrade between waves.',
  FirstMissionGuideStep.salvageModule:
      'Salvage Modules last only for this mission.',
  FirstMissionGuideStep.scanner: 'Check the scanner before the next wave.',
};

void _setSize(WidgetTester tester) {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _host(
  FirstMissionGuideStep step, {
  GlobalKey? anchorKey,
  Offset? targetPoint,
  List<Widget> beneath = const [],
  VoidCallback? onSkip,
  VoidCallback? onDone,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: orionThemeData,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(padding: _safePadding, disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: Stack(
        children: [
          ...beneath,
          Positioned.fill(
            child: FirstMissionGuideCallout(
              step: step,
              anchorKey: anchorKey,
              targetPoint: targetPoint,
              onSkip: onSkip ?? () {},
              onDone: onDone,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Post-frame measurement plus one motion window (orionSheetDuration 220ms)
/// so position corrections land before assertions.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

void _expectBubbleInsideSafeArea(WidgetTester tester, {String? reason}) {
  final rect = tester.getRect(find.byKey(_bubbleKey));
  expect(rect.left, greaterThanOrEqualTo(_safeArea.left), reason: reason);
  expect(rect.top, greaterThanOrEqualTo(_safeArea.top), reason: reason);
  expect(rect.right, lessThanOrEqualTo(_safeArea.right), reason: reason);
  expect(rect.bottom, lessThanOrEqualTo(_safeArea.bottom), reason: reason);
}

void main() {
  testWidgets('renders the exact copy for every step', (tester) async {
    _setSize(tester);
    for (final entry in _copyByStep.entries) {
      await tester.pumpWidget(
        _host(entry.key, targetPoint: const Offset(180, 140)),
      );
      await _settle(tester);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
    }
  });

  testWidgets('Skip tutorial always exists; Got it only on scanner', (
    tester,
  ) async {
    _setSize(tester);
    for (final entry in _copyByStep.entries) {
      await tester.pumpWidget(
        _host(
          entry.key,
          targetPoint: const Offset(180, 140),
          onDone: entry.key == FirstMissionGuideStep.scanner ? () {} : null,
        ),
      );
      await _settle(tester);
      expect(
        find.text('Skip tutorial'),
        findsOneWidget,
        reason: entry.key.name,
      );
      expect(
        find.text('Got it'),
        entry.key == FirstMissionGuideStep.scanner
            ? findsOneWidget
            : findsNothing,
        reason: entry.key.name,
      );
    }
  });

  testWidgets('Skip and Got it invoke only their own callbacks', (
    tester,
  ) async {
    _setSize(tester);
    var skips = 0;
    var dones = 0;
    await tester.pumpWidget(
      _host(
        FirstMissionGuideStep.scanner,
        targetPoint: const Offset(180, 140),
        onSkip: () => skips++,
        onDone: () => dones++,
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Skip tutorial'));
    await tester.pump();
    expect(skips, 1);
    expect(dones, 0);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(skips, 1);
    expect(dones, 1);
  });

  testWidgets('exposes the current copy as a live-region semantics label', (
    tester,
  ) async {
    _setSize(tester);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          FirstMissionGuideStep.buildCell,
          targetPoint: const Offset(180, 140),
        ),
      );
      await _settle(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel(_copyByStep[FirstMissionGuideStep.buildCell]!),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('anchor near each viewport edge clamps inside the SafeArea', (
    tester,
  ) async {
    _setSize(tester);
    final corners = [
      ('top-left', Alignment.topLeft),
      ('top-right', Alignment.topRight),
      ('bottom-left', Alignment.bottomLeft),
      ('bottom-right', Alignment.bottomRight),
    ];
    for (final (name, alignment) in corners) {
      final anchorKey = GlobalKey();
      await tester.pumpWidget(
        _host(
          FirstMissionGuideStep.towerCard,
          anchorKey: anchorKey,
          beneath: [
            Positioned.fill(
              child: Align(
                alignment: alignment,
                child: SizedBox(key: anchorKey, width: 40, height: 40),
              ),
            ),
          ],
        ),
      );
      await _settle(tester);
      _expectBubbleInsideSafeArea(tester, reason: name);
    }
  });

  testWidgets('an unattached anchor renders nothing until the anchor mounts', (
    tester,
  ) async {
    _setSize(tester);
    final anchorKey = GlobalKey();
    Widget host({required bool attach}) => _host(
      FirstMissionGuideStep.towerCard,
      anchorKey: anchorKey,
      beneath: [
        if (attach)
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(key: anchorKey, width: 40, height: 40),
            ),
          ),
      ],
    );

    Finder connector() => find.descendant(
      of: find.byType(FirstMissionGuideCallout),
      matching: find.byType(CustomPaint),
    );

    // The anchor key is not mounted: no bubble, no connector, no copy —
    // pointing at the (w/2, h/3) fallback would draw a meaningless ring.
    await tester.pumpWidget(host(attach: false));
    await _settle(tester);
    expect(find.byKey(_bubbleKey), findsNothing);
    expect(connector(), findsNothing);
    expect(
      find.text(_copyByStep[FirstMissionGuideStep.towerCard]!),
      findsNothing,
    );

    // Once the anchor mounts the measure lands and the callout appears.
    await tester.pumpWidget(host(attach: true));
    await _settle(tester);
    expect(find.byKey(_bubbleKey), findsOneWidget);
    expect(connector(), findsWidgets);
    _expectBubbleInsideSafeArea(tester);
  });

  testWidgets('the bubble and its button row clear a tall anchored target', (
    tester,
  ) async {
    _setSize(tester);
    final anchorKey = GlobalKey();
    // A draft-frame-scale anchor: placement must measure from its edges,
    // not its center, or the bubble (and the Skip button inside it)
    // overlaps the anchor's lower half.
    await tester.pumpWidget(
      _host(
        FirstMissionGuideStep.salvageModule,
        anchorKey: anchorKey,
        onDone: () {},
        beneath: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(key: anchorKey, width: 200, height: 300),
            ),
          ),
        ],
      ),
    );
    await _settle(tester);

    final anchorRect = tester.getRect(find.byKey(anchorKey));
    final bubbleRect = tester.getRect(find.byKey(_bubbleKey));
    expect(
      bubbleRect.overlaps(anchorRect),
      isFalse,
      reason: 'the bubble must sit outside the anchor, not over it',
    );
    for (final label in ['Skip tutorial', 'Got it']) {
      expect(
        tester.getRect(find.text(label)).overlaps(anchorRect),
        isFalse,
        reason: '$label must not sit on the anchor it points at',
      );
    }
    _expectBubbleInsideSafeArea(tester);
  });

  testWidgets(
    'a partially off-screen anchor still renders inside the SafeArea',
    (tester) async {
      _setSize(tester);
      final anchorKey = GlobalKey();
      await tester.pumpWidget(
        _host(
          FirstMissionGuideStep.towerCard,
          anchorKey: anchorKey,
          beneath: [
            // Half of the anchor hangs off the left edge of the canvas.
            Positioned(
              left: -60,
              top: 300,
              child: SizedBox(key: anchorKey, width: 100, height: 100),
            ),
          ],
        ),
      );
      await _settle(tester);

      expect(find.byKey(_bubbleKey), findsOneWidget);
      _expectBubbleInsideSafeArea(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'board-path targetPoint renders a connector and stays in bounds',
    (tester) async {
      _setSize(tester);
      await tester.pumpWidget(
        _host(
          FirstMissionGuideStep.buildCell,
          targetPoint: const Offset(120, 316),
        ),
      );
      await _settle(tester);

      expect(
        find.text(_copyByStep[FirstMissionGuideStep.buildCell]!),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
        findsWidgets,
      );
      _expectBubbleInsideSafeArea(tester);
    },
  );

  testWidgets('empty overlay space passes taps through to content beneath', (
    tester,
  ) async {
    _setSize(tester);
    var buttonTaps = 0;
    var skips = 0;
    await tester.pumpWidget(
      _host(
        FirstMissionGuideStep.startWave,
        targetPoint: const Offset(180, 120),
        onSkip: () => skips++,
        beneath: [
          Positioned(
            left: 24,
            bottom: 48,
            child: TextButton(
              key: const ValueKey('beneath-guide-button'),
              onPressed: () => buttonTaps++,
              child: const Text('Beneath'),
            ),
          ),
        ],
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('beneath-guide-button')));
    await tester.pump();

    expect(buttonTaps, 1);
    expect(skips, 0);
  });

  testWidgets('bubble chrome passes taps through to content beneath', (
    tester,
  ) async {
    _setSize(tester);
    var buttonTaps = 0;
    var skips = 0;
    await tester.pumpWidget(
      _host(
        FirstMissionGuideStep.startWave,
        // Target (180, 120) places the bubble at roughly x 36..324,
        // y 134..198; this probe sits on the bubble's copy area, well clear
        // of the right-aligned Skip / Got it row at the bottom-right.
        targetPoint: const Offset(180, 120),
        onSkip: () => skips++,
        beneath: [
          Positioned(
            left: 60,
            top: 145,
            child: GestureDetector(
              key: const ValueKey('beneath-bubble-button'),
              behavior: HitTestBehavior.opaque,
              onTap: () => buttonTaps++,
              child: const SizedBox(width: 48, height: 20),
            ),
          ),
        ],
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('beneath-bubble-button')));
    await tester.pump();

    expect(buttonTaps, 1);
    expect(skips, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion applies step transitions immediately', (
    tester,
  ) async {
    _setSize(tester);
    await tester.pumpWidget(
      _host(
        FirstMissionGuideStep.buildCell,
        targetPoint: const Offset(180, 120),
        disableAnimations: true,
      ),
    );
    await _settle(tester);

    await tester.pumpWidget(
      _host(
        FirstMissionGuideStep.scanner,
        targetPoint: const Offset(180, 120),
        disableAnimations: true,
        onDone: () {},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(_copyByStep[FirstMissionGuideStep.scanner]!),
      findsOneWidget,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
