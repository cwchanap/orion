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
    expect(RunModuleId.values, hasLength(13));
    expect(catalogIds.toSet().difference(RunModuleUnlocks.baseModules), {
      RunModuleId.relayCalibration,
      RunModuleId.relayArc,
      RunModuleId.salvagedDrones,
      RunModuleId.foundryNanites,
      RunModuleId.auroraFocus,
      RunModuleId.siegeRounds,
      RunModuleId.gravityEcho,
    });

    // Legacy definitions keep their pinned values and families.
    final heavy = runModuleDefinition(RunModuleId.heavyCaliber);
    expect(heavy.damageMultiplier, 1.20);
    expect(heavy.fireIntervalMultiplier, 1.10);
    expect(heavy.tower, isNull);
    final overclock = runModuleDefinition(RunModuleId.overclockRelay);
    expect(overclock.damageMultiplier, 0.92);
    expect(overclock.fireIntervalMultiplier, 0.85);
    expect(overclock.tower, isNull);
    final longSight = runModuleDefinition(RunModuleId.longSight);
    expect(longSight.rangeMultiplier, 1.15);
    expect(longSight.tower, isNull);
    expect(runModuleDefinition(RunModuleId.emergencySalvage).immediateGold, 90);
    expect(runModuleDefinition(RunModuleId.emergencySalvage).tower, isNull);
    final cryo = runModuleDefinition(RunModuleId.cryoReservoir);
    expect(cryo.slowDurationBonus, 0.60);
    expect(cryo.tower, TowerType.cryo);
    final rocket = runModuleDefinition(RunModuleId.rocketFusing);
    expect(rocket.splashRadiusMultiplier, 1.25);
    expect(rocket.damageMultiplier, 0.90);
    expect(rocket.tower, TowerType.rocket);
    final relay = runModuleDefinition(RunModuleId.relayCalibration);
    expect(relay.rangeMultiplier, 1.08);
    expect(relay.fireIntervalMultiplier, 0.92);
    expect(relay.tower, isNull);
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
