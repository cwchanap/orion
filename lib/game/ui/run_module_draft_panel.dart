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
    this.beneficiaries = const {},
    this.guideAnchorKey,
  });

  final RunModuleOffer offer;
  final ValueChanged<RunModuleId> onSelected;

  /// Placed towers each offered module would affect right now.
  final Map<RunModuleId, int> beneficiaries;

  /// Optional first-mission guide anchor wrapped around the draft frame;
  /// anchor keys wrap — `run-module-draft-frame` stays put.
  final Key? guideAnchorKey;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final frame = OrionSurface(
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
              beneficiaryCount: beneficiaries[id] ?? 0,
              onPressed: () => onSelected(id),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
    return Material(
      color: uiTheme.voidBlack.withValues(alpha: 0.92),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          // First-mission guide anchor wraps the frame; the ValueKey stays
          // the regression handle (anchors wrap, never replace).
          child: guideAnchorKey == null
              ? frame
              : KeyedSubtree(key: guideAnchorKey, child: frame),
        ),
      ),
    );
  }
}

/// One line of current-run context for a draft card. Economy modules return
/// null because their effect text already states the payoff directly.
String? _beneficiaryContext(RunModuleDefinition definition, int count) {
  if (!definition.affectsTowerStats) return null;
  final noun = count == 1 ? 'tower' : 'towers';
  if (definition.tower == null) {
    return count == 0
        ? 'Affects every tower you build'
        : 'Affects your $count placed $noun';
  }
  final type = definition.affinityLabel;
  return count == 0
      ? 'Benefits $type towers you build later'
      : 'Affects your $count placed $type $noun';
}

class _RunModuleCard extends StatelessWidget {
  const _RunModuleCard({
    required this.definition,
    required this.beneficiaryCount,
    required this.onPressed,
  });

  final RunModuleDefinition definition;
  final int beneficiaryCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final runContext = _beneficiaryContext(definition, beneficiaryCount);
    return Semantics(
      button: true,
      enabled: true,
      label:
          '${definition.title}. ${definition.effectText} '
          'Affinity: ${definition.affinityLabel}'
          '${runContext == null ? '' : '. $runContext'}',
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
                      definition.affinityLabel,
                      style: OrionTypography.microLabel(
                        color: uiTheme.systemCyan,
                      ),
                    ),
                    if (runContext != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        runContext,
                        style: OrionTypography.microLabel(
                          size: 9,
                          color: uiTheme.textMuted,
                        ),
                      ),
                    ],
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
