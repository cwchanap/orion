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
    final xStep = _horizontalStep;
    final availableHeight =
        (_size.height - plotTop - plotBottomInset - nodeSize.height).clamp(
          0.0,
          double.infinity,
        );
    final yStep = maxRow == 0 ? 0.0 : availableHeight / maxRow;
    return Rect.fromLTWH(
      horizontalPadding + (stage.mapColumn * xStep),
      plotTop + (stage.mapRow * yStep),
      nodeSize.width,
      nodeSize.height,
    );
  }

  /// Horizontal step between adjacent columns. Never falls below
  /// [nodeSize.width] so neighboring nodes cannot overlap; when the viewport
  /// cannot fit all columns at that minimum, [plotContentWidth] exceeds the
  /// available plot width and the view scrolls horizontally.
  double get _horizontalStep {
    final plotWidth = _size.width - (horizontalPadding * 2) - railWidth;
    final availableWidth = (plotWidth - nodeSize.width).clamp(
      0.0,
      double.infinity,
    );
    final naturalStep = maxColumn == 0 ? 0.0 : availableWidth / maxColumn;
    return naturalStep < nodeSize.width ? nodeSize.width : naturalStep;
  }

  /// Total width the plot content occupies (left padding + last column right
  /// edge + right padding). When this exceeds the viewport's plot width the
  /// caller should wrap the plot in a horizontal scroll.
  double get plotContentWidth {
    final xStep = _horizontalStep;
    return horizontalPadding +
        (maxColumn * xStep) +
        nodeSize.width +
        horizontalPadding;
  }

  static List<SectorRoute> routes(
    List<StageDefinition> stages,
    CampaignProgress progress,
  ) {
    final byId = {for (final stage in stages) stage.id: stage};
    return [
      for (final to in stages)
        for (final dependency in to.unlockDependencies)
          if (byId[dependency] case final from?)
            SectorRoute(
              from: from,
              to: to,
              isOptional: !to.isMainPath,
              isActive: progress.statusFor(to) != StageProgressStatus.locked,
              medal: progress.resultFor(to.id)?.medal,
            ),
    ];
  }
}
