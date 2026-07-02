import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/enemy_overlay.dart';
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

    test('shield absorbs damage before health in runtime component', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 50,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          shieldHealth: 20,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(15);

      expect(enemy.health, 50);
      expect(enemy.shield, 5);
      expect(enemy.isAlive, isTrue);
    });

    test('regen restores health while corrosion pauses regen', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(30);
      enemy.update(1);
      expect(enemy.health, 80);

      enemy.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);
      enemy.update(1);

      expect(enemy.health, 75);
      expect(enemy.isCorroded, isTrue);
    });

    test('slow applies to movement through its expiry tick', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [Vector2(0, 0), Vector2(100, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applySlow(multiplier: 0.5, duration: 1);
      enemy.update(1);

      expect(enemy.position.x, closeTo(5, 0.001));
      expect(enemy.isSlowed, isFalse);
    });

    test('regen stays paused during corrosion expiry tick', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.regen},
          regenPerSecond: 10,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(30);
      enemy.applyCorrosion(damagePerSecond: 5, duration: 1, armorShred: 0.1);
      enemy.update(1);

      expect(enemy.health, 65);
      expect(enemy.isCorroded, isFalse);

      enemy.update(1);
      expect(enemy.health, 75);
    });

    test('armor reduces health damage and corrosion damage bypasses armor', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          traits: {EnemyTrait.armored},
          armorReduction: 0.50,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(20);
      expect(enemy.health, 90);

      enemy.applyCorrosion(damagePerSecond: 10, duration: 1, armorShred: 0.2);
      enemy.update(1);

      expect(enemy.health, 80);
    });

    test(
      'component overlay state reflects runtime health shield and effects',
      () {
        final enemy = EnemyComponent(
          enemyId: 1,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
            shieldHealth: 40,
            traits: {EnemyTrait.shielded, EnemyTrait.regen},
            regenPerSecond: 10,
          ),
          waypoints: [Vector2(0, 0), Vector2(1000, 0)],
          onKilled: (_) {},
          onReachedBase: (_) {},
        );

        enemy.applyDamage(30);
        enemy.applySlow(multiplier: 0.5, duration: 2);
        enemy.applyCorrosion(damagePerSecond: 5, duration: 2, armorShred: 0.1);

        final state = enemy.overlayState;

        expect(state.shouldRender, isTrue);
        expect(state.healthRatio, 1);
        expect(state.shieldRatio, 0.25);
        expect(state.showHealthBar, isTrue);
        expect(state.showShieldBar, isTrue);
        expect(state.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.slowed,
        ]);
      },
    );

    test('component inspection expands the overlay state', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        waypoints: [Vector2(0, 0), Vector2(1000, 0)],
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      expect(enemy.isInspected, isFalse);
      expect(enemy.overlayState.shouldRender, isFalse);

      enemy.setInspected(true);

      expect(enemy.isInspected, isTrue);
      expect(enemy.overlayState.shouldRender, isTrue);
      expect(enemy.overlayState.isExpanded, isTrue);
      expect(enemy.overlayState.showHealthBar, isTrue);
    });

    group('EnemyOverlayState', () {
      test('overlay data defensively copies traits', () {
        final traits = {EnemyTrait.armored};
        final data = EnemyOverlayData(
          isResolved: false,
          health: 100,
          maxHealth: 100,
          shield: 0,
          maxShield: 0,
          traits: traits,
          isSlowed: false,
          isCorroded: false,
        );

        traits.add(EnemyTrait.regen);

        expect(data.traits, {EnemyTrait.armored});
        expect(
          () => data.traits.add(EnemyTrait.shielded),
          throwsUnsupportedError,
        );
      });

      test('overlay state defensively copies badges', () {
        final badges = [EnemyOverlayBadge.armored];
        final state = EnemyOverlayState(
          shouldRender: true,
          isExpanded: true,
          healthRatio: 1,
          shieldRatio: 0,
          showHealthBar: true,
          showShieldBar: false,
          badges: badges,
        );

        badges.add(EnemyOverlayBadge.regen);

        expect(state.badges, [EnemyOverlayBadge.armored]);
        expect(
          () => state.badges.add(EnemyOverlayBadge.shielded),
          throwsUnsupportedError,
        );
      });

      test('full-health traitless enemies do not render normal overlays', () {
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(state.shouldRender, isFalse);
        expect(state.showHealthBar, isFalse);
        expect(state.showShieldBar, isFalse);
        expect(state.badges, isEmpty);
      });

      test('damaged enemies expose clamped health ratio', () {
        final damaged = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 25,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );
        final overhealed = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 125,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(damaged.shouldRender, isTrue);
        expect(damaged.healthRatio, 0.25);
        expect(damaged.showHealthBar, isTrue);
        expect(overhealed.healthRatio, 1);
      });

      test('shielded enemies expose shield state separately from health', () {
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 10,
            maxShield: 40,
            traits: {EnemyTrait.shielded},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(state.shouldRender, isTrue);
        expect(state.healthRatio, 1);
        expect(state.shieldRatio, 0.25);
        expect(state.showHealthBar, isTrue);
        expect(state.showShieldBar, isTrue);
        expect(state.badges, [EnemyOverlayBadge.shielded]);
      });

      test('resolved enemies suppress overlays even when inspected', () {
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: true,
            isInspected: true,
            health: 25,
            maxHealth: 100,
            shield: 10,
            maxShield: 40,
            traits: {EnemyTrait.armored, EnemyTrait.regen},
            isSlowed: true,
            isCorroded: true,
          ),
        );

        expect(state.shouldRender, isFalse);
        expect(state.isExpanded, isFalse);
        expect(state.showHealthBar, isFalse);
        expect(state.showShieldBar, isFalse);
        expect(state.badges, isEmpty);
      });

      test('inspected enemies expand even when not otherwise notable', () {
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: true,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(state.shouldRender, isTrue);
        expect(state.isExpanded, isTrue);
        expect(state.showHealthBar, isTrue);
        expect(state.showShieldBar, isFalse);
      });

      test('badges are ordered and capped by overlay mode', () {
        final data = EnemyOverlayData(
          isResolved: false,
          health: 50,
          maxHealth: 100,
          shield: 10,
          maxShield: 40,
          traits: {
            EnemyTrait.shielded,
            EnemyTrait.armored,
            EnemyTrait.regen,
            EnemyTrait.heavy,
            EnemyTrait.swarm,
          },
          isSlowed: true,
          isCorroded: true,
        );

        final normal = EnemyOverlayState.fromData(
          data.copyWith(isInspected: false),
        );
        final expanded = EnemyOverlayState.fromData(
          data.copyWith(isInspected: true),
        );

        expect(normal.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.slowed,
        ]);
        expect(expanded.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.slowed,
          EnemyOverlayBadge.shielded,
          EnemyOverlayBadge.armored,
        ]);
      });

      test('corroded regen enemies keep both badges in priority order', () {
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: true,
            health: 80,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {EnemyTrait.regen},
            isSlowed: false,
            isCorroded: true,
          ),
        );

        expect(state.badges, [
          EnemyOverlayBadge.corroded,
          EnemyOverlayBadge.regen,
        ]);
      });

      test('swarm-only enemies are not automatically notable', () {
        final normal = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {EnemyTrait.swarm},
            isSlowed: false,
            isCorroded: false,
          ),
        );
        final inspected = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: true,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: {EnemyTrait.swarm},
            isSlowed: false,
            isCorroded: false,
          ),
        );

        expect(normal.shouldRender, isFalse);
        expect(normal.badges, isEmpty);
        expect(inspected.shouldRender, isTrue);
        expect(inspected.badges, [EnemyOverlayBadge.swarm]);
      });
    });

    group('EnemyOverlayRenderer', () {
      test('overlay dimensions scale with enemy radius', () async {
        final state = EnemyOverlayState(
          shouldRender: true,
          isExpanded: false,
          healthRatio: 0.5,
          shieldRatio: 0.25,
          showHealthBar: true,
          showShieldBar: true,
          badges: [EnemyOverlayBadge.corroded, EnemyOverlayBadge.slowed],
        );
        final renderer = EnemyOverlayRenderer();

        final smallHeight = await _renderedOverlayHeight(
          renderer: renderer,
          state: state,
          radius: 10,
        );
        final largeHeight = await _renderedOverlayHeight(
          renderer: renderer,
          state: state,
          radius: 20,
        );

        expect(largeHeight / smallHeight, closeTo(2, 0.25));
      });
    });
  });
}

Future<int> _renderedOverlayHeight({
  required EnemyOverlayRenderer renderer,
  required EnemyOverlayState state,
  required double radius,
}) async {
  const imageSize = 120;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(40, 60);

  renderer.render(canvas, state: state, radius: radius);

  final picture = recorder.endRecording();
  final image = await picture.toImage(imageSize, imageSize);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();

  final data = bytes!;
  var minY = imageSize;
  var maxY = -1;

  for (var y = 0; y < imageSize; y += 1) {
    for (var x = 0; x < imageSize; x += 1) {
      final alpha = data.getUint8(((y * imageSize) + x) * 4 + 3);
      if (alpha == 0) {
        continue;
      }
      if (y < minY) {
        minY = y;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
  }

  return maxY - minY + 1;
}
