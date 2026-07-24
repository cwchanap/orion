import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

class GameBossSheet {
  GameBossSheet._(this._sprites);

  static const String fileName = 'orion_boss_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 2; // 8 cells; BossSprite has 7 values

  final Map<BossSprite, Sprite> _sprites;

  static Future<GameBossSheet> load(Images images) async {
    final image = await images.load(fileName);
    return GameBossSheet.fromImage(image);
  }

  static GameBossSheet fromImage(ui.Image image) {
    final sprites = <BossSprite, Sprite>{};
    for (final sprite in BossSprite.values) {
      final sourceRect = sourceRectFor(
        sprite,
        imageWidth: image.width.toDouble(),
        imageHeight: image.height.toDouble(),
      );
      sprites[sprite] = Sprite(
        image,
        srcPosition: Vector2(sourceRect.left, sourceRect.top),
        srcSize: Vector2(sourceRect.width, sourceRect.height),
      );
    }
    return GameBossSheet._(sprites);
  }

  Sprite sprite(BossSprite sprite) => _sprites[sprite]!;

  static ui.Rect sourceRectFor(
    BossSprite sprite, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final index = sprite.index;
    final cellWidth = imageWidth / columns;
    final cellHeight = imageHeight / rows;
    final column = index % columns;
    final row = index ~/ columns;
    return ui.Rect.fromLTWH(
      column * cellWidth,
      row * cellHeight,
      cellWidth,
      cellHeight,
    );
  }
}
