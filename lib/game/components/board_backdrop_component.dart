import 'dart:ui';

import 'package:flame/components.dart';

/// The board skin, bled across the whole viewport behind the playable grid.
///
/// The grid is square-celled, so on a taller-than-2:3 viewport it is
/// width-limited and centred, leaving vertical slack. Painting the skin only
/// under the grid left that slack as black bands — roughly 15% of the screen
/// at the product viewport — which the mock does not have: its board runs
/// edge to edge with the chrome floating over it.
///
/// This component owns the ground so the fix stays presentational. The grid's
/// `cellSize` is unchanged, and enemy speed, tower range and projectile speed
/// are all absolute game units measured against it.
class BoardBackdropComponent extends PositionComponent {
  BoardBackdropComponent({required this.image, super.size, super.priority});

  /// Null until the skin decodes; the fallback fill covers that frame.
  final Image? image;

  final Paint _fallbackPaint = Paint()..color = const Color(0xFF05080D);

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final destination = Offset.zero & size.toSize();
    final image = this.image;
    if (image == null) {
      canvas.drawRect(destination, _fallbackPaint);
      return;
    }

    canvas.drawImageRect(
      image,
      _coverSource(image),
      destination,
      Paint()
        ..colorFilter = const ColorFilter.matrix([
          1.25,
          0,
          0,
          0,
          0,
          0,
          1.25,
          0,
          0,
          0,
          0,
          0,
          1.25,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    );
  }

  /// The centred crop of [image] that fills [size] without distorting it.
  ///
  /// Cover rather than contain: a contain fit would reintroduce the very
  /// bands this component exists to remove.
  Rect _coverSource(Image image) {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    if (size.x <= 0 || size.y <= 0) {
      return Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    }

    // Take the largest source rect with the destination's aspect ratio.
    final sourceWidth = imageHeight * size.x / size.y;
    if (sourceWidth <= imageWidth) {
      return Rect.fromLTWH(
        (imageWidth - sourceWidth) / 2,
        0,
        sourceWidth,
        imageHeight,
      );
    }
    final sourceHeight = imageWidth * size.y / size.x;
    return Rect.fromLTWH(
      0,
      (imageHeight - sourceHeight) / 2,
      imageWidth,
      sourceHeight,
    );
  }
}
