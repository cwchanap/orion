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
