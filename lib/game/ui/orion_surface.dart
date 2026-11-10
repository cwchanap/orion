import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

enum OrionSurfaceRole { floating, card, sheet, shelf }

/// Solid, framed, rounded chrome. Pure presentation: no gestures, animation,
/// or semantics of its own.
///
/// Solid primary actions (WAVE, DEPLOY) deliberately do not use this.
class OrionSurface extends StatelessWidget {
  const OrionSurface({
    super.key,
    required this.role,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 18,
    this.topBorderOnly = false,
  });

  final OrionSurfaceRole role;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 14–20 for cards, 22 for pills. Circles use [BoxShape.circle] elsewhere.
  final double radius;

  /// The shelf's tray is edged along its top side only.
  final bool topBorderOnly;

  @override
  Widget build(BuildContext context) {
    final t = OrionUiTheme.of(context);
    final borderRadius = BorderRadius.circular(radius);
    final panel = Container(
      padding: padding,
      decoration: _roleDecoration(
        role,
        theme: t,
        borderRadius: borderRadius,
        topBorderOnly: topBorderOnly,
      ),
      child: child,
    );

    final glint = switch (role) {
      OrionSurfaceRole.card => orionCardGlint,
      OrionSurfaceRole.sheet => orionPanelGlint,
      _ => null,
    };
    if (glint == null && role != OrionSurfaceRole.sheet) return panel;
    return CustomPaint(
      foregroundPainter: _SurfaceChromePainter(
        borderRadius: borderRadius,
        inset: _borderWidth,
        glintColor: glint,
        brackets: role == OrionSurfaceRole.sheet,
      ),
      child: panel,
    );
  }
}

const _borderWidth = 1.5;

/// Fill, edge and shadow per [OrionSurfaceRole].
BoxDecoration _roleDecoration(
  OrionSurfaceRole role, {
  required OrionUiTheme theme,
  required BorderRadius borderRadius,
  required bool topBorderOnly,
}) {
  Border border(Color color) => topBorderOnly
      ? Border(
          top: BorderSide(color: color, width: _borderWidth),
        )
      : Border.fromBorderSide(BorderSide(color: color, width: _borderWidth));

  return switch (role) {
    OrionSurfaceRole.floating => BoxDecoration(
      color: theme.hullBlack.withValues(alpha: .88),
      borderRadius: borderRadius,
      border: border(orionFloatingEdge),
      boxShadow: [
        BoxShadow(color: theme.voidBlack, offset: const Offset(0, 3)),
      ],
    ),
    OrionSurfaceRole.card => BoxDecoration(
      gradient: orionCardFill,
      borderRadius: borderRadius,
      border: border(orionCardEdge),
      boxShadow: const [BoxShadow(color: orionCardLip, offset: Offset(0, 3))],
    ),
    OrionSurfaceRole.sheet => BoxDecoration(
      gradient: orionPanelFill,
      borderRadius: borderRadius,
      border: border(orionPanelEdge),
      boxShadow: orionPanelShadow,
    ),
    OrionSurfaceRole.shelf => BoxDecoration(
      gradient: orionShelfFill,
      borderRadius: borderRadius,
      border: border(orionShelfEdge),
    ),
  };
}

class OrionInsetEdgePainter extends CustomPainter {
  const OrionInsetEdgePainter({
    required this.borderRadius,
    this.topColor,
    this.topWidth = 0,
    this.bottomColor,
    this.bottomWidth = 0,
    this.inset = 0,
  });

  final BorderRadius borderRadius;
  final Color? topColor;
  final double topWidth;
  final Color? bottomColor;
  final double bottomWidth;

  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = borderRadius.toRRect(rect).deflate(inset);
    final bounds = inner.outerRect;
    canvas.save();
    canvas.clipRRect(inner);
    if (topColor != null && topWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, topWidth),
        Paint()..color = topColor!,
      );
    }
    if (bottomColor != null && bottomWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          bounds.left,
          bounds.bottom - bottomWidth,
          bounds.width,
          bottomWidth,
        ),
        Paint()..color = bottomColor!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OrionInsetEdgePainter old) =>
      old.borderRadius != borderRadius ||
      old.topColor != topColor ||
      old.topWidth != topWidth ||
      old.bottomColor != bottomColor ||
      old.bottomWidth != bottomWidth ||
      old.inset != inset;
}

class _SurfaceChromePainter extends CustomPainter {
  const _SurfaceChromePainter({
    required this.borderRadius,
    required this.inset,
    required this.glintColor,
    required this.brackets,
  });

  final BorderRadius borderRadius;
  final double inset;
  final Color? glintColor;
  final bool brackets;

  static const _arm = 18.0;
  static const _armWidth = 2.0;
  static const _cornerOffset = 10.0;
  static const _bracketOutset = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (glintColor != null) {
      final inner = borderRadius.toRRect(rect).deflate(inset);
      final bounds = inner.outerRect;
      canvas.save();
      canvas.clipRRect(inner);
      canvas.drawRect(
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, 1),
        Paint()..color = glintColor!,
      );
      canvas.restore();
    }
    if (brackets) {
      _paintBrackets(canvas, rect.inflate(_bracketOutset));
    }
  }

  void _paintBrackets(Canvas canvas, Rect r) {
    final paint = Paint()..color = orionBracketCyan;
    for (final (dx, dy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      final fromRight = dx == 1;
      final fromBottom = dy == 1;
      final x = fromRight
          ? r.right - _cornerOffset - _arm
          : r.left + _cornerOffset;
      final y = fromBottom
          ? r.bottom - _cornerOffset - _arm
          : r.top + _cornerOffset;
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          fromBottom ? r.bottom - _armWidth : r.top,
          _arm,
          _armWidth,
        ),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          fromRight ? r.right - _armWidth : r.left,
          y,
          _armWidth,
          _arm,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SurfaceChromePainter old) =>
      old.borderRadius != borderRadius ||
      old.inset != inset ||
      old.glintColor != glintColor ||
      old.brackets != brackets;
}
