import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../assets/game_boss_sheet.dart';
import '../assets/game_terrain.dart';
import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_reward_label.dart';
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
  bool _didPrecacheMapArt = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheMapArt) return;
    _didPrecacheMapArt = true;
    precacheImage(const AssetImage(GameTerrain.assetPath), context).ignore();
    Flame.images.load(GameBossSheet.fileName).ignore();
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

          return Stack(
            children: [
              const Positioned.fill(child: _SectorBackdrop()),
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
                  rect: sectorLayout.nodeRect(stage),
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
              const Positioned(
                left: SectorMapLayout.horizontalPadding,
                bottom: 8,
                child: _MedalLegend(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectorBackdrop extends StatelessWidget {
  const _SectorBackdrop();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          GameTerrain.assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: uiTheme.voidBlack,
            child: Icon(Icons.public_off, color: uiTheme.frameSteel, size: 48),
          ),
        ),
        ColoredBox(color: uiTheme.voidBlack.withValues(alpha: 0.64)),
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
        const Positioned.fill(child: _SectorBackdrop()),
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
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      color: uiTheme.hullBlack.withValues(alpha: 0.94),
      borderColor: isCampaignComplete ? uiTheme.creditGold : uiTheme.systemCyan,
      emphasized: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 16, color: uiTheme.systemCyan),
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
                      message:
                          'Challenge Badge Earned - All side stages cleared',
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
                Icon(Icons.sensors, size: 13, color: uiTheme.warningOrange),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    feedback!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: uiTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
    final uiTheme = OrionUiTheme.of(context);
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      color: uiTheme.hullBlack.withValues(alpha: 0.94),
      borderColor: uiTheme.frameSteel,
      child: Column(
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
      ),
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
      icon: Icon(icon, size: 21),
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
      excludeSemantics: true,
      child: Tooltip(
        message: semanticsLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            splashColor: statusColor.withValues(alpha: 0.20),
            highlightColor: statusColor.withValues(alpha: 0.10),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                SizedBox(
                  width: 56,
                  height: 58,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: _StageArtAperture(
                          stage: stage,
                          isLocked: isLocked,
                          statusColor: statusColor,
                        ),
                      ),
                      if (result != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: _NodeGlyph(
                            icon: _medalIcon(result!.medal),
                            color: _medalColor(uiTheme, result!.medal),
                          ),
                        ),
                      if (stage.reward != null)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: _NodeGlyph(
                            icon: _rewardIcon(stage.reward!),
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
                      if (isLocked)
                        Center(
                          child: Icon(
                            Icons.lock_rounded,
                            size: 17,
                            color: uiTheme.textPrimary,
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

class _StageArtAperture extends StatelessWidget {
  const _StageArtAperture({
    required this.stage,
    required this.isLocked,
    required this.statusColor,
  });

  final StageDefinition stage;
  final bool isLocked;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    Widget art = OrionAtlasSprite(
      art: OrionArt.stage(stage),
      size: Size.square(stage.isMainPath ? 48 : 34),
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

    if (!stage.isMainPath) {
      return SizedBox.square(
        dimension: 54,
        child: Center(
          child: Transform.rotate(
            key: ValueKey('optional-stage-aperture-${stage.id}'),
            angle: math.pi / 4,
            child: SizedBox.square(
              dimension: 38,
              child: CommandFrame(
                padding: const EdgeInsets.all(2),
                color: uiTheme.hullBlack,
                borderColor: statusColor,
                emphasized: true,
                chamfer: 4,
                child: Transform.rotate(angle: -math.pi / 4, child: art),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox.square(
      dimension: 54,
      child: CommandFrame(
        padding: const EdgeInsets.all(2),
        color: uiTheme.hullBlack,
        borderColor: statusColor,
        emphasized: true,
        chamfer: 9,
        child: art,
      ),
    );
  }
}

class _NodeGlyph extends StatelessWidget {
  const _NodeGlyph({required this.icon, required this.color});

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

class _MedalLegend extends StatelessWidget {
  const _MedalLegend();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      color: uiTheme.hullBlack.withValues(alpha: 0.90),
      borderColor: uiTheme.frameSteel,
      chamfer: 6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendGlyph(
            tooltip: 'Clear medal',
            icon: Icons.check_circle,
            color: uiTheme.naniteGreen,
          ),
          const SizedBox(width: 7),
          _LegendGlyph(
            tooltip: 'Silver medal',
            icon: Icons.military_tech,
            color: uiTheme.textMuted,
          ),
          const SizedBox(width: 7),
          _LegendGlyph(
            tooltip: 'Gold medal',
            icon: Icons.emoji_events,
            color: uiTheme.creditGold,
          ),
        ],
      ),
    );
  }
}

class _LegendGlyph extends StatelessWidget {
  const _LegendGlyph({
    required this.tooltip,
    required this.icon,
    required this.color,
  });

  final String tooltip;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 15, color: color),
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
    return _medalColor(uiTheme, result.medal);
  }
  return switch (status) {
    StageProgressStatus.cleared => uiTheme.naniteGreen,
    StageProgressStatus.unlocked => uiTheme.systemCyan,
    StageProgressStatus.locked => uiTheme.frameSteel,
  };
}

Color _medalColor(OrionUiTheme uiTheme, StageMedal medal) {
  return switch (medal) {
    StageMedal.clear => uiTheme.naniteGreen,
    StageMedal.silver => uiTheme.textMuted,
    StageMedal.gold => uiTheme.creditGold,
  };
}

IconData _medalIcon(StageMedal medal) {
  return switch (medal) {
    StageMedal.clear => Icons.check_circle,
    StageMedal.silver => Icons.military_tech,
    StageMedal.gold => Icons.emoji_events,
  };
}

IconData _rewardIcon(CampaignReward reward) {
  return switch (reward) {
    CampaignReward.bonusGold => Icons.savings_rounded,
    CampaignReward.bonusHealth => Icons.favorite_rounded,
    CampaignReward.challengeBadge => Icons.stars_rounded,
  };
}

String _statusLabel(StageProgressStatus status) {
  return switch (status) {
    StageProgressStatus.cleared => 'Cleared',
    StageProgressStatus.unlocked => 'Open',
    StageProgressStatus.locked => 'Locked',
  };
}
