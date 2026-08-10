import 'package:flutter/material.dart';

import '../models/game_models.dart';

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
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.scrim.withValues(alpha: 0.84),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Salvage Module ${offer.draftNumber} of ${offer.draftTotal}',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
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
    );
  }
}

class _RunModuleCard extends StatelessWidget {
  const _RunModuleCard({required this.definition, required this.onPressed});

  final RunModuleDefinition definition;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(definition.effectText),
          const SizedBox(height: 4),
          Text(
            definition.affinity.label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
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
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          '${definition.title} — ${definition.effectText}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
