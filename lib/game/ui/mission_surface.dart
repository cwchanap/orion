import 'package:flutter/material.dart';

import 'orion_surface.dart';

/// Rounded mission chrome primitive.
///
/// Pure presentation: no gestures, animation, painter, or semantics of its
/// own.
@Deprecated(
  'Use OrionSurface with an explicit tier. This adapter exists so the 15 '
  'pre-Revamp call sites convert incrementally; delete it in PR D.',
)
class MissionSurface extends StatelessWidget {
  const MissionSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.radius = 18,
    this.emphasized = false,
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool emphasized;

  /// Ignored. The tier now owns all chrome; kept only so existing call
  /// sites still compile while they convert to [OrionSurface] directly.
  final Color? backgroundColor;

  /// Ignored. The tier now owns all chrome; kept only so existing call
  /// sites still compile while they convert to [OrionSurface] directly.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => OrionSurface(
    tier: emphasized ? OrionSurfaceTier.t3 : OrionSurfaceTier.t2,
    padding: padding,
    radius: radius,
    child: child,
  );
}
