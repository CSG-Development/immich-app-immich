import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
import 'package:image_editor/src/features/vignette_editor/utils/vignette_bake_impl.dart';

/// Bakes a radial vignette effect into image bytes.
///
/// On web, baking runs synchronously on the main isolate via [bakeVignetteIntoBytes]
/// (Flutter web cannot use the [ImageWorker] job cast path reliably).
/// On native, work is delegated to [ImageWorker] in a background isolate.
Future<Uint8List?> bakeVignette(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,
  int? colorHex,
}) async {
  if (kIsWeb) {
    return bakeVignetteOnWeb(
      imageBytes,
      intensity: intensity,
      radius: radius,
      feather: feather,
      colorHex: colorHex,
    );
  }
  return ImageWorker.instance.vignetteBake(
    imageBytes,
    intensity: intensity,
    radius: radius,
    feather: feather,
    colorHex: colorHex,
  );
}

/// Web-specific vignette save: bake on the main isolate without [ImageWorker].
Future<Uint8List?> bakeVignetteOnWeb(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,
  int? colorHex,
}) async {
  try {
    return await bakeVignetteIntoBytes(
      imageBytes,
      intensity: intensity,
      radius: radius,
      feather: feather,
      colorHex: colorHex,
    );
  } catch (_) {
    return null;
  }
}

/// Runs [bakeVignette] (isolate-backed on native, main-isolate on web).
Future<Uint8List?> bakeVignetteAsync(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,
  int? colorHex,
}) async {
  return bakeVignette(
    imageBytes,
    intensity: intensity,
    radius: radius,
    feather: feather,
    colorHex: colorHex,
  );
}
