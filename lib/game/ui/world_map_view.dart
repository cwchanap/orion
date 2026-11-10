import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/stage_reward_label.dart';
import '../models/game_models.dart';
import '../rules/stage_modifier_rules.dart';
import 'campaign_presentation.dart';
import 'orion_atlas_sprite.dart';
import 'orion_primary_button.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'sector_map_layout.dart';

/// Headroom the chart reserves for the destination footer when deciding
/// how tall the plot can be. The footer's own text clamps at 1.3x so it
/// stays under this; if it ever grew past it the region would simply
/// scroll a little further — the reserve is a sizing heuristic, not a cap.
const double _footerReserveExtent = 224;

/// A star chart that bounces (iOS) or stretches (Android) reads as broken
/// chrome when nothing overflows — and even when it does, the clipped
/// nodes already signal "there is more". Edge drags stay inert.
class _NoOverscrollBehavior extends ScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class WorldMapView extends StatefulWidget {
  const WorldMapView({
    super.key,
    required this.stages,
    required this.progress,
    this.campaignModifiers,
    required this.feedback,
    this.isSavingProgress = false,
    this.isResetting = false,
    required this.onStageSelected,
    this.onLockedStageSelected,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final CampaignModifiers? campaignModifiers;
  final String? feedback;
  final bool isSavingProgress;
  final bool isResetting;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

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
    var mainTotal = 0;
    var mainCleared = 0;
    var optionalTotal = 0;
    var optionalCleared = 0;
    for (final stage in widget.stages) {
      final cleared = widget.progress.isCleared(stage.id);
      if (stage.isMainPath) {
        mainTotal += 1;
        if (cleared) {
          mainCleared += 1;
        }
      } else {
        optionalTotal += 1;
        if (cleared) {
          optionalCleared += 1;
        }
      }
    }
    final mainComplete = widget.progress.isCampaignComplete(widget.stages);
    // ALL SECTORS SECURED only makes sense when the campaign actually has
    // optional sectors to secure; a main-only campaign tops out at
    // CAMPAIGN COMPLETE.
    final fullySecured =
        optionalTotal > 0 &&
        mainCleared + optionalCleared == mainTotal + optionalTotal;

    if (widget.stages.isEmpty) {
      return SafeArea(
        child: _EmptySectorMap(
          uiTheme: uiTheme,
          feedback: _effectiveFeedback,
          hasChallengeBadge:
              widget.campaignModifiers?.hasChallengeBadge == true,
        ),
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          const Positioned.fill(
            child: _WorldMapBackdrop(key: ValueKey('world-map-backdrop')),
          ),
          Positioned.fill(
            // The header and utility rail stay fixed above the scrolling
            // region — they must never scroll away, because the transient
            // feedback line and the Codex/Tech Tree/Reset/Settings controls
            // have to be reachable at every scroll offset. (An earlier
            // revision put the header inside the scrollable flow, which
            // also let the feedback line resize the chart each time it
            // appeared.)
            //
            // The chart and the destination footer share ONE vertical
            // scroll region. The plot is sized to the space the footer
            // actually leaves — never less than SectorMapLayout's minimum
            // content height — so the single scroll offset carries the
            // player from the top stages all the way to the footer. There
            // is deliberately no second, nested vertical scrollable for
            // drags to get captured by.
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SectorMapLayout.horizontalPadding,
                    8,
                    SectorMapLayout.horizontalPadding,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectorHeader(
                        mainCleared: mainCleared,
                        mainTotal: mainTotal,
                        optionalCleared: optionalCleared,
                        optionalTotal: optionalTotal,
                        mainComplete: mainComplete,
                        fullySecured: fullySecured,
                        hasChallengeBadge:
                            widget.campaignModifiers?.hasChallengeBadge == true,
                        feedback: _effectiveFeedback,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, region) {
                      final regionSize = region.biggest;
                      final plotHeight = math.max(
                        regionSize.height - _footerReserveExtent,
                        SectorMapLayout.fromStages(
                          stages: widget.stages,
                          size: Size(regionSize.width, 0),
                        ).minContentHeight,
                      );
                      final sectorLayout = SectorMapLayout.fromStages(
                        stages: widget.stages,
                        size: Size(regionSize.width, plotHeight),
                      );
                      final nodeRects = {
                        for (final stage in widget.stages)
                          stage.id: sectorLayout.nodeRect(stage),
                      };

                      // The recommended-stage pulse is the same campaign
                      // signal the destination card and the title's Continue
                      // read, computed once here so node, route accent, and
                      // footer never disagree.
                      final nextStage = widget.progress.recommendedStage(
                        widget.stages,
                      );
                      // At narrow widths the minimum non-overlapping column
                      // step makes the plot wider than the viewport; wrap
                      // routes + nodes in a horizontal scroll so adjacent
                      // targets stay tappable. Vertical overflow is handled
                      // by the region's own scroll instead.
                      final contentWidth = sectorLayout.plotContentWidth;
                      final plotLayers = Stack(
                        key: const ValueKey('world-map-plot'),
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              key: const ValueKey('sector-route-layer'),
                              painter: SectorRoutePainter(
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
                                isNext:
                                    stage.id == nextStage?.id &&
                                    widget.progress.statusFor(stage) ==
                                        StageProgressStatus.unlocked,
                                isBusy: _isBusy,
                                onStageSelected: widget.onStageSelected,
                                onLockedStageSelected:
                                    widget.onLockedStageSelected,
                              ),
                            ),
                        ],
                      );
                      return ScrollConfiguration(
                        behavior: const _NoOverscrollBehavior(),
                        child: SingleChildScrollView(
                          key: const ValueKey('world-map-plot-viewport'),
                          primary: false,
                          physics: const ClampingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: regionSize.height,
                            ),
                            child: Column(
                              // Slack between plot and footer is invisible
                              // over the backdrop; pinning them apart keeps
                              // the footer at the region's bottom edge when
                              // nothing scrolls, and at the end of the
                              // scrollable content when it does.
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                SizedBox(
                                  height: plotHeight,
                                  child: contentWidth > regionSize.width
                                      ? SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: contentWidth,
                                            height: plotHeight,
                                            child: plotLayers,
                                          ),
                                        )
                                      : plotLayers,
                                ),
                                Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 150,
                                  ),
                                  alignment: Alignment.bottomCenter,
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    12,
                                  ),
                                  child: _MissionDestination(
                                    stages: widget.stages,
                                    progress: widget.progress,
                                    campaignModifiers: widget.campaignModifiers,
                                    onStageSelected: _isBusy
                                        ? null
                                        : widget.onStageSelected,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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
        Image.asset(
          'assets/images/reactor_rim_ui/backdrops/map-room.png',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
        // ponytail: square art, so any square child size cover-fits correctly;
        // recompute from the decoded image if the asset ever stops being 1:1.
        Opacity(
          key: const ValueKey('world-map-backdrop-art'),
          opacity: 0.28,
          child: FittedBox(
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
        ),
        const DecoratedBox(
          key: ValueKey('world-map-scrim'),
          decoration: BoxDecoration(gradient: orionMapScrim),
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
  });

  final OrionUiTheme uiTheme;
  final String? feedback;
  final bool hasChallengeBadge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: _WorldMapBackdrop(key: ValueKey('world-map-backdrop')),
        ),
        Center(
          child: OrionSurface(
            role: OrionSurfaceRole.card,
            child: OrionText.micro(
              'No stages available',
              color: uiTheme.textMuted,
              size: 11,
            ),
          ),
        ),
        Positioned(
          left: SectorMapLayout.horizontalPadding,
          top: 8,
          right: SectorMapLayout.horizontalPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectorHeader(
                mainCleared: 0,
                mainTotal: 0,
                optionalCleared: 0,
                optionalTotal: 0,
                mainComplete: false,
                fullySecured: false,
                hasChallengeBadge: hasChallengeBadge,
                feedback: feedback,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectorHeader extends StatelessWidget {
  const _SectorHeader({
    required this.mainCleared,
    required this.mainTotal,
    required this.optionalCleared,
    required this.optionalTotal,
    required this.mainComplete,
    required this.fullySecured,
    required this.hasChallengeBadge,
    required this.feedback,
  });

  final int mainCleared;
  final int mainTotal;
  final int optionalCleared;
  final int optionalTotal;
  final bool mainComplete;
  final bool fullySecured;
  final bool hasChallengeBadge;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // No "optional 0 of 0": campaigns without optional stages report only
    // their main progress.
    final optionalClause = optionalTotal > 0
        ? ', optional $optionalCleared of $optionalTotal stages'
        : '';
    final summary = mainComplete
        ? 'Campaign complete. Main $mainCleared of $mainTotal stages'
              '$optionalClause.'
        : 'Main $mainCleared of $mainTotal stages cleared';
    // The visible OPTIONAL badge is redundant at full clear (ALL SECTORS
    // SECURED + Challenge Badge already say so), but the summary still
    // reports its count.
    final showOptionalBadge = mainComplete && optionalCleared < optionalTotal;
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
              child: OrionTitle(
                'Orion Sector',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: uiTheme.textPrimary,
              ),
            ),
            Semantics(
              label: summary,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderBadge(
                      icon: mainComplete
                          ? Icons.workspace_premium
                          : Icons.radar,
                      label: 'MAIN $mainCleared/$mainTotal',
                      color: mainComplete
                          ? uiTheme.creditGold
                          : uiTheme.systemCyan,
                    ),
                    if (showOptionalBadge) ...[
                      const SizedBox(width: 5),
                      _HeaderBadge(
                        icon: Icons.alt_route_rounded,
                        label: 'OPTIONAL $optionalCleared/$optionalTotal',
                        color: uiTheme.systemViolet,
                      ),
                    ],
                  ],
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
        if (mainComplete) ...[
          const SizedBox(height: 4),
          // Decorative completion line: the badge-group Semantics already
          // announces completion, so this row is excluded from semantics.
          ExcludeSemantics(
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 13,
                  color: uiTheme.creditGold,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    fullySecured ? 'ALL SECTORS SECURED' : 'CAMPAIGN COMPLETE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrionTypography.microLabel(
                      color: uiTheme.creditGold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // The feedback row occupies a fixed-height slot whether or not a
        // message is showing: a transient line used to resize the header —
        // and therefore shift every stage node and reset the chart's scroll
        // offset — each time it appeared or cleared.
        const SizedBox(height: 4),
        SizedBox(
          height: 16,
          child: feedback == null
              ? null
              : Row(
                  children: [
                    Icon(
                      Icons.sensors,
                      size: 13,
                      color: uiTheme.warningOrange,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        feedback!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Same 1.3x dense-map clamp as the badges so the slot
                        // stays a fixed height at any system text scale.
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                        style: OrionTypography.microLabel(
                          color: uiTheme.textMuted,
                          // Tight leading keeps the clamped line inside the
                          // fixed 16px slot at any system text scale.
                        ).copyWith(height: 1.2),
                      ),
                    ),
                  ],
                ),
        ),
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
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              style: OrionTypography.readout(size: 11, color: color),
            ),
          ],
        ),
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
    required this.isNext,
    required this.isBusy,
    required this.onStageSelected,
    required this.onLockedStageSelected,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final StageResult? result;

  /// The campaign recommendation's unlocked marker: bigger orb, pulse rings,
  /// and the NEXT flag (artboard 02's .node.next).
  final bool isNext;
  final bool isBusy;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final isAvailable = status == StageProgressStatus.unlocked;
    // Optional missions read violet while they wait to be cleared; a medal
    // still wins once the stage is beaten.
    final statusColor = isAvailable && !stage.isMainPath
        ? uiTheme.systemViolet
        : _statusColor(uiTheme, status, result);
    final nameColor = isLocked ? uiTheme.textMuted : statusColor;
    final rewardLabel = stageRewardLabel(
      stage,
      isCleared: status == StageProgressStatus.cleared,
    );
    // A committed clear is the only path to owning the stage's blueprint,
    // so the node's own cleared status is the Recovered/Locked signal.
    final blueprintRecovered = status == StageProgressStatus.cleared;
    final blueprintLabel = stage.blueprint == null
        ? null
        : blueprintRecovered
        ? 'Blueprint • Recovered'
        : 'Blueprint • Locked';
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
                  width: 72,
                  height: 66,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (isNext) const Center(child: _NextPulseRings()),
                      Center(
                        child: _StageCrestAperture(
                          key: ValueKey('stage-status-ring-${stage.id}'),
                          stage: stage,
                          isLocked: isLocked,
                          isNext: isNext,
                          ringColor: statusColor,
                        ),
                      ),
                      if (isNext)
                        Align(
                          alignment: const Alignment(0, -1.35),
                          child: _NextFlag(),
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
                            color: statusColor,
                          ),
                        ),
                      if (isLocked)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: _LockBadge(uiTheme: uiTheme),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stage.mapLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.15),
                        // The caption slot under the crest is ~26px: label +
                        // pips must fit inside it at the 1.15x clamp.
                        style: OrionTypography.microLabel(
                          color: nameColor,
                        ).copyWith(height: 1.2),
                      ),
                      if (result != null)
                        Padding(
                          key: ValueKey('stage-pips-${stage.id}'),
                          padding: const EdgeInsets.only(top: 2),
                          child: _MedalPips(
                            medal: result!.medal,
                            uiTheme: uiTheme,
                          ),
                        ),
                    ],
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
/// stage key art, ringed by the integrated status/medal color. The
/// recommendation's node grows to the artboard's 80px hero orb; main
/// missions share the 68px footprint and optional side routes read smaller.
class _StageCrestAperture extends StatelessWidget {
  const _StageCrestAperture({
    super.key,
    required this.stage,
    required this.isLocked,
    required this.isNext,
    required this.ringColor,
  });

  final StageDefinition stage;
  final bool isLocked;
  final bool isNext;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // Main missions share the 68px footprint and the recommendation's hero
    // orb grows to 80; optional side routes read as the kit's smaller
    // circles.
    final diameter = isNext
        ? (stage.isMainPath ? 80.0 : 72.0)
        : (stage.isMainPath ? 68.0 : 56.0);
    final artSize = diameter - 8;
    Widget art = OrionAtlasSprite(
      art: OrionArt.crestFor(stage),
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
              ? uiTheme.frameSteel.withValues(alpha: 0.75)
              : ringColor,
          width: isNext ? 3 : 2,
        ),
        boxShadow: isLocked
            ? const []
            : [
                BoxShadow(
                  color: ringColor.withValues(alpha: isNext ? 0.5 : 0.3),
                  blurRadius: isNext ? 18 : 12,
                  spreadRadius: isNext ? 1 : 0,
                ),
              ],
      ),
      child: ClipOval(child: Center(child: art)),
    );
  }
}

/// The static echo of the artboard's next-node pulse: two low-alpha rings
/// expanding past the orb. Kept non-animated — the live pulse exists in CSS
/// only, and a perpetual chart animation would read as a live countdown.
class _NextPulseRings extends StatelessWidget {
  const _NextPulseRings();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return SizedBox.square(
      dimension: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final spec in const [(132.0, 0.12), (108.0, 0.2)])
            Container(
              width: spec.$1,
              height: spec.$1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: uiTheme.systemCyan.withValues(alpha: spec.$2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The small NEXT flag the recommendation wears above its orb (artboard 02).
class _NextFlag extends StatelessWidget {
  const _NextFlag();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: orionDeckBlack.withValues(alpha: 0.92),
        border: Border.all(color: uiTheme.systemCyan.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          'NEXT',
          style: OrionTypography.microLabel(
            color: uiTheme.systemCyan,
          ).copyWith(letterSpacing: 2.4, shadows: const []),
        ),
      ),
    );
  }
}

/// Locked nodes dim their crest; the kit's badge circle makes the state read
/// without leaning on the grayscale alone.
class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.uiTheme});

  final OrionUiTheme uiTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: orionDeckBlack,
        border: Border.all(color: uiTheme.frameSteel),
      ),
      child: Icon(Icons.lock_rounded, size: 12, color: uiTheme.textMuted),
    );
  }
}

/// The three medal pips under a cleared node's name: a slot per rank, filled
/// in the earned medal's own color up to the medal held.
class _MedalPips extends StatelessWidget {
  const _MedalPips({required this.medal, required this.uiTheme});

  final StageMedal medal;
  final OrionUiTheme uiTheme;

  @override
  Widget build(BuildContext context) {
    final earned = medal.rank;
    final slotColors = [
      uiTheme.naniteGreen,
      uiTheme.medalSilver,
      uiTheme.creditGold,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i += 1)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < earned ? slotColors[i] : orionEmptyPip,
            ),
          ),
      ],
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

class SectorRoutePainter extends CustomPainter {
  const SectorRoutePainter({
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
      final from = nodeRects[route.from.id]?.topCenter.translate(0, 38);
      final to = nodeRects[route.to.id]?.topCenter.translate(0, 38);
      if (from == null || to == null) continue;

      // Route state mirrors the kit chart: a cleared destination draws its
      // path solid gold, an open optional violet-dashed, an open main-path
      // link cyan-dashed with a glow underpass, and a locked one a faint
      // steel dash.
      final cleared = route.medal != null;
      final color = cleared
          ? uiTheme.creditGold
          : !route.isActive
          ? uiTheme.frameSteel
          : route.isOptional
          ? uiTheme.systemViolet
          : uiTheme.systemCyan;
      final glow = Paint()
        ..color = color.withValues(alpha: route.isActive ? 0.30 : 0.08)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 6;
      final line = Paint()
        ..color = color.withValues(alpha: route.isActive ? 0.9 : 0.7)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = cleared
            ? 3
            : route.isOptional
            ? 2.5
            : route.isActive
            ? 3
            : 2;

      if (cleared) {
        canvas.drawLine(from, to, glow);
        canvas.drawLine(from, to, line);
      } else if (route.isOptional) {
        _drawDashedLine(canvas, from, to, glow, dash: 7, gap: 6);
        _drawDashedLine(canvas, from, to, line, dash: 7, gap: 6);
      } else if (route.isActive) {
        _drawDashedLine(canvas, from, to, glow, dash: 9, gap: 6);
        _drawDashedLine(canvas, from, to, line, dash: 9, gap: 6);
      } else {
        _drawDashedLine(canvas, from, to, line, dash: 4, gap: 7);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SectorRoutePainter oldDelegate) {
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

/// The next playable mission, using the same campaign status as its map node
/// — and the same recommendation helper the title's Continue reads.
class _MissionDestination extends StatelessWidget {
  const _MissionDestination({
    required this.stages,
    required this.progress,
    required this.campaignModifiers,
    required this.onStageSelected,
  });
  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final CampaignModifiers? campaignModifiers;
  final ValueChanged<StageDefinition>? onStageSelected;

  @override
  Widget build(BuildContext context) {
    final stage = progress.recommendedStage(stages);
    if (stage == null) return const SizedBox.shrink();
    final theme = OrionUiTheme.of(context);
    final status = progress.statusFor(stage);
    final qualifier = status == StageProgressStatus.unlocked
        ? (stage.isMainPath ? 'NEXT MAIN' : 'OPTIONAL')
        : 'REPLAY';
    final hull = StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth:
          campaignModifiers?.adjustedStartingBaseHealth ??
          GameBalance.initialBaseHealth,
      stageModifiers: stage.modifiers,
    );
    return OrionSurface(
      role: OrionSurfaceRole.sheet,
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Semantics(
        button: true,
        label: 'Briefing for ${stage.name}',
        hint: qualifier,
        enabled: onStageSelected != null,
        excludeSemantics: true,
        onTap: onStageSelected == null ? null : () => onStageSelected!(stage),
        child: InkWell(
          onTap: onStageSelected == null ? null : () => onStageSelected!(stage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: orionCrestEdge),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: OrionAtlasSprite(
                        art: OrionArt.stage(
                          stage,
                          crop: OrionStageArtCrop.mapSquare,
                        ),
                        size: const Size.square(80),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SECTOR ${(stages.indexOf(stage) + 1).toString().padLeft(2, '0')} · $qualifier',
                          // Two clamped lines, not one unclamped: at 3x
                          // system text the single line ellipsized the
                          // qualifier (the informative part) inside the
                          // ~110px column.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textScaler: MediaQuery.textScalerOf(
                            context,
                          ).clamp(maxScaleFactor: 1.3),
                          style: OrionTypography.microLabel(
                            color: theme.systemCyan,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          stage.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textScaler: MediaQuery.textScalerOf(
                            context,
                          ).clamp(maxScaleFactor: 1.3),
                          style: OrionTypography.readout(
                            size: 20,
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _DestinationChip(
                              icon: Icons.waves,
                              value: '${stage.waves.length}',
                              color: theme.systemCyan,
                            ),
                            _DestinationChip(
                              icon: Icons.shield_outlined,
                              value: '$hull',
                              color: theme.systemCyan,
                            ),
                            if (stage.modifiers.isNotEmpty)
                              _DestinationChip(
                                icon: Icons.bolt_rounded,
                                value: StageModifierMetadata.forModifier(
                                  stage.modifiers.first,
                                ).title,
                                color: theme.warningOrange,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OrionPrimaryButton(
                label: 'Deploy',
                icon: Icons.play_arrow_rounded,
                onPressed: onStageSelected == null
                    ? null
                    : () => onStageSelected!(stage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One fact pill in the destination card's chip row (waves, hull, modifier).
class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: OrionTypography.readout(size: 10, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
