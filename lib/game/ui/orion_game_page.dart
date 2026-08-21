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
import '../campaign/stage_modifier_metadata.dart';
import '../campaign/tech_tree.dart';
import '../feedback/feedback_preferences.dart';
import '../feedback/game_feedback.dart';
import '../models/game_models.dart';
import '../orion_defense_game.dart';
import '../rules/run_module_unlocks.dart';
import '../util/format.dart';
import 'codex_view.dart';
import 'campaign_presentation.dart';
import 'command_frame.dart';
import 'feedback_settings_sheet.dart';
import 'mission_command_hud.dart';
import 'mission_report_content.dart';
import 'mission_report_panel.dart';
import 'orion_atlas_sprite.dart';
import 'orion_ui_theme.dart';
import 'run_module_draft_panel.dart';
import 'tech_tree_view.dart';
import 'tower_icons.dart';
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(
                        child: MissionStatusHud(snapshot: snapshot),
                      ),
                      const SizedBox(height: 6),
                      MissionPacingStrip(
                        snapshot: snapshot,
                        onTogglePause: game.togglePause,
                        onSpeedSelected: game.setSpeedMultiplier,
                        onToggleAutoStart: game.toggleAutoStart,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (snapshot.acquiredRunModules.isNotEmpty)
                            Flexible(
                              child: IgnorePointer(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 132,
                                  ),
                                  child: AcquiredRunModuleStrip(
                                    moduleIds: snapshot.acquiredRunModules,
                                  ),
                                ),
                              ),
                            ),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _BottomControls(game: game, snapshot: snapshot),
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
    final shouldStart = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: orionSheetAnimationStyle(context),
      builder: (context) => _StageBriefingSheet(
        stage: stage,
        // Aligned with the rest of the committed-state pattern: the briefing
        // sheet's Start/Replay label, reward-earned flag, best-result line,
        // and HPA-528 blueprint-recovered signal are all first-clear facts
        // sourced from disk, not the optimistic `_progress` aggregate.
        result: _committedProgress.resultFor(stage.id),
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

class _StageBriefingSheet extends StatelessWidget {
  const _StageBriefingSheet({required this.stage, required this.result});

  final StageDefinition stage;
  final StageResult? result;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final metadata = stage.modifiers.isEmpty
        ? [StageModifierMetadata.standardConditions]
        : stage.modifiers
              .map(StageModifierMetadata.forModifier)
              .toList(growable: false);
    final actionLabel = result == null ? 'Launch Mission' : 'Replay Mission';
    final isOptional = !stage.isMainPath;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: CommandFrame(
        key: const ValueKey('stage-briefing'),
        padding: const EdgeInsets.all(14),
        color: uiTheme.hullBlack,
        borderColor: isOptional ? uiTheme.systemViolet : uiTheme.systemCyan,
        emphasized: true,
        chamfer: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox.square(
                dimension: 112,
                child: CommandFrame(
                  padding: const EdgeInsets.all(4),
                  color: uiTheme.panelBlue,
                  borderColor: isOptional
                      ? uiTheme.systemViolet
                      : uiTheme.systemCyan,
                  emphasized: true,
                  chamfer: isOptional ? 28 : 16,
                  child: OrionAtlasSprite(
                    art: OrionArt.stage(stage),
                    size: const Size.square(104),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    stage.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: uiTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _BriefingBadge(
                  label: isOptional ? 'OPTIONAL' : 'PRIMARY',
                  color: isOptional ? uiTheme.systemViolet : uiTheme.systemCyan,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              stage.description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: uiTheme.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              'MISSION INTEL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: uiTheme.systemCyan,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 7),
            for (final entry in metadata) ...[
              _BriefingIntelRow(
                icon: Icons.radar_rounded,
                color: uiTheme.systemCyan,
                title: entry.title,
                detail: entry.description,
              ),
              const SizedBox(height: 7),
            ],
            if (stage.reward != null) ...[
              _BriefingIntelRow(
                icon: rewardIcon(stage.reward!),
                color: uiTheme.creditGold,
                title: 'SALVAGE',
                detail: _briefingRewardLabel(
                  stage.reward!,
                  earned: result != null,
                ),
              ),
              const SizedBox(height: 7),
            ],
            if (result != null) ...[
              _BriefingIntelRow(
                icon: medalIcon(result!.medal),
                color: medalColor(uiTheme, result!.medal),
                title: 'BEST RESULT',
                detail:
                    'Best: ${result!.medal.label} • '
                    '${result!.bestBaseHealth} base health',
              ),
              const SizedBox(height: 7),
            ],
            // HPA-528: a committed Outpost Alpha clear also recovers the
            // Relay Calibration blueprint; the existing committed `result`
            // remains the signal rather than transient sheet state.
            if (stage.id == OrionCampaign.stageOneId && result != null) ...[
              _BriefingIntelRow(
                icon: Icons.memory_rounded,
                color: uiTheme.systemViolet,
                title: 'BLUEPRINT',
                detail: 'Blueprint recovered: Relay Calibration',
              ),
              const SizedBox(height: 7),
            ],
            const SizedBox(height: 7),
            Tooltip(
              message: actionLabel,
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                label: actionLabel,
                child: CommandFrame(
                  padding: EdgeInsets.zero,
                  color: uiTheme.panelBlue,
                  borderColor: uiTheme.systemCyan,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(true),
                      splashColor: uiTheme.systemCyan.withValues(alpha: 0.18),
                      highlightColor: uiTheme.systemCyan.withValues(
                        alpha: 0.10,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            _BriefingReactorBadge(
                              label: result == null ? 'Launch' : 'Replay',
                              icon: result == null
                                  ? Icons.rocket_launch_rounded
                                  : Icons.replay_rounded,
                              size: 72,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    actionLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: uiTheme.textPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    result == null
                                        ? 'Deploy to this sector'
                                        : 'Run this sector again',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: uiTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefingBadge extends StatelessWidget {
  const _BriefingBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _BriefingIntelRow extends StatelessWidget {
  const _BriefingIntelRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      color: uiTheme.panelBlue,
      borderColor: color.withValues(alpha: 0.62),
      chamfer: 7,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: uiTheme.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefingReactorBadge extends StatelessWidget {
  const _BriefingReactorBadge({
    required this.label,
    required this.icon,
    this.size = 68,
  });

  final String label;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final resolvedSize = size < 48 ? 48.0 : size;
    final foreground = uiTheme.textPrimary;
    final accent = uiTheme.systemCyan;

    return SizedBox.square(
      dimension: resolvedSize,
      child: CommandFrame(
        padding: const EdgeInsets.all(3),
        borderColor: accent,
        color: uiTheme.hullBlack,
        emphasized: true,
        chamfer: 12,
        child: CommandFrame(
          padding: EdgeInsets.zero,
          borderColor: accent.withValues(alpha: 0.68),
          color: uiTheme.panelBlue,
          chamfer: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 22),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.15),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _briefingRewardLabel(CampaignReward reward, {required bool earned}) {
  // Persistent campaign rewards are granted once per stage when it is first
  // cleared (CampaignModifiers.fromProgress keys off isCleared); replays do
  // not stack the reward. The label reflects whether it has already been
  // granted so the Replay Mission sheet doesn't imply a fresh payout.
  final prefix = earned ? 'Reward earned:' : 'Completion reward:';
  return switch (reward) {
    CampaignReward.bonusGold =>
      '$prefix +${GameBalance.salvageRiftGoldBonus} Gold',
    CampaignReward.bonusHealth =>
      '$prefix +${GameBalance.voidBastionHealthBonus} HP',
    CampaignReward.challengeBadge => '$prefix Challenge Badge',
  };
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.game, required this.snapshot});

  final OrionDefenseGame game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _content(context);
    final resolvedContent = snapshot.feedback == null
        ? content
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                snapshot.feedback!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              content,
            ],
          );

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
          child: resolvedContent,
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
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'World Map',
              onPressed: snapshot.phase == GamePhase.build
                  ? game.returnToMap
                  : null,
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
                label: type.label,
                icon: towerIcon(type),
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
    final towerName = tower.type.label;
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
              _TowerSummary(
                tower: tower,
                towerName: towerName,
                stats: snapshot.selectedTowerStats,
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        } else {
          summaryAndActions = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TowerSummary(
                  tower: tower,
                  towerName: towerName,
                  stats: snapshot.selectedTowerStats,
                ),
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
  const _TowerSummary({
    required this.tower,
    required this.towerName,
    required this.stats,
  });

  final PlacedTower tower;
  final String towerName;
  final TowerStats? stats;

  @override
  Widget build(BuildContext context) {
    final secondary = switch (tower.type) {
      TowerType.cryo when stats != null && stats!.slowDuration > 0 =>
        'Slow ${number(stats!.slowDuration)}s',
      TowerType.rocket when stats != null && stats!.splashRadius > 0 =>
        'Splash ${number(stats!.splashRadius)}',
      TowerType.nanite
          when stats != null && stats!.corrosionDamagePerSecond > 0 =>
        'Corrosion ${number(stats!.corrosionDamagePerSecond)}/s',
      TowerType.droneBay when stats != null && stats!.droneDamage > 0 =>
        'Drone dmg ${number(stats!.droneDamage)}',
      _ => null,
    };

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
        if (stats != null) ...[
          const SizedBox(height: 4),
          Text(
            'Damage ${number(stats!.damage)} • '
            'Fire ${cadence(stats!.fireInterval)}s • '
            'Range ${number(stats!.range)}',
          ),
          if (secondary != null) ...[
            const SizedBox(height: 2),
            Text(secondary),
          ],
        ],
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
