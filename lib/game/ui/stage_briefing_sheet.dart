import 'package:flutter/material.dart';

import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../campaign/stage_modifier_metadata.dart';
import '../models/game_models.dart';
import 'campaign_presentation.dart';
import 'command_frame.dart';
import 'orion_atlas_sprite.dart';
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

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Container(
        key: const ValueKey('stage-briefing'),
        color: uiTheme.hullBlack,
        height: double.infinity,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BriefingHero(stage: stage, scrimColor: uiTheme.hullBlack),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  stage.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: uiTheme.textPrimary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _BriefingBadge(
                                label: isOptional ? 'OPTIONAL' : 'PRIMARY',
                                color: accent,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            stage.description,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: uiTheme.textMuted),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            key: const ValueKey('briefing-facts'),
                            children: [
                              Expanded(
                                child: _BriefingStatTile(
                                  value: '${stage.waves.length}',
                                  label: 'WAVES',
                                  color: uiTheme.systemCyan,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _BriefingStatTile(
                                  value: '$startingBaseHealth',
                                  label: 'HULL',
                                  color: uiTheme.systemCyan,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _BriefingStatTile(
                                  value: '$startingGold',
                                  label: 'START',
                                  color: uiTheme.creditGold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'CONDITIONS',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: uiTheme.systemCyan,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          const SizedBox(height: 7),
                          for (final entry in metadata) ...[
                            _BriefingIntelRow(
                              icon: Icons.radar_rounded,
                              color: uiTheme.systemCyan,
                              title: entry.title,
                              detail: entry.description,
                            ),
                            const SizedBox(height: 7),
                          ],
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
                              detail: 'Blueprint recovered: Relay Calibration',
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
                16,
                8,
                16,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tooltip(
                    message: actionLabel,
                    excludeFromSemantics: true,
                    child: Semantics(
                      button: true,
                      label: actionLabel,
                      child: CommandFrame(
                        padding: EdgeInsets.zero,
                        color: uiTheme.panelBlue,
                        borderColor: uiTheme.systemCyan,
                        emphasized: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(true),
                            splashColor: uiTheme.systemCyan.withValues(
                              alpha: 0.18,
                            ),
                            highlightColor: uiTheme.systemCyan.withValues(
                              alpha: 0.10,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    result == null
                                        ? Icons.rocket_launch_rounded
                                        : Icons.replay_rounded,
                                    color: uiTheme.textPrimary,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        actionLabel,
                                        maxLines: 1,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: uiTheme.textPrimary,
                                              fontWeight: FontWeight.w900,
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
                  ),
                  const SizedBox(height: 2),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
          ],
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
    // The briefingWide crop is 1.6:1, so an AspectRatio box makes the Flame
    // sprite's contain-fit fill the band exactly — full-bleed, no insets.
    return AspectRatio(
      aspectRatio: OrionArt.briefingHeroAspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          OrionAtlasSprite(
            art: OrionArt.stage(stage, crop: OrionStageArtCrop.briefingWide),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scrimColor.withValues(alpha: 0), scrimColor],
                stops: const [0.82, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefingStatTile extends StatelessWidget {
  const _BriefingStatTile({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: uiTheme.panelBlue,
      borderColor: color.withValues(alpha: 0.62),
      chamfer: 9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: uiTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: uiTheme.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
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
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
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
    return CommandFrame(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      color: uiTheme.panelBlue,
      borderColor: color.withValues(alpha: 0.62),
      chamfer: 7,
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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: uiTheme.textPrimary),
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
