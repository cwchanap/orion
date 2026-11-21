import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

/// HPA-922 Task 5 asset contract, extended for HPA-924: every Last Hearth
/// roster member ships exactly three images under
/// `assets/images/characters/{id}/`. Portrait and chibi are addressable through
/// the shared `OrionArtDescriptor` registry — never through mockup screenshot
/// crops, a parallel path table, or a second image cache.
///
/// * `portrait.png`: 1024x1536 full-size card art, un-cropped.
/// * `face.png`: 512x512 fully opaque square face thumbnail. It has no runtime
///   `OrionArt` descriptor yet; HPA-926 wires it up.
/// * `chibi.png`: 512x512 RGBA full-body battle sprite with a fully
///   transparent 1px frame.
///
/// Flutter bundles each per-ID directory whole, so that directory may hold
/// nothing beyond these three files.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('per-ID character art contract', () {
    test('the roster still has exactly the 12 catalogued members', () {
      // The path table below is meaningless if the roster drifts.
      expect(Character.values, hasLength(12));
    });

    test('every member resolves portrait and chibi descriptors at its '
        'canonical per-ID paths', () {
      for (final character in Character.values) {
        final portrait = OrionArt.characterPortrait(character);
        expect(
          portrait.fileName,
          'characters/${character.name}/portrait.png',
          reason: character.name,
        );
        expect(
          portrait.semanticLabel,
          contains(character.displayName),
          reason: character.name,
        );

        final chibi = OrionArt.characterChibi(character);
        expect(
          chibi.fileName,
          'characters/${character.name}/chibi.png',
          reason: character.name,
        );
        expect(
          chibi.semanticLabel,
          contains(character.displayName),
          reason: character.name,
        );
      }
    });

    test('descriptors draw the full frame — no mockup-source crops', () {
      for (final character in Character.values) {
        for (final art in [
          OrionArt.characterPortrait(character),
          OrionArt.characterChibi(character),
        ]) {
          final rect = art.sourceRectFor(imageWidth: 640, imageHeight: 960);
          expect(
            rect,
            const ui.Rect.fromLTWH(0, 0, 640, 960),
            reason:
                '${character.name}/${art.fileName} must sample the whole '
                'approved frame',
          );
        }
      }
    });

    test(
      'each per-ID directory holds exactly portrait, face and chibi PNGs',
      () {
        for (final character in Character.values) {
          final dir = Directory('$_artRoot/${character.name}');
          expect(dir.existsSync(), isTrue, reason: '${dir.path} is missing');
          // Flutter bundles the whole folder, so any extra entry would ship.
          expect(
            [
              for (final entity in dir.listSync())
                entity.uri.pathSegments.lastWhere(
                  (segment) => segment.isNotEmpty,
                ),
            ],
            unorderedEquals(_artFiles),
            reason: '${character.name}/ must contain exactly $_artFiles',
          );
        }
      },
    );

    test('every per-ID PNG has the approved size and color type', () {
      for (final character in Character.values) {
        final name = character.name;
        final portrait = _pngInfo(_artFile('$name/portrait.png'));
        expect(
          (portrait.width, portrait.height),
          (1024, 1536),
          reason:
              '$name/portrait.png must be the full-size approved concept, '
              'not a crop',
        );

        final face = _pngInfo(_artFile('$name/face.png'));
        expect(
          (face.width, face.height),
          (512, 512),
          reason: '$name/face.png must be the 512px square face thumbnail',
        );

        final chibi = _pngInfo(_artFile('$name/chibi.png'));
        expect(
          (chibi.width, chibi.height),
          (512, 512),
          reason: '$name/chibi.png must be the paired 512px PNG',
        );
        expect(
          chibi.colorType,
          6,
          reason:
              '$name/chibi.png must keep its alpha channel (RGBA color type 6)',
        );
      }
    });

    test('every portrait fully decodes to a 1024x1536 frame', () async {
      for (final character in Character.values) {
        await _decodeFrame(
          '${character.name}/portrait.png',
          width: 1024,
          height: 1536,
        );
      }
    });

    test('every face fully decodes to an opaque 512x512 frame', () async {
      for (final character in Character.values) {
        final key = '${character.name}/face.png';
        await _decodeFrame(
          key,
          width: 512,
          height: 512,
          checkPixels: (rgba) => expect(
            _firstNonOpaquePixel(rgba, 512),
            isNull,
            reason: '$key must be fully opaque in every pixel',
          ),
        );
      }
    });

    test('every chibi fully decodes to a 512x512 frame with a transparent 1px '
        'border', () async {
      for (final character in Character.values) {
        final key = '${character.name}/chibi.png';
        await _decodeFrame(
          key,
          width: 512,
          height: 512,
          checkPixels: (rgba) => expect(
            _firstVisibleBorderPixel(rgba, 512, 512),
            isNull,
            reason: '$key must have a fully transparent 1px border',
          ),
        );
      }
    });

    test('provenance.json has exactly one entry per art file', () {
      final file = File('$_artRoot/provenance.json');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final decoded = jsonDecode(file.readAsStringSync());
      expect(
        decoded,
        isA<Map<String, dynamic>>(),
        reason: 'provenance.json must be a JSON object keyed by "{id}/{file}"',
      );
      final recorded = (decoded as Map<String, dynamic>).keys.toSet();
      final expected = _artKeys();
      expect(
        expected.difference(recorded),
        isEmpty,
        reason: 'provenance.json has no entry for these art files',
      );
      expect(
        recorded.difference(expected),
        isEmpty,
        reason: 'provenance.json has entries for files outside the contract',
      );
    });

    test('every face entry names its source portrait and crop rectangle', () {
      final decoded =
          jsonDecode(File('$_artRoot/provenance.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final character in Character.values) {
        final key = '${character.name}/face.png';
        final entry = decoded[key];
        expect(entry, isA<Map<String, dynamic>>(), reason: key);
        final record = entry as Map<String, dynamic>;
        expect(
          record['method'],
          'cropped',
          reason: '$key is produced by cropping the final portrait',
        );
        expect(
          record['source'],
          '${character.name}/portrait.png',
          reason: '$key must name the final portrait it was cropped from',
        );
        final crop = record['crop'];
        expect(
          crop,
          isA<Map<String, dynamic>>(),
          reason:
              '$key must record the source crop rectangle so a later '
              'portrait edit can be re-cropped deliberately',
        );
        final rect = crop as Map<String, dynamic>;
        final x = rect['x'], y = rect['y'], side = rect['side'];
        for (final (field, value) in [('x', x), ('y', y), ('side', side)]) {
          expect(value, isA<int>(), reason: '$key crop.$field must be an int');
        }
        expect(
          (x as int) >= 0 && (y as int) >= 0 && (side as int) > 0,
          isTrue,
          reason: '$key crop must be a non-empty source rectangle',
        );
        expect(
          x + side <= 1024 && y + side <= 1536,
          isTrue,
          reason:
              '$key crop ($x, $y, ${side}px) must fit inside the '
              '1024x1536 source portrait',
        );
      }
    });

    test(
      'the asset bundle ships all 36 art files but not provenance.json',
      () async {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        final bundled = manifest.listAssets().toSet();
        expect(
          {for (final key in _artKeys()) '$_artRoot/$key'}.difference(bundled),
          isEmpty,
          reason: 'these art files are missing from the Flutter asset bundle',
        );
        expect(
          bundled.contains('$_artRoot/provenance.json'),
          isFalse,
          reason: 'provenance.json is metadata and must not ship in the app',
        );
      },
    );

    test('every per-ID asset directory is registered in pubspec.yaml', () {
      final pubspecLines = File(
        'pubspec.yaml',
      ).readAsLinesSync().map((line) => line.trim());
      for (final character in Character.values) {
        expect(
          pubspecLines,
          contains('- assets/images/characters/${character.name}/'),
          reason:
              'assets/images/characters/${character.name}/ must be '
              'registered in pubspec.yaml',
        );
      }
    });
  });

  group('character art cache path', () {
    test('descriptors are process-lifetime singletons shared with the '
        'OrionArt registry', () {
      for (final character in Character.values) {
        expect(
          identical(
            OrionArt.characterChibi(character),
            OrionArt.characterChibi(character),
          ),
          isTrue,
          reason: character.name,
        );
        expect(
          identical(
            OrionArt.characterPortrait(character),
            OrionArt.characterPortrait(character),
          ),
          isTrue,
          reason: character.name,
        );
      }
    });

    test('resetSpriteCache drops the memoized character sprite', () {
      OrionArtDescriptor.resetSpriteCache();
      addTearDown(OrionArtDescriptor.resetSpriteCache);

      final descriptor = OrionArt.characterChibi(Character.haruto);
      final first = descriptor.sprite;
      OrionArtDescriptor.resetSpriteCache();
      final second = descriptor.sprite;
      expect(
        identical(first, second),
        isFalse,
        reason: 'the test reset must drop the memoized sprite future',
      );
    });

    test(
      'a failed load retries below the cap, then keeps the failure',
      () async {
        final descriptor = OrionArtDescriptor(
          fileName: 'characters/__missing__/chibi.png',
          sourceRectFor: ({required imageWidth, required imageHeight}) =>
              ui.Rect.fromLTWH(0, 0, imageWidth, imageHeight),
          semanticLabel: 'Missing chibi',
          fallbackIcon: Icons.broken_image,
        );
        addTearDown(OrionArtDescriptor.resetSpriteCache);

        // Flame's _ImageAsset attaches a listener-less .then to every load
        // future, so a missing asset always surfaces an unhandled error that
        // no caller can reach; contain it in a guarded zone so the retry
        // assertions can still observe the descriptor's own futures.
        await runZonedGuarded(() async {
          final first = descriptor.sprite;
          await expectLater(first, throwsA(anything));

          final second = descriptor.sprite;
          expect(
            identical(first, second),
            isFalse,
            reason:
                'below the retry cap a transient failure drops the memo so '
                'the next access retries',
          );
          await expectLater(second, throwsA(anything));

          final third = descriptor.sprite;
          expect(identical(second, third), isFalse);
          await expectLater(third, throwsA(anything));

          expect(
            identical(descriptor.sprite, third),
            isTrue,
            reason:
                'past the attempt cap the failed future stays memoized '
                'instead of paying another load on every access',
          );
        }, (error, stack) {});
      },
    );
  });
}

/// The three files every roster member ships, in the order the contract names
/// them.
const _artFiles = ['portrait.png', 'face.png', 'chibi.png'];

const _artRoot = 'assets/images/characters';

/// Every `{id}/{file}` key, 36 in all: exactly the entries provenance.json
/// must record.
Set<String> _artKeys() => {
  for (final character in Character.values)
    for (final file in _artFiles) '${character.name}/$file',
};

/// The art file for [key] (`{id}/{file}`); it must exist on disk.
File _artFile(String key) {
  final file = File('$_artRoot/$key');
  expect(file.existsSync(), isTrue, reason: '$key is missing');
  return file;
}

/// Decodes the art file [key] through the engine's codec and asserts its frame
/// size. [checkPixels] gets the frame's rawRgba bytes (RGBA8, row-major) while
/// the image is still alive; the image and codec are disposed on every path,
/// including a failed assertion.
Future<void> _decodeFrame(
  String key, {
  required int width,
  required int height,
  void Function(ByteData rgba)? checkPixels,
}) async {
  final codec = await ui.instantiateImageCodec(_artFile(key).readAsBytesSync());
  try {
    final frame = await codec.getNextFrame();
    try {
      final image = frame.image;
      expect(
        (image.width, image.height),
        (width, height),
        reason: '$key must decode to ${width}x$height',
      );
      if (checkPixels != null) {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(rgba, isNotNull, reason: '$key has no rawRgba pixels');
        expect(
          rgba!.lengthInBytes,
          width * height * 4,
          reason: '$key rawRgba must be 4 bytes per pixel',
        );
        checkPixels(rgba);
      }
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Describes the first pixel of [rgba] (RGBA8, row-major, [width] pixels per
/// row) whose alpha is not 255, or returns null when the image is opaque.
String? _firstNonOpaquePixel(ByteData rgba, int width) {
  for (var offset = 3; offset < rgba.lengthInBytes; offset += 4) {
    final alpha = rgba.getUint8(offset);
    if (alpha != 255) {
      final pixel = offset ~/ 4;
      return '(${pixel % width}, ${pixel ~/ width}) has alpha $alpha';
    }
  }
  return null;
}

/// Describes the first pixel on the four 1px edges of [rgba] whose alpha is
/// not 0, naming its side, or returns null when the whole frame is transparent.
String? _firstVisibleBorderPixel(ByteData rgba, int width, int height) {
  final border = [
    for (var x = 0; x < width; x++) ('top row', x, 0),
    for (var x = 0; x < width; x++) ('bottom row', x, height - 1),
    for (var y = 0; y < height; y++) ('left column', 0, y),
    for (var y = 0; y < height; y++) ('right column', width - 1, y),
  ];
  for (final (side, x, y) in border) {
    final alpha = rgba.getUint8((y * width + x) * 4 + 3);
    if (alpha != 0) return '$side pixel ($x, $y) has alpha $alpha';
  }
  return null;
}

/// Reads the PNG signature and IHDR chunk for width/height/color type.
/// Color type 6 is RGBA; the chibis must keep their transparency.
({int width, int height, int colorType}) _pngInfo(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.sublist(0, 8), const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ], reason: '${file.path} must be a PNG file');
  expect(
    String.fromCharCodes(bytes.sublist(12, 16)),
    'IHDR',
    reason: '${file.path} must start with an IHDR chunk',
  );
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    colorType: data.getUint8(25),
  );
}
