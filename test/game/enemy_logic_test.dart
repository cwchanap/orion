import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/enemy_logic.dart';

void main() {
  group('EnemyLogic movement', () {
    test(
      'pathProgress includes full completed segments after waypoint crossing',
      () {
        final logic = EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 10,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: [
            const Offset(0, 0),
            const Offset(10, 0),
            const Offset(10, 10),
          ],
        );
        logic.tick(0.6);
        expect(logic.pathProgress, closeTo(6, 0.001));
        logic.tick(0.6);
        expect(logic.position.dx, closeTo(10, 0.001));
        expect(logic.position.dy, closeTo(2, 0.001));
        expect(logic.pathProgress, closeTo(12, 0.001));
      },
    );

    test('reaches base and reports reachedBase when path is exhausted', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 10,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [const Offset(0, 0), const Offset(5, 0)],
      );
      final result = logic.tick(1); // speed 10 * dt 1 = 10 > segment length 5
      expect(result.reachedBase, isTrue);
      expect(logic.isResolved, isTrue);
      expect(logic.position, const Offset(5, 0)); // snapped to waypoints.last
    });

    test('residualWaypointsFromHere starts at current position', () {
      final logic = EnemyLogic(
        enemyId: 1,
        stats: const EnemyStats(
          health: 10,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(10, 10),
        ],
      );
      logic.tick(0.3); // moves 3 units along x
      final residual = logic.residualWaypointsFromHere();
      expect(residual.first, closeToOffset(const Offset(3, 0)));
      expect(residual, hasLength(3)); // current pos + 2 remaining waypoints
    });
  });
}

Matcher closeToOffset(Offset value) => predicate<Offset>(
  (o) => (o.dx - value.dx).abs() < 0.001 && (o.dy - value.dy).abs() < 0.001,
  'is close to $value',
);
