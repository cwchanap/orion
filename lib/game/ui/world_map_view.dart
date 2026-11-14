import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/stage_reward_label.dart';
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
const double _footerReserveExtent = 200;

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
    this.embeddedInMenuShell = false,
    required this.onStageSelected,
    this.onLockedStageSelected,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final CampaignModifiers? campaignModifiers;
  final String? feedback;
  final bool isSavingProgress;
  final bool isResetting;
  final bool embeddedInMenuShell;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

  @override
  State<WorldMapView> createState() => _WorldMapViewState();
}

class _WorldMapViewState extends State<WorldMapView> {
  final ScrollController _plotController = ScrollController();
  bool _hasMoreBelow = false;

  @override
  void initState() {
    super.initState();
    _plotController.addListener(_updateScrollCue);
  }

  void _updateScrollCue() {
    if (!_plotController.hasClients) return;
    final hasMore = _plotController.position.extentAfter > 1;
    if (hasMore != _hasMoreBelow) {
      setState(() => _hasMoreBelow = hasMore);
    }
  }

  @override
  void dispose() {
    _plotController
      ..removeListener(_updateScrollCue)
      ..dispose();
    super.dispose();
  }

  bool get _isBusy => widget.isSavingProgress || widget.isResetting;

  String? get _effectiveFeedback {
    if (_isBusy && widget.feedback == null) {
      return widget.isResetting
          ? 'Resetting campaign…'
          : 'Saving campaign progress…';
    }
    return widget.feedback;
  }

  VoidCallback? _stageTap(StageDefinition stage) {
    if (_isBusy) return null;
    if (widget.progress.statusFor(stage) == StageProgressStatus.locked) {
      final callback = widget.onLockedStageSelected;
      return callback == null ? null : () => callback(stage);
    }
    return () => widget.onStageSelected(stage);
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
          showTitle: !widget.embeddedInMenuShell,
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
                        showTitle: !widget.embeddedInMenuShell,
                        mainCleared: mainCleared,
                        mainTotal: mainTotal,
                        optionalCleared: optionalCleared,
                        optionalTotal: optionalTotal,
                        mainComplete: mainComplete,
                        fullySecured: fullySecured,
                        hasChallengeBadge:
                            widget.campaignModifiers?.hasChallengeBadge == true,
                        feedback: _effectiveFeedback,
                        showScrollCue: _hasMoreBelow,
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
                        SectorMapLayout.minContentHeightFor(widget.stages),
                      );
                      final sectorLayout = SectorMapLayout.fromStages(
                        stages: widget.stages,
                        size: Size(regionSize.width, plotHeight),
                      );
                      final recommendedStage = widget.progress.recommendedStage(
                        widget.stages,
                      );
                      final recommendedStageId = recommendedStage?.id;
                      final nodeRects = {
                        for (final stage in widget.stages)
                          stage.id: sectorLayout.nodeRect(stage),
                      };

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
                            Positioned(
                              left: nodeRects[stage.id]!.left,
                              top: nodeRects[stage.id]!.top,
                              width: nodeRects[stage.id]!.width,
                              height: nodeRects[stage.id]!.height,
                              child: _IllustratedStageNode(
                                key: ValueKey('sector-stage-${stage.id}'),
                                stage: stage,
                                status: widget.progress.statusFor(stage),
                                result: widget.progress.resultFor(stage.id),
                                isNext: recommendedStageId == stage.id,
                                onTap: _stageTap(stage),
                              ),
                            ),
                          // Captions are a second pass painted after every
                          // crest, so a chip's own pixels always hit-test
                          // before a neighbor's crest art and never get
                          // stolen by an overlapping node box.
                          for (final stage in widget.stages)
                            Positioned(
                              left: nodeRects[stage.id]!.left - 20,
                              top: nodeRects[stage.id]!.top + 70,
                              width: nodeRects[stage.id]!.width + 40,
                              child: _StageCaption(
                                key: ValueKey('sector-caption-${stage.id}'),
                                stage: stage,
                                status: widget.progress.statusFor(stage),
                                result: widget.progress.resultFor(stage.id),
                                isNext: recommendedStageId == stage.id,
                                onTap: _stageTap(stage),
                              ),
                            ),
                        ],
                      );
                      final scroll = NotificationListener<ScrollMetricsNotification>(
                        onNotification: (notification) {
                          if (notification.depth == 0) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _updateScrollCue();
                            });
                          }
                          return false;
                        },
                        child: ScrollConfiguration(
                          behavior: const _NoOverscrollBehavior(),
                          child: SingleChildScrollView(
                            key: const ValueKey('world-map-plot-viewport'),
                            controller: _plotController,
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                                      12,
                                      14,
                                      10,
                                    ),
                                    child: _MissionDestination(
                                      stage: recommendedStage,
                                      sectorNumber: recommendedStage == null
                                          ? 0
                                          : (recommendedStage.mainPathOrder ??
                                                widget.stages.indexOf(
                                                      recommendedStage,
                                                    ) +
                                                    1),
                                      progress: widget.progress,
                                      campaignModifiers:
                                          widget.campaignModifiers ??
                                          CampaignModifiers.empty,
                                      onStageSelected: _isBusy
                                          ? null
                                          : widget.onStageSelected,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      return scroll;
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
        // ponytail: square art, so any square child size cover-fits correctly;
        // recompute from the decoded image if the asset ever stops being 1:1.
        Opacity(
          key: const ValueKey('world-map-backdrop-art'),
          opacity: 1,
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
          decoration: BoxDecoration(gradient: orionMapVignette),
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
    required this.showTitle,
    required this.feedback,
    required this.hasChallengeBadge,
  });

  final OrionUiTheme uiTheme;
  final bool showTitle;
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
          child: _SectorHeader(
            showTitle: showTitle,
            mainCleared: 0,
            mainTotal: 0,
            optionalCleared: 0,
            optionalTotal: 0,
            mainComplete: false,
            fullySecured: false,
            hasChallengeBadge: hasChallengeBadge,
            feedback: feedback,
          ),
        ),
      ],
    );
  }
}

class _SectorHeader extends StatelessWidget {
  const _SectorHeader({
    required this.showTitle,
    required this.mainCleared,
    required this.mainTotal,
    required this.optionalCleared,
    required this.optionalTotal,
    required this.mainComplete,
    required this.fullySecured,
    required this.hasChallengeBadge,
    required this.feedback,
    this.showScrollCue = false,
  });

  final bool showTitle;
  final int mainCleared;
  final int mainTotal;
  final int optionalCleared;
  final int optionalTotal;
  final bool mainComplete;
  final bool fullySecured;
  final bool hasChallengeBadge;
  final String? feedback;
  final bool showScrollCue;

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
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showTitle) ...[
              Icon(
                Icons.public,
                size: 16,
                color: uiTheme.systemCyan,
                shadows: [Shadow(color: uiTheme.voidBlack, blurRadius: 6)],
              ),
              OrionTitle(
                'Sector Map',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                color: uiTheme.textPrimary,
              ),
            ],
            Semantics(
              label: summary,
              child: ExcludeSemantics(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 4,
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
                    if (showOptionalBadge)
                      _HeaderBadge(
                        icon: Icons.alt_route_rounded,
                        label: 'OPTIONAL $optionalCleared/$optionalTotal',
                        color: uiTheme.systemViolet,
                      ),
                  ],
                ),
              ),
            ),
            if (hasChallengeBadge)
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
                  shadows: [Shadow(color: uiTheme.voidBlack, blurRadius: 6)],
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
          child: feedback != null
              ? Row(
                  children: [
                    Icon(
                      Icons.sensors,
                      size: 13,
                      color: uiTheme.warningOrange,
                      shadows: [
                        Shadow(color: uiTheme.voidBlack, blurRadius: 6),
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
                        ),
                      ),
                    ),
                  ],
                )
              : showScrollCue
              ? ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        Icons.keyboard_double_arrow_down,
                        size: 15,
                        color: uiTheme.systemCyan,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'SWIPE UP FOR MISSION',
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                        style: OrionTypography.microLabel(
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
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

// Lower-noise chrome: the rail is a bare column of 48dp buttons over the
// backdrop instead of a framed plate (artboard 1f has no utility rail).
class _IllustratedStageNode extends StatelessWidget {
  const _IllustratedStageNode({
    super.key,
    required this.stage,
    required this.status,
    required this.result,
    required this.isNext,
    required this.onTap,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final StageResult? result;

  final bool isNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final isCleared = status == StageProgressStatus.cleared;
    final isOpen = status == StageProgressStatus.unlocked;
    final isRecommended = isNext && isOpen;
    final isSideOpen = isOpen && !isRecommended && !stage.isMainPath;
    final statusColor = _stageStatusColor(
      uiTheme,
      stage,
      status,
      result,
      isNext,
    );
    final rewardLabel = stageRewardLabel(stage, isCleared: isCleared);
    // A committed clear is the only path to owning the stage's blueprint,
    // so the node's own cleared status is the Recovered/Locked signal.
    final blueprintRecovered = isCleared;
    final blueprintLabel = stage.blueprint == null
        ? null
        : blueprintRecovered
        ? 'Blueprint • Recovered'
        : 'Blueprint • Locked';
    final semanticsLabel = [
      stage.name,
      stage.isMainPath ? 'Main mission' : 'Optional mission',
      if (isCleared && result != null)
        'Medal • ${result!.medal.label}'
      else
        _statusLabel(status),
      ?rewardLabel,
      ?blueprintLabel,
    ].join(' • ');

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
              children: [
                SizedBox(
                  height: 76,
                  child: Stack(
                    key: ValueKey('stage-crest-${stage.id}'),
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      if (isRecommended) ...const [
                        Center(
                          child: OverflowBox(
                            maxWidth: 108,
                            maxHeight: 108,
                            child: _PulseRing(diameter: 108, width: 2),
                          ),
                        ),
                        Center(
                          child: OverflowBox(
                            maxWidth: 132,
                            maxHeight: 132,
                            child: _PulseRing(diameter: 132, width: 1.5),
                          ),
                        ),
                      ],
                      Center(
                        child: OverflowBox(
                          maxWidth: 80,
                          maxHeight: 80,
                          child: _StageOrb(
                            key: ValueKey('stage-status-ring-${stage.id}'),
                            stage: stage,
                            isLocked: isLocked,
                            isRecommended: isRecommended,
                            isSideOpen: isSideOpen,
                            ringColor: statusColor,
                          ),
                        ),
                      ),
                      if (isRecommended)
                        Positioned(
                          top: -24,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _NextFlag(
                                key: ValueKey('stage-open-${stage.id}'),
                              ),
                            ),
                          ),
                        )
                      else if (isOpen)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: _NodeGlyph(
                            key: ValueKey('stage-open-${stage.id}'),
                            icon: Icons.bolt_rounded,
                            color: uiTheme.systemViolet,
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
                            color: isCleared
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
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: uiTheme.hullBlack,
                              border: Border.all(
                                color: uiTheme.frameSteel,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 13,
                              color: uiTheme.textMuted,
                            ),
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
}

// The caption chip and medal pips live in a second paint pass above every
// crest, so the chip's own InkWell resolves taps across its painted width —
// including past the 72px layout rect — without an overlapping neighbor's
// box claiming them first.
class _StageCaption extends StatelessWidget {
  const _StageCaption({
    super.key,
    required this.stage,
    required this.status,
    required this.result,
    required this.isNext,
    required this.onTap,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final StageResult? result;
  final bool isNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final isCleared = status == StageProgressStatus.cleared;
    final isRecommended = isNext && status == StageProgressStatus.unlocked;
    final statusColor = _stageStatusColor(
      uiTheme,
      stage,
      status,
      result,
      isNext,
    );
    // The crest node already carries the stage's full semantics; the chip
    // is a redundant visual target.
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            splashColor: statusColor.withValues(alpha: 0.20),
            highlightColor: statusColor.withValues(alpha: 0.10),
            child: _NodeNameChip(
              stage: stage,
              isRecommended: isRecommended,
              color: isLocked ? uiTheme.textMuted : statusColor,
            ),
          ),
          if (isCleared && result != null) ...[
            const SizedBox(height: 4),
            _MedalPips(rank: result!.medal.rank),
          ],
        ],
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.diameter, required this.width});

  final double diameter;
  final double width;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: uiTheme.systemCyan.withValues(
              alpha: width > 1.5 ? 0.45 : 0.18,
            ),
            width: width,
          ),
        ),
      ),
    );
  }
}

class _NextFlag extends StatelessWidget {
  const _NextFlag({super.key});

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: uiTheme.systemCyan,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 11, color: uiTheme.voidBlack),
          const SizedBox(width: 2),
          Text(
            'NEXT',
            textScaler: MediaQuery.textScalerOf(
              context,
            ).clamp(maxScaleFactor: 1.15),
            style: OrionTypography.microLabel(
              size: 10,
              color: uiTheme.voidBlack,
            ).copyWith(letterSpacing: 1.2, shadows: const []),
          ),
        ],
      ),
    );
  }
}

class _NodeNameChip extends StatelessWidget {
  const _NodeNameChip({
    required this.stage,
    required this.isRecommended,
    required this.color,
  });

  final StageDefinition stage;
  final bool isRecommended;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final order = stage.mainPathOrder;
    final labelStyle = OrionTypography.microLabel(
      size: 11,
      color: color,
    ).copyWith(letterSpacing: 1.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: uiTheme.voidBlack.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRecommended ? uiTheme.systemCyan : orionPanelEdge,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (order != null) ...[
            Text(
              '${order.toString().padLeft(2, '0')} ·',
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.15),
              style: labelStyle,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              stage.mapLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.15),
              style: labelStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedalPips extends StatelessWidget {
  const _MedalPips({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final tiers = [
      uiTheme.medalBronze,
      uiTheme.medalSilver,
      uiTheme.creditGold,
    ];
    // Display-only: on a compact plot the pips overlap the next crest's top
    // edge and must not claim taps aimed at that node.
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i += 1) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < rank ? tiers[i] : orionPipEmpty,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Star-chart crest node: a circular aperture holding the square-cropped
/// stage key art, ringed by the integrated status/medal color (artboard 1f).
class _StageOrb extends StatelessWidget {
  const _StageOrb({
    super.key,
    required this.stage,
    required this.isLocked,
    required this.isRecommended,
    required this.isSideOpen,
    required this.ringColor,
  });

  final StageDefinition stage;
  final bool isLocked;
  final bool isRecommended;
  final bool isSideOpen;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final diameter = isRecommended
        ? (stage.isMainPath ? 80.0 : 72.0)
        : stage.isMainPath
        ? 68.0
        : 60.0;
    final artSize = diameter - 6;
    Widget art = OrionAtlasSprite(
      art: OrionArt.crestFor(stage),
      size: Size.square(artSize),
    );
    if (isLocked) {
      art = Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(colorFilter: orionLockDesaturate, child: art),
          ColoredBox(color: uiTheme.voidBlack.withValues(alpha: 0.55)),
        ],
      );
    }

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: uiTheme.hullBlack,
        border: Border.all(
          color: isLocked ? uiTheme.frameSteel : ringColor,
          width: 3,
        ),
        boxShadow: isRecommended
            ? [
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.22),
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.7),
                  blurRadius: 30,
                ),
              ]
            : isSideOpen
            ? [
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ]
            : [
                BoxShadow(
                  color: uiTheme.voidBlack.withValues(alpha: 0.6),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
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

      final isCleared = route.medal != null;
      final color = isCleared
          ? uiTheme.creditGold
          : route.isActive
          ? (route.isOptional ? uiTheme.systemViolet : uiTheme.systemCyan)
          : orionRouteDim;
      final line = Paint()
        ..color = color.withValues(
          alpha: isCleared
              ? 0.85
              : route.isActive
              ? 0.9
              : 0.7,
        )
        ..strokeCap = StrokeCap.round
        ..strokeWidth = isCleared
            ? 3
            : route.isActive
            ? (route.isOptional ? 2.5 : 3)
            : 2;

      if (isCleared) {
        final glow = Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5;
        canvas.drawLine(from, to, glow);
        canvas.drawLine(from, to, line);
      } else if (!route.isActive) {
        _drawDashedLine(canvas, from, to, line, dash: 4, gap: 7);
      } else if (route.isOptional) {
        _drawDashedLine(canvas, from, to, line, dash: 7, gap: 6);
      } else {
        final glow = Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6;
        _drawDashedLine(canvas, from, to, glow, dash: 9, gap: 6);
        _drawDashedLine(canvas, from, to, line, dash: 9, gap: 6);
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

Color _stageStatusColor(
  OrionUiTheme uiTheme,
  StageDefinition stage,
  StageProgressStatus status,
  StageResult? result,
  bool isNext,
) {
  final isRecommended = isNext && status == StageProgressStatus.unlocked;
  final isSideOpen =
      status == StageProgressStatus.unlocked &&
      !isRecommended &&
      !stage.isMainPath;
  if (isRecommended) return uiTheme.systemCyan;
  if (isSideOpen) return uiTheme.systemViolet;
  return _statusColor(uiTheme, status, result);
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

/// The next playable mission, using the same campaign status as its map node.
class _MissionDestination extends StatelessWidget {
  const _MissionDestination({
    required this.stage,
    required this.sectorNumber,
    required this.progress,
    required this.campaignModifiers,
    required this.onStageSelected,
  });
  final StageDefinition? stage;
  final int sectorNumber;
  final CampaignProgress progress;
  final CampaignModifiers campaignModifiers;
  final ValueChanged<StageDefinition>? onStageSelected;

  @override
  Widget build(BuildContext context) {
    final stage = this.stage;
    if (stage == null) return const SizedBox.shrink();
    final theme = OrionUiTheme.of(context);
    final status = progress.statusFor(stage);
    final qualifier = status == StageProgressStatus.unlocked
        ? (stage.isMainPath ? 'NEXT MAIN' : 'OPTIONAL')
        : 'REPLAY';
    final startingHull = StageModifierRules.effectiveStartingBaseHealth(
      campaignAdjustedBaseHealth: campaignModifiers.adjustedStartingBaseHealth,
      stageModifiers: stage.modifiers,
    );
    final modifierTitles = stage.modifiers
        .map((modifier) => StageModifierMetadata.forModifier(modifier).title)
        .toList(growable: false);
    return OrionSurface(
      role: OrionSurfaceRole.sheet,
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Semantics(
        button: true,
        label: 'Briefing for ${stage.name}',
        hint:
            '$qualifier. ${stage.waves.length} waves. '
            '$startingHull starting hull.'
            '${modifierTitles.isEmpty ? '' : ' Modifiers: ${modifierTitles.join(', ')}.'}',
        enabled: onStageSelected != null,
        excludeSemantics: true,
        onTap: onStageSelected == null ? null : () => onStageSelected!(stage),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onStageSelected == null
                  ? null
                  : () => onStageSelected!(stage),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: orionArtFrame, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                          'SECTOR ${sectorNumber.toString().padLeft(2, '0')} / $qualifier',
                          // Two clamped lines, not one unclamped: at 3x system
                          // text the single line ellipsized the qualifier (the
                          // informative part) inside the ~110px column.
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
                            size: 18,
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.3,
                          child: Row(
                            children: [
                              Icon(
                                Icons.waves,
                                color: theme.textMuted,
                                size: 18,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${stage.waves.length}',
                                style: OrionTypography.readout(
                                  size: 12,
                                  color: theme.textMuted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.shield_outlined,
                                color: theme.systemCyan,
                                size: 18,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$startingHull',
                                key: const ValueKey(
                                  'destination-starting-hull',
                                ),
                                style: OrionTypography.readout(
                                  size: 12,
                                  color: theme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (modifierTitles.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final title in modifierTitles)
                                Text(
                                  title,
                                  textScaler: MediaQuery.textScalerOf(
                                    context,
                                  ).clamp(maxScaleFactor: 1.3),
                                  style: OrionTypography.microLabel(
                                    color: theme.warningOrange,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: OrionPrimaryButton(
                label: 'Deploy',
                icon: Icons.play_arrow_rounded,
                height: 48,
                labelSize: 12,
                onPressed: onStageSelected == null
                    ? null
                    : () => onStageSelected!(stage),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
