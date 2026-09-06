import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assets/game_boss_sheet.dart';
import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../campaign/campaign_progress.dart';
import '../campaign/campaign_progress_store.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/tech_tree.dart';
import '../feedback/feedback_preferences.dart';
import '../feedback/game_feedback.dart';
import '../models/game_models.dart';
import '../orion_defense_game.dart';
import '../rules/run_module_unlocks.dart';
import '../rules/stage_modifier_rules.dart';
import 'codex_view.dart';
import 'command_frame.dart';
import 'feedback_settings_sheet.dart';
import 'mission_chrome.dart';
import 'mission_command_dock.dart';
import 'mission_report_content.dart';
import 'mission_report_panel.dart';
import 'orion_ui_theme.dart';
import 'run_module_draft_panel.dart';
import 'stage_briefing_sheet.dart';
import 'tech_tree_view.dart';
import 'world_map_view.dart';

enum _ShellView { worldMap, codex, techTree, stage }

/// Persistence-failure breadcrumb surfaced on both the active view and the
/// world map. Hoisted to a top-level constant so retry paths can match and
/// clear the stale map breadcrumb without re-string-literalizing it.
const String _persistenceFailureMessage = 'Could not save campaign progress.';

/// Feedback-failure breadcrumb surfaced on the world map. Hoisted to a
/// top-level constant so a later successful save can match and clear the
/// stale breadcrumb without re-string-literalizing it.
const String _feedbackSaveFailureMessage = 'Could not save feedback settings.';

class OrionGamePage extends StatefulWidget {
  const OrionGamePage({
    super.key,
    this.progressStore,
    this.progressStoreLoader,
    this.feedbackPreferencesStore,
    this.gameFeedback,
    this.onGameCreated,
  });

  final CampaignProgressStore? progressStore;
  final Future<CampaignProgressStore> Function()? progressStoreLoader;
  final FeedbackPreferencesStore? feedbackPreferencesStore;
  final GameFeedback? gameFeedback;
  final ValueChanged<OrionDefenseGame>? onGameCreated;

  @override
  State<OrionGamePage> createState() => _OrionGamePageState();
}

class _OrionGamePageState extends State<OrionGamePage> {
  OrionDefenseGame? _game;
  final GlobalKey _gameWidgetKey = GlobalKey();
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
  FeedbackPreferences _feedbackPreferences = const FeedbackPreferences();
  FeedbackPreferencesStore? _feedbackPreferencesStore;
  bool _feedbackPreferencesLoaded = false;
  bool _isSavingFeedback = false;
  late final GameFeedback _gameFeedback;
  _ShellView _activeView = _ShellView.worldMap;
  bool _isLoading = true;
  int _progressGeneration = 0;
  Future<void> _saveQueue = Future<void>.value();
  int _pendingSaves = 0;
  bool _isSavingProgress = false;
  bool _isResetting = false;
  StageResult? _missionPriorResult;
  StageResult? _missionVictoryResult;
  String? _missionStageId;
  MissionSaveState? _missionSaveState;
  bool _didPrecacheCommandDeckAssets = false;

  @override
  void initState() {
    super.initState();
    _gameFeedback =
        widget.gameFeedback ??
        PlatformGameFeedback(
          // Suppress both channels until the persisted preference store has
          // resolved. _feedbackPreferences defaults to both-enabled, so
          // without this gate a delayed store load (e.g. a slow first
          // SharedPreferences read) would let cues fire against the default
          // true values during the window between _isLoading clearing and
          // _feedbackPreferencesLoaded flipping — violating a user's saved
          // soundEffectsEnabled:false / hapticsEnabled:false choice. Gameplay
          // itself is not blocked: only feedback is held until preferences
          // resolve (or fail and defaults are intentionally adopted).
          soundEffectsEnabled: () =>
              _feedbackPreferencesLoaded &&
              _feedbackPreferences.soundEffectsEnabled,
          hapticsEnabled: () =>
              _feedbackPreferencesLoaded && _feedbackPreferences.hapticsEnabled,
        );
    _loadProgress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheCommandDeckAssets) return;
    _didPrecacheCommandDeckAssets = true;
    for (final fileName in const [
      GameSpriteSheet.fileName,
      GameTowerVarietySheet.fileName,
      GameBossSheet.fileName,
    ]) {
      Flame.images.load(fileName).ignore();
    }
  }

  Future<void> _loadProgress() async {
    CampaignProgressStore? store = widget.progressStore;
    FeedbackPreferencesStore? feedbackStore = widget.feedbackPreferencesStore;

    try {
      if (store == null && widget.progressStoreLoader == null) {
        // Campaign falls back to the default SharedPreferences-backed store.
        // When the feedback store is also defaulted, one SharedPreferences
        // instance backs both.
        final preferences = await SharedPreferences.getInstance();
        store = SharedPreferencesCampaignProgressStore(
          preferences: preferences,
          knownStages: OrionCampaign.stages,
        );
        feedbackStore ??= SharedPreferencesFeedbackPreferencesStore(
          preferences: preferences,
        );
      }

      if (store == null) {
        final loader = widget.progressStoreLoader;
        store = await loader!();
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

    // Feedback preferences load independently of campaign progress: a
    // feedback failure (including default-store construction) falls back to
    // defaults and never erases (or is erased by) campaign loading.
    if (feedbackStore == null) {
      try {
        final preferences = await SharedPreferences.getInstance();
        feedbackStore = SharedPreferencesFeedbackPreferencesStore(
          preferences: preferences,
        );
      } catch (_) {
        feedbackStore = null;
      }
    }

    if (feedbackStore == null) {
      // No store could be constructed (both SharedPreferences attempts
      // failed). Honor the documented "falls back to defaults" contract:
      // adopt the default preferences and mark the preference state loaded
      // so the sound/haptic predicates can resolve. The store stays null,
      // so a later Settings change surfaces the save-failure breadcrumb
      // via _saveFeedbackPreferences' null-store branch.
      if (!mounted) {
        return;
      }
      setState(() {
        if (!_feedbackPreferencesLoaded) {
          _feedbackPreferences = const FeedbackPreferences();
        }
        _feedbackPreferencesLoaded = true;
      });
      return;
    }

    try {
      final loaded = await feedbackStore.load();
      if (!mounted) {
        return;
      }
      setState(() {
        // A save that committed during the load window owns the
        // in-memory value; discard this stale result. The store and
        // loaded flag always advance so a later save can persist.
        if (!_feedbackPreferencesLoaded) {
          _feedbackPreferences = loaded;
        }
        _feedbackPreferencesStore = feedbackStore;
        _feedbackPreferencesLoaded = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (!_feedbackPreferencesLoaded) {
          _feedbackPreferences = const FeedbackPreferences();
        }
        _feedbackPreferencesStore = feedbackStore;
        _feedbackPreferencesLoaded = true;
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
      case _ShellView.codex:
        return CodexView(progress: _progress, onBack: _closeCodex);
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
        isSavingFeedback: _isSavingFeedback,
        onStageSelected: _showStageBriefing,
        onLockedStageSelected: _showLockedStageFeedback,
        onResetCampaign: _confirmResetCampaign,
        onOpenTechTree: _openTechTree,
        onOpenCodex: _openCodex,
        onOpenSettings: _feedbackPreferencesLoaded
            ? _openFeedbackSettings
            : null,
      ),
    );
  }

  /// Tap arbiter shared by floating chrome (collapsed next-wave scanner,
  /// pacing-strip frame): when the tapped point lands anywhere on the board,
  /// forward the tap to the game so normal board handling applies instead of
  /// being swallowed by the overlay. Path cells are included — enemies travel
  /// on them during waves and must stay inspectable. Taps that miss the board
  /// are left to the overlay's own handling.
  bool _routeTapToBoard(Offset globalPosition) {
    final game = _game;
    final box = _gameWidgetKey.currentContext?.findRenderObject() as RenderBox?;
    if (game == null || box == null || !box.attached) {
      return false;
    }
    final local = box.globalToLocal(globalPosition);
    return game.tryHandleBoardTap(local);
  }

  RenderBox? get _gameRenderBox =>
      _gameWidgetKey.currentContext?.findRenderObject() as RenderBox?;

  /// Maps scene-1e drag-preview events onto the game. Update/Commit convert
  /// the global pointer into GameWidget-local coordinates with the same
  /// [_gameWidgetKey] conversion the board-tap arbiter uses. A commit whose
  /// conversion is impossible cancels — never a blind placement.
  void _handlePlacementPreviewEvent(TowerPlacementPreviewEvent event) {
    final game = _game;
    if (game == null) {
      return;
    }
    switch (event) {
      case TowerPlacementPreviewBegin(:final type):
        game.beginTowerPlacementPreview(type);
      case TowerPlacementPreviewUpdate(:final globalPosition):
        final box = _gameRenderBox;
        if (box != null && box.attached) {
          game.updateTowerPlacementPreview(box.globalToLocal(globalPosition));
        }
      case TowerPlacementPreviewCommit(:final globalPosition):
        final box = _gameRenderBox;
        if (box == null || !box.attached) {
          game.cancelTowerPlacementPreview();
        } else {
          game.commitTowerPlacementPreview(box.globalToLocal(globalPosition));
        }
      case TowerPlacementPreviewCancel():
        game.cancelTowerPlacementPreview();
    }
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
                // The GameWidget fills the entire SafeArea so the Flame
                // viewport (and therefore _cellSize) is identical to the
                // pre-command-deck layout. Enemy speed, tower range, and
                // projectile speed are all absolute game units — shrinking
                // the viewport would silently alter combat balance. The
                // mission chrome overlays the GameWidget as it did before the
                // in-flow reserve attempt.
                Positioned.fill(
                  child: KeyedSubtree(
                    key: _gameWidgetKey,
                    child: GameWidget(game: game),
                  ),
                ),
                Positioned.fill(
                  child: MissionChrome(
                    snapshot: snapshot,
                    onBoardTapIntercept: _routeTapToBoard,
                    onWorldMap: game.returnToMap,
                    onStartWave: game.startWave,
                    onTogglePause: game.togglePause,
                    onSpeedSelected: game.setSpeedMultiplier,
                    onToggleAutoStart: game.toggleAutoStart,
                    onPlaceTower: game.placeTower,
                    onUpgrade: game.upgradeSelectedTower,
                    onSpecialize: game.specializeSelectedTower,
                    onTargetingChanged: game.setTargetingMode,
                    onSell: game.sellSelectedTower,
                    onPlacementPreviewEvent: _handlePlacementPreviewEvent,
                  ),
                ),
                if (snapshot.pendingRunModuleOffer case final offer?)
                  Positioned.fill(
                    child: RunModuleDraftPanel(
                      offer: offer,
                      onSelected: (moduleId) =>
                          game.selectRunModule(offer.offerId, moduleId),
                    ),
                  ),
                if (snapshot.phase == GamePhase.lost)
                  Positioned.fill(
                    child: MissionReportPanel(
                      content: projectLossReport(snapshot: snapshot),
                      onReplay: _restartFromMissionReport,
                      onReturnToMap: _returnFromMissionReport,
                    ),
                  ),
                if (snapshot.phase == GamePhase.won &&
                    _missionVictoryResult != null &&
                    _missionSaveState != null)
                  Positioned.fill(
                    child: MissionReportPanel(
                      content: projectVictoryReport(
                        snapshot: snapshot,
                        result: _missionVictoryResult!,
                        priorSavedResult: _missionPriorResult,
                        saveState: _missionSaveState!,
                        reward: _missionRewardFact(),
                      ),
                      onReplay: _missionSaveState == MissionSaveState.saved
                          ? _restartFromMissionReport
                          : null,
                      onReturnToMap:
                          _missionSaveState == MissionSaveState.saving
                          ? null
                          : _returnFromMissionReport,
                      onRetrySave: _missionSaveState == MissionSaveState.failed
                          ? _saveMissionResult
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showStageBriefing(StageDefinition stage) async {
    // Run inputs derive from the last-known committed disk state, mirroring
    // what a stage launch would actually use; the sheet renders primitives.
    final modifiers = _committedCampaignModifiers();
    final shouldStart = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: orionSheetAnimationStyle(context),
      builder: (context) => StageBriefingSheet(
        stage: stage,
        // Aligned with the rest of the committed-state pattern: the briefing
        // sheet's Start/Replay label, reward-earned flag, best-result line,
        // and HPA-528 blueprint-recovered signal are all first-clear facts
        // sourced from disk, not the optimistic `_progress` aggregate.
        result: _committedProgress.resultFor(stage.id),
        startingGold: modifiers.adjustedStartingGold,
        startingBaseHealth: StageModifierRules.effectiveStartingBaseHealth(
          campaignAdjustedBaseHealth: modifiers.adjustedStartingBaseHealth,
          stageModifiers: stage.modifiers,
        ),
      ),
    );

    if (shouldStart == true && mounted) {
      _startStage(stage);
    }
  }

  Future<void> _openFeedbackSettings() async {
    if (_isSavingFeedback || !_feedbackPreferencesLoaded) {
      return;
    }
    final updated = await showModalBottomSheet<FeedbackPreferences>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: orionSheetAnimationStyle(context),
      builder: (context) => FeedbackSettingsSheet(
        initialPreferences: _feedbackPreferences,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
    );

    if (updated == null || updated == _feedbackPreferences) {
      return;
    }
    await _saveFeedbackPreferences(updated);
  }

  Future<void> _saveFeedbackPreferences(FeedbackPreferences updated) async {
    _isSavingFeedback = true;
    if (mounted) {
      setState(() {});
    }

    final store = _feedbackPreferencesStore;
    if (store == null) {
      // No store: keep the prior effective value and surface a breadcrumb
      // like the campaign persistence failure path.
      _isSavingFeedback = false;
      if (!mounted) {
        return;
      }
      setState(() {
        _mapFeedback = _feedbackSaveFailureMessage;
      });
      return;
    }
    try {
      await store.save(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _feedbackPreferences = updated;
        _feedbackPreferencesLoaded = true;
        if (_mapFeedback == _feedbackSaveFailureMessage) {
          _mapFeedback = null;
        }
      });
    } catch (_) {
      // Keep the prior effective value; surface a breadcrumb like the
      // campaign persistence failure path.
      if (!mounted) {
        return;
      }
      setState(() {
        _mapFeedback = _feedbackSaveFailureMessage;
      });
    } finally {
      _isSavingFeedback = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Run inputs (campaign modifiers and module eligibility) are derived from
  // the last-known committed disk state, not the optimistic `_progress`
  // aggregate. One attempt freezes committed run inputs; a same-object
  // Replay refreshes ALL committed run inputs together (HPA-528).
  CampaignModifiers _committedCampaignModifiers() =>
      CampaignModifiers.fromProgress(
        _committedProgress,
        OrionCampaign.stages,
        _committedTechTree,
      );

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

    final campaignModifiers = _committedCampaignModifiers();
    _missionPriorResult = _committedProgress.resultFor(stage.id);
    _missionVictoryResult = null;
    _missionStageId = stage.id;
    _missionSaveState = null;
    final game = OrionDefenseGame(
      stage: stage,
      campaignModifiers: campaignModifiers,
      availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
      onStageWon: _handleStageWon,
      onReturnToMap: _returnFromMissionReport,
      gameFeedback: _gameFeedback,
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

  void _openCodex() {
    setState(() {
      _activeView = _ShellView.codex;
    });
  }

  void _closeCodex() {
    setState(() {
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
    VoidCallback? rollback,
    ValueChanged<CampaignSave>? onCommitted,
    VoidCallback? onFailed,
  }) async {
    final store = _store;
    if (store == null) {
      if (onFailed != null) {
        onFailed();
      } else {
        _showCampaignPersistenceFailure();
      }
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
          onFailed?.call();
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
          onCommitted?.call(payload);
        } else if (onFailed != null) {
          onFailed();
        }
      } catch (_) {
        if (saveGeneration == _progressGeneration) {
          rollback?.call();
          if (onFailed != null) {
            onFailed();
          } else if (mounted) {
            _showCampaignPersistenceFailure();
          }
        } else if (onFailed != null) {
          onFailed();
        }
      } finally {
        _decrementPendingSaves();
      }
    });
    _saveQueue = saveTask.catchError((_) {});
  }

  void _handleStageWon(StageCompletion completion) {
    if (_isResetting ||
        _missionVictoryResult != null ||
        _missionSaveState != null) {
      return;
    }

    _missionStageId = completion.stage.id;
    _missionVictoryResult = completion.result;

    if (!completion.result.isBetterThan(_missionPriorResult)) {
      _setMissionSaveState(MissionSaveState.saved);
      return;
    }

    _saveMissionResult();
  }

  Future<void> _saveMissionResult() async {
    if (_missionSaveState == MissionSaveState.saving ||
        _missionSaveState == MissionSaveState.saved) {
      return;
    }

    final stageId = _missionStageId;
    final result = _missionVictoryResult;
    if (stageId == null || result == null) {
      _setMissionSaveState(MissionSaveState.failed);
      return;
    }

    _setMissionSaveState(MissionSaveState.saving);

    await _persistSave(
      buildSave: (committed) => CampaignSave(
        progress: committed.progress.recordResult(stageId, result),
        techTree: committed.techTree,
      ),
      onCommitted: (payload) {
        _progress = payload.progress;
        _setMissionSaveState(MissionSaveState.saved);
      },
      onFailed: () => _setMissionSaveState(MissionSaveState.failed),
    );
  }

  void _setMissionSaveState(MissionSaveState state) {
    _missionSaveState = state;
    if (mounted) {
      setState(() {});
    }
  }

  // The blueprint recovery reward is a first-clear fact for stage one only.
  // Because _missionPriorResult was captured from committed progress at
  // attempt start, a successful save can advance _committedProgress without
  // changing the first-clear fact for the completed attempt. Replay
  // recaptures _missionPriorResult from committed progress (now non-null)
  // and suppresses duplicate celebration (HPA-528).
  MissionRewardFact? _missionRewardFact() {
    if (_missionStageId != OrionCampaign.stageOneId ||
        _missionPriorResult != null) {
      return null;
    }

    return switch (_missionSaveState) {
      MissionSaveState.saving => const MissionRewardFact(
        title: 'Blueprint recovery pending',
        detail: 'Relay Calibration unlocks after this result is saved.',
      ),
      MissionSaveState.saved => const MissionRewardFact(
        title: 'Blueprint recovered: Relay Calibration',
        detail: 'Available in Salvage Module drafts on future runs.',
      ),
      MissionSaveState.failed => const MissionRewardFact(
        title: 'Blueprint not recovered',
        detail: 'Retry Save to keep this first-clear reward.',
      ),
      null => null,
    };
  }

  void _returnToMap() {
    if (_missionSaveState == MissionSaveState.saving) {
      return;
    }
    setState(() {
      _game = null;
      _activeView = _ShellView.worldMap;
    });
  }

  void _returnFromMissionReport() {
    if (_missionSaveState == MissionSaveState.saving) {
      return;
    }
    if (_missionSaveState == MissionSaveState.failed) {
      _mapFeedback = 'Mission result was not saved.';
    }
    _returnToMap();
  }

  void _restartFromMissionReport() {
    final game = _game;
    if (game == null) return;

    if (_missionVictoryResult != null &&
        _missionSaveState != MissionSaveState.saved) {
      return;
    }

    _missionPriorResult = _committedProgress.resultFor(_missionStageId!);
    _missionVictoryResult = null;
    _missionSaveState = null;
    // _missionStageId represents the currently running stage, not per-attempt
    // terminal state, so it stays valid across restart() of the same stage.
    // Clearing it broke loss → Retry → loss → Retry: a loss never calls
    // _handleStageWon (the only other re-setter besides _startStage), so the
    // second retry hit the `_missionStageId!` null check above.
    game.restart(
      campaignModifiers: _committedCampaignModifiers(),
      availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
    );
  }

  Future<void> _confirmResetCampaign() async {
    // Single-flight: a second reset while one is already in flight is ignored.
    if (_isResetting) {
      return;
    }

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        final uiTheme = OrionUiTheme.of(context);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: CommandFrame(
              key: const ValueKey('reset-campaign-dialog'),
              borderColor: uiTheme.dangerRed,
              color: uiTheme.hullBlack,
              emphasized: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: uiTheme.dangerRed,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reset Campaign',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: uiTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Clear all campaign progress?',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: uiTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: uiTheme.dangerRed,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
