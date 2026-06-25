import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Bakes a radial vignette into [imageBytes] on the current isolate.
///
/// Used directly on web (no [ImageWorker] job queue) and from the worker on
/// native platforms.
Future<Uint8List?> bakeVignetteIntoBytes(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,
  int? colorHex,
}) async {
  final bytes = _copyBytesIfNeeded(imageBytes);

  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('[VIGNETTE] Failed to decode image.');
  }
  if (decoded.numChannels != 4) {
    decoded = decoded.convert(numChannels: 4);
  }

  final w = decoded.width;
  final h = decoded.height;
  final cx = w / 2.0;
  final cy = h / 2.0;
  final maxDist = math.sqrt(cx * cx + cy * cy);
  final t = radius.clamp(0.0, 1.0);

  const aspectBlend = 0.5;
  final aspect = cx / cy;
  final landscapeDelta = aspect > 1.0 ? (aspect - 1.0) : 0.0;
  final landscapeScale = landscapeDelta * aspectBlend;
  final aspectScale = 1.0 + landscapeScale;
  const baseOffsetMin = 0.03;
  const baseOffsetRange = 0.07;
  final baseOffset = baseOffsetMin + baseOffsetRange * t;
  const smallRadiusLandscapeBoostMax = 0.06;
  final smallRadiusLandscapeBoost = landscapeScale > 0
      ? smallRadiusLandscapeBoostMax * (1.0 - t) * landscapeScale
      : 0.0;

  final inner = 0.15 + 0.6 * (t * aspectScale) + baseOffset + smallRadiusLandscapeBoost;
  final soft = (0.05 + 0.35 * feather.clamp(0.0, 1.0)).clamp(0.01, 1.0);
  final i = intensity.clamp(0.0, 1.0);
  final rgb = colorHex ?? 0x000000;
  final cr = (rgb >> 16) & 0xFF;
  final cg = (rgb >> 8) & 0xFF;
  final cb = rgb & 0xFF;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - cx) / maxDist;
      final dy = (y - cy) / maxDist;
      final d = math.sqrt(dx * dx + dy * dy);
      double factor = 0.0;
      if (d > inner) factor = (((d - inner) / soft).clamp(0.0, 1.0)) * i;
      final pixel = decoded.getPixel(x, y);
      final r = (pixel.r.toDouble() * (1 - factor) + cr.toDouble() * factor).round().clamp(0, 255);
      final g = (pixel.g.toDouble() * (1 - factor) + cg.toDouble() * factor).round().clamp(0, 255);
      final b = (pixel.b.toDouble() * (1 - factor) + cb.toDouble() * factor).round().clamp(0, 255);
      final a = pixel.a.toInt().clamp(0, 255);
      decoded.setPixel(x, y, img.ColorRgba8(r, g, b, a));
    }
  }

  return _encodeLikeInput(decoded, bytes);
}

/// Ensures a contiguous [Uint8List] (web captures may use typed-array views).
Uint8List _copyBytesIfNeeded(Uint8List bytes) {
  if (bytes.offsetInBytes == 0 && bytes.lengthInBytes == bytes.buffer.lengthInBytes) {
    return bytes;
  }
  return Uint8List.fromList(bytes);
}

Uint8List _encodeLikeInput(img.Image image, Uint8List sourceBytes) {
  return Uint8List.fromList(_isJpeg(sourceBytes) ? img.encodeJpg(image) : img.encodePng(image));
}

bool _isJpeg(Uint8List bytes) {
  return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
}
