import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
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
    return Material(
      color: uiTheme.voidBlack.withValues(alpha: 0.92),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: OrionSurface(
            key: const ValueKey('run-module-draft-frame'),
            tier: OrionSurfaceTier.t3,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OrionTitle(
                  'Salvage Module ${offer.draftNumber} of ${offer.draftTotal}',
                  textAlign: TextAlign.center,
                  color: uiTheme.textPrimary,
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
    return Semantics(
      button: true,
      enabled: true,
      label:
          '${definition.title}. ${definition.effectText} '
          'Affinity: ${definition.affinity.label}',
      onTap: onPressed,
      excludeSemantics: true,
      child: OrionInnerSurface(
        tier: OrionSurfaceTier.t3,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
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
                      style: OrionTypography.microLabel(
                        size: 11,
                        color: uiTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      definition.effectText,
                      style: OrionTypography.microLabel(
                        size: 9,
                        color: uiTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      definition.affinity.label,
                      style: OrionTypography.microLabel(
                        color: uiTheme.systemCyan,
                      ),
                    ),
                  ],
                ),
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
    return OrionSurface(
      tier: OrionSurfaceTier.t2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        '${definition.title} — ${definition.effectText}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: OrionTypography.microLabel(size: 9, color: uiTheme.textMuted),
      ),
    );
  }
}
