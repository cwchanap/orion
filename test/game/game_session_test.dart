import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';

void main() {
  group('GameSession', () {
    test('starts in build phase with approved economy', () {
      final session = GameSession.initial();

      expect(session.phase, GamePhase.build);
      expect(session.gold, GameBalance.startingGold);
      expect(session.baseHealth, GameBalance.initialBaseHealth);
      expect(session.waveIndex, 0);
      expect(session.towers, isEmpty);
    });

    test('starts with only the baseline towers unlocked', () {
      final session = GameSession.initial();

      expect(session.unlockedTowerTypes, [
        TowerType.laser,
        TowerType.rocket,
        TowerType.cryo,
      ]);
      expect(session.isTowerUnlocked(TowerType.railgun), isFalse);
      expect(session.isTowerUnlocked(TowerType.droneBay), isFalse);
    });

    test('snapshot exposes default mission pacing state', () {
      final snapshot = GameSession.initial().snapshot();

      expect(snapshot.isPaused, isFalse);
      expect(snapshot.speedMultiplier, 1);
      expect(snapshot.autoStartEnabled, isFalse);
      expect(snapshot.autoStartCountdownRemaining, isNull);
    });

    test('snapshot can carry mission pacing state from the game layer', () {
      final snapshot = GameSession.initial().snapshot(
        isPaused: true,
        speedMultiplier: 2,
        autoStartEnabled: true,
        autoStartCountdownRemaining: 1.5,
      );

      expect(snapshot.isPaused, isTrue);
      expect(snapshot.speedMultiplier, 2);
      expect(snapshot.autoStartEnabled, isTrue);
      expect(snapshot.autoStartCountdownRemaining, 1.5);
    });

    test('snapshot exposes next wave preview only during build phase', () {
      final session = GameSession.initial();

      final firstPreview = session.snapshot().nextWavePreview;

      expect(firstPreview, isNotNull);
      expect(firstPreview!.waveNumber, 1);
      expect(firstPreview.waveTotal, 8);
      expect(
        firstPreview.groups.map(
          (group) => '${group.enemyCount} ${group.label}',
        ),
        ['8 Drones'],
      );

      expect(session.startWave(), isTrue);
      expect(session.snapshot().nextWavePreview, isNull);

      session.finishActiveWave();
      final secondPreview = session.snapshot().nextWavePreview;

      expect(secondPreview, isNotNull);
      expect(secondPreview!.waveNumber, 2);
      expect(
        secondPreview.groups.map(
          (group) => '${group.enemyCount} ${group.label}',
        ),
        ['8 Drones', '2 Armored Drones'],
      );
      expect(secondPreview.traits.toList(), [EnemyTrait.armored]);
      expect(secondPreview.recommendedTowerTypes, [
        TowerType.rocket,
        TowerType.railgun,
      ]);
    });

    test('snapshot preview uses selected stage single-group waves', () {
      final stage = StageDefinition(
        id: 'preview-stage',
        name: 'Preview Stage',
        mapLabel: 'Preview',
        description: 'Stage for preview tests',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: const [
          WaveDefinition(
            groups: [
              WaveGroup(
                enemyCount: 3,
                enemyStats: EnemyStats(
                  health: 78,
                  speed: 72,
                  baseDamage: 1,
                  goldReward: 14,
                  traits: {EnemyTrait.regen},
                  regenPerSecond: 2.5,
                ),
              ),
            ],
            clearBonus: 42,
          ),
        ],
        unlockDependencies: [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );

      final preview = GameSession.initial(
        stage: stage,
      ).snapshot().nextWavePreview;

      expect(preview, isNotNull);
      expect(preview!.waveNumber, 1);
      expect(preview.waveTotal, 1);
      expect(preview.groups.single.enemyCount, 3);
      expect(preview.groups.single.label, 'Regen Drones');
      expect(preview.clearBonus, 42);
      expect(preview.recommendedTowerTypes, [TowerType.laser]);
    });

    test('snapshot preview carries final wave zero clear bonus', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < 7; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      final preview = session.snapshot().nextWavePreview;

      expect(preview, isNotNull);
      expect(preview!.waveNumber, 8);
      expect(preview.waveTotal, 8);
      expect(preview.clearBonus, 0);
    });

    test('snapshot hides next wave preview after win and loss', () {
      final wonSession = GameSession.initial();
      for (var wave = 0; wave < wonSession.stage.waves.length; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      expect(wonSession.phase, GamePhase.won);
      expect(wonSession.snapshot().nextWavePreview, isNull);

      final lostSession = GameSession.initial();
      expect(lostSession.startWave(), isTrue);
      lostSession.damageBase(GameBalance.initialBaseHealth);

      expect(lostSession.phase, GamePhase.lost);
      expect(lostSession.snapshot().nextWavePreview, isNull);
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
      expect(session.gold, GameBalance.startingGold - 50);
    });

    test('places towers and spends gold', () {
      final session = GameSession.initial();

      final result = session.placeTower(
        const GridPosition(0, 0),
        TowerType.rocket,
      );

      expect(result.isAllowed, isTrue);
      expect(session.gold, GameBalance.startingGold - 80);
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

    test('denies locked tower placement without spending gold', () {
      final session = GameSession.initial(gold: 500);

      final result = session.placeTower(
        const GridPosition(0, 0),
        TowerType.droneBay,
      );

      expect(result.isAllowed, isFalse);
      expect(result.failure, PlacementFailure.lockedTower);
      expect(session.gold, 500);
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
      expect(session.gold, GameBalance.startingGold);
      expect(session.towers, isEmpty);
    });

    test('denies placement after terminal states without spending gold', () {
      final wonSession = GameSession.initial();
      for (var wave = 0; wave < wonSession.stage.waves.length; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      final wonResult = wonSession.placeTower(
        const GridPosition(0, 0),
        TowerType.laser,
      );

      expect(wonResult.isAllowed, isFalse);
      expect(wonResult.failure, PlacementFailure.invalidPhase);
      expect(wonSession.gold, 150 + 30 + 40 + 50 + 65 + 80 + 95 + 115);
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
      expect(lostSession.gold, GameBalance.startingGold);
      expect(lostSession.towers, isEmpty);
    });

    test('unlocks towers after cleared waves and applies clear bonuses', () {
      final session = GameSession.initial();

      expect(session.startWave(), isTrue);
      session.finishActiveWave();

      expect(session.phase, GamePhase.build);
      expect(session.gold, 180);
      expect(session.isTowerUnlocked(TowerType.railgun), isTrue);
      expect(session.isTowerUnlocked(TowerType.ionChain), isFalse);
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
        for (var wave = 0; wave < wonSession.stage.waves.length; wave += 1) {
          expect(wonSession.startWave(), isTrue);
          wonSession.finishActiveWave();
        }

        expect(wonSession.upgradeTower(wonTower.id), isFalse);
        expect(wonSession.towers.single.level, 1);
        expect(wonSession.gold, 130 + 30 + 40 + 50 + 65 + 80 + 95 + 115);

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

    test('specializes a level two tower once and spends gold', () {
      final session = GameSession.initial(gold: 500);
      session.placeTower(const GridPosition(0, 0), TowerType.laser);
      final tower = session.towers.single;
      expect(session.upgradeTower(tower.id), isTrue);

      final specialized = session.specializeTower(
        tower.id,
        TowerSpecialization.prismLaser,
      );

      expect(specialized, isTrue);
      expect(session.towers.single.level, 3);
      expect(
        session.towers.single.specialization,
        TowerSpecialization.prismLaser,
      );
      expect(session.gold, 260);
      expect(
        session.specializeTower(tower.id, TowerSpecialization.pulseLaser),
        isFalse,
      );
      expect(session.gold, 260);
    });

    test('rejects specialization in invalid states without spending gold', () {
      final levelOneSession = GameSession.initial(gold: 500);
      levelOneSession.placeTower(const GridPosition(0, 0), TowerType.laser);
      final levelOneTower = levelOneSession.towers.single;

      expect(
        levelOneSession.specializeTower(
          levelOneTower.id,
          TowerSpecialization.prismLaser,
        ),
        isFalse,
      );
      expect(levelOneSession.towers.single.level, 1);
      expect(levelOneSession.gold, 450);

      final wrongTowerSession = GameSession.initial(gold: 500);
      wrongTowerSession.placeTower(const GridPosition(0, 0), TowerType.laser);
      final wrongTower = wrongTowerSession.towers.single;
      expect(wrongTowerSession.upgradeTower(wrongTower.id), isTrue);

      expect(
        wrongTowerSession.specializeTower(
          wrongTower.id,
          TowerSpecialization.siegeRocket,
        ),
        isFalse,
      );
      expect(wrongTowerSession.towers.single.level, 2);
      expect(wrongTowerSession.towers.single.specialization, isNull);
      expect(wrongTowerSession.gold, 380);

      final activeWaveSession = GameSession.initial(gold: 500);
      activeWaveSession.placeTower(const GridPosition(0, 0), TowerType.laser);
      final activeWaveTower = activeWaveSession.towers.single;
      expect(activeWaveSession.upgradeTower(activeWaveTower.id), isTrue);
      expect(activeWaveSession.startWave(), isTrue);

      expect(
        activeWaveSession.specializeTower(
          activeWaveTower.id,
          TowerSpecialization.prismLaser,
        ),
        isFalse,
      );
      expect(activeWaveSession.towers.single.level, 2);
      expect(activeWaveSession.towers.single.specialization, isNull);
      expect(activeWaveSession.gold, 380);
    });

    test('insufficient specialization gold preserves tower level and gold', () {
      final session = GameSession.initial(gold: 239);
      session.placeTower(const GridPosition(0, 0), TowerType.laser);
      final tower = session.towers.single;
      expect(session.upgradeTower(tower.id), isTrue);

      expect(
        session.specializeTower(tower.id, TowerSpecialization.prismLaser),
        isFalse,
      );
      expect(session.towers.single.level, 2);
      expect(session.towers.single.specialization, isNull);
      expect(session.gold, 119);
    });

    test('starts waves only from build phase', () {
      final session = GameSession.initial();

      expect(session.startWave(), isTrue);
      expect(session.phase, GamePhase.wave);
      expect(session.startWave(), isFalse);
    });

    test('progresses through all waves and wins after the final clear', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < session.stage.waves.length; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      expect(session.phase, GamePhase.won);
      expect(session.waveIndex, session.stage.waves.length);
    });

    test('startWave remains false after won', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < session.stage.waves.length; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      expect(session.phase, GamePhase.won);
      expect(session.startWave(), isFalse);
    });

    test('rewardKill mutates gold only during wave for positive rewards', () {
      final session = GameSession.initial();

      session.rewardKill(8);
      expect(session.gold, GameBalance.startingGold);

      expect(session.startWave(), isTrue);
      session.rewardKill(8);
      session.rewardKill(0);
      session.rewardKill(-4);
      expect(session.gold, GameBalance.startingGold + 8);

      session.damageBase(20);
      expect(session.phase, GamePhase.lost);
      session.rewardKill(8);
      expect(session.gold, GameBalance.startingGold + 8);

      final wonSession = GameSession.initial();
      for (var wave = 0; wave < wonSession.stage.waves.length; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      wonSession.rewardKill(8);
      expect(wonSession.gold, 150 + 30 + 40 + 50 + 65 + 80 + 95 + 115);
    });

    test('damageBase mutates health only during wave for positive damage', () {
      final session = GameSession.initial();

      session.damageBase(5);
      expect(session.baseHealth, GameBalance.initialBaseHealth);

      expect(session.startWave(), isTrue);
      session.damageBase(5);
      session.damageBase(0);
      session.damageBase(-4);
      expect(session.baseHealth, GameBalance.initialBaseHealth - 5);

      session.damageBase(20);
      expect(session.baseHealth, 0);
      expect(session.phase, GamePhase.lost);
      session.damageBase(5);
      expect(session.baseHealth, 0);

      final wonSession = GameSession.initial();
      for (var wave = 0; wave < wonSession.stage.waves.length; wave += 1) {
        expect(wonSession.startWave(), isTrue);
        wonSession.finishActiveWave();
      }

      wonSession.damageBase(5);
      expect(wonSession.baseHealth, GameBalance.initialBaseHealth);
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
      expect(session.gold, GameBalance.startingGold);
      expect(session.baseHealth, GameBalance.initialBaseHealth);
      expect(session.waveIndex, 0);
      expect(session.towers, isEmpty);
    });

    test('restart resets unlock progress and specialized towers', () {
      final session = GameSession.initial(gold: 500);
      expect(session.startWave(), isTrue);
      session.finishActiveWave();
      expect(session.isTowerUnlocked(TowerType.railgun), isTrue);
      session.placeTower(const GridPosition(0, 0), TowerType.railgun);
      final tower = session.towers.single;
      expect(session.upgradeTower(tower.id), isTrue);
      expect(
        session.specializeTower(tower.id, TowerSpecialization.magneticRailgun),
        isTrue,
      );
      expect(
        session.towers.single.specialization,
        TowerSpecialization.magneticRailgun,
      );

      session.restart();

      expect(session.waveIndex, 0);
      expect(session.gold, GameBalance.startingGold);
      expect(session.unlockedTowerTypes, [
        TowerType.laser,
        TowerType.rocket,
        TowerType.cryo,
      ]);
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

    test('final wave win does not add a clear bonus', () {
      final session = GameSession.initial();

      for (var wave = 0; wave < session.stage.waves.length; wave += 1) {
        expect(session.startWave(), isTrue);
        session.finishActiveWave();
      }

      expect(session.phase, GamePhase.won);
      expect(session.gold, 150 + 30 + 40 + 50 + 65 + 80 + 95 + 115);
    });

    test('uses selected stage waves for mission progress', () {
      final stage = StageDefinition(
        id: 'test-stage',
        name: 'Test Stage',
        mapLabel: 'Test',
        description: 'Test stage',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: GameBalance.waves.take(2).toList(growable: false),
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );
      final session = GameSession.initial(stage: stage);

      expect(session.stage, stage);
      expect(session.snapshot().stageId, 'test-stage');
      expect(session.snapshot().stageName, 'Test Stage');
      expect(session.snapshot().stageLabel, 'Test');
      expect(session.snapshot().waveTotal, 2);

      expect(session.startWave(), isTrue);
      session.finishActiveWave();
      expect(session.phase, GamePhase.build);

      expect(session.startWave(), isTrue);
      session.finishActiveWave();
      expect(session.phase, GamePhase.won);
      expect(session.waveIndex, 2);
    });

    test('uses selected stage path for placement blocking', () {
      final stage = StageDefinition(
        id: 'path-stage',
        name: 'Path Stage',
        mapLabel: 'Path',
        description: 'Test stage',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: GameBalance.waves,
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );
      final session = GameSession.initial(stage: stage);

      expect(
        session
            .validatePlacement(const GridPosition(0, 0), TowerType.laser)
            .failure,
        PlacementFailure.pathBlocked,
      );
      expect(
        session
            .validatePlacement(const GridPosition(0, 1), TowerType.laser)
            .isAllowed,
        isTrue,
      );
    });

    test('rejects selected stages without waves', () {
      final stage = StageDefinition(
        id: 'empty-stage',
        name: 'Empty Stage',
        mapLabel: 'Empty',
        description: 'Invalid stage',
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
        waves: const [],
        unlockDependencies: const [],
        isMainPath: true,
        mainPathOrder: 1,
        mapColumn: 0,
        mapRow: 0,
      );

      expect(
        () => GameSession.initial(stage: stage),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.invalidValue, 'invalidValue', stage.id)
              .having((error) => error.name, 'name', 'stage'),
        ),
      );
    });
  });
}
