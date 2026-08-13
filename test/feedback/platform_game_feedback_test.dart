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

  /// Sound file names passed to [loadPath] (i.e. actually played), in the
  /// order the play requests reach the cache. [loadPath] throws after
  /// recording so the audio chain never proceeds to the platform-level
  /// `setSourceUrl` call (which would hang waiting for a prepared event
  /// that the mocked channel never sends). [PlatformGameFeedback._playSound]
  /// swallows the error.
  final List<String> playedSounds = [];

  @override
  Future<List<Uri>> loadAll(List<String> fileNames) async {
    loadedSounds.addAll(fileNames);
    if (loadAllError != null) {
      throw loadAllError!;
    }
    return const <Uri>[];
  }

  @override
  Future<String> loadPath(String fileName) async {
    playedSounds.add(fileName);
    throw Exception('loadPath unavailable in test');
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
        PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
        );

        // Flush only the constructor's unawaited warm-up microtask. No cue
        // has been fired yet.
        await flush(tester);

        expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
        expect(tester.takeException(), isNull);
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

        // Allow the audioplayers setup chain (create, setAudioContext,
        // setReleaseMode, setPlayerMode, setVolume) to succeed so the
        // play path reaches AudioCache.loadPath — which records the sound
        // file name and then throws, preventing the chain from proceeding
        // to setSourceUrl (which would hang waiting for a prepared event
        // the mocked channel never sends). _playSound swallows the throw.
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_audioChannel, (MethodCall call) async {
              switch (call.method) {
                case 'create':
                case 'setAudioContext':
                case 'setReleaseMode':
                case 'setPlayerMode':
                case 'setVolume':
                  return null;
                default:
                  throw Exception('audioplayers unavailable');
              }
            });

        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
        );

        // Verify the exact sound mapping per event. After each event,
        // flush the microtask chain so the play request reaches loadPath,
        // then assert the recorded sound and clear the list for the next
        // event. bossDefeated is explicitly checked for no sound request.
        void expectPlayedSound(String? expected) {
          if (expected == null) {
            expect(recordingCache.playedSounds, isEmpty);
          } else {
            expect(recordingCache.playedSounds, [expected]);
          }
          recordingCache.playedSounds.clear();
        }

        feedback.towerConfirmed();
        await flush(tester);
        expectPlayedSound('confirm.wav');

        feedback.moduleSelected();
        await flush(tester);
        expectPlayedSound('confirm.wav');

        feedback.waveCleared();
        await flush(tester);
        expectPlayedSound('clear.wav');

        feedback.bossDefeated();
        await flush(tester);
        expectPlayedSound(null); // haptic only — no sound request

        feedback.missionVictory();
        await flush(tester);
        expectPlayedSound('victory.wav');

        feedback.baseDefeated();
        await flush(tester);
        expectPlayedSound('defeat.wav');

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
}
