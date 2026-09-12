import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../models/game_models.dart';
import 'campaign_presentation.dart';
import 'orion_atlas_sprite.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// Full-height modal stage briefing (scene 1b): full-bleed wide stage-key-art
/// hero, stage identity, run facts, conditions, prior result, and one launch
/// action.
///
/// Presentation only — the page derives the run inputs from committed campaign
/// state and passes them as primitives; no briefing view-model exists.
class StageBriefingSheet extends StatelessWidget {
  const StageBriefingSheet({
    super.key,
    required this.stage,
    required this.result,
    required this.startingGold,
    required this.startingBaseHealth,
  });

  final StageDefinition stage;
  final StageResult? result;

  /// Effective start credits for the committed run (campaign-adjusted gold).
  final int startingGold;

  /// Effective starting hull for the committed run (campaign- and
  /// stage-adjusted base health).
  final int startingBaseHealth;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final actionLabel = result == null ? 'Start Mission' : 'Replay Mission';
    final isOptional = !stage.isMainPath;
    final accent = isOptional ? uiTheme.systemViolet : uiTheme.systemCyan;
    final metadata = stage.modifiers.isEmpty
        ? [StageModifierMetadata.standardConditions]
        : stage.modifiers
              .map(StageModifierMetadata.forModifier)
              .toList(growable: false);

    return Material(
      color: uiTheme.voidBlack,
      child: SizedBox.expand(
        key: const ValueKey('stage-briefing'),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.5,
                child: Image.asset(
                  'assets/images/reactor_rim_ui/boards/nebula.png',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      uiTheme.voidBlack,
                      uiTheme.voidBlack.withValues(alpha: 0.28),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: (MediaQuery.sizeOf(context).height * 0.4)
                              .clamp(260, 360),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _BriefingHero(
                                stage: stage,
                                scrimColor: uiTheme.voidBlack,
                              ),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 24,
                                child: _BriefingIdentity(
                                  stage: stage,
                                  accent: accent,
                                  badgeLabel: isOptional
                                      ? 'OPTIONAL'
                                      : 'PRIMARY',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                key: const ValueKey('briefing-facts'),
                                children: [
                                  Expanded(
                                    child: _BriefingStatTile(
                                      icon: Icons.waves_rounded,
                                      value: '${stage.waves.length}',
                                      label: 'WAVES',
                                      color: uiTheme.systemCyan,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _BriefingStatTile(
                                      icon: Icons.shield_outlined,
                                      value: '$startingBaseHealth',
                                      label: 'HULL',
                                      color: uiTheme.systemCyan,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _BriefingStatTile(
                                      icon: Icons.hexagon,
                                      value: '$startingGold',
                                      label: 'START',
                                      color: uiTheme.creditGold,
                                      valueColor: uiTheme.creditGold,
                                    ),
                                  ),
                                  if (metadata.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _BriefingModifierTile(
                                        key: const ValueKey(
                                          'briefing-modifier',
                                        ),
                                        title: metadata.first.title,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              // The tile above names the modifier, so this is
                              // its effect, not its name again. The artboard has
                              // no conditions section at all -- it expects the
                              // player to know what ION STORM does -- but a
                              // modifier's actual numbers are worth a line, and
                              // repeating the title alongside the tile is not.
                              if (metadata.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Text(
                                  metadata.first.description,
                                  key: const ValueKey(
                                    'briefing-modifier-effect',
                                  ),
                                  style: OrionTypography.microLabel(
                                    color: uiTheme.textMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              _BriefingThreatProfile(stage: stage),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _BriefingIntelRow(
                                      icon: medalIcon(StageMedal.gold),
                                      color: uiTheme.creditGold,
                                      title:
                                          '$startingBaseHealth/$startingBaseHealth',
                                      detail: 'GOLD · NO LEAKS',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _BriefingIntelRow(
                                      icon: medalIcon(StageMedal.silver),
                                      color: uiTheme.textMuted,
                                      title:
                                          '${GameBalance.silverMedalThreshold}+ HULL',
                                      detail: 'SILVER',
                                    ),
                                  ),
                                ],
                              ),
                              if (metadata.length > 1) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'CONDITIONS',
                                  style: OrionTypography.microLabel(
                                    size: 11,
                                    color: uiTheme.systemCyan,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                for (final entry in metadata.skip(1)) ...[
                                  _BriefingIntelRow(
                                    icon: Icons.radar_rounded,
                                    color: uiTheme.systemCyan,
                                    title: entry.title,
                                    detail: entry.description,
                                  ),
                                  const SizedBox(height: 7),
                                ],
                              ],
                              const SizedBox(height: 9),
                              if (stage.reward != null) ...[
                                _BriefingIntelRow(
                                  icon: rewardIcon(stage.reward!),
                                  color: uiTheme.creditGold,
                                  title: 'SALVAGE',
                                  detail: _briefingRewardLabel(
                                    stage.reward!,
                                    earned: result != null,
                                  ),
                                ),
                                const SizedBox(height: 7),
                              ],
                              if (result != null) ...[
                                _BriefingIntelRow(
                                  icon: medalIcon(result!.medal),
                                  color: medalColor(uiTheme, result!.medal),
                                  title: 'BEST RESULT',
                                  detail:
                                      'Best: ${result!.medal.label} • '
                                      '${result!.bestBaseHealth} base health',
                                ),
                                const SizedBox(height: 7),
                              ],
                              // HPA-528: a committed Outpost Alpha clear also
                              // recovers the Relay Calibration blueprint; the
                              // committed `result` is the first-clear signal.
                              if (stage.id == OrionCampaign.stageOneId &&
                                  result != null) ...[
                                _BriefingIntelRow(
                                  icon: Icons.memory_rounded,
                                  color: uiTheme.systemViolet,
                                  title: 'BLUEPRINT',
                                  detail:
                                      'Blueprint recovered: Relay Calibration',
                                ),
                                const SizedBox(height: 7),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    12,
                    14,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _BriefingLaunchAction(
                    label: actionLabel,
                    accent: accent,
                    icon: result == null
                        ? Icons.play_arrow_rounded
                        : Icons.replay_rounded,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 14,
              child: OrionSurface(
                tier: OrionSurfaceTier.t1,
                padding: EdgeInsets.zero,
                radius: 14,
                child: IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: uiTheme.systemCyan,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centred stage identity: sector eyebrow and display-scale name.
///
/// The artboard treats the stage name as the sheet's hero rather than a
/// chrome title, so this is the one place [OrionTitle] is asked for a display
/// size. It renders the caps the artboard sets while keeping the real copy as
/// the semantics label.
class _BriefingIdentity extends StatelessWidget {
  const _BriefingIdentity({
    required this.stage,
    required this.accent,
    required this.badgeLabel,
  });

  final StageDefinition stage;
  final Color accent;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final sector = OrionCampaign.stages.indexWhere((s) => s.id == stage.id) + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wrap, not a Row: at 3x text scale the eyebrow and the badge no
        // longer fit side by side, and reflowing to a second line keeps both
        // readable where a Row would overflow.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (sector > 0)
              OrionText.micro(
                'SECTOR ${sector.toString().padLeft(2, '0')}',
                color: accent,
                size: 11,
              ),
            _BriefingBadge(label: badgeLabel, color: accent),
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: OrionTitle(
            stage.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            color: uiTheme.textPrimary,
            size: 30,
          ),
        ),
      ],
    );
  }
}

/// What the run is actually made of, counted off [StageDefinition.waves].
///
/// Every figure here is derived from committed wave data — the artboard's
/// threat panel also shows a per-objective row, but this game has no leak or
/// tower-cap objective to report, so those are omitted rather than mocked.
class _BriefingThreatProfile extends StatelessWidget {
  const _BriefingThreatProfile({required this.stage});

  final StageDefinition stage;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final threat = _StageThreat.of(stage);

    return OrionSurface(
      tier: OrionSurfaceTier.t2,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 4, height: 12, color: uiTheme.dangerRed),
              const SizedBox(width: 7),
              Expanded(
                child: OrionText.micro(
                  'THREAT PROFILE',
                  color: uiTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _ThreatFigure(
                  art: OrionArt.previewGroup(
                    WavePreviewGroup(
                      enemyCount: threat.enemies,
                      label: 'Drones',
                      traits: const {},
                    ),
                  ),
                  value: '${threat.enemies}',
                  label: 'HOSTILES',
                  color: uiTheme.textPrimary,
                ),
              ),
              Expanded(
                child: _ThreatFigure(
                  art: OrionArt.trait(EnemyTrait.armored)!,
                  value: '${threat.armored}',
                  label: 'ARMORED',
                  color: threat.armored > 0
                      ? uiTheme.warningOrange
                      : uiTheme.textMuted,
                ),
              ),
              Expanded(
                child: _ThreatFigure(
                  art: OrionArt.trait(EnemyTrait.shielded)!,
                  value: '${threat.shielded}',
                  label: 'SHIELDED',
                  color: threat.shielded > 0
                      ? uiTheme.systemViolet
                      : uiTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One numeral over its caps label, sized for a three-across row.
class _ThreatFigure extends StatelessWidget {
  const _ThreatFigure({
    required this.value,
    required this.label,
    required this.color,
    required this.art,
  });

  final OrionArtDescriptor art;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrionAtlasSprite(art: art, size: const Size.square(46)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: OrionTypography.readout(size: 14, color: color),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OrionTypography.microLabel(color: uiTheme.textMuted),
        ),
      ],
    );
  }
}

/// Enemy totals for a whole stage, summed across every wave group.
class _StageThreat {
  const _StageThreat({
    required this.enemies,
    required this.armored,
    required this.shielded,
  });

  factory _StageThreat.of(StageDefinition stage) {
    var enemies = 0;
    var armored = 0;
    var shielded = 0;
    for (final wave in stage.waves) {
      for (final group in wave.groups) {
        final stats = group.enemyStats;
        enemies += group.enemyCount;
        if (stats.armorReduction > 0) {
          armored += group.enemyCount;
        }
        if (stats.shieldHealth > 0) {
          shielded += group.enemyCount;
        }
      }
    }
    return _StageThreat(enemies: enemies, armored: armored, shielded: shielded);
  }

  final int enemies;
  final int armored;
  final int shielded;
}

/// The sheet's one solid, filled action.
class _BriefingLaunchAction extends StatelessWidget {
  const _BriefingLaunchAction({
    required this.label,
    required this.accent,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Color accent;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF7FF0FF), Color(0xFF13B8E6), Color(0xFF0A7EA3)],
              stops: [0, 0.6, 1],
            ),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 24),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(18),
              splashColor: uiTheme.voidBlack.withValues(alpha: 0.18),
              highlightColor: uiTheme.voidBlack.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 22,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: uiTheme.voidBlack),
                    const SizedBox(width: 10),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        // On a filled accent the label must be the dark ink,
                        // which microLabel's muted-only rule cannot express.
                        child: ExcludeSemantics(
                          child: Text(
                            label == 'Start Mission' ? 'DEPLOY' : 'REPLAY',
                            style: OrionTypography.microLabel(
                              color: uiTheme.voidBlack,
                              size: 13,
                            ).copyWith(letterSpacing: 3.6, shadows: const []),
                          ),
                        ),
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

/// Full-bleed wide key-art band with a scrim melting into the sheet body.
class _BriefingHero extends StatelessWidget {
  const _BriefingHero({required this.stage, required this.scrimColor});

  final StageDefinition stage;
  final Color scrimColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 640,
              height: 400,
              child: OrionAtlasSprite(
                art: OrionArt.stage(
                  stage,
                  crop: OrionStageArtCrop.briefingWide,
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scrimColor.withValues(alpha: 0.25),
                scrimColor.withValues(alpha: 0),
                scrimColor,
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// One tile in artboard 1b's fact row: a glyph, a figure, a caption.
///
/// [color] carries the tile's role and tints the glyph. It used to be passed
/// by every caller and read by none — the figure was hard-coded to
/// textPrimary, so START arrived as creditGold and rendered white like the
/// rest. [valueColor] now says explicitly when the figure takes the role
/// colour too, which the artboard does only for credits.
class _BriefingStatTile extends StatelessWidget {
  const _BriefingStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.valueColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final tile = OrionSurface(
      tier: OrionSurfaceTier.t2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: OrionTypography.readout(
                color: valueColor ?? uiTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OrionTypography.microLabel(color: uiTheme.textMuted),
          ),
        ],
      ),
    );
    return tile;
  }
}

/// The fourth tile in artboard 1b's fact row.
///
/// Deliberately not a [_BriefingStatTile] with a colour override: the
/// artboard's modifier tile has no figure. Its name *is* the value, set at
/// label scale over two lines and ringed in warning orange so it reads as the
/// odd one out — a modifier title like "Standard Conditions" would be
/// unreadable shrunk into a numeral slot.
class _BriefingModifierTile extends StatelessWidget {
  const _BriefingModifierTile({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: uiTheme.warningOrange, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.bolt_rounded, color: uiTheme.warningOrange, size: 17),
            const SizedBox(height: 3),
            // OrionTitle's pattern rather than a bare toUpperCase(): caps
            // for display, the real copy kept as the semantics label, so a
            // screen reader announces "Standard Conditions" instead of
            // spelling out a shout -- and finders still match real copy.
            Semantics(
              label: title,
              child: ExcludeSemantics(
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OrionTypography.microLabel(
                    size: 9,
                    color: uiTheme.warningOrange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'MODIFIER',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OrionTypography.microLabel(color: uiTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefingBadge extends StatelessWidget {
  const _BriefingBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(label, style: OrionTypography.microLabel(color: color)),
      ),
    );
  }
}

class _BriefingIntelRow extends StatelessWidget {
  const _BriefingIntelRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return OrionSurface(
      tier: OrionSurfaceTier.t2,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: OrionTypography.microLabel(size: 11, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: OrionTypography.microLabel(
                    size: 9,
                    color: uiTheme.textMuted,
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

String _briefingRewardLabel(CampaignReward reward, {required bool earned}) {
  // Persistent campaign rewards are granted once per stage when it is first
  // cleared (CampaignModifiers.fromProgress keys off isCleared); replays do
  // not stack the reward. The label reflects whether it has already been
  // granted so the Replay Mission sheet doesn't imply a fresh payout.
  final prefix = earned ? 'Reward earned:' : 'Completion reward:';
  return switch (reward) {
    CampaignReward.bonusGold =>
      '$prefix +${GameBalance.salvageRiftGoldBonus} Gold',
    CampaignReward.bonusHealth =>
      '$prefix +${GameBalance.voidBastionHealthBonus} HP',
    CampaignReward.challengeBadge => '$prefix Challenge Badge',
  };
}
