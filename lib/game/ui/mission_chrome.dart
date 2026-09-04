import 'package:flutter/material.dart';

import '../campaign/stage_modifier_metadata.dart';
import '../models/game_models.dart';
import 'acquired_run_module_control.dart';
import 'command_frame.dart';
import 'command_toast.dart';
import 'mission_command_dock.dart';
import 'mission_command_hud.dart';
import 'next_wave_scanner.dart';

/// Horizontal padding for the top and bottom mission overlay bands.
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
  });

  final GameSnapshot snapshot;

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

  @override
  State<MissionChrome> createState() => _MissionChromeState();
}

class _MissionChromeState extends State<MissionChrome> {
  /// Whether each top-band panel is currently borrowing the band's width.
  /// Tracked independently so collapsing one panel never reinserts the idle
  /// World Map action while the other is still expanded — which would steal
  /// width from the still-open panel at the product viewport. The idle World
  /// Map action yields while either is expanded, so the status HUD never
  /// drops below its minimum width.
  bool _scannerExpanded = false;
  bool _modulesExpanded = false;

  bool get _anyTopPanelExpanded => _scannerExpanded || _modulesExpanded;

  void _handleScannerExpanded(bool expanded) {
    if (_scannerExpanded != expanded) {
      setState(() => _scannerExpanded = expanded);
    }
  }

  void _handleModulesExpanded(bool expanded) {
    if (_modulesExpanded != expanded) {
      setState(() => _modulesExpanded = expanded);
    }
  }

  @override
  void didUpdateWidget(covariant MissionChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Panels snap shut without a toggle when a selection requests collapse
    // or their reset token rolls (new wave preview, module list change);
    // mirror those resets so the World Map action cannot stay hidden behind
    // a panel that is no longer expanded. Each panel's MissionCollapsible
    // only closes on its own token change, so reset clears only the matching
    // flag — clearing both would desync from a still-expanded panel whose
    // token is unchanged and reinsert World Map to steal its width. A
    // selection activation raises collapseRequested on both panels, so it
    // clears both.
    final snapshot = widget.snapshot;
    final oldSnapshot = oldWidget.snapshot;
    final selectionActivated =
        (snapshot.selectedCell != null || snapshot.selectedTower != null) &&
        (oldSnapshot.selectedCell == null && oldSnapshot.selectedTower == null);
    final scannerResetTokenChanged =
        snapshot.nextWavePreview?.waveNumber !=
        oldSnapshot.nextWavePreview?.waveNumber;
    final modulesResetTokenChanged =
        Object.hashAll(snapshot.acquiredRunModules) !=
        Object.hashAll(oldSnapshot.acquiredRunModules);
    if (_scannerExpanded && (selectionActivated || scannerResetTokenChanged)) {
      _scannerExpanded = false;
    }
    if (_modulesExpanded && (selectionActivated || modulesResetTokenChanged)) {
      _modulesExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final isIdle =
        snapshot.selectedCell == null && snapshot.selectedTower == null;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          // Top overlay band: a single row of status chrome — the
          // non-interactive status HUD alongside the interactive acquired-
          // module details control (it collapses while a board/tower
          // selection is active), the idle-only World Map mission action,
          // and the interactive scanner.
          Positioned(
            top: _commandDeckPadding,
            left: _commandDeckPadding,
            right: _commandDeckPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: IgnorePointer(
                    child: MissionStatusHud(snapshot: snapshot),
                  ),
                ),
                if (snapshot.acquiredRunModules.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: AcquiredRunModuleControl(
                      moduleIds: snapshot.acquiredRunModules,
                      collapseRequested:
                          snapshot.selectedCell != null ||
                          snapshot.selectedTower != null,
                      onExpandedChanged: _handleModulesExpanded,
                    ),
                  ),
                ],
                // World Map rides in the top band only while idle and while
                // no expanded panel needs the width, keeping the bottom band
                // a single-row dock at the product width.
                if (isIdle && !_anyTopPanelExpanded) ...[
                  const SizedBox(width: 6),
                  WorldMapAction(
                    enabled: snapshot.phase == GamePhase.build,
                    onWorldMap: widget.onWorldMap,
                  ),
                ],
                if (snapshot.phase == GamePhase.build &&
                    snapshot.nextWavePreview != null &&
                    snapshot.pendingRunModuleOffer == null &&
                    !snapshot.isEnded) ...[
                  const SizedBox(width: 6),
                  NextWaveScanner(
                    preview: snapshot.nextWavePreview!,
                    modifierTitles: snapshot.stageModifiers.isEmpty
                        ? [StageModifierMetadata.standardConditions.title]
                        : snapshot.stageModifiers
                              .map(
                                (modifier) => StageModifierMetadata.forModifier(
                                  modifier,
                                ).title,
                              )
                              .toList(growable: false),
                    collapseRequested:
                        snapshot.selectedCell != null ||
                        snapshot.selectedTower != null,
                    onCollapsedTapIntercept: widget.onBoardTapIntercept,
                    onExpandedChanged: _handleScannerExpanded,
                  ),
                ],
              ],
            ),
          ),
          // Bottom overlay band: toast + command dock. The idle dock hosts
          // the pacing controls beside the primary action; a selection
          // replaces them with build or inspector controls so the taller dock
          // does not extend farther into the board. While idle, the dock
          // forwards taps over board cells to the board, mirroring the
          // scanner arbiter.
          Positioned(
            left: _commandDeckPadding,
            right: _commandDeckPadding,
            bottom: _commandDeckPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CommandToast(
                  key: const ValueKey('mission-command-toast'),
                  feedback: snapshot.feedback,
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
                          snapshot: snapshot,
                          onTogglePause: widget.onTogglePause,
                          onSpeedSelected: widget.onSpeedSelected,
                          onToggleAutoStart: widget.onToggleAutoStart,
                          onStartWave: widget.onStartWave,
                          onPlaceTower: widget.onPlaceTower,
                          onUpgrade: widget.onUpgrade,
                          onSpecialize: widget.onSpecialize,
                          onTargetingChanged: widget.onTargetingChanged,
                          onSell: widget.onSell,
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
    return ReactorButton(
      tooltip: 'World Map',
      label: 'World Map',
      icon: Icons.map_outlined,
      onPressed: enabled ? onWorldMap : null,
    );
  }
}
