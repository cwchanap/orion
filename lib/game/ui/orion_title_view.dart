import 'package:flutter/material.dart';

import '../campaign/stage_definition.dart';
import 'orion_atlas_sprite.dart';
import 'orion_menu_shell.dart';
import 'orion_primary_button.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Scene 1a — the arcade command-deck front door. Command-center art behind
/// a readability shade, the ORION wordmark, a campaign progress card with
/// the next recommended mission, one primary action (Continue while a
/// recommendation is open, Sectors once the campaign is fully cleared), and
/// a ghost shortcut row into the shared menu destinations.
///
/// The title never owns navigation state: every control is a plain callback
/// the page wires to its private `_ShellView` switch.
class OrionTitleView extends StatelessWidget {
  const OrionTitleView({
    super.key,
    required this.recommendedStage,
    required this.isContinueAvailable,
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

  /// The stage the shared recommender steers to — the same value the map's
  /// next-mission card shows. Null when the helper found no fallback.
  final StageDefinition? recommendedStage;

  /// True only while [recommendedStage] is unlocked and uncleared — the one
  /// state where 'Continue' is honest. A cleared replay fallback or a null
  /// recommendation turns the primary action into Sectors instead.
  final bool isContinueAvailable;

  final int medalEarned;
  final int medalTotal;
  final int researchPoints;

  /// Fired by the Continue action; the page opens the stage briefing.
  final VoidCallback? onContinue;
  final VoidCallback? onOpenSectors;
  final VoidCallback? onOpenResearch;
  final VoidCallback? onOpenCodex;
  final VoidCallback? onOpenSettings;

  /// Save/reset in flight: every navigation and launch control is inert.
  final bool busy;

  /// Transient status line (save errors, reset breadcrumbs).
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
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SizedBox(height: constraints.maxHeight * 0.14),
                        const _TitleLockup(),
                        const SizedBox(height: 30),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CampaignCard(
                                stage: recommendedStage,
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
                                height: 54,
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
                        Text(
                          'v0.0 // COMMAND DECK',
                          style: OrionTypography.microLabel(
                            size: 10,
                            color: uiTheme.textMuted,
                          ).copyWith(letterSpacing: 2.4),
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

/// Command-center art, cover-fit into the portrait aperture — the same
/// approved backdrop the next-wave scanner's idle state uses.
class _TitleBackdrop extends StatelessWidget {
  const _TitleBackdrop();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox.square(
          dimension: 640,
          child: OrionAtlasSprite(
            art: OrionArt.scene(OrionSceneArt.commandCenter),
            size: const Size.square(640),
          ),
        ),
      ),
    );
  }
}

/// The wordmark lockup: ORION in the Oxanium gradient word, a cyan kicker,
/// and a muted hold-line flanked by hairline rules — all from the kit's
/// `.lockup` block.
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
        Stack(
          alignment: Alignment.center,
          children: [
            // Solid shadow layer: a transparent-fill duplicate carries the
            // glow and lip behind the gradient word, so both stay their own
            // color instead of being tinted by the wordmark gradient.
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
              child: const OrionTitle('Orion', size: 84, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'SPACE TOWER DEFENSE',
          style: OrionTypography.microLabel(size: 12, color: uiTheme.systemCyan)
              .copyWith(
                letterSpacing: 6,
                shadows: [
                  Shadow(
                    color: uiTheme.systemCyan.withValues(alpha: 0.7),
                    blurRadius: 10,
                  ),
                ],
              ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _HoldRule(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'HOLD THE SECTOR',
                style: OrionTypography.microLabel(
                  size: 13,
                  color: uiTheme.creditGold,
                ).copyWith(letterSpacing: 4.2),
              ),
            ),
            const _HoldRule(),
          ],
        ),
      ],
    );
  }
}

/// 44x2 gold hairline fading outward — flanks the hold-line in the lockup.
class _HoldRule extends StatelessWidget {
  const _HoldRule();

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Container(
      width: 44,
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

/// `.panel.br` campaign card: 'DEPLOYMENT' label, the recommended stage
/// name, and the two resource chips the shell's top bar also carries.
class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.stage,
    required this.medalEarned,
    required this.medalTotal,
    required this.researchPoints,
  });

  final StageDefinition? stage;
  final int medalEarned;
  final int medalTotal;
  final int researchPoints;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final stage = this.stage;
    return OrionSurface(
      key: const ValueKey('title-campaign-card'),
      role: OrionSurfaceRole.sheet,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEPLOYMENT',
                      style: OrionTypography.microLabel(
                        size: 11,
                        color: uiTheme.systemCyan,
                      ).copyWith(letterSpacing: 2.6),
                    ),
                    const SizedBox(height: 6),
                    OrionTitle(
                      stage?.name ?? 'No missions',
                      color: uiTheme.textPrimary,
                      size: 22,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OrionResourceChip(
                    icon: Icons.emoji_events,
                    iconColor: uiTheme.creditGold,
                    count: '$medalEarned/$medalTotal',
                    semanticsLabel:
                        '$medalEarned of $medalTotal campaign medals',
                  ),
                  const SizedBox(height: 6),
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
        ],
      ),
    );
  }
}

/// `.btn.ghost` shortcut row: Sectors, R&D, Codex, and the Settings gear —
/// the same destinations the shared shell's tab bar switches between.
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _GhostAction(
          icon: Icons.public_rounded,
          label: 'Sectors',
          tooltip: 'Sectors',
          onPressed: busy ? null : onOpenSectors,
        ),
        const SizedBox(width: 8),
        _GhostAction(
          icon: Icons.biotech_rounded,
          label: 'R&D',
          tooltip: 'R&D',
          onPressed: busy ? null : onOpenResearch,
        ),
        const SizedBox(width: 8),
        _GhostAction(
          icon: Icons.menu_book_rounded,
          label: 'Codex',
          tooltip: 'Codex',
          onPressed: busy ? null : onOpenCodex,
        ),
        const SizedBox(width: 8),
        _GhostAction(
          icon: Icons.settings_rounded,
          label: 'Settings',
          tooltip: 'Settings',
          iconOnly: true,
          onPressed: busy ? null : onOpenSettings,
        ),
      ],
    );
  }
}

/// One `.btn.ghost`: a flat plate with a hairline lip, icon, and a muted
/// all-caps label rendered via microLabel (real copy stays in semantics).
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
          child: Ink(
            decoration: BoxDecoration(
              gradient: orionGhostFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: orionGhostEdge),
              boxShadow: const [
                BoxShadow(color: orionGhostLip, offset: Offset(0, 3)),
              ],
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: iconOnly ? 13 : 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: uiTheme.textMuted),
                    if (!iconOnly) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: OrionTypography.microLabel(
                          size: 11.5,
                          color: uiTheme.textMuted,
                        ).copyWith(letterSpacing: 1.84),
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
