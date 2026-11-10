import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_reward_label.dart';
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
            // The header stays fixed above the scrolling region — it must
            // never scroll away, because the transient feedback line has to
            // be reachable at every scroll offset. (An earlier revision put
            // the header inside the scrollable flow, which also let the
            // feedback line resize the chart each time it appeared.) Menu
            // navigation lives in the shared shell's tabs, so there is no
            // per-view utility rail here any more.
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
                                    widget.progress
                                        .recommendedStage(widget.stages)
                                        ?.id ==
                                    stage.id,
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
                                    12,
                                    14,
                                    // The footer sits under the shell's own
                                    // bottom chrome; its bottom pad stays
                                    // tight so chart+footer still fits a
                                    // common portrait height without
                                    // scrolling.
                                    10,
                                  ),
                                  child: _MissionDestination(
                                    stages: widget.stages,
                                    progress: widget.progress,
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
          child: _SectorHeader(
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
        // CSS flex-wrap analogue: title and badges flow inline until the
        // row cannot hold them, then the trailing children wrap to a second
        // line instead of overflowing — a two-badge + challenge state is
        // wider than a 320px map even at 1x text.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.public,
              size: 16,
              color: uiTheme.systemCyan,
              shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
            ),
            OrionTitle(
              'Orion Sector',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Same dense-map clamp as the badges so an extreme system
              // scale caps the wordmark instead of starving the badges.
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              color: uiTheme.textPrimary,
            ),
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
                        ),
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

/// A star-chart node. Its layout box stays the exact rect SectorMapLayout
/// assigns — route joins and tap targets never move — while the arcade
/// chrome (NEXT flag, pulse rings, name chip, medal pips) is free to
/// overhang the rect edges the way the mock's absolutely-placed layers do.
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

  /// True when the shared recommender steers to this stage. Combined with
  /// the unlocked status inside the node, so a cleared replay fallback
  /// never wears the NEXT flag.
  final bool isNext;
  final bool isBusy;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final isCleared = status == StageProgressStatus.cleared;
    final isOpen = status == StageProgressStatus.unlocked;
    final isRecommended = isNext && isOpen;
    final isSideOpen = isOpen && !isRecommended && !stage.isMainPath;
    final statusColor = isRecommended
        ? uiTheme.systemCyan
        : isSideOpen
        ? uiTheme.systemViolet
        : _statusColor(uiTheme, status, result);
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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 76,
                  child: Stack(
                    key: ValueKey('stage-crest-${stage.id}'),
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      if (isRecommended) ...const [
                        Center(child: _PulseRing(diameter: 108, width: 2)),
                        Center(child: _PulseRing(diameter: 132, width: 1.5)),
                      ],
                      Center(
                        child: _StageOrb(
                          key: ValueKey('stage-status-ring-${stage.id}'),
                          stage: stage,
                          isLocked: isLocked,
                          isRecommended: isRecommended,
                          isSideOpen: isSideOpen,
                          ringColor: statusColor,
                        ),
                      ),
                      if (isRecommended)
                        Positioned(
                          top: -24,
                          left: 0,
                          right: 0,
                          child: Center(
                            // scaleDown keeps the capsule at spec size for
                            // normal text and shrinks it as a unit when a
                            // large system scale would overflow the node's
                            // aperture — the flag floats, so it may shrink,
                            // never clip or push layout.
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
                Positioned(
                  top: 74,
                  left: -20,
                  right: -20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NodeNameChip(
                        stage: stage,
                        isRecommended: isRecommended,
                        color: isLocked ? uiTheme.textMuted : statusColor,
                      ),
                      if (isCleared && result != null) ...[
                        const SizedBox(height: 4),
                        _MedalPips(rank: result!.medal.rank),
                      ],
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

/// Static pulse ring around the recommended node's orb (the mock draws a
/// 108px and a 132px echo ring; animation stays out so reduced-motion
/// players get the same readout).
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

/// The kit's `.tag` NEXT flag: a solid cyan capsule with dark ink, floating
/// above the recommended node's orb.
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
            // Same dense-map clamp as the name chip: the capsule is a
            // fixed 20px flag, so unbounded system text would overflow it.
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

/// The kit's `.name` chip: a small dark pill carrying the sector number and
/// the node's short label, edge-tinted for the recommended target.
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

/// Bronze/silver/gold pips under a cleared node's name chip: pip i fills
/// when the earned medal rank covers tier i (clear = bronze, silver,
/// gold), so a silver medal reads bronze+silver+empty like the kit's.
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
    return Row(
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
    );
  }
}

/// Star-chart crest orb: circular aperture holding the square-cropped
/// stage key art, ringed by the status color with the kit's per-state
/// glow — cleared reads gold, the recommended target reads cyan and
/// oversized, an open side stage reads violet, locked stays dim steel.
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
      // grayscale(1) brightness(.45) from the kit's `.orb.locked img`.
      art = Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.grey,
              BlendMode.saturation,
            ),
            child: art,
          ),
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

      // Per-state routes from the kit: cleared legs run solid gold, the
      // open main leg runs dashed cyan with a glow, an open side leg runs
      // dashed violet, and locked legs stay dim steel. Routes are purely
      // decorative conduits — the nodes remain the only hit targets.
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
    required this.stages,
    required this.progress,
    required this.onStageSelected,
  });
  final List<StageDefinition> stages;
  final CampaignProgress progress;
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
                          'SECTOR ${(stages.indexOf(stage) + 1).toString().padLeft(2, '0')} / $qualifier',
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
                            size: 18,
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.waves, color: theme.textMuted, size: 18),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // The kit's full-width Deploy action: the card as a whole stays
            // one semantic 'Briefing' target, and the button is the visual
            // call-out inside it.
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
