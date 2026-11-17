import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

/// HPA-922 Task 5 asset contract: every Last Hearth roster member ships an
/// approved HPA-924 full-size portrait (1024x1536 PNG, un-cropped) and a
/// transparent 512x512 full-body chibi under
/// `assets/images/characters/{id}/`, addressable through the shared
/// `OrionArtDescriptor` registry — never through mockup screenshot crops,
/// a parallel path table, or a second image cache.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('per-ID character art files', () {
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

    test('all 24 per-ID files exist on disk with the approved dimensions', () {
      for (final character in Character.values) {
        final portraitFile = File(
          'assets/images/characters/${character.name}/portrait.png',
        );
        expect(
          portraitFile.existsSync(),
          isTrue,
          reason: '${portraitFile.path} is missing',
        );
        final portrait = _pngInfo(portraitFile);
        expect(
          (portrait.width, portrait.height),
          (1024, 1536),
          reason:
              'portrait for ${character.name} must be the full-size '
              'approved concept, not a crop',
        );

        final chibiFile = File(
          'assets/images/characters/${character.name}/chibi.png',
        );
        expect(
          chibiFile.existsSync(),
          isTrue,
          reason: '${chibiFile.path} is missing',
        );
        final chibi = _pngInfo(chibiFile);
        expect(
          (chibi.width, chibi.height),
          (512, 512),
          reason: 'chibi for ${character.name} must be the paired 512px PNG',
        );
        expect(
          chibi.colorType,
          6,
          reason:
              'chibi for ${character.name} must keep its alpha channel '
              '(RGBA color type 6)',
        );
      }
    });

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
