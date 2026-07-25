import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameBossSheet', () {
    test('sourceRect maps each BossSprite left-to-right, top-to-bottom', () {
      // 4 columns x 2 rows. Index 0..3 => row 0; 4..6 => row 1.
      final r0 = GameBossSheet.sourceRectFor(
        BossSprite.relayBreaker,
        imageWidth: 400,
        imageHeight: 200,
      );
      expect(r0.left, 0);
      expect(r0.top, 0);
      expect(r0.width, 100);
      expect(r0.height, 100);

      final r4 = GameBossSheet.sourceRectFor(
        BossSprite.regenWarden,
        imageWidth: 400,
        imageHeight: 200,
      );
      expect(r4.left, 0);
      expect(r4.top, 100); // second row
    });

    test('fileName and assetPath are stable', () {
      expect(GameBossSheet.fileName, 'orion_boss_sheet.png');
      expect(GameBossSheet.assetPath, 'assets/images/orion_boss_sheet.png');
    });

    test('fromImage creates a sprite for every BossSprite', () async {
      final image = await _blankImage(400, 200);
      final sheet = GameBossSheet.fromImage(image);

      for (final boss in BossSprite.values) {
        final sprite = sheet.sprite(boss);
        expect(sprite.src.width, closeTo(100, 0.001));
        expect(sprite.src.height, closeTo(100, 0.001));
      }
    });

    test('fromImage slices the second row below the first', () async {
      final image = await _blankImage(400, 200);
      final sheet = GameBossSheet.fromImage(image);

      // Index 4 (regenWarden) is the first sprite on the second row.
      expect(sheet.sprite(BossSprite.regenWarden).src.top, closeTo(100, 0.001));
      expect(sheet.sprite(BossSprite.relayBreaker).src.top, closeTo(0, 0.001));
    });

    test('load returns a sheet backed by the cached image', () async {
      final images = Images();
      images.add(GameBossSheet.fileName, await _blankImage(400, 200));
      final sheet = await GameBossSheet.load(images);

      for (final boss in BossSprite.values) {
        expect(() => sheet.sprite(boss), returnsNormally);
      }
    });
  });
}

Future<ui.Image> _blankImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}
