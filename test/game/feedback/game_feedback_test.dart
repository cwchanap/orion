import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/game_feedback.dart';

/// An [AudioCache] that records [loadAll] invocations and can be configured
/// to throw, so the warming path and its failure branch are both reachable
/// without a real asset bundle or platform audio engine.
class _RecordingAudioCache extends AudioCache {
  _RecordingAudioCache({this.loadAllError});

  final Object? loadAllError;
  final List<String> loadedSounds = [];

  @override
  Future<List<Uri>> loadAll(List<String> fileNames) async {
    loadedSounds.addAll(fileNames);
    if (loadAllError != null) {
      throw loadAllError!;
    }
    return const <Uri>[];
  }
}

const MethodChannel _globalAudioChannel = MethodChannel(
  'xyz.luan/audioplayers.global',
);
const MethodChannel _audioChannel = MethodChannel('xyz.luan/audioplayers');

void main() {
  late AudioCache originalAudioCache;
  late _RecordingAudioCache recordingCache;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    originalAudioCache = FlameAudio.audioCache;
    recordingCache = _RecordingAudioCache();
    FlameAudio.audioCache = recordingCache;

    // The audioplayers platform channels have no engine behind them in a
    // unit test, so an unhandled call would hang forever. Stub the global
    // init to succeed (so GlobalAudioScope.ensureInitialized settles and
    // never leaves a never-completing completer for later tests) and every
    // per-player call to throw an Exception, which FlameAudio.play surfaces
    // as a future error that PlatformGameFeedback._playSound swallows.
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _globalAudioChannel,
          (MethodCall call) async => null,
        );
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _audioChannel,
          (MethodCall call) async =>
              throw Exception('audioplayers unavailable'),
        );
  });

  tearDown(() {
    FlameAudio.audioCache = originalAudioCache;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_globalAudioChannel, null);
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioChannel, null);
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> flush(WidgetTester tester) async {
    // Let the unawaited sound/haptic futures settle. A few short pumps flush
    // the microtask chains behind the mocked platform channels.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  void mockHaptics(WidgetTester tester, bool succeed) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method != 'HapticFeedback.vibrate') {
            return null;
          }
          if (!succeed) {
            throw Exception('haptics unavailable');
          }
          return null;
        });
  }

  group('PlatformGameFeedback', () {
    testWidgets(
      'warms the audio cache at construction, before any semantic cue is '
      'fired',
      (tester) async {
        // The design specifies the best-effort loadAll warm-up fires when
        // the service is constructed, not lazily on the first emit —
        // otherwise the very first cue pays the uncached first-play latency
        // the warm-up exists to avoid.
        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
        );

        // Flush only the constructor's unawaited warm-up microtask. No cue
        // has been fired yet.
        await flush(tester);

        expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
        expect(tester.takeException(), isNull);
        // Reference feedback so the linter does not complain; the cue
        // methods are exercised by the other tests below.
        feedback.towerConfirmed();
      },
    );

    testWidgets(
      'emits each event, warms the cache once, and fires every haptic when '
      'enabled',
      (tester) async {
        final hapticCalls = <Object?>[];
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'HapticFeedback.vibrate') {
                hapticCalls.add(call.arguments);
              }
              return null;
            });

        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
        );

        feedback.towerConfirmed();
        feedback.moduleSelected();
        feedback.waveCleared();
        feedback.bossDefeated();
        feedback.missionVictory();
        feedback.baseDefeated();

        await flush(tester);

        // The cache warms exactly once with the full sound list (at
        // construction), even though five events emit sounds.
        expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
        // Every event carries a haptic.
        expect(hapticCalls, hasLength(6));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'skips sound playback when sound effects are disabled but still warms '
      'the cache at construction',
      (tester) async {
        final hapticCalls = <Object?>[];
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'HapticFeedback.vibrate') {
                hapticCalls.add(call.arguments);
              }
              return null;
            });

        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => false,
          hapticsEnabled: () => true,
        );

        feedback.towerConfirmed();
        await flush(tester);

        // Warming is unconditional (best-effort, construction-time); only
        // playback is gated by the enabled flag.
        expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
        expect(hapticCalls, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('skips haptic when haptics are disabled', (tester) async {
      final hapticCalls = <Object?>[];
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'HapticFeedback.vibrate') {
              hapticCalls.add(call.arguments);
            }
            return null;
          });

      final feedback = PlatformGameFeedback(
        soundEffectsEnabled: () => true,
        hapticsEnabled: () => false,
      );

      feedback.towerConfirmed();
      await flush(tester);

      // Cache warms at construction; haptic is suppressed.
      expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
      expect(hapticCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'boss defeated emits a haptic only (cache warms at construction '
      'regardless of which cue fires)',
      (tester) async {
        final hapticCalls = <Object?>[];
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'HapticFeedback.vibrate') {
                hapticCalls.add(call.arguments);
              }
              return null;
            });

        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
        );

        feedback.bossDefeated();
        await flush(tester);

        // Warming is construction-time and unconditional; bossDefeated
        // itself carries no sound, only a haptic.
        expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
        expect(hapticCalls, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('absorbs audio cache warm, sound play, and haptic failures', (
      tester,
    ) async {
      // Throwing cache -> _warmAudioCache (now fired at construction)
      // swallows. Throwing haptics mock -> _playHaptic swallows. Per-player
      // audioplayers mock (set in setUp) throws -> FlameAudio.play errors
      // -> _playSound swallows. Nothing escapes.
      FlameAudio.audioCache = _RecordingAudioCache(
        loadAllError: StateError('warm failed'),
      );
      mockHaptics(tester, false);

      final feedback = PlatformGameFeedback(
        soundEffectsEnabled: () => true,
        hapticsEnabled: () => true,
      );

      feedback.towerConfirmed();
      await flush(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('NoOpGameFeedback', () {
    test('every method is a safe no-op', () {
      const feedback = NoOpGameFeedback();
      feedback.towerConfirmed();
      feedback.moduleSelected();
      feedback.waveCleared();
      feedback.bossDefeated();
      feedback.missionVictory();
      feedback.baseDefeated();
    });
  });
}
