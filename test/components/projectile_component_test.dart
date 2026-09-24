import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/combat_feedback_component.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/projectile_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/enemy_logic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TowerStats makeStats({
    TowerType type = TowerType.rocket,
    double damage = 20,
    double splashRadius = 0,
    int chainCount = 0,
    double chainRange = 0,
    double chainFalloff = 1,
    int pierceCount = 0,
    double pierceWidth = 0,
  }) {
    return TowerStats(
      type: type,
      level: 3,
      specialization: switch (type) {
        TowerType.ionChain => TowerSpecialization.stormRelay,
        TowerType.railgun => TowerSpecialization.lanceRailgun,
        _ => TowerSpecialization.siegeRocket,
      },
      cost: 0,
      upgradeCost: 0,
      specializationCost: 0,
      range: 200,
      damage: damage,
      fireInterval: 1,
      projectileSpeed: 100,
      splashRadius: splashRadius,
      slowMultiplier: 1,
      slowDuration: 0,
      chainCount: chainCount,
      chainRange: chainRange,
      chainFalloff: chainFalloff,
      pierceCount: pierceCount,
      pierceWidth: pierceWidth,
    );
  }

  EnemyComponent makeEnemy({
    required int id,
    required Offset position,
    double health = 100,
  }) {
    final stats = EnemyStats(
      health: health,
      speed: 1,
      baseDamage: 1,
      goldReward: 1,
    );
    final enemy = EnemyComponent(
      enemyId: id,
      stats: stats,
      logic: EnemyLogic(
        enemyId: id,
        stats: stats,
        waypoints: [position, position + const Offset(1000, 0)],
      ),
      onKilled: (_) {},
      onReachedBase: (_) {},
    );
    // ProjectileComponent.update rejects an unmounted target; standalone
    // fixtures have no FlameGame host, so mark them mounted explicitly.
    // ignore: invalid_use_of_internal_member
    enemy.setMounted();
    return enemy;
  }

  group('ProjectileComponent combat feedback', () {
    test(
      'splash resolves damage and emits one cue with resolved positions',
      () {
        final target = makeEnemy(id: 1, position: const Offset(100, 100));
        final near = makeEnemy(id: 2, position: const Offset(120, 100));
        final far = makeEnemy(id: 3, position: const Offset(300, 300));
        final feedbacks = <CombatFeedbackComponent>[];
        final projectile = ProjectileComponent(
          stats: makeStats(splashRadius: 40, damage: 20),
          target: target,
          startPosition: Vector2(0, 100),
          enemiesProvider: () => [target, near, far],
          onCombatFeedback: feedbacks.add,
        );

        projectile.update(2);

        expect(target.health, closeTo(80, 0.001));
        expect(near.health, closeTo(80, 0.001));
        expect(far.health, 100);
        expect(feedbacks, hasLength(1));
        final cue = feedbacks.single;
        expect(cue.kind, CombatFeedbackKind.splash);
        expect(cue.origin, Vector2(100, 100));
        expect(cue.radius, 40);
        expect(cue.positions, [Vector2(100, 100), Vector2(120, 100)]);
        expect(cue.color, projectile.paint.color);
      },
    );

    test('splash with no secondary records only the primary hit', () {
      final target = makeEnemy(id: 1, position: const Offset(100, 100));
      final far = makeEnemy(id: 2, position: const Offset(300, 300));
      final feedbacks = <CombatFeedbackComponent>[];
      final projectile = ProjectileComponent(
        stats: makeStats(splashRadius: 40, damage: 20),
        target: target,
        startPosition: Vector2(0, 100),
        enemiesProvider: () => [target, far],
        onCombatFeedback: feedbacks.add,
      );

      projectile.update(2);

      expect(feedbacks.single.positions, [Vector2(100, 100)]);
      expect(far.health, 100);
    });

    test('chain resolves ordered jumps and emits ordered points', () {
      final target = makeEnemy(id: 1, position: const Offset(100, 100));
      final second = makeEnemy(id: 2, position: const Offset(130, 100));
      final third = makeEnemy(id: 3, position: const Offset(160, 100));
      final feedbacks = <CombatFeedbackComponent>[];
      final projectile = ProjectileComponent(
        stats: makeStats(
          type: TowerType.ionChain,
          damage: 40,
          chainCount: 3,
          chainRange: 60,
          chainFalloff: 0.5,
        ),
        target: target,
        startPosition: Vector2(0, 100),
        enemiesProvider: () => [target, second, third],
        onCombatFeedback: feedbacks.add,
      );

      projectile.update(2);

      expect(target.health, closeTo(60, 0.001));
      expect(second.health, closeTo(80, 0.001));
      expect(third.health, closeTo(90, 0.001));
      final cue = feedbacks.single;
      expect(cue.kind, CombatFeedbackKind.chain);
      expect(cue.origin, Vector2(100, 100));
      expect(cue.radius, 0);
      expect(cue.positions, [
        Vector2(100, 100),
        Vector2(130, 100),
        Vector2(160, 100),
      ]);
    });

    test(
      'pierce resolves line targets and emits origin plus ordered points',
      () {
        final target = makeEnemy(id: 1, position: const Offset(100, 100));
        final beyond = makeEnemy(id: 2, position: const Offset(150, 105));
        final offRay = makeEnemy(id: 3, position: const Offset(110, 140));
        final feedbacks = <CombatFeedbackComponent>[];
        final projectile = ProjectileComponent(
          stats: makeStats(
            type: TowerType.railgun,
            damage: 30,
            pierceCount: 2,
            pierceWidth: 12,
          ),
          target: target,
          startPosition: Vector2(0, 100),
          enemiesProvider: () => [target, beyond, offRay],
          onCombatFeedback: feedbacks.add,
        );

        projectile.update(2);

        expect(target.health, closeTo(70, 0.001));
        expect(beyond.health, closeTo(70, 0.001));
        expect(offRay.health, 100);
        final cue = feedbacks.single;
        expect(cue.kind, CombatFeedbackKind.pierce);
        expect(cue.origin, Vector2(0, 100));
        expect(cue.beamTarget, Vector2(100, 100));
        expect(cue.positions, [Vector2(100, 100), Vector2(150, 105)]);
      },
    );

    test('no feedback is emitted for plain single-target hits', () {
      final target = makeEnemy(id: 1, position: const Offset(100, 100));
      final feedbacks = <CombatFeedbackComponent>[];
      final projectile = ProjectileComponent(
        stats: makeStats(damage: 10),
        target: target,
        startPosition: Vector2(0, 100),
        enemiesProvider: () => [target],
        onCombatFeedback: feedbacks.add,
      );

      projectile.update(2);

      expect(target.health, closeTo(90, 0.001));
      expect(feedbacks, isEmpty);
    });
  });
}
