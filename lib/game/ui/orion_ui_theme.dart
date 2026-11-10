import 'package:flutter/material.dart';

@immutable
final class OrionUiTheme extends ThemeExtension<OrionUiTheme> {
  const OrionUiTheme({
    required this.voidBlack,
    required this.sheetBlack,
    required this.hullBlack,
    required this.panelBlue,
    required this.panelRaised,
    required this.frameSteel,
    required this.textPrimary,
    required this.textMuted,
    required this.textDim,
    required this.systemCyan,
    required this.systemCyanStrong,
    required this.creditGold,
    required this.actionAmber,
    required this.systemViolet,
    required this.naniteGreen,
    required this.warningOrange,
    required this.dangerRed,
    required this.medalBronze,
    required this.medalSilver,
  });

  static const dark = OrionUiTheme(
    voidBlack: Color(0xFF05080D),
    sheetBlack: Color(0xFF080D13),
    hullBlack: Color(0xFF0B1118),
    panelBlue: Color(0xFF111B25),
    panelRaised: Color(0xFF182532),
    frameSteel: Color(0xFF2E4658),
    textPrimary: Color(0xFFF4F8FB),
    // kit.css --muted; the older #8EA4B5 read dimmer than the kit's label
    // role, so the role follows the kit value now.
    textMuted: Color(0xFF9DB2C3),
    textDim: Color(0xFF5F7487),
    systemCyan: Color(0xFF46E6FF),
    systemCyanStrong: Color(0xFF13B8E6),
    creditGold: Color(0xFFFFC857),
    actionAmber: Color(0xFFFFA62B),
    systemViolet: Color(0xFFA98BFF),
    naniteGreen: Color(0xFF7BE495),
    warningOrange: Color(0xFFFF8A3D),
    dangerRed: Color(0xFFFF5D6C),
    medalBronze: Color(0xFFD9925A),
    medalSilver: Color(0xFFCFDBE6),
  );

  final Color voidBlack;
  final Color sheetBlack;
  final Color hullBlack;
  final Color panelBlue;
  final Color panelRaised;
  final Color frameSteel;
  final Color textPrimary;
  final Color textMuted;

  /// kit.css `--dim`: secondary labels, separators and de-emphasized rows —
  /// one step below [textMuted].
  final Color textDim;

  final Color systemCyan;
  final Color systemCyanStrong;
  final Color creditGold;

  /// kit.css `--amber`: the one dominant action on a surface (WAVE, DEPLOY).
  /// The button chrome consumes [orionPrimaryFill]; this role is for the
  /// amber accents elsewhere.
  final Color actionAmber;

  final Color systemViolet;
  final Color naniteGreen;
  final Color warningOrange;
  final Color dangerRed;

  /// Medal ranks from the report artboard; gold medals reuse [creditGold].
  final Color medalBronze;
  final Color medalSilver;

  static OrionUiTheme of(BuildContext context) =>
      Theme.of(context).extension<OrionUiTheme>() ?? dark;

  @override
  OrionUiTheme copyWith({
    Color? voidBlack,
    Color? sheetBlack,
    Color? hullBlack,
    Color? panelBlue,
    Color? panelRaised,
    Color? frameSteel,
    Color? textPrimary,
    Color? textMuted,
    Color? textDim,
    Color? systemCyan,
    Color? systemCyanStrong,
    Color? creditGold,
    Color? actionAmber,
    Color? systemViolet,
    Color? naniteGreen,
    Color? warningOrange,
    Color? dangerRed,
    Color? medalBronze,
    Color? medalSilver,
  }) {
    return OrionUiTheme(
      voidBlack: voidBlack ?? this.voidBlack,
      sheetBlack: sheetBlack ?? this.sheetBlack,
      hullBlack: hullBlack ?? this.hullBlack,
      panelBlue: panelBlue ?? this.panelBlue,
      panelRaised: panelRaised ?? this.panelRaised,
      frameSteel: frameSteel ?? this.frameSteel,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      textDim: textDim ?? this.textDim,
      systemCyan: systemCyan ?? this.systemCyan,
      systemCyanStrong: systemCyanStrong ?? this.systemCyanStrong,
      creditGold: creditGold ?? this.creditGold,
      actionAmber: actionAmber ?? this.actionAmber,
      systemViolet: systemViolet ?? this.systemViolet,
      naniteGreen: naniteGreen ?? this.naniteGreen,
      warningOrange: warningOrange ?? this.warningOrange,
      dangerRed: dangerRed ?? this.dangerRed,
      medalBronze: medalBronze ?? this.medalBronze,
      medalSilver: medalSilver ?? this.medalSilver,
    );
  }

  @override
  OrionUiTheme lerp(covariant OrionUiTheme? other, double t) {
    if (other == null) return this;
    return OrionUiTheme(
      voidBlack: Color.lerp(voidBlack, other.voidBlack, t)!,
      sheetBlack: Color.lerp(sheetBlack, other.sheetBlack, t)!,
      hullBlack: Color.lerp(hullBlack, other.hullBlack, t)!,
      panelBlue: Color.lerp(panelBlue, other.panelBlue, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      frameSteel: Color.lerp(frameSteel, other.frameSteel, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      systemCyan: Color.lerp(systemCyan, other.systemCyan, t)!,
      systemCyanStrong: Color.lerp(
        systemCyanStrong,
        other.systemCyanStrong,
        t,
      )!,
      creditGold: Color.lerp(creditGold, other.creditGold, t)!,
      actionAmber: Color.lerp(actionAmber, other.actionAmber, t)!,
      systemViolet: Color.lerp(systemViolet, other.systemViolet, t)!,
      naniteGreen: Color.lerp(naniteGreen, other.naniteGreen, t)!,
      warningOrange: Color.lerp(warningOrange, other.warningOrange, t)!,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t)!,
      medalBronze: Color.lerp(medalBronze, other.medalBronze, t)!,
      medalSilver: Color.lerp(medalSilver, other.medalSilver, t)!,
    );
  }
}

/// The shared text shadow every [TextStyle] role carries, so contrast never
/// depends on a surface fill. One literal, one home.
const orionTextShadow = Shadow(
  color: Color(0xE605080D),
  offset: Offset(0, 1),
  blurRadius: 4,
);

// ---- kit.css surface tokens -------------------------------------------------
// Exact transcriptions from the reference table in the design spec; every
// surface and button consumes these rather than re-declaring values.

/// `.panel`: `linear-gradient(180deg, #15222F 0%, #0C141D 100%)`.
const orionPanelFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF15222F), Color(0xFF0C141D)],
);

/// `.panel` frame: `1.5px solid #2A4256`.
const orionPanelEdge = Color(0xFF2A4256);

/// `.panel`'s lit top edge: `inset 0 1px 0 rgba(140,225,255,.16)`.
const orionPanelGlint = Color(0x298CE1FF);

/// `.panel` drop shadow: `0 8px 22px rgba(0,0,0,.5)`.
const orionPanelShadow = [
  BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 22),
];

/// `.panel.br` corner-bracket arms: `rgba(70,230,255,.75)`.
const orionBracketCyan = Color(0xBF46E6FF);

/// `.card`: `linear-gradient(180deg, #172532, #0F1922)`.
const orionCardFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF172532), Color(0xFF0F1922)],
);

/// `.card` frame: `1.5px solid #253A4C`.
const orionCardEdge = Color(0xFF253A4C);

/// `.card` bottom lip: `0 3px 0 #060A0F`.
const orionCardLip = Color(0xFF060A0F);

/// `.card`'s quiet top glint: `inset 0 1px 0 rgba(255,255,255,.06)`.
const orionCardGlint = Color(0x0FFFFFFF);

/// The 42px fab frame from the battle artboards: `1.5px #34506A` over a
/// `0 3px 0 #05080D` lip on `rgba(11,17,24,.88)` (hullBlack at .88).
const orionFloatingEdge = Color(0xFF34506A);

/// The dock tray: `linear-gradient(180deg,#101B26,#070C12)`.
const orionShelfFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF101B26), Color(0xFF070C12)],
);

/// The dock tray's only edge: `border-top 1.5px #22384A`.
const orionShelfEdge = Color(0xFF22384A);

// ---- kit.css button tokens --------------------------------------------------

/// `.btn.primary` fill: `linear-gradient(180deg,#FFE493 0%,#FFBB3D 52%,
/// #FF9A1F 100%)`.
const orionPrimaryFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFE493), Color(0xFFFFBB3D), Color(0xFFFF9A1F)],
  stops: [0, .52, 1],
);

/// `.btn.primary` bottom lip: `0 5px 0 #A3570A` (sinks to `0 1px 0` pressed).
const orionPrimaryLip = Color(0xFFA3570A);

/// `.btn.primary` glow: `0 10px 24px rgba(255,160,30,.38)`.
const orionPrimaryGlow = Color(0x61FFA01E);

/// `.btn.primary` text: `#2B1600`.
const orionPrimaryInk = Color(0xFF2B1600);

/// `.btn.primary` lit top edge: `inset 0 1.5px 0 rgba(255,255,255,.75)`.
const orionPrimaryGlint = Color(0xBFFFFFFF);

/// `.btn.primary` bottom shade: `inset 0 -2px 0 rgba(150,70,0,.35)` —
/// `rgba(150,70,0,.4)` pressed.
const orionPrimaryShade = Color(0x59964600);
const orionPrimaryShadePressed = Color(0x66964600);

/// `.btn.secondary` fill: `linear-gradient(180deg,#9AF6FF 0%,#3CD8F5 52%,
/// #14B2E2 100%)`.
const orionSecondaryFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF9AF6FF), Color(0xFF3CD8F5), Color(0xFF14B2E2)],
  stops: [0, .52, 1],
);

/// `.btn.secondary` bottom lip: `0 5px 0 #0A6380`.
const orionSecondaryLip = Color(0xFF0A6380);

/// `.btn.secondary` glow: `0 10px 22px rgba(30,200,240,.3)`.
const orionSecondaryGlow = Color(0x4D1EC8F0);

/// `.btn.secondary` text: `#03141B`.
const orionSecondaryInk = Color(0xFF03141B);

/// `.btn.secondary` lit top edge: `inset 0 1.5px 0 rgba(255,255,255,.7)`.
const orionSecondaryGlint = Color(0xB3FFFFFF);

/// `.btn.danger` fill: `linear-gradient(180deg,#3A1820,#241015)`.
const orionDangerFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF3A1820), Color(0xFF241015)],
);

/// `.btn.danger` frame: `1.5px solid #8A2A3A`.
const orionDangerEdge = Color(0xFF8A2A3A);

/// `.btn.danger` bottom lip: `0 4px 0 #12070A`.
const orionDangerLip = Color(0xFF12070A);

/// `.btn.danger` text: `#FFE9EC`.
const orionDangerInk = Color(0xFFFFE9EC);

/// `.btn.danger` lit top edge: `inset 0 1px 0 rgba(255,120,140,.18)`.
const orionDangerGlint = Color(0x2EFF788C);

/// The disabled rule's lip: `0 5px 0 #222` under `grayscale(1)
/// brightness(.55)`, which ColorFiltered applies for real.
const orionDisabledLip = Color(0xFF222222);

Duration orionMotionDuration(BuildContext context, Duration normal) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;

/// Motion durations from the Revamp system sheet (scene 1i). Route each through
/// [orionMotionDuration] at the call site so `disableAnimationsOf` still wins.
const orionPressDuration = Duration(milliseconds: 90);
const orionSheetDuration = Duration(milliseconds: 220);
const orionLaneFlowDuration = Duration(milliseconds: 1100);
const orionHullPulseDuration = Duration(milliseconds: 2400);
const orionIdleBobDuration = Duration(milliseconds: 1600);

AnimationStyle? orionSheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null;
