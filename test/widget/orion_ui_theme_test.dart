import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

void main() {
  testWidgets('theme lookup falls back under a bare MaterialApp', (
    tester,
  ) async {
    late OrionUiTheme resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = OrionUiTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, OrionUiTheme.dark);
    expect(resolved.systemCyan, const Color(0xFF46E6FF));
    expect(resolved.creditGold, const Color(0xFFFFC857));
  });

  testWidgets('registered extension wins over the fallback', (tester) async {
    final custom = OrionUiTheme.dark.copyWith(systemCyan: Colors.pink);
    late OrionUiTheme resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [custom]),
        home: Builder(
          builder: (context) {
            resolved = OrionUiTheme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved.systemCyan, Colors.pink);
  });

  testWidgets('reactor action is at least 48dp and invokes once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ReactorButton(
            tooltip: 'Launch Mission',
            label: 'Launch',
            icon: Icons.rocket_launch,
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byTooltip('Launch Mission'));
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Launch Mission'));
    expect(taps, 1);

    // The Tooltip must not duplicate the explicit Semantics label, or
    // VoiceOver/TalkBack will announce "Launch Mission" twice (once as the
    // label, once as the tooltip). With excludeFromSemantics on the Tooltip,
    // exactly one semantics node carries the label and its tooltip is empty.
    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(find.bySemanticsLabel('Launch Mission'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Launch Mission')),
        matchesSemantics(
          label: 'Launch Mission',
          tooltip: '',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('reactor semantics tap action fires onPressed', (tester) async {
    // excludeSemantics: true replaces the InkResponse's tap action, so the
    // outer Semantics must carry its own onTap or screen readers cannot
    // activate the button via the accessibility double-tap.
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ReactorButton(
            tooltip: 'Launch Mission',
            label: 'Launch',
            icon: Icons.rocket_launch,
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      final data = tester.getSemantics(find.bySemanticsLabel('Launch Mission'));
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        data.id,
        SemanticsAction.tap,
      );
      expect(taps, 1);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('disabled reactor semantics carries no tap action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Center(
          child: ReactorButton(
            tooltip: 'Launch Mission',
            label: 'Launch',
            icon: Icons.rocket_launch,
            onPressed: null,
          ),
        ),
      ),
    );

    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Launch Mission')),
        matchesSemantics(
          label: 'Launch Mission',
          tooltip: '',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'reactor caption clamps text scale so the button never overflows',
    (tester) async {
      // The reactor caption caps textScaler at 1.15x (see command_frame.dart).
      // This is a deliberate trade-off for the compact 48dp button: unbounded
      // scaling would overflow the fixed frame. This test verifies the clamp
      // prevents overflow at an extreme system scale — it is NOT a claim that
      // the button supports large-text accessibility. Real large-text support
      // is tracked separately.
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3.0)),
            child: child!,
          ),
          home: const Center(
            child: ReactorButton(
              tooltip: 'Launch Mission',
              label: 'Launch Mission Long Label',
              icon: Icons.rocket_launch,
              onPressed: null,
              size: 48,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Launch Mission Long Label'), findsOneWidget);
    },
  );

  testWidgets('reduced motion returns zero duration', (tester) async {
    late Duration resolved;
    late AnimationStyle? sheetStyle;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = orionMotionDuration(
                context,
                const Duration(milliseconds: 220),
              );
              sheetStyle = orionSheetAnimationStyle(context);
              return const CommandFrame(child: Text('Hull'));
            },
          ),
        ),
      ),
    );

    expect(resolved, Duration.zero);
    expect(sheetStyle, AnimationStyle.noAnimation);
    expect(find.text('Hull'), findsOneWidget);
  });
}
