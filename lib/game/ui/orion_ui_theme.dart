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
  final Color textDim;

  final Color systemCyan;
  final Color systemCyanStrong;
  final Color creditGold;
  final Color actionAmber;

  final Color systemViolet;
  final Color naniteGreen;
  final Color warningOrange;
  final Color dangerRed;
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

const orionTextShadow = Shadow(
  color: Color(0xE605080D),
  offset: Offset(0, 1),
  blurRadius: 4,
);

const orionPanelFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF15222F), Color(0xFF0C141D)],
);

const orionPanelEdge = Color(0xFF2A4256);

const orionPanelGlint = Color(0x298CE1FF);

const orionPanelShadow = [
  BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 22),
];

const orionBracketCyan = Color(0xBF46E6FF);

const orionCardFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF172532), Color(0xFF0F1922)],
);

const orionCardEdge = Color(0xFF253A4C);

const orionCardLip = Color(0xFF060A0F);

const orionCardGlint = Color(0x0FFFFFFF);

const orionFloatingEdge = Color(0xFF34506A);

const orionShelfFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF101B26), Color(0xFF070C12)],
);

const orionShelfEdge = Color(0xFF22384A);

const orionPrimaryFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFE493), Color(0xFFFFBB3D), Color(0xFFFF9A1F)],
  stops: [0, .52, 1],
);

const orionPrimaryLip = Color(0xFFA3570A);

const orionPrimaryGlow = Color(0x61FFA01E);

const orionPrimaryInk = Color(0xFF2B1600);

const orionPrimaryGlint = Color(0xBFFFFFFF);

const orionPrimaryShade = Color(0x59964600);
const orionPrimaryShadePressed = Color(0x66964600);

const orionSecondaryFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF9AF6FF), Color(0xFF3CD8F5), Color(0xFF14B2E2)],
  stops: [0, .52, 1],
);

const orionSecondaryLip = Color(0xFF0A6380);

const orionSecondaryGlow = Color(0x4D1EC8F0);

const orionSecondaryInk = Color(0xFF03141B);

const orionSecondaryGlint = Color(0xB3FFFFFF);

const orionDangerFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF3A1820), Color(0xFF241015)],
);

const orionDangerEdge = Color(0xFF8A2A3A);

const orionDangerLip = Color(0xFF12070A);

const orionDangerInk = Color(0xFFFFE9EC);

const orionDangerGlint = Color(0x2EFF788C);

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

const orionChromePlate = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0E1822), Color(0xFF070C12)],
);

const orionGhostFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF1C2C3A), Color(0xFF111C27)],
);

const orionGhostEdge = Color(0x1F8FB4D8);

const orionGhostLip = Color(0xFF070D14);

const orionChipFill = Color(0xD10A121A);

const orionArtFrame = Color(0xFF3A5A74);

const orionPipEmpty = Color(0xFF2A3A48);

const orionRouteDim = Color(0xFF5F7487);

const orionWordmarkMid = Color(0xFFDDf8FF);

const orionWordmarkLip = Color(0xE604283C);

const orionWordmarkFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFFFFF), orionWordmarkMid, Color(0xFF46E6FF)],
  stops: [0, .45, 1],
);

const orionTitleShade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x6603070C), Color(0x4D03070C), Color(0xF003070C)],
  stops: [0, .45, 1],
);

const orionMapScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x0005080D),
    Color(0x0005080D),
    Color(0xF205080D),
    Color(0xF205080D),
  ],
  stops: [0, 0.6, 0.72, 1],
);

const orionMapVignette = RadialGradient(
  center: Alignment(0, -0.2),
  radius: 1.2,
  colors: [Color(0x0005080D), Color(0x8C05080D)],
);

const orionTechTreeScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x5505080D),
    Color(0x2205080D),
    Color(0x6605080D),
    Color(0xCC05080D),
  ],
  stops: [0, 0.28, 0.72, 1],
);

const orionScannerScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x8005080D), Color(0x3305080D), Color(0xCC05080D)],
);

const orionBriefingDeployFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF7FF0FF), Color(0xFF13B8E6), Color(0xFF0A7EA3)],
  stops: [0, 0.6, 1],
);

const orionHexOwnShell = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFD5C7FF), Color(0xFF7A5CE6)],
);

const orionHexOwnCore = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF2A2150), Color(0xFF17122E)],
);

const orionHexAvailShell = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF8AF4FF), Color(0xFF13B2E2)],
);

const orionHexAvailCore = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF123042), Color(0xFF0A1822)],
);

const orionHexLockCore = Color(0xFF0C141D);

const orionLockDesaturate = ColorFilter.mode(
  Color(0xFF9E9E9E),
  BlendMode.saturation,
);

const orionHexLockBadge = Color(0xFF0E1822);

const orionHexCheckInk = Color(0xFF17122E);

const orionBarDamage = LinearGradient(
  colors: [Color(0xFFFF5D6C), Color(0xFFFF8A9A)],
);

const orionBarFire = LinearGradient(
  colors: [Color(0xFFFFB534), Color(0xFFFFE08A)],
);

const orionBarRange = LinearGradient(
  colors: [Color(0xFF13B8E6), Color(0xFF46E6FF)],
);

const orionBarSecondary = LinearGradient(
  colors: [Color(0xFF7A5CE6), Color(0xFFD5C7FF)],
);
