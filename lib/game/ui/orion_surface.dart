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
  ///
  /// Deliberately unused in `lib/` today: the command deck is inset 12px on
  /// all sides, so nothing in the current layout is edge to edge, and forcing
  /// it would make [OrionSurface.topBorderOnly] draw a border that stops short
  /// of the screen. Kept rather than deleted because the system sheet ships
  /// four tiers and the in-battle scenes still to be built are where a shelf
  /// would appear; the blur tripwire, not this member's use, is what keeps a
  /// fifth value from creeping in.
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
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: tier.blur, sigmaY: tier.blur),
        child: DecoratedBox(
          decoration: _tierDecoration(
            context,
            tier: tier,
            borderRadius: borderRadius,
            topBorderOnly: topBorderOnly,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The same tier chrome as [OrionSurface], with no blur.
///
/// For a surface nested inside one that is already blurred — a rail tile in a
/// blurred rail. Blurring a child of a blurred container is the anti-pattern
/// orion_surface.dart names ("blur the container rather than each child"), and
/// it is what pushed the mission scene to roughly 13 concurrent blurs against
/// a documented budget of 5-9. Visually it is near-indistinguishable, because
/// the parent has already blurred everything behind it.
class OrionInnerSurface extends StatelessWidget {
  const OrionInnerSurface({
    super.key,
    required this.tier,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
  });

  final OrionSurfaceTier tier;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: _tierDecoration(
        context,
        tier: tier,
        borderRadius: borderRadius,
        topBorderOnly: false,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Fill, gradient and border for [tier] — shared so the blurred and flat
/// surfaces cannot drift apart.
BoxDecoration _tierDecoration(
  BuildContext context, {
  required OrionSurfaceTier tier,
  required BorderRadius borderRadius,
  required bool topBorderOnly,
}) {
  {
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

    return BoxDecoration(
      color: color,
      gradient: gradient,
      borderRadius: borderRadius,
      border: topBorderOnly
          ? Border(top: BorderSide(color: borderColor))
          : Border.fromBorderSide(BorderSide(color: borderColor)),
    );
  }
}
