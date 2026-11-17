import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/game_session.dart';
import 'package:orion/game/rules/module_offer_picker.dart';

import 'game_test_fixtures.dart';

final class _RecordingOfferPicker implements ModuleOfferPicker {
  final List<List<RunModuleId>> candidateHistory = [];

  @override
  List<RunModuleId> pick(List<RunModuleId> candidates, {required int count}) {
    candidateHistory.add(List<RunModuleId>.unmodifiable(candidates));
    return List<RunModuleId>.unmodifiable(candidates.take(count));
  }
}

void _completeWave(GameSession session) {
  expect(session.startWave(), isTrue);
  session.finishActiveWave();
}

void main() {
  group('GameSession squad deployment (HPA-922)', () {
    test('defaults to the starter squad when none is supplied', () {
      final session = GameSession.initial();

      expect(session.squad, [Character.haruto, Character.mio]);
      expect(session.snapshot().squad, [Character.haruto, Character.mio]);
    });

    test('accepts a squad at the six-member cap', () {
      final session = GameSession.initial(
        squad: {
          for (final member in Character.values.take(GameBalance.squadMaxSize))
            member: 1,
        },
      );

      expect(session.squad, hasLength(GameBalance.squadMaxSize));
    });

    test('rejects a squad larger than the six-member cap', () {
      expect(
        () => GameSession.initial(
          squad: {
            for (final member in Character.values.take(
              GameBalance.squadMaxSize + 1,
            ))
              member: 1,
          },
        ),
        throwsArgumentError,
      );
    });

    test(
      'snapshot exposes the ordered squad separately from deduped styles',
      () {
        final session = GameSession.initial(
          squad: {Character.rin: 2, Character.hikari: 5, Character.haruto: 3},
        );

        final snapshot = session.snapshot();

        expect(snapshot.squad, [
          Character.rin,
          Character.hikari,
          Character.haruto,
        ]);
        // Rin is cryo; Hikari and Haruto are both laser — the style list is
        // deduplicated in squad order while the squad keeps every member.
        expect(snapshot.unlockedTowerTypes, [TowerType.cryo, TowerType.laser]);
      },
    );

    test('places a squad member storing character and persistent level', () {
      final session = GameSession.initial(squad: {Character.jin: 4}, gold: 500);

      final result = session.placeTower(
        const GridPosition(0, 0),
        Character.jin,
      );

      expect(result.isAllowed, isTrue);
      final tower = session.towers.single;
      expect(tower.character, Character.jin);
      expect(tower.characterLevel, 4);
      expect(tower.type, TowerType.cryo);
      expect(tower.level, 1);
      expect(tower.specialization, isNull);
    });

    test('rejects a character outside the squad', () {
      final session = GameSession.initial();

      final result = session.placeTower(
        const GridPosition(0, 0),
        Character.jin,
      );

      expect(result.isAllowed, isFalse);
      expect(result.failure, PlacementFailure.notInSquad);
      expect(session.towers, isEmpty);
      expect(session.gold, GameBalance.startingGold);
    });

    test('rejects a second deployment of the same character', () {
      final session = GameSession.initial();
      expect(
        session
            .placeTower(const GridPosition(0, 0), Character.haruto)
            .isAllowed,
        isTrue,
      );

      final result = session.placeTower(
        const GridPosition(1, 2),
        Character.haruto,
      );

      expect(result.isAllowed, isFalse);
      expect(result.failure, PlacementFailure.alreadyDeployed);
      expect(session.towers, hasLength(1));
    });

    test('two characters sharing a style can both deploy', () {
      final session = GameSession.initial(
        squad: {Character.haruto: 1, Character.hikari: 3},
        gold: 500,
      );

      expect(
        session
            .placeTower(const GridPosition(0, 0), Character.haruto)
            .isAllowed,
        isTrue,
      );
      expect(
        session
            .placeTower(const GridPosition(1, 2), Character.hikari)
            .isAllowed,
        isTrue,
      );

      expect(session.towers.map((tower) => tower.type), [
        TowerType.laser,
        TowerType.laser,
      ]);
      // Both lasers deploy, yet the squad style projection stays deduplicated.
      expect(session.unlockedTowerTypes, [TowerType.laser]);
    });

    test('persistent character level scales placed damage channels', () {
      final session = GameSession.initial(squad: {Character.haruto: 40});
      session.placeTower(const GridPosition(0, 0), Character.haruto);

      final stats = session.resolveTowerStats(session.towers.single);

      final base = GameBalance.towerStats(TowerType.laser, level: 1);
      final factor = GameBalance.characterScalingFactor(
        Character.haruto.rank,
        40,
      );
      expect(stats.damage, closeTo(base.damage * factor, 1e-9));
    });

    test('preview validation uses the same squad and occupancy rules', () {
      final session = GameSession.initial();

      expect(
        session
            .validatePlacement(const GridPosition(0, 0), Character.jin)
            .failure,
        PlacementFailure.notInSquad,
      );
      session.placeTower(const GridPosition(0, 0), Character.haruto);
      expect(
        session
            .validatePlacement(const GridPosition(1, 2), Character.haruto)
            .failure,
        PlacementFailure.alreadyDeployed,
      );
      expect(
        session
            .validatePlacement(const GridPosition(0, 0), Character.mio)
            .failure,
        PlacementFailure.occupied,
      );
    });
  });

  group('GameSession merged three-tier upgrade (HPA-922)', () {
    test(
      'one upgrade action walks all three tiers and applies the signature',
      () {
        final session = GameSession.initial(
          squad: {Character.haruto: 1},
          gold: 500,
        );
        session.placeTower(const GridPosition(0, 0), Character.haruto);
        final tower = session.towers.single;
        final laserCosts = GameBalance.towerStats(TowerType.laser, level: 1);
        expect(session.gold, 450);
        expect(tower.canUpgrade, isTrue);

        expect(session.upgradeTower(tower.id), isTrue);
        expect(session.towers.single.level, 2);
        expect(session.towers.single.specialization, isNull);
        expect(session.gold, 450 - laserCosts.upgradeCost);

        expect(session.upgradeTower(tower.id), isTrue);
        expect(session.towers.single.level, 3);
        expect(
          session.towers.single.specialization,
          Character.haruto.signature,
        );
        expect(
          session.gold,
          450 - laserCosts.upgradeCost - laserCosts.specializationCost,
        );

        expect(session.towers.single.isMaxLevel, isTrue);
        expect(session.upgradeTower(tower.id), isFalse);
        expect(
          session.gold,
          450 - laserCosts.upgradeCost - laserCosts.specializationCost,
        );
      },
    );

    test('tier-2 upgrade charges specializationCost, not upgradeCost', () {
      final session = GameSession.initial(
        squad: {Character.haruto: 1},
        gold: 500,
      );
      session.placeTower(const GridPosition(0, 0), Character.haruto);
      final tower = session.towers.single;
      expect(session.upgradeTower(tower.id), isTrue);
      final afterTier2 = session.gold;

      // Exactly the signature price: one gold short denies the tier-3 step.
      final laserCosts = GameBalance.towerStats(TowerType.laser, level: 2);
      expect(laserCosts.nextUpgradeCost, laserCosts.specializationCost);
      expect(
        afterTier2 - laserCosts.specializationCost,
        greaterThanOrEqualTo(0),
      );

      final tightSession = GameSession.initial(
        squad: {Character.haruto: 1},
        gold:
            GameBalance.towerStats(TowerType.laser, level: 1).cost +
            GameBalance.towerStats(TowerType.laser, level: 1).upgradeCost +
            GameBalance.towerStats(
              TowerType.laser,
              level: 2,
            ).specializationCost -
            1,
      );
      tightSession.placeTower(const GridPosition(0, 0), Character.haruto);
      final tightTower = tightSession.towers.single;
      expect(tightSession.upgradeTower(tightTower.id), isTrue);
      expect(tightSession.upgradeTower(tightTower.id), isFalse);
      expect(tightSession.towers.single.level, 2);
      expect(tightSession.towers.single.specialization, isNull);
    });

    test('the applied signature is the fixed character signature', () {
      final session = GameSession.initial(
        squad: {Character.hikari: 1, Character.haruto: 1},
        gold: 999,
      );
      session.placeTower(const GridPosition(0, 0), Character.hikari);
      session.placeTower(const GridPosition(1, 2), Character.haruto);
      for (final tower in session.towers.toList()) {
        expect(session.upgradeTower(tower.id), isTrue);
        expect(session.upgradeTower(tower.id), isTrue);
      }
      final byCharacter = {
        for (final tower in session.towers) tower.character: tower,
      };
      expect(
        byCharacter[Character.hikari]!.specialization,
        TowerSpecialization.prismLaser,
      );
      expect(
        byCharacter[Character.haruto]!.specialization,
        TowerSpecialization.pulseLaser,
      );
      expect(
        session.resolveTowerStats(byCharacter[Character.hikari]!).damage,
        closeTo(
          GameBalance.towerStats(
                TowerType.laser,
                level: 3,
                specialization: TowerSpecialization.prismLaser,
              ).damage *
              GameBalance.characterScalingFactor(Character.hikari.rank, 1),
          1e-9,
        ),
      );
    });

    test('upgrade preview stays on the shared next-tier projection', () {
      final session = GameSession.initial(
        squad: {Character.haruto: 1},
        gold: 500,
      );
      session.placeTower(const GridPosition(0, 0), Character.haruto);
      final tower = session.towers.single;

      final tier2Preview = session
          .snapshot(selectedTower: tower)
          .selectedTowerUpgradeStats;
      expect(tier2Preview, isNotNull);
      expect(tier2Preview!.level, 2);
      expect(tier2Preview.specialization, isNull);

      expect(session.upgradeTower(tower.id), isTrue);
      final tier3Preview = session
          .snapshot(selectedTower: session.towers.single)
          .selectedTowerUpgradeStats;
      expect(tier3Preview, isNotNull);
      expect(tier3Preview!.level, 3);
      expect(tier3Preview.specialization, Character.haruto.signature);
    });
  });

  group('GameSession recall (HPA-922)', () {
    test(
      'recall refunds invested gold and frees the character to redeploy',
      () {
        final session = GameSession.initial(
          squad: {Character.haruto: 1},
          gold: 500,
        );
        session.placeTower(const GridPosition(0, 0), Character.haruto);
        final tower = session.towers.single;
        expect(session.upgradeTower(tower.id), isTrue);

        final refund = session.sellTower(tower.id);

        // 70% of 50 + 70 = 84; the character is available again at tier 1.
        expect(refund, 84);
        expect(session.gold, 464);
        expect(session.towers, isEmpty);

        final redeploy = session.placeTower(
          const GridPosition(1, 2),
          Character.haruto,
        );
        expect(redeploy.isAllowed, isTrue);
        expect(session.towers.single.level, 1);
        expect(session.towers.single.characterLevel, 1);
      },
    );

    test('recall of a tier-3 signature refunds the full investment', () {
      final session = GameSession.initial(
        squad: {Character.haruto: 1},
        gold: 999,
      );
      session.placeTower(const GridPosition(0, 0), Character.haruto);
      final tower = session.towers.single;
      session.upgradeTower(tower.id);
      session.upgradeTower(tower.id);
      expect(session.towers.single.specialization, isNotNull);

      final refund = session.sellTower(tower.id);

      // 70% of 50 + 70 + 120 = 168.
      expect(refund, 168);
      expect(session.towers, isEmpty);
      expect(
        session
            .placeTower(const GridPosition(0, 0), Character.haruto)
            .isAllowed,
        isTrue,
      );
    });
  });

  group('GameSession module pool with squad styles (HPA-922)', () {
    test(
      'starter-squad wave-2 draft keeps every family module out of the pool',
      () {
        final picker = _RecordingOfferPicker();
        final session = GameSession.initial(
          stage: stageWithWaveCount(8),
          offerPicker: picker,
        );

        _completeWave(session);
        _completeWave(session);

        final candidates = picker.candidateHistory.single;
        // Five universal modules remain in the base pool, so neither the
        // squad's rocket family nor any off-squad family is offered early.
        expect(
          candidates.every((id) => runModuleDefinition(id).tower == null),
          isTrue,
        );
      },
    );

    test('a placed squad family surfaces its module in the first pass', () {
      final picker = _RecordingOfferPicker();
      final session = GameSession.initial(
        stage: stageWithWaveCount(8),
        gold: 9999,
        squad: const {Character.jin: 1},
        offerPicker: picker,
      );
      session.placeTower(const GridPosition(2, 0), Character.jin);

      _completeWave(session);
      _completeWave(session);

      expect(
        picker.candidateHistory.single,
        contains(RunModuleId.cryoReservoir),
      );
    });

    test('squad families precede off-squad families in the fallback', () {
      final picker = _RecordingOfferPicker();
      final session = GameSession.initial(
        stage: stageWithWaveCount(8),
        squad: const {Character.jin: 1},
        // Constrain the pool so every fill tier is exercised: one universal,
        // the squad's cryo family, then only off-squad families left.
        availableRunModules: const {
          RunModuleId.emergencySalvage,
          RunModuleId.cryoReservoir,
          RunModuleId.rocketFusing,
          RunModuleId.relayArc,
        },
        offerPicker: picker,
      );

      _completeWave(session);
      _completeWave(session);

      expect(picker.candidateHistory.single, [
        RunModuleId.emergencySalvage,
        RunModuleId.cryoReservoir,
        RunModuleId.rocketFusing,
        RunModuleId.relayArc,
      ]);
    });

    test('off-squad families stay out while squad fill reaches three', () {
      final picker = _RecordingOfferPicker();
      final session = GameSession.initial(
        stage: stageWithWaveCount(8),
        // Starter squad: laser (Haruto) + rocket (Mio) families.
        availableRunModules: const {
          RunModuleId.emergencySalvage,
          RunModuleId.rocketFusing,
          RunModuleId.auroraFocus,
          RunModuleId.cryoReservoir,
        },
        offerPicker: picker,
      );

      _completeWave(session);
      _completeWave(session);

      expect(picker.candidateHistory.single, [
        RunModuleId.emergencySalvage,
        RunModuleId.rocketFusing,
        RunModuleId.auroraFocus,
      ]);
      expect(
        picker.candidateHistory.single,
        isNot(contains(RunModuleId.cryoReservoir)),
      );
    });

    test('three-card drafts survive the squad-based pool', () {
      final picker = _RecordingOfferPicker();
      final session = GameSession.initial(
        stage: stageWithWaveCount(8),
        squad: testStarterSquad,
        offerPicker: picker,
      );

      for (var wave = 0; wave < 6; wave += 1) {
        _completeWave(session);
        final offer = session.pendingRunModuleOffer;
        if (offer != null) {
          expect(offer.moduleIds, hasLength(3));
          expect(
            session.selectRunModule(
              offerId: offer.offerId,
              moduleId: offer.moduleIds.first,
            ),
            isTrue,
          );
        }
      }
      expect(picker.candidateHistory, hasLength(3));
      expect(
        picker.candidateHistory.every((candidates) => candidates.length >= 3),
        isTrue,
      );
    });

    test('unlockedTowerTypes stays a deduplicated squad-style list', () {
      final session = GameSession.initial(
        squad: {Character.rin: 1, Character.jin: 1, Character.mio: 1},
      );

      expect(session.unlockedTowerTypes, [TowerType.cryo, TowerType.rocket]);
      expect(session.snapshot().unlockedTowerTypes, [
        TowerType.cryo,
        TowerType.rocket,
      ]);
    });
  });
}
