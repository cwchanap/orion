import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  test('TowerType labels are non-empty for every value', () {
    for (final type in TowerType.values) {
      expect(type.label, isNotEmpty);
    }
    expect(TowerType.ionChain.label, 'Ion Chain');
    expect(TowerType.gravityWell.label, 'Gravity Well');
  });

  test('EnemyTrait labels match the canonical adjectives', () {
    expect(EnemyTrait.armored.label, 'Armored');
    expect(EnemyTrait.shielded.label, 'Shielded');
    expect(EnemyTrait.swarm.label, 'Swarm');
    expect(EnemyTrait.regen.label, 'Regen');
    expect(EnemyTrait.heavy.label, 'Heavy');
  });

  test('EnemyArchetype labels match wave-preview text exactly', () {
    expect(EnemyArchetype.basicDrone.label, 'Drones');
    expect(EnemyArchetype.basicEliteDrone.label, 'Elite Drones');
    expect(EnemyArchetype.armoredDrone.label, 'Armored Drones');
    expect(EnemyArchetype.shieldedDrone.label, 'Shielded Drones');
    expect(EnemyArchetype.swarmDrone.label, 'Swarm Drones');
    expect(EnemyArchetype.regenDrone.label, 'Regen Drones');
    expect(EnemyArchetype.heavyDrone.label, 'Heavy Drones');
    expect(EnemyArchetype.armoredHeavyDrone.label, 'Armored Heavy Drones');
    expect(EnemyArchetype.regenHeavyDrone.label, 'Regen Heavy Drones');
  });
}
