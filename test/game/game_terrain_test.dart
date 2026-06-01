import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_terrain.dart';

void main() {
  group('GameTerrain', () {
    test('defines the terrain background asset path', () {
      expect(GameTerrain.fileName, 'orion_terrain_background.png');
      expect(
        GameTerrain.assetPath,
        'assets/images/orion_terrain_background.png',
      );
    });
  });
}
