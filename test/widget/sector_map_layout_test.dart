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
      expect(rect.size, const Size(56, 80));
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

  test('a synthetic sixth column remains inside the plotting bounds', () {
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

    expect(
      layout.nodeRect(futureStage).right,
      lessThanOrEqualTo(size.width - SectorMapLayout.railWidth - 12),
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

  test('nodeRect clamps steps to zero when available span is constrained', () {
    const tinySize = Size(50, 100);
    final layout = SectorMapLayout.fromStages(
      stages: OrionCampaign.stages,
      size: tinySize,
    );
    final rect = layout.nodeRect(OrionCampaign.stages.last);
    expect(rect.left, SectorMapLayout.horizontalPadding);
    expect(rect.top, SectorMapLayout.plotTop);
    expect(rect.size, const Size(56, 80));
  });
}
