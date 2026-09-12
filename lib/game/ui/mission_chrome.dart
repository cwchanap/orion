import 'package:flutter/material.dart';

import '../campaign/stage_modifier_metadata.dart';
import '../models/game_models.dart';
import 'acquired_run_module_control.dart';
import 'command_toast.dart';
import 'mission_command_dock.dart';
import 'mission_command_hud.dart';
import 'mission_surface.dart';
import 'next_wave_scanner.dart';
import 'orion_ui_theme.dart';
import 'orion_surface.dart';
import 'hold_to_salvage.dart';

/// Horizontal padding for the top mission overlay band.
const double _commandDeckPadding = 12;

/// The mission's full-screen chrome: the status band, next-wave scanner,
/// toast, and command dock composed over the board. Presentation only — it
/// owns no game reference; every interaction is forwarded through the
/// constructor callbacks.
///
/// The root is a layout-only [LayoutBuilder]/[Stack]: it paints nothing and
/// never hit-tests outside the positioned control bands, so taps on empty
/// chrome space fall through to the board beneath.
class MissionChrome extends StatefulWidget {
  const MissionChrome({
    super.key,
    required this.snapshot,
    required this.onBoardTapIntercept,
    required this.onWorldMap,
    required this.onStartWave,
    required this.onTogglePause,
    required this.onSpeedSelected,
    required this.onToggleAutoStart,
    required this.onPlaceTower,
    required this.onUpgrade,
    required this.onSpecialize,
    required this.onTargetingChanged,
    required this.onSell,
    this.onPlacementPreviewEvent,
    this.towerAnchor,
    this.onInspectTower,
    this.onBoardViewportChanged,
  });

  final GameSnapshot snapshot;
  final ValueChanged<Rect>? onBoardViewportChanged;
  final Offset? towerAnchor;
  final VoidCallback? onInspectTower;

  /// Arbiter for taps over board cells: the collapsed scanner band and the
  /// idle dock forward board-area taps here so the board handles them.
  final bool Function(Offset globalPosition) onBoardTapIntercept;
  final VoidCallback onWorldMap;
  final VoidCallback onStartWave;
  final VoidCallback onTogglePause;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onToggleAutoStart;
  final ValueChanged<TowerType> onPlaceTower;
  final VoidCallback onUpgrade;
  final ValueChanged<TowerSpecialization> onSpecialize;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;
  final VoidCallback onSell;

  /// Closed scene-1e drag-preview event family, forwarded from the dock to
  /// the page. Presentation only — the page maps events onto the game.
  final ValueChanged<TowerPlacementPreviewEvent>? onPlacementPreviewEvent;

  @override
  State<MissionChrome> createState() => _MissionChromeState();
}

class _MissionChromeState extends State<MissionChrome> {
  final _hudKey = GlobalKey();
  final _dockKey = GlobalKey();
  final _scannerKey = GlobalKey();
  Size? _measuredSize;
  double? _measuredTextScale;
  double _topReserve = 0;
  double _bottomReserve = 0;
  Rect? _lastViewport;

  void _measureBoardViewport() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final hud = _hudKey.currentContext?.findRenderObject() as RenderBox?;
    final dock = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || hud == null || dock == null) return;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    if (_measuredSize != box.size || _measuredTextScale != textScale) {
      _measuredSize = box.size;
      _measuredTextScale = textScale;
      _topReserve = 0;
      _bottomReserve = 0;
    }
    // Keep the field stable when selecting a cell or starting a wave makes
    // the dock shorter. Text scaling and viewport changes still get measured.
    final scanner =
        _scannerKey.currentContext?.findRenderObject() as RenderBox?;
    final topBand = scanner ?? hud;
    final top =
        box
            .globalToLocal(
              topBand.localToGlobal(Offset(0, topBand.size.height)),
            )
            .dy +
        8;
    final bottom =
        box.size.height -
        box.globalToLocal(dock.localToGlobal(Offset.zero)).dy +
        8;
    if (top > _topReserve) _topReserve = top;
    if (bottom > _bottomReserve) _bottomReserve = bottom;
    final viewport = Rect.fromLTRB(
      8,
      _topReserve,
      box.size.width - 8,
      (box.size.height - _bottomReserve).clamp(
        _topReserve + 1,
        double.infinity,
      ),
    );
    if (viewport == _lastViewport) return;
    setState(() => _lastViewport = viewport);
    widget.onBoardViewportChanged?.call(viewport);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _measureBoardViewport(),
    );
    final isIdle =
        widget.snapshot.selectedCell == null &&
        widget.snapshot.selectedTower == null;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          // Readouts above the scanner and acquired-module controls.
          Positioned(
            top: _commandDeckPadding,
            left: _commandDeckPadding,
            right: _commandDeckPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IgnorePointer(
                  child: MissionStatusHud(
                    key: _hudKey,
                    snapshot: widget.snapshot,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.snapshot.acquiredRunModules.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: AcquiredRunModuleControl(
                          moduleIds: widget.snapshot.acquiredRunModules,
                          collapseRequested:
                              widget.snapshot.selectedCell != null ||
                              widget.snapshot.selectedTower != null,
                        ),
                      ),
                    ],
                    if (widget.snapshot.phase == GamePhase.build &&
                        widget.snapshot.nextWavePreview != null &&
                        widget.snapshot.pendingRunModuleOffer == null &&
                        !widget.snapshot.isEnded) ...[
                      const SizedBox(width: 6),
                      NextWaveScanner(
                        key: _scannerKey,
                        preview: widget.snapshot.nextWavePreview!,
                        stageId: widget.snapshot.stageId,
                        onStartWave: widget.onStartWave,
                        modifierTitles: widget.snapshot.stageModifiers.isEmpty
                            ? [StageModifierMetadata.standardConditions.title]
                            : widget.snapshot.stageModifiers
                                  .map(
                                    (modifier) =>
                                        StageModifierMetadata.forModifier(
                                          modifier,
                                        ).title,
                                  )
                                  .toList(growable: false),
                        collapseRequested:
                            widget.snapshot.selectedCell != null ||
                            widget.snapshot.selectedTower != null,
                        onCollapsedTapIntercept: widget.onBoardTapIntercept,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (widget.snapshot.selectedTower != null &&
              widget.towerAnchor != null &&
              widget.onInspectTower != null &&
              _lastViewport != null)
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _TowerRadialLayout(
                  widget.towerAnchor!,
                  _lastViewport!,
                ),
                // The automatic desktop scrollbar intercepts the empty gaps.
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    hitTestBehavior: HitTestBehavior.deferToChild,
                    child: TowerRadialActions(
                      snapshot: widget.snapshot,
                      onUpgrade: widget.onUpgrade,
                      onInspect: widget.onInspectTower!,
                      onSell: widget.onSell,
                      onTargetingChanged: widget.onTargetingChanged,
                    ),
                  ),
                ),
              ),
            ),
          // Bottom overlay band: toast + command dock. The idle dock hosts
          // the pacing controls beside the primary action; a selection
          // replaces them with build or inspector controls so the taller dock
          // does not extend farther into the board. While idle, the dock
          // forwards taps over board cells to the board, mirroring the
          // scanner arbiter.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CommandToast(
                  key: const ValueKey('mission-command-toast'),
                  feedback: widget.snapshot.feedback,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTapUp: isIdle
                            ? (details) => widget.onBoardTapIntercept(
                                details.globalPosition,
                              )
                            : null,
                        child: MissionCommandDock(
                          key: _dockKey,
                          snapshot: widget.snapshot,
                          worldMapAction: WorldMapAction(
                            enabled: widget.snapshot.phase == GamePhase.build,
                            onWorldMap: widget.onWorldMap,
                          ),
                          onTogglePause: widget.onTogglePause,
                          onSpeedSelected: widget.onSpeedSelected,
                          onToggleAutoStart: widget.onToggleAutoStart,
                          onStartWave: widget.onStartWave,
                          onPlaceTower: widget.onPlaceTower,
                          onUpgrade: widget.onUpgrade,
                          onSpecialize: widget.onSpecialize,
                          onTargetingChanged: widget.onTargetingChanged,
                          onSell: widget.onSell,
                          onPlacementPreviewEvent:
                              widget.onPlacementPreviewEvent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chrome action for returning to the world map. Owned by the chrome
/// composition (not the dock contract); enabled only while the mission is in
/// its build phase.
///
/// The visible shell is a compact 48dp icon chip at the scanner's scale so
/// the map exit reads as a top-band utility, not a primary control; the full
/// "World Map" label lives in the tooltip and semantics, unchanged.
class WorldMapAction extends StatelessWidget {
  const WorldMapAction({
    super.key,
    required this.enabled,
    required this.onWorldMap,
  });

  final bool enabled;
  final VoidCallback onWorldMap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Tooltip(
      message: 'World Map',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'World Map',
        onTap: enabled ? onWorldMap : null,
        excludeSemantics: true,
        child: GestureDetector(
          // The opaque gesture surface owns the full 48dp chip so taps in
          // every corner reach the action (mirrors the scanner chip).
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onWorldMap : null,
          child: SizedBox.square(
            key: const ValueKey('world-map-action'),
            dimension: 48,
            child: MissionSurface(
              padding: const EdgeInsets.all(10),
              radius: 12,
              child: Icon(
                Icons.map_outlined,
                size: 24,
                color: enabled ? uiTheme.textPrimary : uiTheme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TowerRadialLayout extends SingleChildLayoutDelegate {
  _TowerRadialLayout(this.anchor, this.viewport);
  final Offset anchor;
  final Rect viewport;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: viewport.width, maxHeight: viewport.height);

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.dx - childSize.width / 2).clamp(
      viewport.left,
      viewport.right - childSize.width,
    ),
    (anchor.dy - 88).clamp(viewport.top, viewport.bottom - childSize.height),
  );

  @override
  bool shouldRelayout(_TowerRadialLayout oldDelegate) =>
      anchor != oldDelegate.anchor || viewport != oldDelegate.viewport;
}

class TowerRadialActions extends StatelessWidget {
  const TowerRadialActions({
    super.key,
    required this.snapshot,
    required this.onUpgrade,
    required this.onInspect,
    required this.onSell,
    required this.onTargetingChanged,
  });
  final GameSnapshot snapshot;
  final VoidCallback onUpgrade;
  final VoidCallback onInspect;
  final VoidCallback onSell;
  final ValueChanged<TowerTargetingMode> onTargetingChanged;

  @override
  Widget build(BuildContext context) {
    final tower = snapshot.selectedTower!;
    final stats = snapshot.selectedTowerStats;
    final build = snapshot.phase == GamePhase.build;
    final canUpgrade =
        build &&
        tower.canUpgrade &&
        stats != null &&
        snapshot.gold >= stats.upgradeCost;
    final t = OrionUiTheme.of(context);
    final labelStyle = TextStyle(
      fontFamily: 'Oxanium',
      fontSize: 11,
      color: t.creditGold,
    );
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 196),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OrionSurface(
              tier: OrionSurfaceTier.t1,
              radius: 28,
              padding: EdgeInsets.zero,
              child: IconButton(
                constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
                tooltip: tower.canUpgrade
                    ? 'Upgrade ${stats?.upgradeCost ?? ''}'
                    : 'Specialize tower',
                onPressed: tower.canUpgrade
                    ? (canUpgrade ? onUpgrade : null)
                    : onInspect,
                icon: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tower.canUpgrade ? Icons.upgrade : Icons.auto_awesome,
                      color: t.systemCyan,
                      size: 22,
                    ),
                    if (tower.canUpgrade && stats != null)
                      Text('${stats.upgradeCost}', style: labelStyle),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OrionSurface(
                  tier: OrionSurfaceTier.t1,
                  radius: 28,
                  padding: EdgeInsets.zero,
                  child: SizedBox.square(
                    dimension: 56,
                    child: IconButton(
                      tooltip: 'Inspect tower',
                      onPressed: onInspect,
                      icon: const Icon(Icons.info_outline),
                    ),
                  ),
                ),
                GestureDetector(
                  onLongPress: onInspect,
                  child: const SizedBox.square(dimension: 60),
                ),
                HoldToSalvage(
                  key: ValueKey('radial-salvage-${tower.id}'),
                  compact: true,
                  refund: GameBalance.refundValue(tower),
                  onSell: build ? onSell : null,
                ),
              ],
            ),
            const SizedBox(height: 2),
            OrionSurface(
              tier: OrionSurfaceTier.t1,
              radius: 28,
              padding: EdgeInsets.zero,
              child: IconButton(
                constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
                tooltip:
                    'Targeting: ${tower.targetingMode.label}. Change targeting',
                onPressed: build
                    ? () => onTargetingChanged(
                        TowerTargetingMode.values[(tower.targetingMode.index +
                                1) %
                            TowerTargetingMode.values.length],
                      )
                    : null,
                icon: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.my_location, color: t.systemCyan, size: 22),
                    Text(
                      tower.targetingMode.label.toUpperCase(),
                      style: labelStyle.copyWith(color: t.systemCyan),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
