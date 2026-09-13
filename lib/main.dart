import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'game/ui/orion_game_page.dart';
import 'game/ui/orion_theme_data.dart';

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
      theme: orionThemeData,
      home: const OrionGamePage(),
    );
  }
}
