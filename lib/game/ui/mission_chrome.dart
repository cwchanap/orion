import 'package:flutter/material.dart';

import '../campaign/stage_modifier_metadata.dart';
import '../models/game_models.dart';
import 'command_frame.dart';
import 'command_toast.dart';
import 'mission_command_dock.dart';
import 'mission_command_hud.dart';
import 'next_wave_scanner.dart';
import 'run_module_draft_panel.dart';

/// Horizontal padding for the top and bottom mission overlay bands.
const double _commandDeckPadding = 12;

/// The mission's full-screen chrome: the status band, next-wave scanner,
/// toast, and command dock composed over the board. Presentation only — it
/// owns no state and holds no game reference; every interaction is forwarded
/// through the constructor callbacks.
///
/// The root is a layout-only [LayoutBuilder]/[Stack]: it paints nothing and
/// never hit-tests outside the positioned control bands, so taps on empty
/// chrome space fall through to the board beneath.
class MissionChrome extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isIdle =
        snapshot.selectedCell == null && snapshot.selectedTower == null;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          // Top overlay band: a single row of status chrome — the
          // non-interactive status HUD and acquired-module strip
          // (IgnorePointer so taps pass through to the board) alongside the
          // interactive scanner. The module strip renders at its natural
          // wrapped height: any growth extends downward over
          // pointer-transparent territory only, so all acquired modules stay
          // visible and nothing interactive below them moves.
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
                    child: IgnorePointer(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 132),
                        child: AcquiredRunModuleStrip(
                          moduleIds: snapshot.acquiredRunModules,
                        ),
                      ),
                    ),
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
                    onCollapsedTapIntercept: onBoardTapIntercept,
                  ),
                ],
              ],
            ),
          ),
          // Bottom overlay band: toast + command dock. The idle dock hosts
          // the pacing controls beside the primary action; a selection
          // replaces them with build or inspector controls so the taller dock
          // does not extend farther into the board. World Map rides beside
          // the dock only while it idles, keeping selection surfaces at full
          // dock width. While idle, the dock forwards taps over board cells
          // to the board, mirroring the scanner arbiter.
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
                            ? (details) =>
                                  onBoardTapIntercept(details.globalPosition)
                            : null,
                        child: MissionCommandDock(
                          snapshot: snapshot,
                          onTogglePause: onTogglePause,
                          onSpeedSelected: onSpeedSelected,
                          onToggleAutoStart: onToggleAutoStart,
                          onStartWave: onStartWave,
                          onPlaceTower: onPlaceTower,
                          onUpgrade: onUpgrade,
                          onSpecialize: onSpecialize,
                          onTargetingChanged: onTargetingChanged,
                          onSell: onSell,
                        ),
                      ),
                    ),
                    if (isIdle) ...[
                      const SizedBox(width: 6),
                      WorldMapAction(
                        enabled: snapshot.phase == GamePhase.build,
                        onWorldMap: onWorldMap,
                      ),
                    ],
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
