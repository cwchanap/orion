import 'package:flame_audio/flame_audio.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flutter/foundation.dart';
import 'package:orion/game/feedback/game_feedback.dart';
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
  GameMusicController({MusicPlayer? player, int Function()? nowMs})
    : _player = player ?? _BgmMusicPlayer(),
      _nowMs = nowMs ?? _defaultNowMs;

  /// Minimum spacing between automatic retries of a failed play for an
  /// unchanged target. Stop retries are never throttled: delaying an
  /// unwanted playing track is user-facing, while delaying a retry that
  /// merely stays silent costs nothing but log lines. A changed target
  /// always resets the window and attempts immediately.
  @visibleForTesting
  static const int playRetryDelayMs = 5000;

  static final Stopwatch _processClock = Stopwatch()..start();
  static int _defaultNowMs() => _processClock.elapsedMilliseconds;

  final MusicPlayer _player;
  final int Function() _nowMs;
  Future<void> _commands = Future<void>.value();
  Future<void>? _disposeFuture;
  MusicTrack? _desiredTrack;
  MusicTrack? _playingTrack;

  /// A stop attempt may not have landed after a failed play, so the recorded
  /// [_playingTrack] is unconfirmed: an equal desired track is NOT converged
  /// and must re-sync (stop, then play) instead of staying silent.
  bool _stopPending = false;

  /// A sync command is queued or running. Callers only need to update
  /// [_desiredTrack]; the running loop reads the latest target after every
  /// awaited native call, so no further sync is queued.
  bool _syncScheduled = false;

  /// Earliest nowMs at which an unchanged target may retry after a failed
  /// play. Zero means no play attempt has failed.
  int _playRetryNotBeforeMs = 0;

  bool _disposed = false;

  Future<void> set(MusicTrack? track) {
    if (_disposed) {
      return _commands;
    }
    final targetUnchanged = track == _desiredTrack;
    if (targetUnchanged && _playingTrack == _desiredTrack && !_stopPending) {
      return _commands;
    }
    _desiredTrack = track;
    if (!targetUnchanged) {
      _playRetryNotBeforeMs = 0;
    }
    if (_syncScheduled ||
        (targetUnchanged && _nowMs() < _playRetryNotBeforeMs)) {
      return _commands;
    }
    _syncScheduled = true;
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
        await _stopPlayer();
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
    try {
      while (!_disposed) {
        final requested = _desiredTrack;
        if (requested == _playingTrack && !_stopPending) {
          return;
        }

        if (_playingTrack != null) {
          if (!await _stopPlayer()) {
            return;
          }
          _playingTrack = null;
          _stopPending = false;
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
          _playRetryNotBeforeMs = _nowMs() + playRetryDelayMs;
        }
        if (!playSucceeded) {
          final stopped = await _stopPlayer();
          _playingTrack = stopped ? null : requested;
          _stopPending = !stopped;
          if (_desiredTrack != requested && stopped) {
            continue;
          }
          return;
        }
        _playingTrack = requested;
        _stopPending = false;
        if (_disposed || _desiredTrack != requested) {
          if (!await _stopPlayer()) {
            return;
          }
          _playingTrack = null;
          continue;
        }
        return;
      }
    } finally {
      _syncScheduled = false;
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
    try {
      final bgm = _bgm ??= await _createBgm();
      await bgm.play(filename, volume: 0.18);
    } catch (_) {
      // A natively broken player never recovers in place; drop it so the
      // next attempt builds a fresh one instead of erroring until restart.
      await _discard();
      rethrow;
    }
  }

  /// Builds the lazy private player and applies the shared game audio
  /// context to it directly — without `Bgm.initialize()`'s competing
  /// lifecycle observer — so a player created while the global context
  /// setup failed (or under another host) still avoids Android's default
  /// audio focus.
  Future<Bgm> _createBgm() async {
    final bgm = Bgm(audioCache: FlameAudio.audioCache);
    try {
      await bgm.audioPlayer.setAudioContext(gameAudioContext);
    } catch (_) {
      try {
        await bgm.dispose();
      } catch (_) {}
      rethrow;
    }
    return bgm;
  }

  Future<void> _discard() async {
    final bgm = _bgm;
    _bgm = null;
    if (bgm != null) {
      try {
        await bgm.dispose();
      } catch (_) {}
    }
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
