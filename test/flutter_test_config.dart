import 'package:flame_audio/flame_audio.dart'; // re-exports audioplayers
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Default audioplayers channel stubs, installed before the tests of every
/// file run and persisting across the tests of a file until overridden.
///
/// The page-owned [PlatformGameFeedback] eagerly initializes its 13 combat
/// `AudioPool`s at construction, which reaches the audioplayers platform
/// channels from otherwise unrelated widget tests that build `OrionGamePage`
/// without injecting feedback (e.g. `test/widget/sell_button_test.dart`).
/// Unstubbed, those calls can hang waiting for native events the test
/// binding never produces. The defaults below make the channels fail
/// promptly instead: global init completes, and per-player operations throw
/// an Exception that `PlatformGameFeedback` swallows. Tests that need
/// recording or success-path behavior override these locally and restore
/// them (see `test/feedback/platform_game_feedback_test.dart`).
const MethodChannel _globalAudioChannel = MethodChannel(
  'xyz.luan/audioplayers.global',
);
const MethodChannel _audioChannel = MethodChannel('xyz.luan/audioplayers');

Future<void> testExecutable(Future<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    _globalAudioChannel,
    (MethodCall call) async => null,
  );
  // Temporarily permissive while priming, so the warm-up player below can
  // complete its setup chain.
  messenger.setMockMethodCallHandler(
    _audioChannel,
    (MethodCall call) async => null,
  );

  // Prime the audioplayers global scope once per file, here in the
  // long-lived test-runner zone. `GlobalAudioScope` caches the Completer of
  // its first initialization; if that happened inside a test's FakeAsync
  // zone, every later test awaiting the same Completer would stall forever,
  // because the resumption microtask stays trapped in the finished test's
  // zone. Completing it here keeps AudioPlayer creation unblocked in every
  // test; per-player operations still fail promptly via the default stubs
  // registered below.
  final warmupPlayer = AudioPlayer();
  try {
    await warmupPlayer.setPlayerMode(PlayerMode.mediaPlayer);
  } catch (error) {
    // Never let warm-up trouble fail the file; tests stub channels anyway.
    debugPrint('flutter_test_config: audioplayers warm-up failed: $error');
  }

  messenger.setMockMethodCallHandler(
    _audioChannel,
    (MethodCall call) async => throw Exception('audioplayers unavailable'),
  );
  await testMain();
}
