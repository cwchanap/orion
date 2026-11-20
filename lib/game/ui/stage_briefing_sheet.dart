import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../models/game_models.dart';
import '../rules/stage_scrip_rules.dart';
import '../util/format.dart';
import '../onboarding/contextual_tips.dart';
import 'campaign_presentation.dart';
import 'first_mission_guide_callout.dart';
import 'orion_atlas_sprite.dart';
import 'orion_scroll_view.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Full-height modal stage briefing (scene 1b): full-bleed wide stage-key-art
/// hero, stage identity, run facts, conditions, prior result, the squad
/// picker, and the launch actions.
///
/// Presentation only — the page derives the run inputs from committed campaign
/// state and passes them as primitives; no briefing view-model exists. The
/// squad section edits a route-local draft seeded from the committed roster:
/// tapping a member never writes, Cancel discards the whole draft, and Launch
/// hands the draft to [onLaunch] exactly once (HPA-922 task 6).
class StageBriefingSheet extends StatefulWidget {
  const StageBriefingSheet({
    super.key,
    required this.stage,
    required this.result,
    required this.startingGold,
    required this.startingBaseHealth,
    required this.squad,
    required this.ownedLevels,
    required this.onLaunch,
    this.endlessBest,
    this.modifierTip,
  });

  final StageDefinition stage;
  final StageResult? result;
  final int? endlessBest;

  /// Effective start credits for the committed run (campaign-adjusted gold).
  final int startingGold;

  /// Effective starting hull for the committed run (campaign- and
  /// stage-adjusted base health).
  final int startingBaseHealth;

  /// The last-committed ordered squad — seeds the route-local draft.
  final List<Character> squad;

  /// Every owned character mapped to its persistent level; the picker offers
  /// exactly these members, in [Character.values] order.
  final Map<Character, int> ownedLevels;

  /// Called once per launch tap with the local draft, after the draft's
  /// single queued write has been requested. Resolves `true` only when the
  /// write committed; the sheet then pops itself with the selected [RunMode]
  /// and the page's post-route continuation starts the stage. A `false`
  /// return keeps the modal open with retryable feedback — the caller must
  /// not pop or launch itself.
  final Future<bool> Function(RunMode mode, List<Character> draft) onLaunch;

  /// Renders the once-only stage-modifier tip over this sheet when set
  /// (and real modifiers are present): the modifier tile's anchor key plus
  /// its acknowledgement. The briefing route — not this sheet — owns the
  /// tip's visibility, so the pair is always passed together or not at all.
  final ({GlobalKey anchorKey, VoidCallback onDone})? modifierTip;

  @override
  State<StageBriefingSheet> createState() => _StageBriefingSheetState();
}

class _StageBriefingSheetState extends State<StageBriefingSheet>
    implements PopEntry<Object?> {
  /// The route-local squad draft — seeded from the committed roster, edited
  /// in place, discarded by Cancel, and written once on Launch.
  late final List<Character> _draft = List.of(widget.squad);

  /// Route-level pop veto registered on the enclosing modal route in
  /// [didChangeDependencies]. Unlike `PopScope.canPop` — which only reaches
  /// the route on the next rebuild — the notifier flips synchronously inside
  /// [_launch], so a back press, a barrier tap, or a stale Dismiss callback
  /// landing between the launch tap and the first rebuilt frame still meets
  /// the veto. The page opens the route with `enableDrag: false` because the
  /// bottom-sheet drag path pops imperatively and cannot consult this.
  final _canPop = ValueNotifier<bool>(true);

  ModalRoute<Object?>? _route;

  /// A launch whose save committed while a pushed route covered this sheet.
  /// Popping immediately would dismiss the covering route, and unwinding
  /// [_launching] would wedge "Saving squad…" behind it — so the mode waits
  /// here until the route regains `isCurrent`, when [didChangeDependencies]
  /// or [_onDeferredWake] hands it to [_finishDeferredLaunch].
  RunMode? _deferredLaunchMode;

  /// Event wakes for the deferred finish. A cover pushed and removed inside
  /// a single frame produces no `isCurrent` rebuild for the inherited
  /// notification to fire — and, verified empirically, no
  /// [ModalRoute.secondaryAnimation] status edge either — so the defer arms
  /// both the animation listener and a bounded post-frame recheck chain.
  /// Two consecutive rechecks are enough: a cover still present after a
  /// second full frame has had its `isCurrent:false` status built, which
  /// makes the inherited notification reliable for its removal again.
  Animation<double>? _deferredWakeAnimation;
  var _deferredRecheckScheduled = false;
  var _deferredRecheckBudget = 0;

  var _pickerOpen = false;
  var _launching = false;
  var _launchFailed = false;
  String? _editFeedback;

  /// Anchors the YOUR SQUAD section so opening the picker can scroll it —
  /// and its new chips — into view.
  final _squadSectionKey = GlobalKey();

  bool get _launchEnabled => _draft.isNotEmpty && !_launching;

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.unregisterPopEntry(this);
      _route = route;
      _route?.registerPopEntry(this);
    }
    // ModalRoute.of subscribes to every _ModalScopeStatus change, so this
    // refires when the route regains `isCurrent` — the only moment a
    // deferred launch may finish.
    _finishDeferredLaunch();
  }

  @override
  void dispose() {
    _disarmDeferredWake();
    _route?.unregisterPopEntry(this);
    _canPop.dispose();
    super.dispose();
  }

  void _togglePicker() {
    if (_launching) {
      return;
    }
    setState(() {
      _pickerOpen = !_pickerOpen;
      _editFeedback = null;
    });
    if (_pickerOpen) {
      // The picker grows the section below the current fold; reveal it so
      // every offered member is tappable without a manual scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final squadContext = _squadSectionKey.currentContext;
        if (squadContext != null) {
          Scrollable.ensureVisible(
            squadContext,
            alignment: 1,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
  }

  /// Adds a member to the draft's end or removes it — the only order edit
  /// the picker models, which keeps the displayed order unambiguous.
  void _toggleMember(Character member) {
    if (_launching) {
      return;
    }
    setState(() {
      if (_draft.remove(member)) {
        _editFeedback = null;
      } else if (_draft.length >= GameBalance.squadMaxSize) {
        _editFeedback = 'Squad is full — remove a member first.';
      } else {
        _draft.add(member);
        _editFeedback = null;
      }
    });
  }

  Future<void> _launch(RunMode mode) async {
    if (!_launchEnabled) {
      return;
    }
    // Synchronous first: the rebuild that nulls the controls lands a frame
    // later, but the route must already refuse to pop.
    _canPop.value = false;
    setState(() {
      _launching = true;
      _launchFailed = false;
    });
    bool committed;
    try {
      committed = await widget.onLaunch(mode, List.of(_draft));
    } catch (_) {
      // A throwing callback — synchronous or a rejected future — lands on
      // the same retryable failure path as a clean false.
      committed = false;
    }
    if (!mounted) {
      return;
    }
    if (committed) {
      // The page's post-route continuation owns _startStage: pop exactly
      // once with the mode and never start anything here.
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) {
        // The route is already gone or being removed — leave the committed
        // save standing; popping now could hit the route beneath.
        return;
      }
      if (!route.isCurrent) {
        // Active but covered — a route pushed on top while the save was in
        // flight. Popping now would dismiss the covering route; unwinding
        // _launching would strand "Saving squad…" behind it. Keep the
        // in-flight state and defer the finish until the cover lifts.
        _deferredLaunchMode = mode;
        _armDeferredWake(route);
        return;
      }
      Navigator.of(context).pop(mode);
      return;
    }
    _canPop.value = true;
    setState(() {
      _launching = false;
      _launchFailed = true;
    });
  }

  /// The Cancel path. [_launching] is re-checked at call time: the
  /// IconButton's null `onPressed` only lands on the rebuild after a launch
  /// starts, so a tap racing that frame must meet the guard here instead.
  void _dismiss() {
    if (_launching) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// Finishes a launch whose save committed while a pushed route covered
  /// the sheet. Called from [didChangeDependencies] — which refires on the
  /// `isCurrent` flip — and from [_onDeferredWake], which catches the cover
  /// lifecycles that flip coalesces away. The pop itself waits one frame:
  /// route status changes land mid-update, and a synchronous Navigator pop
  /// there would re-enter the transition machinery before history settles.
  void _finishDeferredLaunch() {
    if (_deferredLaunchMode == null || _route?.isCurrent != true) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mode = _deferredLaunchMode;
      if (!mounted || mode == null) {
        return;
      }
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) {
        // Another cover interposed before this callback. If its whole
        // lifecycle also fits inside the frame window it leaves no signal
        // behind, so spend one bounded recheck rather than trusting a
        // notification that may never come.
        if (route != null) {
          _queueDeferredRecheck(1);
        }
        return;
      }
      _deferredLaunchMode = null;
      _disarmDeferredWake();
      Navigator.of(context).pop(mode);
    });
    // A post-frame wake needs a new frame for the queued pop to run.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Arms the wakes for a deferred finish. The
  /// [ModalRoute.secondaryAnimation] listener costs one callback per cover
  /// transition — never per frame — and [_queueDeferredRecheck] covers the
  /// transitions that announce nothing at all.
  void _armDeferredWake(ModalRoute<Object?> route) {
    _queueDeferredRecheck(2);
    final animation = route.secondaryAnimation;
    if (animation == null || identical(animation, _deferredWakeAnimation)) {
      return;
    }
    _deferredWakeAnimation?.removeStatusListener(_onDeferredWake);
    _deferredWakeAnimation = animation;
    animation.addStatusListener(_onDeferredWake);
  }

  void _onDeferredWake(AnimationStatus status) {
    if (_deferredLaunchMode == null || !mounted) {
      _disarmDeferredWake();
      return;
    }
    // Edges fire mid history-update, before the covering entry has fully
    // left `isPresent`, so `isCurrent` cannot be trusted at this tick —
    // hand off to a post-frame recheck with a fresh bounded budget.
    _queueDeferredRecheck(2);
  }

  /// Schedules one post-frame recheck of the deferred finish. Each wake may
  /// chain at most [budget] further rechecks while the route stays covered;
  /// once a cover has survived a full frame its `isCurrent:false` status
  /// has been built, so the inherited notification and animation edges can
  /// be trusted to announce its removal and the chain stops.
  void _queueDeferredRecheck([int budget = 1]) {
    if (_deferredRecheckBudget < budget) {
      _deferredRecheckBudget = budget;
    }
    if (_deferredRecheckScheduled) {
      return;
    }
    _deferredRecheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredRecheckScheduled = false;
      if (!mounted || _deferredLaunchMode == null) {
        return;
      }
      _finishDeferredLaunch();
      if (_deferredLaunchMode != null && _deferredRecheckBudget > 0) {
        _deferredRecheckBudget -= 1;
        _queueDeferredRecheck(0);
      }
    });
    // Post-frame callbacks do not schedule their own successor frames.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _disarmDeferredWake() {
    _deferredRecheckBudget = 0;
    _deferredWakeAnimation?.removeStatusListener(_onDeferredWake);
    _deferredWakeAnimation = null;
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stage = widget.stage;
    final result = widget.result;
    final isOptional = !stage.isMainPath;
    final accent = isOptional ? uiTheme.systemViolet : uiTheme.systemCyan;
    final metadata = stage.modifiers.isEmpty
        ? [StageModifierMetadata.standardConditions]
        : stage.modifiers
              .map(StageModifierMetadata.forModifier)
              .toList(growable: false);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    const headerHeight = 64.0;
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.4).clamp(
      260.0,
      360.0,
    );
    final facts = [
      _BriefingStatTile(
        icon: Icons.waves_rounded,
        value: '${stage.waves.length}',
        label: 'WAVES',
        color: uiTheme.systemCyan,
        horizontal: largeText,
      ),
      _BriefingStatTile(
        icon: Icons.shield_outlined,
        value: '${widget.startingBaseHealth}',
        label: 'HULL',
        color: uiTheme.systemCyan,
        horizontal: largeText,
      ),
      _BriefingStatTile(
        icon: Icons.hexagon,
        value: '${widget.startingGold}',
        label: 'START',
        color: uiTheme.creditGold,
        valueColor: uiTheme.creditGold,
        horizontal: largeText,
      ),
    ];
    final medalCriteria = [
      _BriefingIntelRow(
        icon: medalIcon(StageMedal.gold),
        color: uiTheme.creditGold,
        title: '${widget.startingBaseHealth}/${widget.startingBaseHealth}',
        detail: 'GOLD · NO LEAKS',
      ),
      _BriefingIntelRow(
        icon: medalIcon(StageMedal.silver),
        color: uiTheme.textMuted,
        title: '${GameBalance.silverMedalThreshold}+ HULL',
        detail: 'SILVER',
      ),
    ];

    // While a launch save is in flight the route cannot be dismissed — the
    // PopEntry registered in didChangeDependencies vetoes barrier taps and
    // the system back gesture; the sheet's own Dismiss and launch controls
    // disable alongside.
    return Material(
      color: uiTheme.voidBlack,
      child: SizedBox.expand(
        key: const ValueKey('stage-briefing'),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.5,
                child: Image.asset(
                  'assets/images/reactor_rim_ui/boards/nebula.png',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      uiTheme.voidBlack,
                      uiTheme.voidBlack.withValues(alpha: 0.28),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight,
              child: IgnorePointer(
                child: _BriefingHero(
                  stage: stage,
                  scrimColor: uiTheme.voidBlack,
                ),
              ),
            ),
            Column(
              children: [
                const SizedBox(height: headerHeight),
                Expanded(
                  child: OrionScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: heroHeight - headerHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 24,
                                child: _BriefingIdentity(
                                  stage: stage,
                                  accent: accent,
                                  badgeLabel: isOptional
                                      ? 'OPTIONAL'
                                      : 'PRIMARY',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                key: const ValueKey('briefing-facts'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (largeText)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (final (index, fact)
                                            in facts.indexed) ...[
                                          if (index > 0)
                                            const SizedBox(height: 8),
                                          fact,
                                        ],
                                      ],
                                    )
                                  else
                                    Row(
                                      children: [
                                        for (final (index, fact)
                                            in facts.indexed) ...[
                                          if (index > 0)
                                            const SizedBox(width: 8),
                                          Expanded(child: fact),
                                        ],
                                      ],
                                    ),
                                  if (metadata.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    KeyedSubtree(
                                      key: widget.modifierTip?.anchorKey,
                                      child: _BriefingModifierTile(
                                        key: const ValueKey(
                                          'briefing-modifier',
                                        ),
                                        title: metadata.first.title,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              // The tile above names the modifier, so this is
                              // its effect, not its name again. The artboard has
                              // no conditions section at all -- it expects the
                              // player to know what ION STORM does -- but a
                              // modifier's actual numbers are worth a line, and
                              // repeating the title alongside the tile is not.
                              if (metadata.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Text(
                                  metadata.first.description,
                                  key: const ValueKey(
                                    'briefing-modifier-effect',
                                  ),
                                  style: OrionTypography.microLabel(
                                    color: uiTheme.textMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              _BriefingThreatProfile(stage: stage),
                              const SizedBox(height: 12),
                              if (largeText) ...[
                                medalCriteria[0],
                                const SizedBox(height: 8),
                                medalCriteria[1],
                              ] else
                                Row(
                                  children: [
                                    Expanded(child: medalCriteria[0]),
                                    const SizedBox(width: 8),
                                    Expanded(child: medalCriteria[1]),
                                  ],
                                ),
                              if (metadata.length > 1) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'CONDITIONS',
                                  style: OrionTypography.microLabel(
                                    size: 11,
                                    color: uiTheme.systemCyan,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                for (final entry in metadata.skip(1)) ...[
                                  _BriefingIntelRow(
                                    icon: Icons.radar_rounded,
                                    color: uiTheme.systemCyan,
                                    title: entry.title,
                                    detail: entry.description,
                                  ),
                                  const SizedBox(height: 7),
                                ],
                              ],
                              const SizedBox(height: 9),
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
                                  icon: medalIcon(result.medal),
                                  color: medalColor(uiTheme, result.medal),
                                  title: 'BEST RESULT',
                                  detail:
                                      'Best: ${result.medal.label} • '
                                      '${result.bestBaseHealth} base health',
                                ),
                                const SizedBox(height: 7),
                                _BriefingIntelRow(
                                  icon: Icons.all_inclusive_rounded,
                                  color: uiTheme.systemViolet,
                                  title: 'ENDLESS',
                                  detail: widget.endlessBest == null
                                      ? 'No endless run yet'
                                      : 'Endless best: ${widget.endlessBest} ${widget.endlessBest == 1 ? 'wave' : 'waves'}',
                                ),
                                const SizedBox(height: 7),
                              ],
                              // A stage's blueprint module is knowable before
                              // deploying: locked stages tease the module name
                              // and exact effect; the committed `result` is the
                              // first-clear signal that flips the row to
                              // Recovered.
                              if (stage.blueprint case final blueprint?) ...[
                                _BriefingIntelRow(
                                  icon: Icons.memory_rounded,
                                  color: uiTheme.systemViolet,
                                  title: 'BLUEPRINT',
                                  detail: _briefingBlueprintLabel(
                                    runModuleDefinition(blueprint),
                                    recovered: result != null,
                                  ),
                                ),
                                const SizedBox(height: 7),
                              ],
                              // HPA-923 task 6 (artboard 14): the Scrip
                              // projection closes the intel block ahead of the
                              // squad editor. It quotes only committed facts —
                              // the Clear-medal floor and the medal
                              // multipliers — never a payout for a medal the
                              // run has not earned yet.
                              if (stage.firstClearScrip > 0 ||
                                  stage.replayScrip > 0)
                                _BriefingScripRewards(
                                  key: const ValueKey('briefing-scrip-reward'),
                                  stage: stage,
                                  claimed: result != null,
                                  horizontal: largeText,
                                ),
                              const SizedBox(height: 9),
                              _BriefingSquad(
                                key: _squadSectionKey,
                                draft: _draft,
                                ownedLevels: widget.ownedLevels,
                                pickerOpen: _pickerOpen,
                                enabled: !_launching,
                                feedback: _editFeedback,
                                onTogglePicker: _togglePicker,
                                onToggleMember: _toggleMember,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    12,
                    14,
                    24 +
                        math.max(
                          MediaQuery.viewPaddingOf(context).bottom,
                          MediaQuery.viewInsetsOf(context).bottom,
                        ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_launching || _launchFailed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _launching
                                ? 'Saving squad…'
                                : 'Could not save squad changes — tap a '
                                      'launch action to retry.',
                            key: const ValueKey('briefing-launch-status'),
                            textAlign: TextAlign.center,
                            style: OrionTypography.microLabel(
                              color: _launching
                                  ? uiTheme.textMuted
                                  : uiTheme.warningOrange,
                            ),
                          ),
                        ),
                      if (result == null)
                        _BriefingLaunchAction(
                          label: 'Start Mission',
                          kicker: 'DEPLOY',
                          accent: accent,
                          icon: Icons.play_arrow_rounded,
                          onPressed: _launchEnabled
                              ? () => _launch(RunMode.mission)
                              : null,
                        )
                      else
                        _BriefingReplayActions(
                          accent: accent,
                          enabled: _launchEnabled,
                          onLaunch: _launch,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 14,
              child: OrionSurface(
                role: OrionSurfaceRole.floating,
                padding: EdgeInsets.zero,
                radius: 14,
                child: IconButton(
                  tooltip: 'Dismiss',
                  onPressed: _launching ? null : _dismiss,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: uiTheme.systemCyan,
                  ),
                ),
              ),
            ),
            // Last so the shared, hit-transparent callout sits above the
            // sheet chrome; only its own Got it row intercepts taps.
            if (stage.modifiers.isNotEmpty && widget.modifierTip != null)
              Positioned.fill(
                child: ContextualTipCallout(
                  tip: ContextualTip.stageModifier,
                  anchorKey: widget.modifierTip!.anchorKey,
                  onDone: widget.modifierTip!.onDone,
                  preferAbove: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Centred stage identity: sector eyebrow and display-scale name.
///
/// The artboard treats the stage name as the sheet's hero rather than a
/// chrome title, so this is the one place [OrionTitle] is asked for a display
/// size. It renders the caps the artboard sets while keeping the real copy as
/// the semantics label.
class _BriefingIdentity extends StatelessWidget {
  const _BriefingIdentity({
    required this.stage,
    required this.accent,
    required this.badgeLabel,
  });

  final StageDefinition stage;
  final Color accent;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final sector = OrionCampaign.stages.indexWhere((s) => s.id == stage.id) + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wrap, not a Row: at 3x text scale the eyebrow and the badge no
        // longer fit side by side, and reflowing to a second line keeps both
        // readable where a Row would overflow.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (sector > 0)
              OrionText.micro(
                'SECTOR ${sector.toString().padLeft(2, '0')}',
                color: accent,
                size: 11,
              ),
            _BriefingBadge(label: badgeLabel, color: accent),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: OrionTitle(
            stage.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            color: uiTheme.textPrimary,
            size: 30,
          ),
        ),
      ],
    );
  }
}

/// What the run is actually made of, counted off [StageDefinition.waves].
///
/// Every figure here is derived from committed wave data — the artboard's
/// threat panel also shows a per-objective row, but this game has no leak or
/// tower-cap objective to report, so those are omitted rather than mocked.
class _BriefingThreatProfile extends StatelessWidget {
  const _BriefingThreatProfile({required this.stage});

  final StageDefinition stage;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final threat = _StageThreat.of(stage);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final figures = [
      _ThreatFigure(
        art: OrionArt.previewGroup(
          WavePreviewGroup(
            enemyCount: threat.enemies,
            label: 'Drones',
            traits: const {},
          ),
        ),
        value: '${threat.enemies}',
        label: 'HOSTILES',
        color: uiTheme.textPrimary,
        horizontal: largeText,
      ),
      _ThreatFigure(
        art: OrionArt.trait(EnemyTrait.armored)!,
        value: '${threat.armored}',
        label: 'ARMORED',
        color: threat.armored > 0 ? uiTheme.warningOrange : uiTheme.textMuted,
        horizontal: largeText,
      ),
      _ThreatFigure(
        art: OrionArt.trait(EnemyTrait.shielded)!,
        value: '${threat.shielded}',
        label: 'SHIELDED',
        color: threat.shielded > 0 ? uiTheme.systemViolet : uiTheme.textMuted,
        horizontal: largeText,
      ),
    ];

    return OrionSurface(
      role: OrionSurfaceRole.card,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 4, height: 12, color: uiTheme.dangerRed),
              const SizedBox(width: 7),
              Expanded(
                child: OrionText.micro(
                  'THREAT PROFILE',
                  color: uiTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (largeText)
            Column(
              children: [
                for (final (index, figure) in figures.indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  figure,
                ],
              ],
            )
          else
            Row(
              children: [for (final figure in figures) Expanded(child: figure)],
            ),
        ],
      ),
    );
  }
}

/// One numeral over its caps label, sized for a three-across row.
class _ThreatFigure extends StatelessWidget {
  const _ThreatFigure({
    required this.value,
    required this.label,
    required this.color,
    required this.art,
    this.horizontal = false,
  });

  final OrionArtDescriptor art;
  final String value;
  final String label;
  final Color color;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    if (horizontal) {
      return Row(
        children: [
          OrionAtlasSprite(art: art, size: const Size.square(46)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(color: uiTheme.textMuted),
                ),
                Text(
                  value,
                  style: OrionTypography.readout(size: 14, color: color),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrionAtlasSprite(art: art, size: const Size.square(46)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: OrionTypography.readout(size: 14, color: color),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OrionTypography.microLabel(color: uiTheme.textMuted),
        ),
      ],
    );
  }
}

/// Enemy totals for a whole stage, summed across every wave group.
class _StageThreat {
  const _StageThreat({
    required this.enemies,
    required this.armored,
    required this.shielded,
  });

  factory _StageThreat.of(StageDefinition stage) {
    var enemies = 0;
    var armored = 0;
    var shielded = 0;
    for (final wave in stage.waves) {
      for (final group in wave.groups) {
        final stats = group.enemyStats;
        enemies += group.enemyCount;
        if (stats.armorReduction > 0) {
          armored += group.enemyCount;
        }
        if (stats.shieldHealth > 0) {
          shielded += group.enemyCount;
        }
      }
    }
    return _StageThreat(enemies: enemies, armored: armored, shielded: shielded);
  }

  final int enemies;
  final int armored;
  final int shielded;
}

TextStyle _briefingLaunchLabelStyle(Color color) => OrionTypography.microLabel(
  color: color,
  size: 13,
).copyWith(letterSpacing: 3.6, shadows: const []);

class _BriefingReplayActions extends StatelessWidget {
  const _BriefingReplayActions({
    required this.accent,
    required this.enabled,
    required this.onLaunch,
  });

  final Color accent;
  final bool enabled;
  final Future<void> Function(RunMode mode) onLaunch;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final uiTheme = OrionUiTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final label = TextPainter(
          text: TextSpan(
            text: 'ENDLESS',
            style: _briefingLaunchLabelStyle(uiTheme.voidBlack),
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final actionChromeWidth = 28 + (IconTheme.of(context).size ?? 24) + 10;
        final stackActions =
            scaler.scale(13) > 13 * 1.15 &&
            (constraints.maxWidth - 8) / 2 < label.width + actionChromeWidth;
        label.dispose();

        final replay = _BriefingLaunchAction(
          label: 'Replay Mission',
          kicker: 'REPLAY',
          accent: accent,
          icon: Icons.replay_rounded,
          compactVertical: stackActions,
          onPressed: enabled ? () => onLaunch(RunMode.mission) : null,
        );
        final endless = _BriefingLaunchAction(
          label: 'Endless',
          kicker: 'ENDLESS',
          accent: accent,
          icon: Icons.all_inclusive_rounded,
          compactVertical: stackActions,
          onPressed: enabled ? () => onLaunch(RunMode.endless) : null,
        );
        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [replay, const SizedBox(height: 8), endless],
          );
        }
        return Row(
          children: [
            Expanded(child: replay),
            const SizedBox(width: 8),
            Expanded(child: endless),
          ],
        );
      },
    );
  }
}

/// A solid, filled launch action on the briefing sheet (such as Launch,
/// Replay, or Endless). A null [onPressed] dims the action and removes its
/// tap — used while a squad save is in flight or the draft is empty.
class _BriefingLaunchAction extends StatelessWidget {
  const _BriefingLaunchAction({
    required this.label,
    required this.kicker,
    required this.accent,
    required this.icon,
    required this.onPressed,
    this.compactVertical = false,
  });

  final String label;
  final String kicker;
  final Color accent;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool compactVertical;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        enabled: onPressed != null,
        child: Opacity(
          opacity: onPressed == null ? 0.45 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: orionBriefingDeployFill,
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 24),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(18),
                splashColor: uiTheme.voidBlack.withValues(alpha: 0.18),
                highlightColor: uiTheme.voidBlack.withValues(alpha: 0.10),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: compactVertical ? 12 : 22,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: uiTheme.voidBlack),
                      const SizedBox(width: 10),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          // On a filled accent the label must be the dark ink,
                          // which microLabel's muted-only rule cannot express.
                          child: ExcludeSemantics(
                            child: Text(
                              kicker,
                              style: _briefingLaunchLabelStyle(
                                uiTheme.voidBlack,
                              ),
                            ),
                          ),
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
    );
  }
}

/// Full-bleed wide key-art band with a scrim melting into the sheet body.
class _BriefingHero extends StatelessWidget {
  const _BriefingHero({required this.stage, required this.scrimColor});

  final StageDefinition stage;
  final Color scrimColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 640,
              height: 400,
              child: OrionAtlasSprite(
                art: OrionArt.stage(
                  stage,
                  crop: OrionStageArtCrop.briefingWide,
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scrimColor.withValues(alpha: 0.25),
                scrimColor.withValues(alpha: 0),
                scrimColor,
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// One tile in artboard 1b's fact row: a glyph, a figure, a caption.
///
/// [color] carries the tile's role and tints the glyph. It used to be passed
/// by every caller and read by none — the figure was hard-coded to
/// textPrimary, so START arrived as creditGold and rendered white like the
/// rest. [valueColor] now says explicitly when the figure takes the role
/// colour too, which the artboard does only for credits.
class _BriefingStatTile extends StatelessWidget {
  const _BriefingStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.valueColor,
    this.horizontal = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color? valueColor;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final tile = OrionSurface(
      role: OrionSurfaceRole.card,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: horizontal
          ? Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrionTypography.microLabel(color: uiTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      value,
                      style: OrionTypography.readout(
                        color: valueColor ?? uiTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, color: color, size: 17),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: OrionTypography.readout(
                      color: valueColor ?? uiTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(color: uiTheme.textMuted),
                ),
              ],
            ),
    );
    return tile;
  }
}

/// Width of [data] laid out in [style] under the ambient text scaler — the
/// same real-font-metrics measurement Camp's SQUAD pill uses, applied to the
/// reward labels so the column count follows what actually fits.
double _measureLabel(BuildContext context, String data, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: data, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The SCRIP REWARD projection (HPA-923 task 6, artboard 14): the once-only
/// first-clear total at the Clear-medal floor beside the standing replay
/// base and the top-medal multiplier on the variable component.
///
/// No Silver/Gold payout is quoted — the run's medal is unknowable until the
/// report, so the only honest figures are the floor (what Clear always pays)
/// and the percentages. Stage one's first clear additionally states its
/// ten-flare guarantee in text, the onboarding promise the economy tuned
/// `firstClearScrip` to honour.
class _BriefingScripRewards extends StatelessWidget {
  const _BriefingScripRewards({
    super.key,
    required this.stage,
    required this.claimed,
    required this.horizontal,
  });

  final StageDefinition stage;

  /// True once a committed result exists — the first-clear bonus was paid,
  /// so that tile reads CLAIMED and only the replay base projects a payout.
  final bool claimed;

  /// Layout toggle shared with the fact tiles: above 1.5x text scale each
  /// chip stretches to a full-width label/value row.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // Both figures come from the same pure rule the save transaction pays:
    // Clear medal is the floor — every earned medal pays at least this.
    final firstClear = StageScripRules.award(
      stage,
      StageMedal.clear,
      firstClear: true,
    );
    final replay = StageScripRules.award(
      stage,
      StageMedal.clear,
      firstClear: false,
    );
    const labels = ['FIRST CLEAR', 'EVERY REPLAY', 'GOLD MEDAL'];
    List<_BriefingScripTile> tilesFor(bool horizontal) => [
      _BriefingScripTile(
        label: labels[0],
        icon: Icons.check_circle_rounded,
        value: claimed ? 'CLAIMED' : grouped(firstClear),
        color: uiTheme.naniteGreen,
        valueColor: uiTheme.creditGold,
        horizontal: horizontal,
      ),
      _BriefingScripTile(
        label: labels[1],
        icon: Icons.payments_rounded,
        value: grouped(replay),
        color: uiTheme.creditGold,
        valueColor: uiTheme.creditGold,
        horizontal: horizontal,
      ),
      _BriefingScripTile(
        label: labels[2],
        icon: medalIcon(StageMedal.gold),
        value: '+${GameBalance.scripMedalPercentGold - 100}%',
        color: uiTheme.creditGold,
        valueColor: uiTheme.creditGold,
        horizontal: horizontal,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: uiTheme.creditGold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'SCRIP REWARD',
                style: OrionTypography.microLabel(
                  size: 11,
                  color: uiTheme.creditGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        LayoutBuilder(
          builder: (context, constraints) {
            // Three columns only while every label fits at its real
            // measured width — the same honesty the Camp SQUAD pill uses.
            // 'FIRST CLEAR' already overflows the ~74px a 320px tile
            // leaves after padding at 1x, so compact widths and large
            // text stack the chips as full-width label/value rows instead
            // of ellipsizing.
            final labelStyle = OrionTypography.microLabel(
              color: uiTheme.textMuted,
            );
            final widestLabel = labels
                .map((label) => _measureLabel(context, label, labelStyle))
                .reduce(math.max);
            const columns = 3;
            const gap = 8.0;
            // A tile's real text inset is its 9px horizontal padding plus
            // OrionSurface's 1.5px border on each side — 21px, not 18.
            // Using only the padding picked three columns at widths where
            // the widest label still ellipsized inside the border.
            const tileTextInset = 18.0 + 3.0;
            final columnTextWidth =
                (constraints.maxWidth - (columns - 1) * gap) / columns -
                tileTextInset;
            final fullWidth = horizontal || widestLabel > columnTextWidth;
            // In a full-width row the label owns flex 3 of five after the
            // same inset, the 20px icon, a 10px icon gap and an 8px value
            // gap; a label wider than that share ellipsizes, so it drops
            // to the label-above-figure placement that grants the full
            // tile width (e.g. EVERY REPLAY at 3-4x text).
            final rowLabelShare =
                (constraints.maxWidth - tileTextInset - 20 - 10 - gap) * 3 / 5;
            final tiles = tilesFor(fullWidth && widestLabel <= rowLabelShare);
            if (fullWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, tile) in tiles.indexed) ...[
                    if (index > 0) const SizedBox(height: 8),
                    tile,
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (final (index, tile) in tiles.indexed) ...[
                  if (index > 0) const SizedBox(width: gap),
                  Expanded(child: tile),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'The run\u2019s medal lifts the variable award — '
          'Silver +${GameBalance.scripMedalPercentSilver - 100}%, '
          'Gold +${GameBalance.scripMedalPercentGold - 100}%.',
          style: OrionTypography.microLabel(color: uiTheme.textMuted),
        ),
        if (!claimed && stage.id == OrionCampaign.stageOne.id) ...[
          const SizedBox(height: 4),
          Text(
            'First clear pays for at least '
            '${firstClear ~/ GameBalance.flareCost} Signal Flares.',
            style: OrionTypography.microLabel(color: uiTheme.creditGold),
          ),
        ],
      ],
    );
  }
}

/// One SCRIP REWARD chip: label on top, icon plus grouped figure beneath —
/// the artboard's tile order, inverted from [_BriefingStatTile]'s
/// figure-over-label so the reward reads as a labelled payout.
class _BriefingScripTile extends StatelessWidget {
  const _BriefingScripTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
    required this.valueColor,
    required this.horizontal,
  });

  final String label;
  final IconData icon;
  final String value;
  final Color color;
  final Color valueColor;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final figure = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: OrionTypography.readout(color: valueColor),
            ),
          ),
        ),
      ],
    );
    return OrionSurface(
      role: OrionSurfaceRole.card,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: horizontal
          ? Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrionTypography.microLabel(color: uiTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: Align(alignment: Alignment.centerRight, child: figure),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(color: uiTheme.textMuted),
                ),
                const SizedBox(height: 4),
                figure,
              ],
            ),
    );
  }
}

/// The fourth tile in artboard 1b's fact row.
///
/// Deliberately not a [_BriefingStatTile] with a colour override: the
/// artboard's modifier tile has no figure. Its name *is* the value, set at
/// label scale over two lines and ringed in warning orange so it reads as the
/// odd one out — a modifier title like "Standard Conditions" would be
/// unreadable shrunk into a numeral slot.
class _BriefingModifierTile extends StatelessWidget {
  const _BriefingModifierTile({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: uiTheme.warningOrange, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.bolt_rounded, color: uiTheme.warningOrange, size: 17),
            const SizedBox(height: 3),
            // OrionTitle's pattern rather than a bare toUpperCase(): caps
            // for display, the real copy kept as the semantics label, so a
            // screen reader announces "Standard Conditions" instead of
            // spelling out a shout -- and finders still match real copy.
            Semantics(
              label: title,
              child: ExcludeSemantics(
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: uiTheme.warningOrange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'MODIFIER',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OrionTypography.microLabel(color: uiTheme.textMuted),
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
        child: Text(label, style: OrionTypography.microLabel(color: color)),
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
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: OrionTypography.microLabel(size: 11, color: color)),
        const SizedBox(height: 2),
        Text(
          detail,
          style: OrionTypography.microLabel(size: 10, color: uiTheme.textMuted),
        ),
      ],
    );
    return OrionSurface(
      role: OrionSurfaceRole.card,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: MediaQuery.textScalerOf(context).scale(1) > 3
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(height: 6),
                text,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(width: 9),
                Expanded(child: text),
              ],
            ),
    );
  }
}

/// One compact row serves locked and recovered states: the module name plus
/// its exact effect, with the committed-clear signal flipping the status
/// prefix. Mirrors the Mission Report's `Blueprint recovered: <name>` copy.
String _briefingBlueprintLabel(
  RunModuleDefinition module, {
  required bool recovered,
}) =>
    '${recovered ? 'Blueprint recovered' : 'Blueprint locked'}: '
    '${module.title} • ${module.effectText}';

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

/// The YOUR SQUAD briefing section (artboard 14): the committed-seeded draft
/// as ordered chibi tokens, an EDIT affordance opening the owned-member
/// picker, and a count against the six-member cap.
///
/// Every tap mutates only the route-local draft — the sheet owns all draft
/// state, so this section is pure presentation.
class _BriefingSquad extends StatelessWidget {
  const _BriefingSquad({
    super.key,
    required this.draft,
    required this.ownedLevels,
    required this.pickerOpen,
    required this.enabled,
    required this.feedback,
    required this.onTogglePicker,
    required this.onToggleMember,
  });

  /// The local draft in deploy order — token order is the launch order.
  final List<Character> draft;

  /// Every member the picker may offer, with its persistent level.
  final Map<Character, int> ownedLevels;

  final bool pickerOpen;

  /// False while a launch save is in flight — tokens and picker stay mounted
  /// (so the draft reads identically on retry) but stop answering taps.
  final bool enabled;

  /// Inline edit feedback such as the six-member cap message.
  final String? feedback;

  final VoidCallback onTogglePicker;
  final ValueChanged<Character> onToggleMember;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    // Picker order follows the Camp roster's character order, not the draft.
    final owned = [
      for (final member in Character.values)
        if (ownedLevels.containsKey(member)) member,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'YOUR SQUAD',
                style: OrionTypography.microLabel(
                  size: 11,
                  color: uiTheme.systemCyan,
                ),
              ),
            ),
            Text(
              '${draft.length} / ${GameBalance.squadMaxSize}',
              style: OrionTypography.microLabel(
                size: 10,
                color: uiTheme.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              key: const ValueKey('briefing-squad-edit'),
              onTap: enabled ? onTogglePicker : null,
              borderRadius: BorderRadius.circular(8),
              // The ink region is the hit target: keep it at the 48px floor
              // in both dimensions — EDIT's real-font width is ~44px alone.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      pickerOpen ? 'DONE' : 'EDIT',
                      style: OrionTypography.microLabel(
                        size: 11,
                        color: enabled ? uiTheme.systemCyan : uiTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (draft.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Select at least one squad member to deploy.',
              style: OrionTypography.microLabel(
                size: 10,
                color: uiTheme.warningOrange,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, member) in draft.indexed)
                _BriefingSquadToken(
                  key: ValueKey('briefing-squad-token-${member.name}'),
                  member: member,
                  level: ownedLevels[member] ?? 1,
                  position: index + 1,
                  onTap: enabled ? () => onToggleMember(member) : null,
                ),
            ],
          ),
        if (pickerOpen) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in owned)
                _BriefingSquadPick(
                  key: ValueKey('briefing-squad-pick-${member.name}'),
                  member: member,
                  level: ownedLevels[member]!,
                  selected: draft.contains(member),
                  onTap: enabled ? () => onToggleMember(member) : null,
                ),
            ],
          ),
        ],
        if (feedback != null) ...[
          const SizedBox(height: 6),
          Text(
            feedback!,
            style: OrionTypography.microLabel(
              size: 10,
              color: uiTheme.warningOrange,
            ),
          ),
        ],
      ],
    );
  }
}

/// One ordered squad token: the member's chibi portrait, name, and level.
/// Tapping removes the member from the draft — removal is a draft edit, so
/// it stays local until launch.
class _BriefingSquadToken extends StatelessWidget {
  const _BriefingSquadToken({
    super.key,
    required this.member,
    required this.level,
    required this.position,
    required this.onTap,
  });

  final Character member;
  final int level;

  /// 1-based deploy position shown as the order badge.
  final int position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      button: true,
      label:
          'Squad member $position: ${member.displayName}, level $level. '
          'Activate to remove.',
      child: OrionSurface(
        role: OrionSurfaceRole.card,
        // The padding sits inside the InkWell so the whole card is the hit
        // target (48px floor), not just the 30px content row.
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: OrionAtlasSprite(
                            art: OrionArt.characterChibi(member),
                            size: const Size.square(30),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: uiTheme.voidBlack.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Text(
                                '$position',
                                style: OrionTypography.microLabel(
                                  size: 10,
                                  color: uiTheme.systemCyan,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.displayName,
                        style: OrionTypography.readout(
                          size: 10,
                          color: uiTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Lv $level',
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: onTap == null ? uiTheme.textMuted : uiTheme.systemCyan,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One picker chip: offered owned member with selected checkmark state.
class _BriefingSquadPick extends StatelessWidget {
  const _BriefingSquadPick({
    super.key,
    required this.member,
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final Character member;
  final int level;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${member.displayName}, level $level'
          '${selected ? ', in squad' : ''}',
      child: OrionSurface(
        role: OrionSurfaceRole.card,
        // The padding sits inside the InkWell so the whole card is the hit
        // target (48px floor), not just the 30px content row.
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: selected ? 1 : 0.55,
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: OrionAtlasSprite(
                        art: OrionArt.characterChibi(member),
                        size: const Size.square(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.displayName,
                        style: selected
                            ? OrionTypography.readout(
                                size: 10,
                                color: uiTheme.textPrimary,
                              )
                            : OrionTypography.microLabel(
                                size: 10,
                                color: uiTheme.textMuted,
                              ),
                      ),
                      Text(
                        'Lv $level',
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 13,
                  color: selected ? uiTheme.systemCyan : uiTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
