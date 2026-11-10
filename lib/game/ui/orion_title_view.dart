import 'package:flutter/material.dart';

import '../campaign/stage_definition.dart';
import 'orion_atlas_sprite.dart';
import 'orion_primary_button.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// The front door (artboard 01): full-bleed command-center backdrop, a
/// text-styled ORION wordmark, the live campaign recommendation card, one
/// primary action (Continue or Sectors), and ghost shortcuts into Sectors,
/// R&D, Codex, and Settings.
///
/// Presentation only — the page resolves the recommendation and every
/// navigation callback; this view renders what it is handed.
class OrionTitleView extends StatelessWidget {
  const OrionTitleView({
    super.key,
    required this.recommendedStage,
    required this.canContinue,
    required this.campaignComplete,
    required this.medalRank,
    required this.medalRankMax,
    required this.researchPoints,
    this.feedback,
    this.actionsEnabled = true,
    this.onContinue,
    this.onOpenSectors,
    this.onOpenTechTree,
    this.onOpenCodex,
    this.onOpenSettings,
  });

  /// The campaign's recommended stage, straight from
  /// `CampaignProgress.recommendedStage` — null only when no stage is
  /// unlocked at all.
  final StageDefinition? recommendedStage;

  /// True only when the recommendation is an unlocked, uncleared mission —
  /// the only case where the primary action reads Continue. A cleared
  /// replay fallback or a null recommendation shows Sectors instead.
  final bool canContinue;

  /// `CampaignProgress.isCampaignComplete` — copy only, never selection.
  final bool campaignComplete;

  final int medalRank;
  final int medalRankMax;
  final int researchPoints;
  final String? feedback;

  /// Save/reset busy states freeze destination switching, mirroring the
  /// shell's tab gating.
  final bool actionsEnabled;

  /// Fires only when [canContinue]; the page routes it to the stage
  /// briefing, never to a direct launch.
  final VoidCallback? onContinue;
  final VoidCallback? onOpenSectors;
  final VoidCallback? onOpenTechTree;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return SafeArea(
      child: Stack(
        children: [
          const Positioned.fill(child: _TitleBackdrop()),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: SizedBox(
                  height: constraints.maxHeight < 560
                      ? 560
                      : constraints.maxHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(flex: 5),
                        const _TitleWordmark(),
                        const Spacer(flex: 4),
                        _ProgressCard(
                          stage: recommendedStage,
                          canContinue: canContinue,
                          campaignComplete: campaignComplete,
                          medalRank: medalRank,
                          medalRankMax: medalRankMax,
                          researchPoints: researchPoints,
                        ),
                        const SizedBox(height: 12),
                        OrionPrimaryButton(
                          label: canContinue ? 'Continue' : 'Sectors',
                          icon: canContinue
                              ? Icons.play_arrow_rounded
                              : Icons.map_rounded,
                          onPressed: canContinue ? onContinue : onOpenSectors,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _GhostAction(
                                tooltip: 'Sectors',
                                label: 'Sectors',
                                icon: Icons.map_rounded,
                                onPressed: actionsEnabled
                                    ? onOpenSectors
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _GhostAction(
                                tooltip: 'Tech Tree',
                                label: 'R&D',
                                icon: Icons.science_rounded,
                                onPressed: actionsEnabled
                                    ? onOpenTechTree
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _GhostAction(
                                tooltip: 'Codex',
                                label: 'Codex',
                                icon: Icons.menu_book_rounded,
                                onPressed: actionsEnabled ? onOpenCodex : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _GhostAction(
                              tooltip: 'Settings',
                              icon: Icons.settings_rounded,
                              onPressed: onOpenSettings,
                            ),
                          ],
                        ),
                        if (feedback != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            feedback!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: OrionTypography.microLabel(
                              color: uiTheme.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'v1.0 · Command deck',
                          textAlign: TextAlign.center,
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Command-center scene art plus the artboard's two readability shades.
class _TitleBackdrop extends StatelessWidget {
  const _TitleBackdrop();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: uiTheme.voidBlack),
        Image.asset(
          'assets/images/reactor_rim_ui/backdrops/command-center.png',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: orionTitleGlowWash),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: orionTitleShade),
        ),
      ],
    );
  }
}

/// Kicker + gradient ORION word + gold subtitle rule (scene 01's .logo).
class _TitleWordmark extends StatelessWidget {
  const _TitleWordmark();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SPACE TOWER DEFENSE',
          textAlign: TextAlign.center,
          style: OrionTypography.microLabel(size: 12, color: uiTheme.systemCyan)
              .copyWith(
                letterSpacing: 6,
                shadows: [
                  Shadow(
                    color: uiTheme.systemCyan.withValues(alpha: .6),
                    blurRadius: 14,
                  ),
                ],
              ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => orionTitleWordFill.createShader(bounds),
            child: Text(
              'ORION',
              textAlign: TextAlign.center,
              style: OrionTypography.wordmark(color: uiTheme.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      uiTheme.creditGold.withValues(alpha: 0),
                      uiTheme.creditGold.withValues(alpha: .9),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'HOLD THE SECTOR',
                style: OrionTypography.microLabel(
                  size: 11,
                  color: uiTheme.creditGold,
                ).copyWith(letterSpacing: 4.6),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      uiTheme.creditGold.withValues(alpha: .9),
                      uiTheme.creditGold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Live campaign recommendation: crest, eyebrow, stage name, and the medal /
/// research chips — all fed by committed progress, not mock copy.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.stage,
    required this.canContinue,
    required this.campaignComplete,
    required this.medalRank,
    required this.medalRankMax,
    required this.researchPoints,
  });

  final StageDefinition? stage;
  final bool canContinue;
  final bool campaignComplete;
  final int medalRank;
  final int medalRankMax;
  final int researchPoints;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final label = canContinue
        ? 'Campaign · Next mission'
        : campaignComplete
        ? 'Campaign · Complete'
        : 'Campaign · Mission select';
    // A finished campaign's recommendation is only a replay fallback — the
    // card celebrates completion instead of pointing at an old stage.
    final title = campaignComplete
        ? 'All missions cleared'
        : stage?.name ?? 'Choose a sector';
    return OrionSurface(
      role: OrionSurfaceRole.sheet,
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          if (stage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: orionCrestEdge),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: OrionAtlasSprite(
                    art: OrionArt.stage(
                      stage!,
                      crop: OrionStageArtCrop.mapSquare,
                    ),
                    size: const Size.square(56),
                  ),
                ),
              ),
            )
          else
            Icon(Icons.public, size: 40, color: uiTheme.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                OrionText.micro(label, color: uiTheme.textDim, size: 10),
                const SizedBox(height: 4),
                OrionTitle(
                  title,
                  size: 18,
                  color: uiTheme.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _ProgressChip(
                      icon: Icons.emoji_events_rounded,
                      value: '$medalRank/$medalRankMax',
                      color: uiTheme.creditGold,
                    ),
                    const SizedBox(width: 7),
                    _ProgressChip(
                      icon: Icons.science_rounded,
                      value: '$researchPoints',
                      color: uiTheme.systemViolet,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small figure chip inside the title progress card (medal rank, R&D points).
class _ProgressChip extends StatelessWidget {
  const _ProgressChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(value, style: OrionTypography.readout(size: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Title ghost shortcut: raised panel tile with a dark lip and top glint.
class _GhostAction extends StatelessWidget {
  const _GhostAction({
    required this.tooltip,
    this.label,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final String? label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    final tint = enabled ? uiTheme.textMuted : uiTheme.textDim;
    final borderRadius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      label: tooltip,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius,
            child: Ink(
              height: 62,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: orionGhostFill,
                border: Border.all(color: uiTheme.frameSteel),
                boxShadow: const [
                  BoxShadow(color: orionGhostLip, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: tint),
                  if (label != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      label!,
                      maxLines: 1,
                      style: OrionTypography.microLabel(size: 10, color: tint),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
