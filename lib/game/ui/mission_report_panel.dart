import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../models/game_models.dart';
import 'mission_report_content.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'run_module_draft_panel.dart';
import 'orion_ui_theme.dart';
import 'orion_primary_button.dart';

/// Scene 1h mission debrief: approved backdrop art with a readability scrim,
/// one victory/defeat result banner selected through `OrionArt.result`, and
/// the real stage facts as subordinate sections over the state-dependent
/// action row.
class MissionReportPanel extends StatelessWidget {
  const MissionReportPanel({
    super.key,
    required this.content,
    this.onReplay,
    this.onReturnToMap,
    this.onRetrySave,
  });

  final MissionReportContent content;
  final VoidCallback? onReplay;
  final VoidCallback? onReturnToMap;
  final VoidCallback? onRetrySave;

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    final uiTheme = OrionUiTheme.of(context);

    return Material(
      color: uiTheme.voidBlack,
      child: Stack(
        children: [
          Positioned.fill(
            child: _ReportBackdrop(
              result: content.result,
              isEndless: content.snapshot.isEndless,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ReportBodyViewport(content: content)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (_actionsStack(context, actions, constraints)) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < actions.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 8),
                              _MissionActionButton(action: actions[index]),
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (
                            var index = 0;
                            index < actions.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _MissionActionButton(
                                action: actions[index],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_MissionAction> _actions() {
    if (!content.didWin && content.saveState == null) {
      return [
        _MissionAction(
          label: 'Retry',
          icon: Icons.restart_alt,
          onPressed: onReplay,
        ),
        _MissionAction(
          label: 'World Map',
          icon: Icons.map,
          onPressed: onReturnToMap,
          tonal: true,
        ),
      ];
    }

    final replayLabel = content.snapshot.isEndless
        ? 'Replay Endless'
        : 'Replay Mission';
    return switch (content.saveState) {
      MissionSaveState.saving || null => [
        _MissionAction(label: replayLabel, icon: Icons.replay),
        _MissionAction(label: 'World Map', icon: Icons.map, tonal: true),
      ],
      MissionSaveState.saved => [
        _MissionAction(
          label: replayLabel,
          icon: Icons.replay,
          onPressed: onReplay,
        ),
        _MissionAction(
          label: 'World Map',
          icon: Icons.map,
          onPressed: onReturnToMap,
          tonal: true,
        ),
      ],
      MissionSaveState.failed => [
        _MissionAction(
          label: 'Retry Save',
          icon: Icons.save,
          onPressed: onRetrySave,
        ),
        _MissionAction(
          label: 'World Map (Unsaved)',
          icon: Icons.map,
          onPressed: onReturnToMap,
          tonal: true,
        ),
      ],
    };
  }
}

class _ReportBodyViewport extends StatefulWidget {
  const _ReportBodyViewport({required this.content});

  final MissionReportContent content;

  @override
  State<_ReportBodyViewport> createState() => _ReportBodyViewportState();
}

class _ReportBodyViewportState extends State<_ReportBodyViewport> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: _ReportBody(content: widget.content),
    ),
  );
}

bool _actionsStack(
  BuildContext context,
  List<_MissionAction> actions,
  BoxConstraints constraints,
) {
  final share =
      (constraints.maxWidth - 8.0 * (actions.length - 1)) / actions.length;
  final style = OrionTypography.microLabel(size: 11);
  for (final action in actions) {
    for (final word in action.label.split(' ')) {
      if (_singleLineWidth(context, word, style) + 64 > share) {
        return true;
      }
    }
  }
  return false;
}

/// Approved debrief-hall scene art behind the report, dimmed by a readability
/// scrim so the facts stay legible. The supplied portrait art is cover-fitted.
class _ReportBackdrop extends StatelessWidget {
  const _ReportBackdrop({required this.result, required this.isEndless});

  final StageResult? result;
  final bool isEndless;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      key: const ValueKey('mission-report-backdrop'),
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        Image.asset(
          'assets/images/reactor_rim_ui/backdrops/mission-report-debrief.png',
          key: const ValueKey('mission-report-backdrop-art'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 360,
          child: Semantics(
            label: result == null
                ? isEndless
                      ? 'Endless run over'
                      : 'Mission failed'
                : null,
            excludeSemantics: result == null,
            child: Image.asset(
              'assets/images/${OrionArt.result(result).fileName}',
              key: const ValueKey('mission-report-result-art'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
        const DecoratedBox(
          key: ValueKey('mission-report-scrim'),
          decoration: BoxDecoration(gradient: orionReportScrim),
        ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.content});

  final MissionReportContent content;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final reward = content.reward;
    final result = content.result;

    final snapshot = content.snapshot;
    final isEndless = snapshot.isEndless;
    final outcomeColor = content.didWin
        ? uiTheme.creditGold
        : uiTheme.dangerRed;
    final outcomeSemantics = content.didWin
        ? 'Victory'
        : isEndless
        ? 'Endless Run Over'
        : 'Mission Failed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height >= 760 ? 76 : 24),
        if (content.didWin) ...[
          Center(
            child: OrionText.micro(
              'SECTOR SECURED',
              size: 11,
              color: outcomeColor,
            ),
          ),
          const SizedBox(height: 8),
        ],
        OrionTitle(
          content.stageName,
          size: 26,
          textAlign: TextAlign.center,
          color: uiTheme.textPrimary,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: _OutcomeRibbon(text: outcomeSemantics, accent: outcomeColor),
        ),
        if (result != null) ...[
          const SizedBox(height: 48),
          Semantics(
            label: '${result.medal.label} medal',
            excludeSemantics: true,
            child: _MedalCriteriaRow(medal: result.medal),
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats =
                <
                  ({
                    String label,
                    String value,
                    Color color,
                    IconData? icon,
                    OrionArtDescriptor? art,
                  })
                >[
                  (
                    label: 'HULL',
                    value:
                        '${snapshot.baseHealth}/${snapshot.startingBaseHealth}',
                    color: uiTheme.naniteGreen,
                    icon: null,
                    art: OrionArt.trait(EnemyTrait.shielded),
                  ),
                  (
                    label: 'WAVES',
                    value: snapshot.missionWaveTotal == null
                        ? '${snapshot.wavesCleared}'
                        : '${snapshot.waveNumber}/${snapshot.missionWaveTotal}',
                    color: uiTheme.textPrimary,
                    icon: Icons.radar,
                    art: null,
                  ),
                  (
                    label: 'CREDITS',
                    value: '${snapshot.gold}',
                    color: uiTheme.creditGold,
                    icon: Icons.hexagon,
                    art: null,
                  ),
                  if (!isEndless)
                    (
                      label: content.saveState == MissionSaveState.saved
                          ? 'R&D'
                          : 'PENDING',
                      value: '+${content.medalPoints}',
                      color: uiTheme.systemViolet,
                      icon: Icons.pentagon,
                      art: null,
                    ),
                ];
            final share =
                (constraints.maxWidth - 8.0 * (stats.length - 1)) /
                stats.length;
            final stacks = stats.any(
              (stat) => _statWidth(context, stat) > share,
            );
            if (stacks) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < stats.length; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    _ReportStat(
                      label: stats[index].label,
                      value: stats[index].value,
                      color: stats[index].color,
                      icon: stats[index].icon,
                      art: stats[index].art,
                    ),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ReportStat(
                      label: stats[index].label,
                      value: stats[index].value,
                      color: stats[index].color,
                      icon: stats[index].icon,
                      art: stats[index].art,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        if (content.saveText != null)
          _SaveStateRow(state: content.saveState, text: content.saveText!),
        if (content.comparisonText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              content.comparisonText!,
              style: OrionTypography.microLabel(
                size: 10,
                color: uiTheme.textMuted,
              ),
            ),
          ),
        if (content.didWin &&
            !isEndless &&
            (content.medalPoints > 0 || reward != null)) ...[
          const SizedBox(height: 14),
          _RewardsPanel(
            medalPoints: content.medalPoints,
            reward: reward,
            saveState: content.saveState,
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: OrionText.micro(
            'MISSION DETAILS',
            color: uiTheme.textMuted,
            size: 10,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                content.outcomeText,
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (content.moduleIds.isNotEmpty)
              AcquiredRunModuleStrip(moduleIds: content.moduleIds)
            else if (content.emptyModulesText != null)
              Text(
                content.emptyModulesText!,
                style: OrionTypography.microLabel(
                  size: 10,
                  color: uiTheme.textMuted,
                ),
              ),
            Text(
              content.nextOpportunityText,
              style: OrionTypography.microLabel(
                size: 10,
                color: uiTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutcomeRibbon extends StatelessWidget {
  const _OutcomeRibbon({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return ClipPath(
      clipper: const _OutcomeRibbonClipper(),
      child: Container(
        width: double.infinity,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(accent, uiTheme.textPrimary, .15)!,
              Color.lerp(accent, uiTheme.voidBlack, .25)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: uiTheme.voidBlack.withValues(alpha: .6),
              offset: const Offset(0, 4),
              blurRadius: 10,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: OrionTitle(
              text,
              size: 34,
              color: uiTheme.voidBlack,
              shadows: const [],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeRibbonClipper extends CustomClipper<Path> {
  const _OutcomeRibbonClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 18, size.height / 2)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..lineTo(18, size.height / 2)
    ..close();

  @override
  bool shouldReclip(_OutcomeRibbonClipper oldClipper) => false;
}

class _MedalCriteriaRow extends StatelessWidget {
  const _MedalCriteriaRow({required this.medal});

  final StageMedal medal;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final criteria = [
      (tier: 1, label: 'CLEARED', color: uiTheme.medalBronze),
      (
        tier: 2,
        label: '${GameBalance.silverMedalThreshold}+ HULL',
        color: uiTheme.medalSilver,
      ),
      (tier: 3, label: 'NO LEAKS', color: uiTheme.creditGold),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelStyle = OrionTypography.microLabel(size: 10);
        final needed = criteria.fold<double>(
          0,
          (width, criterion) =>
              width +
              math.max(
                70,
                _singleLineWidth(context, criterion.label, labelStyle),
              ),
        );
        if (needed > constraints.maxWidth) {
          return Column(
            children: [
              for (var index = 0; index < criteria.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                _MedalCriterion(
                  label: criteria[index].label,
                  tier: criteria[index].tier,
                  earned: medal.rank >= criteria[index].tier,
                  color: criteria[index].color,
                ),
              ],
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final criterion in criteria)
              _MedalCriterion(
                label: criterion.label,
                tier: criterion.tier,
                earned: medal.rank >= criterion.tier,
                color: criterion.color,
              ),
          ],
        );
      },
    );
  }
}

class _MedalCriterion extends StatelessWidget {
  const _MedalCriterion({
    required this.label,
    required this.tier,
    required this.earned,
    required this.color,
  });

  final String label;
  final int tier;
  final bool earned;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: earned ? null : uiTheme.hullBlack,
            gradient: earned
                ? RadialGradient(
                    center: const Alignment(-0.35, -0.35),
                    colors: [
                      Color.lerp(color, uiTheme.textPrimary, .5)!,
                      color,
                      Color.lerp(color, uiTheme.voidBlack, .25)!,
                    ],
                  )
                : null,
            border: Border.all(
              width: 3,
              color: earned ? color : uiTheme.frameSteel.withValues(alpha: .6),
            ),
            boxShadow: earned
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: .35),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: uiTheme.voidBlack.withValues(alpha: .25),
              ),
            ),
            child: Icon(
              switch (tier) {
                1 => Icons.check_rounded,
                2 => Icons.shield_rounded,
                _ => Icons.emoji_events_rounded,
              },
              size: 28,
              color: earned ? uiTheme.voidBlack : uiTheme.textDim,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: OrionTypography.microLabel(
            size: 10,
            color: earned ? color : uiTheme.textDim,
          ),
        ),
      ],
    );
  }
}

class _RewardsPanel extends StatelessWidget {
  const _RewardsPanel({
    required this.medalPoints,
    required this.reward,
    required this.saveState,
  });

  final int medalPoints;
  final MissionRewardFact? reward;
  final MissionSaveState? saveState;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final reward = this.reward;
    final pointsDetail = switch (saveState) {
      MissionSaveState.saved => 'Spend it in the R&D lab',
      MissionSaveState.failed => 'Not awarded — save failed',
      _ => 'Pending save',
    };
    return OrionSurface(
      role: OrionSurfaceRole.card,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          OrionText.micro('REWARDS', color: uiTheme.creditGold, size: 10),
          const SizedBox(height: 8),
          if (medalPoints > 0) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.hexagon_outlined,
                  color: uiTheme.systemViolet,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+$medalPoints R&D',
                        style: OrionTypography.readout(
                          size: 15,
                          color: uiTheme.systemViolet,
                        ),
                      ),
                      Text(
                        pointsDetail,
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (reward != null) ...[
            if (medalPoints > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: uiTheme.creditGold,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reward.title,
                        style: OrionTypography.microLabel(
                          size: 11,
                          color: uiTheme.creditGold,
                        ),
                      ),
                      Text(
                        reward.detail,
                        style: OrionTypography.microLabel(
                          size: 10,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.art,
  });
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final OrionArtDescriptor? art;
  @override
  Widget build(BuildContext context) => OrionSurface(
    role: OrionSurfaceRole.card,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
    child: Column(
      children: [
        if (art != null)
          OrionAtlasSprite(art: art!, size: const Size.square(24))
        else
          Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: OrionTypography.readout(size: 20, color: color),
          ),
        ),
        const SizedBox(height: 6),
        OrionText.micro(label, size: 10),
      ],
    ),
  );
}

class _SaveStateRow extends StatelessWidget {
  const _SaveStateRow({required this.state, required this.text});

  final MissionSaveState? state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stateColor = switch (state) {
      MissionSaveState.saving || null => uiTheme.systemCyan,
      MissionSaveState.saved => uiTheme.systemCyan,
      MissionSaveState.failed => uiTheme.dangerRed,
    };
    final icon = switch (state) {
      MissionSaveState.saving => Icons.sync,
      MissionSaveState.saved =>
        text == 'No result to save.'
            ? Icons.info_outline
            : Icons.check_circle_outline,
      MissionSaveState.failed => Icons.error_outline,
      null => Icons.info_outline,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: stateColor, semanticLabel: 'Save status'),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: OrionTypography.microLabel(size: 10, color: stateColor),
          ),
        ),
      ],
    );
  }
}

class _MissionAction {
  const _MissionAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.tonal = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool tonal;
}

class _MissionActionButton extends StatelessWidget {
  const _MissionActionButton({required this.action});

  final _MissionAction action;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.label,
      child: OrionPrimaryButton(
        label: action.label,
        icon: action.icon,
        onPressed: action.onPressed,
        variant: action.tonal
            ? OrionButtonVariant.primary
            : OrionButtonVariant.secondary,
        height: 54,
        // Labels are muted-only under the system sheet; the enabled state
        // reads via its accent instead of the forbidden near-white that
        // the icon above still carries.
        labelSize: 11,
      ),
    );
  }
}

double _statWidth(
  BuildContext context,
  ({
    String label,
    String value,
    Color color,
    IconData? icon,
    OrionArtDescriptor? art,
  })
  stat,
) {
  final widest = math.max(
    _singleLineWidth(
      context,
      stat.value,
      OrionTypography.readout(size: 20, color: stat.color),
    ),
    _singleLineWidth(context, stat.label, OrionTypography.microLabel(size: 10)),
  );
  return math.max(24, widest) + 8;
}

double _singleLineWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}
