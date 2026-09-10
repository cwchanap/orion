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
/// The phase pair's colour. naniteGreen while building, per artboard 1a;
/// muted once the wave runs; warning orange while paused.
Color _phaseAccent(GameSnapshot snapshot, OrionUiTheme uiTheme) {
  if (snapshot.isPaused) return uiTheme.warningOrange;
  if (snapshot.phase == GamePhase.build) return uiTheme.naniteGreen;
  return uiTheme.textMuted;
}

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

    // Unboxed and spread, per artboard 1a: the status readouts float on the
    // live board rather than each sitting in its own pill. Every
    // OrionTypography role carries a shadow for exactly this — "contrast
    // never depends on a surface fill" — and dropping three pills' padding
    // buys back the width the hero-scale numerals need.
    //
    // spaceBetween is the arrangement, not decoration: the artboard pins hull
    // to the left edge, centres the wave group and pins credits to the right,
    // so the three readings are found by position rather than by reading
    // along a row. Still a Wrap, so a narrow viewport or a large text scale
    // reflows to a second run instead of overflowing; `spacing` is then the
    // minimum gap rather than the actual one.
    return Wrap(
      key: const ValueKey('mission-status-hud'),
      alignment: WrapAlignment.spaceBetween,
      spacing: 10,
      runSpacing: 6,
      children: [
        Semantics(
          container: true,
          excludeSemantics: true,
          label:
              'Base ${snapshot.baseHealth} of ${snapshot.startingBaseHealth}',
          child: _BaseHealthAnchor(
            key: const ValueKey('mission-status-base'),
            snapshot: snapshot,
            uiTheme: uiTheme,
            textScaler: textScaler,
          ),
        ),
        Semantics(
          container: true,
          excludeSemantics: true,
          label:
              '${snapshot.stageName}. '
              'Wave ${snapshot.waveNumber} of ${snapshot.waveTotal}, '
              '${_missionPhaseLabel(snapshot)}',
          child: _MissionStatusAnchor(
            key: const ValueKey('mission-status-stage'),
            snapshot: snapshot,
            uiTheme: uiTheme,
            textScaler: textScaler,
          ),
        ),
        Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Credits ${snapshot.gold}',
          child: _CreditsAnchor(
            key: const ValueKey('mission-status-credits'),
            snapshot: snapshot,
            uiTheme: uiTheme,
            textScaler: textScaler,
          ),
        ),
      ],
    );
  }
}

class _BaseHealthAnchor extends StatelessWidget {
  const _BaseHealthAnchor({
    super.key,
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
            Icon(Icons.shield_outlined, color: uiTheme.systemCyan, size: 22),
            const SizedBox(width: 4),
            Flexible(
              child: OrionReadout(
                value: '${snapshot.baseHealth}',
                denominator: '${snapshot.startingBaseHealth}',
                color: uiTheme.textPrimary,
                size: 26,
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
          width: 84,
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
    super.key,
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
      // Artboard 1a stacks the wave group: the count on top, the phase
      // centred beneath it. The stage name is not in the band at all there —
      // the band carries three numbers, not prose — so it stays in this
      // widget's tooltip and in the Semantics label its parent supplies.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          OrionReadout(
            value: '${snapshot.waveNumber}',
            denominator: '${snapshot.waveTotal}',
            color: uiTheme.systemCyan,
            size: 26,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: textScaler,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The artboard colours this pair by phase, not by chrome:
              // `BUILD` is naniteGreen with a green dot -- it is the state
              // that invites action -- and a running wave goes muted. Paused
              // keeps our warning orange, which the artboard has no state for.
              SizedBox.square(
                dimension: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _phaseAccent(snapshot, uiTheme),
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
                    color: _phaseAccent(snapshot, uiTheme),
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
    super.key,
    required this.snapshot,
    required this.uiTheme,
    required this.textScaler,
  });

  final GameSnapshot snapshot;
  final OrionUiTheme uiTheme;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    // Artboard order: the figure, then the credit mark -- "410 (hex)". The
    // number is what the player reads, so it leads.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${snapshot.gold}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: textScaler,
            textAlign: TextAlign.end,
            style: OrionTypography.readout(size: 26, color: uiTheme.creditGold),
          ),
        ),
        const SizedBox(width: 5),
        Icon(Icons.hexagon, color: uiTheme.creditGold, size: 19),
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
    final uiTheme = OrionUiTheme.of(context);
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
      // Artboard 1a's dock leads with three chips of one shape and size,
      // told apart by their accent rather than by their outline.
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _PacingChip(
            semanticsLabel: snapshot.isPaused ? 'Resume' : 'Pause',
            tooltip: snapshot.isPaused ? 'Resume' : 'Pause',
            icon: snapshot.isPaused ? Icons.play_arrow : Icons.pause,
            accent: uiTheme.systemCyan,
            active: snapshot.isPaused,
            onPressed: canTogglePause ? onTogglePause : null,
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
            child: _PacingChip(
              key: ValueKey(autoSemanticsLabel),
              semanticsLabel: autoSemanticsLabel,
              tooltip: 'Auto-start waves',
              icon: Icons.timer_outlined,
              label: countdown == null ? 'Auto' : 'Auto ${countdown.ceil()}s',
              accent: uiTheme.warningOrange,
              active: snapshot.autoStartEnabled,
              onPressed: canUsePacing ? onToggleAutoStart : null,
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
/// One dock pacing control, shaped as artboard 1a shapes all three: a 44dp
/// rounded square (radius 14) with a translucent hull fill and a 1px border
/// in the control's own accent — cyan for pacing, orange for auto-start.
/// The active control takes a tinted fill instead of a dark one.
///
/// Ours used to be three different Material widgets — a filled circular
/// IconButton, a stadium OutlinedButton and a rounded FilterChip — so the row
/// read as three unrelated controls. The visual square is 44dp per the
/// artboard; the tappable box stays 48dp.
class _PacingChip extends StatelessWidget {
  const _PacingChip({
    super.key,
    required this.semanticsLabel,
    required this.tooltip,
    required this.icon,
    required this.accent,
    required this.onPressed,
    this.label,
    this.active = false,
  });

  final String semanticsLabel;
  final String tooltip;
  final IconData icon;
  final Color accent;
  final VoidCallback? onPressed;
  final String? label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    final tint = enabled ? accent : uiTheme.frameSteel;
    final label = this.label;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          // 44dp square is the artboard's shape and this chip's minimum; the
          // auto-start chip widens while it counts down rather than clipping
          // its own label. The tappable box stays 48dp tall.
          // The artboard's 44dp is the visual; the tappable box holds a 48dp
          // minimum in both axes, and grows past it only for a long label.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            // widthFactor: a bare Center expands to the incoming maxWidth,
            // which made every chip claim the whole pacing row and stack the
            // three into their own Wrap runs.
            child: Center(
              widthFactor: 1,
              child: Material(
                color: active
                    ? tint.withValues(alpha: 0.14)
                    : uiTheme.hullBlack.withValues(alpha: 0.55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: tint.withValues(alpha: active ? 0.6 : 0.3),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkResponse(
                  onTap: onPressed,
                  containedInkWell: true,
                  highlightShape: BoxShape.rectangle,
                  splashColor: tint.withValues(alpha: 0.18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: label == null ? 19 : 15, color: tint),
                        if (label != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text(
                              label,
                              maxLines: 1,
                              style: OrionTypography.microLabel(
                                size: 7.5,
                                color: tint,
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
      ),
    );
  }
}

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
    // The artboard pairs a fast-forward glyph with the multiplier and tints
    // the chip while the speed is raised.
    return _PacingChip(
      // The bare label would announce "2x" with no hint that it changes, so
      // the semantics say what the control is and what a tap does.
      semanticsLabel: 'Game speed $label, tap for $next',
      tooltip: 'Game speed',
      icon: Icons.fast_forward_rounded,
      label: label,
      accent: uiTheme.systemCyan,
      active: speed > 1,
      onPressed: onSelected == null ? null : () => onSelected(_next),
    );
  }
}
