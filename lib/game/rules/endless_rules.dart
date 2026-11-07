import 'dart:math' as math;

import '../models/game_models.dart';

class EndlessRules {
  const EndlessRules._();

  static int loopFor(int waveIndex, int scriptLength) =>
      waveIndex ~/ scriptLength;

  static WaveDefinition waveAt(List<WaveDefinition> script, int waveIndex) =>
      script[waveIndex % script.length];

  static double healthMultiplier(int waveIndex, int scriptLength) => math
      .pow(
        GameBalance.endlessLoopHealthGrowth,
        loopFor(waveIndex, scriptLength),
      )
      .toDouble();
}
