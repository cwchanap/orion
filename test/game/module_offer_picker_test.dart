import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/module_offer_picker.dart';
import 'package:orion/game/rules/run_module_unlocks.dart';

void main() {
  test('catalog covers every RunModuleId exactly once', () {
    final catalogIds = runModuleCatalog
        .map((definition) => definition.id)
        .toList(growable: false);

    expect(catalogIds.toSet(), RunModuleId.values.toSet());
    expect(catalogIds.toSet(), hasLength(catalogIds.length));
    expect(catalogIds.toSet().difference(RunModuleUnlocks.baseModules), {
      RunModuleId.relayCalibration,
    });

    final relay = runModuleDefinition(RunModuleId.relayCalibration);
    expect(relay.rangeMultiplier, 1.08);
    expect(relay.fireIntervalMultiplier, 0.92);
  });

  test('picker returns distinct cards without mutating candidates', () {
    final picker = RandomModuleOfferPicker(math.Random(7));
    final candidates = RunModuleId.values.toList();
    final before = List<RunModuleId>.of(candidates);

    final result = picker.pick(candidates, count: 3);

    expect(result, hasLength(3));
    expect(result.toSet(), hasLength(3));
    expect(result.every(candidates.contains), isTrue);
    expect(candidates, before);
  });

  test('picker rejects direct misuse with too few candidates', () {
    final picker = RandomModuleOfferPicker(math.Random(3));
    expect(
      () => picker.pick(const [
        RunModuleId.heavyCaliber,
        RunModuleId.longSight,
      ], count: 3),
      throwsStateError,
    );
  });
}
