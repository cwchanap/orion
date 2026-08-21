import 'package:flutter/material.dart';

import 'command_frame.dart';
import 'mission_report_content.dart';
import 'run_module_draft_panel.dart';
import 'orion_ui_theme.dart';

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
      color: uiTheme.voidBlack.withValues(alpha: 0.92),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CommandFrame(
                    key: const ValueKey('mission-report-frame'),
                    padding: const EdgeInsets.all(14),
                    color: uiTheme.hullBlack,
                    borderColor: _reportAccent(uiTheme, content),
                    emphasized: true,
                    chamfer: 14,
                    child: _ReportBody(content: content),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
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
            ],
          ),
        ),
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

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.content});

  final MissionReportContent content;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final theme = Theme.of(context);
    final reward = content.reward;
    final accent = _reportAccent(uiTheme, content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              Icon(
                content.didWin ? Icons.emoji_events : Icons.warning_amber,
                size: 42,
                color: accent,
              ),
              const SizedBox(height: 6),
              Text(
                content.didWin ? 'Victory' : 'Mission Failed',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content.stageName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: uiTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content.outcomeText,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: uiTheme.textPrimary,
          ),
        ),
        if (content.didWin && content.comparisonText != null) ...[
          const SizedBox(height: 8),
          Text(
            content.comparisonText!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: uiTheme.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Salvage Modules',
          style: theme.textTheme.titleMedium?.copyWith(
            color: uiTheme.systemCyan,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (content.moduleIds.isNotEmpty)
          AcquiredRunModuleStrip(moduleIds: content.moduleIds)
        else if (content.emptyModulesText != null)
          Text(
            content.emptyModulesText!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: uiTheme.textMuted,
            ),
          ),
        if (content.didWin && content.saveText != null) ...[
          const SizedBox(height: 18),
          _SaveStateRow(state: content.saveState, text: content.saveText!),
        ],
        if (reward != null) ...[
          const SizedBox(height: 18),
          Text(
            reward.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: uiTheme.creditGold,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reward.detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: uiTheme.textPrimary,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          content.nextOpportunityText,
          style: theme.textTheme.bodyMedium?.copyWith(color: uiTheme.textMuted),
        ),
      ],
    );
  }
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: stateColor,
              fontWeight: FontWeight.w700,
            ),
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
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return Tooltip(
      message: action.label,
      child: CommandFrame(
        padding: const EdgeInsets.all(3),
        color: uiTheme.hullBlack,
        borderColor: accent,
        emphasized: enabled,
        chamfer: 12,
        child: CommandFrame(
          padding: EdgeInsets.zero,
          color: uiTheme.panelBlue,
          borderColor: accent.withValues(alpha: enabled ? 0.68 : 0.4),
          chamfer: 8,
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
