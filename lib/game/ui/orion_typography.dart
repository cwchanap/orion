import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// Type roles from the Revamp system sheet (scene 1i): two faces, three roles.
///
/// Oxanium carries every numeral and the single screen title; Chakra Petch
/// carries every label. Nothing in the game UI reads Material's [TextTheme].
abstract final class OrionTypography {
  /// Shadow applied to all roles so contrast never depends on a surface fill.
  static const shadow = Shadow(
    color: Color(0xE605080D),
    offset: Offset(0, 1),
    blurRadius: 4,
  );

  /// Resource, hull, wave, cost and count numerals. The sheet's hero range is
  /// 22–40; smaller sizes are the same role used inline.
  static TextStyle readout({double size = 24, required Color color}) =>
      TextStyle(
        fontFamily: 'Oxanium',
        fontVariations: const [FontVariation('wght', 800)],
        fontSize: size,
        height: 1,
        color: color,
        shadows: const [shadow],
      );

  /// The one title per screen.
  static TextStyle title({required Color color}) => TextStyle(
    fontFamily: 'Oxanium',
    fontVariations: const [FontVariation('wght', 800)],
    fontSize: 15,
    height: 1,
    letterSpacing: 1.2,
    color: color,
    shadows: const [shadow],
  );

  /// Every label. Muted by construction: the sheet says "muted, never white".
  static TextStyle microLabel({Color? color, double size = 8}) {
    final resolved = color ?? OrionUiTheme.dark.textMuted;
    if (resolved == OrionUiTheme.dark.textPrimary) {
      throw ArgumentError.value(
        color,
        'color',
        'microLabel is muted-only; the system sheet forbids white labels.',
      );
    }
    return TextStyle(
      fontFamily: 'ChakraPetch',
      fontWeight: FontWeight.w700,
      fontSize: size,
      letterSpacing: size * 0.18,
      color: resolved,
      shadows: const [shadow],
    );
  }
}

/// A micro-label. Exists so call sites read as intent, not as styling.
class OrionText extends StatelessWidget {
  const OrionText.micro(this.data, {super.key, this.color, this.size = 8});

  final String data;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    data,
    style: OrionTypography.microLabel(color: color, size: size),
  );
}

/// A numeric readout with an optional muted denominator.
///
/// The denominator is structurally smaller and muted, so the sheet's rule —
/// "never two full-size numbers" — cannot be violated by a caller.
class OrionReadout extends StatelessWidget {
  const OrionReadout({
    super.key,
    required this.value,
    required this.color,
    this.denominator,
    this.size = 24,
  });

  final String value;
  final Color color;
  final String? denominator;
  final double size;

  @override
  Widget build(BuildContext context) {
    final muted = OrionUiTheme.of(context).textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: OrionTypography.readout(size: size, color: color),
        ),
        if (denominator != null)
          Text(
            '/$denominator',
            style: OrionTypography.readout(size: size * 0.45, color: muted),
          ),
      ],
    );
  }
}
