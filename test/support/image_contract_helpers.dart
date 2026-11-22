import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Decodes [file] through the engine's codec and asserts its frame
/// size. [checkPixels] gets the frame's rawRgba bytes (RGBA8, row-major) while
/// the image is still alive; the image and codec are disposed on every path,
/// including a failed assertion.
Future<void> decodePngFrame(
  File file, {
  required int width,
  required int height,
  void Function(ByteData rgba)? checkPixels,
}) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  try {
    final frame = await codec.getNextFrame();
    try {
      final image = frame.image;
      expect(
        (image.width, image.height),
        (width, height),
        reason: '${file.path} must decode to ${width}x$height',
      );
      if (checkPixels != null) {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(rgba, isNotNull, reason: '${file.path} has no rawRgba pixels');
        expect(
          rgba!.lengthInBytes,
          width * height * 4,
          reason: '${file.path} rawRgba must be 4 bytes per pixel',
        );
        checkPixels(rgba);
      }
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Describes the first pixel of [rgba] (RGBA8, row-major, [width] pixels per
/// row) whose alpha is not 255, or returns null when the image is opaque.
String? firstNonOpaquePixel(ByteData rgba, int width) {
  for (var offset = 3; offset < rgba.lengthInBytes; offset += 4) {
    final alpha = rgba.getUint8(offset);
    if (alpha != 255) {
      final pixel = offset ~/ 4;
      return '(${pixel % width}, ${pixel ~/ width}) has alpha $alpha';
    }
  }
  return null;
}

/// Describes the first pixel on the four 1px edges of [rgba] whose alpha is
/// not 0, naming its side, or returns null when the whole frame is transparent.
String? firstVisibleBorderPixel(ByteData rgba, int width, int height) {
  final border = [
    for (var x = 0; x < width; x++) ('top row', x, 0),
    for (var x = 0; x < width; x++) ('bottom row', x, height - 1),
    for (var y = 0; y < height; y++) ('left column', 0, y),
    for (var y = 0; y < height; y++) ('right column', width - 1, y),
  ];
  for (final (side, x, y) in border) {
    final alpha = rgba.getUint8((y * width + x) * 4 + 3);
    if (alpha != 0) return '$side pixel ($x, $y) has alpha $alpha';
  }
  return null;
}

/// Reads the PNG signature and IHDR chunk for width/height/color type.
/// Color type 6 is RGBA.
({int width, int height, int colorType}) pngInfo(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.sublist(0, 8), const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ], reason: '${file.path} must be a PNG file');
  expect(
    String.fromCharCodes(bytes.sublist(12, 16)),
    'IHDR',
    reason: '${file.path} must start with an IHDR chunk',
  );
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    colorType: data.getUint8(25),
  );
}
