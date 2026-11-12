import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'mission_command_hud.dart';
import 'orion_atlas_sprite.dart';
import 'orion_primary_button.dart';
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
    this.nextWaveIntel,
    this.towerCardGuideAnchor,
    this.waveGuideAnchorKey,
  });

  final Widget? worldMapAction;
  final Widget? nextWaveIntel;

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
    final worldMapAction = this.worldMapAction;
    Widget railRow(TowerBuildRail rail, {Widget? accessory}) => Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: rail),
          if (accessory != null) ...[const SizedBox(width: 8), accessory],
          if (worldMapAction != null) ...[
            const SizedBox(width: 8),
            worldMapAction,
          ],
        ],
      ),
    );
    if (snapshot.selectedCell != null && snapshot.selectedTower == null) {
      contentKey = const ValueKey('command-dock-build');
      final rail = railRow(
        TowerBuildRail(
          phase: snapshot.phase,
          gold: snapshot.gold,
          unlockedTowerTypes: snapshot.unlockedTowerTypes,
          onPlaceTower: onPlaceTower,
          onPlacementPreviewEvent: onPlacementPreviewEvent,
          // Selected-cell branch only: see [towerCardGuideAnchor].
          towerCardGuideAnchor: towerCardGuideAnchor,
        ),
        accessory: nextWaveIntel,
      );
      content = snapshot.waveHostilesTotal != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _WaveStatusStrip(snapshot: snapshot),
                ),
                const SizedBox(height: 8),
                rail,
              ],
            )
          : rail;
    } else {
      contentKey = const ValueKey('command-dock-idle');
      final idleBar = IdleCommandBar(
        nextWaveIntel: nextWaveIntel,
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
                railRow(
                  TowerBuildRail(
                    key: const ValueKey('command-dock-persistent-rail'),
                    phase: snapshot.phase,
                    gold: snapshot.gold,
                    unlockedTowerTypes: snapshot.unlockedTowerTypes,
                    onPlaceTower: onPlaceTower,
                    onPlacementPreviewEvent: onPlacementPreviewEvent,
                  ),
                ),
              ],
            )
          : snapshot.waveHostilesTotal != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _WaveStatusStrip(snapshot: snapshot),
                ),
                const SizedBox(height: 8),
                idleBar,
              ],
            )
          : idleBar;
    }

    // One full-width shelf groups every dock state.
    return OrionSurface(
      role: OrionSurfaceRole.shelf,
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
    this.nextWaveIntel,
    this.waveGuideAnchorKey,
  });

  final Widget? nextWaveIntel;
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
    final reactorLabel = countdown != null ? 'Start Now' : 'Start Wave';
    final showReactor = snapshot.phase != GamePhase.wave || countdown != null;
    final preview = snapshot.nextWavePreview;
    final showIntel = nextWaveIntel != null && preview != null && showReactor;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final actionWidth = showIntel ? (textScale > 1.15 ? 112.0 : 96.0) : 116.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Widget controls;
          final summaryWidth = showIntel
              ? (constraints.maxWidth - 152 - 48 - actionWidth - 16).clamp(
                  0.0,
                  48.0,
                )
              : 0.0;
          final inlineSummary =
              showIntel &&
              textScale <= 1.3 &&
              summaryWidth >= 22 &&
              summaryWidth < 32;
          if (showReactor &&
              (textScale > 1.3 || (showIntel && summaryWidth < 22))) {
            controls = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MissionPacingControls(
                  snapshot: snapshot,
                  onTogglePause: onTogglePause,
                  onSpeedSelected: onSpeedSelected,
                  onToggleAutoStart: onToggleAutoStart,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (nextWaveIntel != null) ...[
                      nextWaveIntel!,
                      const SizedBox(width: 8),
                    ],
                    if (showIntel) ...[
                      SizedBox(
                        width: 48,
                        child: _IncomingSummary(preview: preview),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: _reactorPill(
                        reactorLabel: reactorLabel,
                        tooltip: reactorLabel,
                        width: double.infinity,
                        label: 'START',
                      ),
                    ),
                  ],
                ),
              ],
            );
          } else {
            // Preserve the three 48dp pacing targets before using spare space
            // for a visible summary beside the existing scanner.
            controls = Row(
              children: [
                Expanded(
                  child: MissionPacingControls(
                    snapshot: snapshot,
                    onTogglePause: onTogglePause,
                    onSpeedSelected: onSpeedSelected,
                    onToggleAutoStart: onToggleAutoStart,
                  ),
                ),
                if (nextWaveIntel != null) ...[
                  const SizedBox(width: 8),
                  nextWaveIntel!,
                ],
                if (summaryWidth >= 22 && !inlineSummary)
                  SizedBox(
                    width: summaryWidth,
                    child: _IncomingSummary(preview: preview!),
                  ),
                if (showReactor) ...[
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
                      tooltip: reactorLabel,
                      width: actionWidth,
                      label: 'START',
                    ),
                  ),
                ],
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              controls,
              if (showIntel)
                _IncomingComposition(
                  key: ValueKey('incoming-composition-${preview.waveNumber}'),
                  preview: preview,
                  inlineSummary: inlineSummary,
                ),
            ],
          );
        },
      ),
    );
  }

  /// The scanner remains the interactive, accessible details control.
  Widget _reactorPill({
    required String reactorLabel,
    required String tooltip,
    required String label,
    required double width,
  }) {
    final onPressed = snapshot.canStartWave ? onStartWave : null;
    final pill = Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        onTap: onPressed,
        excludeSemantics: true,
        child: SizedBox(
          width: width,
          height: 48,
          child: OrionPrimaryButton(
            label: label.toUpperCase(),
            icon: Icons.play_arrow_rounded,
            onPressed: onPressed,
            height: 48,
            labelSize: 10,
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: ValueKey(reactorLabel),
      child: KeyedSubtree(key: waveGuideAnchorKey, child: pill),
    );
  }
}

class _IncomingComposition extends StatefulWidget {
  const _IncomingComposition({
    super.key,
    required this.preview,
    this.inlineSummary = false,
  });

  final WavePreview preview;
  final bool inlineSummary;

  @override
  State<_IncomingComposition> createState() => _IncomingCompositionState();
}

class _IncomingCompositionState extends State<_IncomingComposition> {
  final _scrollController = ScrollController();
  final _largeTextScrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _largeTextScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OrionUiTheme.of(context);
    final bosses = widget.preview.bossGroups.toSet();
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final groups = widget.preview.groups;
    final traits = widget.preview.traits.toList(growable: false);
    Widget groupItem(WavePreviewGroup group) => Semantics(
      label:
          '${group.enemyCount} ${group.label}'
          '${bosses.contains(group) ? ', boss' : ''}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrionAtlasSprite(
            art: OrionArt.previewGroup(group),
            size: const Size.square(22),
          ),
          Text(
            'x${group.enemyCount}',
            style: OrionTypography.readout(
              size: largeText ? 10 : 12,
              color: theme.textPrimary,
            ),
          ),
        ],
      ),
    );
    Widget traitItem(EnemyTrait trait) => Text(
      trait.label.toUpperCase(),
      style: OrionTypography.microLabel(color: theme.warningOrange),
    );
    List<Widget> itemsFor(EnemyTrait? leadingTrait) => <Widget>[
      if (!largeText && !widget.inlineSummary)
        Semantics(
          label: 'Incoming',
          excludeSemantics: true,
          child: Text(
            'INCOMING',
            style: OrionTypography.microLabel(color: theme.textMuted),
          ),
        ),
      if (bosses.isNotEmpty)
        Text(
          'BOSS',
          style: OrionTypography.microLabel(color: theme.warningOrange),
        ),
      if (leadingTrait != null) traitItem(leadingTrait),
      if (groups.isNotEmpty) groupItem(groups.first),
      for (final group in groups.skip(1)) groupItem(group),
      for (final trait in traits)
        if (trait != leadingTrait) traitItem(trait),
    ];
    if (largeText) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final inheritedStyle = DefaultTextStyle.of(context).style;
      final labelMeasure = TextPainter(
        text: TextSpan(
          text: 'BOSS',
          style: inheritedStyle.merge(
            OrionTypography.microLabel(color: theme.textMuted),
          ),
        ),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final countMeasure = TextPainter(
        text: TextSpan(
          text: 'x10',
          style: inheritedStyle.merge(
            OrionTypography.readout(size: 10, color: theme.textPrimary),
          ),
        ),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final lineHeight = math.max(
        22.0,
        math.max(labelMeasure.height, countMeasure.height),
      );
      labelMeasure.dispose();
      countMeasure.dispose();
      // Constrain the preview on short screens and long waves so the board
      // remains usable; its first group and trait stay at the front.
      final shortScreen = MediaQuery.sizeOf(context).height < 700;
      final visibleLines = groups.length > 4 || shortScreen ? 1 : 2;
      final maxHeight = math.min(
        lineHeight * visibleLines + 4,
        MediaQuery.sizeOf(context).height * .25,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double widthOf(String text, TextStyle style) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: text,
                    style: inheritedStyle.merge(style),
                  ),
                  textDirection: direction,
                  textScaler: scaler,
                )..layout();
                final width = painter.width;
                painter.dispose();
                return width;
              }

              final labelStyle = OrionTypography.microLabel(
                color: theme.warningOrange,
              );
              final countStyle = OrionTypography.readout(
                size: 10,
                color: theme.textPrimary,
              );
              final fixedWidth =
                  (bosses.isEmpty ? 0.0 : widthOf('BOSS', labelStyle) + 8) +
                  (groups.isEmpty
                      ? 0.0
                      : 22 +
                            widthOf('x${groups.first.enemyCount}', countStyle) +
                            8);
              final available = constraints.maxWidth - 6 - fixedWidth;
              final leadingTrait = traits.cast<EnemyTrait?>().firstWhere(
                (trait) =>
                    widthOf(trait!.label.toUpperCase(), labelStyle) <=
                    available,
                orElse: () => traits.isEmpty ? null : traits.first,
              );
              return Scrollbar(
                controller: _largeTextScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _largeTextScrollController,
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    container: true,
                    label: 'Incoming enemies',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: itemsFor(leadingTrait),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    final items = itemsFor(traits.firstOrNull);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          if (widget.inlineSummary) ...[
            _IncomingSummary(preview: widget.preview, inline: true),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      items[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingSummary extends StatelessWidget {
  const _IncomingSummary({required this.preview, this.inline = false});

  final WavePreview preview;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = OrionUiTheme.of(context);
    final total = preview.groups.fold<int>(
      0,
      (sum, group) => sum + group.enemyCount,
    );
    if (inline) {
      return ExcludeSemantics(
        child: Row(
          key: const ValueKey('incoming-wave-summary'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$total',
              style: OrionTypography.readout(
                size: 14,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'FOES',
              style: OrionTypography.microLabel(color: theme.textMuted),
            ),
          ],
        ),
      );
    }
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('incoming-wave-summary'),
        height: 48,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: OrionTypography.readout(
                  size: 14,
                  color: theme.textPrimary,
                ),
              ),
              Text(
                'FOES',
                style: OrionTypography.microLabel(color: theme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveStatusStrip extends StatelessWidget {
  const _WaveStatusStrip({required this.snapshot});

  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final total = snapshot.waveHostilesTotal;
    final remaining = snapshot.waveHostilesRemaining;
    final bonus = snapshot.waveClearBonus;
    if (total == null || remaining == null || bonus == null) {
      return const SizedBox.shrink();
    }
    final resolved = total - remaining;
    final progress = total <= 0
        ? 0.0
        : (resolved / total).clamp(0.0, 1.0).toDouble();
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final waveLabel = Text(
      'Wave ${snapshot.waveNumber}',
      maxLines: 1,
      style: OrionTypography.microLabel(
        color: uiTheme.textMuted,
        size: largeText ? 10 : 11,
      ),
    );
    final remainingLabel = Container(
      key: const ValueKey('mission-hostiles-remaining'),
      child: Text(
        '$remaining hostiles left',
        style: OrionTypography.microLabel(color: uiTheme.dangerRed, size: 11),
      ),
    );
    final bonusBadge = Semantics(
      label: 'Clear bonus $bonus credits',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('mission-clear-bonus'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: uiTheme.creditGold.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: uiTheme.creditGold.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hexagon, size: 13, color: uiTheme.creditGold),
            const SizedBox(width: 4),
            Text(
              '+$bonus clear',
              maxLines: 1,
              style: OrionTypography.microLabel(
                color: uiTheme.creditGold,
                size: largeText ? 10 : 11,
              ),
            ),
          ],
        ),
      ),
    );
    return OrionSurface(
      role: OrionSurfaceRole.card,
      radius: 14,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largeText)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [waveLabel, bonusBadge, remainingLabel],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      waveLabel,
                      Text(
                        '·',
                        style: OrionTypography.microLabel(
                          color: uiTheme.textDim,
                          size: 11,
                        ),
                      ),
                      remainingLabel,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                bonusBadge,
              ],
            ),
          const SizedBox(height: 8),
          SizedBox(
            key: const ValueKey('mission-wave-progress'),
            height: 9,
            child: Semantics(
              value: '$resolved of $total hostiles resolved',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.5),
                child: ColoredBox(
                  color: uiTheme.hullBlack,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [uiTheme.dangerRed, uiTheme.warningOrange],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
  Widget _buildCard(TowerType type, double cardHeight) {
    final card = _TowerBuildCard(
      type: type,
      cardHeight: cardHeight,
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
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final cardHeight = compact
        ? _largeTextTowerCardHeight(context)
        : textScaler.scale(1) * _TowerBuildCard.baseHeight;
    return Padding(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: cardHeight + 12,
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
                              child: _buildCard(type, cardHeight),
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

double _largeTextTowerCardHeight(BuildContext context) {
  final uiTheme = OrionUiTheme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final inheritedStyle = DefaultTextStyle.of(context).style;
  double heightOf(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: inheritedStyle.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final labelsHeight =
      heightOf('LASER', OrionTypography.microLabel(color: uiTheme.textMuted)) +
      heightOf(
        '50',
        OrionTypography.readout(
          size: _largeTextTowerCostSize(scaler),
          color: uiTheme.creditGold,
        ),
      );
  return math.max(_TowerBuildCard.compactHeight, labelsHeight + 10);
}

// Preserve the price hierarchy at the compact-layout threshold without
// letting a hero-sized price consume the whole battlefield at 3x.
double _largeTextTowerCostSize(TextScaler scaler) => 10 + 6 / scaler.scale(1);

class _TowerBuildCard extends StatelessWidget {
  const _TowerBuildCard({
    required this.type,
    required this.cardHeight,
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
  final double cardHeight;
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
  static const double compactHeight = 90;

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
    final requestedScaler = MediaQuery.textScalerOf(context);
    final compact = requestedScaler.scale(1) > 1.3;
    final textScaler = requestedScaler;
    final scaleFactor = textScaler.scale(1);
    final sprite = OrionAtlasSprite(
      art: OrionArt.tower(type),
      size: const Size(58, 58),
    );
    final nameStyle = OrionTypography.microLabel(
      size: 10,
      color: uiTheme.textMuted,
    );
    final priceStyle = OrionTypography.readout(
      size: compact ? _largeTextTowerCostSize(textScaler) : 14,
      color: !unlocked
          ? uiTheme.textMuted
          : affordable
          ? uiTheme.creditGold
          : uiTheme.dangerRed,
    );
    double textWidth(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final cardWidth = compact
        ? math.max(
            baseWidth,
            58.0 +
                math.max(
                  textWidth(type.label.toUpperCase(), nameStyle),
                  textWidth('${stats.cost}', priceStyle),
                ),
          )
        : baseWidth * scaleFactor;
    final art = FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: affordable ? 1 : 0.48,
            child: unlocked
                ? sprite
                : ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
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
            Icon(Icons.lock_outline, size: 17, color: uiTheme.textMuted),
        ],
      ),
    );
    final price = Text(
      '${stats.cost}',
      maxLines: 1,
      textScaler: textScaler,
      style: priceStyle,
    );
    final name = Text(
      type.label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      textScaler: textScaler,
      style: nameStyle,
    );

    final card = Semantics(
      button: true,
      enabled: canAttempt,
      label: cardLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        key: ValueKey('tower-card-${type.name}'),
        width: cardWidth,
        height: cardHeight,
        child: OrionSurface(
          role: OrionSurfaceRole.card,
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
                child: compact
                    ? Row(
                        children: [
                          SizedBox(width: 42, child: art),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [name, price],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(child: art),
                          const SizedBox(height: 2),
                          price,
                          const SizedBox(height: 1),
                          name,
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
        childWhenDragging: _buildLiftedSource(context, cardWidth, cardHeight),
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
  Widget _buildLiftedSource(
    BuildContext context,
    double cardWidth,
    double cardHeight,
  ) {
    final uiTheme = OrionUiTheme.of(context);
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: OrionSurface(
        role: OrionSurfaceRole.card,
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
