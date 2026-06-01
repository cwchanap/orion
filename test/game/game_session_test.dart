import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';

void main() {
  group('GameSession', () {
    test('starts in build phase with approved economy', () {
      final session = GameSession.initial();

      expect(session.phase, GamePhase.build);
      expect(session.gold, 120);
      expect(session.baseHealth, 20);
      expect(session.waveIndex, 0);
      expect(session.towers, isEmpty);
    });

    test('validates invalid placements without spending gold', () {
      final session = GameSession.initial();

      expect(
        session
            .validatePlacement(const GridPosition(-1, 0), TowerType.laser)
            .failure,
        PlacementFailure.offBoard,
      );
      expect(
        session
            .validatePlacement(const GridPosition(0, 1), TowerType.laser)
            .failure,
        PlacementFailure.pathBlocked,
      );

      session.placeTower(const GridPosition(0, 0), TowerType.laser);
      expect(
        session
            .validatePlacement(const GridPosition(0, 0), TowerType.cryo)
            .failure,
        PlacementFailure.occupied,
      );
      expect(session.gold, 70);
    });

    test('places towers and spends gold', () {
      final session = GameSession.initial();

      final result = session.placeTower(
        const GridPosition(0, 0),
        TowerType.rocket,
      );

      expect(result.isAllowed, isTrue);
      expect(session.gold, 40);
      expect(session.towers.single.type, TowerType.rocket);
      expect(session.towers.single.level, 1);
    });

    test('denies purchase when gold is insufficient', () {
      final session = GameSession.initial(gold: 40);

      final result = session.placeTower(
        const GridPosition(0, 0),
        TowerType.laser,
      );

      expect(result.isAllowed, isFalse);
      expect(result.failure, PlacementFailure.insufficientGold);
      expect(session.gold, 40);
      expect(session.towers, isEmpty);
    });

    test('denies placement during an active wave without spending gold', () {
      final session = GameSession.initial();
      expect(session.startWave(), isTrue);

      final validation = session.validatePlacement(
        const GridPosition(0, 0),
        TowerType.laser,
      );
      final result = session.placeTower(
        const GridPosition(0, 0),
        TowerType.laser,
      );

      expect(validation.isAllowed, isFalse);
      expect(validation.failure, PlacementFailure.invalidPhase);
      expect(result.isAllowed, isFalse);
      expect(result.failure, PlacementFailure.invalidPhase);
      expect(session.gold, 120);
      expect(session.towers, isEmpty);
    });

    test('denies placement after terminal states without spending gold', () {
      final wonSession = GameSession.initial();
      for (var wave = 0; wave < 5; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      final wonResult = wonSession.placeTower(
        const GridPosition(0, 0),
        TowerType.laser,
      );

      expect(wonResult.isAllowed, isFalse);
      expect(wonResult.failure, PlacementFailure.invalidPhase);
      expect(wonSession.gold, 120);
      expect(wonSession.towers, isEmpty);

      final lostSession = GameSession.initial(baseHealth: 1);
      expect(lostSession.startWave(), isTrue);
      lostSession.damageBase(1);

      final lostResult = lostSession.placeTower(
        const GridPosition(0, 0),
        TowerType.laser,
      );

      expect(lostResult.isAllowed, isFalse);
      expect(lostResult.failure, PlacementFailure.invalidPhase);
      expect(lostSession.gold, 120);
      expect(lostSession.towers, isEmpty);
    });

    test('upgrades a tower once and spends gold', () {
      final session = GameSession.initial(gold: 200);
      session.placeTower(const GridPosition(0, 0), TowerType.cryo);
      final tower = session.towers.single;

      final upgraded = session.upgradeTower(tower.id);

      expect(upgraded, isTrue);
      expect(session.towers.single.level, 2);
      expect(session.gold, 40);
      expect(session.upgradeTower(tower.id), isFalse);
    });

    test(
      'denies upgrade during wave without spending gold or changing level',
      () {
        final session = GameSession.initial(gold: 200);
        session.placeTower(const GridPosition(0, 0), TowerType.cryo);
        final tower = session.towers.single;
        expect(session.startWave(), isTrue);

        expect(session.upgradeTower(tower.id), isFalse);
        expect(session.towers.single.level, 1);
        expect(session.gold, 130);
      },
    );

    test(
      'denies upgrade after terminal states without spending gold or level',
      () {
        final wonSession = GameSession.initial(gold: 200);
        wonSession.placeTower(const GridPosition(0, 0), TowerType.cryo);
        final wonTower = wonSession.towers.single;
        for (var wave = 0; wave < 5; wave += 1) {
          expect(wonSession.startWave(), isTrue);
          wonSession.finishActiveWave();
        }

        expect(wonSession.upgradeTower(wonTower.id), isFalse);
        expect(wonSession.towers.single.level, 1);
        expect(wonSession.gold, 130);

        final lostSession = GameSession.initial(gold: 200, baseHealth: 1);
        lostSession.placeTower(const GridPosition(0, 0), TowerType.cryo);
        final lostTower = lostSession.towers.single;
        expect(lostSession.startWave(), isTrue);
        lostSession.damageBase(1);

        expect(lostSession.upgradeTower(lostTower.id), isFalse);
        expect(lostSession.towers.single.level, 1);
        expect(lostSession.gold, 130);
      },
    );

    test('insufficient upgrade gold preserves tower level and gold', () {
      final session = GameSession.initial(gold: 100);
      session.placeTower(const GridPosition(0, 0), TowerType.cryo);
      final tower = session.towers.single;

      expect(session.upgradeTower(tower.id), isFalse);
      expect(session.towers.single.level, 1);
      expect(session.gold, 30);
    });

    test('starts waves only from build phase', () {
      final session = GameSession.initial();

      expect(session.startWave(), isTrue);
      expect(session.phase, GamePhase.wave);
      expect(session.startWave(), isFalse);
    });

    test('progresses through five waves and wins after the final clear', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < 5; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      expect(session.phase, GamePhase.won);
      expect(session.waveIndex, 5);
    });

    test('startWave remains false after won', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < 5; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      expect(session.phase, GamePhase.won);
      expect(session.startWave(), isFalse);
    });

    test('rewardKill mutates gold only during wave for positive rewards', () {
      final session = GameSession.initial();

      session.rewardKill(8);
      expect(session.gold, 120);

      expect(session.startWave(), isTrue);
      session.rewardKill(8);
      session.rewardKill(0);
      session.rewardKill(-4);
      expect(session.gold, 128);

      session.damageBase(20);
      expect(session.phase, GamePhase.lost);
      session.rewardKill(8);
      expect(session.gold, 128);

      final wonSession = GameSession.initial();
      for (var wave = 0; wave < 5; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      wonSession.rewardKill(8);
      expect(wonSession.gold, 120);
    });

    test('damageBase mutates health only during wave for positive damage', () {
      final session = GameSession.initial();

      session.damageBase(5);
      expect(session.baseHealth, 20);

      expect(session.startWave(), isTrue);
      session.damageBase(5);
      session.damageBase(0);
      session.damageBase(-4);
      expect(session.baseHealth, 15);

      session.damageBase(20);
      expect(session.baseHealth, 0);
      expect(session.phase, GamePhase.lost);
      session.damageBase(5);
      expect(session.baseHealth, 0);

      final wonSession = GameSession.initial();
      for (var wave = 0; wave < 5; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      wonSession.damageBase(5);
      expect(wonSession.baseHealth, 20);
    });

    test('loses when base health reaches zero and clamps health', () {
      final session = GameSession.initial(baseHealth: 2);

      expect(session.startWave(), isTrue);
      session.damageBase(5);

      expect(session.baseHealth, 0);
      expect(session.phase, GamePhase.lost);
    });

    test('loss cannot later become win by finishing the active wave', () {
      final session = GameSession.initial(baseHealth: 1);

      expect(session.startWave(), isTrue);
      session.damageBase(1);
      session.finishActiveWave();

      expect(session.phase, GamePhase.lost);
      expect(session.waveIndex, 0);
    });

    test('restart returns a clean initial state', () {
      final session = GameSession.initial();
      session.placeTower(const GridPosition(0, 0), TowerType.laser);
      session.startWave();
      session.damageBase(20);

      session.restart();

      expect(session.phase, GamePhase.build);
      expect(session.gold, 120);
      expect(session.baseHealth, 20);
      expect(session.waveIndex, 0);
      expect(session.towers, isEmpty);
    });

    test('restart resets tower IDs', () {
      final session = GameSession.initial();
      session.placeTower(const GridPosition(0, 0), TowerType.laser);

      expect(session.towers.single.id, 1);

      session.restart();
      session.placeTower(const GridPosition(0, 0), TowerType.laser);

      expect(session.towers.single.id, 1);
    });
  });
}
