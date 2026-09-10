import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_board_skin.dart';

void main() {
  group('GameBoardSkin', () {
    test('defines the board skin asset path', () {
      expect(GameBoardSkin.fileName, 'reactor_rim_ui/boards/nebula.png');
      expect(
        GameBoardSkin.assetPath,
        'assets/images/reactor_rim_ui/boards/nebula.png',
      );
    });
  });
}
