import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:orion/game/feedback/combat_sound_limiter.dart';
import 'package:orion/game/models/game_models.dart';

abstract interface class GameFeedback {
  void towerConfirmed();
  void waveCleared();
  void moduleSelected();
  void towerFired(TowerType type);
  void splashImpact();
  void chainImpact();
  void pierceImpact();
  void enemyDestroyed();
  void coreHit();
  void waveStarted();
  void bossArrived();
  void bossDefeated();
  void towerSold();
  void missionVictory();
  void baseDefeated();
}

final class NoOpGameFeedback implements GameFeedback {
  const NoOpGameFeedback();

  @override
  void towerConfirmed() {}
  @override
  void waveCleared() {}
  @override
  void moduleSelected() {}
  @override
  void towerFired(TowerType type) {}
  @override
  void splashImpact() {}
  @override
  void chainImpact() {}
  @override
  void pierceImpact() {}
  @override
  void enemyDestroyed() {}
  @override
  void coreHit() {}
  @override
  void waveStarted() {}
  @override
  void bossArrived() {}
  @override
  void bossDefeated() {}
  @override
  void towerSold() {}
  @override
  void missionVictory() {}
  @override
  void baseDefeated() {}
}

final class PlatformGameFeedback implements GameFeedback {
  PlatformGameFeedback({
    required this.soundEffectsEnabled,
    required this.hapticsEnabled,
    Future<void> Function(String file)? startCombatSound,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? _defaultNowMs {
    _startCombatSound = startCombatSound;
    // Best-effort cache warm-up at construction time, so the first semantic
    // cue does not pay the uncached first-play latency. The design explicitly
    // specifies this fires when the service is constructed, not lazily on the
    // first emit (which would defeat the warm-up for the very cue it is meant
    // to help). Errors are swallowed by _warmAudioCache.
    unawaited(_warmAudioCache());
    // Production: eagerly initialize the 13 high-frequency AudioPools once,
    // asynchronously and best-effort. An injected starter (tests) replaces
    // pool creation and readiness entirely.
    if (_startCombatSound == null) {
      unawaited(_initPools());
    }
  }

  /// The four pre-existing stingers, the only files the constructor-time
  /// loadAll warm-up loads (Ruling B: the warm-up list stays exactly these
  /// four). The 13 high-frequency combat clips are warmed by their
  /// eagerly-created AudioPools instead; the four rare transition cues play
  /// uncached as one-shots, like these stingers once did.
  static const sounds = [
    'confirm.wav',
    'clear.wav',
    'victory.wav',
    'defeat.wav',
  ];

  /// Per-pool player reuse budget. Pool size is NOT the global admission
  /// cap — [CombatSoundLimiter] owns that.
  static const int _playersPerPool = 2;

  static final Stopwatch _processClock = Stopwatch()..start();

  /// Monotonic wall-clock milliseconds, never Flame's speed-scaled dt.
  static int _defaultNowMs() => _processClock.elapsedMilliseconds;

  final bool Function() soundEffectsEnabled;
  final bool Function() hapticsEnabled;

  // ignore: prefer_initializing_formals — the public parameter name is part
  // of the design contract; Dart has no private named initializing formals.
  Future<void> Function(String file)? _startCombatSound;
  final int Function() _nowMs;
  final CombatSoundLimiter _limiter = CombatSoundLimiter();

  /// Ready pools per combat cue. A missing entry means still initializing
  /// or failed: its cues are dropped without consuming admission. Kept as
  /// a field so the page-owned disposal step can release the players.
  final _pools = <CombatSoundCue, AudioPool>{};

  bool _disposed = false;

  /// Idempotent, best-effort cleanup for the owning page's teardown: marks
  /// the service disposed and releases the owned combat pools. Pools that
  /// finish initializing after this call are disposed immediately. Never
  /// clears the shared Flame audio cache; an injected [GameFeedback] must
  /// never have this called (only the page that created this instance
  /// may call it).
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final pools = Map.of(_pools);
    _pools.clear();
    for (final MapEntry(key: cue, value: pool) in pools.entries) {
      unawaited(_disposePool(pool, cue.filename));
    }
  }

  @override
  void towerConfirmed() =>
      _emit(sound: 'confirm.wav', haptic: HapticFeedback.selectionClick);

  @override
  void moduleSelected() =>
      _emit(sound: 'confirm.wav', haptic: HapticFeedback.selectionClick);

  @override
  void waveCleared() =>
      _emit(sound: 'clear.wav', haptic: HapticFeedback.lightImpact);

  // Combat cues: the 13 high-frequency sounds go through limiter admission
  // and a pooled start; admission order is enabled → ready → limiter → start.
  @override
  void towerFired(TowerType type) =>
      _playCombat(CombatSoundCue.fireCueFor(type));

  @override
  void splashImpact() => _playCombat(CombatSoundCue.splashImpact);

  @override
  void chainImpact() => _playCombat(CombatSoundCue.chainImpact);

  @override
  void pierceImpact() => _playCombat(CombatSoundCue.pierceImpact);

  @override
  void enemyDestroyed() => _playCombat(CombatSoundCue.enemyDestroyed);

  @override
  void coreHit() => _playCombat(CombatSoundCue.coreHit);

  // Always-audible rare transition cues: FlameAudio.play directly, outside
  // the limiter, so bursts of combat can never suppress them.
  @override
  void waveStarted() => _emit(sound: waveStartedSound);

  @override
  void bossArrived() =>
      _emit(sound: bossArrivalSound, haptic: HapticFeedback.lightImpact);

  @override
  void towerSold() => _emit(sound: towerSoldSound);

  @override
  void bossDefeated() =>
      _emit(sound: bossDefeatedSound, haptic: HapticFeedback.mediumImpact);

  @override
  void missionVictory() =>
      _emit(sound: 'victory.wav', haptic: HapticFeedback.heavyImpact);

  @override
  void baseDefeated() =>
      _emit(sound: 'defeat.wav', haptic: HapticFeedback.heavyImpact);

  /// Eagerly creates the 13 combat AudioPools, one per cue, sequentially
  /// and best-effort: a missing/failed WAV (HPA-385 not merged, corrupted
  /// asset, channel error) leaves that cue's map entry absent so its cues
  /// are silently dropped instead of crashing gameplay. Never awaited by
  /// gameplay.
  Future<void> _initPools() async {
    for (final cue in CombatSoundCue.values) {
      final AudioPool pool;
      try {
        pool = await FlameAudio.createPool(
          cue.filename,
          maxPlayers: _playersPerPool,
        );
      } catch (error) {
        debugPrint(
          'PlatformGameFeedback: failed to init combat pool '
          '"${cue.filename}": $error',
        );
        continue;
      }
      if (_disposed) {
        // The owning page was disposed while this pool was initializing:
        // dispose the late-completed pool immediately.
        unawaited(_disposePool(pool, cue.filename));
        continue;
      }
      _pools[cue] = pool;
    }
  }

  Future<void> _disposePool(AudioPool pool, String file) async {
    try {
      await pool.dispose();
    } catch (error) {
      debugPrint(
        'PlatformGameFeedback: failed to dispose combat pool "$file": $error',
      );
    }
  }

  void _playCombat(CombatSoundCue cue) {
    if (!soundEffectsEnabled()) {
      return;
    }
    final start = _startCombatSound;
    if (start != null) {
      // Test seam: the starter is always "ready", replacing pools entirely.
      if (!_limiter.admit(cue, nowMs: _nowMs())) {
        return;
      }
      unawaited(_startViaCallback(start, cue.filename));
      return;
    }
    // Unready or failed pool: drop without consuming an admission slot.
    final pool = _pools[cue];
    if (pool == null) {
      return;
    }
    if (!_limiter.admit(cue, nowMs: _nowMs())) {
      return;
    }
    // Admitted: the timestamp stays even if the start below fails.
    unawaited(_startPooledSound(pool, cue.filename));
  }

  Future<void> _startViaCallback(
    Future<void> Function(String file) start,
    String file,
  ) async {
    try {
      await start(file);
    } catch (error) {
      debugPrint(
        'PlatformGameFeedback: failed to start combat sound "$file": $error',
      );
    }
  }

  Future<void> _startPooledSound(AudioPool pool, String file) async {
    try {
      await pool.start();
    } catch (error) {
      debugPrint(
        'PlatformGameFeedback: failed to start combat sound "$file": $error',
      );
    }
  }

  void _emit({String? sound, Future<void> Function()? haptic}) {
    if (sound != null && soundEffectsEnabled()) {
      unawaited(_playSound(sound));
    }
    if (haptic != null && hapticsEnabled()) {
      unawaited(_playHaptic(haptic));
    }
  }

  Future<void> _warmAudioCache() async {
    try {
      await FlameAudio.audioCache.loadAll(sounds);
    } catch (error) {
      debugPrint('PlatformGameFeedback: failed to warm audio cache: $error');
    }
  }

  Future<void> _playSound(String sound) async {
    try {
      await FlameAudio.play(sound);
    } catch (error) {
      debugPrint('PlatformGameFeedback: failed to play sound "$sound": $error');
    }
  }

  Future<void> _playHaptic(Future<void> Function() haptic) async {
    try {
      await haptic();
    } catch (error) {
      debugPrint('PlatformGameFeedback: haptic feedback failed: $error');
    }
  }
}
