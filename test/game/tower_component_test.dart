import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/components/tower_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/ui/orion_ui_theme.dart';

Future<ui.Image> _solidImage(
  int width,
  int height, [
  int argb = 0xFFFFFFFF,
]) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = ui.Color(argb),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ByteData> _renderPixels(TowerComponent tower, {int size = 100}) async {
  final recorder = ui.PictureRecorder();
  tower.render(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

({int r, int g, int b, int a}) _pixelAt(ByteData data, int x, int y) {
  final index = (y * 100 + x) * 4;
  return (
    r: data.getUint8(index),
    g: data.getUint8(index + 1),
    b: data.getUint8(index + 2),
    a: data.getUint8(index + 3),
  );
}

TowerComponent _deployedChibi(
  Character character,
  Sprite chibi, {
  double radius = 15,
}) {
  return TowerComponent(
    tower: PlacedTower(
      id: 1,
      character: character,
      position: const GridPosition(1, 1),
    ),
    center: Vector2(radius, radius),
    resolveStats: (tower) =>
        GameBalance.towerStats(tower.type, level: tower.level),
    acquireTarget: (_) => null,
    launchProjectile: (_, _) {},
    chibiSprite: chibi,
    radius: radius,
  );
}

/// The first fully opaque pixel in the vertical band under the socket —
/// where the rank-colored deployment ring's bottom edge is stroked. The
/// translucent platform glow (alpha < 1) and the transparent corners of
/// the chibi are skipped by the alpha check.
({int r, int g, int b, int a}) _ringEdgePixel(ByteData data, double radius) {
  for (var y = (radius * 1.2).round(); y < (radius * 1.9).round(); y++) {
    final pixel = _pixelAt(data, radius.round(), y);
    if (pixel.a > 220) {
      return pixel;
    }
  }
  throw StateError('no ring edge pixel found under the socket');
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
            character: Character.haruto,
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

        final data = await _renderPixels(tower);

        final x = (radius + radius * 1.9).round();
        final index = (radius.round() * 100 + x) * 4;
        expect(data.getUint8(index + 3), greaterThan(0));
      },
    );
  });

  group('TowerComponent chibi deployment (HPA-922)', () {
    test(
      'renders the full-body chibi standing on the rank ring, not a socket fill',
      () async {
        const radius = 15.0;
        final chibi = Sprite(await _solidImage(512, 512, 0xFFCC2200));
        final tower = _deployedChibi(Character.hikari, chibi, radius: radius);

        final data = await _renderPixels(tower);

        // The sprite is anchored bottom-center on the ring, so its body
        // fills the canvas well above the socket edge.
        final body = _pixelAt(data, radius.round(), 3);
        expect(
          body.a,
          greaterThan(200),
          reason: 'chibi must draw above the ring',
        );
        expect(body.r, greaterThan(150));
        expect(
          body.g,
          lessThan(80),
          reason: 'the chibi art must be drawn, not the socket paint',
        );

        // The ring's bottom edge is stroked in the member's rank color —
        // S rank is the command gold, not the legacy type palette.
        final ring = _ringEdgePixel(data, radius);
        expect(ring.r, greaterThan(200), reason: 'S-rank ring must be gold');
        expect(ring.g, greaterThan(160));
        expect(ring.b, lessThan(140));
      },
    );

    test(
      'rank rings match the roster palette, including same-style members',
      () async {
        const radius = 15.0;
        final transparentChibi = Sprite(await _solidImage(1, 1, 0x00000000));
        for (final character in [
          Character.hikari,
          Character.akane,
          Character.elena,
          Character.rin,
          Character.sayo,
          Character.haruto,
        ]) {
          final tower = _deployedChibi(
            character,
            transparentChibi,
            radius: radius,
          );
          final pixel = _ringEdgePixel(await _renderPixels(tower), radius);
          final expected = character.rank.orionColor(OrionUiTheme.dark);
          final reason = '${character.rank.label}-rank ring must match Camp';
          expect(pixel.r, closeTo(expected.r * 255, 3), reason: reason);
          expect(pixel.g, closeTo(expected.g * 255, 3), reason: reason);
          expect(pixel.b, closeTo(expected.b * 255, 3), reason: reason);
        }
      },
    );

    test(
      'a member without a preloaded chibi keeps the legacy socket rendering',
      () async {
        final spriteSheet = GameSpriteSheet.fromImage(
          await _solidImage(1024, 768),
        );
        const radius = 15.0;
        final tower = TowerComponent(
          tower: const PlacedTower(
            id: 1,
            character: Character.haruto,
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

        final data = await _renderPixels(tower);
        final x = (radius + radius * 1.9).round();
        final index = (radius.round() * 100 + x) * 4;
        expect(data.getUint8(index + 3), greaterThan(0));
      },
    );
  });
}
