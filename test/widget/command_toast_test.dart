import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/ui/command_frame.dart';
import 'package:orion/game/ui/command_toast.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Widget toastHost(
  String? feedback, {
  int revision = 0,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Semantics(
        label: 'toast-host-$revision',
        child: CommandToast(
          key: const ValueKey('test-command-toast'),
          feedback: feedback,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('toast stays latched through null and exits only on its timer', (
    tester,
  ) async {
    await tester.pumpWidget(toastHost('Not enough gold.'));

    expect(find.text('Not enough gold.'), findsOneWidget);
    await tester.pumpWidget(toastHost(null, revision: 1));
    expect(find.text('Not enough gold.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2399));
    expect(find.text('Not enough gold.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text('Not enough gold.'), findsNothing);
  });

  testWidgets(
    'null rearms the same text and different text restarts the timer',
    (tester) async {
      await tester.pumpWidget(toastHost('First'));
      await tester.pump(const Duration(seconds: 1));

      await tester.pumpWidget(toastHost('Second', revision: 1));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Second'), findsOneWidget);

      await tester.pumpWidget(toastHost(null, revision: 2));
      await tester.pumpWidget(toastHost('Second', revision: 3));
      await tester.pump(const Duration(milliseconds: 2399));
      expect(find.text('Second'), findsOneWidget);
    },
  );

  testWidgets('uninterrupted duplicate input does not restart the timer', (
    tester,
  ) async {
    await tester.pumpWidget(toastHost('Hold'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(toastHost('Hold', revision: 1));
    await tester.pump(const Duration(milliseconds: 1399));
    expect(find.text('Hold'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text('Hold'), findsNothing);
  });

  testWidgets(
    'expired copy does not reappear when a replacement arrives during exit',
    (tester) async {
      await tester.pumpWidget(toastHost('Expired'));
      await tester.pump(const Duration(milliseconds: 2399));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 70));

      await tester.pumpWidget(toastHost('Replacement', revision: 1));

      expect(find.text('Expired'), findsNothing);
      expect(find.text('Replacement'), findsOneWidget);
    },
  );

  testWidgets('different feedback replaces the latched copy', (tester) async {
    await tester.pumpWidget(toastHost('First'));
    await tester.pumpWidget(toastHost('Second', revision: 1));

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('active timer is canceled when the toast is disposed', (
    tester,
  ) async {
    await tester.pumpWidget(toastHost('Dispose me'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback maps to danger, warning, and neutral tones', (
    tester,
  ) async {
    final cases = <({String feedback, Color color})>[
      (feedback: 'Wave failed.', color: OrionUiTheme.dark.dangerRed),
      (
        feedback: 'Could not save campaign progress.',
        color: OrionUiTheme.dark.dangerRed,
      ),
      (feedback: 'Not enough gold.', color: OrionUiTheme.dark.warningOrange),
      (
        feedback: 'Railgun locked until wave 4.',
        color: OrionUiTheme.dark.warningOrange,
      ),
      (
        feedback: 'Wave cannot start right now.',
        color: OrionUiTheme.dark.warningOrange,
      ),
      (feedback: 'Tower placed.', color: OrionUiTheme.dark.systemCyan),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(toastHost(testCase.feedback));
      final frame = tester.widget<CommandFrame>(
        find.byKey(const ValueKey('command-toast')),
      );
      expect(frame.borderColor, testCase.color, reason: testCase.feedback);
    }
  });

  testWidgets('feedback text is limited to two lines', (tester) async {
    const feedback =
        'This is a deliberately long mission feedback message that should remain readable.';
    await tester.pumpWidget(toastHost(feedback));

    final text = tester.widget<Text>(find.text(feedback));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('toast width is capped to viewport minus 32dp', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const feedback =
        'This deliberately long feedback copy must wrap within the safe portrait viewport width.';
    await tester.pumpWidget(toastHost(feedback));

    final frameRect = tester.getRect(
      find.byKey(const ValueKey('command-toast')),
    );
    expect(frameRect.width, lessThanOrEqualTo(328));
  });

  testWidgets('reduced motion removes toast transitions', (tester) async {
    await tester.pumpWidget(
      toastHost('Reduced motion', disableAnimations: true),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });
}
