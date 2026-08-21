import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'command_frame.dart';
import 'orion_ui_theme.dart';

class RunModuleDraftPanel extends StatelessWidget {
  const RunModuleDraftPanel({
    super.key,
    required this.offer,
    required this.onSelected,
  });

  final RunModuleOffer offer;
  final ValueChanged<RunModuleId> onSelected;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: uiTheme.voidBlack.withValues(alpha: 0.92),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CommandFrame(
            key: const ValueKey('run-module-draft-frame'),
            padding: const EdgeInsets.all(14),
            color: uiTheme.hullBlack,
            borderColor: uiTheme.systemCyan,
            emphasized: true,
            chamfer: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Salvage Module ${offer.draftNumber} of ${offer.draftTotal}',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    color: uiTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                for (final id in offer.moduleIds) ...[
                  _RunModuleCard(
                    definition: runModuleDefinition(id),
                    onPressed: () => onSelected(id),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RunModuleCard extends StatelessWidget {
  const _RunModuleCard({required this.definition, required this.onPressed});

  final RunModuleDefinition definition;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: true,
      label:
          '${definition.title}. ${definition.effectText} '
          'Affinity: ${definition.affinity.label}',
      onTap: onPressed,
      excludeSemantics: true,
      child: CommandFrame(
        padding: EdgeInsets.zero,
        color: uiTheme.panelBlue,
        borderColor: uiTheme.systemCyanStrong,
        emphasized: true,
        chamfer: 10,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            splashColor: uiTheme.systemCyan.withValues(alpha: 0.18),
            highlightColor: uiTheme.systemCyan.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    definition.title,
                    style: textTheme.titleMedium?.copyWith(
                      color: uiTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    definition.effectText,
                    style: textTheme.bodyMedium?.copyWith(
                      color: uiTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    definition.affinity.label,
                    style: textTheme.labelMedium?.copyWith(
                      color: uiTheme.systemCyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AcquiredRunModuleStrip extends StatelessWidget {
  const AcquiredRunModuleStrip({super.key, required this.moduleIds});

  final List<RunModuleId> moduleIds;

  @override
  Widget build(BuildContext context) {
    if (moduleIds.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in moduleIds)
          _AcquiredModuleLabel(definition: runModuleDefinition(id)),
      ],
    );
  }
}

class _AcquiredModuleLabel extends StatelessWidget {
  const _AcquiredModuleLabel({required this.definition});

  final RunModuleDefinition definition;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: uiTheme.panelBlue,
      borderColor: uiTheme.frameSteel,
      chamfer: 6,
      child: Text(
        '${definition.title} — ${definition.effectText}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: uiTheme.textPrimary),
      ),
    );
  }
}
