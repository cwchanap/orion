import 'dart:typed_data';
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
          // brightness(.62) saturate(1.1), luma-weighted
          0.668794,
          -0.044341,
          -0.004453,
          0,
          0,
          -0.013206,
          0.637659,
          -0.004453,
          0,
          0,
          -0.013206,
          -0.044341,
          0.677547,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    );

    final centre = destination.center;
    // radial-gradient(75% 60% at 50% 50%, transparent 40%, rgba(3,6,10,.75)
    // 100%): an ellipse whose radii are 75% of the width and 60% of the
    // height, not a circle. The unit-radius gradient is scaled onto it.
    final vignette = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(destination.width * 0.75, destination.height * 0.6, 1, 1);
    canvas.drawRect(
      destination,
      Paint()
        ..shader = Gradient.radial(
          Offset.zero,
          1,
          const <Color>[Color(0x00000000), Color(0xBF03060A)],
          const <double>[0.4, 1],
          TileMode.clamp,
          Float64List.fromList(vignette.storage),
        ),
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
