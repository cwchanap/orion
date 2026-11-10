import 'package:flutter/material.dart';
import 'orion_surface.dart';
import 'orion_typography.dart';
import 'orion_ui_theme.dart';

/// The kit's `.btn` variants: one dominant amber action per surface, a
/// supporting cyan action, and the destructive action.
enum OrionButtonVariant { primary, secondary, danger }

typedef _VariantSpec = ({
  Gradient fill,
  Color? edge,
  Color lip,
  double lipHeight,
  Color ink,
  Color? glow,
  double glowBlur,
  Color? glint,
  Color? shade,
});

/// The kit's solid framed action — lip, glint and press — shared by
/// full-screen scene actions.
///
/// Press sinks the whole control 4px onto a 1px lip, routed through
/// [orionMotionDuration] so reduced motion snaps instead of tweening.
/// Disabled follows the kit's grayscale rule; [loading] shows a busy glyph
/// and renders the action inert without losing its semantics.
class OrionPrimaryButton extends StatefulWidget {
  const OrionPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = OrionButtonVariant.primary,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final OrionButtonVariant variant;

  /// In-flight state: the glyph replaces the icon and the button stops
  /// firing, so a tap cannot queue a second action.
  final bool loading;

  @override
  State<OrionPrimaryButton> createState() => _OrionPrimaryButtonState();
}

class _OrionPrimaryButtonState extends State<OrionPrimaryButton> {
  /// Physical press tracked by pointer events rather than the inner button's
  /// states controller — a Listener observes taps without joining the
  /// TextButton's gesture arena or semantics.
  var _pressed = false;

  static const _radius = 14.0;

  /// kit.css `grayscale(1) brightness(.55)` as a ColorFilter matrix: the
  /// luminance row, scaled by .55, applied to every channel.
  static const _disabledFilter = ColorFilter.matrix([
    .1173,
    .3934,
    .0399,
    0,
    0,
    .1173,
    .3934,
    .0399,
    0,
    0,
    .1173,
    .3934,
    .0399,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  _VariantSpec _spec() => switch (widget.variant) {
    OrionButtonVariant.primary => (
      fill: orionPrimaryFill,
      edge: null,
      lip: orionPrimaryLip,
      lipHeight: 5,
      ink: orionPrimaryInk,
      glow: orionPrimaryGlow,
      glowBlur: 24,
      glint: orionPrimaryGlint,
      shade: orionPrimaryShade,
    ),
    OrionButtonVariant.secondary => (
      fill: orionSecondaryFill,
      edge: null,
      lip: orionSecondaryLip,
      lipHeight: 5,
      ink: orionSecondaryInk,
      glow: orionSecondaryGlow,
      glowBlur: 22,
      glint: orionSecondaryGlint,
      shade: null,
    ),
    OrionButtonVariant.danger => (
      fill: orionDangerFill,
      edge: orionDangerEdge,
      lip: orionDangerLip,
      lipHeight: 4,
      ink: orionDangerInk,
      glow: null,
      glowBlur: 0,
      glint: orionDangerGlint,
      shade: null,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final spec = _spec();
    // A null onPressed or an in-flight load renders the kit's disabled rule;
    // the TextButton keeps the null onPressed either way so semantics stay
    // honest about the control being inert.
    final enabled = widget.onPressed != null && !widget.loading;
    final borderRadius = BorderRadius.circular(_radius);
    final pressed = enabled && _pressed;
    final sink = pressed ? 4.0 : 0.0;
    final lipHeight = enabled ? (pressed ? 1.0 : spec.lipHeight) : 5.0;
    final lipColor = enabled ? spec.lip : orionDisabledLip;
    Widget frame = AnimatedContainer(
      duration: orionMotionDuration(context, orionPressDuration),
      transform: Matrix4.translationValues(0, sink, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: spec.fill,
        border: spec.edge == null
            ? null
            : Border.fromBorderSide(BorderSide(color: spec.edge!, width: 1.5)),
        boxShadow: [
          BoxShadow(color: lipColor, offset: Offset(0, lipHeight)),
          if (enabled && !pressed && spec.glow != null)
            BoxShadow(
              color: spec.glow!,
              offset: const Offset(0, 10),
              blurRadius: spec.glowBlur,
            ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: OrionInsetEdgePainter(
          borderRadius: borderRadius,
          inset: spec.edge == null ? 0 : 1.5,
          topColor: spec.glint,
          topWidth: spec.glint == null ? 0 : 1.5,
          // Pressed trades the resting shade for the kit's deeper inset
          // shadow (`inset 0 2px 4px rgba(150,70,0,.4)`); only the amber
          // variant carries a bottom shade at all.
          bottomColor: pressed && spec.shade == orionPrimaryShade
              ? orionPrimaryShadePressed
              : spec.shade,
          bottomWidth: spec.shade == null ? 0 : (pressed ? 4 : 2),
        ),
        child: TextButton.icon(
          onPressed: enabled ? widget.onPressed : null,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            foregroundColor: spec.ink,
            disabledForegroundColor: spec.ink,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
          ),
          icon: widget.loading
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: spec.ink,
                  ),
                )
              : Icon(widget.icon, size: 24),
          label: Text(
            widget.label,
            style: OrionTypography.microLabel(size: 13, color: spec.ink),
          ),
        ),
      ),
    );
    if (!enabled) {
      frame = ColorFiltered(colorFilter: _disabledFilter, child: frame);
    }
    return Listener(
      onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      child: frame,
    );
  }
}
