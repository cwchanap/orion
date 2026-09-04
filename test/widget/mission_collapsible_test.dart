import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/mission_collapsible.dart';

const _collapsedKey = ValueKey('probe-collapsed');
const _expandedKey = ValueKey('probe-expanded');

Widget _host(
  MissionCollapsible collapsible, {
  bool disableAnimations = false,
  void Function()? onBackgroundTap,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBackgroundTap,
            ),
          ),
          Align(alignment: Alignment.topLeft, child: collapsible),
        ],
      ),
    ),
  );
}

MissionCollapsible _collapsible({
  bool collapseRequested = false,
  Object? resetToken,
  ValueChanged<bool>? onExpandedChanged,
}) {
  Widget probe({
    required Key key,
    required VoidCallback toggle,
    required Size size,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
      child: SizedBox.fromSize(key: key, size: size),
    );
  }

  return MissionCollapsible(
    collapseRequested: collapseRequested,
    resetToken: resetToken,
    onExpandedChanged: onExpandedChanged,
    collapsedBuilder: (context, toggle) =>
        probe(key: _collapsedKey, toggle: toggle, size: const Size.square(48)),
    expandedBuilder: (context, toggle) =>
        probe(key: _expandedKey, toggle: toggle, size: const Size(212, 168)),
  );
}

void main() {
  testWidgets('collapsed trigger toggles expanded', (tester) async {
    await tester.pumpWidget(_host(_collapsible()));
    expect(find.byKey(_collapsedKey), findsOneWidget);

    await tester.tap(find.byKey(_collapsedKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedKey), findsOneWidget);
  });

  testWidgets('expanded trigger toggles collapsed', (tester) async {
    await tester.pumpWidget(_host(_collapsible()));
    await tester.tap(find.byKey(_collapsedKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedKey), findsOneWidget);

    await tester.tap(find.byKey(_expandedKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_collapsedKey), findsOneWidget);
  });

  testWidgets('collapseRequested closes immediately', (tester) async {
    await tester.pumpWidget(_host(_collapsible()));
    await tester.tap(find.byKey(_collapsedKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedKey), findsOneWidget);

    await tester.pumpWidget(_host(_collapsible(collapseRequested: true)));
    expect(find.byKey(_collapsedKey), findsOneWidget);
    expect(find.byKey(_expandedKey), findsNothing);
  });

  testWidgets('collapseRequested disables pointer input', (tester) async {
    var backgroundTaps = 0;
    await tester.pumpWidget(
      _host(
        _collapsible(collapseRequested: true),
        onBackgroundTap: () => backgroundTaps += 1,
      ),
    );

    final collapsedRect = tester.getRect(find.byKey(_collapsedKey));
    await tester.tapAt(collapsedRect.center);
    expect(backgroundTaps, 1);
  });

  testWidgets('resetToken change closes expanded state', (tester) async {
    await tester.pumpWidget(_host(_collapsible(resetToken: 1)));
    await tester.tap(find.byKey(_collapsedKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_expandedKey), findsOneWidget);

    await tester.pumpWidget(_host(_collapsible(resetToken: 2)));
    expect(find.byKey(_collapsedKey), findsOneWidget);
    expect(find.byKey(_expandedKey), findsNothing);
  });

  testWidgets(
    'outgoing expanded rectangle is not hit-testable after one transition frame',
    (tester) async {
      var backgroundTaps = 0;
      void countTap() => backgroundTaps += 1;
      await tester.pumpWidget(_host(_collapsible(), onBackgroundTap: countTap));
      // 1. open the expanded child.
      await tester.tap(find.byKey(_collapsedKey));
      await tester.pumpAndSettle();
      // 2. record its rectangle.
      final formerExpandedRect = tester.getRect(find.byKey(_expandedKey));

      // 3. pump with collapseRequested: true.
      await tester.pumpWidget(
        _host(_collapsible(collapseRequested: true), onBackgroundTap: countTap),
      );
      // 4. pump 1ms.
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(_expandedKey), findsNothing);

      // 5. tap the former expanded rectangle.
      await tester.tapAt(formerExpandedRect.center);
      // 6. the background receives exactly one tap.
      expect(backgroundTaps, 1);
    },
  );

  testWidgets(
    'outgoing expanded rectangle is not hit-testable after a local collapse',
    (tester) async {
      var backgroundTaps = 0;
      void countTap() => backgroundTaps += 1;
      await tester.pumpWidget(_host(_collapsible(), onBackgroundTap: countTap));
      // 1. open the expanded child.
      await tester.tap(find.byKey(_collapsedKey));
      await tester.pumpAndSettle();
      // 2. record its rectangle.
      final formerExpandedRect = tester.getRect(find.byKey(_expandedKey));

      // 3. collapse by tapping the expanded trigger (collapseRequested stays
      //    false), so the stale-area case cannot rely on IgnorePointer masking
      //    the outgoing child — AnimatedSwitcher must release it on its own.
      await tester.tap(find.byKey(_expandedKey));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(_expandedKey), findsNothing);

      // 4. tap the former expanded rectangle.
      await tester.tapAt(formerExpandedRect.center);
      // 5. the background receives exactly one tap.
      expect(backgroundTaps, 1);
    },
  );

  testWidgets('Reduced Motion makes the switch duration zero', (tester) async {
    await tester.pumpWidget(_host(_collapsible(), disableAnimations: true));
    await tester.tap(find.byKey(_collapsedKey));
    await tester.pump();
    expect(find.byKey(_expandedKey), findsOneWidget);

    await tester.tap(find.byKey(_expandedKey));
    await tester.pump();
    expect(find.byKey(_collapsedKey), findsOneWidget);
  });
}
