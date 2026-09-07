import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_reward_label.dart';
import 'campaign_presentation.dart';
import 'command_frame.dart';
import 'orion_atlas_sprite.dart';
import 'orion_ui_theme.dart';
import 'sector_map_layout.dart';

class WorldMapView extends StatefulWidget {
  const WorldMapView({
    super.key,
    required this.stages,
    required this.progress,
    this.campaignModifiers,
    required this.feedback,
    this.isSavingProgress = false,
    this.isResetting = false,
    this.isSavingFeedback = false,
    required this.onStageSelected,
    this.onLockedStageSelected,
    required this.onResetCampaign,
    this.onOpenTechTree,
    this.onOpenCodex,
    this.onOpenSettings,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final CampaignModifiers? campaignModifiers;
  final String? feedback;
  final bool isSavingProgress;
  final bool isResetting;
  final bool isSavingFeedback;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;
  final VoidCallback onResetCampaign;
  final VoidCallback? onOpenTechTree;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenSettings;

  @override
  State<WorldMapView> createState() => _WorldMapViewState();
}

class _WorldMapViewState extends State<WorldMapView> {
  bool get _isBusy => widget.isSavingProgress || widget.isResetting;

  String? get _effectiveFeedback {
    if (_isBusy && widget.feedback == null) {
      return widget.isResetting
          ? 'Resetting campaign…'
          : 'Saving campaign progress…';
    }
    return widget.feedback;
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final cleared = widget.stages
        .where((stage) => widget.progress.isCleared(stage.id))
        .length;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (widget.stages.isEmpty) {
            return _EmptySectorMap(
              uiTheme: uiTheme,
              feedback: _effectiveFeedback,
              hasChallengeBadge:
                  widget.campaignModifiers?.hasChallengeBadge == true,
              isBusy: _isBusy,
              isSavingFeedback: widget.isSavingFeedback,
              onOpenCodex: widget.onOpenCodex,
              onOpenTechTree: widget.onOpenTechTree,
              onResetCampaign: widget.onResetCampaign,
              onOpenSettings: widget.onOpenSettings,
            );
          }

          final sectorLayout = SectorMapLayout.fromStages(
            stages: widget.stages,
            size: constraints.biggest,
          );
          final nodeRects = {
            for (final stage in widget.stages)
              stage.id: sectorLayout.nodeRect(stage),
          };

          // At narrow widths the minimum non-overlapping column step makes the
          // plot wider than the viewport; wrap routes + nodes in a horizontal
          // scroll so adjacent targets stay tappable. Header, utility rail and
          // medal legend remain fixed above the scrollable plot.
          final contentWidth = sectorLayout.plotContentWidth;
          final needsScroll = contentWidth > constraints.biggest.width;

          Widget plotLayers = Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey('sector-route-layer'),
                  painter: _SectorRoutePainter(
                    routes: SectorMapLayout.routes(
                      widget.stages,
                      widget.progress,
                    ),
                    nodeRects: nodeRects,
                    uiTheme: uiTheme,
                  ),
                ),
              ),
              for (final stage in widget.stages)
                Positioned.fromRect(
                  rect: nodeRects[stage.id]!,
                  child: _IllustratedStageNode(
                    key: ValueKey('sector-stage-${stage.id}'),
                    stage: stage,
                    status: widget.progress.statusFor(stage),
                    result: widget.progress.resultFor(stage.id),
                    blueprintRecovered: widget.progress.isCleared(
                      OrionCampaign.stageOneId,
                    ),
                    isBusy: _isBusy,
                    onStageSelected: widget.onStageSelected,
                    onLockedStageSelected: widget.onLockedStageSelected,
                  ),
                ),
            ],
          );
          if (needsScroll) {
            plotLayers = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: constraints.biggest.height,
                child: plotLayers,
              ),
            );
          }

          return Stack(
            children: [
              const Positioned.fill(
                child: _WorldMapBackdrop(key: ValueKey('world-map-backdrop')),
              ),
              Positioned.fill(child: plotLayers),
              Positioned(
                left: SectorMapLayout.horizontalPadding,
                top: 8,
                right:
                    SectorMapLayout.railWidth +
                    SectorMapLayout.horizontalPadding,
                child: _SectorHeader(
                  cleared: cleared,
                  total: widget.stages.length,
                  isCampaignComplete: widget.progress.isCampaignComplete(
                    widget.stages,
                  ),
                  hasChallengeBadge:
                      widget.campaignModifiers?.hasChallengeBadge == true,
                  feedback: _effectiveFeedback,
                ),
              ),
              Positioned(
                top: 8,
                right: 4,
                width: SectorMapLayout.railWidth,
                child: _UtilityRail(
                  isBusy: _isBusy,
                  isSavingFeedback: widget.isSavingFeedback,
                  onOpenCodex: widget.onOpenCodex,
                  onOpenTechTree: widget.onOpenTechTree,
                  onResetCampaign: widget.onResetCampaign,
                  onOpenSettings: widget.onOpenSettings,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Approved star-chart scene art behind the plot, dimmed by a readability
/// scrim so routes and node labels stay legible. The art is square, so it is
/// cover-fitted (never stretched) into the portrait aperture.
class _WorldMapBackdrop extends StatelessWidget {
  const _WorldMapBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        // ponytail: square art, so any square child size cover-fits correctly;
        // recompute from the decoded image if the asset ever stops being 1:1.
        FittedBox(
          key: const ValueKey('world-map-backdrop-art'),
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox.square(
            dimension: 640,
            child: OrionAtlasSprite(
              art: OrionArt.scene(OrionSceneArt.worldMap),
              size: const Size.square(640),
            ),
          ),
        ),
        const DecoratedBox(
          key: ValueKey('world-map-scrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xAA05080D),
                Color(0x3305080D),
                Color(0x4405080D),
                Color(0x8805080D),
              ],
              stops: [0, 0.28, 0.72, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySectorMap extends StatelessWidget {
  const _EmptySectorMap({
    required this.uiTheme,
    required this.feedback,
    required this.hasChallengeBadge,
    required this.isBusy,
    required this.isSavingFeedback,
    required this.onOpenCodex,
    required this.onOpenTechTree,
    required this.onResetCampaign,
    required this.onOpenSettings,
  });

  final OrionUiTheme uiTheme;
  final String? feedback;
  final bool hasChallengeBadge;
  final bool isBusy;
  final bool isSavingFeedback;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenTechTree;
  final VoidCallback onResetCampaign;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: _WorldMapBackdrop(key: ValueKey('world-map-backdrop')),
        ),
        Center(
          child: CommandFrame(
            borderColor: uiTheme.frameSteel,
            child: Text(
              'No stages available',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: uiTheme.textPrimary),
            ),
          ),
        ),
        Positioned(
          left: SectorMapLayout.horizontalPadding,
          top: 8,
          right: SectorMapLayout.railWidth + SectorMapLayout.horizontalPadding,
          child: _SectorHeader(
            cleared: 0,
            total: 0,
            isCampaignComplete: false,
            hasChallengeBadge: hasChallengeBadge,
            feedback: feedback,
          ),
        ),
        Positioned(
          top: 8,
          right: 4,
          width: SectorMapLayout.railWidth,
          child: _UtilityRail(
            isBusy: isBusy,
            isSavingFeedback: isSavingFeedback,
            onOpenCodex: onOpenCodex,
            onOpenTechTree: onOpenTechTree,
            onResetCampaign: onResetCampaign,
            onOpenSettings: onOpenSettings,
          ),
        ),
      ],
    );
  }
}

class _SectorHeader extends StatelessWidget {
  const _SectorHeader({
    required this.cleared,
    required this.total,
    required this.isCampaignComplete,
    required this.hasChallengeBadge,
    required this.feedback,
  });

  final int cleared;
  final int total;
  final bool isCampaignComplete;
  final bool hasChallengeBadge;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // Lower-noise chrome: an unboxed floating title row over the backdrop
    // instead of a framed command plate (artboard 1f).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.public,
              size: 16,
              color: uiTheme.systemCyan,
              shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'ORION SECTOR',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: uiTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            ),
            Semantics(
              label: isCampaignComplete
                  ? 'Campaign Complete • $cleared/$total stages cleared'
                  : '$cleared of $total stages cleared',
              child: ExcludeSemantics(
                child: _HeaderBadge(
                  icon: isCampaignComplete
                      ? Icons.workspace_premium
                      : Icons.radar,
                  label: '$cleared/$total',
                  color: isCampaignComplete
                      ? uiTheme.creditGold
                      : uiTheme.systemCyan,
                ),
              ),
            ),
            if (hasChallengeBadge) ...[
              const SizedBox(width: 5),
              Semantics(
                label: 'Challenge Badge Earned - All side stages cleared',
                child: ExcludeSemantics(
                  child: Tooltip(
                    message: 'Challenge Badge Earned - All side stages cleared',
                    child: Icon(
                      Icons.stars_rounded,
                      size: 18,
                      color: uiTheme.systemViolet,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (feedback != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.sensors,
                size: 13,
                color: uiTheme.warningOrange,
                shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  feedback!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: uiTheme.textPrimary,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UtilityRail extends StatelessWidget {
  const _UtilityRail({
    required this.isBusy,
    required this.isSavingFeedback,
    required this.onOpenCodex,
    required this.onOpenTechTree,
    required this.onResetCampaign,
    required this.onOpenSettings,
  });

  final bool isBusy;
  final bool isSavingFeedback;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenTechTree;
  final VoidCallback onResetCampaign;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // Lower-noise chrome: the rail is a bare column of 48dp buttons over the
    // backdrop instead of a framed plate (artboard 1f has no utility rail).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onOpenCodex != null)
          _RailButton(
            tooltip: 'Codex',
            icon: Icons.menu_book_rounded,
            onPressed: isBusy ? null : onOpenCodex,
          ),
        if (onOpenTechTree != null)
          _RailButton(
            tooltip: 'Tech Tree',
            icon: Icons.account_tree_rounded,
            onPressed: isBusy ? null : onOpenTechTree,
          ),
        _RailButton(
          tooltip: 'Reset Campaign',
          icon: Icons.restart_alt_rounded,
          isDestructive: true,
          onPressed: isBusy ? null : onResetCampaign,
        ),
        if (onOpenSettings != null)
          _RailButton(
            tooltip: 'Settings',
            icon: Icons.settings_rounded,
            onPressed: isBusy || isSavingFeedback ? null : onOpenSettings,
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    final activeColor = isDestructive ? uiTheme.dangerRed : uiTheme.systemCyan;
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      color: enabled ? activeColor : uiTheme.textMuted,
      disabledColor: uiTheme.frameSteel,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 21,
        shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
      ),
    );
  }
}

class _IllustratedStageNode extends StatelessWidget {
  const _IllustratedStageNode({
    super.key,
    required this.stage,
    required this.status,
    required this.result,
    required this.blueprintRecovered,
    required this.isBusy,
    required this.onStageSelected,
    required this.onLockedStageSelected,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final StageResult? result;
  final bool blueprintRecovered;
  final bool isBusy;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final isAvailable = status == StageProgressStatus.unlocked;
    final statusColor = _statusColor(uiTheme, status, result);
    final rewardLabel = stageRewardLabel(
      stage,
      isCleared: status == StageProgressStatus.cleared,
    );
    final blueprintLabel = stage.id == OrionCampaign.stageOneId
        ? blueprintRecovered
              ? 'Blueprint • Recovered'
              : 'Blueprint • Locked'
        : null;
    final semanticsLabel = [
      stage.name,
      stage.isMainPath ? 'Main mission' : 'Optional mission',
      if (status == StageProgressStatus.cleared && result != null)
        'Medal • ${result!.medal.label}'
      else
        _statusLabel(status),
      ?rewardLabel,
      ?blueprintLabel,
    ].join(' • ');
    final onTap = _onTap(isLocked);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticsLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            splashColor: statusColor.withValues(alpha: 0.20),
            highlightColor: statusColor.withValues(alpha: 0.10),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                SizedBox(
                  key: ValueKey('stage-crest-${stage.id}'),
                  width: 56,
                  height: 58,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: _StageCrestAperture(
                          key: ValueKey('stage-status-ring-${stage.id}'),
                          stage: stage,
                          isLocked: isLocked,
                          isAvailable: isAvailable,
                          ringColor: statusColor,
                        ),
                      ),
                      if (result != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: _NodeGlyph(
                            key: ValueKey('stage-medal-${stage.id}'),
                            icon: medalIcon(result!.medal),
                            color: medalColor(uiTheme, result!.medal),
                          ),
                        ),
                      if (stage.reward != null)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: _NodeGlyph(
                            icon: rewardIcon(stage.reward!),
                            color: status == StageProgressStatus.cleared
                                ? uiTheme.naniteGreen
                                : uiTheme.textMuted,
                          ),
                        ),
                      if (blueprintLabel != null)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: _NodeGlyph(
                            icon: Icons.memory_rounded,
                            color: blueprintRecovered
                                ? uiTheme.systemViolet
                                : uiTheme.textMuted,
                          ),
                        ),
                      if (isAvailable)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: _NodeGlyph(
                            key: ValueKey('stage-open-${stage.id}'),
                            icon: Icons.play_arrow_rounded,
                            color: uiTheme.systemCyan,
                          ),
                        ),
                      if (isLocked)
                        Center(
                          child: Icon(
                            Icons.lock_rounded,
                            size: 17,
                            color: uiTheme.textPrimary,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Center(
                    child: Text(
                      stage.mapLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.15),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isLocked
                            ? uiTheme.textMuted
                            : uiTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback? _onTap(bool isLocked) {
    if (isBusy) return null;
    if (isLocked) {
      final callback = onLockedStageSelected;
      return callback == null ? null : () => callback(stage);
    }
    return () => onStageSelected(stage);
  }
}

/// Star-chart crest node: a circular aperture holding the square-cropped
/// stage key art, ringed by the integrated status/medal color (artboard 1f).
class _StageCrestAperture extends StatelessWidget {
  const _StageCrestAperture({
    super.key,
    required this.stage,
    required this.isLocked,
    required this.isAvailable,
    required this.ringColor,
  });

  final StageDefinition stage;
  final bool isLocked;
  final bool isAvailable;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final diameter = stage.isMainPath ? 52.0 : 42.0;
    final artSize = stage.isMainPath ? 48.0 : 38.0;
    Widget art = OrionAtlasSprite(
      art: OrionArt.stage(stage, crop: OrionStageArtCrop.mapSquare),
      size: Size.square(artSize),
    );
    if (isLocked) {
      art = Opacity(
        opacity: 0.38,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: art,
        ),
      );
    }

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: uiTheme.hullBlack,
        border: Border.all(
          color: isLocked
              ? uiTheme.frameSteel.withValues(alpha: 0.85)
              : ringColor,
          width: isAvailable ? 2.4 : 1.6,
        ),
        boxShadow: isAvailable
            ? [
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: ClipOval(child: Center(child: art)),
    );
  }
}

class _NodeGlyph extends StatelessWidget {
  const _NodeGlyph({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: uiTheme.voidBlack,
        border: Border.all(color: color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 10, color: color),
      ),
    );
  }
}

class _SectorRoutePainter extends CustomPainter {
  const _SectorRoutePainter({
    required this.routes,
    required this.nodeRects,
    required this.uiTheme,
  });

  final List<SectorRoute> routes;
  final Map<String, Rect> nodeRects;
  final OrionUiTheme uiTheme;

  @override
  void paint(Canvas canvas, Size size) {
    for (final route in routes) {
      final from = nodeRects[route.from.id]?.center;
      final to = nodeRects[route.to.id]?.center;
      if (from == null || to == null) continue;

      final color = route.isActive ? uiTheme.systemCyan : uiTheme.frameSteel;
      final glow = Paint()
        ..color = color.withValues(alpha: route.isActive ? 0.16 : 0.08)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7;
      final line = Paint()
        ..color = color.withValues(alpha: route.isActive ? 0.88 : 0.72)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = route.isOptional ? 1.5 : 2.2;

      if (route.isOptional) {
        _drawDashedLine(canvas, from, to, glow, dash: 5, gap: 5);
        _drawDashedLine(canvas, from, to, line, dash: 5, gap: 5);
      } else {
        canvas
          ..drawLine(from, to, glow)
          ..drawLine(from, to, line);
      }

      if (route.medal == StageMedal.gold) {
        canvas.drawCircle(to, 4, Paint()..color = uiTheme.creditGold);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SectorRoutePainter oldDelegate) {
    if (oldDelegate.uiTheme != uiTheme ||
        !mapEquals(oldDelegate.nodeRects, nodeRects) ||
        oldDelegate.routes.length != routes.length) {
      return true;
    }
    for (var index = 0; index < routes.length; index += 1) {
      final previous = oldDelegate.routes[index];
      final current = routes[index];
      if (previous.from.id != current.from.id ||
          previous.to.id != current.to.id ||
          previous.isOptional != current.isOptional ||
          previous.isActive != current.isActive ||
          previous.medal != current.medal) {
        return true;
      }
    }
    return false;
  }
}

void _drawDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  final delta = end - start;
  final distance = delta.distance;
  if (distance == 0) return;
  final direction = delta / distance;
  var travelled = 0.0;
  while (travelled < distance) {
    final segmentEnd = (travelled + dash).clamp(0.0, distance);
    canvas.drawLine(
      start + (direction * travelled),
      start + (direction * segmentEnd),
      paint,
    );
    travelled += dash + gap;
  }
}

Color _statusColor(
  OrionUiTheme uiTheme,
  StageProgressStatus status,
  StageResult? result,
) {
  if (status == StageProgressStatus.cleared && result != null) {
    return medalColor(uiTheme, result.medal);
  }
  return switch (status) {
    StageProgressStatus.cleared => uiTheme.naniteGreen,
    StageProgressStatus.unlocked => uiTheme.systemCyan,
    StageProgressStatus.locked => uiTheme.frameSteel,
  };
}

String _statusLabel(StageProgressStatus status) {
  return switch (status) {
    StageProgressStatus.cleared => 'Cleared',
    StageProgressStatus.unlocked => 'Open',
    StageProgressStatus.locked => 'Locked',
  };
}
