import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// The four surface tiers from the Revamp system sheet (scene 1i).
///
/// Tier is an enum rather than a number so a fifth blur value — which the sheet
/// calls a bug — is unrepresentable. Budget 5–9 of these per screen, and blur
/// the container rather than each child: an eight-tile rail is one blurred row.
enum OrionSurfaceTier {
  /// Floating control on live art: radial, pacing, back, locked nodes, toasts.
  t1(7),

  /// Content card: rail tiles, stat/counter/spec cards, tech plates.
  t2(6),

  /// A sheet or drawer that deliberately covers the scene.
  t3(12),

  /// The full-width dock shelf — the one surface that spans edge to edge.
  t4(14);

  const OrionSurfaceTier(this.blur);

  final double blur;
}

/// Translucent, blurred, rounded chrome. Pure presentation: no gestures,
/// animation, or semantics of its own.
///
/// Solid primary actions (WAVE, DEPLOY) deliberately do not use this.
class OrionSurface extends StatelessWidget {
  const OrionSurface({
    super.key,
    required this.tier,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
    this.topBorderOnly = false,
  });

  final OrionSurfaceTier tier;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 14–20 for cards, 22 for pills. Circles use [BoxShape.circle] elsewhere.
  final double radius;

  /// t4's shelf is bordered along its top edge only.
  final bool topBorderOnly;

  @override
  Widget build(BuildContext context) {
    final t = OrionUiTheme.of(context);
    final (Gradient? gradient, Color? color) = switch (tier) {
      OrionSurfaceTier.t1 => (null, t.hullBlack.withValues(alpha: 0.55)),
      OrionSurfaceTier.t2 => (
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            t.panelRaised.withValues(alpha: 0.66),
            t.hullBlack.withValues(alpha: 0.76),
          ],
        ),
        null,
      ),
      OrionSurfaceTier.t3 => (
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            t.panelBlue.withValues(alpha: 0.90),
            t.sheetBlack.withValues(alpha: 0.94),
          ],
        ),
        null,
      ),
      OrionSurfaceTier.t4 => (
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            t.voidBlack.withValues(alpha: 0.50),
            t.voidBlack.withValues(alpha: 0.62),
          ],
        ),
        null,
      ),
    };

    final borderColor = switch (tier) {
      OrionSurfaceTier.t1 => t.systemCyan.withValues(alpha: 0.5),
      OrionSurfaceTier.t2 => t.frameSteel,
      OrionSurfaceTier.t3 => t.systemCyan.withValues(alpha: 0.3),
      OrionSurfaceTier.t4 => t.systemCyan.withValues(alpha: 0.14),
    };

    final borderRadius = BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: tier.blur, sigmaY: tier.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: borderRadius,
            border: topBorderOnly
                ? Border(top: BorderSide(color: borderColor))
                : Border.fromBorderSide(BorderSide(color: borderColor)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
