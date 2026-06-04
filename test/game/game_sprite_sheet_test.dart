import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/models/game_models.dart';

void main() {
  group('GameSpriteSheet', () {
    test('maps the 4x3 sprite sheet cells in stable order', () {
      expect(GameSpriteSheet.columns, 4);
      expect(GameSpriteSheet.rows, 3);
      expect(GameSpriteSheet.fileName, 'orion_sprite_sheet.png');
      expect(GameSpriteSheet.assetPath, 'assets/images/orion_sprite_sheet.png');

      final laserRect = GameSpriteSheet.sourceRectFor(
        GameSprite.laserTower,
        imageWidth: 1024,
        imageHeight: 768,
      );
      expect(laserRect.left, 0);
      expect(laserRect.top, 0);
      expect(laserRect.width, 256);
      expect(laserRect.height, 256);

      final finalRect = GameSpriteSheet.sourceRectFor(
        GameSprite.cryoImpact,
        imageWidth: 1024,
        imageHeight: 768,
      );
      expect(finalRect.left, 768);
      expect(finalRect.top, 512);
      expect(finalRect.width, 256);
      expect(finalRect.height, 256);
    });

    test('selects sprites for gameplay object types', () {
      expect(
        GameSpriteSheet.spriteForTower(TowerType.laser),
        GameSprite.laserTower,
      );
      expect(
        GameSpriteSheet.spriteForTower(TowerType.rocket),
        GameSprite.rocketTower,
      );
      expect(
        GameSpriteSheet.spriteForTower(TowerType.cryo),
        GameSprite.cryoTower,
      );

      expect(
        GameSpriteSheet.spriteForProjectile(TowerType.laser),
        GameSprite.laserBolt,
      );
      expect(
        GameSpriteSheet.spriteForProjectile(TowerType.rocket),
        GameSprite.rocketProjectile,
      );
      expect(
        GameSpriteSheet.spriteForProjectile(TowerType.cryo),
        GameSprite.cryoProjectile,
      );

      expect(
        GameSpriteSheet.spriteForEnemy(
          const EnemyStats(health: 30, speed: 72, baseDamage: 1, goldReward: 8),
        ),
        GameSprite.basicDroneEnemy,
      );
      expect(
        GameSpriteSheet.spriteForEnemy(
          const EnemyStats(
            health: 76,
            speed: 84,
            baseDamage: 2,
            goldReward: 11,
          ),
        ),
        GameSprite.heavyDroneEnemy,
      );
    });
  });

  group('GameTowerVarietySheet', () {
    test('maps the 4x4 tower variety sheet cells in stable order', () {
      expect(GameTowerVarietySheet.columns, 4);
      expect(GameTowerVarietySheet.rows, 4);
      expect(GameTowerVarietySheet.fileName, 'orion_tower_variety_sheet.png');
      expect(
        GameTowerVarietySheet.assetPath,
        'assets/images/orion_tower_variety_sheet.png',
      );

      final railgunRect = GameTowerVarietySheet.sourceRectFor(
        GameTowerVarietySprite.railgunTower,
        imageWidth: 1024,
        imageHeight: 1024,
      );
      expect(railgunRect.left, 0);
      expect(railgunRect.top, 0);
      expect(railgunRect.width, 256);
      expect(railgunRect.height, 256);

      final finalRect = GameTowerVarietySheet.sourceRectFor(
        GameTowerVarietySprite.prismSplit,
        imageWidth: 1024,
        imageHeight: 1024,
      );
      expect(finalRect.left, 768);
      expect(finalRect.top, 768);
      expect(finalRect.width, 256);
      expect(finalRect.height, 256);
    });

    test('selects tower variety sprites for new gameplay object types', () {
      expect(
        GameTowerVarietySheet.spriteForTower(TowerType.railgun),
        GameTowerVarietySprite.railgunTower,
      );
      expect(
        GameTowerVarietySheet.spriteForTower(TowerType.ionChain),
        GameTowerVarietySprite.ionChainTower,
      );
      expect(
        GameTowerVarietySheet.spriteForTower(TowerType.nanite),
        GameTowerVarietySprite.naniteTower,
      );
      expect(
        GameTowerVarietySheet.spriteForTower(TowerType.gravityWell),
        GameTowerVarietySprite.gravityWellTower,
      );
      expect(
        GameTowerVarietySheet.spriteForTower(TowerType.droneBay),
        GameTowerVarietySprite.droneBayTower,
      );

      expect(
        GameTowerVarietySheet.spriteForProjectile(TowerType.railgun),
        GameTowerVarietySprite.railSlug,
      );
    });
  });
}
