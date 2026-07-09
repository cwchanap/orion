import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
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

  group('targeting modes', () {
    // Tower at (0,0). Range is large enough to include everyone.
    //   id1: hp 30,  not shielded/armored, pp 0.2, dist 10  -> eff 30
    //   id2: hp 10,  shielded,             pp 0.9, dist 20  -> eff 10
    //   id3: hp 80 + shield 20, shielded,  pp 0.5, dist 30  -> eff 100
    //   id4: hp 50,  armored,              pp 0.6, dist 40  -> eff 50
    const candidates = <TargetCandidate>[
      TargetCandidate(
        id: 1,
        x: 10,
        y: 0,
        pathProgress: 0.2,
        isAlive: true,
        currentHealth: 30,
      ),
      TargetCandidate(
        id: 2,
        x: 20,
        y: 0,
        pathProgress: 0.9,
        isAlive: true,
        currentHealth: 10,
        isShielded: true,
      ),
      TargetCandidate(
        id: 3,
        x: 30,
        y: 0,
        pathProgress: 0.5,
        isAlive: true,
        currentHealth: 80,
        currentShield: 20,
        isShielded: true,
      ),
      TargetCandidate(
        id: 4,
        x: 40,
        y: 0,
        pathProgress: 0.6,
        isAlive: true,
        currentHealth: 50,
        isArmored: true,
      ),
    ];

    test('effectiveHealth defaults to zero and sums health + shield', () {
      const bare = TargetCandidate(
        id: 0,
        x: 0,
        y: 0,
        pathProgress: 0,
        isAlive: true,
      );
      expect(bare.effectiveHealth, 0);
      const tough = TargetCandidate(
        id: 0,
        x: 0,
        y: 0,
        pathProgress: 0,
        isAlive: true,
        currentHealth: 25,
        currentShield: 15,
      );
      expect(tough.effectiveHealth, 40);
    });

    test('first (default) picks highest path progress', () {
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: candidates,
      );
      expect(target?.id, 2);
    });

    test('strongest picks highest effective health', () {
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: candidates,
        mode: TowerTargetingMode.strongest,
      );
      expect(target?.id, 3); // eff 100
    });

    test('weakest picks lowest effective health', () {
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: candidates,
        mode: TowerTargetingMode.weakest,
      );
      expect(target?.id, 2); // eff 10
    });

    test('closest picks nearest to the tower', () {
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: candidates,
        mode: TowerTargetingMode.closest,
      );
      expect(target?.id, 1); // dist 10
    });

    test('shielded ranks the shielded subset by path progress', () {
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: candidates,
        mode: TowerTargetingMode.shielded,
      );
      expect(target?.id, 2); // shielded {2,3}; highest pp is 2
    });

    test('armored picks from the armored subset', () {
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: candidates,
        mode: TowerTargetingMode.armored,
      );
      expect(target?.id, 4); // only armored candidate
    });

    test('shielded falls back to first when no shielded enemy is in range', () {
      const unshielded = <TargetCandidate>[
        TargetCandidate(id: 1, x: 10, y: 0, pathProgress: 0.2, isAlive: true),
        TargetCandidate(id: 2, x: 20, y: 0, pathProgress: 0.9, isAlive: true),
      ];
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: unshielded,
        mode: TowerTargetingMode.shielded,
      );
      expect(target?.id, 2); // fallback to highest path progress
    });

    test('armored falls back to first when no armored enemy is in range', () {
      const unarmored = <TargetCandidate>[
        TargetCandidate(id: 1, x: 10, y: 0, pathProgress: 0.2, isAlive: true),
        TargetCandidate(id: 2, x: 20, y: 0, pathProgress: 0.9, isAlive: true),
      ];
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: unarmored,
        mode: TowerTargetingMode.armored,
      );
      expect(target?.id, 2); // fallback to highest path progress
    });

    test('strongest tie breaks to higher path progress', () {
      const tied = <TargetCandidate>[
        TargetCandidate(
          id: 1,
          x: 10,
          y: 0,
          pathProgress: 0.3,
          isAlive: true,
          currentHealth: 50,
        ),
        TargetCandidate(
          id: 2,
          x: 20,
          y: 0,
          pathProgress: 0.8,
          isAlive: true,
          currentHealth: 50,
        ),
      ];
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: tied,
        mode: TowerTargetingMode.strongest,
      );
      expect(target?.id, 2);
    });

    test('weakest tie breaks to higher path progress', () {
      const tied = <TargetCandidate>[
        TargetCandidate(
          id: 1,
          x: 10,
          y: 0,
          pathProgress: 0.3,
          isAlive: true,
          currentHealth: 50,
        ),
        TargetCandidate(
          id: 2,
          x: 20,
          y: 0,
          pathProgress: 0.8,
          isAlive: true,
          currentHealth: 50,
        ),
      ];
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: tied,
        mode: TowerTargetingMode.weakest,
      );
      expect(target?.id, 2);
    });

    test('closest tie breaks to higher path progress', () {
      // Both candidates equidistant from the tower (dist² = 100).
      const tied = <TargetCandidate>[
        TargetCandidate(
          id: 1,
          x: 10,
          y: 0,
          pathProgress: 0.3,
          isAlive: true,
        ),
        TargetCandidate(
          id: 2,
          x: 0,
          y: 10,
          pathProgress: 0.8,
          isAlive: true,
        ),
      ];
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: tied,
        mode: TowerTargetingMode.closest,
      );
      expect(target?.id, 2);
    });

    test('first resolves equal path progress by ascending id', () {
      const tied = <TargetCandidate>[
        TargetCandidate(
          id: 3,
          x: 10,
          y: 0,
          pathProgress: 0.5,
          isAlive: true,
        ),
        TargetCandidate(
          id: 1,
          x: 20,
          y: 0,
          pathProgress: 0.5,
          isAlive: true,
        ),
        TargetCandidate(
          id: 2,
          x: 30,
          y: 0,
          pathProgress: 0.5,
          isAlive: true,
        ),
      ];
      final target = TowerTargeting.selectTarget(
        tower: const TargetPoint(x: 0, y: 0),
        range: 999,
        candidates: tied,
      );
      expect(target?.id, 1);
    });
  });
}
