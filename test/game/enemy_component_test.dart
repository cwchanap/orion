import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/components/enemy_component.dart';
import 'package:orion/game/components/enemy_overlay.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/enemy_logic.dart';
import 'package:orion/game/rules/enemy_overlay_state.dart';

void main() {
  group('EnemyComponent', () {
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
          logic: EnemyLogic(
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
            waypoints: const [Offset(0, 0), Offset(1000, 0)],
          ),
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
      const stats = EnemyStats(
        health: 100,
        speed: 10,
        baseDamage: 1,
        goldReward: 1,
      );
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: stats,
        logic: EnemyLogic(
          enemyId: 1,
          stats: stats,
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        ),
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

    test('targetCandidate exposes runtime health shield and trait flags', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
          shieldHealth: 40,
          traits: {EnemyTrait.shielded, EnemyTrait.armored},
        ),
        logic: EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
            shieldHealth: 40,
            traits: {EnemyTrait.shielded, EnemyTrait.armored},
          ),
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        ),
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(30);

      final candidate = enemy.targetCandidate;
      expect(candidate.id, 1);
      expect(candidate.isAlive, isTrue);
      expect(candidate.currentHealth, enemy.health);
      expect(candidate.currentShield, enemy.shield);
      expect(candidate.isShielded, isTrue);
      expect(candidate.isArmored, isTrue);
      expect(candidate.effectiveHealth, enemy.health + enemy.shield);
    });

    test('targetCandidate reports no traits for plain enemies', () {
      final enemy = EnemyComponent(
        enemyId: 2,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        logic: EnemyLogic(
          enemyId: 2,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        ),
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      final candidate = enemy.targetCandidate;
      expect(candidate.currentHealth, 100);
      expect(candidate.currentShield, 0);
      expect(candidate.isShielded, isFalse);
      expect(candidate.isArmored, isFalse);
    });

    test('overlay state is cached until a mutation marks it dirty', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        logic: EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        ),
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.applyDamage(20);
      final first = enemy.overlayState;
      expect(identical(enemy.overlayState, first), isTrue);

      enemy.applyDamage(10);
      final afterMutation = enemy.overlayState;
      expect(identical(afterMutation, first), isFalse);
      expect(afterMutation.healthRatio, closeTo(0.7, 0.001));
      expect(identical(enemy.overlayState, afterMutation), isTrue);
    });

    test('residualWaypointsFromHere starts at current position', () {
      final boss = EnemyComponent(
        enemyId: 1,
        stats: GameBalance.relayBreaker,
        logic: EnemyLogic(
          enemyId: 1,
          stats: GameBalance.relayBreaker,
          waypoints: const [Offset(0, 0), Offset(10000, 0), Offset(10000, 10)],
        ),
        onKilled: (_) {},
        onReachedBase: (_) {},
      );
      boss.logic.tick(1.0); // moves ~46 units along x, clamped to path
      boss.syncRender();
      final residual = boss.residualWaypointsFromHere();
      expect(residual.first, equals(boss.position));
      expect(residual.length, greaterThanOrEqualTo(2));
    });

    test('initialCompletedDistance seeds pathProgress', () {
      final boss = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 10,
          speed: 0,
          baseDamage: 1,
          goldReward: 1,
        ),
        logic: EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 10,
            speed: 0,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: const [Offset(0, 0), Offset(100, 0)],
          initialCompletedDistance: 50,
        ),
        onKilled: (_) {},
        onReachedBase: (_) {},
      );
      expect(boss.pathProgress, closeTo(50, 0.001));
    });

    test(
      'applyDamage lethal fires onKilled exactly once via the new guard',
      () {
        var killed = 0;
        const stats = EnemyStats(
          health: 10,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        );
        final logic = EnemyLogic(
          enemyId: 1,
          stats: stats,
          waypoints: const [Offset(0, 0), Offset(1000, 0)],
        );
        final enemy = EnemyComponent(
          enemyId: 1,
          stats: stats,
          logic: logic,
          onKilled: (_) => killed += 1,
          onReachedBase: (_) {},
        );
        enemy.applyDamage(10);
        expect(killed, 1);
        expect(logic.isResolved, isTrue);
        // A second lethal hit must not re-fire (guard holds even with logic
        // already resolved).
        enemy.applyDamage(10);
        expect(killed, 1);
      },
    );

    test('syncRender derives position from logic.position', () {
      final enemy = EnemyComponent(
        enemyId: 1,
        stats: const EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        ),
        logic: EnemyLogic(
          enemyId: 1,
          stats: const EnemyStats(
            health: 100,
            speed: 10,
            baseDamage: 1,
            goldReward: 1,
          ),
          waypoints: const [Offset(0, 0), Offset(100, 0)],
        ),
        onKilled: (_) {},
        onReachedBase: (_) {},
      );

      enemy.logic.tick(1); // moves 10 units along x
      expect(enemy.position.x, 0); // not yet synced
      enemy.syncRender();
      expect(enemy.position.x, closeTo(10, 0.001));
      expect(enemy.position.y, 0);
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

      test('copyWith preserves fields not explicitly provided', () {
        final original = EnemyOverlayData(
          isResolved: false,
          isInspected: true,
          health: 50,
          maxHealth: 100,
          shield: 10,
          maxShield: 40,
          traits: {EnemyTrait.armored},
          isSlowed: true,
          isCorroded: false,
        );

        final copy = original.copyWith(health: 75);

        expect(copy.isInspected, isTrue);
        expect(copy.isResolved, isFalse);
        expect(copy.health, 75);
        expect(copy.maxHealth, 100);
        expect(copy.shield, 10);
        expect(copy.maxShield, 40);
        expect(copy.traits, {EnemyTrait.armored});
        expect(copy.isSlowed, isTrue);
        expect(copy.isCorroded, isFalse);
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

      test('boss overlay always shows health bar at full health', () {
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isInspected: false,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: const {},
            isSlowed: false,
            isCorroded: false,
            isBoss: true,
          ),
        );
        expect(state.shouldRender, isTrue);
        expect(state.showHealthBar, isTrue);
      });

      test(
        'non-boss overlay renders nothing at full health with no traits',
        () {
          final state = EnemyOverlayState.fromData(
            EnemyOverlayData(
              isResolved: false,
              isInspected: false,
              health: 100,
              maxHealth: 100,
              shield: 0,
              maxShield: 0,
              traits: const {},
              isSlowed: false,
              isCorroded: false,
            ),
          );
          expect(state.shouldRender, isFalse);
        },
      );
    });

    group('EnemyOverlayRenderer', () {
      test('overlay layout height scales linearly with enemy radius', () {
        final state = EnemyOverlayState(
          shouldRender: true,
          isExpanded: false,
          healthRatio: 0.5,
          shieldRatio: 0.25,
          showHealthBar: true,
          showShieldBar: true,
          badges: [EnemyOverlayBadge.corroded, EnemyOverlayBadge.slowed],
        );

        final small = EnemyOverlayLayout.compute(state, 10);
        final large = EnemyOverlayLayout.compute(state, 20);

        expect(small.height, greaterThan(0));
        expect(large.height, greaterThan(small.height));
        expect(large.height / small.height, closeTo(2, 0.001));
      });

      test('overlay layout reports zero height when not rendering', () {
        final state = EnemyOverlayState(
          shouldRender: false,
          isExpanded: false,
          healthRatio: 0.5,
          shieldRatio: 0.25,
          showHealthBar: true,
          showShieldBar: true,
          badges: [EnemyOverlayBadge.corroded],
        );

        final layout = EnemyOverlayLayout.compute(state, 20);

        expect(layout.height, 0);
        expect(layout.badgesY, isNull);
        expect(layout.healthBarY, isNull);
        expect(layout.shieldBarY, isNull);
      });

      test('overlay layout omits skipped elements', () {
        final state = EnemyOverlayState(
          shouldRender: true,
          isExpanded: true,
          healthRatio: 0.5,
          shieldRatio: 0,
          showHealthBar: true,
          showShieldBar: false,
          badges: [],
        );

        final layout = EnemyOverlayLayout.compute(state, 20);

        expect(layout.badgesY, isNull);
        expect(layout.healthBarY, isNotNull);
        expect(layout.shieldBarY, isNull);
        expect(layout.height, closeTo(layout.healthBarHeight, 0.001));
      });

      test(
        'render with tower variety sheet uses sprites for indicator badges',
        () async {
          final sheet = GameTowerVarietySheet.fromImage(
            await _blankImage(1024, 1024),
          );
          final state = EnemyOverlayState(
            shouldRender: true,
            isExpanded: true,
            healthRatio: 0.5,
            shieldRatio: 0.25,
            showHealthBar: true,
            showShieldBar: true,
            badges: [
              EnemyOverlayBadge.shielded,
              EnemyOverlayBadge.armored,
              EnemyOverlayBadge.regen,
              EnemyOverlayBadge.corroded,
              EnemyOverlayBadge.slowed,
              EnemyOverlayBadge.heavy,
              EnemyOverlayBadge.swarm,
            ],
          );
          final renderer = EnemyOverlayRenderer();

          expect(
            () => _renderOverlayToCanvas(
              renderer: renderer,
              state: state,
              radius: 20,
              towerVarietySheet: sheet,
            ),
            returnsNormally,
          );
        },
      );

      test(
        'render fallback shapes for all badge types without sheet',
        () async {
          for (final badge in EnemyOverlayBadge.values) {
            final state = EnemyOverlayState(
              shouldRender: true,
              isExpanded: true,
              healthRatio: 0.5,
              shieldRatio: 0.25,
              showHealthBar: true,
              showShieldBar: true,
              badges: [badge],
            );
            final renderer = EnemyOverlayRenderer();

            expect(
              () => _renderOverlayToCanvas(
                renderer: renderer,
                state: state,
                radius: 20,
              ),
              returnsNormally,
            );
          }
        },
      );

      test('EnemyOverlayRenderer.render accepts and draws a boss name', () {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final renderer = EnemyOverlayRenderer();
        final state = EnemyOverlayState.fromData(
          EnemyOverlayData(
            isResolved: false,
            isBoss: true,
            health: 100,
            maxHealth: 100,
            shield: 0,
            maxShield: 0,
            traits: const {},
            isSlowed: false,
            isCorroded: false,
          ),
        );
        // Must not throw; the name is drawn above the layout origin.
        renderer.render(
          canvas,
          state: state,
          radius: 20,
          name: 'Relay Breaker',
        );
        expect(recorder.endRecording(), isNotNull);
      });
    });

    group('EnemyComponent.render', () {
      test(
        'render draws sprite and overlay when sprite sheet is provided',
        () async {
          final spriteSheet = GameSpriteSheet.fromImage(
            await _blankImage(1024, 768),
          );
          final enemy = EnemyComponent(
            enemyId: 1,
            stats: const EnemyStats(
              health: 100,
              speed: 10,
              baseDamage: 1,
              goldReward: 1,
            ),
            logic: EnemyLogic(
              enemyId: 1,
              stats: const EnemyStats(
                health: 100,
                speed: 10,
                baseDamage: 1,
                goldReward: 1,
              ),
              waypoints: const [Offset(0, 0), Offset(1000, 0)],
            ),
            onKilled: (_) {},
            onReachedBase: (_) {},
            spriteSheet: spriteSheet,
          );
          enemy.setInspected(true);

          expect(() => _renderEnemyToCanvas(enemy), returnsNormally);
        },
      );

      test('render draws fallback circle and overlay without sprite sheet', () {
        const stats = EnemyStats(
          health: 100,
          speed: 10,
          baseDamage: 1,
          goldReward: 1,
        );
        final enemy = EnemyComponent(
          enemyId: 1,
          stats: stats,
          logic: EnemyLogic(
            enemyId: 1,
            stats: stats,
            waypoints: const [Offset(0, 0), Offset(1000, 0)],
          ),
          onKilled: (_) {},
          onReachedBase: (_) {},
        );
        enemy.setInspected(true);

        expect(() => _renderEnemyToCanvas(enemy), returnsNormally);
      });

      test(
        'render draws boss sprite and name overlay when boss sheet is provided',
        () async {
          final bossSheet = GameBossSheet.fromImage(
            await _blankImage(400, 200),
          );
          final enemy = EnemyComponent(
            enemyId: 1,
            stats: GameBalance.relayBreaker,
            logic: EnemyLogic(
              enemyId: 1,
              stats: GameBalance.relayBreaker,
              waypoints: const [Offset(0, 0), Offset(1000, 0)],
            ),
            onKilled: (_) {},
            onReachedBase: (_) {},
            bossSheet: bossSheet,
            radius: 20,
          );
          enemy.setInspected(true);

          expect(() => _renderEnemyToCanvas(enemy), returnsNormally);
        },
      );

      test(
        'render falls back to sprite sheet when boss stats lack a boss sheet',
        () async {
          final spriteSheet = GameSpriteSheet.fromImage(
            await _blankImage(1024, 768),
          );
          final enemy = EnemyComponent(
            enemyId: 1,
            stats: GameBalance.relayBreaker,
            logic: EnemyLogic(
              enemyId: 1,
              stats: GameBalance.relayBreaker,
              waypoints: const [Offset(0, 0), Offset(1000, 0)],
            ),
            onKilled: (_) {},
            onReachedBase: (_) {},
            spriteSheet: spriteSheet,
          );
          enemy.setInspected(true);

          expect(() => _renderEnemyToCanvas(enemy), returnsNormally);
        },
      );
    });
  });
}

Future<ui.Image> _blankImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void _renderOverlayToCanvas({
  required EnemyOverlayRenderer renderer,
  required EnemyOverlayState state,
  required double radius,
  GameTowerVarietySheet? towerVarietySheet,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(60, 80);
  renderer.render(
    canvas,
    state: state,
    radius: radius,
    towerVarietySheet: towerVarietySheet,
  );
  recorder.endRecording().dispose();
}

void _renderEnemyToCanvas(EnemyComponent enemy) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(60, 80);
  enemy.render(canvas);
  recorder.endRecording().dispose();
}
