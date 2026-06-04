import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../models/game_models.dart';

enum GameTowerVarietySprite {
  railgunTower,
  ionChainTower,
  naniteTower,
  gravityWellTower,
  droneBayTower,
  railSlug,
  ionArc,
  naniteCloud,
  gravityField,
  drone,
  shieldIndicator,
  armorIndicator,
  regenIndicator,
  corrosionIndicator,
  clusterBurst,
  prismSplit,
}

class GameTowerVarietySheet {
  GameTowerVarietySheet._(this._sprites);

  static const String fileName = 'orion_tower_variety_sheet.png';
  static const String assetPath = 'assets/images/$fileName';
  static const int columns = 4;
  static const int rows = 4;

  final Map<GameTowerVarietySprite, Sprite> _sprites;

  static Future<GameTowerVarietySheet> load(Images images) async {
    final image = await images.load(fileName);
    return GameTowerVarietySheet.fromImage(image);
  }

  static GameTowerVarietySheet fromImage(ui.Image image) {
    final sprites = <GameTowerVarietySprite, Sprite>{};
    for (final sprite in GameTowerVarietySprite.values) {
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
    return GameTowerVarietySheet._(sprites);
  }

  Sprite sprite(GameTowerVarietySprite sprite) => _sprites[sprite]!;

  static ui.Rect sourceRectFor(
    GameTowerVarietySprite sprite, {
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

  static bool hasTowerSprite(TowerType type) {
    return switch (type) {
      TowerType.laser || TowerType.rocket || TowerType.cryo => false,
      TowerType.railgun ||
      TowerType.ionChain ||
      TowerType.nanite ||
      TowerType.gravityWell ||
      TowerType.droneBay => true,
    };
  }

  static GameTowerVarietySprite spriteForTower(TowerType type) {
    return switch (type) {
      TowerType.laser || TowerType.rocket || TowerType.cryo =>
        throw ArgumentError.value(type, 'type', 'Use GameSpriteSheet'),
      TowerType.railgun => GameTowerVarietySprite.railgunTower,
      TowerType.ionChain => GameTowerVarietySprite.ionChainTower,
      TowerType.nanite => GameTowerVarietySprite.naniteTower,
      TowerType.gravityWell => GameTowerVarietySprite.gravityWellTower,
      TowerType.droneBay => GameTowerVarietySprite.droneBayTower,
    };
  }

  static GameTowerVarietySprite spriteForProjectile(TowerType type) {
    return switch (type) {
      TowerType.laser || TowerType.rocket || TowerType.cryo =>
        throw ArgumentError.value(type, 'type', 'Use GameSpriteSheet'),
      TowerType.railgun => GameTowerVarietySprite.railSlug,
      TowerType.ionChain => GameTowerVarietySprite.ionArc,
      TowerType.nanite => GameTowerVarietySprite.naniteCloud,
      TowerType.gravityWell => GameTowerVarietySprite.gravityField,
      TowerType.droneBay => GameTowerVarietySprite.drone,
    };
  }
}
