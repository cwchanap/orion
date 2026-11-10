import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/orion_surface.dart';
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

  test('kit semantic roles resolve to the kit.css values', () {
    const t = OrionUiTheme.dark;
    expect(t.textMuted, const Color(0xFF9DB2C3), reason: '--muted');
    expect(t.textDim, const Color(0xFF5F7487), reason: '--dim');
    expect(t.actionAmber, const Color(0xFFFFA62B), reason: '--amber');
    expect(t.medalBronze, const Color(0xFFD9925A), reason: '--bronze');
    expect(t.medalSilver, const Color(0xFFCFDBE6), reason: '--silver');
    expect(t.systemCyan, const Color(0xFF46E6FF));
    expect(t.systemViolet, const Color(0xFFA98BFF));
    expect(t.naniteGreen, const Color(0xFF7BE495));
    expect(t.warningOrange, const Color(0xFFFF8A3D));
    expect(t.dangerRed, const Color(0xFFFF5D6C));
  });

  test('new roles survive copyWith and lerp', () {
    const t = OrionUiTheme.dark;
    expect(t.copyWith().textDim, t.textDim);
    expect(t.copyWith().actionAmber, t.actionAmber);
    expect(t.copyWith().medalBronze, t.medalBronze);
    expect(t.copyWith().medalSilver, t.medalSilver);
    final other = t.copyWith(
      textDim: Colors.white,
      actionAmber: Colors.white,
      medalBronze: Colors.white,
      medalSilver: Colors.white,
    );
    expect(t.lerp(other, 0).textDim, t.textDim);
    expect(t.lerp(other, 1).textDim, Colors.white);
    expect(t.lerp(other, 1).actionAmber, Colors.white);
    expect(t.lerp(other, 1).medalBronze, Colors.white);
    expect(t.lerp(other, 1).medalSilver, Colors.white);
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
              return const OrionSurface(
                role: OrionSurfaceRole.card,
                child: Text('Hull'),
              );
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
