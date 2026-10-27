import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/feedback/game_music.dart';
import 'package:orion/game/models/game_models.dart';

const _audioChannel = MethodChannel('xyz.luan/audioplayers');

void main() {
  group('MusicTrack', () {
    test('uses the four HPA-168 filenames', () {
      expect(MusicTrack.values.map((track) => track.filename), [
        'music_map.wav',
        'music_build.wav',
        'music_wave.wav',
        'music_boss.wav',
      ]);
    });
  });

  group('desiredMusicTrack', () {
    test('selects map ambience without an active stage', () {
      _expectTrack(expected: MusicTrack.map);
    });

    test('selects build ambience in build phase', () {
      _expectTrack(
        stage: _snapshot(phase: GamePhase.build),
        expected: MusicTrack.build,
      );
    });

    test('selects wave ambience while a wave has no boss', () {
      _expectTrack(
        stage: _snapshot(phase: GamePhase.wave),
        expected: MusicTrack.wave,
      );
    });

    test('selects boss ambience while a boss is active', () {
      _expectTrack(
        stage: _snapshot(phase: GamePhase.wave, bossActive: true),
        expected: MusicTrack.boss,
      );
    });

    test('returns silence until preferences are loaded', () {
      _expectTrack(prefsLoaded: false, stage: null, expected: null);
    });

    test('returns silence when Music is off', () {
      _expectTrack(musicOn: false, stage: null, expected: null);
    });

    test('returns silence while the app is not foregrounded', () {
      _expectTrack(appForeground: false, stage: null, expected: null);
    });

    test('returns silence while the stage is paused', () {
      _expectTrack(stage: _snapshot(isPaused: true), expected: null);
    });

    test('returns silence after victory', () {
      _expectTrack(stage: _snapshot(phase: GamePhase.won), expected: null);
    });

    test('returns silence after defeat', () {
      _expectTrack(stage: _snapshot(phase: GamePhase.lost), expected: null);
    });
  });

  group('GameMusicController', () {
    test('does nothing for a repeated target', () async {
      final player = _FakeMusicPlayer();
      final controller = GameMusicController(player: player);

      await controller.set(MusicTrack.map);
      await controller.set(MusicTrack.map);

      expect(player.calls, ['play:music_map.wav']);
      await controller.dispose();
    });

    test('rapid target changes keep only the latest pending track', () async {
      final player = _FakeMusicPlayer()..playGate = Completer<void>();
      final controller = GameMusicController(player: player);

      final mapRequest = controller.set(MusicTrack.map);
      await player.playStarted.future;
      final waveRequest = controller.set(MusicTrack.wave);
      final bossRequest = controller.set(MusicTrack.boss);
      player.playGate!.complete();
      await Future.wait([mapRequest, waveRequest, bossRequest]);

      expect(player.calls, [
        'play:music_map.wav',
        'stop',
        'play:music_boss.wav',
      ]);
      await controller.dispose();
    });

    test('Music OFF stops a track whose play is still pending', () async {
      final player = _FakeMusicPlayer()..playGate = Completer<void>();
      final controller = GameMusicController(player: player);

      final play = controller.set(MusicTrack.map);
      await player.playStarted.future;
      final off = controller.set(null);
      player.playGate!.complete();
      await Future.wait([play, off]);

      expect(player.calls, ['play:music_map.wav', 'stop']);
      await controller.dispose();
    });

    test(
      'null stops and selecting the same track starts it from zero',
      () async {
        final player = _FakeMusicPlayer();
        final controller = GameMusicController(player: player);

        await controller.set(MusicTrack.build);
        await controller.set(null);
        await controller.set(MusicTrack.build);

        expect(player.calls, [
          'play:music_build.wav',
          'stop',
          'play:music_build.wav',
        ]);
        await controller.dispose();
      },
    );

    test('a repeated silence target retries a failed stop', () async {
      final player = _FakeMusicPlayer(stopError: StateError('stop failed'));
      final controller = GameMusicController(player: player);

      await controller.set(MusicTrack.map);
      await controller.set(null);

      player.stopError = null;
      await controller.set(null);

      expect(player.calls, ['play:music_map.wav', 'stop', 'stop']);
      await controller.dispose();
    });

    test('disposal invalidates pending playback and is idempotent', () async {
      final player = _FakeMusicPlayer()..playGate = Completer<void>();
      final controller = GameMusicController(player: player);

      final play = controller.set(MusicTrack.map);
      await player.playStarted.future;
      final firstDispose = controller.dispose();
      final secondDispose = controller.dispose();
      player.playGate!.complete();
      await Future.wait([play, firstDispose, secondDispose]);
      await controller.set(MusicTrack.boss);

      expect(player.calls, ['play:music_map.wav', 'stop', 'dispose']);
    });

    test('swallows and logs rejected play, stop, and disposal calls', () async {
      await _captureDebugPrint((messages) async {
        final player = _FakeMusicPlayer(
          playError: StateError('play failed'),
          stopError: StateError('stop failed'),
          disposeError: StateError('dispose failed'),
        );
        final controller = GameMusicController(player: player);

        await controller.set(MusicTrack.map);
        await controller.set(null);
        await controller.dispose();

        expect(
          messages.any((message) => message.contains('play failed')),
          isTrue,
        );
        expect(
          messages.any((message) => message.contains('stop failed')),
          isTrue,
        );
        expect(
          messages.any((message) => message.contains('dispose failed')),
          isTrue,
        );
        expect(player.calls.last, 'dispose');
      });
    });

    test('contains synchronous play construction failures', () async {
      await _captureDebugPrint((messages) async {
        final player = _FakeMusicPlayer(
          playError: StateError('constructor failed'),
          throwPlaySynchronously: true,
        );
        final controller = GameMusicController(player: player);

        await controller.set(MusicTrack.map);
        await controller.dispose();

        expect(
          messages.any((message) => message.contains('constructor failed')),
          isTrue,
        );
      });
    });

    test('default player constructs its Bgm only on first play', () async {
      final messenger =
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(_audioChannel, (call) async {
        methods.add(call.method);
        throw Exception('audioplayers unavailable');
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          _audioChannel,
          (call) async => throw Exception('audioplayers unavailable'),
        );
      });

      await _captureDebugPrint((messages) async {
        final controller = GameMusicController();

        expect(methods, isEmpty);
        await controller.set(null);
        expect(methods, isEmpty);

        await controller.set(MusicTrack.map);
        expect(methods, contains('create'));
        expect(messages, isNotEmpty);
        await controller.dispose();
      });
    });

    test('loads music from FlameAudio audio asset directory', () async {
      final originalMusicCache = FlameAudio.audioCache;
      final originalDefaultCache = AudioCache.instance;
      final musicCache = _RecordingAudioCache(prefix: 'assets/audio/');
      final defaultCache = _RecordingAudioCache(prefix: 'assets/');
      final messenger =
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
      FlameAudio.audioCache = musicCache;
      AudioCache.instance = defaultCache;
      messenger.setMockMethodCallHandler(_audioChannel, (call) async {
        if (call.method == 'create') {
          final playerId = call.arguments['playerId'] as String;
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$playerId'),
            (eventCall) async => null,
          );
        } else if (call.method == 'setSourceUrl') {
          final playerId = call.arguments['playerId'] as String;
          messenger.handlePlatformMessage(
            'xyz.luan/audioplayers/events/$playerId',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': 'audio.onPrepared',
              'value': true,
            }),
            (reply) {},
          );
        } else if (call.method == 'dispose') {
          final playerId = call.arguments['playerId'] as String;
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$playerId'),
            null,
          );
        }
        return null;
      });
      addTearDown(() {
        FlameAudio.audioCache = originalMusicCache;
        AudioCache.instance = originalDefaultCache;
        messenger.setMockMethodCallHandler(
          _audioChannel,
          (call) async => throw Exception('audioplayers unavailable'),
        );
      });

      final controller = GameMusicController();
      await controller.set(MusicTrack.map);
      await controller.dispose();

      expect(musicCache.assetKeys, ['assets/audio/music_map.wav']);
      expect(defaultCache.assetKeys, isEmpty);
    });
  });
}

void _expectTrack({
  bool prefsLoaded = true,
  bool musicOn = true,
  bool appForeground = true,
  GameSnapshot? stage,
  required MusicTrack? expected,
}) {
  expect(
    desiredMusicTrack(
      prefsLoaded: prefsLoaded,
      musicOn: musicOn,
      appForeground: appForeground,
      stage: stage,
    ),
    expected,
  );
}

GameSnapshot _snapshot({
  GamePhase phase = GamePhase.build,
  bool isPaused = false,
  bool bossActive = false,
}) => GameSnapshot(
  phase: phase,
  gold: 0,
  baseHealth: 100,
  startingBaseHealth: 100,
  waveNumber: 1,
  waveTotal: 8,
  stageId: 'test-stage',
  stageName: 'Test Stage',
  stageLabel: 'Test',
  unlockedTowerTypes: const [],
  stageModifiers: const [],
  selectedCell: null,
  selectedTower: null,
  feedback: null,
  isPaused: isPaused,
  speedMultiplier: 1,
  autoStartEnabled: false,
  autoStartCountdownRemaining: null,
  bossActive: bossActive,
);

Future<void> _captureDebugPrint(
  Future<void> Function(List<String> messages) body,
) async {
  final previousDebugPrint = debugPrint;
  final messages = <String>[];
  debugPrint = (message, {wrapWidth}) {
    if (message != null) {
      messages.add(message);
    }
  };
  try {
    await body(messages);
  } finally {
    debugPrint = previousDebugPrint;
  }
}

class _FakeMusicPlayer implements MusicPlayer {
  _FakeMusicPlayer({
    this.playError,
    this.stopError,
    this.disposeError,
    this.throwPlaySynchronously = false,
  });

  final calls = <String>[];
  final Completer<void> playStarted = Completer<void>();
  Completer<void>? playGate;
  final Object? playError;
  Object? stopError;
  final Object? disposeError;
  final bool throwPlaySynchronously;

  @override
  Future<void> play(String filename) {
    calls.add('play:$filename');
    if (!playStarted.isCompleted) {
      playStarted.complete();
    }
    if (playError != null) {
      if (throwPlaySynchronously) {
        throw playError!;
      }
      return Future<void>.error(playError!);
    }
    return playGate?.future ?? Future<void>.value();
  }

  @override
  Future<void> stop() {
    calls.add('stop');
    if (stopError != null) {
      return Future<void>.error(stopError!);
    }
    return Future<void>.value();
  }

  @override
  Future<void> dispose() {
    calls.add('dispose');
    if (disposeError != null) {
      return Future<void>.error(disposeError!);
    }
    return Future<void>.value();
  }
}

class _RecordingAudioCache extends AudioCache {
  _RecordingAudioCache({required super.prefix});

  final assetKeys = <String>[];

  @override
  Future<String> loadPath(String fileName) async {
    final assetKey = '$prefix$fileName';
    assetKeys.add(assetKey);
    return assetKey;
  }
}
