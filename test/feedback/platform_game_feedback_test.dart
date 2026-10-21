import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/game_feedback.dart';
import 'package:orion/game/models/game_models.dart';

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
  // Filenames accepted by the injected combat-sound starter, and the fake
  // monotonic clock driving limiter admission in the tests below.
  final combatStarts = <String>[];
  var clockMs = 0;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    combatStarts.clear();
    clockMs = 0;
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

  // Fires a one-shot cue and lets its detached FlameAudio.play chain reach
  // loadPath. The chain crosses zone machinery: the global-scope init
  // completer is primed once per file by flutter_test_config in the
  // runner's root zone (its resumptions only run in real time, via
  // runAsync), while the per-player hops complete inside this test's
  // FakeAsync zone (flushed by pumps). Alternate both, bounded, until the
  // recording cache sees the play.
  Future<void> fireOneShot(WidgetTester tester, void Function() trigger) async {
    recordingCache.playedSounds.clear();
    trigger();
    for (
      var round = 0;
      round < 6 && recordingCache.playedSounds.isEmpty;
      round++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await flush(tester);
    }
    expect(
      recordingCache.playedSounds,
      hasLength(1),
      reason: 'one-shot play chain never reached loadPath',
    );
  }

  // Allows the audioplayers setup chain (create, setAudioContext,
  // setReleaseMode, setPlayerMode, setVolume) to succeed so one-shot plays
  // (legacy stingers and rare cues) reach loadPath — which records the file
  // name and then throws, preventing the chain from proceeding to the
  // platform-level setSourceUrl call (which would hang waiting for a
  // prepared event that the mocked channel never sends).
  void allowOneShotSetupChain() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioChannel, (MethodCall call) async {
          switch (call.method) {
            case 'create':
              // Stub this player's event channel as well: without any
              // handler its 'listen' activation reports a
              // MissingPluginException that fails the test.
              final playerId = call.arguments['playerId'] as String;
              TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(
                    MethodChannel('xyz.luan/audioplayers/events/$playerId'),
                    (MethodCall eventCall) async => null,
                  );
              return null;
            case 'setAudioContext':
            case 'setReleaseMode':
            case 'setPlayerMode':
            case 'setVolume':
              return null;
            default:
              throw Exception('audioplayers unavailable');
          }
        });
  }

  // A [PlatformGameFeedback] whose combat cues start through a recording
  // callback on a fake clock. The starter replaces pool creation and
  // readiness entirely, so no AudioPool is ever created and the recording
  // cache only sees one-shot (legacy/rare) plays.
  PlatformGameFeedback starterFeedback({
    required bool Function() soundEffectsEnabled,
    Future<void> Function(String file)? startCombatSound,
  }) {
    return PlatformGameFeedback(
      soundEffectsEnabled: soundEffectsEnabled,
      hapticsEnabled: () => true,
      startCombatSound:
          startCombatSound ?? (file) async => combatStarts.add(file),
      nowMs: () => clockMs,
    );
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

        // Let one-shot plays reach loadPath, which records the sound file
        // name and then throws (see allowOneShotSetupChain); _playSound
        // swallows the throw.
        allowOneShotSetupChain();

        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
          // Bypass pool creation so the recording cache only sees the
          // one-shot plays under test; the 13 combat cues and their starter
          // mapping are covered in the combat playback group below.
          startCombatSound: (file) async {},
          nowMs: () => clockMs,
        );

        // Verify the exact sound mapping per event. fireOneShot lets each
        // detached play chain reach loadPath, then asserts the recorded
        // sound and clears the list for the next event.
        void expectPlayedSound(String? expected) {
          if (expected == null) {
            expect(recordingCache.playedSounds, isEmpty);
          } else {
            expect(recordingCache.playedSounds, [expected]);
          }
          recordingCache.playedSounds.clear();
        }

        await fireOneShot(tester, feedback.towerConfirmed);
        expectPlayedSound('confirm.wav');

        await fireOneShot(tester, feedback.moduleSelected);
        expectPlayedSound('confirm.wav');

        await fireOneShot(tester, feedback.waveCleared);
        expectPlayedSound('clear.wav');

        await fireOneShot(tester, feedback.bossDefeated);
        // Rare cues play outside the limiter — and boss defeat now carries
        // its own WAV alongside the retained medium haptic.
        expectPlayedSound('boss_defeated.wav');

        await fireOneShot(tester, feedback.missionVictory);
        expectPlayedSound('victory.wav');

        await fireOneShot(tester, feedback.baseDefeated);
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
      'boss defeated emits its rare WAV and the retained medium haptic',
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

        allowOneShotSetupChain();

        final feedback = PlatformGameFeedback(
          soundEffectsEnabled: () => true,
          hapticsEnabled: () => true,
          startCombatSound: (file) async {},
          nowMs: () => clockMs,
        );

        await fireOneShot(tester, feedback.bossDefeated);

        // bossDefeated now plays its own stinger (instead of doubling a
        // generic death sound) and keeps the pre-existing medium haptic.
        expect(recordingCache.playedSounds, ['boss_defeated.wav']);
        expect(hapticCalls, ['HapticFeedbackType.mediumImpact']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('absorbs audio cache warm, sound play, and haptic failures', (
      tester,
    ) async {
      // Throwing cache -> _warmAudioCache (now fired at construction)
      // swallows. Throwing haptics mock -> _playHaptic swallows. Per-player
      // audioplayers mock (set in setUp) throws -> FlameAudio.play errors
      // -> _playSound swallows. Pool init failures are swallowed too. Nothing
      // escapes.
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

  group('PlatformGameFeedback combat playback (injected starter)', () {
    testWidgets(
      'maps all 21 cues to their exact WAV filenames, recording accepted '
      'combat starts at fake timestamps',
      (tester) async {
        allowOneShotSetupChain();
        final feedback = starterFeedback(soundEffectsEnabled: () => true);

        final combatCalls = <void Function()>[
          () => feedback.towerFired(TowerType.laser),
          () => feedback.towerFired(TowerType.rocket),
          () => feedback.towerFired(TowerType.cryo),
          () => feedback.towerFired(TowerType.railgun),
          () => feedback.towerFired(TowerType.ionChain),
          () => feedback.towerFired(TowerType.nanite),
          () => feedback.towerFired(TowerType.gravityWell),
          () => feedback.towerFired(TowerType.droneBay),
          feedback.splashImpact,
          feedback.chainImpact,
          feedback.pierceImpact,
          feedback.enemyDestroyed,
          feedback.coreHit,
        ];
        const expectedCombatFilenames = [
          'fire_laser.wav',
          'fire_rocket.wav',
          'fire_cryo.wav',
          'fire_railgun.wav',
          'fire_ion_chain.wav',
          'fire_nanite.wav',
          'fire_gravity_well.wav',
          'fire_drone_bay.wav',
          'impact_splash.wav',
          'impact_chain.wav',
          'impact_pierce.wav',
          'enemy_destroyed.wav',
          'core_hit.wav',
        ];

        // 500 ms between starts: past every per-cue cooldown (max 500 ms)
        // and long enough to fully expire the shared 2-per-500 ms window,
        // so each of the 13 pooled cues is admitted exactly once.
        for (var i = 0; i < combatCalls.length; i++) {
          combatCalls[i]();
          expect(combatStarts, expectedCombatFilenames.take(i + 1));
          clockMs += 500;
        }

        // The rare transition cues and the original four stingers play via
        // FlameAudio.play, outside the limiter and outside the starter.
        void expectOneShot(String expected) {
          expect(recordingCache.playedSounds, [expected]);
          recordingCache.playedSounds.clear();
        }

        await fireOneShot(tester, feedback.towerConfirmed);
        expectOneShot('confirm.wav');

        await fireOneShot(tester, feedback.moduleSelected);
        expectOneShot('confirm.wav');

        await fireOneShot(tester, feedback.waveCleared);
        expectOneShot('clear.wav');

        await fireOneShot(tester, feedback.waveStarted);
        expectOneShot('wave_start.wav');

        await fireOneShot(tester, feedback.bossArrived);
        expectOneShot('boss_arrival.wav');

        await fireOneShot(tester, feedback.bossDefeated);
        expectOneShot('boss_defeated.wav');

        await fireOneShot(tester, feedback.towerSold);
        expectOneShot('tower_sold.wav');

        await fireOneShot(tester, feedback.missionVictory);
        expectOneShot('victory.wav');

        await fireOneShot(tester, feedback.baseDefeated);
        expectOneShot('defeat.wav');

        // 13 combat + 4 rare + 4 legacy = 21 advertised filenames.
        expect(combatStarts, expectedCombatFilenames);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'admits pooled starts per the limiter: per-cue cooldown, shared '
      '2-per-500 ms budget, and rolling-window expiry',
      (tester) async {
        final feedback = starterFeedback(soundEffectsEnabled: () => true);

        feedback.towerFired(TowerType.laser); // clock 0 → admitted
        clockMs = 100;
        feedback.towerFired(TowerType.laser); // 100 ms < 120 ms → denied
        expect(combatStarts, ['fire_laser.wav']);

        clockMs = 200;
        feedback.towerFired(TowerType.rocket); // shared window [0, 200]
        clockMs = 300;
        feedback.towerFired(TowerType.cryo); // shared budget full → denied
        expect(combatStarts, ['fire_laser.wav', 'fire_rocket.wav']);

        clockMs = 500;
        feedback.towerFired(
          TowerType.laser,
        ); // laser cooldown passed, 0 ms pruned → admitted
        expect(combatStarts, [
          'fire_laser.wav',
          'fire_rocket.wav',
          'fire_laser.wav',
        ]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disabled Sound Effects consumes no admission slot; re-enabling plays '
      'immediately',
      (tester) async {
        var soundOn = false;
        final feedback = starterFeedback(soundEffectsEnabled: () => soundOn);

        feedback.coreHit();
        feedback.coreHit();
        expect(combatStarts, isEmpty);

        // If the disabled calls had consumed the 0 ms slot, this hit at
        // 10 ms would fall inside the 250 ms core-hit cooldown and be
        // denied. Admitted ⇒ disabled sound consumed nothing.
        clockMs = 10;
        soundOn = true;
        feedback.coreHit();
        clockMs = 20;
        feedback.towerFired(TowerType.laser);
        expect(combatStarts, ['core_hit.wav', 'fire_laser.wav']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a playback-start failure after admission keeps its timestamp and is '
      'not retried',
      (tester) async {
        var attempts = 0;
        final feedback = starterFeedback(
          soundEffectsEnabled: () => true,
          startCombatSound: (file) async {
            attempts++;
            throw Exception('start failed');
          },
        );

        feedback.towerFired(TowerType.laser); // clock 0 → admitted; start fails
        clockMs = 100;
        feedback.towerFired(
          TowerType.laser,
        ); // 100 ms < 120 ms → denied: failure kept its slot
        clockMs = 120;
        feedback.towerFired(TowerType.laser); // cooldown expired → admitted
        await flush(tester); // let the throwing starts settle

        expect(attempts, 2); // failed start never retried
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'two core hits cannot suppress a boss-defeat request: rare cues '
      'bypass the limiter',
      (tester) async {
        allowOneShotSetupChain();
        final feedback = starterFeedback(soundEffectsEnabled: () => true);

        feedback.coreHit(); // clock 0 → admitted
        clockMs = 250;
        feedback.coreHit(); // exactly at the 250 ms interval → admitted
        expect(combatStarts, ['core_hit.wav', 'core_hit.wav']);

        clockMs = 300;
        // Would be starved if rare cues were limited.
        await fireOneShot(tester, feedback.bossDefeated);

        expect(recordingCache.playedSounds, ['boss_defeated.wav']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'haptics stay independent of the sound toggle: light boss arrival, '
      'retained medium boss defeat',
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
        final feedback = starterFeedback(soundEffectsEnabled: () => false);

        feedback.bossArrived();
        feedback.bossDefeated();
        feedback.waveStarted(); // sound-only rare cue: no haptic
        feedback.towerFired(TowerType.laser); // pooled cue: sound off → silent
        await flush(tester);

        expect(recordingCache.playedSounds, isEmpty);
        expect(combatStarts, isEmpty);
        expect(hapticCalls, [
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.mediumImpact',
        ]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('defaults to a monotonic Stopwatch clock', (tester) async {
      final feedback = PlatformGameFeedback(
        soundEffectsEnabled: () => true,
        hapticsEnabled: () => true,
        startCombatSound: (file) async => combatStarts.add(file),
      );

      feedback.coreHit();
      feedback.coreHit(); // real elapsed time ≪ 250 ms → denied
      await flush(tester);

      expect(combatStarts, ['core_hit.wav']);
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'PlatformGameFeedback pool warm-up and readiness (production path)',
    () {
      testWidgets(
        'warms exactly the four legacy WAVs, fails pool init best-effort, and '
        'drops combat cues while pools are unready',
        (tester) async {
          // No starter injected: the constructor eagerly initializes pools,
          // which fail promptly against the throwing channel stubs.
          final feedback = PlatformGameFeedback(
            soundEffectsEnabled: () => true,
            hapticsEnabled: () => true,
          );
          await flush(tester);

          // Ruling B: the loadAll warm-up stays exactly the four legacy WAVs
          // — pool warm-up must not add the 13 combat files to it.
          expect(recordingCache.loadedSounds, PlatformGameFeedback.sounds);
          expect(recordingCache.playedSounds, isEmpty);

          feedback.towerFired(TowerType.laser);
          feedback.splashImpact();
          feedback.enemyDestroyed();
          feedback.coreHit();
          await flush(tester);

          // Unready pools: cues silently dropped, no crash, nothing played.
          expect(recordingCache.playedSounds, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'drops combat cues while pools are still initializing and settles '
        'when initialization later fails',
        (tester) async {
          // Park pool creation on the gated per-player 'create' call; the
          // global scope init is already primed by flutter_test_config.
          final initGate = Completer<void>();
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(_audioChannel, (MethodCall call) async {
                if (call.method == 'create') {
                  await initGate.future;
                }
                throw Exception('audioplayers unavailable');
              });

          final feedback = PlatformGameFeedback(
            soundEffectsEnabled: () => true,
            hapticsEnabled: () => true,
          );

          // Pool creation is parked on the gate: no pool is ready, so the
          // cue is dropped without consuming admission or crashing.
          feedback.coreHit();
          await flush(tester);
          expect(recordingCache.playedSounds, isEmpty);
          expect(tester.takeException(), isNull);

          // Let creation proceed into the throwing stub: every pool fails,
          // the failures are swallowed, and the service keeps working.
          initGate.complete();
          await flush(tester);
          expect(recordingCache.playedSounds, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
