import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/stage_definition.dart';

class WorldMapView extends StatelessWidget {
  const WorldMapView({
    super.key,
    required this.stages,
    required this.progress,
    required this.feedback,
    required this.onStageSelected,
    this.onLockedStageSelected,
    required this.onResetCampaign,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final String? feedback;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;
  final VoidCallback onResetCampaign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleared = stages
        .where((stage) => progress.isCleared(stage.id))
        .length;
    final total = stages.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Orion Sector Map',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Reset Campaign',
                  onPressed: onResetCampaign,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
            if (feedback != null) ...[
              const SizedBox(height: 8),
              Text(
                feedback!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
            if (progress.isCampaignComplete(stages)) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Campaign Complete • $cleared/$total stages cleared',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _StageMap(
                stages: stages,
                progress: progress,
                onStageSelected: onStageSelected,
                onLockedStageSelected: onLockedStageSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageMap extends StatelessWidget {
  const _StageMap({
    required this.stages,
    required this.progress,
    required this.onStageSelected,
    required this.onLockedStageSelected,
  });

  final List<StageDefinition> stages;
  final CampaignProgress progress;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (stages.isEmpty) {
              return Center(
                child: Text(
                  'No stages available',
                  style: theme.textTheme.bodyLarge,
                ),
              );
            }

            final maxColumn = stages
                .map((stage) => stage.mapColumn)
                .reduce((a, b) => a > b ? a : b);
            final maxRow = stages
                .map((stage) => stage.mapRow)
                .reduce((a, b) => a > b ? a : b);
            final nodeWidth = constraints.maxWidth < 420 ? 86.0 : 104.0;
            const nodeHeight = 92.0;
            final availableWidth = constraints.maxWidth > nodeWidth
                ? constraints.maxWidth - nodeWidth
                : 0.0;
            final availableHeight = constraints.maxHeight > nodeHeight
                ? constraints.maxHeight - nodeHeight
                : 0.0;

            return Stack(
              children: [
                for (final stage in stages)
                  Positioned(
                    left:
                        availableWidth *
                        _mapCoordinate(stage.mapColumn, maxColumn),
                    top: availableHeight * _mapCoordinate(stage.mapRow, maxRow),
                    width: nodeWidth,
                    height: nodeHeight,
                    child: _StageNode(
                      stage: stage,
                      status: progress.statusFor(stage),
                      onStageSelected: onStageSelected,
                      onLockedStageSelected: onLockedStageSelected,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({
    required this.stage,
    required this.status,
    required this.onStageSelected,
    required this.onLockedStageSelected,
  });

  final StageDefinition stage;
  final StageProgressStatus status;
  final ValueChanged<StageDefinition> onStageSelected;
  final ValueChanged<StageDefinition>? onLockedStageSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocked = status == StageProgressStatus.locked;
    final colors = _stageColors(theme.colorScheme, status);

    return Material(
      color: colors.background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isLocked
            ? () => onLockedStageSelected?.call(stage)
            : () => onStageSelected(stage),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_statusIcon(status), color: colors.foreground),
              const SizedBox(height: 5),
              Text(
                stage.mapLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _statusLabel(status),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageColors {
  const _StageColors({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

_StageColors _stageColors(ColorScheme colorScheme, StageProgressStatus status) {
  return switch (status) {
    StageProgressStatus.cleared => _StageColors(
      background: colorScheme.tertiaryContainer,
      border: colorScheme.tertiary,
      foreground: colorScheme.onTertiaryContainer,
    ),
    StageProgressStatus.unlocked => _StageColors(
      background: colorScheme.secondaryContainer,
      border: colorScheme.secondary,
      foreground: colorScheme.onSecondaryContainer,
    ),
    StageProgressStatus.locked => _StageColors(
      background: colorScheme.surface,
      border: colorScheme.outlineVariant,
      foreground: colorScheme.onSurfaceVariant,
    ),
  };
}

double _mapCoordinate(int value, int maxValue) {
  if (maxValue == 0) {
    return 0.5;
  }

  return value / maxValue;
}

IconData _statusIcon(StageProgressStatus status) {
  return switch (status) {
    StageProgressStatus.cleared => Icons.check_circle,
    StageProgressStatus.unlocked => Icons.radio_button_checked,
    StageProgressStatus.locked => Icons.lock,
  };
}

String _statusLabel(StageProgressStatus status) {
  return switch (status) {
    StageProgressStatus.cleared => 'Cleared',
    StageProgressStatus.unlocked => 'Open',
    StageProgressStatus.locked => 'Locked',
  };
}
