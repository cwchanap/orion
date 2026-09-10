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
  ///
  /// 15 is the chrome size — a title sharing a band with other controls.
  /// A sheet whose title *is* its hero (the stage briefing) passes a display
  /// [size]; the sheet's own briefing artboard sets that title far above the
  /// chrome step, and a single fixed size could not express both.
  /// Tracking scales with the size so the caps keep their measured rhythm.
  static TextStyle title({required Color color, double size = 15}) => TextStyle(
    fontFamily: 'Oxanium',
    fontVariations: const [FontVariation('wght', 800)],
    fontSize: size,
    height: 1,
    letterSpacing: size * 0.08,
    color: color,
    shadows: const [shadow],
  );

  /// Every label. Muted by construction: the sheet says "muted, never white".
  ///
  /// The sheet describes this role as a 7-9px range, but there is no role
  /// above [title] for a label bigger than that, so the migration also
  /// reaches for [microLabel] at larger sizes the sheet never wrote down.
  /// Each step below is deliberate and reviewed; this list exists so the
  /// next feature copies from it instead of picking a new number:
  ///
  ///  - 8 (the default) — the base label size for the tightest chrome:
  ///    tower-build cards, dock pills, chips, and other high-density
  ///    controls.
  ///  - 9 — supporting/secondary text one step up from the base: a subtitle
  ///    under a title (e.g. "Level 3 • Piercing") and feedback text.
  ///  - 10 — a card title with a little more room to read; currently only
  ///    the tech-tree node label inside its fixed-width card.
  ///  - 11 — section and detail labels inside expanded panels, and the
  ///    caption beside a numeral-heavy [readout] (e.g. "Targeting",
  ///    "SPECIALIZE - LV 4", a cost figure's label).
  ///  - 13 — a primary, tappable call-to-action label inside a t3 sheet
  ///    (e.g. the stage-briefing Launch/Retry button); the largest step,
  ///    reserved for the one label per sheet that reads as an action.
  ///
  /// Do not add a new size without updating this list.
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
    this.maxLines,
    this.overflow,
    this.textScaler,
  });

  final String value;
  final Color color;
  final String? denominator;
  final double size;

  /// Applied to both the value and denominator [Text]s, unset by default —
  /// matching a plain [Text] until a caller opts in (e.g. a constrained
  /// [Flexible] row that must ellipsize and honour text-size preferences).
  final int? maxLines;
  final TextOverflow? overflow;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    final muted = OrionUiTheme.of(context).textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Flexible, not a plain Text: the denominator is short and keeps its
        // natural width, so under a tight constraint (a Flexible ancestor at
        // small widths) it is the value that must be able to shrink and
        // ellipsize instead of the Row overflowing.
        Flexible(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: overflow,
            textScaler: textScaler,
            style: OrionTypography.readout(size: size, color: color),
          ),
        ),
        if (denominator != null)
          Text(
            '/$denominator',
            maxLines: maxLines,
            overflow: overflow,
            textScaler: textScaler,
            style: OrionTypography.readout(size: size * 0.62, color: muted),
          ),
      ],
    );
  }
}
