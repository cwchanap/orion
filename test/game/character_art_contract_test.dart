import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

import '../support/image_contract_helpers.dart';

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
        final portrait = pngInfo(_artFile('$name/portrait.png'));
        expect(
          (portrait.width, portrait.height),
          (1024, 1536),
          reason:
              '$name/portrait.png must be the full-size approved concept, '
              'not a crop',
        );

        final face = pngInfo(_artFile('$name/face.png'));
        expect(
          (face.width, face.height),
          (512, 512),
          reason: '$name/face.png must be the 512px square face thumbnail',
        );

        final chibi = pngInfo(_artFile('$name/chibi.png'));
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
            firstNonOpaquePixel(rgba, 512),
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
            firstVisibleBorderPixel(rgba, 512, 512),
            isNull,
            reason: '$key must have a fully transparent 1px border',
          ),
        );
      }
    });

    test('provenance.json has a valid schema record for every art file', () {
      final file = File('$_artRoot/provenance.json');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final decoded = jsonDecode(file.readAsStringSync());
      expect(
        decoded,
        isA<Map<String, dynamic>>(),
        reason: 'provenance.json must be a JSON object keyed by "{id}/{file}"',
      );
      final map = decoded as Map<String, dynamic>;
      final recorded = map.keys.toSet();
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

      for (final character in Character.values) {
        for (final (fileName, expectedRole) in [
          ('portrait.png', 'card'),
          ('face.png', 'face'),
          ('chibi.png', 'chibi'),
        ]) {
          final key = '${character.name}/$fileName';
          final entry = map[key];
          expect(entry, isA<Map<String, dynamic>>(), reason: key);
          final record = entry as Map<String, dynamic>;
          expect(
            record['role'],
            expectedRole,
            reason: '$key role must be "$expectedRole"',
          );
          final method = record['method'];
          expect(
            method,
            isIn(_allowedProvenanceMethods),
            reason:
                '$key method must be one of $_allowedProvenanceMethods '
                '(got $method)',
          );
          for (final field in ['approval', 'source', 'reference']) {
            final value = record[field];
            expect(
              value,
              isA<String>(),
              reason: '$key $field must be a String',
            );
            expect(
              (value as String).trim(),
              isNotEmpty,
              reason: '$key $field must not be empty',
            );
          }
          if (method == 'generated') {
            for (final field in ['model', 'prompt']) {
              final value = record[field];
              expect(
                value,
                isA<String>(),
                reason: '$key $field must be recorded when method is generated',
              );
              expect(
                (value as String).trim(),
                isNotEmpty,
                reason: '$key $field must not be empty when generated',
              );
            }
          } else {
            for (final field in ['model', 'prompt']) {
              expect(
                record.containsKey(field),
                isTrue,
                reason:
                    '$key $field must be present (null) when method is $method',
              );
              expect(
                record[field],
                isNull,
                reason: '$key $field must be null when method is $method',
              );
            }
          }
        }
      }
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

/// The five provenance methods allowed by the HPA-924 design spec.
const _allowedProvenanceMethods = {
  'reused',
  'optimized',
  'cropped',
  'retouched',
  'generated',
};

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

Future<void> _decodeFrame(
  String key, {
  required int width,
  required int height,
  void Function(ByteData rgba)? checkPixels,
}) => decodePngFrame(
  _artFile(key),
  width: width,
  height: height,
  checkPixels: checkPixels,
);
