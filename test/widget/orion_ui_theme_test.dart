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
  });

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
