import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/components/board_backdrop_component.dart';

Future<Image> _solidImage(int width, int height, Color color) async {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<List<int>> _rgbaAt(Image image, int x, int y) async {
  final data = await image.toByteData(format: ImageByteFormat.rawRgba);
  final index = (y * image.width + x) * 4;
  return [
    data!.getUint8(index),
    data.getUint8(index + 1),
    data.getUint8(index + 2),
    data.getUint8(index + 3),
  ];
}

Future<Image> _renderBackdrop(Image skin, int width, int height) async {
  final recorder = PictureRecorder();
  final component = BoardBackdropComponent(
    image: skin,
    size: Vector2(width.toDouble(), height.toDouble()),
  );
  component.render(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  group('BoardBackdropComponent board.js field treatment (HPA-699)', () {
    test('dims the skin to the kit brightness, not a lift', () async {
      final skin = await _solidImage(64, 64, const Color(0xFF808080));
      final image = await _renderBackdrop(skin, 128, 128);

      final center = await _rgbaAt(image, 64, 64);
      expect(center[3], 0xFF);
      expect(
        center[0],
        lessThan(0x60),
        reason:
            'brightness(.62) puts a 0x80 source near 0x4F; a lift to '
            '~0xA0 leaves the board fighting the chrome for contrast',
      );
      expect(center[0], greaterThan(0x20));
    });

    test('vignettes the field edges darker than the middle', () async {
      final skin = await _solidImage(64, 64, const Color(0xFF808080));
      final image = await _renderBackdrop(skin, 128, 128);

      final center = await _rgbaAt(image, 64, 64);
      final corner = await _rgbaAt(image, 8, 8);
      expect(
        corner[0],
        lessThan(center[0]),
        reason: 'the kit board falls off toward the edges',
      );
    });

    test('the vignette is the kit ellipse, not a generic round fade', () async {
      final skin = await _solidImage(64, 64, const Color(0xFF808080));
      final image = await _renderBackdrop(skin, 375, 667);

      final center = await _rgbaAt(image, 187, 333);
      expect(
        center[0],
        closeTo(0x4F, 6),
        reason:
            'radial-gradient(75% 60% at 50% 50%, transparent 40%) leaves '
            'the middle untouched by the vignette',
      );

      final midEdge = await _rgbaAt(image, 373, 333);
      expect(
        midEdge[0],
        inInclusiveRange(0x2E, 0x42),
        reason:
            'at the horizontal edge the kit ellipse is mid-ramp '
            '(~u 0.66 -> ~0x36); a circular fade barely darkens there '
            '(~0x4E)',
      );

      final corner = await _rgbaAt(image, 3, 3);
      expect(
        corner[0],
        lessThan(0x20),
        reason:
            'corners sit outside the ellipse and take rgba(3,6,10,.75) '
            'over the dimmed skin (~0x16), not a light haze',
      );
      expect(
        corner[2],
        greaterThan(corner[0]),
        reason:
            'the vignette colour is the near-black blue rgba(3,6,10,.75), '
            'so blue stays above red at the edges',
      );
    });

    test('keeps painting the full-viewport fallback without a skin', () {
      final recorder = PictureRecorder();
      BoardBackdropComponent(
        image: null,
        size: Vector2(200, 200),
      ).render(Canvas(recorder));

      expect(recorder.endRecording(), isNotNull);
    });
  });
}
