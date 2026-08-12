import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class GameFeedback {
  void towerConfirmed();
  void waveCleared();
  void moduleSelected();
  void bossDefeated();
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
  void bossDefeated() {}
  @override
  void missionVictory() {}
  @override
  void baseDefeated() {}
}

final class PlatformGameFeedback implements GameFeedback {
  PlatformGameFeedback({
    required this.soundEffectsEnabled,
    required this.hapticsEnabled,
  });

  static const sounds = [
    'confirm.wav',
    'clear.wav',
    'victory.wav',
    'defeat.wav',
  ];

  final bool Function() soundEffectsEnabled;
  final bool Function() hapticsEnabled;

  bool _audioCacheWarmed = false;

  @override
  void towerConfirmed() =>
      _emit(sound: 'confirm.wav', haptic: HapticFeedback.selectionClick);

  @override
  void moduleSelected() =>
      _emit(sound: 'confirm.wav', haptic: HapticFeedback.selectionClick);

  @override
  void waveCleared() =>
      _emit(sound: 'clear.wav', haptic: HapticFeedback.lightImpact);

  @override
  void bossDefeated() => _emit(haptic: HapticFeedback.mediumImpact);

  @override
  void missionVictory() =>
      _emit(sound: 'victory.wav', haptic: HapticFeedback.heavyImpact);

  @override
  void baseDefeated() =>
      _emit(sound: 'defeat.wav', haptic: HapticFeedback.heavyImpact);

  void _emit({String? sound, Future<void> Function()? haptic}) {
    if (sound != null && soundEffectsEnabled()) {
      if (!_audioCacheWarmed) {
        _audioCacheWarmed = true;
        unawaited(_warmAudioCache());
      }
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
