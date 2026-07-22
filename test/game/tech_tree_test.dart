import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/tech_tree.dart';

void main() {
  group('CampaignTechUpgrade', () {
    test('has exactly five values', () {
      expect(CampaignTechUpgrade.values, hasLength(5));
    });

    test(
      'each upgrade carries a stable id, cost, label, description, effectLabel',
      () {
        for (final upgrade in CampaignTechUpgrade.values) {
          expect(upgrade.id, isNotEmpty);
          expect(upgrade.cost, greaterThan(0));
          expect(upgrade.label, isNotEmpty);
          expect(upgrade.description, isNotEmpty);
          expect(upgrade.effectLabel, isNotEmpty);
        }
      },
    );

    test('fromIdList round-trips toIdList', () {
      final set = {
        CampaignTechUpgrade.solarCapacitors,
        CampaignTechUpgrade.cryoCoolant,
      };
      final tree = CampaignTechTree(purchased: set);
      expect(CampaignTechTree.fromIdList(tree.toIdList()).purchased, set);
    });

    test('fromIdList drops unknown ids', () {
      final tree = CampaignTechTree.fromIdList(const [
        'solar-capacitors',
        'unknown-future-id',
        'cryo-coolant',
      ]);
      expect(tree.purchased, {
        CampaignTechUpgrade.solarCapacitors,
        CampaignTechUpgrade.cryoCoolant,
      });
    });

    test('fromIdList deduplicates duplicate ids', () {
      final tree = CampaignTechTree.fromIdList(const [
        'solar-capacitors',
        'solar-capacitors',
        'cryo-coolant',
      ]);
      expect(tree.purchased, hasLength(2));
      expect(tree.purchased, {
        CampaignTechUpgrade.solarCapacitors,
        CampaignTechUpgrade.cryoCoolant,
      });
    });

    test('fromIdList on null returns empty tree', () {
      expect(CampaignTechTree.fromIdList(null).purchased, isEmpty);
    });
  });

  group('CampaignTechTree.unspentPoints', () {
    CampaignProgress progressWithRanks(List<int> ranks) {
      final results = <String, StageResult>{};
      for (var i = 0; i < ranks.length; i++) {
        final medal = ranks[i] == 3
            ? StageMedal.gold
            : ranks[i] == 2
            ? StageMedal.silver
            : StageMedal.clear;
        results['stage-$i'] = StageResult(medal: medal, bestBaseHealth: 10);
      }
      return CampaignProgress(bestResultsByStageId: results);
    }

    test('empty progress yields zero points', () {
      final tree = CampaignTechTree();
      expect(tree.unspentPoints(CampaignProgress()), 0);
    });

    test('seven clears (rank 1 each) yield 7 points', () {
      final progress = progressWithRanks(const [1, 1, 1, 1, 1, 1, 1]);
      expect(CampaignTechTree().unspentPoints(progress), 7);
    });

    test('seven golds (rank 3 each) yield 21 points', () {
      final progress = progressWithRanks(const [3, 3, 3, 3, 3, 3, 3]);
      expect(CampaignTechTree().unspentPoints(progress), 21);
    });

    test('partial purchase reduces unspent by current cost', () {
      final progress = progressWithRanks(const [3, 3, 3, 3]);
      final tree = CampaignTechTree(
        purchased: {CampaignTechUpgrade.solarCapacitors},
      );
      // 4 golds = 12 earned; solarCapacitors costs 3; unspent = 9
      expect(tree.unspentPoints(progress), 9);
    });

    test('overdrawn bank (spent > earned) clamps to zero', () {
      final progress = CampaignProgress();
      // Pretend a prior version let us buy something for free; the purchased
      // set now has totalSpent > 0 but the player has no medals.
      final tree = CampaignTechTree(
        purchased: {CampaignTechUpgrade.cryoCoolant},
      );
      expect(tree.unspentPoints(progress), 0);
    });
  });

  group('CampaignTechTree.canPurchase', () {
    final richProgress = CampaignProgress(
      bestResultsByStageId: {
        's': const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      },
    );

    test('true when upgrade not purchased and bank >= cost', () {
      expect(
        CampaignTechTree().canPurchase(
          CampaignTechUpgrade.solarCapacitors,
          richProgress,
        ),
        isTrue,
      );
    });

    test('false when already purchased', () {
      final tree = CampaignTechTree(
        purchased: {CampaignTechUpgrade.solarCapacitors},
      );
      expect(
        tree.canPurchase(CampaignTechUpgrade.solarCapacitors, richProgress),
        isFalse,
      );
    });

    test('false when bank < cost', () {
      expect(
        CampaignTechTree().canPurchase(
          CampaignTechUpgrade.laserTuning,
          CampaignProgress(),
        ),
        isFalse,
      );
    });
  });

  group('CampaignTechTree.purchase', () {
    final richProgress = CampaignProgress(
      bestResultsByStageId: {
        's': const StageResult(medal: StageMedal.gold, bestBaseHealth: 20),
      },
    );

    test(
      'returns a new instance containing the upgrade; original unchanged',
      () {
        const upgrade = CampaignTechUpgrade.solarCapacitors;
        final original = CampaignTechTree();
        final next = original.purchase(upgrade, richProgress);
        expect(next.isPurchased(upgrade), isTrue);
        expect(original.isPurchased(upgrade), isFalse);
      },
    );

    test('throws ArgumentError when upgrade already purchased', () {
      final tree = CampaignTechTree(
        purchased: {CampaignTechUpgrade.solarCapacitors},
      );
      expect(
        () => tree.purchase(CampaignTechUpgrade.solarCapacitors, richProgress),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when unaffordable', () {
      expect(
        () => CampaignTechTree().purchase(
          CampaignTechUpgrade.cryoCoolant,
          CampaignProgress(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('CampaignTechTree total cost across all upgrades', () {
    test('equals 20 (intentional 1-pt slack below 21 max)', () {
      final totalSpent = CampaignTechUpgrade.values.fold(
        0,
        (sum, u) => sum + u.cost,
      );
      expect(totalSpent, 20);
    });
  });
}
