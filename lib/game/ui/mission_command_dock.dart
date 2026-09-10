import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'mission_command_hud.dart';
import 'mission_surface.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'tower_inspector.dart';

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
  });

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
    if (snapshot.selectedTower != null) {
      contentKey = const ValueKey('command-dock-tower');
      content = TowerInspector(
        snapshot: snapshot,
        onUpgrade: onUpgrade,
        onSpecialize: onSpecialize,
        onTargetingChanged: onTargetingChanged,
        onSell: onSell,
        sellRefund: GameBalance.refundValue(snapshot.selectedTower!),
      );
    } else if (snapshot.selectedCell != null) {
      contentKey = const ValueKey('command-dock-build');
      content = TowerBuildRail(
        phase: snapshot.phase,
        gold: snapshot.gold,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
        onPlaceTower: onPlaceTower,
        onPlacementPreviewEvent: onPlacementPreviewEvent,
      );
    } else {
      contentKey = const ValueKey('command-dock-idle');
      final idleBar = IdleCommandBar(
        snapshot: snapshot,
        onTogglePause: onTogglePause,
        onSpeedSelected: onSpeedSelected,
        onToggleAutoStart: onToggleAutoStart,
        onStartWave: onStartWave,
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

    // Every dock state surfaces itself: idle, build rail, and inspector
    // each own a rounded MissionSurface — no outer frame chrome.
    return Column(
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
  });

  final GameSnapshot snapshot;
  final VoidCallback onTogglePause;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onToggleAutoStart;
  final VoidCallback onStartWave;

  @override
  Widget build(BuildContext context) {
    final countdown = snapshot.autoStartCountdownRemaining;
    final reactorLabel = _reactorLabel(snapshot, countdown);
    final reactorTooltip = snapshot.phase == GamePhase.wave
        ? 'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}'
        : reactorLabel;

    return MissionSurface(
      // The shell is a low grouping surface for the idle row, not a strong
      // cyan frame: reduced vertical padding groups the controls into the
      // dock's quiet default (unemphasized) tier.
      padding: const EdgeInsets.all(6),
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
          const SizedBox(width: 8),
          AnimatedSwitcher(
            key: const ValueKey('idle-command-reactor-transition'),
            duration: orionMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            layoutBuilder: (currentChild, previousChildren) =>
                currentChild ?? const SizedBox.shrink(),
            child: _PrimaryActionPill(
              key: ValueKey(reactorLabel),
              tooltip: reactorTooltip,
              label: reactorLabel,
              icon: snapshot.phase == GamePhase.wave
                  ? Icons.radar
                  : Icons.play_arrow_rounded,
              onPressed: snapshot.canStartWave ? onStartWave : null,
            ),
          ),
        ],
      ),
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
    super.key,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  static const double _width = 98;
  static const double _height = 52;

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
                  ? uiTheme.systemCyan
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
                          style: OrionTypography.microLabel(color: foreground),
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
  });

  final GamePhase phase;
  final int gold;
  final List<TowerType> unlockedTowerTypes;
  final ValueChanged<TowerType> onPlaceTower;
  final ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent;

  @override
  State<TowerBuildRail> createState() => _TowerBuildRailState();
}

class _TowerBuildRailState extends State<TowerBuildRail> {
  /// Local transient drag presentation: the lifted tower and the latest
  /// global pointer position. Nothing here reaches game state — the game
  /// resolves validity, mutation, and cleanup through the emitted events.
  TowerType? _activeDraggedType;
  Offset? _latestGlobalPointer;

  /// Set when the OS cancels the drag pointer (see [_handleDragCanceled]);
  /// LongPressDraggable then still reports a drag end, which must not commit.
  bool _dragCancelledBySystem = false;

  void _emit(TowerPlacementPreviewEvent event) {
    widget.onPlacementPreviewEvent?.call(event);
  }

  void _handleDragStarted(TowerType type) {
    _dragCancelledBySystem = false;
    setState(() {
      _activeDraggedType = type;
      _latestGlobalPointer = null;
    });
    _emit(TowerPlacementPreviewBegin(type));
  }

  void _handleDragUpdate(Offset globalPosition) {
    _latestGlobalPointer = globalPosition;
    _emit(TowerPlacementPreviewUpdate(globalPosition));
  }

  void _handleDragEnded() {
    if (_dragCancelledBySystem) {
      _dragCancelledBySystem = false;
      return;
    }
    setState(() => _activeDraggedType = null);
    final pointer = _latestGlobalPointer;
    _latestGlobalPointer = null;
    if (pointer != null) {
      _emit(TowerPlacementPreviewCommit(pointer));
    } else {
      _emit(TowerPlacementPreviewCancel());
    }
  }

  /// Recognizer-level cancel (OS pointer interruption: incoming call,
  /// notification shade, app switcher, or rail unmount). This SDK has no
  /// onDragCancel callback and surfaces cancels as onDragEnd — the raw
  /// pointer cancel preempts it here; the trailing drag end is ignored.
  /// Never commits at the last pointer — always cancels the preview.
  void _handleDragCanceled() {
    if (_activeDraggedType == null) return;
    _dragCancelledBySystem = true;
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
    return MissionSurface(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: textScaler.scale(1) * _TowerBuildCard.baseHeight + 12,
        child: Stack(
          children: [
            ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: TowerType.values.length,
              separatorBuilder: (_, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final type = TowerType.values[index];
                return _TowerBuildCard(
                  type: type,
                  phase: widget.phase,
                  gold: widget.gold,
                  unlocked: widget.unlockedTowerTypes.contains(type),
                  onPlaceTower: widget.onPlaceTower,
                  onDragStarted: () => _handleDragStarted(type),
                  onDragUpdate: _handleDragUpdate,
                  onDragEnded: _handleDragEnded,
                  onDragCanceled: _handleDragCanceled,
                );
              },
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

  // Artboard 1a's rail card: 70x88, radius 16, a 58px sprite, then the cost,
  // then the name. Ours was 64x92 with a 42px sprite and the name above a
  // bolt-prefixed cost -- the sprite is what the player picks from, so it
  // gets the room, and the cost is the decision, so it outranks the name.
  static const double baseWidth = 70;
  static const double baseHeight = 88;

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
          tier: canAttempt && affordable
              ? OrionSurfaceTier.t3
              : OrionSurfaceTier.t2,
          // No inset: the artboard bottom-aligns the card's contents and
          // lets the sprite overhang the top edge, which is the only way a
          // 58px sprite, a cost and a name fit inside 88px.
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
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        ColorFiltered(
                          colorFilter: unlocked
                              ? const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.dst,
                                )
                              : const ColorFilter.matrix(<double>[
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
                          child: Opacity(
                            opacity: affordable ? 1 : 0.48,
                            child: OrionAtlasSprite(
                              art: OrionArt.tower(type),
                              size: const Size(50, 50),
                            ),
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
                        size: 7.5,
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
      child: LongPressDraggable<TowerType>(
        data: type,
        // The game holds exactly one transient preview; a second concurrent
        // drag would overwrite its type and commit the wrong tower.
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
            size: const Size(48, 48),
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
            style: OrionTypography.microLabel(
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
      child: MissionSurface(
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
