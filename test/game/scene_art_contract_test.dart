import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_boss_sheet.dart';
import 'package:orion/game/assets/game_path_tiles.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/assets/game_tower_variety_sheet.dart';
import 'package:orion/game/models/game_models.dart';

import '../support/image_contract_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const root = 'assets/images/';
  const stages = [
    'outpost-alpha',
    'nebula-relay',
    'salvage-rift',
    'asteroid-foundry',
    'aurora-gate',
    'void-bastion',
    'singularity-core',
  ];
  final sizes = <String, (int, int)>{
    'orion_sprite_sheet.png': (1448, 1086),
    'orion_tower_variety_sheet.png': (1024, 1024),
    'orion_boss_sheet.png': (1024, 512),
    'orion_path_tiles.png': (1776, 888),
    for (final name in [
      'command-center',
      'tech-tree-rnd-bay',
      'mission-report-debrief',
      'map-room',
    ])
      'reactor_rim_ui/backdrops/$name.png': (512, 1110),
    'reactor_rim_ui/backdrops/world-map.png': (640, 640),
    'reactor_rim_ui/boards/nebula.png': (512, 768),
    for (final name in stages) 'reactor_rim_ui/stages/$name.png': (1024, 1024),
    for (final name in stages) 'reactor_rim_ui/crests/$name.png': (160, 160),
    for (final name in ['victory', 'defeat'])
      'reactor_rim_ui/results/$name.png': (512, 256),
  };
  final atlases = <String, (int, int)>{
    'orion_sprite_sheet.png': (GameSpriteSheet.columns, GameSpriteSheet.rows),
    'orion_tower_variety_sheet.png': (
      GameTowerVarietySheet.columns,
      GameTowerVarietySheet.rows,
    ),
    'orion_boss_sheet.png': (GameBossSheet.columns, GameBossSheet.rows),
    'orion_path_tiles.png': (GamePathTiles.columns, GamePathTiles.rows),
  };
  // Cells index < this count map to a sprite enum value and must contain art;
  // any later cell must stay fully transparent (the boss sheet's 8th cell).
  final occupiedCells = <String, int>{
    'orion_sprite_sheet.png': GameSprite.values.length,
    'orion_tower_variety_sheet.png': GameTowerVarietySprite.values.length,
    'orion_boss_sheet.png': BossSprite.values.length,
  };

  test(
    'all 26 scene images are registered and decode at the required sizes',
    () async {
      expect(sizes, hasLength(26));
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final registered = manifest.listAssets().toSet();
      for (final entry in sizes.entries) {
        final path = '$root${entry.key}';
        expect(registered, contains(path));
        final bytes = await rootBundle.load(path);
        final info = pngInfo(bytes, name: path);
        expect((info.width, info.height), entry.value, reason: path);
        final grid = atlases[entry.key];
        if (grid != null) {
          expect(info.width % grid.$1, 0, reason: path);
          expect(info.height % grid.$2, 0, reason: path);
        }
        final isSprite = grid != null && entry.key != 'orion_path_tiles.png';
        if (isSprite) expect(info.colorType, 6, reason: path);
        final fullBleed =
            entry.key.startsWith('reactor_rim_ui/') &&
            !entry.key.contains('/crests/');
        await decodePngFrame(
          bytes,
          name: path,
          width: entry.value.$1,
          height: entry.value.$2,
          checkPixels: (rgba) {
            if (fullBleed) {
              expect(
                firstNonOpaquePixel(rgba, entry.value.$1),
                isNull,
                reason: path,
              );
            }
            if (isSprite) {
              _checkCellBorders(
                rgba,
                entry.value.$1,
                entry.value.$2,
                grid.$1,
                grid.$2,
                path,
              );
              _checkCellContent(
                rgba,
                entry.value.$1,
                entry.value.$2,
                grid.$1,
                grid.$2,
                occupiedCells[entry.key]!,
                path,
              );
            }
          },
        );
      }
    },
  );
}

/// Asserts cells `0..occupied-1` each hold at least one visible pixel and
/// cells `occupied..columns*rows-1` are fully transparent, so a blank sprite
/// frame cannot pass as valid art and reserved cells stay empty.
void _checkCellContent(
  ByteData rgba,
  int width,
  int height,
  int columns,
  int rows,
  int occupied,
  String path,
) {
  final cellW = width ~/ columns;
  final cellH = height ~/ rows;
  for (var cell = 0; cell < columns * rows; cell++) {
    final left = (cell % columns) * cellW, top = (cell ~/ columns) * cellH;
    var hasPixel = false;
    for (var y = top; y < top + cellH && !hasPixel; y++) {
      for (var x = left; x < left + cellW; x++) {
        if (rgba.getUint8((y * width + x) * 4 + 3) != 0) {
          hasPixel = true;
          break;
        }
      }
    }
    expect(hasPixel, cell < occupied, reason: '$path cell $cell');
  }
}

void _checkCellBorders(
  ByteData rgba,
  int width,
  int height,
  int columns,
  int rows,
  String path,
) {
  final cellW = width ~/ columns;
  final cellH = height ~/ rows;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < columns; col++) {
      final left = col * cellW, top = row * cellH;
      for (var x = left; x < left + cellW; x++) {
        expect(rgba.getUint8((top * width + x) * 4 + 3), 0, reason: path);
        expect(
          rgba.getUint8(((top + cellH - 1) * width + x) * 4 + 3),
          0,
          reason: path,
        );
      }
      for (var y = top; y < top + cellH; y++) {
        expect(rgba.getUint8((y * width + left) * 4 + 3), 0, reason: path);
        expect(
          rgba.getUint8((y * width + left + cellW - 1) * 4 + 3),
          0,
          reason: path,
        );
      }
    }
  }
}
