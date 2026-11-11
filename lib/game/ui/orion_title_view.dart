import 'package:flutter/material.dart';

import '../campaign/stage_definition.dart';
import 'orion_atlas_sprite.dart';
import 'orion_menu_shell.dart';
import 'orion_primary_button.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

class OrionTitleView extends StatelessWidget {
  const OrionTitleView({
    super.key,
    required this.recommendedStage,
    required this.isContinueAvailable,
    required this.campaignComplete,
    required this.medalEarned,
    required this.medalTotal,
    required this.researchPoints,
    required this.onContinue,
    required this.onOpenSectors,
    required this.onOpenResearch,
    required this.onOpenCodex,
    required this.onOpenSettings,
    this.busy = false,
    this.feedback,
  });

  final StageDefinition? recommendedStage;

  final bool isContinueAvailable;

  final bool campaignComplete;

  final int medalEarned;
  final int medalTotal;
  final int researchPoints;

  final VoidCallback? onContinue;
  final VoidCallback? onOpenSectors;
  final VoidCallback? onOpenResearch;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenSettings;

  final bool busy;

  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Material(
      color: uiTheme.voidBlack,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _TitleBackdrop(),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: orionTitleShade),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        SizedBox(
                          height:
                              constraints.maxHeight *
                              (constraints.maxHeight >= 760 ? 0.30 : 0.12),
                        ),
                        const _TitleLockup(),
                        SizedBox(
                          height: constraints.maxHeight >= 760
                              ? constraints.maxHeight * 0.13
                              : 20,
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CampaignCard(
                                stage: recommendedStage,
                                campaignComplete: campaignComplete,
                                continueAvailable: isContinueAvailable,
                                medalEarned: medalEarned,
                                medalTotal: medalTotal,
                                researchPoints: researchPoints,
                              ),
                              const SizedBox(height: 14),
                              OrionPrimaryButton(
                                key: const ValueKey('title-primary-cta'),
                                label: isContinueAvailable
                                    ? 'Continue'
                                    : 'Sectors',
                                icon: isContinueAvailable
                                    ? Icons.play_arrow_rounded
                                    : Icons.public_rounded,
                                height: 64,
                                labelSize: 16,
                                onPressed: busy
                                    ? null
                                    : (isContinueAvailable
                                          ? onContinue
                                          : onOpenSectors),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        _ShortcutRow(
                          busy: busy,
                          onOpenSectors: onOpenSectors,
                          onOpenResearch: onOpenResearch,
                          onOpenCodex: onOpenCodex,
                          onOpenSettings: onOpenSettings,
                        ),
                        if (feedback != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            feedback!,
                            textAlign: TextAlign.center,
                            style: OrionTypography.microLabel(
                              size: 11,
                              color: uiTheme.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'ORION // COMMAND DECK',
                            maxLines: 1,
                            style: OrionTypography.microLabel(
                              size: 10,
                              color: uiTheme.textMuted,
                            ).copyWith(letterSpacing: 2.4),
                          ),
                        ),
                        const SizedBox(height: 14),
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

class _TitleBackdrop extends StatelessWidget {
  const _TitleBackdrop();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/reactor_rim_ui/backdrops/command-center.png',
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _TitleLockup extends StatelessWidget {
  const _TitleLockup();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final glow = Shadow(
      color: uiTheme.systemCyan.withValues(alpha: 0.55),
      blurRadius: 18,
    );
    const lip = Shadow(color: orionWordmarkLip, offset: Offset(0, 4));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'SPACE TOWER DEFENSE',
            maxLines: 1,
            style:
                OrionTypography.microLabel(
                  size: 12,
                  color: uiTheme.systemCyan,
                ).copyWith(
                  letterSpacing: 6,
                  shadows: [
                    Shadow(
                      color: uiTheme.systemCyan.withValues(alpha: 0.7),
                      blurRadius: 10,
                    ),
                  ],
                ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  child: OrionTitle(
                    'Orion',
                    size: 84,
                    color: Colors.transparent,
                    shadows: [glow, lip],
                  ),
                ),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: orionWordmarkFill.createShader,
                  child: OrionTitle(
                    'Orion',
                    size: 84,
                    color: uiTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Flexible(child: _HoldRule()),
            Flexible(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'HOLD THE SECTOR',
                    maxLines: 1,
                    style: OrionTypography.microLabel(
                      size: 13,
                      color: uiTheme.creditGold,
                    ).copyWith(letterSpacing: 4.2),
                  ),
                ),
              ),
            ),
            const Flexible(child: _HoldRule()),
          ],
        ),
      ],
    );
  }
}

class _HoldRule extends StatelessWidget {
  const _HoldRule();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 44),
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            uiTheme.creditGold.withValues(alpha: 0),
            uiTheme.creditGold.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.stage,
    required this.campaignComplete,
    required this.continueAvailable,
    required this.medalEarned,
    required this.medalTotal,
    required this.researchPoints,
  });

  final StageDefinition? stage;
  final bool campaignComplete;
  final bool continueAvailable;
  final int medalEarned;
  final int medalTotal;
  final int researchPoints;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stage = this.stage;
    final headline = continueAvailable
        ? (stage?.name ?? 'No missions')
        : campaignComplete
        ? 'All sectors cleared'
        : (stage?.name ?? 'No missions');
    final showArt =
        stage != null && MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    return OrionSurface(
      key: const ValueKey('title-campaign-card'),
      role: OrionSurfaceRole.sheet,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showArt) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: OrionAtlasSprite(
                art: OrionArt.stage(stage, crop: OrionStageArtCrop.mapSquare),
                size: const Size.square(56),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  campaignComplete
                      ? 'CAMPAIGN COMPLETE'
                      : 'CAMPAIGN / NEXT MISSION',
                  maxLines: 2,
                  style: OrionTypography.microLabel(
                    size: 10,
                    color: uiTheme.textMuted,
                  ).copyWith(letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                OrionTitle(
                  headline,
                  color: uiTheme.textPrimary,
                  size: 18,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OrionResourceChip(
                      icon: Icons.emoji_events,
                      iconColor: uiTheme.creditGold,
                      count: '$medalEarned/$medalTotal',
                      semanticsLabel:
                          '$medalEarned of $medalTotal campaign medals',
                    ),
                    OrionResourceChip(
                      icon: Icons.diamond_rounded,
                      iconColor: uiTheme.systemViolet,
                      count: '$researchPoints',
                      semanticsLabel: '$researchPoints research points',
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

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.busy,
    required this.onOpenSectors,
    required this.onOpenResearch,
    required this.onOpenCodex,
    required this.onOpenSettings,
  });

  final bool busy;
  final VoidCallback? onOpenSectors;
  final VoidCallback? onOpenResearch;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GhostAction(
            icon: Icons.public_rounded,
            label: 'Sectors',
            tooltip: 'Sectors',
            onPressed: busy ? null : onOpenSectors,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GhostAction(
            icon: Icons.biotech_rounded,
            label: 'R&D',
            tooltip: 'R&D',
            onPressed: busy ? null : onOpenResearch,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GhostAction(
            icon: Icons.menu_book_rounded,
            label: 'Codex',
            tooltip: 'Codex',
            onPressed: busy ? null : onOpenCodex,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _GhostAction(
            icon: Icons.settings_rounded,
            label: 'Settings',
            tooltip: 'Settings',
            iconOnly: true,
            onPressed: busy ? null : onOpenSettings,
          ),
        ),
      ],
    );
  }
}

class _GhostAction extends StatelessWidget {
  const _GhostAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 62,
              width: double.infinity,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: orionGhostFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: orionGhostEdge),
                  boxShadow: const [
                    BoxShadow(color: orionGhostLip, offset: Offset(0, 3)),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: iconOnly
                            ? uiTheme.textMuted
                            : icon == Icons.biotech_rounded
                            ? uiTheme.systemViolet
                            : uiTheme.systemCyan,
                      ),
                      if (!iconOnly) ...[
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.3),
                            style: OrionTypography.microLabel(
                              size: 10,
                              color: uiTheme.textMuted,
                            ).copyWith(letterSpacing: 1),
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
      ),
    );
  }
}
