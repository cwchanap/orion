import 'dart:ui';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';

final class SectorRoute {
  const SectorRoute({
    required this.from,
    required this.to,
    required this.isOptional,
    required this.isActive,
    required this.medal,
  });

  final StageDefinition from;
  final StageDefinition to;
  final bool isOptional;
  final bool isActive;
  final StageMedal? medal;
}

final class SectorMapLayout {
  const SectorMapLayout._(
    this._size, {
    required this.maxColumn,
    required this.maxRow,
  });

  static const railWidth = 52.0;
  static const horizontalPadding = 12.0;
  static const nodeSize = Size(56, 80);
  static const plotTop = 76.0;
  static const plotBottomInset = 40.0;

  final Size _size;
  final int maxColumn;
  final int maxRow;

  factory SectorMapLayout.fromStages({
    required List<StageDefinition> stages,
    required Size size,
  }) {
    if (stages.isEmpty) {
      throw ArgumentError.value(stages, 'stages', 'Must not be empty');
    }
    return SectorMapLayout._(
      size,
      maxColumn: stages
          .map((stage) => stage.mapColumn)
          .reduce((left, right) => left > right ? left : right),
      maxRow: stages
          .map((stage) => stage.mapRow)
          .reduce((left, right) => left > right ? left : right),
    );
  }

  Rect nodeRect(StageDefinition stage) {
    final plotWidth = _size.width - (horizontalPadding * 2) - railWidth;
    final xStep = maxColumn == 0
        ? 0.0
        : (plotWidth - nodeSize.width) / maxColumn;
    final availableHeight =
        _size.height - plotTop - plotBottomInset - nodeSize.height;
    final yStep = maxRow == 0 ? 0.0 : availableHeight / maxRow;
    return Rect.fromLTWH(
      horizontalPadding + (stage.mapColumn * xStep),
      plotTop + (stage.mapRow * yStep),
      nodeSize.width,
      nodeSize.height,
    );
  }

  static List<SectorRoute> routes(
    List<StageDefinition> stages,
    CampaignProgress progress,
  ) {
    final byId = {for (final stage in stages) stage.id: stage};
    return [
      for (final to in stages)
        for (final dependency in to.unlockDependencies)
          SectorRoute(
            from: byId[dependency]!,
            to: to,
            isOptional: !to.isMainPath,
            isActive: progress.statusFor(to) != StageProgressStatus.locked,
            medal: progress.resultFor(to.id)?.medal,
          ),
    ];
  }
}
