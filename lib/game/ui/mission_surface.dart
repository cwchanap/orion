import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// Rounded, translucent mission chrome primitive.
///
/// Pure presentation: no gestures, animation, painter, or semantics of its
/// own. All colors come from [OrionUiTheme].
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
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = OrionUiTheme.of(context);
    final sideColor =
        borderColor ??
        (emphasized
            ? theme.systemCyanStrong
            : theme.systemCyan.withValues(alpha: 0.25));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.hullBlack.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(radius),
        border: Border.fromBorderSide(
          BorderSide(color: sideColor, width: emphasized ? 2 : 1),
        ),
        boxShadow: emphasized
            ? [
                BoxShadow(
                  color: theme.systemCyanStrong.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: padding,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      ),
    );
  }
}
