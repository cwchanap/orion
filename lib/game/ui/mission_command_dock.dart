import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'command_frame.dart';
import 'mission_command_hud.dart';
import 'mission_surface.dart';
import 'orion_atlas_sprite.dart';
import 'orion_ui_theme.dart';
import 'tower_inspector.dart';

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
      );
    } else {
      contentKey = const ValueKey('command-dock-idle');
      content = IdleCommandBar(
        snapshot: snapshot,
        onTogglePause: onTogglePause,
        onSpeedSelected: onSpeedSelected,
        onToggleAutoStart: onToggleAutoStart,
        onStartWave: onStartWave,
      );
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
      child: Row(
        children: [
          // Pacing flexes and wraps on narrow viewports; the fixed-size
          // reactor keeps the primary action pinned to the dock's edge.
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
            child: ReactorButton(
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

class TowerBuildRail extends StatelessWidget {
  const TowerBuildRail({
    super.key,
    required this.phase,
    required this.gold,
    required this.unlockedTowerTypes,
    required this.onPlaceTower,
  });

  final GamePhase phase;
  final int gold;
  final List<TowerType> unlockedTowerTypes;
  final ValueChanged<TowerType> onPlaceTower;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3);
    return MissionSurface(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: textScaler.scale(1) * _TowerBuildCard.baseHeight + 12,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          scrollDirection: Axis.horizontal,
          itemCount: TowerType.values.length,
          separatorBuilder: (_, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final type = TowerType.values[index];
            return _TowerBuildCard(
              type: type,
              phase: phase,
              gold: gold,
              unlocked: unlockedTowerTypes.contains(type),
              onPlaceTower: onPlaceTower,
            );
          },
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
  });

  final TowerType type;
  final GamePhase phase;
  final int gold;
  final bool unlocked;
  final ValueChanged<TowerType> onPlaceTower;

  static const double baseWidth = 64;
  static const double baseHeight = 92;

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

    return Semantics(
      button: true,
      enabled: canAttempt,
      label: cardLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        key: ValueKey('tower-card-${type.name}'),
        width: baseWidth * scaleFactor,
        height: baseHeight * scaleFactor,
        child: MissionSurface(
          padding: const EdgeInsets.all(2),
          radius: 10,
          backgroundColor: uiTheme.panelBlue,
          borderColor: accent,
          emphasized: canAttempt && affordable,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: onTap,
              containedInkWell: true,
              highlightShape: BoxShape.rectangle,
              splashColor: accent.withValues(alpha: 0.18),
              highlightColor: accent.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                              size: const Size(42, 42),
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
                    const SizedBox(height: 1),
                    Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: textScaler,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: unlocked
                            ? uiTheme.textPrimary
                            : uiTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 11,
                          color: affordable && unlocked
                              ? uiTheme.creditGold
                              : uiTheme.textMuted,
                        ),
                        const SizedBox(width: 1),
                        Text(
                          '${stats.cost}',
                          maxLines: 1,
                          textScaler: textScaler,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: affordable && unlocked
                                    ? uiTheme.creditGold
                                    : uiTheme.textMuted,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
