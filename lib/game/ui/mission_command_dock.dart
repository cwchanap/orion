import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'mission_command_hud.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Closed scene-1e placement-preview event family. The dock emits, Chrome
/// forwards, and the page maps onto [OrionDefenseGame]'s preview methods.
/// One family, no controller; commit carries the FINAL global pointer
/// position and an off-board commit always cancels downstream.
sealed class TowerPlacementPreviewEvent {
  const TowerPlacementPreviewEvent();
}

final class TowerPlacementPreviewBegin extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewBegin(this.type);

  final TowerType type;
}

final class TowerPlacementPreviewUpdate extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewUpdate(this.globalPosition);

  final Offset globalPosition;
}

final class TowerPlacementPreviewCommit extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewCommit(this.globalPosition);

  final Offset globalPosition;
}

final class TowerPlacementPreviewCancel extends TowerPlacementPreviewEvent {
  const TowerPlacementPreviewCancel();
}

/// One guide anchor over exactly one build-rail card: which tower type the
/// guide points at, and the key wrapping that card. The same key is never
/// attached to two cards (or both dock branches) at once — the page owns it
/// and supplies it only while a single card is the active guide target.
typedef TowerCardGuideAnchor = ({TowerType type, Key anchorKey});

class MissionCommandDock extends StatelessWidget {
  const MissionCommandDock({
    super.key,
    required this.snapshot,
    required this.onTogglePause,
    required this.onSpeedSelected,
    required this.onToggleAutoStart,
    required this.onStartWave,
    required this.onPlaceTower,
    required this.onUpgrade,
    required this.onSpecialize,
    required this.onTargetingChanged,
    required this.onSell,
    this.onPlacementPreviewEvent,
    this.worldMapAction,
    this.towerCardGuideAnchor,
    this.waveGuideAnchorKey,
  });

  final Widget? worldMapAction;

  /// Card anchor for the first-mission/contextual guide; attached ONLY to
  /// the selected-cell rail (never the persistent idle rail — the same
  /// GlobalKey on both dock branches would collide during the dock
  /// transition).
  ///
  /// Anchor keys WRAP existing surfaces — they never replace gameplay
  /// ValueKeys — and stay null unless the page supplies them, so production
  /// behavior is unchanged.
  final TowerCardGuideAnchor? towerCardGuideAnchor;

  /// Primary wave-action anchor around `_PrimaryActionPill`.
  final Key? waveGuideAnchorKey;
  final GameSnapshot snapshot;
  final VoidCallback onTogglePause;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onToggleAutoStart;
  final VoidCallback onStartWave;
  final ValueChanged<TowerType> onPlaceTower;
  final VoidCallback onUpgrade;
  final ValueChanged<TowerSpecialization> onSpecialize;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;
  final VoidCallback onSell;
  final ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    final Key contentKey;
    if (snapshot.selectedCell != null && snapshot.selectedTower == null) {
      contentKey = const ValueKey('command-dock-build');
      content = TowerBuildRail(
        phase: snapshot.phase,
        gold: snapshot.gold,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
        onPlaceTower: onPlaceTower,
        onPlacementPreviewEvent: onPlacementPreviewEvent,
        // Selected-cell branch only: see [towerCardGuideAnchor].
        towerCardGuideAnchor: towerCardGuideAnchor,
      );
    } else {
      contentKey = const ValueKey('command-dock-idle');
      final idleBar = IdleCommandBar(
        worldMapAction: worldMapAction,
        snapshot: snapshot,
        onTogglePause: onTogglePause,
        onSpeedSelected: onSpeedSelected,
        onToggleAutoStart: onToggleAutoStart,
        onStartWave: onStartWave,
        waveGuideAnchorKey: waveGuideAnchorKey,
      );
      // Artboard 1a's dock is two rows during build: the pacing controls
      // beside the primary action, and the tower rail beneath them. The rail
      // was reachable only after selecting a cell, so the artboard's own
      // scene could not be produced -- and a rail you have to summon cannot
      // be dragged from, which is how 1e says a tower is placed.
      content = snapshot.phase == GamePhase.build && !snapshot.isEnded
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                idleBar,
                const SizedBox(height: 8),
                TowerBuildRail(
                  key: const ValueKey('command-dock-persistent-rail'),
                  phase: snapshot.phase,
                  gold: snapshot.gold,
                  unlockedTowerTypes: snapshot.unlockedTowerTypes,
                  onPlaceTower: onPlaceTower,
                  onPlacementPreviewEvent: onPlacementPreviewEvent,
                ),
              ],
            )
          : idleBar;
    }

    // One full-width shelf groups every dock state.
    return OrionSurface(
      tier: OrionSurfaceTier.t4,
      radius: 0,
      topBorderOnly: true,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            key: const ValueKey('mission-command-dock-transition'),
            duration: orionMotionDuration(
              context,
              const Duration(milliseconds: 180),
            ),
            layoutBuilder: (currentChild, previousChildren) =>
                currentChild ?? const SizedBox.shrink(),
            child: KeyedSubtree(key: contentKey, child: content),
          ),
        ],
      ),
    );
  }
}

class IdleCommandBar extends StatelessWidget {
  const IdleCommandBar({
    super.key,
    required this.snapshot,
    required this.onTogglePause,
    required this.onSpeedSelected,
    required this.onToggleAutoStart,
    required this.onStartWave,
    this.worldMapAction,
    this.waveGuideAnchorKey,
  });

  final Widget? worldMapAction;
  final GameSnapshot snapshot;
  final VoidCallback onTogglePause;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onToggleAutoStart;
  final VoidCallback onStartWave;

  /// Optional first-mission guide anchor for the primary wave action.
  final Key? waveGuideAnchorKey;

  @override
  Widget build(BuildContext context) {
    final countdown = snapshot.autoStartCountdownRemaining;
    final reactorLabel = _reactorLabel(snapshot, countdown);
    final reactorTooltip = snapshot.phase == GamePhase.wave
        ? 'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}'
        : reactorLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Pacing flexes and wraps on narrow viewports; the fixed-size
          // primary action stays pinned to the dock's edge.
          Expanded(
            child: MissionPacingControls(
              snapshot: snapshot,
              onTogglePause: onTogglePause,
              onSpeedSelected: onSpeedSelected,
              onToggleAutoStart: onToggleAutoStart,
            ),
          ),
          if (worldMapAction != null) ...[
            const SizedBox(width: 8),
            worldMapAction!,
          ],
          const SizedBox(width: 8),
          AnimatedSwitcher(
            key: const ValueKey('idle-command-reactor-transition'),
            duration: orionMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            layoutBuilder: (currentChild, previousChildren) =>
                currentChild ?? const SizedBox.shrink(),
            child: _reactorPill(
              reactorLabel: reactorLabel,
              tooltip: reactorTooltip,
              label: snapshot.canStartWave && countdown == null
                  ? 'Wave ${snapshot.waveNumber}'
                  : reactorLabel,
            ),
          ),
        ],
      ),
    );
  }

  /// The AnimatedSwitcher's direct child keeps ONE runtimeType and key —
  /// the outer KeyedSubtree's [ValueKey] on the reactor label — whether or
  /// not the guide anchor is attached, so toggling the guide never fires a
  /// transition while label changes still do. The inner KeyedSubtree
  /// carries the (possibly null) guide anchor key.
  Widget _reactorPill({
    required String reactorLabel,
    required String tooltip,
    required String label,
  }) {
    final pill = _PrimaryActionPill(
      tooltip: tooltip,
      label: label,
      icon: snapshot.phase == GamePhase.wave
          ? Icons.radar
          : Icons.play_arrow_rounded,
      onPressed: snapshot.canStartWave ? onStartWave : null,
    );
    return KeyedSubtree(
      key: ValueKey(reactorLabel),
      child: KeyedSubtree(key: waveGuideAnchorKey, child: pill),
    );
  }

  static String _reactorLabel(GameSnapshot snapshot, double? countdown) {
    if (countdown != null) return 'Start Now';
    if (snapshot.phase == GamePhase.wave) {
      return '${snapshot.waveNumber}/${snapshot.waveTotal}';
    }
    return 'Start Wave';
  }
}

/// Wide filled pill for the dock's single primary action: 48-56dp tall,
/// filled cyan with dark content while enabled, and the dock's only glow.
/// The wave-progress and countdown variants share the same footprint so the
/// idle dock never reflows when the phase label changes.
class _PrimaryActionPill extends StatelessWidget {
  const _PrimaryActionPill({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  static const double _width = 116;
  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    final foreground = enabled ? uiTheme.voidBlack : uiTheme.textMuted;
    final accent = enabled ? uiTheme.systemCyanStrong : uiTheme.frameSteel;
    final radius = BorderRadius.circular(_height / 2);

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: SizedBox(
          width: _width,
          height: _height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: enabled
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF7FF0FF),
                        Color(0xFF13B8E6),
                        Color(0xFF0A7EA3),
                      ],
                      stops: [0, 0.6, 1],
                    )
                  : null,
              // The strongest glow in the idle dock is reserved for this
              // one action; pacing and the shell carry none.
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: uiTheme.systemCyanStrong.withValues(alpha: 0.30),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: enabled
                  ? Colors.transparent
                  : uiTheme.hullBlack.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: accent, width: 1),
              ),
              child: InkWell(
                onTap: onPressed,
                borderRadius: radius,
                splashColor: uiTheme.voidBlack.withValues(alpha: 0.12),
                highlightColor: uiTheme.voidBlack.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          // Caps to match the artboard's pill; the pill
                          // already excludes its own semantics in favour of
                          // `tooltip`, so the real copy is untouched.
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: MediaQuery.textScalerOf(
                            context,
                          ).clamp(maxScaleFactor: 1.15),
                          style: OrionTypography.microLabel(
                            color: foreground,
                            size: 10,
                          ).copyWith(shadows: const []),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TowerBuildRail extends StatefulWidget {
  const TowerBuildRail({
    super.key,
    required this.phase,
    required this.gold,
    required this.unlockedTowerTypes,
    required this.onPlaceTower,
    this.onPlacementPreviewEvent,
    this.towerCardGuideAnchor,
  });

  final GamePhase phase;
  final int gold;
  final List<TowerType> unlockedTowerTypes;
  final ValueChanged<TowerType> onPlaceTower;
  final ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent;

  /// Optional guide anchor for exactly one card. Supplied only by the
  /// selected-cell rail; the persistent idle rail passes nothing.
  final TowerCardGuideAnchor? towerCardGuideAnchor;

  @override
  State<TowerBuildRail> createState() => _TowerBuildRailState();
}

class _TowerBuildRailState extends State<TowerBuildRail> {
  /// Local transient drag presentation: the lifted tower and the latest
  /// global pointer position. Nothing here reaches game state — the game
  /// resolves validity, mutation, and cleanup through the emitted events.
  TowerType? _activeDraggedType;
  Offset? _latestGlobalPointer;

  @override
  void initState() {
    super.initState();
    _revealAnchorCard();
  }

  @override
  void didUpdateWidget(TowerBuildRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A changed (or freshly attached) target type is a new activation; the
    // same activation rebuilding must never re-scroll — the user may have
    // scrolled elsewhere in between.
    if (widget.towerCardGuideAnchor?.type !=
        oldWidget.towerCardGuideAnchor?.type) {
      _revealAnchorCard();
    }
  }

  /// Brings the anchored card into view once per activation: post-frame (so
  /// the branch switch has laid the card out), centered, reduced-motion
  /// aware. Detaching the anchor during the frame cancels the reveal.
  void _revealAnchorCard() {
    final type = widget.towerCardGuideAnchor?.type;
    if (type == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.towerCardGuideAnchor?.type != type) return;
      final key = widget.towerCardGuideAnchor?.anchorKey;
      final context = key is GlobalKey ? key.currentContext : null;
      if (context == null || !context.mounted) return;
      // Reveal only what the player cannot already reach: ensureVisible
      // re-centers even a fully visible card, which would scroll the rail
      // out from under their finger at branch mount.
      final scrollable = Scrollable.maybeOf(context);
      final viewportBox = scrollable?.context.findRenderObject() as RenderBox?;
      final cardBox = context.findRenderObject() as RenderBox?;
      if (viewportBox == null || cardBox == null || !cardBox.attached) {
        return;
      }
      final cardRect =
          cardBox.localToGlobal(Offset.zero, ancestor: viewportBox) &
          cardBox.size;
      final viewportRect = Offset.zero & viewportBox.size;
      final fullyVisible =
          cardRect.left >= viewportRect.left &&
          cardRect.top >= viewportRect.top &&
          cardRect.right <= viewportRect.right &&
          cardRect.bottom <= viewportRect.bottom;
      if (fullyVisible) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: orionMotionDuration(
          context,
          const Duration(milliseconds: 240),
        ),
        curve: Curves.easeOut,
      );
    });
  }

  void _emit(TowerPlacementPreviewEvent event) {
    widget.onPlacementPreviewEvent?.call(event);
  }

  /// Builds one rail card, wrapping it in the guide anchor when it is the
  /// single active target. The card's own ValueKey stays untouched.
  Widget _buildCard(TowerType type) {
    final card = _TowerBuildCard(
      type: type,
      phase: widget.phase,
      gold: widget.gold,
      unlocked: widget.unlockedTowerTypes.contains(type),
      onPlaceTower: widget.onPlaceTower,
      onDragStarted: () => _handleDragStarted(type),
      onDragUpdate: (position) => _handleDragUpdate(type, position),
      onDragEnded: () => _handleDragEnded(type),
      onDragCanceled: () => _handleDragCanceled(type),
      onPointerUp: (position) => _handlePointerUp(type, position),
    );
    final anchor = widget.towerCardGuideAnchor;
    if (anchor == null || type != anchor.type) return card;
    return KeyedSubtree(key: anchor.anchorKey, child: card);
  }

  /// Each card owns its recognizer, so `maxSimultaneousDrags: 1` cannot stop
  /// a second finger starting a drag on a different card. Every handler is
  /// gated on [type] matching [_activeDraggedType]: a second card's drag
  /// still animates its ghost but emits no events, so it can never overwrite
  /// the airborne preview or commit the wrong tower.
  void _handleDragStarted(TowerType type) {
    if (_activeDraggedType != null) return;
    setState(() {
      _activeDraggedType = type;
      _latestGlobalPointer = null;
    });
    _emit(TowerPlacementPreviewBegin(type));
  }

  void _handleDragUpdate(TowerType type, Offset globalPosition) {
    if (_activeDraggedType != type) return;
    _latestGlobalPointer = globalPosition;
    _emit(TowerPlacementPreviewUpdate(globalPosition));
  }

  /// The pointer router dispatches up events to recognizers before hit-test
  /// listeners, so [LongPressDraggable.onDragEnd] cannot observe the release
  /// coordinate — and `DraggableDetails.offset` is the anchored avatar
  /// position, not the pointer. The release point lands here one beat after
  /// drag end, ahead of the deferred settle. Only recorded once updates have
  /// streamed: a release that never moved stays a cancel, never a commit at
  /// the card's own position.
  void _handlePointerUp(TowerType type, Offset position) {
    if (_activeDraggedType != type || _latestGlobalPointer == null) return;
    _latestGlobalPointer = position;
  }

  void _handleDragEnded(TowerType type) {
    if (_activeDraggedType != type) return;
    // Settle one microtask later so the paired onPointerUp — dispatched
    // synchronously right after this callback — can supply the true release
    // coordinate before the commit reads it.
    scheduleMicrotask(() {
      if (!mounted || _activeDraggedType != type) return;
      setState(() => _activeDraggedType = null);
      final pointer = _latestGlobalPointer;
      _latestGlobalPointer = null;
      if (pointer != null) {
        _emit(TowerPlacementPreviewCommit(pointer));
      } else {
        _emit(TowerPlacementPreviewCancel());
      }
    });
  }

  /// Recognizer-level cancel (OS pointer interruption: incoming call,
  /// notification shade, app switcher, or rail unmount). This SDK has no
  /// onDragCancel callback and surfaces cancels as onDragEnd — the raw
  /// pointer cancel preempts it here, and the trailing drag end is ignored
  /// by the [type] gate because the active type is already cleared.
  /// Never commits at the last pointer — always cancels the preview.
  void _handleDragCanceled(TowerType type) {
    if (_activeDraggedType != type) return;
    setState(() {
      _activeDraggedType = null;
      _latestGlobalPointer = null;
    });
    _emit(TowerPlacementPreviewCancel());
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3);
    return Padding(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: textScaler.scale(1) * _TowerBuildCard.baseHeight + 12,
        child: Stack(
          children: [
            // Eight fixed cards: one eager Row in a scroll view. Every card
            // is always built, so the guide can anchor and reveal any card
            // (even offscreen) — lazy viewport items could not. The padding
            // stays INSIDE the scrollable: outside it clips cards 14px from
            // the screen edge and swallows drags that start in the strip.
            // Each card keeps what ListView supplied for free: an indexed
            // semantics node and its own repaint boundary, while
            // semanticChildCount restores the "of 8" collection size a
            // SingleChildScrollView cannot announce ("item N of 8").
            CustomScrollView(
              semanticChildCount: TowerType.values.length,
              scrollDirection: Axis.horizontal,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        for (final (index, type)
                            in TowerType.values.indexed) ...[
                          if (index > 0) const SizedBox(width: 8),
                          RepaintBoundary(
                            child: IndexedSemantics(
                              index: index,
                              child: _buildCard(type),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 1e treatment: the rail reads DROP TO BUILD while a long-press
            // drag is airborne. Overlay only — the rail's height never shifts.
            if (_activeDraggedType != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: OrionUiTheme.of(
                          context,
                        ).hullBlack.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: OrionUiTheme.of(context).systemCyan,
                        ),
                      ),
                      child: Text(
                        'DROP TO BUILD',
                        textScaler: textScaler,
                        style: OrionTypography.microLabel(
                          color: OrionUiTheme.of(context).systemCyan,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TowerBuildCard extends StatelessWidget {
  const _TowerBuildCard({
    required this.type,
    required this.phase,
    required this.gold,
    required this.unlocked,
    required this.onPlaceTower,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnded,
    this.onDragCanceled,
    this.onPointerUp,
  });

  final TowerType type;
  final GamePhase phase;
  final int gold;
  final bool unlocked;
  final ValueChanged<TowerType> onPlaceTower;

  /// Long-press drag wiring. Only invoked for eligible cards (build phase +
  /// unlocked); affordability stays authority-driven (game validation).
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnded;
  final VoidCallback? onDragCanceled;

  /// Raw pointer-up on this card — carries the release coordinate, which
  /// recognizer callbacks never see.
  final ValueChanged<Offset>? onPointerUp;

  // Artboard 1a's rail card: 70x88, radius 16, a 58px sprite, then the cost,
  // then the name. Ours was 64x92 with a 42px sprite and the name above a
  // bolt-prefixed cost -- the sprite is what the player picks from, so it
  // gets the room, and the cost is the decision, so it outranks the name.
  static const double baseWidth = 70;
  static const double baseHeight = 96;

  @override
  Widget build(BuildContext context) {
    final stats = GameBalance.towerStats(type, level: 1);
    final affordable = gold >= stats.cost;
    final canAttempt = phase == GamePhase.build && unlocked;
    final uiTheme = OrionUiTheme.of(context);
    final cardLabel = _cardLabel(stats, affordable);
    final onTap = canAttempt ? () => onPlaceTower(type) : null;
    final accent = !unlocked
        ? uiTheme.frameSteel
        : affordable
        ? uiTheme.systemCyan
        : uiTheme.textMuted;
    // Honor the player's text-size preference up to 1.3x and grow the card
    // with it so the scaled labels keep their room instead of truncating.
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3);
    final scaleFactor = textScaler.scale(1);
    final sprite = OrionAtlasSprite(
      art: OrionArt.tower(type),
      size: const Size(58, 58),
    );

    final card = Semantics(
      button: true,
      enabled: canAttempt,
      label: cardLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        key: ValueKey('tower-card-${type.name}'),
        width: baseWidth * scaleFactor,
        height: baseHeight * scaleFactor,
        // Flat: the rail around these tiles is already one blurred row, and
        // blurring each tile inside it is the anti-pattern OrionSurface names.
        child: OrionInnerSurface(
          tier: OrionSurfaceTier.t2,
          // Keep room for the sprite above the cost and name.
          padding: EdgeInsets.zero,
          radius: 16,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: onTap,
              containedInkWell: true,
              highlightShape: BoxShape.rectangle,
              splashColor: accent.withValues(alpha: 0.18),
              highlightColor: accent.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: affordable ? 1 : 0.48,
                              // A ColorFiltered layer is only worth its cost
                              // for the locked greyscale; unlocked cards pass
                              // the sprite through untouched.
                              child: unlocked
                                  ? sprite
                                  : ColorFiltered(
                                      colorFilter:
                                          const ColorFilter.matrix(<double>[
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0,
                                            0,
                                            0,
                                            1,
                                            0,
                                          ]),
                                      child: sprite,
                                    ),
                            ),
                            if (!unlocked)
                              Icon(
                                Icons.lock_outline,
                                size: 17,
                                color: uiTheme.textMuted,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Cost above name, per the artboard's card template
                    // (icon, cost, name). An unaffordable cost goes red
                    // rather than muted: the artboard says *why* the card is
                    // dimmed instead of only that it is.
                    Text(
                      '${stats.cost}',
                      maxLines: 1,
                      textScaler: textScaler,
                      style: OrionTypography.readout(
                        size: 14,
                        color: !unlocked
                            ? uiTheme.textMuted
                            : affordable
                            ? uiTheme.creditGold
                            : uiTheme.dangerRed,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      // The artboard sets every micro label in caps; the
                      // card's Semantics carries the real copy, so the
                      // display string is free to shout.
                      type.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: textScaler,
                      // Muted in every state, as the artboard sets it: the
                      // cost carries the affordability signal now, so the
                      // name does not need to.
                      style: OrionTypography.microLabel(
                        size: 8,
                        color: uiTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Locked or wrong-phase cards never begin a preview; affordability stays
    // authority-driven (the game denies on validate/place).
    if (!canAttempt) {
      return card;
    }

    // Delayed long-press recognizer only: an immediate pan drag would fight
    // the horizontal rail scroll. A quick tap still reaches the card's tap
    // handler; a horizontal swipe scrolls the rail and never begins preview.
    // The Flame board is NOT a DragTarget — game validation decides, never
    // wasAccepted/onDragCompleted.
    // Listener observes the raw pointer cancel, which the GestureBinding
    // dispatches before the avatar's drag-end cleanup, letting the rail
    // treat a recognizer cancel as a cancel instead of a commit.
    return Listener(
      onPointerCancel: (_) => onDragCanceled?.call(),
      onPointerUp: (event) => onPointerUp?.call(event.position),
      child: LongPressDraggable<TowerType>(
        data: type,
        // Per-card cap only: it stops two drags on THIS card. A second finger
        // on a different card still starts a drag — the rail gates those
        // events on the active type so they can never reach the preview.
        maxSimultaneousDrags: 1,
        onDragStarted: onDragStarted,
        onDragUpdate: (details) => onDragUpdate?.call(details.globalPosition),
        onDragEnd: (_) => onDragEnded?.call(),
        feedback: _buildDragFeedback(context),
        childWhenDragging: _buildLiftedSource(context, scaleFactor),
        child: card,
      ),
    );
  }

  /// 1e treatment: tower ghost follows the pointer over a soft shadow, with
  /// a cost pill showing −cost → remaining gold; an unaffordable drag states
  /// the real need instead of pretending placement is allowed.
  Widget _buildDragFeedback(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stats = GameBalance.towerStats(type, level: 1);
    final affordable = gold >= stats.cost;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: uiTheme.voidBlack.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: OrionAtlasSprite(
            art: OrionArt.tower(type),
            size: const Size(64, 64),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: uiTheme.hullBlack.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: affordable ? uiTheme.systemCyan : uiTheme.dangerRed,
            ),
          ),
          child: Text(
            affordable
                ? '−${stats.cost} → ${gold - stats.cost}'
                : 'need ${stats.cost - gold} more',
            style: OrionTypography.readout(
              size: 13,
              color: affordable ? uiTheme.creditGold : uiTheme.dangerRed,
            ),
          ),
        ),
      ],
    );
  }

  /// 1e treatment: the source card reads LIFTED while its drag is airborne.
  Widget _buildLiftedSource(BuildContext context, double scaleFactor) {
    final uiTheme = OrionUiTheme.of(context);
    return SizedBox(
      width: baseWidth * scaleFactor,
      height: baseHeight * scaleFactor,
      child: OrionInnerSurface(
        tier: OrionSurfaceTier.t2,
        padding: const EdgeInsets.all(2),
        radius: 10,
        child: Center(
          child: Text(
            'LIFTED',
            style: OrionTypography.microLabel(color: uiTheme.textMuted),
          ),
        ),
      ),
    );
  }

  String _cardLabel(TowerStats stats, bool affordable) {
    final state = unlocked
        ? 'unlocked'
        : 'locked until wave ${GameBalance.towerUnlockWave(type)}';
    final affordability = affordable ? 'affordable' : 'unaffordable';
    return '${type.label}, $state, cost ${stats.cost}, $affordability, '
        'place on selected cell';
  }
}
