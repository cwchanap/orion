import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// What kind of chrome the kit wraps this surface in.
///
/// The vocabulary comes from kit.css rather than a numbered scale: a surface
/// picks the kit treatment its content plays on the artboards, and no other
/// chrome exists to choose between.
enum OrionSurfaceRole {
  /// Floating control on live art: radial chips, back buttons, toasts,
  /// collapsed scanners. The battle artboard's 42px fab — `rgba(11,17,24,.88)`
  /// over a 1.5px `#34506A` edge with a `0 3px 0` drop lip.
  floating,

  /// Content card: rail tiles, stat cards, option plates. kit.css `.card` —
  /// 1.5px `#253A4C` edge, `#172532 → #0F1922` fill, quiet top glint and a
  /// `0 3px 0` bottom lip.
  card,

  /// A sheet or drawer that deliberately covers the scene. kit.css
  /// `.panel.br` — 1.5px `#2A4256` edge, `#15222F → #0C141D` fill, the lit
  /// top edge, the panel drop shadow and the restrained cyan corner brackets.
  sheet,

  /// The full-width dock tray — the one surface that spans edge to edge.
  /// `#101B26 → #070C12` with only a `#22384A` top edge; pair with
  /// [OrionSurface.topBorderOnly].
  shelf,
}

/// Solid, framed, rounded chrome. Pure presentation: no gestures, animation,
/// or semantics of its own.
///
/// Every role is opaque or near-opaque — the art stays visible *behind* a
/// panel, never *through* it. Solid primary actions (WAVE, DEPLOY)
/// deliberately do not use this; they are buttons.
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

    // Chrome that cannot live in a BoxDecoration: the kit's inset lit edge
    // (a CSS inner shadow) and, on sheets, the .br corner brackets that ride
    // just outside the frame.
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

/// Fill, edge and shadow per [OrionSurfaceRole] — the kit's `.panel`, `.card`,
/// fab and tray treatments verbatim from the reference table.
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

/// Paints a kit inset edge band — the lit top edge every framed piece
/// carries, or a bottom shade — clipped inside the rounded frame. CSS
/// `inset` shadows have no [BoxDecoration] equivalent, so surfaces and
/// buttons share this painter for them.
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

  /// How far inside the frame the band starts — pass the frame's border
  /// width so the band sits under the chrome, not on it.
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(borderRadius.toRRect(rect).deflate(inset));
    if (topColor != null && topWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, topWidth),
        Paint()..color = topColor!,
      );
    }
    if (bottomColor != null && bottomWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - bottomWidth, size.width, bottomWidth),
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

/// A sheet's chrome: the lit top edge plus the `.br` corner brackets —
/// eight 18×2 arms offset 10px from each corner, outset 2px so they ride
/// just outside the frame, drawn as solid strips like the kit's
/// `::after` elements.
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
      canvas.save();
      canvas.clipRRect(borderRadius.toRRect(rect).deflate(inset));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, 1),
        Paint()..color = glintColor!,
      );
      canvas.restore();
    }
    if (brackets) {
      _paintBrackets(canvas, rect.inflate(_bracketOutset));
    }
  }

  void _paintBrackets(Canvas canvas, Rect r) {
    // kit.css paints each arm as a solid `linear-gradient(var(--c), var(--c))`
    // strip — a flat color, not a fade — positioned like `top 0 left 10px /
    // 18px 2px` on the outset (::after inset:-2px) rect.
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
