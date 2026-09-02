import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'mission_collapsible.dart';
import 'mission_surface.dart';
import 'orion_ui_theme.dart';

/// Mission-only acquired-module details: a compact "Modules n" trigger that
/// expands in place to the full title/effect/affinity rows. Shares the
/// mission collapse invariant (external collapse request, list-change reset,
/// in-tree toggle) through [MissionCollapsible] — never an overlay popup.
/// The Mission Report keeps using the read-only [AcquiredRunModuleStrip].
class AcquiredRunModuleControl extends StatelessWidget {
  const AcquiredRunModuleControl({
    super.key,
    required this.moduleIds,
    required this.collapseRequested,
  });

  final List<RunModuleId> moduleIds;
  final bool collapseRequested;

  @override
  Widget build(BuildContext context) {
    if (moduleIds.isEmpty) return const SizedBox.shrink();
    return MissionCollapsible(
      collapseRequested: collapseRequested,
      resetToken: Object.hashAll(moduleIds),
      collapsedBuilder: _buildCollapsed,
      expandedBuilder: _buildExpanded,
    );
  }

  Widget _buildCollapsed(BuildContext context, VoidCallback toggle) {
    final uiTheme = OrionUiTheme.of(context);
    final foreground = collapseRequested
        ? uiTheme.textMuted
        : uiTheme.textPrimary;
    return Semantics(
      key: const ValueKey('acquired-modules-collapsed'),
      container: true,
      button: true,
      enabled: !collapseRequested,
      label: 'Acquired modules: ${moduleIds.length}',
      onTap: collapseRequested ? null : toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: collapseRequested ? null : toggle,
        child: MissionSurface(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          radius: 12,
          emphasized: !collapseRequested,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: Text(
                'Modules ${moduleIds.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, VoidCallback toggle) {
    return Tooltip(
      message: 'Collapse acquired modules',
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: Semantics(
          button: true,
          label: 'Collapse acquired modules',
          onTap: toggle,
          child: ConstrainedBox(
            key: const ValueKey('acquired-modules-expanded'),
            constraints: BoxConstraints(
              maxWidth: 212,
              maxHeight: (MediaQuery.sizeOf(context).height - 24).clamp(
                0,
                double.infinity,
              ),
            ),
            child: MissionSurface(
              padding: const EdgeInsets.all(8),
              radius: 12,
              emphasized: true,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < moduleIds.length; index++) ...[
                      _AcquiredModuleRow(
                        definition: runModuleDefinition(moduleIds[index]),
                      ),
                      if (index < moduleIds.length - 1)
                        const SizedBox(height: 8),
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

class _AcquiredModuleRow extends StatelessWidget {
  const _AcquiredModuleRow({required this.definition});

  final RunModuleDefinition definition;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          definition.title,
          style: textTheme.titleSmall?.copyWith(
            color: uiTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          definition.effectText,
          style: textTheme.bodySmall?.copyWith(color: uiTheme.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          definition.affinity.label,
          style: textTheme.labelSmall?.copyWith(
            color: uiTheme.systemCyan,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
