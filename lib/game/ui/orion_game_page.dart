import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/campaign_progress_store.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/tech_tree.dart';
import '../models/game_models.dart';
import '../orion_defense_game.dart';
import 'tech_tree_view.dart';
import 'world_map_view.dart';

enum _ShellView { worldMap, techTree, stage }

/// Persistence-failure breadcrumb surfaced on both the active view and the
/// world map. Hoisted to a top-level constant so retry paths can match and
/// clear the stale map breadcrumb without re-string-literalizing it.
const String _persistenceFailureMessage = 'Could not save campaign progress.';

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
  CampaignTechTree _techTree = CampaignTechTree();
  // Last-known committed disk state. Queued saves compose their payload from
  // this rather than the shared optimistic `_progress`/`_techTree` aggregate,
  // so a later transaction's mutation cannot be persisted under an earlier
  // save that subsequently fails (round-4 review P1). Advanced inside the
  // save queue on each successful write; reset to empty on a successful reset.
  CampaignProgress _committedProgress = CampaignProgress();
  CampaignTechTree _committedTechTree = CampaignTechTree();
  CampaignProgressStore? _store;
  String? _mapFeedback;
  String? _techTreeFeedback;
  _ShellView _activeView = _ShellView.worldMap;
  bool _isLoading = true;
  int _progressGeneration = 0;
  Future<void> _saveQueue = Future<void>.value();
  int _pendingSaves = 0;
  bool _isSavingProgress = false;
  bool _isResetting = false;

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

      final save = await store.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _store = store;
        _progress = save.progress;
        _techTree = save.techTree;
        _committedProgress = save.progress;
        _committedTechTree = save.techTree;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _store = store;
        _progress = CampaignProgress();
        _techTree = CampaignTechTree();
        _committedProgress = CampaignProgress();
        _committedTechTree = CampaignTechTree();
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

    switch (_activeView) {
      case _ShellView.worldMap:
        return _buildWorldMapScaffold();
      case _ShellView.techTree:
        return TechTreeView(
          progress: _progress,
          techTree: _techTree,
          feedback: _techTreeFeedback,
          isSavingProgress: _isSavingProgress,
          onPurchase: _purchaseTech,
          onBack: _closeTechTree,
        );
      case _ShellView.stage:
        return _buildStageScaffold();
    }
  }

  Widget _buildWorldMapScaffold() {
    return Scaffold(
      body: WorldMapView(
        stages: OrionCampaign.stages,
        progress: _progress,
        campaignModifiers: CampaignModifiers.fromProgress(
          _progress,
          OrionCampaign.stages,
          _techTree,
        ),
        feedback: _mapFeedback,
        isSavingProgress: _isSavingProgress,
        isResetting: _isResetting,
        onStageSelected: _showStageBriefing,
        onLockedStageSelected: _showLockedStageFeedback,
        onResetCampaign: _confirmResetCampaign,
        onOpenTechTree: _openTechTree,
      ),
    );
  }

  Widget _buildStageScaffold() {
    final game = _game;
    if (game == null) {
      // Defensive: _activeView == stage implies _game is set, but if state
      // ever drifts we fall back to the world map rather than crashing.
      return _buildWorldMapScaffold();
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
                          _NextWavePanel(
                            preview: snapshot.nextWavePreview!,
                            modifierTitles: snapshot.stageModifiers.isEmpty
                                ? [
                                    StageModifierMetadata
                                        .standardConditions
                                        .title,
                                  ]
                                : snapshot.stageModifiers
                                      .map(
                                        (modifier) =>
                                            StageModifierMetadata.forModifier(
                                              modifier,
                                            ).title,
                                      )
                                      .toList(growable: false),
                          ),
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

  Future<void> _showStageBriefing(StageDefinition stage) async {
    final shouldStart = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _StageBriefingSheet(
        stage: stage,
        result: _progress.resultFor(stage.id),
      ),
    );

    if (shouldStart == true && mounted) {
      _startStage(stage);
    }
  }

  void _startStage(StageDefinition stage) {
    if (_isSavingProgress || _isResetting) {
      setState(() {
        _mapFeedback = _isResetting
            ? 'Resetting campaign…'
            : 'Saving campaign progress…';
      });
      return;
    }

    if (!_progress.isUnlocked(stage)) {
      _showLockedStageFeedback(stage);
      return;
    }

    final campaignModifiers = CampaignModifiers.fromProgress(
      _progress,
      OrionCampaign.stages,
      _techTree,
    );
    final game = OrionDefenseGame(
      stage: stage,
      campaignModifiers: campaignModifiers,
      onStageWon: _saveStageCompletion,
      onReturnToMap: _returnToMap,
    );
    widget.onGameCreated?.call(game);

    setState(() {
      _mapFeedback = null;
      _game = game;
      _activeView = _ShellView.stage;
    });
  }

  void _showLockedStageFeedback(StageDefinition stage) {
    setState(() {
      _mapFeedback = '${stage.name} is locked.';
    });
  }

  void _openTechTree() {
    setState(() {
      _techTreeFeedback = null;
      _activeView = _ShellView.techTree;
    });
  }

  // Wired up by TechTreeView's back button.
  void _closeTechTree() {
    setState(() {
      _techTreeFeedback = null;
      _activeView = _ShellView.worldMap;
    });
  }

  // Invoked by TechTreeView purchase buttons.
  Future<void> _purchaseTech(CampaignTechUpgrade upgrade) async {
    if (_isSavingProgress || _isResetting) {
      return; // matches stage-launch guard; UI also disables the button
    }
    // Clear any prior failure feedback so a stale error doesn't persist
    // after the next successful purchase (tech-tree-design.md:395).
    if (_techTreeFeedback != null) {
      setState(() {
        _techTreeFeedback = null;
      });
    }
    // P2 (round-4 review): also clear the matching map breadcrumb. A failed
    // purchase writes the persistence-failure message into _mapFeedback; the
    // retry previously cleared only _techTreeFeedback, so returning to the
    // world map after a successful retry still showed the stale error.
    if (_mapFeedback == _persistenceFailureMessage) {
      setState(() {
        _mapFeedback = null;
      });
    }
    final newTechTree = _techTree.purchase(upgrade, _progress);
    await _persistSave(
      nextTechTree: newTechTree,
      buildSave: (committed) => CampaignSave(
        progress: committed.progress,
        techTree: committed.techTree.purchase(upgrade, committed.progress),
      ),
      rollback: () => _techTree = _techTree.withoutUpgrade(upgrade),
    );
  }

  Future<void> _persistSave({
    CampaignProgress? nextProgress,
    CampaignTechTree? nextTechTree,
    required CampaignSave Function(CampaignSave committed) buildSave,
    required VoidCallback rollback,
  }) async {
    final store = _store;
    if (store == null) {
      _showCampaignPersistenceFailure();
      return;
    }

    final saveGeneration = _progressGeneration;

    // Optimistic update: scoped to provided fields. Applied immediately so
    // the UI reflects the change without waiting for the queued save to run.
    if (nextProgress != null) _progress = nextProgress;
    if (nextTechTree != null) _techTree = nextTechTree;
    _pendingSaves++;
    _setSavingProgress(true);

    // Queue the COMPLETE transaction — persistence, targeted rollback, and
    // saving-state reconciliation — so the next writer cannot start until
    // this one has committed or rolled back.
    //
    // The persisted payload is built from the last-known committed disk state
    // (_committed*), NOT from the shared optimistic _progress/_techTree
    // aggregate. Reading the aggregate let an earlier successful save persist
    // a later transaction's mutation: if saves A and B were queued
    // synchronously, save A wrote A+B (the aggregate already held both
    // optimistic updates), then save B failed and rolled B back in memory
    // while B remained on disk — reopening the app resurrected a result whose
    // save reported failure (round-4 review P1). Building from _committed*
    // scopes each save's payload to its own delta; on success _committed*
    // advances so the next queued save composes on top of it. A per-call
    // snapshot would not suffice, because a later snapshot could still carry
    // an earlier mutation that eventually fails.
    final saveTask = _saveQueue.then((_) async {
      try {
        if (saveGeneration != _progressGeneration) {
          return; // a reset invalidated this save; the reset owns wiping
        }
        final payload = buildSave(
          CampaignSave(
            progress: _committedProgress,
            techTree: _committedTechTree,
          ),
        );
        await store.save(payload);
        if (saveGeneration == _progressGeneration) {
          _committedProgress = payload.progress;
          _committedTechTree = payload.techTree;
        }
      } catch (_) {
        if (saveGeneration == _progressGeneration) {
          rollback();
          // UI feedback is guarded by mounted: the rollback must still run
          // after disposal (it only mutates in-memory state), but calling
          // setState on a defunct State is a debug assertion violation
          // (round-5 review P2).
          if (mounted) {
            _showCampaignPersistenceFailure();
          }
        }
      } finally {
        _decrementPendingSaves();
      }
    });
    _saveQueue = saveTask.catchError((_) {});
  }

  Future<void> _saveStageCompletion(StageCompletion completion) {
    if (_isResetting) {
      return Future<void>.value();
    }
    final stageId = completion.stage.id;
    final priorResult = _progress.resultFor(stageId);
    final newProgress = _progress.recordResult(stageId, completion.result);
    // recordResult returns the same instance when the new result is not an
    // improvement; compare the stored result for the stage (via StageResult.==)
    // so this no-op check survives a future recordResult implementation that
    // always allocates a fresh CampaignProgress.
    if (newProgress.resultFor(stageId) == priorResult) {
      return Future<void>.value();
    }
    return _persistSave(
      nextProgress: newProgress,
      buildSave: (committed) => CampaignSave(
        progress: committed.progress.recordResult(stageId, completion.result),
        techTree: committed.techTree,
      ),
      rollback: () {
        // Conditional rollback: only undo this save's result if it is still
        // the current optimistic value for the stage. A later concurrent
        // completion for the same stage (e.g. clear then gold) supersedes
        // this one and owns its own rollback; unconditionally restoring the
        // prior value onto the aggregate would erase the later result from
        // the optimistic UI state (round-4 review P1 same-stage case).
        //
        // When the latest optimistic result fails, restore the committed
        // disk state rather than the captured priorResult. priorResult was
        // read from the optimistic _progress at queue time, so when two
        // saves target the same stage and both fail, the second save's
        // priorResult carries the first save's optimistic (never-committed)
        // value — restoring it leaves a stale result in the UI that can
        // unlock dependent stages and contribute medal points until reload.
        // Since transactions execute serially, _committedProgress already
        // represents the resolved outcome of every earlier transaction
        // (round-5 review P2).
        if (_progress.resultFor(stageId) == completion.result) {
          _progress = _progress.withResult(
            stageId,
            _committedProgress.resultFor(stageId),
          );
        }
      },
    );
  }

  void _returnToMap() {
    setState(() {
      _game = null;
      _activeView = _ShellView.worldMap;
    });
  }

  Future<void> _confirmResetCampaign() async {
    // Single-flight: a second reset while one is already in flight is ignored.
    if (_isResetting) {
      return;
    }

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

    _isResetting = true;
    if (mounted) {
      setState(() {});
    }

    final store = _store;
    if (store == null) {
      _isResetting = false;
      if (!mounted) {
        return;
      }

      setState(() {
        _mapFeedback = 'Could not reset campaign progress.';
      });
      return;
    }

    // Serialize the reset with the save queue: wait for all pending saves to
    // drain, then perform exactly one reset as the next queued operation.
    // No save can interleave because stage launches and tech purchases are
    // disabled while _isResetting is true. Generation bumps monotonically
    // inside the queue (never rolled back) so any save that somehow queues
    // during the drain sees the mismatch and skips its write — and a failed
    // reset leaves the bumped generation in place harmlessly, since all
    // pre-reset saves already completed during the drain (round-3 review P1).
    final resetTask = _saveQueue.then((_) async {
      _progressGeneration++;
      await store.reset();
    });
    _saveQueue = resetTask.catchError((_) {});

    try {
      await resetTask;
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = CampaignProgress();
        _techTree = CampaignTechTree();
        _committedProgress = CampaignProgress();
        _committedTechTree = CampaignTechTree();
        _game = null;
        _activeView = _ShellView.worldMap;
        _mapFeedback = 'Campaign reset.';
        _pendingSaves = 0;
        _isSavingProgress = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      // Generation stays bumped (monotonic). All pre-reset saves completed
      // during the drain, so no save is skipped. New saves capture the new
      // generation and persist normally.
      setState(() {
        _mapFeedback = 'Could not reset campaign progress.';
      });
    } finally {
      _isResetting = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _setSavingProgress(bool value) {
    if (_isSavingProgress == value) {
      return;
    }
    _isSavingProgress = value;
    if (mounted) {
      setState(() {});
    }
  }

  void _decrementPendingSaves() {
    _pendingSaves--;
    if (_pendingSaves <= 0) {
      _pendingSaves = 0;
      _setSavingProgress(false);
    }
  }

  void _showCampaignPersistenceFailure() {
    const message = _persistenceFailureMessage;
    final game = _game;
    setState(() {
      _mapFeedback = message; // always; preserves HPA-94 breadcrumb behavior
      if (_activeView == _ShellView.techTree) {
        _techTreeFeedback = message;
      }
    });
    if (_activeView == _ShellView.stage && game != null) {
      game.overrideFeedback(message);
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

class _StageBriefingSheet extends StatelessWidget {
  const _StageBriefingSheet({required this.stage, required this.result});

  final StageDefinition stage;
  final StageResult? result;

  @override
  Widget build(BuildContext context) {
    final metadata = stage.modifiers.isEmpty
        ? [StageModifierMetadata.standardConditions]
        : stage.modifiers
              .map(StageModifierMetadata.forModifier)
              .toList(growable: false);
    final actionLabel = result == null ? 'Start Mission' : 'Replay Mission';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stage.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(stage.description),
          const SizedBox(height: 16),
          for (final entry in metadata) ...[
            Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(entry.description),
            const SizedBox(height: 12),
          ],
          if (stage.reward != null) Text(_briefingRewardLabel(stage.reward!)),
          if (result != null)
            Text(
              'Best: ${result!.medal.label} • '
              '${result!.bestBaseHealth} base health',
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}

String _briefingRewardLabel(CampaignReward reward) {
  return switch (reward) {
    CampaignReward.bonusGold =>
      'Completion reward: +${GameBalance.salvageRiftGoldBonus} Gold',
    CampaignReward.bonusHealth =>
      'Completion reward: +${GameBalance.voidBastionHealthBonus} HP',
    CampaignReward.challengeBadge => 'Completion reward: Challenge Badge',
  };
}

class _NextWavePanel extends StatelessWidget {
  const _NextWavePanel({required this.preview, required this.modifierTitles});

  final WavePreview preview;
  final List<String> modifierTitles;

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
            const SizedBox(height: 8),
            Text(
              'Environment: ${modifierTitles.join(', ')}',
              style: theme.textTheme.bodyMedium,
            ),
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

        final Widget summaryAndActions;
        if (constraints.maxWidth < 440) {
          summaryAndActions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TowerSummary(tower: tower, towerName: towerName),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        } else {
          summaryAndActions = Row(
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
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            summaryAndActions,
            const SizedBox(height: 10),
            _TargetingModePicker(game: game, snapshot: snapshot, tower: tower),
          ],
        );
      },
    );
  }
}

class _TargetingModePicker extends StatelessWidget {
  const _TargetingModePicker({
    required this.game,
    required this.snapshot,
    required this.tower,
  });

  final OrionDefenseGame game;
  final GameSnapshot snapshot;
  final PlacedTower tower;

  @override
  Widget build(BuildContext context) {
    final enabled = snapshot.phase == GamePhase.build;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Targeting', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in TowerTargetingMode.values)
              ChoiceChip(
                label: Text(mode.label),
                selected: tower.targetingMode == mode,
                onSelected: enabled ? (_) => game.setTargetingMode(mode) : null,
              ),
          ],
        ),
      ],
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
    final Widget primary;
    if (tower.canUpgrade) {
      primary = FilledButton.icon(
        onPressed: canUpgrade ? game.upgradeSelectedTower : null,
        icon: const Icon(Icons.upgrade),
        label: Text('Upgrade ${stats.upgradeCost}'),
      );
    } else if (tower.canSpecialize) {
      primary = Wrap(
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
    } else {
      primary = FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check),
        label: const Text('Max'),
      );
    }

    return Wrap(
      alignment: alignment,
      spacing: 8,
      runSpacing: 8,
      children: [
        primary,
        FilledButton.tonalIcon(
          onPressed: snapshot.phase == GamePhase.build
              ? game.sellSelectedTower
              : null,
          icon: const Icon(Icons.sell),
          label: Text('Sell +${GameBalance.refundValue(tower)}'),
        ),
      ],
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
    final result = didWin
        ? StageResult.fromVictoryBaseHealth(
            snapshot.baseHealth,
            startingBaseHealth: snapshot.startingBaseHealth,
          )
        : null;

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
                if (didWin && result != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${result.medal.label} medal - '
                    'Base ${result.bestBaseHealth}/${snapshot.startingBaseHealth}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
