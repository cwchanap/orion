import 'package:flutter/material.dart';

import 'mission_report_content.dart';
import 'run_module_draft_panel.dart';

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

    return Material(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.78),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ReportBody(content: content),
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
    final theme = Theme.of(context);
    final reward = content.reward;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              Icon(
                content.didWin ? Icons.emoji_events : Icons.warning_amber,
                size: 42,
                color: content.didWin
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(height: 6),
              Text(
                content.didWin ? 'Victory' : 'Mission Failed',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content.stageName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(content.outcomeText, textAlign: TextAlign.center),
        if (content.didWin && content.comparisonText != null) ...[
          const SizedBox(height: 8),
          Text(content.comparisonText!, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 18),
        Text('Salvage Modules', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (content.moduleIds.isNotEmpty)
          AcquiredRunModuleStrip(moduleIds: content.moduleIds)
        else if (content.emptyModulesText != null)
          Text(content.emptyModulesText!),
        if (content.didWin && content.saveText != null) ...[
          const SizedBox(height: 18),
          _SaveStateRow(state: content.saveState, text: content.saveText!),
        ],
        if (reward != null) ...[
          const SizedBox(height: 18),
          Text(reward.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(reward.detail),
        ],
        const SizedBox(height: 18),
        Text(content.nextOpportunityText),
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
    final icon = switch (state) {
      MissionSaveState.saving => Icons.sync,
      MissionSaveState.saved => Icons.check_circle_outline,
      MissionSaveState.failed => Icons.error_outline,
      null => Icons.info_outline,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, semanticLabel: 'Save status'),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
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
    final icon = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(action.icon),
        const SizedBox(height: 2),
        Text(
          action.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );

    final button = action.tonal
        ? IconButton.filledTonal(onPressed: action.onPressed, icon: icon)
        : IconButton.filled(onPressed: action.onPressed, icon: icon);
    return Tooltip(message: action.label, child: button);
  }
}
