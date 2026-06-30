import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/campaign_progress_store.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../models/game_models.dart';
import '../orion_defense_game.dart';
import 'world_map_view.dart';

class OrionGamePage extends StatefulWidget {
  const OrionGamePage({
    super.key,
    this.progressStore,
    this.progressStoreLoader,
    this.onGameCreated,
  });

  final CampaignProgressStore? progressStore;
  final Future<CampaignProgressStore> Function()? progressStoreLoader;
  final ValueChanged<OrionDefenseGame>? onGameCreated;

  @override
  State<OrionGamePage> createState() => _OrionGamePageState();
}

class _OrionGamePageState extends State<OrionGamePage> {
  OrionDefenseGame? _game;
  CampaignProgress _progress = CampaignProgress();
  CampaignProgressStore? _store;
  StageDefinition? _activeStage;
  String? _mapFeedback;
  bool _isLoading = true;
  int _progressGeneration = 0;
  Future<void> _clearSaveQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    CampaignProgressStore? store = widget.progressStore;

    try {
      if (store == null) {
        final loader = widget.progressStoreLoader;
        if (loader != null) {
          store = await loader();
        } else {
          final preferences = await SharedPreferences.getInstance();
          store = SharedPreferencesCampaignProgressStore(
            preferences: preferences,
            knownStages: OrionCampaign.stages,
          );
        }
      }

      final progress = await store.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _store = store;
        _progress = progress;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _store = store;
        _progress = CampaignProgress();
        _mapFeedback = 'Could not load campaign progress.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final game = _game;
    if (_activeStage == null || game == null) {
      return Scaffold(
        body: WorldMapView(
          stages: OrionCampaign.stages,
          progress: _progress,
          feedback: _mapFeedback,
          onStageSelected: _startStage,
          onLockedStageSelected: _showLockedStageFeedback,
          onResetCampaign: _confirmResetCampaign,
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<GameSnapshot>(
          valueListenable: game.stateNotifier,
          builder: (context, snapshot, _) {
            return Stack(
              children: [
                Positioned.fill(child: GameWidget(game: game)),
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: IgnorePointer(
                    ignoring: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Hud(snapshot: snapshot),
                        if (snapshot.nextWavePreview != null) ...[
                          const SizedBox(height: 8),
                          _NextWavePanel(preview: snapshot.nextWavePreview!),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _BottomControls(game: game, snapshot: snapshot),
                ),
                if (snapshot.isEnded)
                  Positioned.fill(
                    child: _EndStatePanel(game: game, snapshot: snapshot),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _startStage(StageDefinition stage) {
    if (!_progress.isUnlocked(stage)) {
      _showLockedStageFeedback(stage);
      return;
    }

    final game = OrionDefenseGame(
      stage: stage,
      onStageWon: _markStageCleared,
      onReturnToMap: _returnToMap,
    );
    widget.onGameCreated?.call(game);

    setState(() {
      _activeStage = stage;
      _mapFeedback = null;
      _game = game;
    });
  }

  void _showLockedStageFeedback(StageDefinition stage) {
    setState(() {
      _mapFeedback = '${stage.name} is locked.';
    });
  }

  Future<void> _markStageCleared(StageDefinition stage) async {
    final saveGeneration = _progressGeneration;
    final saveTask = _clearSaveQueue.then(
      (_) => _saveStageClear(stage, saveGeneration),
    );
    _clearSaveQueue = saveTask.catchError((_) {});
    await saveTask;
  }

  Future<void> _saveStageClear(
    StageDefinition stage,
    int saveGeneration,
  ) async {
    final store = _store;
    if (store == null) {
      _showCampaignPersistenceFailure();
      return;
    }

    if (saveGeneration != _progressGeneration) {
      return;
    }

    final progress = _progress.markCleared(stage.id);
    try {
      await store.save(progress);
    } catch (_) {
      if (!mounted || saveGeneration != _progressGeneration) {
        return;
      }

      _showCampaignPersistenceFailure();
      return;
    }

    if (!mounted) {
      return;
    }

    if (saveGeneration != _progressGeneration) {
      await _resetStoreAfterStaleClearSave(store);
      return;
    }

    setState(() {
      _progress = progress;
    });
  }

  void _returnToMap() {
    setState(() {
      _activeStage = null;
      _game = null;
    });
  }

  Future<void> _confirmResetCampaign() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset Campaign'),
          content: const Text('Clear all campaign progress?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) {
      return;
    }

    final store = _store;
    if (store == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _mapFeedback = 'Could not reset campaign progress.';
      });
      return;
    }

    try {
      await store.reset();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _mapFeedback = 'Could not reset campaign progress.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    _progressGeneration++;

    setState(() {
      _progress = CampaignProgress();
      _activeStage = null;
      _game = null;
      _mapFeedback = 'Campaign reset.';
    });
  }

  Future<void> _resetStoreAfterStaleClearSave(
    CampaignProgressStore store,
  ) async {
    try {
      await store.reset();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _mapFeedback = 'Could not reset campaign progress.';
      });
    }
  }

  void _showCampaignPersistenceFailure() {
    const message = 'Could not save campaign progress.';
    final game = _game;

    setState(() {
      _mapFeedback = message;
    });

    if (_activeStage != null && game != null) {
      final snapshot = game.stateNotifier.value;
      game.stateNotifier.value = GameSnapshot(
        phase: snapshot.phase,
        gold: snapshot.gold,
        baseHealth: snapshot.baseHealth,
        waveNumber: snapshot.waveNumber,
        waveTotal: snapshot.waveTotal,
        stageId: snapshot.stageId,
        stageName: snapshot.stageName,
        stageLabel: snapshot.stageLabel,
        unlockedTowerTypes: snapshot.unlockedTowerTypes,
        nextWavePreview: snapshot.nextWavePreview,
        selectedCell: snapshot.selectedCell,
        selectedTower: snapshot.selectedTower,
        feedback: message,
        isPaused: snapshot.isPaused,
        speedMultiplier: snapshot.speedMultiplier,
        autoStartEnabled: snapshot.autoStartEnabled,
        autoStartCountdownRemaining: snapshot.autoStartCountdownRemaining,
      );
    }
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
                    snapshot.stageName,
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
                  label: 'Wave ${snapshot.waveNumber}/${snapshot.waveTotal}',
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

class _NextWavePanel extends StatelessWidget {
  const _NextWavePanel({required this.preview});

  final WavePreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommendations = preview.recommendedTowerTypes
        .map(_towerLabel)
        .join(', ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Next Wave ${preview.waveNumber}/${preview.waveTotal}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (preview.groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in preview.groups)
                    _StatusChip(label: '${group.enemyCount} ${group.label}'),
                ],
              ),
            ],
            if (preview.traits.isNotEmpty || preview.clearBonus > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final trait in preview.traits)
                    _StatusChip(label: _enemyTraitLabel(trait)),
                  if (preview.clearBonus > 0)
                    _StatusChip(label: 'Clear bonus ${preview.clearBonus}'),
                ],
              ),
            ],
            if (recommendations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Recommended: $recommendations',
                style: theme.textTheme.bodyMedium,
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

    return Column(
      key: const ValueKey('start-wave'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PacingControls(game: game, snapshot: snapshot),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'World Map',
              onPressed: snapshot.phase == GamePhase.wave
                  ? null
                  : game.returnToMap,
              icon: const Icon(Icons.map),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: snapshot.canStartWave ? game.startWave : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  snapshot.autoStartCountdownRemaining == null
                      ? 'Start Wave'
                      : 'Start Now',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PacingControls extends StatelessWidget {
  const _PacingControls({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final canUsePacing = !snapshot.isEnded;
    final canTogglePause =
        canUsePacing &&
        (snapshot.phase == GamePhase.wave ||
            snapshot.autoStartCountdownRemaining != null ||
            snapshot.isPaused);
    final countdown = snapshot.autoStartCountdownRemaining;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: snapshot.isPaused ? 'Resume' : 'Pause',
          onPressed: canTogglePause ? game.togglePause : null,
          icon: Icon(snapshot.isPaused ? Icons.play_arrow : Icons.pause),
        ),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<double>(value: 1.0, label: Text('1x')),
            ButtonSegment<double>(value: 2.0, label: Text('2x')),
            ButtonSegment<double>(value: 3.0, label: Text('3x')),
          ],
          selected: {snapshot.speedMultiplier},
          onSelectionChanged: canUsePacing
              ? (selection) => game.setSpeedMultiplier(selection.single)
              : null,
        ),
        FilterChip(
          tooltip: 'Auto-start waves',
          label: const Text('Auto'),
          selected: snapshot.autoStartEnabled,
          onSelected: canUsePacing ? (_) => game.toggleAutoStart() : null,
        ),
        if (countdown != null) _StatusChip(label: 'Next ${countdown.ceil()}s'),
      ],
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: game.restart,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Restart'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: game.returnToMap,
                      icon: const Icon(Icons.map),
                      label: const Text('World Map'),
                    ),
                  ],
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

String _enemyTraitLabel(EnemyTrait trait) {
  return switch (trait) {
    EnemyTrait.armored => 'Armored',
    EnemyTrait.shielded => 'Shielded',
    EnemyTrait.swarm => 'Swarm',
    EnemyTrait.regen => 'Regen',
    EnemyTrait.heavy => 'Heavy',
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
