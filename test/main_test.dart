import 'dart:async';

import 'package:flutter/foundation.dart' as foundation show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/main.dart' as orion;

const _globalAudioChannel = MethodChannel('xyz.luan/audioplayers.global');

void main() {
  tearDown(() {
    // Restore the permissive global stub installed by flutter_test_config.
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_globalAudioChannel, (call) async => null);
  });

  testWidgets('waits for the shared audio context before booting the app', (
    tester,
  ) async {
    final oldDebugPrint = foundation.debugPrint;
    final debugMessages = <String>[];
    foundation.debugPrint = (message, {wrapWidth}) {
      if (message != null) debugMessages.add(message);
    };
    try {
      final gate = Completer<void>();
      final contextCalls = <MethodCall>[];
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_globalAudioChannel, (call) async {
            if (call.method == 'setAudioContext') {
              contextCalls.add(call);
              await gate.future;
            }
            return null;
          });

      late Future<void> startup;
      await tester.runAsync(() async {
        startup = orion.main();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });

      expect(contextCalls, hasLength(1));
      expect(contextCalls.single.arguments, gameAudioContext.toJson());
      expect(find.byType(orion.OrionApp), findsNothing);

      gate.complete();
      await tester.runAsync(() => startup);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );

      expect(find.byType(orion.OrionApp), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    } finally {
      foundation.debugPrint = oldDebugPrint;
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('boots the app when global audio context setup fails', (
    tester,
  ) async {
    final oldDebugPrint = foundation.debugPrint;
    final debugMessages = <String>[];
    foundation.debugPrint = (message, {wrapWidth}) {
      if (message != null) debugMessages.add(message);
    };
    try {
      final contextCalls = <MethodCall>[];
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_globalAudioChannel, (call) async {
            if (call.method == 'setAudioContext') {
              contextCalls.add(call);
              throw PlatformException(code: 'audio-context-unavailable');
            }
            return null;
          });

      await tester.runAsync(orion.main);
      await tester.pump();
      // The warm-cache failure trails real rootBundle reads of the audio
      // assets; CI disks can exceed the fixed 5 ms this test once allowed,
      // so poll for the message instead of racing it.
      final warmCacheDeadline = DateTime.now().add(const Duration(seconds: 2));
      await tester.runAsync(() async {
        while (!debugMessages.any(
              (message) => message.startsWith(
                'PlatformGameFeedback: failed to warm audio cache:',
              ),
            ) &&
            DateTime.now().isBefore(warmCacheDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(contextCalls, hasLength(1));
      expect(contextCalls.single.arguments, gameAudioContext.toJson());
      expect(find.byType(orion.OrionApp), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        debugMessages,
        contains(
          startsWith('Orion: failed to configure shared audio context:'),
        ),
      );
      expect(
        debugMessages,
        contains(
          startsWith('PlatformGameFeedback: failed to warm audio cache:'),
        ),
        reason:
            'the test binding lacks path_provider; its caught log is captured',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    } finally {
      foundation.debugPrint = oldDebugPrint;
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
