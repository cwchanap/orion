import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../orion_defense_game.dart';

class OrionGamePage extends StatefulWidget {
  const OrionGamePage({super.key});

  @override
  State<OrionGamePage> createState() => _OrionGamePageState();
}

class _OrionGamePageState extends State<OrionGamePage> {
  late final OrionDefenseGame _game;

  @override
  void initState() {
    super.initState();
    _game = OrionDefenseGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<GameSnapshot>(
          valueListenable: _game.stateNotifier,
          builder: (context, snapshot, _) {
            return Stack(
              children: [
                Positioned.fill(child: GameWidget(game: _game)),
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: _Hud(snapshot: snapshot),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _BottomControls(game: _game, snapshot: snapshot),
                ),
                if (snapshot.isEnded)
                  Positioned.fill(
                    child: _EndStatePanel(game: _game, snapshot: snapshot),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.snapshot});

  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.86),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orion',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusChip(label: _phaseLabel(snapshot.phase)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(label: 'Base ${snapshot.baseHealth}'),
                _StatusChip(label: 'Gold ${snapshot.gold}'),
                _StatusChip(
                  label:
                      'Wave ${snapshot.waveNumber}/${GameBalance.waves.length}',
                ),
              ],
            ),
            if (snapshot.feedback != null) ...[
              const SizedBox(height: 8),
              Text(
                snapshot.feedback!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final selectedTower = snapshot.selectedTower;
    if (selectedTower != null) {
      return _UpgradePanel(
        key: const ValueKey('upgrade-panel'),
        game: game,
        snapshot: snapshot,
      );
    }

    if (snapshot.selectedCell != null) {
      return _TowerPicker(
        key: const ValueKey('tower-picker'),
        game: game,
        phase: snapshot.phase,
        gold: snapshot.gold,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
      );
    }

    return SizedBox(
      key: const ValueKey('start-wave'),
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: snapshot.canStartWave ? game.startWave : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start Wave'),
      ),
    );
  }
}

class _TowerPicker extends StatelessWidget {
  const _TowerPicker({
    super.key,
    required this.game,
    required this.phase,
    required this.gold,
    required this.unlockedTowerTypes,
  });

  final OrionDefenseGame game;
  final GamePhase phase;
  final int gold;
  final List<TowerType> unlockedTowerTypes;

  @override
  Widget build(BuildContext context) {
    final unlockedTypes = TowerType.values
        .where((type) => unlockedTowerTypes.contains(type))
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Build Tower', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in unlockedTypes)
              _TowerButton(
                label: _towerLabel(type),
                icon: _towerIcon(type),
                stats: GameBalance.towerStats(type, level: 1),
                phase: phase,
                gold: gold,
                onPressed: () => game.placeTower(type),
              ),
          ],
        ),
      ],
    );
  }
}

class _TowerButton extends StatelessWidget {
  const _TowerButton({
    required this.label,
    required this.icon,
    required this.stats,
    required this.phase,
    required this.gold,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final TowerStats stats;
  final GamePhase phase;
  final int gold;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final canPlace = phase == GamePhase.build && gold >= stats.cost;

    return FilledButton.tonalIcon(
      onPressed: canPlace ? onPressed : null,
      icon: Icon(icon),
      label: Text('$label ${stats.cost}'),
    );
  }
}

class _UpgradePanel extends StatelessWidget {
  const _UpgradePanel({super.key, required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tower = snapshot.selectedTower!;
    final stats = GameBalance.towerStats(
      tower.type,
      level: tower.level,
      specialization: tower.specialization,
    );
    final towerName = _towerLabel(tower.type);
    final canUpgrade =
        snapshot.phase == GamePhase.build &&
        tower.canUpgrade &&
        snapshot.gold >= stats.upgradeCost;

    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = _UpgradeActions(
          game: game,
          snapshot: snapshot,
          tower: tower,
          stats: stats,
          canUpgrade: canUpgrade,
          alignment: constraints.maxWidth < 440
              ? WrapAlignment.start
              : WrapAlignment.end,
        );

        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TowerSummary(tower: tower, towerName: towerName),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _TowerSummary(tower: tower, towerName: towerName),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    );
  }
}

class _TowerSummary extends StatelessWidget {
  const _TowerSummary({required this.tower, required this.towerName});

  final PlacedTower tower;
  final String towerName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$towerName Tower',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          tower.specialization == null
              ? 'Level ${tower.level}'
              : 'Level ${tower.level} • ${tower.specialization!.label}',
        ),
      ],
    );
  }
}

class _UpgradeActions extends StatelessWidget {
  const _UpgradeActions({
    required this.game,
    required this.snapshot,
    required this.tower,
    required this.stats,
    required this.canUpgrade,
    required this.alignment,
  });

  final OrionDefenseGame game;
  final GameSnapshot snapshot;
  final PlacedTower tower;
  final TowerStats stats;
  final bool canUpgrade;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    if (tower.canUpgrade) {
      return FilledButton.icon(
        onPressed: canUpgrade ? game.upgradeSelectedTower : null,
        icon: const Icon(Icons.upgrade),
        label: Text('Upgrade ${stats.upgradeCost}'),
      );
    }

    if (tower.canSpecialize) {
      return Wrap(
        alignment: alignment,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final specialization in GameBalance.specializationsFor(
            tower.type,
          ))
            FilledButton.tonalIcon(
              onPressed:
                  snapshot.phase == GamePhase.build &&
                      snapshot.gold >= stats.specializationCost
                  ? () => game.specializeSelectedTower(specialization)
                  : null,
              icon: const Icon(Icons.call_split),
              label: Text(
                '${specialization.label} ${stats.specializationCost}',
              ),
            ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: null,
      icon: const Icon(Icons.check),
      label: const Text('Max'),
    );
  }
}

class _EndStatePanel extends StatelessWidget {
  const _EndStatePanel({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final didWin = snapshot.phase == GamePhase.won;

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  didWin ? Icons.emoji_events : Icons.warning_amber,
                  size: 44,
                  color: didWin
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  didWin ? 'Victory' : 'Base Lost',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: game.restart,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _phaseLabel(GamePhase phase) {
  return switch (phase) {
    GamePhase.build => 'Build',
    GamePhase.wave => 'Wave Active',
    GamePhase.won => 'Won',
    GamePhase.lost => 'Lost',
  };
}

String _towerLabel(TowerType type) {
  return switch (type) {
    TowerType.laser => 'Laser',
    TowerType.rocket => 'Rocket',
    TowerType.cryo => 'Cryo',
    TowerType.railgun => 'Railgun',
    TowerType.ionChain => 'Ion Chain',
    TowerType.nanite => 'Nanite',
    TowerType.gravityWell => 'Gravity Well',
    TowerType.droneBay => 'Drone Bay',
  };
}

IconData _towerIcon(TowerType type) {
  return switch (type) {
    TowerType.laser => Icons.bolt,
    TowerType.rocket => Icons.rocket_launch,
    TowerType.cryo => Icons.ac_unit,
    TowerType.railgun => Icons.linear_scale,
    TowerType.ionChain => Icons.electrical_services,
    TowerType.nanite => Icons.bubble_chart,
    TowerType.gravityWell => Icons.blur_circular,
    TowerType.droneBay => Icons.hub,
  };
}
