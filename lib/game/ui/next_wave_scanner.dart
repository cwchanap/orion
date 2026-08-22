import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'command_frame.dart';
import 'orion_atlas_sprite.dart';
import 'orion_ui_theme.dart';

class NextWaveScanner extends StatefulWidget {
  const NextWaveScanner({
    super.key,
    required this.preview,
    required this.modifierTitles,
    required this.collapseRequested,
    this.onCollapsedTapIntercept,
  });

  final WavePreview preview;
  final List<String> modifierTitles;
  final bool collapseRequested;

  /// Called with the global tap position when the collapsed radar is tapped.
  /// Return true when the tap was handled elsewhere (e.g. forwarded to the
  /// board because it landed on a buildable cell) so the scanner neither
  /// expands nor plays its ink reaction.
  final bool Function(Offset globalPosition)? onCollapsedTapIntercept;

  @override
  State<NextWaveScanner> createState() => _NextWaveScannerState();
}

class _NextWaveScannerState extends State<NextWaveScanner> {
  bool _expanded = false;
  bool _hasUnreadPreview = true;
  bool _tapIntercepted = false;

  @override
  void didUpdateWidget(covariant NextWaveScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.waveNumber != widget.preview.waveNumber) {
      _expanded = false;
      _hasUnreadPreview = true;
    } else if (!oldWidget.collapseRequested && widget.collapseRequested) {
      _expanded = false;
    }
  }

  void _toggleExpanded() {
    if (widget.collapseRequested) return;
    setState(() {
      _expanded = !_expanded;
      if (_expanded) _hasUnreadPreview = false;
    });
  }

  void _handleCollapsedTapUp(TapUpDetails details) {
    _tapIntercepted =
        widget.onCollapsedTapIntercept?.call(details.globalPosition) ?? false;
  }

  void _handleCollapsedTap() {
    final intercepted = _tapIntercepted;
    _tapIntercepted = false;
    if (intercepted || widget.collapseRequested) return;
    _toggleExpanded();
  }

  @override
  Widget build(BuildContext context) {
    final duration = orionMotionDuration(
      context,
      const Duration(milliseconds: 180),
    );
    final child = _expanded && !widget.collapseRequested
        ? _buildExpanded(context)
        : _buildCollapsed(context);

    return IgnorePointer(
      ignoring: widget.collapseRequested,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        // Keep only the current child in the layout while switching. The
        // default Stack layout keeps the outgoing expanded detector hit-testable
        // for the fade duration, even after a board/tower selection requests an
        // immediate collapse.
        layoutBuilder: (currentChild, _) =>
            currentChild ?? const SizedBox.shrink(),
        child: child,
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final totalEnemyCount = widget.preview.groups.fold<int>(
      0,
      (total, group) => total + group.enemyCount,
    );
    final unreadLabel = _hasUnreadPreview
        ? 'New wave preview available. '
              'Next wave ${widget.preview.waveNumber} of ${widget.preview.waveTotal}. '
              '$totalEnemyCount enemies.'
        : 'Next wave ${widget.preview.waveNumber} of ${widget.preview.waveTotal}. '
              '$totalEnemyCount enemies.';

    return Semantics(
      key: const ValueKey('next-wave-scanner-collapsed-semantics'),
      container: true,
      button: true,
      enabled: !widget.collapseRequested,
      label: unreadLabel,
      onTap: widget.collapseRequested ? null : _toggleExpanded,
      child: Tooltip(
        message: 'Expand next-wave scanner',
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          // The gesture detector owns the full 48dp control (opaque), not just
          // the painted radar pixels: InkResponse's deferToChild behavior left
          // dead corners and border bands where a tap joined no gesture arena
          // at all — silently blocking the board cell underneath instead of
          // reaching either the scanner or, via the tap arbiter, the game.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _handleCollapsedTapUp,
            onTapCancel: () => _tapIntercepted = false,
            onTap: _handleCollapsedTap,
            child: SizedBox.square(
              key: const ValueKey('next-wave-scanner-collapsed'),
              dimension: 48,
              child: CommandFrame(
                padding: const EdgeInsets.all(3),
                color: uiTheme.hullBlack,
                borderColor: widget.collapseRequested
                    ? uiTheme.frameSteel
                    : uiTheme.systemCyan,
                emphasized: !widget.collapseRequested,
                chamfer: 12,
                child: CommandFrame(
                  padding: EdgeInsets.zero,
                  color: uiTheme.panelBlue,
                  borderColor: widget.collapseRequested
                      ? uiTheme.frameSteel
                      : uiTheme.systemCyan.withValues(alpha: 0.68),
                  chamfer: 8,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.radar,
                        color: widget.collapseRequested
                            ? uiTheme.textMuted
                            : uiTheme.systemCyan,
                        size: 27,
                      ),
                      if (_hasUnreadPreview)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: _UnreadBeacon(color: uiTheme.warningOrange),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Tooltip(
      message: 'Collapse next-wave scanner',
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleExpanded,
        child: Semantics(
          button: true,
          label: 'Collapse next-wave scanner',
          onTap: _toggleExpanded,
          child: SizedBox(
            width: 212,
            height: 168,
            child: CommandFrame(
              key: const ValueKey('next-wave-scanner-expanded'),
              padding: const EdgeInsets.all(8),
              color: uiTheme.hullBlack,
              borderColor: uiTheme.systemCyan,
              emphasized: true,
              chamfer: 10,
              child: SizedBox.expand(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: _ExpandedPreviewBody(
                    preview: widget.preview,
                    modifierTitles: widget.modifierTitles,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBeacon extends StatelessWidget {
  const _UnreadBeacon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.65), blurRadius: 5),
        ],
      ),
      child: const SizedBox.square(dimension: 7),
    );
  }
}

class _ExpandedPreviewBody extends StatelessWidget {
  const _ExpandedPreviewBody({
    required this.preview,
    required this.modifierTitles,
  });

  final WavePreview preview;
  final List<String> modifierTitles;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);
    final groupedTraits = <EnemyTrait>{
      for (final group in preview.groups) ...group.traits,
    };
    // Wave-level traits that no group row already reports above.
    final ungroupedTraits = preview.traits.difference(groupedTraits);
    final recommendationLabel = preview.recommendedTowerTypes.isEmpty
        ? 'Recommended towers: none'
        : 'Recommended towers: ${preview.recommendedTowerTypes.map((type) => type.label).join(', ')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.radar, color: uiTheme.systemCyan, size: 17),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'NEXT WAVE ${preview.waveNumber}/${preview.waveTotal}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: textScaler,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: uiTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < preview.groups.length; index++) ...[
          _PreviewGroupRow(
            key: ValueKey('preview-group-$index'),
            group: preview.groups[index],
            textScaler: textScaler,
          ),
          if (index < preview.groups.length - 1) const SizedBox(height: 5),
        ],
        if (ungroupedTraits.isNotEmpty) ...[
          const SizedBox(height: 5),
          _TraitSummary(traits: ungroupedTraits),
        ],
        if (preview.clearBonus > 0) ...[
          const SizedBox(height: 6),
          Semantics(
            container: true,
            label: 'Clear bonus ${preview.clearBonus} credits',
            child: Row(
              children: [
                Icon(Icons.stars_outlined, color: uiTheme.creditGold, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      'Clear bonus +${preview.clearBonus}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: textScaler,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: uiTheme.creditGold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (preview.recommendedTowerTypes.isNotEmpty) ...[
          const SizedBox(height: 5),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: recommendationLabel,
            child: _RecommendationRow(
              towerTypes: preview.recommendedTowerTypes,
              textScaler: textScaler,
            ),
          ),
        ],
        if (modifierTitles.isNotEmpty) ...[
          const SizedBox(height: 5),
          Semantics(
            container: true,
            label: 'Modifiers: ${modifierTitles.join(', ')}',
            child: Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                for (final title in modifierTitles)
                  _ModifierTitle(title: title, textScaler: textScaler),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TraitSummary extends StatelessWidget {
  const _TraitSummary({required this.traits});

  final Set<EnemyTrait> traits;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final trait in EnemyTrait.values)
        if (traits.contains(trait)) _traitSemanticLabel(trait),
    ];
    return Semantics(
      container: true,
      label: 'Threat traits: ${labels.join(', ')}',
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          for (final trait in EnemyTrait.values)
            if (traits.contains(trait)) _TraitBadge(trait: trait),
        ],
      ),
    );
  }
}

class _PreviewGroupRow extends StatelessWidget {
  const _PreviewGroupRow({
    super.key,
    required this.group,
    required this.textScaler,
  });

  final WavePreviewGroup group;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Semantics(
      container: true,
      label: group.label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrionAtlasSprite(
            art: OrionArt.previewGroup(group),
            size: const Size.square(30),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Semantics(
                      container: true,
                      label: '${group.enemyCount} ${group.label}',
                      child: ExcludeSemantics(
                        child: Text(
                          '${group.enemyCount}x',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: textScaler,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: uiTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: textScaler,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: uiTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (group.traits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        for (final trait in EnemyTrait.values)
                          if (group.traits.contains(trait))
                            _TraitBadge(trait: trait),
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
}

String _traitSemanticLabel(EnemyTrait trait) {
  return switch (trait) {
    EnemyTrait.armored => 'Armored trait',
    EnemyTrait.shielded => 'Shielded trait',
    EnemyTrait.swarm => 'Swarm trait',
    EnemyTrait.regen => 'Regeneration trait',
    EnemyTrait.heavy => 'Heavy trait',
  };
}

class _TraitBadge extends StatelessWidget {
  const _TraitBadge({required this.trait});

  final EnemyTrait trait;

  @override
  Widget build(BuildContext context) {
    final art = OrionArt.trait(trait);
    if (art != null) {
      return Semantics(
        image: true,
        label: art.semanticLabel,
        child: ExcludeSemantics(
          child: OrionAtlasSprite(art: art, size: const Size.square(17)),
        ),
      );
    }

    final uiTheme = OrionUiTheme.of(context);
    final (icon, label) = switch (trait) {
      EnemyTrait.swarm => (Icons.change_history, _traitSemanticLabel(trait)),
      EnemyTrait.heavy => (Icons.square, _traitSemanticLabel(trait)),
      EnemyTrait.armored ||
      EnemyTrait.shielded ||
      EnemyTrait.regen => (Icons.help_outline, _traitSemanticLabel(trait)),
    };
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Icon(icon, size: 17, color: uiTheme.warningOrange),
      ),
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  const _RecommendationRow({
    required this.towerTypes,
    required this.textScaler,
  });

  final List<TowerType> towerTypes;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    if (towerTypes.isEmpty) {
      return Text(
        'No tower recommendation',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: textScaler,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: uiTheme.textMuted),
      );
    }
    return Wrap(
      spacing: 5,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.auto_awesome, color: uiTheme.systemViolet, size: 15),
        for (final type in towerTypes)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrionAtlasSprite(
                art: OrionArt.tower(type),
                size: const Size.square(19),
              ),
              const SizedBox(width: 2),
              Text(
                type.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: textScaler,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: uiTheme.systemViolet,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ModifierTitle extends StatelessWidget {
  const _ModifierTitle({required this.title, required this.textScaler});

  final String title;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: uiTheme.panelRaised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: uiTheme.frameSteel),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textScaler: textScaler,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: uiTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
