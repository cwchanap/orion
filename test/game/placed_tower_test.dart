import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('TowerTargetingMode', () {
    test('exposes human-readable labels', () {
      expect(TowerTargetingMode.first.label, 'First');
      expect(TowerTargetingMode.strongest.label, 'Strongest');
      expect(TowerTargetingMode.weakest.label, 'Weakest');
      expect(TowerTargetingMode.closest.label, 'Closest');
      expect(TowerTargetingMode.shielded.label, 'Shielded');
      expect(TowerTargetingMode.armored.label, 'Armored');
    });
  });

  group('PlacedTower targeting mode', () {
    test('defaults to First', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      );
      expect(tower.targetingMode, TowerTargetingMode.first);
    });

    test('copyWith changes only the targeting mode', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
      );
      final retargeted = tower.copyWith(
        targetingMode: TowerTargetingMode.strongest,
      );
      expect(retargeted.targetingMode, TowerTargetingMode.strongest);
      expect(retargeted.id, 1);
      expect(retargeted.type, TowerType.laser);
      expect(retargeted.position, const GridPosition(0, 0));
      expect(retargeted.level, 1);
    });

    test('upgraded preserves the targeting mode', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        targetingMode: TowerTargetingMode.weakest,
      );
      expect(tower.upgraded().targetingMode, TowerTargetingMode.weakest);
    });

    test('specialized preserves the targeting mode', () {
      const tower = PlacedTower(
        id: 1,
        type: TowerType.laser,
        position: GridPosition(0, 0),
        level: 2,
        targetingMode: TowerTargetingMode.closest,
      );
      final specialized = tower.specialized(TowerSpecialization.pulseLaser);
      expect(specialized.targetingMode, TowerTargetingMode.closest);
      expect(specialized.level, 3);
      expect(specialized.specialization, TowerSpecialization.pulseLaser);
    });
  });
}
