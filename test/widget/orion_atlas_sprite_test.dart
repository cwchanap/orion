import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/campaign/orion_campaign.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_atlas_sprite.dart';

void main() {
  test('every tower resolves through an existing loader helper', () {
    for (final type in TowerType.values) {
      final art = OrionArt.tower(type);
      final rect = art.sourceRectFor(imageWidth: 400, imageHeight: 400);
      expect(rect.width, greaterThan(0), reason: type.name);
      expect(rect.height, greaterThan(0), reason: type.name);
    }

    expect(
      OrionArt.tower(
        TowerType.cryo,
      ).sourceRectFor(imageWidth: 400, imageHeight: 300),
      GameSpriteSheet.sourceRectFor(
        GameSprite.cryoTower,
        imageWidth: 400,
        imageHeight: 300,
      ),
    );
    expect(
      OrionArt.tower(
        TowerType.droneBay,
      ).sourceRectFor(imageWidth: 400, imageHeight: 400),
      GameTowerVarietySheet.sourceRectFor(
        GameTowerVarietySprite.droneBayTower,
        imageWidth: 400,
        imageHeight: 400,
      ),
    );
  });

  test('every campaign stage resolves to its authored final boss sprite', () {
    for (final stage in OrionCampaign.stages) {
      final boss = stage.waves.last.groups.last.enemyStats as BossDefinition;
      final art = OrionArt.stage(stage);
      expect(
        art.sourceRectFor(imageWidth: 400, imageHeight: 200),
        GameBossSheet.sourceRectFor(
          boss.sprite,
          imageWidth: 400,
          imageHeight: 200,
        ),
        reason: stage.id,
      );
    }
  });

  test('real wave preview preserves boss art at the projection seam', () {
    for (final boss in GameBalance.bosses) {
      final preview = GameBalance.wavePreview(
        wave: WaveDefinition(
          groups: [WaveGroup(enemyCount: 1, enemyStats: boss)],
          clearBonus: 0,
        ),
        waveNumber: 1,
        waveTotal: 1,
        unlockedTowerTypes: TowerType.values,
        effectiveClearBonus: 0,
      );
      expect(
        OrionArt.previewGroup(
          preview.groups.single,
        ).sourceRectFor(imageWidth: 400, imageHeight: 200),
        GameBossSheet.sourceRectFor(
          boss.sprite,
          imageWidth: 400,
          imageHeight: 200,
        ),
        reason: boss.name,
      );
    }

    final queen = WavePreviewGroup(
      enemyCount: 1,
      label: 'Swarm Queen',
      traits: {EnemyTrait.swarm, EnemyTrait.regen},
    );
    final heavy = WavePreviewGroup(
      enemyCount: 4,
      label: 'Heavy Drones',
      traits: {EnemyTrait.heavy},
    );
    final basic = WavePreviewGroup(
      enemyCount: 8,
      label: 'Drones',
      traits: const {},
    );

    expect(OrionArt.previewGroup(queen).fileName, GameBossSheet.fileName);
    expect(
      OrionArt.previewGroup(
        queen,
      ).sourceRectFor(imageWidth: 400, imageHeight: 200),
      GameBossSheet.sourceRectFor(
        BossSprite.swarmQueen,
        imageWidth: 400,
        imageHeight: 200,
      ),
    );
    expect(
      OrionArt.previewGroup(
        heavy,
      ).sourceRectFor(imageWidth: 400, imageHeight: 300),
      GameSpriteSheet.sourceRectFor(
        GameSprite.heavyDroneEnemy,
        imageWidth: 400,
        imageHeight: 300,
      ),
    );
    expect(
      OrionArt.previewGroup(
        basic,
      ).sourceRectFor(imageWidth: 400, imageHeight: 300),
      GameSpriteSheet.sourceRectFor(
        GameSprite.basicDroneEnemy,
        imageWidth: 400,
        imageHeight: 300,
      ),
    );
  });

  test('trait art reuses indicator cells and shape fallbacks', () {
    expect(OrionArt.trait(EnemyTrait.armored), isNotNull);
    expect(OrionArt.trait(EnemyTrait.shielded), isNotNull);
    expect(OrionArt.trait(EnemyTrait.regen), isNotNull);
    expect(OrionArt.trait(EnemyTrait.swarm), isNull);
    expect(OrionArt.trait(EnemyTrait.heavy), isNull);
  });

  testWidgets('renders through SpriteWidget and reuses the canonical future', (
    tester,
  ) async {
    Flame.images.add(GameSpriteSheet.fileName, await _blankImage(400, 300));
    final art = OrionArt.tower(TowerType.laser);
    final firstSpriteFuture = art.sprite;

    await tester.pumpWidget(
      MaterialApp(
        home: OrionAtlasSprite(art: art, size: const Size.square(64)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SpriteWidget), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: OrionAtlasSprite(
          art: OrionArt.tower(TowerType.laser),
          size: const Size.square(64),
        ),
      ),
    );
    expect(
      identical(firstSpriteFuture, OrionArt.tower(TowerType.laser).sprite),
      isTrue,
    );
  });

  testWidgets('sprite resolution failure renders the descriptor fallback', (
    tester,
  ) async {
    const failingSheet = 'failing-command-deck-sheet.png';
    Flame.images.add(failingSheet, await _blankImage(64, 64));
    final failing = OrionArtDescriptor(
      fileName: failingSheet,
      sourceRectFor: ({required imageWidth, required imageHeight}) =>
          throw StateError('Simulated atlas resolution failure'),
      semanticLabel: 'Unavailable command-deck art',
      fallbackIcon: Icons.broken_image,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OrionAtlasSprite(art: failing, size: const Size.square(64)),
      ),
    );
    await tester.pumpAndSettle();

    // Flame 1.37 emits a second unhandled cache future for a truly missing
    // key. Failing after its local cache boundary exercises the same widget
    // error snapshot without coupling this regression to that package bug.
    expect(find.byIcon(Icons.broken_image), findsOneWidget);
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
