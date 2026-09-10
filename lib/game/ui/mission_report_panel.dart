import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import 'mission_report_content.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'run_module_draft_panel.dart';
import 'orion_ui_theme.dart';

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
        _MissionAction(
          label: 'Replay Mission',
          icon: Icons.replay,
          tonal: true,
        ),
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
/// scrim so the facts stay legible. The art is square, so it is cover-fitted
/// (never stretched) into the portrait aperture.
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
        // ponytail: square art, so any square child size cover-fits correctly;
        // recompute from the decoded image if the asset ever stops being 1:1.
        FittedBox(
          key: const ValueKey('mission-report-backdrop-art'),
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox.square(
            dimension: 640,
            child: OrionAtlasSprite(
              art: OrionArt.scene(OrionSceneArt.missionReport),
              size: const Size.square(640),
            ),
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          content.didWin ? 'Victory' : 'Mission Failed',
          textAlign: TextAlign.center,
          style: OrionTypography.microLabel(size: 11, color: accent),
        ),
        const SizedBox(height: 4),
        OrionTitle(
          content.stageName,
          textAlign: TextAlign.center,
          color: uiTheme.textPrimary,
        ),
        const SizedBox(height: 14),
        // Exactly one victory/defeat banner, selected from the real result.
        Center(
          child: OrionAtlasSprite(
            key: const ValueKey('mission-report-result-art'),
            art: OrionArt.result(result),
            size: const Size.square(208),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < result.medal.rank; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Icon(
                  Icons.workspace_premium,
                  color: _medalColor(uiTheme, result.medal),
                  semanticLabel: '${result.medal.label} medal',
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text(
          content.outcomeText,
          textAlign: TextAlign.center,
          style: OrionTypography.microLabel(size: 9, color: uiTheme.textMuted),
        ),
        if (content.didWin && content.comparisonText != null) ...[
          const SizedBox(height: 6),
          Text(
            content.comparisonText!,
            textAlign: TextAlign.center,
            style: OrionTypography.microLabel(
              size: 9,
              color: uiTheme.textMuted,
            ),
          ),
        ],
        if (content.didWin && content.saveText != null) ...[
          const SizedBox(height: 10),
          _SaveStateRow(state: content.saveState, text: content.saveText!),
        ],
        const SizedBox(height: 18),
        Text(
          content.moduleIds.isEmpty
              ? 'Salvage Modules'
              : 'Salvage Modules · ${content.moduleIds.length}',
          style: OrionTypography.microLabel(
            size: 11,
            color: uiTheme.systemCyan,
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
        if (reward != null) ...[
          const SizedBox(height: 18),
          Text(
            reward.title,
            style: OrionTypography.microLabel(
              size: 11,
              color: uiTheme.creditGold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reward.detail,
            style: OrionTypography.microLabel(
              size: 9,
              color: uiTheme.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          content.nextOpportunityText,
          style: OrionTypography.microLabel(size: 9, color: uiTheme.textMuted),
        ),
      ],
    );
  }
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
