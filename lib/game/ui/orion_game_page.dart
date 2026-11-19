import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assets/game_boss_sheet.dart';
import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../campaign/campaign_progress.dart';
import '../campaign/campaign_progress_store.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../feedback/feedback_preferences.dart';
import '../feedback/game_feedback.dart';
import '../feedback/game_music.dart';
import '../models/game_models.dart';
import '../onboarding/contextual_tips.dart';
import '../onboarding/first_mission_guide.dart';
import '../onboarding/first_mission_guide_store.dart';
import '../orion_defense_game.dart';
import '../rules/module_offer_picker.dart';
import '../rules/run_module_unlocks.dart';
import '../rules/stage_modifier_rules.dart';
import 'camp_view.dart';
import 'codex_view.dart';
import 'feedback_settings_sheet.dart';
import 'first_mission_guide_callout.dart';
import 'mission_chrome.dart';
import 'mission_command_dock.dart';
import 'mission_report_content.dart';
import 'mission_report_panel.dart';
import 'orion_menu_shell.dart';
import 'orion_surface.dart';
import 'orion_title_view.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'run_module_draft_panel.dart';
import 'stage_briefing_sheet.dart';
import 'tower_inspector.dart';
import 'world_map_view.dart';

enum _ShellView { title, worldMap, codex, camp, stage }

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
    this.firstMissionGuideStore,
    this.moduleOfferPicker,
    this.gameFeedback,
    this.gameMusicController,
    this.onGameCreated,
    @visibleForTesting this.startOnWorldMap = false,
  });

  final CampaignProgressStore? progressStore;
  final Future<CampaignProgressStore> Function()? progressStoreLoader;
  final FeedbackPreferencesStore? feedbackPreferencesStore;

  /// Optional persistence for the first-mission tutorial completion flag.
  /// Defaults to a SharedPreferences-backed store (reusing the campaign's
  /// instance on the default load path).
  final FirstMissionGuideStore? firstMissionGuideStore;

  /// Optional deterministic seam for run-module draft offers; null keeps the
  /// game's built-in (random) picking.
  final ModuleOfferPicker? moduleOfferPicker;

  final GameFeedback? gameFeedback;

  /// Optional music owner for tests or an embedding host. The page never
  /// disposes an injected controller.
  final GameMusicController? gameMusicController;

  final ValueChanged<OrionDefenseGame>? onGameCreated;

  @visibleForTesting
  final bool startOnWorldMap;

  @override
  State<OrionGamePage> createState() => _OrionGamePageState();
}

class _OrionGamePageState extends State<OrionGamePage> {
  OrionDefenseGame? _game;
  int? _inspectedTowerId;
  final GlobalKey _gameWidgetKey = GlobalKey();
  CampaignProgress _progress = CampaignProgress();
  Map<Character, int> _ownedLevels = CampaignSave.starterOwnedLevels;
  List<Character> _squad = CampaignSave.starterSquad;
  // Last-known committed disk state. Queued saves compose their payload from
  // this rather than the shared optimistic `_progress`/profile aggregate, so
  // a later transaction's mutation cannot be persisted under an earlier save
  // that subsequently fails (round-4 review P1). Advanced inside the save
  // queue on each successful write; reset to the fresh profile on a
  // successful reset.
  CampaignProgress _committedProgress = CampaignProgress();
  Map<Character, int> _committedOwnedLevels = CampaignSave.starterOwnedLevels;
  List<Character> _committedSquad = CampaignSave.starterSquad;
  CampaignProgressStore? _store;
  String? _mapFeedback;
  String? _shellFeedback;
  FeedbackPreferences _feedbackPreferences = const FeedbackPreferences();
  FeedbackPreferencesStore? _feedbackPreferencesStore;
  bool _feedbackPreferencesLoaded = false;
  FirstMissionGuideStore? _firstMissionGuideStore;
  bool _firstMissionGuideCompleted = false;
  // Typed seen set for the HPA-413 contextual tips, loaded alongside the
  // guide flag before the loading gate clears; acknowledged in memory first,
  // then written through best-effort.
  Set<ContextualTip> _seenTips = const {};
  // The last board viewport MissionChrome measured — the free space between
  // the top chrome and the dock, in this Stack's coordinates. Contextual-tip
  // bubbles clamp to it so they can never land inside the idle bar.
  Rect? _boardViewport;
  // Serializes seen-tip write-throughs: acknowledgements replace the whole
  // set, so an older write landing after a newer one would forget tips.
  Future<void> _seenTipsWrite = Future<void>.value();
  // Guide anchor keys wrap the existing gameplay surfaces (dock cards, wave
  // pill, radial Upgrade, collapsed scanner, draft frame) so the callout can
  // point at real widgets; they are only attached while their step is active.
  // The ONE card anchor key: HPA-412's Laser lesson and the HPA-413 unlock
  // tips are mutually exclusive (the old guide wins while eligible), so a
  // single GlobalKey serves exactly one active card at a time.
  final GlobalKey _towerCardGuideAnchorKey = GlobalKey();
  final GlobalKey _waveGuideAnchorKey = GlobalKey();
  final GlobalKey _upgradeGuideAnchorKey = GlobalKey();
  final GlobalKey _scannerGuideAnchorKey = GlobalKey();
  final GlobalKey _targetingGuideAnchorKey = GlobalKey();
  final GlobalKey _moduleDraftGuideAnchorKey = GlobalKey();
  bool _isSavingFeedback = false;
  late final GameFeedback _gameFeedback;
  late final GameMusicController _gameMusicController;
  GameMusicController? _ownedGameMusicController;
  late final AppLifecycleListener _appLifecycleListener;
  bool _appForeground = true;
  VoidCallback? _gameSnapshotListener;

  /// The feedback this page created, if any. Non-null only when no
  /// [OrionGamePage.gameFeedback] was injected; disposed in [dispose] —
  /// never an injected implementation.
  PlatformGameFeedback? _ownedGameFeedback;
  late _ShellView _activeView = widget.startOnWorldMap
      ? _ShellView.worldMap
      : _ShellView.title;
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
  int _endlessSaveSequence = 0;
  int? _endlessPriorBest;
  bool _didPrecacheCommandDeckAssets = false;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _ownedGameMusicController = widget.gameMusicController == null
        ? GameMusicController()
        : null;
    _gameMusicController =
        widget.gameMusicController ?? _ownedGameMusicController!;
    _appLifecycleListener = AppLifecycleListener(
      onStateChange: _handleAppLifecycleStateChanged,
    );
    _ownedGameFeedback = widget.gameFeedback == null
        ? PlatformGameFeedback(
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
                _feedbackPreferencesLoaded &&
                _feedbackPreferences.hapticsEnabled,
          )
        : null;
    _gameFeedback = widget.gameFeedback ?? _ownedGameFeedback!;
    _loadProgress();
  }

  // Only the page-owned feedback is disposed here; map/stage transitions
  // never tear down the app's home page, so this fires once at real
  // teardown (widget unmount / app root disposal).
  @override
  void dispose() {
    _appLifecycleListener.dispose();
    _appForeground = false;
    _listenToGame(null);
    _ownedGameMusicController?.dispose().ignore();
    _ownedGameFeedback?.dispose();
    super.dispose();
  }

  void _handleAppLifecycleStateChanged(AppLifecycleState state) {
    if (!mounted) return;
    _appForeground = state == AppLifecycleState.resumed;
    _syncMusic();
  }

  void _listenToGame(OrionDefenseGame? game) {
    final previous = _game;
    final previousListener = _gameSnapshotListener;
    if (previous != null && previousListener != null) {
      previous.stateNotifier.removeListener(previousListener);
    }
    _gameSnapshotListener = null;
    _game = game;
    if (game != null) {
      void listener() {
        if (!mounted || !identical(_game, game)) return;
        _syncMusic();
      }

      _gameSnapshotListener = listener;
      game.stateNotifier.addListener(listener);
    }
    _syncMusic();
  }

  void _syncMusic() {
    _gameMusicController
        .set(
          desiredMusicTrack(
            prefsLoaded: _feedbackPreferencesLoaded,
            musicOn: _feedbackPreferences.musicEnabled,
            appForeground: _appForeground,
            stage: _game?.snapshot,
          ),
        )
        .ignore();
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
    // The first-mission guide flag must resolve (or fall back to false)
    // before the loading gate clears, so it loads alongside the campaign.
    FirstMissionGuideStore? guideStore = widget.firstMissionGuideStore;

    try {
      SharedPreferences? preferences;
      if (store == null && widget.progressStoreLoader == null) {
        // Campaign falls back to the default SharedPreferences-backed store.
        // When the feedback store is also defaulted, one SharedPreferences
        // instance backs both.
        preferences = await SharedPreferences.getInstance();
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

      // The default path reuses the already-acquired SharedPreferences; a
      // custom campaign store fetches an instance solely for the guide.
      guideStore ??= await _defaultFirstMissionGuideStore(preferences);
      final guideCompleted = await _loadFirstMissionGuideCompleted(guideStore);
      final seenTips = await _loadSeenTips(guideStore);

      final save = await store.load();

      if (!mounted) {
        return;
      }

      // A missing guide record resolves through campaign progress: a
      // committed Alpha result means this player cleared the tutorial's
      // mission before the flag existed.
      final freezeInferredCompletion =
          guideCompleted == null &&
          save.progress.resultFor(OrionCampaign.stageOneId) != null;

      setState(() {
        _store = store;
        _progress = save.progress;
        _ownedLevels = save.ownedLevels;
        _squad = save.squad;
        _committedProgress = save.progress;
        _committedOwnedLevels = save.ownedLevels;
        _committedSquad = save.squad;
        _firstMissionGuideStore = guideStore;
        // A missing guide record resolves through campaign progress: a
        // committed Alpha result means this player cleared the tutorial's
        // mission before the flag existed, so the guide counts as done.
        // An explicit stored false — Replay Tutorial — is always honored,
        // so replay survives restarts.
        _firstMissionGuideCompleted =
            guideCompleted ??
            (save.progress.resultFor(OrionCampaign.stageOneId) != null);
        _seenTips = seenTips;
        _isLoading = false;
      });

      // Freeze an inferred completion: Reset Campaign wipes the campaign
      // evidence the inference reads, so only a persisted record keeps the
      // grandfathered player's tutorial suppressed on the next launch.
      // Best-effort — a write failure leaves the next load to infer again.
      if (freezeInferredCompletion) {
        guideStore?.setCompleted(true).catchError((_) {});
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      // The gate may clear on a campaign failure before a guide store could
      // be built; build the default store here so Skip/Got it still
      // persist, and keep the null-fallback if that fails too.
      guideStore ??= await _defaultFirstMissionGuideStore(null);
      if (!mounted) {
        return;
      }

      final guideCompleted = await _loadFirstMissionGuideCompleted(guideStore);
      if (!mounted) {
        return;
      }
      final seenTips = await _loadSeenTips(guideStore);
      if (!mounted) {
        return;
      }

      setState(() {
        // Leave _store null on any load failure so a later Launch or victory
        // save can never overwrite an unreadable profile with starter defaults.
        _store = null;
        _progress = CampaignProgress();
        _ownedLevels = CampaignSave.starterOwnedLevels;
        _squad = CampaignSave.starterSquad;
        _committedProgress = CampaignProgress();
        _committedOwnedLevels = CampaignSave.starterOwnedLevels;
        _committedSquad = CampaignSave.starterSquad;
        _firstMissionGuideStore = guideStore;
        _firstMissionGuideCompleted = guideCompleted ?? false;
        _seenTips = seenTips;
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
      _syncMusic();
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
      _syncMusic();
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
      _syncMusic();
    }
  }

  /// Builds the default SharedPreferences-backed guide store, reusing an
  /// already-acquired instance when there is one. SharedPreferences problems
  /// (e.g. tests without mock initial values) leave the store null; the flag
  /// then reads as false for the process.
  Future<FirstMissionGuideStore?> _defaultFirstMissionGuideStore(
    SharedPreferences? preferences,
  ) async {
    try {
      return SharedPreferencesFirstMissionGuideStore(
        preferences: preferences ?? await SharedPreferences.getInstance(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Store failures never block the guide flag; they read as no record,
  /// which the callsite resolves through campaign progress.
  Future<bool?> _loadFirstMissionGuideCompleted(
    FirstMissionGuideStore? store,
  ) async {
    if (store == null) {
      return null;
    }
    try {
      return await store.loadCompleted();
    } catch (_) {
      return null;
    }
  }

  /// Same failure convention as the guide flag: unreadable means empty.
  Future<Set<ContextualTip>> _loadSeenTips(
    FirstMissionGuideStore? store,
  ) async {
    if (store == null) {
      return const {};
    }
    try {
      return await store.loadSeenTips();
    } catch (_) {
      return const {};
    }
  }

  /// In-memory state wins immediately; the store write-through is best-effort
  /// and a failure never touches campaign or feedback breadcrumbs.
  void _setFirstMissionGuideCompleted(bool completed) {
    if (_firstMissionGuideCompleted == completed) {
      return;
    }
    setState(() {
      _firstMissionGuideCompleted = completed;
    });
    _firstMissionGuideStore?.setCompleted(completed).catchError((_) {});
  }

  /// Marks a contextual tip seen: in-memory flip first, then the HPA-412
  /// fire-and-forget write-through. Play never waits on the write.
  void _acknowledgeContextualTip(ContextualTip tip) =>
      _acknowledgeContextualTips([tip]);

  /// Marks several facts seen in ONE flip + ONE write: a multi-fact
  /// snapshot (e.g. a specialized and a retargeted tower together) must
  /// not issue N sequential store writes. Idempotent and best-effort,
  /// exactly like the single-tip path.
  void _acknowledgeContextualTips(Iterable<ContextualTip> tips) {
    final updated = Set.unmodifiable({..._seenTips, ...tips});
    if (updated.length == _seenTips.length) {
      return; // already acknowledged
    }
    setState(() {
      _seenTips = updated;
    });
    _writeSeenTips(updated).catchError((_) {});
  }

  /// Serializes seen-tip write-throughs behind [_seenTipsWrite] so an
  /// older replacement set can never land after a newer one. The chain
  /// head always resolves — failures are swallowed there, never
  /// propagated — so chaining the Replay Tutorial reset onto it drains
  /// every pending acknowledgement before the clear is issued.
  Future<void> _writeSeenTips(Set<ContextualTip> tips) {
    final store = _firstMissionGuideStore;
    if (store == null) {
      return _seenTipsWrite;
    }
    final write = _seenTipsWrite.then((_) => store.setSeenTips(tips));
    _seenTipsWrite = write.catchError((_) {});
    return write;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    switch (_activeView) {
      case _ShellView.title:
        return _buildTitleView();
      case _ShellView.worldMap:
      case _ShellView.camp:
      case _ShellView.codex:
        return _buildMenuShell();
      case _ShellView.stage:
        return _buildStageScaffold();
    }
  }

  Widget _buildTitleView() {
    final recommended = _progress.recommendedStage(OrionCampaign.stages);
    final continueAvailable =
        recommended != null &&
        _progress.statusFor(recommended) == StageProgressStatus.unlocked;
    return OrionTitleView(
      recommendedStage: recommended,
      isContinueAvailable: continueAvailable,
      campaignComplete: _progress.isCampaignComplete(OrionCampaign.stages),
      medalEarned: _progress.totalMedalRank,
      medalTotal: _campaignMedalTotal,
      busy: _isBusy,
      feedback: _mapFeedback,
      onContinue: continueAvailable
          ? () => _showStageBriefing(recommended)
          : null,
      onOpenSectors: () => _openMenuDestination(OrionMenuDestination.sectors),
      onOpenCamp: () => _openMenuDestination(OrionMenuDestination.camp),
      onOpenCodex: () => _openMenuDestination(OrionMenuDestination.codex),
      onOpenSettings:
          _feedbackPreferencesLoaded && !_isSavingFeedback && !_isBusy
          ? _openFeedbackSettings
          : null,
    );
  }

  Widget _buildMenuShell() {
    final destination = switch (_activeView) {
      _ShellView.camp => OrionMenuDestination.camp,
      _ShellView.codex => OrionMenuDestination.codex,
      _ => OrionMenuDestination.sectors,
    };
    final body = switch (_activeView) {
      _ShellView.camp => CampView(
        ownedLevels: _ownedLevels,
        squad: _squad,
        onBack: null,
        embeddedInMenuShell: true,
      ),
      _ShellView.codex => CodexView(
        progress: _progress,
        onBack: null,
        embeddedInMenuShell: true,
      ),
      _ => WorldMapView(
        stages: OrionCampaign.stages,
        progress: _progress,
        embeddedInMenuShell: true,
        campaignModifiers: CampaignModifiers.fromProgress(
          _progress,
          OrionCampaign.stages,
        ),
        feedback: _mapFeedback,
        isSavingProgress: _isSavingProgress,
        isResetting: _isResetting,
        onStageSelected: _showStageBriefing,
        onLockedStageSelected: _showLockedStageFeedback,
      ),
    };
    return OrionMenuShell(
      destination: destination,
      medalEarned: _progress.totalMedalRank,
      medalTotal: _campaignMedalTotal,
      navigationEnabled: !_isBusy,
      settingsEnabled:
          _feedbackPreferencesLoaded && !_isSavingFeedback && !_isBusy,
      onDestinationSelected: _openMenuDestination,
      onOpenSettings: _feedbackPreferencesLoaded ? _openFeedbackSettings : null,
      feedback: _activeView == _ShellView.worldMap ? null : _shellFeedback,
      child: body,
    );
  }

  int get _campaignMedalTotal => OrionCampaign.stages.length * 3;

  bool get _isBusy => _isSavingProgress || _isResetting;

  void _openMenuDestination(OrionMenuDestination destination) {
    if (_isBusy) {
      return;
    }
    final target = switch (destination) {
      OrionMenuDestination.sectors => _ShellView.worldMap,
      OrionMenuDestination.camp => _ShellView.camp,
      OrionMenuDestination.codex => _ShellView.codex,
    };
    if (target == _activeView) {
      return;
    }
    setState(() {
      _shellFeedback = null;
      _activeView = target;
    });
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
      case TowerPlacementPreviewBegin(:final character):
        game.beginTowerPlacementPreview(character);
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
      return _buildMenuShell();
    }
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<GameSnapshot>(
          valueListenable: game.stateNotifier,
          builder: (context, snapshot, _) {
            // Board-cell guide targets derive from the live board layout;
            // a resize re-lays the board without publishing a snapshot, so
            // this builder must also rebuild on size changes or the points
            // keep pointing at pre-rotation coordinates.
            MediaQuery.sizeOf(context);
            // First-mission guidance is a soft overlay on eligible Alpha
            // runs only: snapshot facts choose the step, the completion flag
            // and stage choose eligibility. Never a lock.
            final guideEligible =
                snapshot.stageId == OrionCampaign.stageOneId &&
                !snapshot.isEndless &&
                !_firstMissionGuideCompleted;
            final resolvedGuideStep = guideEligible
                ? firstMissionGuideStepFor(snapshot)
                : null;
            // A selected tower the player cannot afford to upgrade leaves
            // the Upgrade anchor pointing at a disabled button — suppress
            // the callout until they deselect (it then points at the tower
            // cell) or gold covers the cost. Mirrors the chrome's own
            // enable condition in MissionChrome._upgradeSurface.
            final upgradeAnchorDead =
                resolvedGuideStep == FirstMissionGuideStep.upgrade &&
                snapshot.selectedTower != null &&
                (snapshot.selectedTowerStats == null ||
                    snapshot.selectedTowerStats!.nextUpgradeCost == null ||
                    snapshot.gold <
                        snapshot.selectedTowerStats!.nextUpgradeCost!);
            final guideStep = upgradeAnchorDead ? null : resolvedGuideStep;

            // The old HPA-412 guide always wins: while it is eligible (a
            // not-yet-completed Alpha run) no contextual tip shows, even
            // between guide lessons. The modal tower inspector suppresses
            // too: its barrier covers the board, so a surviving bubble
            // would float over dimmed controls (anchor detachment already
            // hides radial-anchored tips; this gate makes it explicit for
            // every anchor kind).
            // The inspector overlay's exact render condition (selected
            // tower inspected, session live, no draft) — shared by the
            // overlay below so a stale _inspectedTowerId never suppresses
            // tips beyond the modal's lifetime, and the two can never
            // drift apart.
            final inspectorOpen =
                snapshot.selectedTower != null &&
                snapshot.selectedTower!.id == _inspectedTowerId &&
                !snapshot.isEnded &&
                snapshot.pendingRunModuleOffer == null;
            final contextualTip = guideEligible || inspectorOpen
                ? null
                : contextualTipFor(snapshot, _seenTips);

            // Placing a tower of an unlock family demonstrates its lesson:
            // union the learned facts post-frame (setState is illegal
            // mid-build). Idempotent, so steady-state snapshots add no work;
            // acknowledgements write through best-effort. Every learned
            // action (placing, specializing, retargeting) is build-gated, so
            // snapshots in other phases — including the countdown's
            // once-per-frame publishes — skip the board scan entirely.
            if (snapshot.phase == GamePhase.build) {
              final learned = learnedTipsIn(snapshot);
              if (learned.any((tip) => !_seenTips.contains(tip))) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _acknowledgeContextualTips(learned);
                });
              }
            }

            // Completion is a snapshot fact, not only a button fact: the
            // auto-start countdown calls game.startWave() directly, so the
            // wave leaving the build phase under the scanner lesson's
            // conditions retires the tutorial even when the chrome's
            // onStartWave never ran. setState inside build is illegal —
            // defer the flag flip to a post-frame callback.
            if (guideEligible &&
                snapshot.phase != GamePhase.build &&
                snapshot.waveNumber >= 3 &&
                snapshot.acquiredRunModules.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _setFirstMissionGuideCompleted(true);
                }
              });
            }

            // Exactly one active card anchor: the guide's member card step.
            // Prefer the first member still deployable (the callout teaches
            // placement), falling back to the first squad member.
            final undeployed = snapshot.squad
                .where((m) => !snapshot.deployedCharacters.contains(m))
                .toList();
            final Character? anchoredCardCharacter =
                guideStep == FirstMissionGuideStep.towerCard
                ? undeployed.firstOrNull ?? snapshot.squad.firstOrNull
                : null;

            GlobalKey? guideAnchorKey;
            Offset? guideTargetPoint;
            switch (guideStep) {
              case null:
                break;
              case FirstMissionGuideStep.buildCell:
                guideTargetPoint = game.boardCellCenter(
                  const GridPosition(2, 2),
                );
              case FirstMissionGuideStep.towerCard:
                guideAnchorKey = _towerCardGuideAnchorKey;
              case FirstMissionGuideStep.startWave:
                guideAnchorKey = _waveGuideAnchorKey;
              case FirstMissionGuideStep.upgrade:
                // The resolver guarantees a tower exists for the upgrade
                // step, so the unselected branch can always point at one.
                if (snapshot.selectedTower == null) {
                  guideTargetPoint = game.boardCellCenter(
                    snapshot.placedTowers.first.position,
                  );
                } else {
                  guideAnchorKey = _upgradeGuideAnchorKey;
                }
              case FirstMissionGuideStep.salvageModule:
                guideAnchorKey = _moduleDraftGuideAnchorKey;
              case FirstMissionGuideStep.scanner:
                guideAnchorKey = _scannerGuideAnchorKey;
            }

            // Contextual anchor targets: boss owns the collapsed scanner,
            // targeting the radial targeting button, and signature either
            // the selected member's radial progression surface or — while
            // idle — the qualifying member's board cell. The resolver
            // guarantees a qualifying member exists whenever it resolves
            // signature.
            GlobalKey? contextualAnchorKey;
            Offset? contextualTargetPoint;
            switch (contextualTip) {
              case null:
                break;
              case ContextualTip.bossWave:
                contextualAnchorKey = _scannerGuideAnchorKey;
              case ContextualTip.signature:
                if (snapshot.selectedTower != null) {
                  contextualAnchorKey = _upgradeGuideAnchorKey;
                } else {
                  contextualTargetPoint = game.boardCellCenter(
                    signatureCandidateIn(snapshot)!.position,
                  );
                }
              case ContextualTip.targeting:
                contextualAnchorKey = _targetingGuideAnchorKey;
              case ContextualTip.stageModifier:
                // Never resolved here — the stage briefing owns it.
                break;
            }
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
                    child: GestureDetector(
                      onLongPressStart: (details) {
                        final box = _gameRenderBox;
                        if (box == null) return;
                        game.handleBoardTap(
                          box.globalToLocal(details.globalPosition),
                        );
                        setState(
                          () => _inspectedTowerId =
                              game.stateNotifier.value.selectedTower?.id,
                        );
                      },
                      child: GameWidget(game: game),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: MissionChrome(
                    snapshot: snapshot,
                    onBoardViewportChanged: (viewport) {
                      // The same rect bounds contextual-tip bubbles; an
                      // empty report is meaningless to both consumers. The
                      // game call must not hide behind || — short-circuit
                      // would skip its board-transform update entirely.
                      if (viewport.isEmpty) return;
                      final gameChanged = game.setBoardViewport(viewport);
                      final pageChanged = _boardViewport != viewport;
                      _boardViewport = viewport;
                      if (mounted && (pageChanged || gameChanged)) {
                        setState(() {});
                      }
                    },
                    towerAnchor: snapshot.selectedTower == null
                        ? null
                        : game.boardCellCenter(
                            snapshot.selectedTower!.position,
                          ),
                    // Guide anchor keys are only attached for the active
                    // step, so gameplay surfaces stay untouched otherwise.
                    towerCardGuideAnchor: anchoredCardCharacter == null
                        ? null
                        : (
                            character: anchoredCardCharacter,
                            anchorKey: _towerCardGuideAnchorKey,
                          ),
                    waveGuideAnchorKey:
                        guideStep == FirstMissionGuideStep.startWave
                        ? _waveGuideAnchorKey
                        : null,
                    upgradeGuideAnchorKey:
                        snapshot.selectedTower != null &&
                            (guideStep == FirstMissionGuideStep.upgrade ||
                                contextualTip == ContextualTip.signature)
                        ? _upgradeGuideAnchorKey
                        : null,
                    targetingGuideAnchorKey:
                        contextualTip == ContextualTip.targeting
                        ? _targetingGuideAnchorKey
                        : null,
                    scannerGuideAnchorKey:
                        guideStep == FirstMissionGuideStep.scanner ||
                            contextualTip == ContextualTip.bossWave
                        ? _scannerGuideAnchorKey
                        : null,
                    onInspectTower:
                        _inspectedTowerId == snapshot.selectedTower?.id
                        ? null
                        : () => setState(
                            () =>
                                _inspectedTowerId = snapshot.selectedTower?.id,
                          ),
                    onBoardTapIntercept: _routeTapToBoard,
                    onWorldMap: game.returnToMap,
                    onStartWave: () {
                      // The scanner lesson completes the tutorial: flip the
                      // flag before the wave starts so no later snapshot
                      // still shows guidance.
                      if (guideStep == FirstMissionGuideStep.scanner) {
                        _setFirstMissionGuideCompleted(true);
                      }
                      // A PLAYER starting the wave while the boss tip is up
                      // acknowledges it — the spec's only start-channel; the
                      // auto-start countdown bypasses this callback and must
                      // NOT acknowledge (a player who never saw the tip gets
                      // it again on the next eligible boss preview). Other
                      // visible tips always stay unseen and may re-guide.
                      // Both flips are synchronous and the write-through is
                      // fire-and-forget, so game.startWave below is never
                      // blocked or delayed.
                      if (contextualTip == ContextualTip.bossWave) {
                        _acknowledgeContextualTip(contextualTip!);
                      }
                      game.startWave();
                    },
                    onTogglePause: game.togglePause,
                    onSpeedSelected: game.setSpeedMultiplier,
                    onToggleAutoStart: game.toggleAutoStart,
                    onPlaceTower: game.placeTower,
                    onUpgrade: game.upgradeSelectedTower,
                    onTargetingChanged: game.setTargetingMode,
                    onSell: game.sellSelectedTower,
                    onPlacementPreviewEvent: _handlePlacementPreviewEvent,
                  ),
                ),
                if (inspectorOpen)
                  Positioned.fill(
                    child: PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (didPop, _) {
                        if (!didPop) setState(() => _inspectedTowerId = null);
                      },
                      child: Stack(
                        children: [
                          ModalBarrier(
                            color: OrionUiTheme.of(
                              context,
                            ).voidBlack.withValues(alpha: .54),
                            dismissible: true,
                            onDismiss: () =>
                                setState(() => _inspectedTowerId = null),
                          ),
                          TowerInspector(
                            snapshot: snapshot,
                            onUpgrade: game.upgradeSelectedTower,
                            onTargetingChanged: game.setTargetingMode,
                            onSell: game.sellSelectedTower,
                            sellRefund: GameBalance.refundValue(
                              snapshot.selectedTower!,
                            ),
                            onClose: () =>
                                setState(() => _inspectedTowerId = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (snapshot.pendingRunModuleOffer case final offer?)
                  Positioned.fill(
                    child: RunModuleDraftPanel(
                      offer: offer,
                      beneficiaries: snapshot.pendingRunModuleBeneficiaries,
                      guideAnchorKey:
                          guideStep == FirstMissionGuideStep.salvageModule
                          ? _moduleDraftGuideAnchorKey
                          : null,
                      onSelected: (moduleId) =>
                          game.selectRunModule(offer.offerId, moduleId),
                    ),
                  ),
                if (snapshot.phase == GamePhase.lost)
                  Positioned.fill(
                    child: snapshot.isEndless
                        ? MissionReportPanel(
                            content: projectEndlessReport(
                              snapshot: snapshot,
                              priorBest: _endlessPriorBest,
                              savedBest: _committedProgress.endlessBestFor(
                                snapshot.stageId,
                              ),
                              saveState:
                                  _missionSaveState ?? MissionSaveState.saved,
                            ),
                            onReplay:
                                _missionSaveState == MissionSaveState.saved
                                ? _restartFromMissionReport
                                : null,
                            onReturnToMap:
                                _missionSaveState == MissionSaveState.saving
                                ? null
                                : _returnFromMissionReport,
                            onRetrySave:
                                _missionSaveState == MissionSaveState.failed
                                ? _retryEndlessBestSave
                                : null,
                          )
                        : MissionReportPanel(
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
                // Rendered last so it sits above the module panel/report
                // layers while remaining non-modal (no barrier, no lock).
                if (guideStep case final step?)
                  Positioned.fill(
                    child: FirstMissionGuideCallout(
                      step: step,
                      anchorKey: guideAnchorKey,
                      targetPoint: guideTargetPoint,
                      onSkip: () => _setFirstMissionGuideCompleted(true),
                      // "Got it" is scanner-only: the callout renders it iff
                      // onDone is non-null.
                      onDone: step == FirstMissionGuideStep.scanner
                          ? () => _setFirstMissionGuideCompleted(true)
                          : null,
                    ),
                  ),
                if (contextualTip case final ContextualTip tip)
                  Positioned.fill(
                    child: ContextualTipCallout(
                      tip: tip,
                      anchorKey: contextualAnchorKey,
                      targetPoint: contextualTargetPoint,
                      boardViewport: _boardViewport,
                      onDone: () => _acknowledgeContextualTip(tip),
                      // The radial progression surface tops the radial
                      // menu: pin its bubble up so it never covers the
                      // Inspect/Salvage row beneath. The targeting anchor
                      // sits at the radial's bottom — below it is free
                      // space down to the board viewport edge, so it keeps
                      // the default below-first placement and only flips
                      // up when the dock leaves no room.
                      preferAbove:
                          contextualAnchorKey == _upgradeGuideAnchorKey,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Recovers only the campaign store and committed profile after an initial
  /// load failure, without touching mid-session onboarding or feedback state.
  Future<CampaignSave?> _retryCampaignLoad() async {
    try {
      CampaignProgressStore? store = widget.progressStore;
      if (store == null && widget.progressStoreLoader == null) {
        final preferences = await SharedPreferences.getInstance();
        store = SharedPreferencesCampaignProgressStore(
          preferences: preferences,
          knownStages: OrionCampaign.stages,
        );
      }
      store ??= await widget.progressStoreLoader!();
      final save = await store.load();
      if (!mounted) {
        return null;
      }
      setState(() {
        _store = store;
        _progress = save.progress;
        _ownedLevels = save.ownedLevels;
        _squad = save.squad;
        _committedProgress = save.progress;
        _committedOwnedLevels = save.ownedLevels;
        _committedSquad = save.squad;
        if (_mapFeedback == 'Could not load campaign progress.') {
          _mapFeedback = null;
        }
      });
      return save;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showStageBriefing(StageDefinition stage) async {
    // Run inputs derive from the last-known committed disk state, mirroring
    // what a stage launch would actually use; the sheet renders primitives.
    final openedSquad = _committedSquad;
    final openedOwnedLevels = _committedOwnedLevels;
    final openedResult = _committedProgress.resultFor(stage.id);
    final openedEndlessBest = _committedProgress.endlessBestFor(stage.id);
    final modifiers = _committedCampaignModifiers();
    // The once-only stage-modifier tip lives inside this modal route: a
    // parent setState never rebuilds an open route, so the route's own
    // StatefulBuilder owns visibility and clears it on Got it before the
    // page persists the acknowledgement. Seeded once from the seen set —
    // closing or launching the sheet without Got it leaves it unseen.
    final modifierTipAnchorKey = GlobalKey();
    var modifierTipVisible =
        stage.modifiers.isNotEmpty &&
        !_seenTips.contains(ContextualTip.stageModifier);
    final mode = await showModalBottomSheet<RunMode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The bottom-sheet drag path calls Navigator.pop imperatively — it
      // cannot consult the sheet's in-flight-save veto, so a downward fling
      // could strand the commit or the retry surface. Dismissal stays on
      // the sheet's own Dismiss/back affordances.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: orionSheetAnimationStyle(context),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => StageBriefingSheet(
          stage: stage,
          // Aligned with the rest of the committed-state pattern: the briefing
          // sheet's Start/Replay label, reward-earned flag, best-result line,
          // and HPA-528 blueprint-recovered signal are all first-clear facts
          // sourced from disk, not the optimistic `_progress` aggregate.
          result: openedResult,
          endlessBest: openedEndlessBest,
          startingGold: modifiers.adjustedStartingGold,
          startingBaseHealth: StageModifierRules.effectiveStartingBaseHealth(
            campaignAdjustedBaseHealth: modifiers.adjustedStartingBaseHealth,
            stageModifiers: stage.modifiers,
          ),
          modifierTip: modifierTipVisible
              ? (
                  anchorKey: modifierTipAnchorKey,
                  onDone: () {
                    setSheetState(() => modifierTipVisible = false);
                    _acknowledgeContextualTip(ContextualTip.stageModifier);
                  },
                )
              : null,
          // The launch draft seeds from committed state — the same values a
          // run would read — while the sheet edits its local copy and hands
          // the draft back through onLaunch.
          squad: openedSquad,
          ownedLevels: openedOwnedLevels,
          onLaunch: (mode, draft) => _persistSquadDraft(
            draft,
            stage: stage,
            mode: mode,
            openedSquad: openedSquad,
            openedOwnedLevels: openedOwnedLevels,
            openedModifiers: modifiers,
            openedResult: openedResult,
            openedEndlessBest: openedEndlessBest,
            sheetContext: sheetContext,
          ),
        ),
      ),
    );

    if (mode != null && mounted) {
      _startStage(stage, mode);
    }
  }

  /// The stage briefing's single write on Launch (HPA-922 task 6): the
  /// sheet's local draft is committed through the same committed-base queue
  /// as every other campaign write. The returned future settles only after
  /// the queued save's `finally` clears the pending flag, so the sheet pops
  /// — and this page's post-route continuation starts the stage — strictly
  /// after the write lands or is reported lost.
  Future<bool> _persistSquadDraft(
    List<Character> draft, {
    required StageDefinition stage,
    required RunMode mode,
    required List<Character> openedSquad,
    required Map<Character, int> openedOwnedLevels,
    required CampaignModifiers openedModifiers,
    required StageResult? openedResult,
    required int? openedEndlessBest,
    required BuildContext sheetContext,
  }) async {
    // A failed initial load leaves _store null and Launch would fail forever:
    // recover only the campaign store/profile before writing anything.
    if (_store == null && await _retryCampaignLoad() == null) {
      return false;
    }
    // Abort Launch whenever committed state no longer matches what the
    // briefing displayed — recovery can swap in a different roster, and a
    // sheet a covering route kept open through the first mismatch must not
    // lose the guard on retry.
    final committedModifiers = _committedCampaignModifiers();
    final briefingMatches =
        listEquals(_committedSquad, openedSquad) &&
        mapEquals(_committedOwnedLevels, openedOwnedLevels) &&
        committedModifiers.adjustedStartingGold ==
            openedModifiers.adjustedStartingGold &&
        committedModifiers.adjustedStartingBaseHealth ==
            openedModifiers.adjustedStartingBaseHealth &&
        _committedProgress.resultFor(stage.id) == openedResult &&
        _committedProgress.endlessBestFor(stage.id) == openedEndlessBest &&
        _committedProgress.isUnlocked(stage) &&
        (mode != RunMode.endless || _committedProgress.isCleared(stage.id));
    if (!briefingMatches) {
      if (mounted) {
        setState(() {
          _mapFeedback =
              'Campaign progress recovered — review squad before launching.';
        });
      }
      if (sheetContext.mounted) {
        final route = ModalRoute.of(sheetContext);
        if (route != null && route.isActive && route.isCurrent) {
          Navigator.of(sheetContext).pop();
        }
      }
      return false;
    }
    if (listEquals(draft, _committedSquad)) {
      return true;
    }
    return _persistSave(
      buildSave: (committed) => committed.withSquad(draft),
      onCommitted: (payload) => _squad = payload.squad,
      // Failure feedback lives inside the still-mounted sheet (retryable); a
      // map breadcrumb would sit hidden under the modal route.
      onFailed: () {},
    );
  }

  Future<void> _openFeedbackSettings() async {
    if (_isSavingFeedback || !_feedbackPreferencesLoaded || _isBusy) {
      return;
    }
    final result = await showModalBottomSheet<FeedbackSettingsResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: orionSheetAnimationStyle(context),
      builder: (context) => FeedbackSettingsSheet(
        initialPreferences: _feedbackPreferences,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onReplayTutorial: () async {
          // The sheet confirms only after this future completes, so the flags
          // must be reset AND persisted here: a store problem throws back to
          // the sheet, which leaves the action enabled and shows no
          // confirmation. The writes are unconditional — an in-memory reset
          // over a stale persisted record must still rewrite both.
          var store = _firstMissionGuideStore;
          store ??= await _defaultFirstMissionGuideStore(null);
          if (store == null) {
            throw StateError('First-mission guide store is unavailable.');
          }
          _firstMissionGuideStore = store;
          // Chained behind every pending acknowledgement like the other
          // seen-tip writes — an in-flight ack lands BEFORE the reset and
          // can never repopulate the replayed set. The store makes the
          // pair transactional: if the completion write fails after the
          // clear, the prior record is restored verbatim, so a reported
          // failure persists nothing.
          final guideStore = store;
          final reset = _seenTipsWrite.then((_) => guideStore.resetForReplay());
          _seenTipsWrite = reset.catchError((_) {});
          await reset;
          if (mounted) {
            setState(() {
              _seenTips = const {};
              _firstMissionGuideCompleted = false;
            });
          }
        },
      ),
    );

    if (result == null) {
      return;
    }

    if (result.preferences != _feedbackPreferences) {
      final saved = await _saveFeedbackPreferences(result.preferences);
      if (!saved) {
        return;
      }
    }
    if (result.resetCampaignRequested && mounted) {
      await _confirmResetCampaign();
    }
  }

  Future<bool> _saveFeedbackPreferences(FeedbackPreferences updated) async {
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
        return false;
      }
      setState(() {
        _setActiveDestinationFeedback(_feedbackSaveFailureMessage);
      });
      return false;
    }
    var committed = false;
    try {
      await store.save(updated);
      committed = true;
      if (!mounted) {
        return true;
      }
      setState(() {
        _feedbackPreferences = updated;
        _feedbackPreferencesLoaded = true;
        if (_mapFeedback == _feedbackSaveFailureMessage) {
          _mapFeedback = null;
        }
        if (_shellFeedback == _feedbackSaveFailureMessage) {
          _shellFeedback = null;
        }
      });
      _syncMusic();
    } catch (_) {
      // Keep the prior effective value; surface a breadcrumb like the
      // campaign persistence failure path.
      if (!mounted) {
        return false;
      }
      setState(() {
        _setActiveDestinationFeedback(_feedbackSaveFailureMessage);
      });
    } finally {
      _isSavingFeedback = false;
      if (mounted) {
        setState(() {});
      }
    }
    return committed;
  }

  // Run inputs (campaign modifiers and module eligibility) are derived from
  // the last-known committed disk state, not the optimistic `_progress`
  // aggregate. One attempt freezes committed run inputs; a same-object
  // Replay refreshes ALL committed run inputs together (HPA-528).
  CampaignModifiers _committedCampaignModifiers() =>
      CampaignModifiers.fromProgress(_committedProgress, OrionCampaign.stages);

  void _startStage(StageDefinition stage, RunMode mode) {
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

    if (mode == RunMode.endless && !_committedProgress.isCleared(stage.id)) {
      return;
    }

    final campaignModifiers = _committedCampaignModifiers();
    _endlessSaveSequence = 0;
    _missionPriorResult = _committedProgress.resultFor(stage.id);
    _missionVictoryResult = null;
    _missionStageId = stage.id;
    _missionSaveState = mode == RunMode.endless ? MissionSaveState.saved : null;
    _endlessPriorBest = mode == RunMode.endless
        ? _committedProgress.endlessBestFor(stage.id)
        : null;
    final game = OrionDefenseGame(
      stage: stage,
      mode: mode,
      campaignModifiers: campaignModifiers,
      availableRunModules: RunModuleUnlocks.availableFor(_committedProgress),
      moduleOfferPicker: widget.moduleOfferPicker,
      // The committed squad goes to battle in selection order, each member
      // carrying their persistent profile level (HPA-922).
      squad: {
        for (final member in _committedSquad)
          member: _committedOwnedLevels[member] ?? 1,
      },
      onStageWon: _handleStageWon,
      onEndlessWaveCleared: _saveEndlessBest,
      onReturnToMap: _returnFromMissionReport,
      gameFeedback: _gameFeedback,
    );
    widget.onGameCreated?.call(game);

    setState(() {
      _mapFeedback = null;
      _shellFeedback = null;
      _listenToGame(game);
      _inspectedTowerId = null;
      _boardViewport = null;
      _activeView = _ShellView.stage;
    });
  }

  void _showLockedStageFeedback(StageDefinition stage) {
    setState(() {
      _mapFeedback = '${stage.name} is locked.';
    });
  }

  /// Queues one atomic campaign write and resolves `true` only once the
  /// queued task has committed (and [onCommitted] ran) — `false` on any
  /// failure, a missing store, or a reset that invalidated the write. The
  /// future awaits the queued task itself, so it settles strictly after its
  /// `finally` reconciles the pending-save counter: a caller can gate a
  /// follow-on step (stage launch) on the busy flag being clear again.
  Future<bool> _persistSave({
    required CampaignSave Function(CampaignSave committed) buildSave,
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
      return false;
    }

    final saveGeneration = _progressGeneration;
    _pendingSaves++;
    _setSavingProgress(true);

    // Queue the COMPLETE transaction — persistence, failure reporting, and
    // saving-state reconciliation — so the next writer cannot start until
    // this one has committed or reported.
    //
    // The persisted payload is built from the last-known committed disk state
    // (_committed*), NOT from the shared optimistic _progress/profile
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
    var committed = false;
    final saveTask = _saveQueue.then((_) async {
      try {
        if (saveGeneration != _progressGeneration) {
          onFailed?.call();
          return; // a reset invalidated this save; the reset owns wiping
        }
        final payload = buildSave(
          CampaignSave(
            progress: _committedProgress,
            ownedLevels: _committedOwnedLevels,
            squad: _committedSquad,
          ),
        );
        await store.save(payload);
        if (saveGeneration == _progressGeneration) {
          _committedProgress = payload.progress;
          _committedOwnedLevels = payload.ownedLevels;
          _committedSquad = payload.squad;
          onCommitted?.call(payload);
          committed = true;
        } else if (onFailed != null) {
          onFailed();
        }
      } catch (_) {
        if (saveGeneration == _progressGeneration) {
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
    try {
      await saveTask;
    } catch (_) {
      // A task-level throw (only the reconciliation `finally` could produce
      // one) reports as not-committed; the swallowed queue error above keeps
      // the chain alive for the next writer.
    }
    return committed;
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
        ownedLevels: committed.ownedLevels,
        squad: committed.squad,
      ),
      onCommitted: (payload) {
        _progress = payload.progress;
        _setMissionSaveState(MissionSaveState.saved);
      },
      onFailed: () => _setMissionSaveState(MissionSaveState.failed),
    );
  }

  void _saveEndlessBest(int wavesCleared) {
    final stageId = _missionStageId;
    if (stageId == null || wavesCleared <= (_endlessPriorBest ?? 0)) {
      return;
    }

    final saveSequence = ++_endlessSaveSequence;
    _setMissionSaveState(MissionSaveState.saving);
    _persistSave(
      buildSave: (committed) => CampaignSave(
        progress: committed.progress.recordEndlessBest(stageId, wavesCleared),
        ownedLevels: committed.ownedLevels,
        squad: committed.squad,
      ),
      onCommitted: (payload) {
        _progress = payload.progress;
        if (saveSequence == _endlessSaveSequence) {
          if (_mapFeedback == _persistenceFailureMessage) {
            _mapFeedback = null;
          }
          _setMissionSaveState(MissionSaveState.saved);
        }
      },
      onFailed: () {
        if (saveSequence == _endlessSaveSequence) {
          _setMissionSaveState(MissionSaveState.failed);
          if (mounted && _game?.snapshot.isEnded == false) {
            _showCampaignPersistenceFailure();
          }
        }
      },
    );
  }

  void _retryEndlessBestSave() {
    if (_missionSaveState != MissionSaveState.failed) {
      return;
    }
    final wavesCleared = _game?.snapshot.wavesCleared;
    if (wavesCleared == null) {
      return;
    }
    _saveEndlessBest(wavesCleared);
  }

  void _setMissionSaveState(MissionSaveState state) {
    _missionSaveState = state;
    if (mounted) {
      setState(() {});
    }
  }

  // The blueprint recovery reward is a first-clear fact: _missionPriorResult
  // was captured from committed progress at attempt start, so a successful
  // save can advance _committedProgress without changing the first-clear
  // fact for the completed attempt. Replay recaptures _missionPriorResult
  // from committed progress (now non-null) and suppresses duplicate
  // celebration. The module identity resolves generically from the
  // mission's own stage (HPA-415); Alpha's strings are the Relay
  // Calibration instance of the same pattern.
  MissionRewardFact? _missionRewardFact() {
    final stageId = _missionStageId;
    if (stageId == null || _missionPriorResult != null) {
      return null;
    }

    final blueprint = OrionCampaign.stageById(stageId).blueprint;
    if (blueprint == null) {
      return null;
    }
    final module = runModuleDefinition(blueprint);

    return switch (_missionSaveState) {
      MissionSaveState.saving => MissionRewardFact(
        title: 'Blueprint recovery pending',
        detail: '${module.title} unlocks after this result is saved.',
      ),
      MissionSaveState.saved => MissionRewardFact(
        title: 'Blueprint recovered: ${module.title}',
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
      _listenToGame(null);
      _activeView = _ShellView.worldMap;
    });
  }

  void _returnFromMissionReport() {
    if (_missionSaveState == MissionSaveState.saving) {
      final isEndless = _game?.snapshot.isEndless ?? false;
      if (isEndless && _activeView == _ShellView.stage && _game != null) {
        _game!.overrideFeedback(
          'Saving Endless best… Finish saving before returning.',
        );
      }
      return;
    }
    if (_missionSaveState == MissionSaveState.failed) {
      final isEndless = _game?.snapshot.isEndless ?? false;
      if (isEndless) {
        final savedBest = _missionStageId == null
            ? null
            : _committedProgress.endlessBestFor(_missionStageId!);
        final committedEarlier =
            savedBest != null && savedBest > (_endlessPriorBest ?? 0);
        _mapFeedback = committedEarlier
            ? 'Endless save failed — best $savedBest ${savedBest == 1 ? 'wave' : 'waves'} kept.'
            : 'Endless best was not saved.';
      } else {
        _mapFeedback = 'Mission result was not saved.';
      }
    }
    _returnToMap();
  }

  void _restartFromMissionReport() {
    final game = _game;
    if (game == null) return;

    final isEndless = game.snapshot.isEndless;
    if (isEndless) {
      if (_missionSaveState != MissionSaveState.saved) {
        return;
      }
    } else if (_missionVictoryResult != null &&
        _missionSaveState != MissionSaveState.saved) {
      return;
    }

    _inspectedTowerId = null;
    _endlessSaveSequence = 0;
    _missionPriorResult = _committedProgress.resultFor(_missionStageId!);
    _missionVictoryResult = null;
    _missionSaveState = isEndless ? MissionSaveState.saved : null;
    if (isEndless) {
      _endlessPriorBest = _committedProgress.endlessBestFor(_missionStageId!);
    }
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
            child: OrionSurface(
              key: const ValueKey('reset-campaign-dialog'),
              role: OrionSurfaceRole.sheet,
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
                        child: OrionTitle(
                          'Reset Campaign',
                          color: uiTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OrionText.micro(
                    'Clear all campaign progress?',
                    color: uiTheme.textMuted,
                    size: 10,
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
        _setActiveDestinationFeedback('Could not reset campaign progress.');
      });
      return;
    }

    // Serialize the reset with the save queue: wait for all pending saves to
    // drain, then perform exactly one reset as the next queued operation.
    // No save can interleave because stage launches are disabled while
    // _isResetting is true. Generation bumps monotonically
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
        _ownedLevels = CampaignSave.starterOwnedLevels;
        _squad = CampaignSave.starterSquad;
        _committedProgress = CampaignProgress();
        _committedOwnedLevels = CampaignSave.starterOwnedLevels;
        _committedSquad = CampaignSave.starterSquad;
        _listenToGame(null);
        if (_activeView == _ShellView.stage) {
          _activeView = _ShellView.worldMap;
        }
        _mapFeedback = null;
        _shellFeedback = null;
        _setActiveDestinationFeedback('Campaign reset.');
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
        _setActiveDestinationFeedback('Could not reset campaign progress.');
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

  void _setActiveDestinationFeedback(String message) {
    if (_activeView == _ShellView.camp || _activeView == _ShellView.codex) {
      _shellFeedback = message;
    } else {
      _mapFeedback = message;
    }
  }

  void _showCampaignPersistenceFailure() {
    const message = _persistenceFailureMessage;
    final game = _game;
    setState(() {
      _mapFeedback = message; // always; preserves HPA-94 breadcrumb behavior
    });
    if (_activeView == _ShellView.stage && game != null) {
      game.overrideFeedback(message);
    }
  }
}
