import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/models/game_models.dart';

Future<ui.Image> _solidImage(int width, int height) async {
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

void main() {
  group('TowerComponent board readability (HPA-699)', () {
    test(
      'the drawn sprite keeps its footprint while board art changes',
      () async {
        final spriteSheet = GameSpriteSheet.fromImage(
          await _solidImage(1024, 768),
        );
        const radius = 15.0;
        final tower = TowerComponent(
          tower: const PlacedTower(
            id: 1,
            type: TowerType.laser,
            position: GridPosition(1, 1),
          ),
          center: Vector2(radius, radius),
          resolveStats: (tower) =>
              GameBalance.towerStats(tower.type, level: tower.level),
          acquireTarget: (_) => null,
          launchProjectile: (_, _) {},
          spriteSheet: spriteSheet,
          radius: radius,
        );

        final recorder = ui.PictureRecorder();
        tower.render(ui.Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        picture.dispose();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

        final x = (radius + radius * 1.9).round();
        final index = (radius.round() * image.width + x) * 4;
        expect(data!.getUint8(index + 3), greaterThan(0));
      },
    );
  });
}
