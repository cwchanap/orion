import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/campaign/campaign_progress.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/campaign/stage_definition.dart';
import 'package:orion/game/ui/sector_map_layout.dart';

void main() {
  test('five main-path hit rectangles are distinct at 375x812', () {
    const size = Size(375, 812);
    final layout = SectorMapLayout.fromStages(
      stages: OrionCampaign.stages,
      size: size,
    );
    final rects = {
      for (final stage in OrionCampaign.mainStages)
        stage.id: layout.nodeRect(stage),
    };

    expect(rects.values, hasLength(5));
    for (final rect in rects.values) {
      expect(rect.width, closeTo(72, 0.001));
      expect(rect.height, closeTo(94, 0.001));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.right, lessThanOrEqualTo(375 - 52 - 12));
    }
    final ordered = OrionCampaign.mainStages
        .map((stage) => rects[stage.id]!)
        .toList(growable: false);
    for (var index = 1; index < ordered.length; index += 1) {
      expect(ordered[index - 1].overlaps(ordered[index]), isFalse);
    }
  });

  test('a synthetic sixth column overflows the viewport without overlapping '
      'its column-4 neighbor at 375px', () {
    const size = Size(375, 812);
    final source = OrionCampaign.stages.last;
    final futureStage = StageDefinition(
      id: 'future-stage',
      name: 'Future Stage',
      mapLabel: 'Future',
      description: 'Synthetic layout coverage only.',
      pathCells: source.pathCells,
      waves: source.waves,
      unlockDependencies: [source.id],
      isMainPath: false,
      reward: CampaignReward.bonusGold,
      mapColumn: 5,
      mapRow: 1,
    );
    final layout = SectorMapLayout.fromStages(
      stages: [...OrionCampaign.stages, futureStage],
      size: size,
    );

    // At 375px six columns cannot fit without overlap, so the step floors at
    // nodeSize.width and the plot content overflows the viewport (caller
    // wraps it in a horizontal scroll).
    final futureRect = layout.nodeRect(futureStage);
    final columnFour = OrionCampaign.stages
        .where((stage) => stage.mapColumn == 4)
        .map((stage) => layout.nodeRect(stage))
        .toList(growable: false);
    for (final neighbor in columnFour) {
      expect(neighbor.overlaps(futureRect), isFalse);
    }
    expect(
      layout.plotContentWidth,
      greaterThan(size.width - SectorMapLayout.railWidth),
    );
  });

  test('routes are derived from unlock dependencies', () {
    final routes = SectorMapLayout.routes(
      OrionCampaign.stages,
      CampaignProgress(),
    );

    expect(routes, hasLength(6));
    expect(
      routes.map((route) => (route.from.id, route.to.id)).toSet(),
      containsAll({
        ('outpost-alpha', 'nebula-relay'),
        ('nebula-relay', 'salvage-rift'),
        ('nebula-relay', 'asteroid-foundry'),
        ('asteroid-foundry', 'aurora-gate'),
        ('aurora-gate', 'void-bastion'),
        ('aurora-gate', 'singularity-core'),
      }),
    );
    expect(
      routes.where((route) => route.isOptional).map((route) => route.to.id),
      {'salvage-rift', 'void-bastion'},
    );
  });

  test('routes skips dependencies not present in the provided stages list', () {
    // Only provide nebula-relay without its dependency outpost-alpha
    final subset = [OrionCampaign.stages[1]]; // nebula-relay
    expect(subset.first.unlockDependencies, contains('outpost-alpha'));

    final routes = SectorMapLayout.routes(subset, CampaignProgress());
    expect(routes, isEmpty);
  });

  test(
    'compact viewports retain a scrollable, non-overlapping portrait map',
    () {
      final layout = SectorMapLayout.fromStages(
        stages: OrionCampaign.stages,
        size: const Size(280, 568),
      );
      final rects = OrionCampaign.stages.map(layout.nodeRect).toList();
      expect(layout.plotContentWidth, 360);
      expect(layout.plotContentHeight, 740);
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    },
  );

  test('the main route climbs from Alpha to Singularity as in scene 1f', () {
    final layout = SectorMapLayout.fromStages(
      stages: OrionCampaign.stages,
      size: const Size(393, 852),
    );
    final main = OrionCampaign.mainStages.map(layout.nodeRect).toList();
    for (var i = 1; i < main.length; i++) {
      expect(main[i].top, lessThan(main[i - 1].top));
    }
    expect(main[2].center.dx, lessThan(main[1].center.dx));
    expect(main[3].center.dx, greaterThan(main[2].center.dx));
  });
}
