import 'package:flutter/material.dart';

import '../models/game_models.dart';
import 'mission_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

Color baseHealthColor(GameSnapshot snapshot, OrionUiTheme uiTheme) {
  final fraction = snapshot.startingBaseHealth == 0
      ? 0.0
      : snapshot.baseHealth / snapshot.startingBaseHealth;
  if (fraction > 0.50) return uiTheme.systemCyan;
  if (fraction > 0.25) return uiTheme.warningOrange;
  return uiTheme.dangerRed;
}

/// Single source for the visible (and semantic) mission phase label, so the
/// HUD's semantics carry the same Build/Wave Active/Paused/Won/Lost state the
/// player sees.
String _missionPhaseLabel(GameSnapshot snapshot) => snapshot.isPaused
    ? 'Paused'
    : switch (snapshot.phase) {
        GamePhase.build => 'Build',
        GamePhase.wave => 'Wave Active',
        GamePhase.won => 'Won',
        GamePhase.lost => 'Lost',
      };

class MissionStatusHud extends StatelessWidget {
  const MissionStatusHud({super.key, required this.snapshot});

  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);

    return Wrap(
      key: const ValueKey('mission-status-hud'),
      spacing: 4,
      runSpacing: 4,
      children: [
        Semantics(
          container: true,
          excludeSemantics: true,
          label:
              'Base ${snapshot.baseHealth} of ${snapshot.startingBaseHealth}',
          child: MissionSurface(
            key: const ValueKey('mission-status-base'),
            child: _BaseHealthAnchor(
              snapshot: snapshot,
              uiTheme: uiTheme,
              textScaler: textScaler,
            ),
          ),
        ),
        Semantics(
          container: true,
          excludeSemantics: true,
          label:
              '${snapshot.stageName}. '
              'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, '
              '${_missionPhaseLabel(snapshot)}',
          child: MissionSurface(
            key: const ValueKey('mission-status-stage'),
            child: _MissionStatusAnchor(
              snapshot: snapshot,
              uiTheme: uiTheme,
              textScaler: textScaler,
            ),
          ),
        ),
        Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Credits ${snapshot.gold}',
          child: MissionSurface(
            key: const ValueKey('mission-status-credits'),
            child: _CreditsAnchor(
              snapshot: snapshot,
              uiTheme: uiTheme,
              textScaler: textScaler,
            ),
          ),
        ),
      ],
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

    // ponytail: fixed-width fill track so the anchor shrink-wraps without
    // intrinsic-width queries (IntrinsicWidth + width:infinity asserts under
    // unbounded-height ancestors, e.g. Stack positioned overlays).
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: uiTheme.systemCyan, size: 18),
            const SizedBox(width: 4),
            Flexible(
              child: OrionReadout(
                value: '${snapshot.baseHealth}',
                denominator: '${snapshot.startingBaseHealth}',
                color: uiTheme.textPrimary,
                size: 16,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: textScaler,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          key: const ValueKey('base-health-fill-track'),
          height: 4,
          width: 72,
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
    final phaseLabel = _missionPhaseLabel(snapshot);

    return Tooltip(
      message: snapshot.stageName,
      excludeFromSemantics: true,
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
            style: OrionTypography.microLabel(color: uiTheme.textMuted),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: OrionReadout(
                  value: '${snapshot.waveNumber}',
                  denominator: '${snapshot.waveTotal}',
                  color: uiTheme.systemCyan,
                  size: 14,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: textScaler,
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
                  style: OrionTypography.microLabel(
                    color: snapshot.isPaused
                        ? uiTheme.warningOrange
                        : uiTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
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
            style: OrionTypography.readout(size: 16, color: uiTheme.creditGold),
          ),
        ),
      ],
    );
  }
}

/// Pause + visible 1x/2x/3x speeds + auto-start. Frameless by design: the
/// idle command dock owns the painted surface, so the controls shrink-wrap
/// inside its [MissionSurface] and the dock keeps the tap-arbiter contract.
class MissionPacingControls extends StatelessWidget {
  const MissionPacingControls({
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

    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          IconButton.filledTonal(
            tooltip: snapshot.isPaused ? 'Resume' : 'Pause',
            onPressed: canTogglePause ? onTogglePause : null,
            icon: Icon(snapshot.isPaused ? Icons.play_arrow : Icons.pause),
          ),
          _SpeedCycleButton(
            speed: snapshot.speedMultiplier,
            onSelected: canUsePacing ? onSpeedSelected : null,
          ),
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
                    // Tighter chip insets keep pause + speeds + auto on one
                    // row inside the idle dock at the product width; the
                    // chip keeps its default 48dp hit height.
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text(
                      countdown == null ? 'Auto' : 'Auto ${countdown.ceil()}s',
                    ),
                    selected: snapshot.autoStartEnabled,
                    onSelected: canUsePacing
                        ? (_) => onToggleAutoStart()
                        : null,
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

/// Mission speed as one button that cycles 1x -> 2x -> 3x -> 1x.
///
/// A three-segment control costs three 48dp touch targets (144px). At the
/// product width the idle dock has 248px for pacing and needs 249.5 with the
/// segments, so it wrapped onto a second row over the board — and the
/// auto-start countdown label ("Auto 5s") widens that further. Segments
/// cannot shrink below the touch floor, so the control had to stop costing
/// three of them. One button costs 48px and leaves real headroom.
///
/// Every speed stays reachable, and the artboard shows a single speed button
/// rather than a segmented control, so this also moves toward the sheet.
class _SpeedCycleButton extends StatelessWidget {
  const _SpeedCycleButton({required this.speed, required this.onSelected});

  final double speed;

  /// Null while pacing is unavailable, which disables the button.
  final ValueChanged<double>? onSelected;

  static const List<double> _cycle = [1, 2, 3];

  double get _next {
    final index = _cycle.indexOf(speed);
    // An unrecognised speed restarts the cycle rather than throwing.
    return index == -1 ? _cycle.first : _cycle[(index + 1) % _cycle.length];
  }

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final onSelected = this.onSelected;
    final label = '${speed.toStringAsFixed(0)}x';
    final next = '${_next.toStringAsFixed(0)}x';
    return Semantics(
      button: true,
      enabled: onSelected != null,
      // The bare label would announce "2x" with no hint that it changes, so
      // the semantics say what the control is and what a tap does.
      label: 'Game speed $label, tap for $next',
      onTap: onSelected == null ? null : () => onSelected(_next),
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Game speed',
          excludeFromSemantics: true,
          child: OutlinedButton(
            onPressed: onSelected == null ? null : () => onSelected(_next),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              side: BorderSide(color: uiTheme.frameSteel),
              shape: const StadiumBorder(),
            ),
            child: Text(
              label,
              style: OrionTypography.microLabel(
                size: 11,
                color: speed > 1 ? uiTheme.systemCyan : uiTheme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
