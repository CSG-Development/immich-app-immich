import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Bakes a radial vignette effect into image bytes.
///
/// Uses the same formula as [VignetteOverlayPainter]: darkening factor from
/// center (0) to edges (intensity), with [radius] controlling the bright center
/// size and [feather] the softness. Returns PNG/JPEG bytes so the main editor
/// receives an image with the effect applied.
Future<Uint8List?> bakeVignette(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,

  /// Optional RGB color used as the vignette tint.
  ///
  /// If null (or 0), the vignette behaves like the original implementation
  /// and darkens toward pure black.
  int? colorHex,
}) async {
  final decoder = img.findDecoderForData(imageBytes) ?? img.PngDecoder();
  var decoded = decoder.decode(imageBytes);
  if (decoded == null) return null;

  // Ensure RGBA format for correct getPixel/setPixel with ColorRgba8.
  // JPEG and some other formats decode to RGB; pixel ops need consistent format.
  if (decoded.numChannels != 4) {
    decoded = decoded.convert(numChannels: 4);
  }

  final w = decoded.width;
  final h = decoded.height;
  final cx = w / 2.0;
  final cy = h / 2.0;
  final maxDist = math.sqrt(cx * cx + cy * cy);

  // Normalized radius in [0, 1].
  final t = radius.clamp(0.0, 1.0);

  // ----- Aspect-ratio compensation (landscape vs portrait) -----
  //
  // We keep portrait behavior close to the original while slightly
  // increasing the effective radius for landscape images so the baked
  // result better matches the preview.
  const aspectBlend = 0.5; // 0 = no boost, 1 = full aspect ratio
  final aspect = cx / cy; // >1 = landscape, <1 = portrait
  final landscapeDelta = aspect > 1.0 ? (aspect - 1.0) : 0.0;
  final landscapeScale = landscapeDelta * aspectBlend;
  final aspectScale = 1.0 + landscapeScale;

  // ----- Radius-dependent offset compensation -----
  //
  // Base offset works well for portrait and large radii.
  const baseOffsetMin = 0.03;
  const baseOffsetRange = 0.07;
  final baseOffset = baseOffsetMin + baseOffsetRange * t;

  // Extra boost only for landscape, strongest at small t, fading to 0 at t=1.
  const smallRadiusLandscapeBoostMax = 0.06;
  final smallRadiusLandscapeBoost = landscapeScale > 0
      ? smallRadiusLandscapeBoostMax * (1.0 - t) * landscapeScale
      : 0.0;

  final inner = 0.15 + 0.6 * (t * aspectScale) + baseOffset + smallRadiusLandscapeBoost;
  final soft = (0.05 + 0.35 * feather.clamp(0.0, 1.0)).clamp(0.01, 1.0);
  final i = intensity.clamp(0.0, 1.0);

  // Decode the vignette color (RGB). We keep alpha driven purely by the
  // [intensity] factor so behavior stays consistent with the preview painter.
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
      if (d > inner) {
        factor = (((d - inner) / soft).clamp(0.0, 1.0)) * i;
      }

      final pixel = decoded.getPixel(x, y);
      final r = (pixel.r.toDouble() * (1 - factor) + cr.toDouble() * factor).round().clamp(0, 255);
      final g = (pixel.g.toDouble() * (1 - factor) + cg.toDouble() * factor).round().clamp(0, 255);
      final b = (pixel.b.toDouble() * (1 - factor) + cb.toDouble() * factor).round().clamp(0, 255);
      final a = pixel.a.toInt().clamp(0, 255);
      decoded.setPixel(x, y, img.ColorRgba8(r, g, b, a));
    }
  }

  final isJpeg = decoder is img.JpegDecoder;
  return Uint8List.fromList(isJpeg ? img.encodeJpg(decoded) : img.encodePng(decoded));
}

/// Runs [bakeVignette] in a background isolate when supported.
///
/// This keeps the expensive pixel loop off the UI thread on mobile/desktop,
/// while falling back to a direct call on platforms where isolates are not
/// available or are single-threaded (e.g. web).
Future<Uint8List?> bakeVignetteAsync(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,
  int? colorHex,
}) async {
  if (kIsWeb) {
    // Web uses a single JavaScript thread; spawning isolates there does not
    // provide real parallelism and adds overhead, so we run inline instead.
    return bakeVignette(
      imageBytes,
      intensity: intensity,
      radius: radius,
      feather: feather,
      colorHex: colorHex,
    );
  }

  // On native platforms, offload the CPU-heavy work to an isolate.
  return Isolate.run(() {
    return bakeVignette(
      imageBytes,
      intensity: intensity,
      radius: radius,
      feather: feather,
      colorHex: colorHex,
    );
  });
}
