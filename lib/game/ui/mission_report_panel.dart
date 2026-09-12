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
          const Positioned.fill(child: _ReportBackdrop()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: _ReportBody(content: content),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var index = 0; index < actions.length; index++) ...[
                        if (index > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _MissionActionButton(action: actions[index]),
                        ),
                      ],
                    ],
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
    if (!content.didWin) {
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

    return switch (content.saveState) {
      MissionSaveState.saving || null => [
        _MissionAction(label: 'Replay Mission', icon: Icons.replay),
        _MissionAction(label: 'World Map', icon: Icons.map, tonal: true),
      ],
      MissionSaveState.saved => [
        _MissionAction(
          label: 'Replay Mission',
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

/// Approved debrief-hall scene art behind the report, dimmed by a readability
/// scrim so the facts stay legible. The supplied portrait art is cover-fitted.
class _ReportBackdrop extends StatelessWidget {
  const _ReportBackdrop();

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
        ),
        const DecoratedBox(
          key: ValueKey('mission-report-scrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xAA05080D),
                Color(0x3305080D),
                Color(0x4405080D),
                Color(0x8805080D),
              ],
              stops: [0, 0.28, 0.72, 1],
            ),
          ),
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
    final accent = _reportAccent(uiTheme, content);
    final result = content.result;

    final snapshot = content.snapshot;
    final medalColor = result == null
        ? uiTheme.dangerRed
        : _medalColor(uiTheme, result.medal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Semantics(
          label: content.didWin ? 'Victory' : 'Mission Failed',
          excludeSemantics: true,
          child: Center(
            child: OrionText.micro(
              content.didWin ? 'SECTOR SECURED' : 'MISSION FAILED',
              size: 11,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OrionTitle(
          content.stageName,
          size: 28,
          textAlign: TextAlign.center,
          color: uiTheme.textPrimary,
        ),
        const SizedBox(height: 60),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .85, end: 1),
            duration: orionMotionDuration(
              context,
              const Duration(milliseconds: 500),
            ),
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Semantics(
              label: result == null
                  ? 'Mission failed'
                  : '${result.medal.label} medal',
              child: ClipPath(
                clipper: _MedalClipper(),
                child: Container(
                  width: 112,
                  height: 132,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(medalColor, Colors.white, .5)!,
                        medalColor,
                        Color.lerp(medalColor, Colors.black, .35)!,
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    result == null ? '×' : '${result.medal.rank}',
                    style: OrionTypography.readout(
                      size: 44,
                      color: uiTheme.hullBlack,
                    ).copyWith(shadows: const []),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (result != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < result.medal.rank; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ClipPath(
                    clipper: _MedalClipper(),
                    child: ColoredBox(
                      color: medalColor,
                      child: const SizedBox(width: 20, height: 24),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _ReportStat(
                label: 'HULL',
                value: '${snapshot.baseHealth}/${snapshot.startingBaseHealth}',
                color: uiTheme.naniteGreen,
                art: OrionArt.trait(EnemyTrait.shielded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReportStat(
                label: 'WAVES',
                value: '${snapshot.waveNumber}/${snapshot.waveTotal}',
                color: uiTheme.textPrimary,
                icon: Icons.radar,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReportStat(
                label: 'CREDITS',
                value: '${snapshot.gold}',
                color: uiTheme.creditGold,
                icon: Icons.hexagon,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReportStat(
                label: content.saveState == MissionSaveState.saved
                    ? 'R&D'
                    : 'PENDING',
                value: '+${content.medalPoints}',
                color: uiTheme.systemViolet,
                icon: Icons.pentagon,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/images/${OrionArt.result(result).fileName}',
            key: const ValueKey('mission-report-result-art'),
            height: 120,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        const SizedBox(height: 14),
        if (content.didWin && content.saveText != null)
          _SaveStateRow(state: content.saveState, text: content.saveText!),
        if (content.comparisonText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              content.comparisonText!,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: OrionText.micro(
            'MISSION DETAILS',
            color: uiTheme.textMuted,
            size: 9,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                content.outcomeText,
                style: OrionTypography.microLabel(
                  size: 9,
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
                  size: 9,
                  color: uiTheme.textMuted,
                ),
              ),
            if (reward != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  reward.title,
                  style: OrionTypography.microLabel(
                    size: 11,
                    color: uiTheme.creditGold,
                  ),
                ),
                subtitle: Text(
                  reward.detail,
                  style: OrionTypography.microLabel(
                    size: 9,
                    color: uiTheme.textMuted,
                  ),
                ),
              ),
            Text(
              content.nextOpportunityText,
              style: OrionTypography.microLabel(
                size: 9,
                color: uiTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MedalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width / 2, 0)
    ..lineTo(s.width, s.height * .22)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height * .78)
    ..lineTo(0, s.height)
    ..lineTo(0, s.height * .22)
    ..close();
  @override
  bool shouldReclip(_MedalClipper oldClipper) => false;
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
    tier: OrionSurfaceTier.t2,
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
        OrionText.micro(label, size: 8),
      ],
    ),
  );
}

Color _medalColor(OrionUiTheme uiTheme, StageMedal medal) {
  return switch (medal) {
    StageMedal.gold => uiTheme.creditGold,
    StageMedal.silver => uiTheme.textMuted,
    StageMedal.clear => uiTheme.systemCyan,
  };
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
      MissionSaveState.saved => Icons.check_circle_outline,
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
            style: OrionTypography.microLabel(size: 9, color: stateColor),
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
    final uiTheme = OrionUiTheme.of(context);
    if (action.tonal) {
      return Tooltip(
        message: action.label,
        child: OrionPrimaryButton(
          label: action.label,
          icon: action.icon,
          onPressed: action.onPressed,
        ),
      );
    }
    final enabled = action.onPressed != null;
    final accent = enabled
        ? (action.tonal ? uiTheme.creditGold : uiTheme.systemCyan)
        : uiTheme.frameSteel;
    final foreground = enabled ? uiTheme.textPrimary : uiTheme.textMuted;
    final icon = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(action.icon, color: foreground),
        const SizedBox(height: 2),
        Text(
          action.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          // Labels are muted-only under the system sheet; the enabled state
          // reads via its accent instead of the forbidden near-white that
          // the icon above still carries.
          style: OrionTypography.microLabel(
            color: enabled ? accent : uiTheme.textMuted,
          ),
        ),
      ],
    );

    return Tooltip(
      message: action.label,
      child: OrionSurface(
        tier: enabled ? OrionSurfaceTier.t3 : OrionSurfaceTier.t2,
        padding: const EdgeInsets.all(3),
        // The inner tile sat directly inside the outer OrionSurface's
        // already-blurred fill, so its own BackdropFilter blurred a
        // backdrop that was already blurred — a second blur pass that was
        // visually almost a no-op. This DecoratedBox reproduces
        // OrionSurfaceTier.t2's exact fill, border and radius (see
        // OrionSurface.build) without paying for that blur again; padding
        // is unchanged (zero).
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  uiTheme.panelRaised.withValues(alpha: 0.66),
                  uiTheme.hullBlack.withValues(alpha: 0.76),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.fromBorderSide(
                BorderSide(color: uiTheme.frameSteel),
              ),
            ),
            child: IconButton(
              onPressed: action.onPressed,
              style: IconButton.styleFrom(
                foregroundColor: foreground,
                disabledForegroundColor: uiTheme.textMuted,
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                overlayColor: accent.withValues(alpha: enabled ? 0.16 : 0),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                minimumSize: const Size(48, 48),
              ),
              icon: icon,
            ),
          ),
        ),
      ),
    );
  }
}

Color _reportAccent(OrionUiTheme uiTheme, MissionReportContent content) {
  if (!content.didWin) return uiTheme.dangerRed;
  return switch (content.saveState) {
    MissionSaveState.saving => uiTheme.systemCyan,
    MissionSaveState.failed => uiTheme.dangerRed,
    MissionSaveState.saved || null => uiTheme.creditGold,
  };
}
