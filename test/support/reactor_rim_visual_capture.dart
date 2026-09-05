import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Deterministic fixture capture for Reactor Rim scene parity evidence.
///
/// The caller wraps the representative scene in a named `RepaintBoundary`
/// and passes its [GlobalKey] here. When `ORION_CAPTURE_DIR` is unset the
/// helper is a no-op, so ordinary test runs stay side-effect free; when set,
/// the boundary is rasterized at `pixelRatio: 1`, encoded as PNG, and written
/// to `<ORION_CAPTURE_DIR>/<fileName>` (directory created as needed).
///
/// No pixel-comparison assertion and no golden dependency: the captured file
/// is evidence for human review, not a test oracle.
Future<void> captureReactorRimFixture(
  GlobalKey boundaryKey,
  String fileName,
) async {
  final dirPath = Platform.environment['ORION_CAPTURE_DIR'];
  if (dirPath == null || dirPath.isEmpty) {
    return;
  }

  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError(
      'RepaintBoundary for "$fileName" not found or not mounted; wrap the '
      'scene in a keyed RepaintBoundary and pump before capturing.',
    );
  }

  final image = await renderObject.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('Failed to encode fixture "$fileName" as PNG.');
  }

  final directory = Directory(dirPath);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File(
    '${directory.path}/$fileName',
  ).writeAsBytesSync(byteData.buffer.asUint8List());
}
