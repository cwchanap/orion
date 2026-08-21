import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'command_frame.dart';
import 'orion_atlas_sprite.dart';
import 'orion_ui_theme.dart';
import 'tower_inspector.dart';

class MissionCommandDock extends StatelessWidget {
  const MissionCommandDock({
    super.key,
    required this.snapshot,
    required this.onWorldMap,
    required this.onStartWave,
    required this.onPlaceTower,
    required this.onUpgrade,
    required this.onSpecialize,
    required this.onTargetingChanged,
    required this.onSell,
  });

  final GameSnapshot snapshot;
  final VoidCallback onWorldMap;
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
        onWorldMap: onWorldMap,
        onStartWave: onStartWave,
      );
    }

    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.feedback case final feedback?) ...[
            Text(
              feedback,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 6),
          ],
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
    required this.onWorldMap,
    required this.onStartWave,
  });

  final GameSnapshot snapshot;
  final VoidCallback onWorldMap;
  final VoidCallback onStartWave;

  @override
  Widget build(BuildContext context) {
    final countdown = snapshot.autoStartCountdownRemaining;
    final reactorLabel = _reactorLabel(snapshot, countdown);
    final reactorTooltip = snapshot.phase == GamePhase.wave
        ? 'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}'
        : reactorLabel;
    final stateLabel = _stateLabel(snapshot, countdown);
    final uiTheme = OrionUiTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            container: true,
            label: stateLabel,
            excludeSemantics: true,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MISSION',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: uiTheme.textMuted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _phaseLabel(snapshot.phase),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: snapshot.phase == GamePhase.wave
                            ? uiTheme.warningOrange
                            : uiTheme.systemCyan,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ReactorButton(
            tooltip: 'World Map',
            label: 'World Map',
            icon: Icons.map_outlined,
            onPressed: snapshot.phase == GamePhase.build ? onWorldMap : null,
            size: 68,
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
              size: 68,
            ),
          ),
        ],
      ),
    );
  }

  static String _stateLabel(GameSnapshot snapshot, double? countdown) {
    if (countdown != null) {
      return 'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, '
          'countdown ${countdown.ceil()} seconds';
    }
    return switch (snapshot.phase) {
      GamePhase.build =>
        'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, build phase',
      GamePhase.wave =>
        'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, active',
      GamePhase.won =>
        'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, won',
      GamePhase.lost =>
        'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, lost',
    };
  }

  static String _phaseLabel(GamePhase phase) => switch (phase) {
    GamePhase.build => 'BUILD PHASE',
    GamePhase.wave => 'WAVE ACTIVE',
    GamePhase.won => 'MISSION WON',
    GamePhase.lost => 'MISSION LOST',
  };

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
    return SizedBox(
      height: 104,
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

    return Semantics(
      button: true,
      enabled: canAttempt,
      label: cardLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        key: ValueKey('tower-card-${type.name}'),
        width: 64,
        height: 92,
        child: CommandFrame(
          padding: const EdgeInsets.all(2),
          color: uiTheme.panelBlue,
          borderColor: accent,
          emphasized: canAttempt && affordable,
          chamfer: 8,
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
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.0),
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
                          textScaler: const TextScaler.linear(1),
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
