import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'game/ui/orion_game_page.dart';
import 'game/ui/orion_ui_theme.dart';

void main() {
  _registerFontLicenses();
  runApp(const OrionApp());
}

/// `assets/fonts/` ships Oxanium and ChakraPetch under the OFL, which
/// requires the licence to accompany the distributed font. Registering them
/// here is what actually ships them in the binary that embeds the fonts —
/// declaring the .txt files as assets alone does not surface them anywhere.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final oxanium = await rootBundle.loadString('assets/fonts/OFL-Oxanium.txt');
    yield LicenseEntryWithLineBreaks(['Oxanium'], oxanium);
    final chakraPetch = await rootBundle.loadString(
      'assets/fonts/OFL-ChakraPetch.txt',
    );
    yield LicenseEntryWithLineBreaks(['ChakraPetch'], chakraPetch);
  });
}

class OrionApp extends StatelessWidget {
  const OrionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF31E6A1),
          brightness: Brightness.dark,
        ),
        // Material *components* (button labels, dialog text, segmented
        // controls, ...) never read OrionTypography and so never picked up
        // the Revamp faces; they rendered in Roboto beside migrated Oxanium
        // and ChakraPetch text. OrionTypography's roles set their own
        // fontFamily explicitly (see orion_typography.dart), so they are
        // unaffected by this default.
        fontFamily: 'ChakraPetch',
        extensions: const [OrionUiTheme.dark],
        useMaterial3: true,
      ),
      home: const OrionGamePage(),
    );
  }
}
