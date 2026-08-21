import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

Path commandFramePath(Size size, double chamfer) {
  final resolvedChamfer = chamfer.clamp(0.0, size.shortestSide / 2);
  return Path()
    ..moveTo(resolvedChamfer, 0)
    ..lineTo(size.width - resolvedChamfer, 0)
    ..lineTo(size.width, resolvedChamfer)
    ..lineTo(size.width, size.height - resolvedChamfer)
    ..lineTo(size.width - resolvedChamfer, size.height)
    ..lineTo(resolvedChamfer, size.height)
    ..lineTo(0, size.height - resolvedChamfer)
    ..lineTo(0, resolvedChamfer)
    ..close();
}

class CommandFrame extends StatelessWidget {
  const CommandFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.borderColor,
    this.emphasized = false,
    this.chamfer = 10,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final bool emphasized;
  final double chamfer;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    return CustomPaint(
      painter: _CommandFramePainter(
        color: color ?? uiTheme.hullBlack,
        borderColor: borderColor ?? uiTheme.frameSteel,
        strokeWidth: emphasized ? 2 : 1,
        chamfer: chamfer,
      ),
      child: ClipPath(
        clipper: _CommandFrameClipper(chamfer),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class ReactorButton extends StatelessWidget {
  const ReactorButton({
    super.key,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.size = 68,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uiTheme = OrionUiTheme.of(context);
    final enabled = onPressed != null;
    final resolvedSize = size < 48 ? 48.0 : size;
    final foreground = enabled ? uiTheme.textPrimary : uiTheme.textMuted;
    final accent = enabled ? uiTheme.systemCyan : uiTheme.frameSteel;

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: resolvedSize,
          child: CommandFrame(
            padding: const EdgeInsets.all(3),
            borderColor: accent,
            color: uiTheme.hullBlack,
            emphasized: enabled,
            chamfer: 12,
            child: CommandFrame(
              padding: EdgeInsets.zero,
              borderColor: accent.withValues(alpha: enabled ? 0.68 : 0.4),
              color: uiTheme.panelBlue,
              chamfer: 8,
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: onPressed,
                  containedInkWell: true,
                  highlightShape: BoxShape.rectangle,
                  splashColor: accent.withValues(alpha: 0.18),
                  highlightColor: accent.withValues(alpha: 0.10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: foreground, size: 22),
                        const SizedBox(height: 2),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.15),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
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

class _CommandFrameClipper extends CustomClipper<Path> {
  const _CommandFrameClipper(this.chamfer);

  final double chamfer;

  @override
  Path getClip(Size size) => commandFramePath(size, chamfer);

  @override
  bool shouldReclip(covariant _CommandFrameClipper oldClipper) =>
      oldClipper.chamfer != chamfer;
}

class _CommandFramePainter extends CustomPainter {
  const _CommandFramePainter({
    required this.color,
    required this.borderColor,
    required this.strokeWidth,
    required this.chamfer,
  });

  final Color color;
  final Color borderColor;
  final double strokeWidth;
  final double chamfer;

  @override
  void paint(Canvas canvas, Size size) {
    final path = commandFramePath(size, chamfer);
    canvas
      ..drawPath(path, Paint()..color = color)
      ..drawPath(
        path,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
  }

  @override
  bool shouldRepaint(covariant _CommandFramePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.chamfer != chamfer;
}
