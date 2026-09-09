import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the Flutter SDK's real Roboto — and by default the Material icon —
/// fonts so text uses production metrics. The host test harness otherwise
/// falls back to 1em-per-glyph placeholder glyphs, which cannot expose real
/// truncation.
Future<void> loadRealFonts({bool withMaterialIcons = true}) async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is not set; cannot load real Roboto metrics.');
  }
  final loader = FontLoader('Roboto');
  for (final file in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final fontFile = File('$root/bin/cache/artifacts/material_fonts/$file');
    if (!fontFile.existsSync()) fail('Missing SDK font: ${fontFile.path}');
    final bytes = fontFile.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();

  for (final family in const {
    'Oxanium': ['Oxanium[wght].ttf'],
    'ChakraPetch': ['ChakraPetch-Bold.ttf'],
  }.entries) {
    final familyLoader = FontLoader(family.key);
    for (final fileName in family.value) {
      final file = File('assets/fonts/$fileName');
      if (!file.existsSync()) fail('Missing project font: ${file.path}');
      familyLoader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
    await familyLoader.load();
  }

  if (!withMaterialIcons) return;
  final iconFile = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!iconFile.existsSync()) fail('Missing SDK font: ${iconFile.path}');
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
  await iconLoader.load();
}
