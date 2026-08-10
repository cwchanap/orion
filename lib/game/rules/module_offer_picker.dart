import 'dart:math' as math;

import '../models/game_models.dart';

abstract interface class ModuleOfferPicker {
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count});
}

final class RandomModuleOfferPicker implements ModuleOfferPicker {
  RandomModuleOfferPicker([math.Random? random])
    : _random = random ?? math.Random();

  final math.Random _random;

  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    if (count < 0 || candidates.length < count) {
      throw StateError('Not enough eligible Salvage Modules.');
    }
    final shuffled = List<RunModuleId>.of(candidates)..shuffle(_random);
    return List.unmodifiable(shuffled.take(count));
  }
}
