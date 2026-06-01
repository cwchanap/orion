import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/rules/tower_targeting.dart';

void main() {
  group('TowerTargeting', () {
    test('selects the in-range enemy closest to the base', () {
      const tower = TargetPoint(x: 0, y: 0);
      const candidates = [
        TargetCandidate(id: 1, x: 20, y: 0, pathProgress: 0.2, isAlive: true),
        TargetCandidate(id: 2, x: 70, y: 0, pathProgress: 0.9, isAlive: true),
        TargetCandidate(id: 3, x: 30, y: 0, pathProgress: 0.5, isAlive: true),
      ];

      final target = TowerTargeting.selectTarget(
        tower: tower,
        range: 80,
        candidates: candidates,
      );

      expect(target?.id, 2);
    });

    test('ignores enemies outside range or already dead', () {
      final target = TowerTargeting.selectTarget(
        tower: TargetPoint(x: 0, y: 0),
        range: 40,
        candidates: [
          TargetCandidate(
            id: 1,
            x: 100,
            y: 0,
            pathProgress: 0.9,
            isAlive: true,
          ),
          TargetCandidate(
            id: 2,
            x: 10,
            y: 0,
            pathProgress: 0.8,
            isAlive: false,
          ),
        ],
      );

      expect(target, isNull);
    });
  });
}
