import 'package:flutter/material.dart';

@immutable
final class OrionUiTheme extends ThemeExtension<OrionUiTheme> {
  const OrionUiTheme({
    required this.voidBlack,
    required this.hullBlack,
    required this.panelBlue,
    required this.panelRaised,
    required this.frameSteel,
    required this.textPrimary,
    required this.textMuted,
    required this.systemCyan,
    required this.systemCyanStrong,
    required this.creditGold,
    required this.systemViolet,
    required this.naniteGreen,
    required this.warningOrange,
    required this.dangerRed,
  });

  static const dark = OrionUiTheme(
    voidBlack: Color(0xFF05080D),
    hullBlack: Color(0xFF0B1118),
    panelBlue: Color(0xFF111B25),
    panelRaised: Color(0xFF182532),
    frameSteel: Color(0xFF2E4658),
    textPrimary: Color(0xFFF4F8FB),
    textMuted: Color(0xFF8EA4B5),
    systemCyan: Color(0xFF46E6FF),
    systemCyanStrong: Color(0xFF13B8E6),
    creditGold: Color(0xFFFFC857),
    systemViolet: Color(0xFFA98BFF),
    naniteGreen: Color(0xFF7BE495),
    warningOrange: Color(0xFFFF8A3D),
    dangerRed: Color(0xFFFF5D6C),
  );

  final Color voidBlack;
  final Color hullBlack;
  final Color panelBlue;
  final Color panelRaised;
  final Color frameSteel;
  final Color textPrimary;
  final Color textMuted;
  final Color systemCyan;
  final Color systemCyanStrong;
  final Color creditGold;
  final Color systemViolet;
  final Color naniteGreen;
  final Color warningOrange;
  final Color dangerRed;

  static OrionUiTheme of(BuildContext context) =>
      Theme.of(context).extension<OrionUiTheme>() ?? dark;

  @override
  OrionUiTheme copyWith({
    Color? voidBlack,
    Color? hullBlack,
    Color? panelBlue,
    Color? panelRaised,
    Color? frameSteel,
    Color? textPrimary,
    Color? textMuted,
    Color? systemCyan,
    Color? systemCyanStrong,
    Color? creditGold,
    Color? systemViolet,
    Color? naniteGreen,
    Color? warningOrange,
    Color? dangerRed,
  }) {
    return OrionUiTheme(
      voidBlack: voidBlack ?? this.voidBlack,
      hullBlack: hullBlack ?? this.hullBlack,
      panelBlue: panelBlue ?? this.panelBlue,
      panelRaised: panelRaised ?? this.panelRaised,
      frameSteel: frameSteel ?? this.frameSteel,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      systemCyan: systemCyan ?? this.systemCyan,
      systemCyanStrong: systemCyanStrong ?? this.systemCyanStrong,
      creditGold: creditGold ?? this.creditGold,
      systemViolet: systemViolet ?? this.systemViolet,
      naniteGreen: naniteGreen ?? this.naniteGreen,
      warningOrange: warningOrange ?? this.warningOrange,
      dangerRed: dangerRed ?? this.dangerRed,
    );
  }

  @override
  OrionUiTheme lerp(covariant OrionUiTheme? other, double t) {
    if (other == null) return this;
    return OrionUiTheme(
      voidBlack: Color.lerp(voidBlack, other.voidBlack, t)!,
      hullBlack: Color.lerp(hullBlack, other.hullBlack, t)!,
      panelBlue: Color.lerp(panelBlue, other.panelBlue, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      frameSteel: Color.lerp(frameSteel, other.frameSteel, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      systemCyan: Color.lerp(systemCyan, other.systemCyan, t)!,
      systemCyanStrong: Color.lerp(
        systemCyanStrong,
        other.systemCyanStrong,
        t,
      )!,
      creditGold: Color.lerp(creditGold, other.creditGold, t)!,
      systemViolet: Color.lerp(systemViolet, other.systemViolet, t)!,
      naniteGreen: Color.lerp(naniteGreen, other.naniteGreen, t)!,
      warningOrange: Color.lerp(warningOrange, other.warningOrange, t)!,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t)!,
    );
  }
}

Duration orionMotionDuration(BuildContext context, Duration normal) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;

AnimationStyle? orionSheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null;
