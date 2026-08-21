import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'command_frame.dart';
import 'orion_ui_theme.dart';

Color baseHealthColor(GameSnapshot snapshot, OrionUiTheme uiTheme) {
  final fraction = snapshot.startingBaseHealth == 0
      ? 0.0
      : snapshot.baseHealth / snapshot.startingBaseHealth;
  if (fraction > 0.50) return uiTheme.systemCyan;
  if (fraction > 0.25) return uiTheme.warningOrange;
  return uiTheme.dangerRed;
}

class MissionStatusHud extends StatelessWidget {
  const MissionStatusHud({super.key, required this.snapshot});

  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);

    return CommandFrame(
      padding: EdgeInsets.zero,
      color: uiTheme.hullBlack,
      borderColor: uiTheme.frameSteel,
      child: SizedBox(
        height: 56,
        child: Row(
          key: const ValueKey('mission-status-hud'),
          children: [
            Expanded(
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label:
                    'Base ${snapshot.baseHealth} of ${snapshot.startingBaseHealth}',
                child: _BaseHealthAnchor(
                  snapshot: snapshot,
                  uiTheme: uiTheme,
                  textScaler: textScaler,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label: 'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}',
                child: _MissionStatusAnchor(
                  snapshot: snapshot,
                  uiTheme: uiTheme,
                  textScaler: textScaler,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label: 'Credits ${snapshot.gold}',
                child: _CreditsAnchor(
                  snapshot: snapshot,
                  uiTheme: uiTheme,
                  textScaler: textScaler,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaseHealthAnchor extends StatelessWidget {
  const _BaseHealthAnchor({
    required this.snapshot,
    required this.uiTheme,
    required this.textScaler,
  });

  final GameSnapshot snapshot;
  final OrionUiTheme uiTheme;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final fraction = snapshot.startingBaseHealth == 0
        ? 0.0
        : (snapshot.baseHealth / snapshot.startingBaseHealth)
              .clamp(0.0, 1.0)
              .toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: uiTheme.systemCyan, size: 18),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${snapshot.baseHealth}/${snapshot.startingBaseHealth}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: textScaler,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: uiTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            key: const ValueKey('base-health-fill-track'),
            height: 4,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: ColoredBox(
                color: uiTheme.panelRaised,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: ColoredBox(
                      key: const ValueKey('base-health-fill'),
                      color: baseHealthColor(snapshot, uiTheme),
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

class _MissionStatusAnchor extends StatelessWidget {
  const _MissionStatusAnchor({
    required this.snapshot,
    required this.uiTheme,
    required this.textScaler,
  });

  final GameSnapshot snapshot;
  final OrionUiTheme uiTheme;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final phaseLabel = snapshot.isPaused
        ? 'Paused'
        : switch (snapshot.phase) {
            GamePhase.build => 'Build',
            GamePhase.wave => 'Wave Active',
            GamePhase.won => 'Won',
            GamePhase.lost => 'Lost',
          };

    return Tooltip(
      message: snapshot.stageName,
      excludeFromSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              snapshot.stageLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: textScaler,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: uiTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    '${snapshot.waveNumber}/${snapshot.waveTotal}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: textScaler,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: uiTheme.systemCyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox.square(
                  dimension: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: snapshot.isPaused
                          ? uiTheme.warningOrange
                          : uiTheme.systemCyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    phaseLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: textScaler,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: snapshot.isPaused
                          ? uiTheme.warningOrange
                          : uiTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditsAnchor extends StatelessWidget {
  const _CreditsAnchor({
    required this.snapshot,
    required this.uiTheme,
    required this.textScaler,
  });

  final GameSnapshot snapshot;
  final OrionUiTheme uiTheme;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: uiTheme.creditGold,
            size: 18,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${snapshot.gold}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: textScaler,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: uiTheme.creditGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MissionPacingStrip extends StatelessWidget {
  const MissionPacingStrip({
    super.key,
    required this.snapshot,
    required this.onTogglePause,
    required this.onSpeedSelected,
    required this.onToggleAutoStart,
  });

  final GameSnapshot snapshot;
  final VoidCallback onTogglePause;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onToggleAutoStart;

  @override
  Widget build(BuildContext context) {
    final canUsePacing = !snapshot.isEnded;
    final canTogglePause =
        canUsePacing &&
        (snapshot.phase == GamePhase.wave ||
            snapshot.autoStartCountdownRemaining != null ||
            snapshot.isPaused);
    final countdown = snapshot.autoStartCountdownRemaining;
    final autoSemanticsLabel = countdown == null
        ? 'Auto-start waves'
        : 'Auto-start waves, ${countdown.ceil()} seconds';

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              tooltip: snapshot.isPaused ? 'Resume' : 'Pause',
              onPressed: canTogglePause ? onTogglePause : null,
              icon: Icon(snapshot.isPaused ? Icons.play_arrow : Icons.pause),
            ),
            const SizedBox(width: 4),
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<double>(value: 1.0, label: Text('1x')),
                ButtonSegment<double>(value: 2.0, label: Text('2x')),
                ButtonSegment<double>(value: 3.0, label: Text('3x')),
              ],
              selected: {snapshot.speedMultiplier},
              onSelectionChanged: canUsePacing
                  ? (selection) => onSpeedSelected(selection.single)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: orionMotionDuration(
            context,
            const Duration(milliseconds: 160),
          ),
          child: Semantics(
            key: ValueKey(autoSemanticsLabel),
            container: true,
            button: true,
            enabled: canUsePacing,
            label: autoSemanticsLabel,
            onTap: canUsePacing ? onToggleAutoStart : null,
            child: Tooltip(
              message: 'Auto-start waves',
              excludeFromSemantics: true,
              child: ExcludeSemantics(
                child: FilterChip(
                  label: Text(
                    countdown == null ? 'Auto' : 'Auto ${countdown.ceil()}s',
                  ),
                  selected: snapshot.autoStartEnabled,
                  onSelected: canUsePacing ? (_) => onToggleAutoStart() : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth.isFinite ? maxWidth - 12 : double.infinity,
              ),
              child: CommandFrame(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                color: OrionUiTheme.of(context).hullBlack,
                borderColor: OrionUiTheme.of(context).frameSteel,
                child: Material(
                  type: MaterialType.transparency,
                  child: controls,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
