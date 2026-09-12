import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../campaign/orion_campaign.dart';
import 'mission_surface.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';
import 'orion_primary_button.dart';

class NextWaveScanner extends StatefulWidget {
  const NextWaveScanner({
    super.key,
    required this.preview,
    required this.modifierTitles,
    required this.collapseRequested,
    this.onCollapsedTapIntercept,
    this.onExpandedChanged,
    this.onStartWave,
    this.stageId,
  });
  final String? stageId;
  final WavePreview preview;
  final List<String> modifierTitles;
  final bool collapseRequested;
  final bool Function(Offset globalPosition)? onCollapsedTapIntercept;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? onStartWave;
  @override
  State<NextWaveScanner> createState() => _NextWaveScannerState();
}

class _NextWaveScannerState extends State<NextWaveScanner> {
  static const double _radarInset = 3;
  final _overlay = OverlayPortalController();
  bool _hasUnreadPreview = true;
  bool _tapIntercepted = false;
  bool _expanded = false;

  void _toggle() {
    if (widget.collapseRequested && !_expanded) return;
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _hasUnreadPreview = false;
      _overlay.show();
    } else {
      _overlay.hide();
    }
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  void didUpdateWidget(covariant NextWaveScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.preview.waveNumber != widget.preview.waveNumber;
    if (changed) _hasUnreadPreview = true;
    if (_expanded && (changed || widget.collapseRequested)) {
      _expanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_expanded) _overlay.hide();
      });
    }
  }

  void _handleCollapsedTapUp(TapUpDetails details) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    final onRadar =
        local.dx >= _radarInset &&
        local.dy >= _radarInset &&
        local.dx <= box.size.width - _radarInset &&
        local.dy <= box.size.height - _radarInset;
    if (!onRadar) {
      _tapIntercepted =
          widget.onCollapsedTapIntercept?.call(details.globalPosition) ?? false;
    }
  }

  void _handleCollapsedTap(VoidCallback toggle) {
    final intercepted = _tapIntercepted;
    _tapIntercepted = false;
    if (!intercepted && !widget.collapseRequested) toggle();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_expanded,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _expanded) _toggle();
    },
    child: OverlayPortal(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _overlay,
      overlayChildBuilder: (context) => !_expanded
          ? const SizedBox.shrink()
          : Positioned.fill(
              child: BlockSemantics(
                child: FocusScope(
                  autofocus: true,
                  child: WaveScannerScene(
                    preview: widget.preview,
                    stageId: widget.stageId,
                    modifierTitles: widget.modifierTitles,
                    onClose: _toggle,
                    onStartWave: widget.onStartWave == null
                        ? null
                        : () {
                            _toggle();
                            widget.onStartWave!();
                          },
                  ),
                ),
              ),
            ),
      child: IgnorePointer(
        ignoring: widget.collapseRequested,
        child: _expanded
            ? const SizedBox.square(dimension: 48)
            : _buildCollapsed(context, _toggle),
      ),
    ),
  );
  Widget _buildCollapsed(BuildContext context, VoidCallback toggle) {
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
      onTap: widget.collapseRequested ? null : toggle,
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
            onTap: () => _handleCollapsedTap(toggle),
            child: SizedBox.square(
              key: const ValueKey('next-wave-scanner-collapsed'),
              dimension: 48,
              child: MissionSurface(
                padding: const EdgeInsets.all(_radarInset),
                radius: 12,
                emphasized: !widget.collapseRequested,
                // The inner tile sat directly inside the outer
                // MissionSurface's already-blurred fill, so its own
                // BackdropFilter blurred a backdrop that was already
                // blurred — a second blur pass that was visually almost a
                // no-op. This DecoratedBox reproduces OrionSurfaceTier.t2's
                // exact fill and border (see OrionSurface.build) without
                // paying for that blur again; padding and rounding are
                // unchanged.
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.fromBorderSide(
                        BorderSide(color: uiTheme.frameSteel),
                      ),
                    ),
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
      ),
    );
  }
}

class _UnreadBeacon extends StatelessWidget {
  const _UnreadBeacon({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: .65), blurRadius: 5),
      ],
    ),
    child: const SizedBox.square(dimension: 7),
  );
}

/// Same preview and start-wave callback as the HUD, presented as scene 1c.
class WaveScannerScene extends StatelessWidget {
  const WaveScannerScene({
    super.key,
    required this.preview,
    required this.modifierTitles,
    required this.onClose,
    this.onStartWave,
    this.stageId,
  });
  final String? stageId;
  final WavePreview preview;
  final List<String> modifierTitles;
  final VoidCallback onClose;
  final VoidCallback? onStartWave;

  @override
  Widget build(BuildContext context) {
    final t = OrionUiTheme.of(context);
    final largest = preview.groups.fold<int>(
      1,
      (n, g) => g.enemyCount > n ? g.enemyCount : n,
    );
    final stage = OrionCampaign.stages
        .where((s) => s.id == stageId)
        .firstOrNull;
    final forecast = stage == null || stage.waves.isEmpty
        ? preview
        : GameBalance.wavePreview(
            wave: stage.waves.last,
            waveNumber: stage.waves.length,
            waveTotal: stage.waves.length,
            unlockedTowerTypes: const [],
            effectiveClearBonus: 0,
          );
    final bosses = forecast.groups.where(
      (g) => GameBalance.bosses.any((b) => b.name == g.label),
    );
    final traits = {
      ...preview.traits,
      for (final group in preview.groups) ...group.traits,
    };
    return Material(
      key: const ValueKey('next-wave-scanner-expanded'),
      color: t.voidBlack,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/reactor_rim_ui/backdrops/command-center.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x8005080D),
                  Color(0x3305080D),
                  Color(0xCC05080D),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 24, 16, 14),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Collapse next-wave scanner',
                        autofocus: true,
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          children: [
                            OrionText.micro(
                              'INBOUND',
                              color: t.warningOrange,
                              size: 9,
                            ),
                            Semantics(
                              label:
                                  'Next wave ${preview.waveNumber}/${preview.waveTotal}',
                              excludeSemantics: true,
                              child: OrionReadout(
                                value: '${preview.waveNumber}'.padLeft(2, '0'),
                                color: t.textPrimary,
                                denominator: '${preview.waveTotal}',
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OrionSurface(
                          tier: OrionSurfaceTier.t2,
                          padding: EdgeInsets.zero,
                          radius: 20,
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  minHeight: 148,
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    18,
                                    14,
                                    10,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (final (i, g)
                                          in preview.groups.indexed) ...[
                                        if (i > 0) const SizedBox(width: 10),
                                        Semantics(
                                          key: ValueKey('preview-group-$i'),
                                          label: '${g.enemyCount} ${g.label}',
                                          excludeSemantics: true,
                                          child: Tooltip(
                                            message: g.label,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minWidth:
                                                    48 +
                                                    36 * g.enemyCount / largest,
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  OrionAtlasSprite(
                                                    art: OrionArt.previewGroup(
                                                      g,
                                                    ),
                                                    size: Size.square(
                                                      42 +
                                                          36 *
                                                              g.enemyCount /
                                                              largest,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  OrionReadout(
                                                    value: '×${g.enemyCount}',
                                                    color: t.textPrimary,
                                                    size: 17,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  children: [
                                    for (final trait in traits)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _TraitBadge(trait: trait),
                                          const SizedBox(width: 4),
                                          OrionReadout(
                                            value:
                                                '×${preview.groups.where((g) => g.traits.contains(trait)).fold<int>(0, (n, g) => n + g.enemyCount)}',
                                            color: t.textPrimary,
                                            size: 12,
                                          ),
                                        ],
                                      ),
                                    if (preview.clearBonus > 0)
                                      Semantics(
                                        label:
                                            'Clear bonus ${preview.clearBonus} credits',
                                        excludeSemantics: true,
                                        child: OrionText.micro(
                                          'CLEAR +${preview.clearBonus}',
                                          color: t.creditGold,
                                          size: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final boss in bosses)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: OrionSurface(
                              tier: OrionSurfaceTier.t2,
                              child: Row(
                                children: [
                                  OrionAtlasSprite(
                                    art: OrionArt.previewGroup(boss),
                                    size: const Size.square(120),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        OrionText.micro(
                                          'WAVE ${forecast.waveNumber} · BOSS',
                                          color: t.systemViolet,
                                          size: 9,
                                        ),
                                        OrionTitle(
                                          boss.label,
                                          color: t.textPrimary,
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (preview.recommendedTowerTypes.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          OrionText.micro(
                            'RECOMMENDED COUNTERS',
                            size: 10,
                            color: t.textMuted,
                          ),
                          const SizedBox(height: 10),
                          Semantics(
                            container: true,
                            explicitChildNodes: true,
                            label:
                                'Recommended towers: ${preview.recommendedTowerTypes.map((t) => t.label).join(', ')}',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final type
                                    in preview.recommendedTowerTypes)
                                  SizedBox(
                                    width: 108,
                                    child: OrionSurface(
                                      tier: OrionSurfaceTier.t2,
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        children: [
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Icon(
                                              Icons.check,
                                              size: 18,
                                              color: t.naniteGreen,
                                            ),
                                          ),
                                          OrionAtlasSprite(
                                            art: OrionArt.tower(type),
                                            size: const Size.square(56),
                                          ),
                                          OrionText.micro(
                                            type.label,
                                            color: t.textMuted,
                                            size: 9,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (modifierTitles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Semantics(
                              label: 'Modifiers: ${modifierTitles.join(', ')}',
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final title in modifierTitles)
                                    OrionText.micro(
                                      title,
                                      color: t.warningOrange,
                                      size: 9,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: OrionPrimaryButton(
                    label: 'START WAVE',
                    icon: Icons.play_arrow,
                    onPressed: onStartWave,
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
    final uiTheme = OrionUiTheme.of(context);
    final art = OrionArt.trait(trait);
    return Semantics(
      image: true,
      label: art?.semanticLabel ?? _traitSemanticLabel(trait),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: uiTheme.panelRaised,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: uiTheme.frameSteel),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: art != null
                ? OrionAtlasSprite(art: art, size: const Size.square(17))
                : Icon(
                    switch (trait) {
                      EnemyTrait.swarm => Icons.change_history,
                      EnemyTrait.heavy => Icons.square,
                      EnemyTrait.armored ||
                      EnemyTrait.shielded ||
                      EnemyTrait.regen => Icons.help_outline,
                    },
                    size: 17,
                    color: uiTheme.warningOrange,
                  ),
          ),
        ),
      ),
    );
  }
}
