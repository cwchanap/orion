import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

enum GameSprite {
  laserTower,
  rocketTower,
  cryoTower,
  basicDroneEnemy,
  heavyDroneEnemy,
  laserBolt,
  rocketProjectile,
  cryoProjectile,
  spawnGate,
  baseReactor,
  greenImpact,
  cryoImpact,
}

class GameSpriteSheet {
  GameSpriteSheet._(this._sprites);

  static const String fileName = 'orion_sprite_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 3;
  static const double heavyEnemyHealthThreshold = 70;

  final Map<GameSprite, Sprite> _sprites;

  static Future<GameSpriteSheet> load(Images images) async {
    final image = await images.load(fileName);
    return GameSpriteSheet.fromImage(image);
  }

  static GameSpriteSheet fromImage(ui.Image image) {
    final sprites = <GameSprite, Sprite>{};
    for (final sprite in GameSprite.values) {
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
    return GameSpriteSheet._(sprites);
  }

  Sprite sprite(GameSprite sprite) => _sprites[sprite]!;

  static ui.Rect sourceRectFor(
    GameSprite sprite, {
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

  static GameSprite spriteForTower(TowerType type) {
    return switch (type) {
      TowerType.laser => GameSprite.laserTower,
      TowerType.rocket => GameSprite.rocketTower,
      TowerType.cryo => GameSprite.cryoTower,
    };
  }

  static GameSprite spriteForProjectile(TowerType type) {
    return switch (type) {
      TowerType.laser => GameSprite.laserBolt,
      TowerType.rocket => GameSprite.rocketProjectile,
      TowerType.cryo => GameSprite.cryoProjectile,
    };
  }

  static GameSprite spriteForEnemy(EnemyStats stats) {
    if (stats.health >= heavyEnemyHealthThreshold) {
      return GameSprite.heavyDroneEnemy;
    }
    return GameSprite.basicDroneEnemy;
  }
}
