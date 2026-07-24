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
  });
}
