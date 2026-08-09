import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/modules/run_module.dart';
import 'package:orion/game/rules/module_offer_picker.dart';

void main() {
  test('catalog exposes six single-source module definitions', () {
    expect(runModuleCatalog, hasLength(6));
    expect(
      runModuleCatalog.map((definition) => definition.id).toSet(),
      hasLength(6),
    );

    final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
    expect(heavy.damageMultiplier, 1.20);
    expect(heavy.fireIntervalMultiplier, 1.10);
    expect(heavy.effectText, contains('20%'));
    expect(heavy.effectText, contains('10%'));

    final salvage = runModuleDefinition(RunModuleId.emergencySalvage);
    expect(salvage.immediateGold, 90);
    expect(salvage.effectText, contains('90'));
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
