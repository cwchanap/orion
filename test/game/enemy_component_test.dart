import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('EnemyComponent', () {
    test(
      'pathProgress includes full completed segments after waypoint crossing',
      () {
        final enemy = EnemyComponent(
          enemyId: 1,
          stats: const EnemyStats(
            health: 10,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)],
          onKilled: (_) {},
          onReachedBase: (_) {},
        );

        enemy.update(0.6);
        expect(enemy.pathProgress, closeTo(6, 0.001));

        enemy.update(0.6);
        expect(enemy.position.x, closeTo(10, 0.001));
        expect(enemy.position.y, closeTo(2, 0.001));
        expect(enemy.pathProgress, closeTo(12, 0.001));
      },
    );
  });
}
