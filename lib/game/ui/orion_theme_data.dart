import 'package:flutter/material.dart';

import 'orion_ui_theme.dart';

/// The Revamp palette as a Material [ColorScheme].
///
/// Kept in lockstep with [OrionUiTheme.dark]: the extension is what Orion's
/// own widgets read, and this is the same palette expressed in the roles
/// Material components look up.
final ColorScheme _orionColorScheme = ColorScheme.dark(
  primary: OrionUiTheme.dark.systemCyan,
  onPrimary: OrionUiTheme.dark.voidBlack,
  primaryContainer: OrionUiTheme.dark.systemCyanStrong,
  onPrimaryContainer: OrionUiTheme.dark.voidBlack,
  secondary: OrionUiTheme.dark.systemViolet,
  onSecondary: OrionUiTheme.dark.voidBlack,
  secondaryContainer: OrionUiTheme.dark.panelRaised,
  onSecondaryContainer: OrionUiTheme.dark.textPrimary,
  tertiary: OrionUiTheme.dark.creditGold,
  onTertiary: OrionUiTheme.dark.voidBlack,
  error: OrionUiTheme.dark.dangerRed,
  onError: OrionUiTheme.dark.voidBlack,
  surface: OrionUiTheme.dark.panelBlue,
  onSurface: OrionUiTheme.dark.textPrimary,
  // Material derives disabled and unselected states from onSurfaceVariant.
  // textMuted is the palette's answer for "readable but secondary", so an
  // unselected pacing segment reads as an available choice rather than as
  // an empty box.
  onSurfaceVariant: OrionUiTheme.dark.textMuted,
  surfaceContainerHighest: OrionUiTheme.dark.panelRaised,
  outline: OrionUiTheme.dark.frameSteel,
  outlineVariant: OrionUiTheme.dark.frameSteel,
);

/// The app's Material theme.
///
/// Shared rather than built inline in `main`, because Material components the
/// game still uses take their colours and face from here — a widget test that
/// pumps a bare [MaterialApp] renders them against Flutter's defaults, which
/// is how off-palette component colours went unnoticed.
final ThemeData orionThemeData = ThemeData(
  colorScheme: _orionColorScheme,
  // Material *components* (button labels, dialog text, segmented controls,
  // ...) never read OrionTypography and so never picked up the Revamp faces;
  // they rendered in Roboto beside migrated Oxanium and ChakraPetch text.
  // OrionTypography's roles set their own fontFamily explicitly (see
  // orion_typography.dart), so they are unaffected by this default.
  fontFamily: 'ChakraPetch',
  extensions: const [OrionUiTheme.dark],
  useMaterial3: true,
);
