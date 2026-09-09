import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';

import '../assets/game_boss_sheet.dart';
import '../assets/game_sprite_sheet.dart';
import '../assets/game_tower_variety_sheet.dart';
import '../campaign/campaign_progress.dart';
import '../campaign/orion_campaign.dart';
import '../campaign/stage_definition.dart';
import '../models/game_models.dart';

typedef OrionSourceRectResolver =
    ui.Rect Function({required double imageWidth, required double imageHeight});

enum OrionStageArtCrop { briefingWide, mapSquare }

enum OrionSceneArt { worldMap, techTree, missionReport, commandCenter }

@immutable
final class OrionArtDescriptor {
  OrionArtDescriptor({
    required this.fileName,
    required this.sourceRectFor,
    required this.semanticLabel,
    required this.fallbackIcon,
  });

  final String fileName;
  final OrionSourceRectResolver sourceRectFor;
  final String semanticLabel;
  final IconData fallbackIcon;

  late final Future<Sprite> sprite = _loadSprite();

  Future<Sprite> _loadSprite() async {
    final image = await Flame.images.load(fileName);
    final source = sourceRectFor(
      imageWidth: image.width.toDouble(),
      imageHeight: image.height.toDouble(),
    );
    return Sprite(
      image,
      srcPosition: Vector2(source.left, source.top),
      srcSize: Vector2(source.width, source.height),
    );
  }
}

abstract final class OrionArt {
  static final Map<TowerType, OrionArtDescriptor> _towers = Map.unmodifiable({
    for (final type in TowerType.values) type: _towerDescriptor(type),
  });

  static final Map<BossSprite, OrionArtDescriptor> _bosses = Map.unmodifiable({
    for (final boss in GameBalance.bosses)
      boss.sprite: OrionArtDescriptor(
        fileName: GameBossSheet.fileName,
        sourceRectFor: ({required imageWidth, required imageHeight}) =>
            GameBossSheet.sourceRectFor(
              boss.sprite,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
            ),
        semanticLabel: '${boss.name} boss',
        fallbackIcon: Icons.warning_amber_rounded,
      ),
  });

  static final OrionArtDescriptor _basicDrone = OrionArtDescriptor(
    fileName: GameSpriteSheet.fileName,
    sourceRectFor: ({required imageWidth, required imageHeight}) =>
        GameSpriteSheet.sourceRectFor(
          GameSprite.basicDroneEnemy,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
    semanticLabel: 'Drone threat',
    fallbackIcon: Icons.smart_toy_outlined,
  );

  static final OrionArtDescriptor _heavyDrone = OrionArtDescriptor(
    fileName: GameSpriteSheet.fileName,
    sourceRectFor: ({required imageWidth, required imageHeight}) =>
        GameSpriteSheet.sourceRectFor(
          GameSprite.heavyDroneEnemy,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
    semanticLabel: 'Heavy drone threat',
    fallbackIcon: Icons.smart_toy,
  );

  static final OrionArtDescriptor _armorIndicator = _varietyDescriptor(
    GameTowerVarietySprite.armorIndicator,
    semanticLabel: 'Armored trait',
    fallbackIcon: Icons.shield_outlined,
  );

  static final OrionArtDescriptor _shieldIndicator = _varietyDescriptor(
    GameTowerVarietySprite.shieldIndicator,
    semanticLabel: 'Shielded trait',
    fallbackIcon: Icons.shield,
  );

  static final OrionArtDescriptor _regenIndicator = _varietyDescriptor(
    GameTowerVarietySprite.regenIndicator,
    semanticLabel: 'Regeneration trait',
    fallbackIcon: Icons.autorenew,
  );

  /// Aspect of the briefingWide hero crop; drives both the sprite crop and
  /// the briefing sheet's full-bleed AspectRatio band.
  static const double briefingHeroAspect = 1.6;

  static final Map<(String, OrionStageArtCrop), OrionArtDescriptor> _stageArt =
      Map.unmodifiable({
        for (final stage in OrionCampaign.stages)
          for (final crop in OrionStageArtCrop.values)
            (stage.id, crop): _stageKeyArtDescriptor(stage, crop),
      });

  static final Map<OrionSceneArt, OrionArtDescriptor> _scenes =
      Map.unmodifiable({
        OrionSceneArt.worldMap: OrionArtDescriptor(
          fileName: 'reactor_rim_ui/backdrops/world-map.png',
          sourceRectFor: _fullRectFor,
          semanticLabel: 'Star chart backdrop',
          fallbackIcon: Icons.public,
        ),
        OrionSceneArt.techTree: OrionArtDescriptor(
          fileName: 'reactor_rim_ui/backdrops/tech-tree-rnd-bay.png',
          sourceRectFor: _fullRectFor,
          semanticLabel: 'R&D bay backdrop',
          fallbackIcon: Icons.science,
        ),
        OrionSceneArt.missionReport: OrionArtDescriptor(
          fileName: 'reactor_rim_ui/backdrops/mission-report-debrief.png',
          sourceRectFor: _fullRectFor,
          semanticLabel: 'Mission debrief backdrop',
          fallbackIcon: Icons.description,
        ),
        OrionSceneArt.commandCenter: OrionArtDescriptor(
          fileName: 'reactor_rim_ui/backdrops/command-center.png',
          sourceRectFor: _fullRectFor,
          semanticLabel: 'Command center backdrop',
          fallbackIcon: Icons.dashboard,
        ),
      });

  static final Map<String, OrionArtDescriptor> _crests = Map.unmodifiable({
    for (final stage in OrionCampaign.stages)
      stage.id: OrionArtDescriptor(
        fileName: 'reactor_rim_ui/crests/${stage.id}.png',
        sourceRectFor: ({required imageWidth, required imageHeight}) =>
            ui.Rect.fromLTWH(0, 0, imageWidth, imageHeight),
        semanticLabel: '${stage.name} crest',
        fallbackIcon: Icons.shield_outlined,
      ),
  });

  static final OrionArtDescriptor _victoryArt = OrionArtDescriptor(
    fileName: 'reactor_rim_ui/results/victory.png',
    sourceRectFor: _fullRectFor,
    semanticLabel: 'Victory banner art',
    fallbackIcon: Icons.emoji_events,
  );

  static final OrionArtDescriptor _defeatArt = OrionArtDescriptor(
    fileName: 'reactor_rim_ui/results/defeat.png',
    sourceRectFor: _fullRectFor,
    semanticLabel: 'Defeat banner art',
    fallbackIcon: Icons.flag,
  );

  static OrionArtDescriptor tower(TowerType type) => _towers[type]!;

  static OrionArtDescriptor boss(BossSprite sprite) => _bosses[sprite]!;

  static OrionArtDescriptor stage(
    StageDefinition stage, {
    OrionStageArtCrop? crop,
  }) {
    if (crop != null) {
      return _stageArt[(stage.id, crop)]!;
    }
    if (stage.waves.isEmpty || stage.waves.last.groups.isEmpty) {
      throw StateError('Stage ${stage.id} has no final enemy group');
    }
    final finalEnemy = stage.waves.last.groups.last.enemyStats;
    if (finalEnemy is! BossDefinition) {
      throw StateError('Stage ${stage.id} does not end with a boss');
    }
    return boss(finalEnemy.sprite);
  }

  static OrionArtDescriptor result(StageResult? result) {
    return result == null ? _defeatArt : _victoryArt;
  }

  static OrionArtDescriptor scene(OrionSceneArt scene) => _scenes[scene]!;

  static OrionArtDescriptor crestFor(StageDefinition stage) =>
      _crests[stage.id]!;

  static ui.Rect _stageRectFor(
    OrionStageArtCrop crop, {
    required double imageWidth,
    required double imageHeight,
  }) {
    return switch (crop) {
      OrionStageArtCrop.briefingWide => _briefingWideRectFor(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ),
      OrionStageArtCrop.mapSquare => _mapSquareRectFor(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ),
    };
  }

  static ui.Rect _briefingWideRectFor({
    required double imageWidth,
    required double imageHeight,
  }) {
    const aspect = briefingHeroAspect;
    var width = imageWidth;
    var height = width / aspect;
    if (height > imageHeight) {
      height = imageHeight;
      width = height * aspect;
    }
    return ui.Rect.fromLTWH(
      (imageWidth - width) / 2,
      (imageHeight - height) / 2,
      width,
      height,
    );
  }

  static ui.Rect _mapSquareRectFor({
    required double imageWidth,
    required double imageHeight,
  }) {
    final side = imageWidth < imageHeight ? imageWidth : imageHeight;
    return ui.Rect.fromLTWH(
      (imageWidth - side) / 2,
      (imageHeight - side) / 2,
      side,
      side,
    );
  }

  static ui.Rect _fullRectFor({
    required double imageWidth,
    required double imageHeight,
  }) {
    return ui.Rect.fromLTWH(0, 0, imageWidth, imageHeight);
  }

  static OrionArtDescriptor _stageKeyArtDescriptor(
    StageDefinition stage,
    OrionStageArtCrop crop,
  ) {
    return OrionArtDescriptor(
      fileName: 'reactor_rim_ui/stages/${stage.id}.png',
      sourceRectFor: ({required imageWidth, required imageHeight}) =>
          _stageRectFor(crop, imageWidth: imageWidth, imageHeight: imageHeight),
      semanticLabel: '${stage.name} sector key art',
      fallbackIcon: Icons.landscape,
    );
  }

  static OrionArtDescriptor previewGroup(WavePreviewGroup group) {
    for (final boss in GameBalance.bosses) {
      if (boss.name == group.label) return OrionArt.boss(boss.sprite);
    }
    return group.traits.contains(EnemyTrait.heavy) ? _heavyDrone : _basicDrone;
  }

  static OrionArtDescriptor? trait(EnemyTrait trait) {
    return switch (trait) {
      EnemyTrait.armored => _armorIndicator,
      EnemyTrait.shielded => _shieldIndicator,
      EnemyTrait.regen => _regenIndicator,
      EnemyTrait.swarm || EnemyTrait.heavy => null,
    };
  }

  static OrionArtDescriptor _towerDescriptor(TowerType type) {
    if (GameTowerVarietySheet.hasTowerSprite(type)) {
      return _varietyDescriptor(
        GameTowerVarietySheet.spriteForTower(type),
        semanticLabel: '${type.label} tower',
        fallbackIcon: Icons.cell_tower,
      );
    }

    final sprite = GameSpriteSheet.spriteForTower(type);
    return OrionArtDescriptor(
      fileName: GameSpriteSheet.fileName,
      sourceRectFor: ({required imageWidth, required imageHeight}) =>
          GameSpriteSheet.sourceRectFor(
            sprite,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          ),
      semanticLabel: '${type.label} tower',
      fallbackIcon: Icons.cell_tower,
    );
  }

  static OrionArtDescriptor _varietyDescriptor(
    GameTowerVarietySprite sprite, {
    required String semanticLabel,
    required IconData fallbackIcon,
  }) {
    return OrionArtDescriptor(
      fileName: GameTowerVarietySheet.fileName,
      sourceRectFor: ({required imageWidth, required imageHeight}) =>
          GameTowerVarietySheet.sourceRectFor(
            sprite,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          ),
      semanticLabel: semanticLabel,
      fallbackIcon: fallbackIcon,
    );
  }
}

class OrionAtlasSprite extends StatelessWidget {
  const OrionAtlasSprite({super.key, required this.art, this.size});

  final OrionArtDescriptor art;
  final Size? size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: art.semanticLabel,
      child: ExcludeSemantics(
        child: FutureBuilder<Sprite>(
          future: art.sprite,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Icon(art.fallbackIcon, size: size?.shortestSide);
            }
            final sprite = snapshot.data;
            if (sprite == null) {
              return SizedBox.fromSize(size: size);
            }
            return SpriteWidget(sprite: sprite, size: size);
          },
        ),
      ),
    );
  }
}
