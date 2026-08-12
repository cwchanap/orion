import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/feedback_preferences.dart';
import 'package:orion/game/ui/feedback_settings_sheet.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    FeedbackPreferences initial = const FeedbackPreferences(),
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackSettingsSheet(
            initialPreferences: initial,
            reduceMotion: reduceMotion,
          ),
        ),
      ),
    );
  }

  testWidgets('renders all labels', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Sound Effects'), findsOneWidget);
    expect(find.text('Haptics'), findsOneWidget);
    expect(find.text('Reduced Motion'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches reflect the provided preferences independently', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      initial: const FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      ),
    );
    final soundSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Sound Effects'),
    );
    final hapticsSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Haptics'),
    );
    expect(soundSwitch.value, isFalse);
    expect(hapticsSwitch.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduceMotion true shows Follows system On', (tester) async {
    await pumpSheet(tester, reduceMotion: true);
    expect(find.text('Follows system • On'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduceMotion false shows Follows system Off', (tester) async {
    await pumpSheet(tester, reduceMotion: false);
    expect(find.text('Follows system • Off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling one switch changes only the local draft', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      initial: const FeedbackPreferences(
        soundEffectsEnabled: true,
        hapticsEnabled: true,
      ),
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Haptics'));
    await tester.pump();

    final soundSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Sound Effects'),
    );
    final hapticsSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Haptics'),
    );
    expect(soundSwitch.value, isTrue);
    expect(hapticsSwitch.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Done pops the final preferences value', (tester) async {
    FeedbackPreferences? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await showModalBottomSheet<FeedbackPreferences>(
                    context: context,
                    builder: (context) => const FeedbackSettingsSheet(
                      initialPreferences: FeedbackPreferences(),
                      reduceMotion: false,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Toggle Sound Effects off, then confirm Done pops the draft.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      popped,
      const FeedbackPreferences(
        soundEffectsEnabled: false,
        hapticsEnabled: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing via the barrier returns null (draft not persisted)', (
    tester,
  ) async {
    FeedbackPreferences? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await showModalBottomSheet<FeedbackPreferences>(
                    context: context,
                    builder: (context) => const FeedbackSettingsSheet(
                      initialPreferences: FeedbackPreferences(),
                      reduceMotion: false,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Toggle Sound Effects off in the draft, then dismiss without Done.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound Effects'));
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(popped, isNull);
    expect(tester.takeException(), isNull);
  });
}
