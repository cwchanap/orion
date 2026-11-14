import 'dart:math' as math;
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
    required this._hasUnanchoredStages,
  });

  static const railWidth = 52.0;
  static const horizontalPadding = 12.0;
  static const nodeSize = Size(72, 94);

  /// Vertical insets the node field keeps inside its own box. Anchored and
  /// grid-placed nodes share this frame, so both baselines agree. The top
  /// inset also reserves headroom for the recommended node's NEXT flag,
  /// which hangs 24px above its crest and would otherwise clip against the
  /// scroll viewport for the topmost stage. The bottom inset likewise
  /// reserves room for the bottommost node's caption — its chip and medal
  /// pips reach ~17px below the node rect and would clip against the
  /// plot's own bounds.
  static const plotTopInset = 28.0;
  static const plotBottomInset = 24.0;

  /// Smallest node-top spread that keeps the tightest anchor pair a full
  /// node apart. The closest pair (singularity-core/aurora-gate and
  /// nebula-relay/asteroid-foundry) spans ~0.325 of the anchor dy range, so
  /// 300 guarantees ~97px between node tops at the minimum content height.
  static const minNodeSpan = 300.0;

  final Size _size;
  final int maxColumn;
  final int maxRow;
  final bool _hasUnanchoredStages;

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
      hasUnanchoredStages: stages.any(
        (stage) => !_anchors.containsKey(stage.id),
      ),
    );
  }

  static const _anchors = <String, Offset>{
    'outpost-alpha': Offset(70 / 393, 640 / 852),
    'nebula-relay': Offset(150 / 393, 550 / 852),
    'salvage-rift': Offset(262 / 393, 588 / 852),
    'asteroid-foundry': Offset(118 / 393, 420 / 852),
    'aurora-gate': Offset(228 / 393, 370 / 852),
    'void-bastion': Offset(318 / 393, 440 / 852),
    'singularity-core': Offset(232 / 393, 240 / 852),
  };

  static final double _anchorMinDy = _anchors.values
      .map((anchor) => anchor.dy)
      .reduce(math.min);
  static final double _anchorMaxDy = _anchors.values
      .map((anchor) => anchor.dy)
      .reduce(math.max);

  /// Vertical distance node tops can spread over inside the plot box.
  double get _nodeSpan =>
      (_size.height - plotTopInset - plotBottomInset - nodeSize.height).clamp(
        0.0,
        double.infinity,
      );

  /// Smallest plot height that keeps every node a full node apart: the
  /// anchor fit needs [minNodeSpan]; unanchored grid rows need one node
  /// height per row step. The caller should grow the plot (and scroll)
  /// rather than let nodes overlap below this height.
  double get minContentHeight =>
      _minContentHeight(maxRow, _hasUnanchoredStages);

  static double minContentHeightFor(List<StageDefinition> stages) {
    if (stages.isEmpty) {
      throw ArgumentError.value(stages, 'stages', 'Must not be empty');
    }
    var maxRow = stages.first.mapRow;
    var hasUnanchoredStages = false;
    for (final stage in stages) {
      if (stage.mapRow > maxRow) maxRow = stage.mapRow;
      if (!_anchors.containsKey(stage.id)) hasUnanchoredStages = true;
    }
    return _minContentHeight(maxRow, hasUnanchoredStages);
  }

  static double _minContentHeight(int maxRow, bool hasUnanchoredStages) {
    final gridSpan = hasUnanchoredStages ? maxRow * nodeSize.height : 0.0;
    return plotTopInset +
        plotBottomInset +
        nodeSize.height +
        math.max(minNodeSpan, gridSpan);
  }

  Rect nodeRect(StageDefinition stage) {
    final anchor = _anchors[stage.id];
    if (anchor != null) {
      // Fit the anchor dy range into the plot's own top/bottom insets: the
      // chart fills whatever height it is given instead of floating inside
      // a fixed 680px frame with a hand-tuned vertical offset.
      final t = (anchor.dy - _anchorMinDy) / (_anchorMaxDy - _anchorMinDy);
      return Rect.fromLTWH(
        anchor.dx * _size.width.clamp(360, double.infinity) -
            nodeSize.width / 2,
        plotTopInset + t * _nodeSpan,
        nodeSize.width,
        nodeSize.height,
      );
    }
    final xStep = _horizontalStep;
    // Grid-placed stages share the anchored nodes' top baseline and spread;
    // the row step floors at a full node height so compact boxes scroll
    // instead of stacking every stage on one spot.
    final yStep = maxRow == 0
        ? 0.0
        : math.max(_nodeSpan / maxRow, nodeSize.height);
    return Rect.fromLTWH(
      horizontalPadding + (stage.mapColumn * xStep),
      plotTopInset + (stage.mapRow * yStep),
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
    if (maxColumn <= 4) return _size.width.clamp(360, double.infinity);
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
