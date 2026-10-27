import 'package:flame_audio/flame_audio.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flutter/foundation.dart';
import 'package:orion/game/models/game_models.dart';

enum MusicTrack {
  map('music_map.wav'),
  build('music_build.wav'),
  wave('music_wave.wav'),
  boss('music_boss.wav');

  const MusicTrack(this.filename);

  final String filename;
}

MusicTrack? desiredMusicTrack({
  required bool prefsLoaded,
  required bool musicOn,
  required bool appForeground,
  GameSnapshot? stage,
}) {
  if (!prefsLoaded ||
      !musicOn ||
      !appForeground ||
      stage?.isPaused == true ||
      stage?.isEnded == true) {
    return null;
  }
  if (stage == null) {
    return MusicTrack.map;
  }
  if (stage.phase == GamePhase.build) {
    return MusicTrack.build;
  }
  return stage.bossActive ? MusicTrack.boss : MusicTrack.wave;
}

abstract interface class MusicPlayer {
  Future<void> play(String filename);
  Future<void> stop();
  Future<void> dispose();
}

final class GameMusicController {
  GameMusicController({MusicPlayer? player})
    : _player = player ?? _BgmMusicPlayer();

  final MusicPlayer _player;
  Future<void> _commands = Future<void>.value();
  Future<void>? _disposeFuture;
  MusicTrack? _desiredTrack;
  MusicTrack? _playingTrack;
  bool _disposed = false;

  Future<void> set(MusicTrack? track) {
    if (_disposed ||
        (track == _desiredTrack && _playingTrack == _desiredTrack)) {
      return _commands;
    }
    _desiredTrack = track;
    final command = _commands.then((_) => _syncLatest());
    _commands = command.catchError((Object error, StackTrace _) {
      _log('synchronize playback', error);
    });
    return _commands;
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    _desiredTrack = null;
    final command = _commands.then((_) async {
      if (_playingTrack != null) {
        if (await _stopPlayer()) {
          _playingTrack = null;
        }
      }
      try {
        await _player.dispose();
      } catch (error) {
        _log('dispose player', error);
      }
      _playingTrack = null;
    });
    _commands = command.catchError((Object error, StackTrace _) {
      _log('dispose controller', error);
    });
    _disposeFuture = _commands;
    return _disposeFuture!;
  }

  Future<void> _syncLatest() async {
    while (!_disposed) {
      final requested = _desiredTrack;
      if (requested == _playingTrack) {
        return;
      }

      if (_playingTrack != null) {
        if (!await _stopPlayer()) {
          return;
        }
        _playingTrack = null;
        if (_disposed) {
          return;
        }
        continue;
      }

      if (requested == null) {
        return;
      }

      var playSucceeded = false;
      try {
        await _player.play(requested.filename);
        playSucceeded = true;
      } catch (error) {
        _log('play ${requested.filename}', error);
      }
      if (!playSucceeded) {
        final stopped = await _stopPlayer();
        _playingTrack = stopped ? null : requested;
        if (_disposed) {
          return;
        }
        if (_desiredTrack != requested && stopped) {
          continue;
        }
        return;
      }
      _playingTrack = requested;
      if (_disposed || _desiredTrack != requested) {
        if (!await _stopPlayer()) {
          return;
        }
        _playingTrack = null;
        if (_disposed) {
          return;
        }
        continue;
      }
      return;
    }
  }

  Future<bool> _stopPlayer() async {
    try {
      await _player.stop();
      return true;
    } catch (error) {
      _log('stop player', error);
      return false;
    }
  }

  void _log(String action, Object error) {
    debugPrint('GameMusicController: failed to $action: $error');
  }
}

final class _BgmMusicPlayer implements MusicPlayer {
  Bgm? _bgm;

  @override
  Future<void> play(String filename) async {
    final bgm = _bgm ??= Bgm(audioCache: FlameAudio.audioCache);
    await bgm.play(filename, volume: 0.18);
  }

  @override
  Future<void> stop() async {
    final bgm = _bgm;
    if (bgm != null) {
      await bgm.stop();
    }
  }

  @override
  Future<void> dispose() async {
    final bgm = _bgm;
    _bgm = null;
    if (bgm != null) {
      await bgm.dispose();
    }
  }
}
