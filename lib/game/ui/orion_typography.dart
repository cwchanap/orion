import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'orion_ui_theme.dart';

/// Type roles from the Revamp system sheet (scene 1i): two faces, three roles.
///
/// Oxanium carries every numeral and the single screen title; Chakra Petch
/// carries every label. Nothing in the game UI reads Material's [TextTheme].
abstract final class OrionTypography {
  /// Shadow applied to all roles so contrast never depends on a surface fill.
  static const shadow = orionTextShadow;

  static const _oxaniumFallback = ['ChakraPetch'];

  /// Resource, hull, wave, cost and count numerals. The sheet's hero range is
  /// 22–40; smaller sizes are the same role used inline.
  static TextStyle readout({double size = 24, required Color color}) =>
      TextStyle(
        fontFamily: 'Oxanium',
        fontFamilyFallback: _oxaniumFallback,
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
    fontFamilyFallback: _oxaniumFallback,
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
  static TextStyle microLabel({Color? color, double size = 10}) {
    assert(
      size >= 10,
      'microLabel has a 10px floor; the kit scale has no '
      'legible label below it.',
    );
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
      letterSpacing: size * 0.10,
      color: resolved,
      shadows: const [shadow],
    );
  }
}

/// The screen title, set in caps.
///
/// The caps are presentational: [data] is kept verbatim as the semantics
/// label, so assistive tech announces "Outpost Alpha" rather than spelling
/// out a shouted string, and the visible Text is excluded from the tree.
/// Call sites therefore pass normal copy — never a pre-uppercased literal.
class OrionTitle extends StatelessWidget {
  const OrionTitle(
    this.data, {
    super.key,
    required this.color,
    this.size = 15,
    this.shadows,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.textScaler,
  });

  final String data;
  final Color color;
  final double size;

  final List<Shadow>? shadows;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    final style = OrionTypography.title(color: color, size: size);
    final resolved = shadows == null ? style : style.copyWith(shadows: shadows);
    final upper = data.toUpperCase();
    final plainTitle = Text(
      upper,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      textScaler: textScaler,
      style: resolved,
    );
    Widget title = plainTitle;
    if (maxLines == null && overflow == null) {
      final words = upper.split(' ');
      if (words.length <= 1) {
        title = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: switch (textAlign) {
            TextAlign.right || TextAlign.end => Alignment.centerRight,
            TextAlign.center => Alignment.center,
            _ => Alignment.centerLeft,
          },
          child: plainTitle,
        );
      } else {
        title = _AdaptiveMultiWordTitle(
          upper: upper,
          words: words,
          style: resolved,
          textAlign: textAlign,
          textScaler: textScaler ?? MediaQuery.textScalerOf(context),
          plainTitle: plainTitle,
        );
      }
    }
    return Semantics(
      label: data,
      child: ExcludeSemantics(child: title),
    );
  }
}

class _AdaptiveMultiWordTitle extends StatefulWidget {
  const _AdaptiveMultiWordTitle({
    required this.upper,
    required this.words,
    required this.style,
    required this.textAlign,
    required this.textScaler,
    required this.plainTitle,
  });

  final String upper;
  final List<String> words;
  final TextStyle style;
  final TextAlign? textAlign;
  final TextScaler textScaler;
  final Widget plainTitle;

  @override
  State<_AdaptiveMultiWordTitle> createState() =>
      _AdaptiveMultiWordTitleState();
}

class _AdaptiveMultiWordTitleState extends State<_AdaptiveMultiWordTitle> {
  TextDirection? _measuredDirection;
  double _widestWord = 0;
  double _spaceWidth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureIfNeeded();
  }

  @override
  void didUpdateWidget(_AdaptiveMultiWordTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upper != widget.upper ||
        oldWidget.style != widget.style ||
        oldWidget.textScaler != widget.textScaler) {
      _measuredDirection = null;
      _measureIfNeeded();
    }
  }

  void _measureIfNeeded() {
    final direction = Directionality.of(context);
    if (_measuredDirection == direction) return;
    _measuredDirection = direction;
    final painter = TextPainter(
      textDirection: direction,
      textScaler: widget.textScaler,
    );
    try {
      var widest = 0.0;
      for (final word in widget.words) {
        painter
          ..text = TextSpan(text: word, style: widget.style)
          ..layout();
        if (painter.width > widest) widest = painter.width;
      }
      painter
        ..text = TextSpan(text: ' ', style: widget.style)
        ..layout();
      _widestWord = widest;
      _spaceWidth = painter.width;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return _IntrinsicTitleBuilder(
      upper: widget.upper,
      style: widget.style,
      textScaler: widget.textScaler,
      textDirection: direction,
      textAlign: widget.textAlign,
      builder: (context, constraints) {
        if (constraints.maxWidth.isInfinite ||
            _widestWord <= constraints.maxWidth) {
          return widget.plainTitle;
        }
        return Wrap(
          alignment: switch (widget.textAlign) {
            TextAlign.right || TextAlign.end => WrapAlignment.end,
            TextAlign.center => WrapAlignment.center,
            _ => WrapAlignment.start,
          },
          spacing: _spaceWidth,
          runSpacing: 4,
          children: [
            for (final word in widget.words)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  word,
                  textScaler: widget.textScaler,
                  style: widget.style,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IntrinsicTitleBuilder extends ConstrainedLayoutBuilder<BoxConstraints> {
  const _IntrinsicTitleBuilder({
    required super.builder,
    required this.upper,
    required this.style,
    required this.textScaler,
    required this.textDirection,
    required this.textAlign,
  });

  final String upper;
  final TextStyle style;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final TextAlign? textAlign;

  @override
  RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox>
  createRenderObject(BuildContext context) => _RenderIntrinsicTitleBuilder(
    upper,
    style,
    textScaler,
    textDirection,
    textAlign,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderIntrinsicTitleBuilder renderObject,
  ) {
    renderObject
      ..upper = upper
      ..style = style
      ..textScaler = textScaler
      ..textDirection = textDirection
      ..textAlign = textAlign;
  }
}

class _RenderIntrinsicTitleBuilder extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox> {
  _RenderIntrinsicTitleBuilder(
    this._upper,
    this._style,
    this._textScaler,
    this._textDirection,
    this._textAlign,
  );

  String _upper;
  TextStyle _style;
  TextScaler _textScaler;
  TextDirection _textDirection;
  TextAlign? _textAlign;
  TextPainter? _intrinsicPainter;

  set upper(String value) {
    if (_upper == value) return;
    _upper = value;
    _intrinsicPainter?.text = TextSpan(text: _upper, style: _style);
    markNeedsLayout();
  }

  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _intrinsicPainter?.text = TextSpan(text: _upper, style: _style);
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _intrinsicPainter?.textScaler = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _intrinsicPainter?.textDirection = value;
    markNeedsLayout();
  }

  set textAlign(TextAlign? value) {
    if (_textAlign == value) return;
    _textAlign = value;
    _intrinsicPainter?.textAlign = value ?? TextAlign.start;
    markNeedsLayout();
  }

  TextPainter get _painter => _intrinsicPainter ??= TextPainter(
    text: TextSpan(text: _upper, style: _style),
    textAlign: _textAlign ?? TextAlign.start,
    textDirection: _textDirection,
    textScaler: _textScaler,
  );

  @override
  void dispose() {
    _intrinsicPainter?.dispose();
    _intrinsicPainter = null;
    super.dispose();
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final painter = _painter..layout();
    return painter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final painter = _painter..layout();
    return painter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final painter = _painter..layout(maxWidth: width);
    return painter.height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final painter = _painter
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    return constraints.constrain(painter.size);
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final painter = _painter
      ..layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    return painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  void performLayout() {
    runLayoutCallback();
    child?.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(child?.size ?? Size.zero);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      child?.getDistanceToActualBaseline(baseline) ??
      super.computeDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;
}

/// A micro-label. Exists so call sites read as intent, not as styling.
class OrionText extends StatelessWidget {
  const OrionText.micro(this.data, {super.key, this.color, this.size = 10});

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
            style: OrionTypography.readout(size: size * 0.45, color: muted),
          ),
      ],
    );
  }
}
