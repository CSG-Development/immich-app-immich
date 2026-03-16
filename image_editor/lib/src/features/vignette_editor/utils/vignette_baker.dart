import 'dart:typed_data';

import 'package:image_editor/src/features/services/image_worker.dart';

/// Bakes a radial vignette effect into image bytes.
///
/// Implementation is delegated to the shared [ImageWorker] so that heavy
/// pixel processing can run off the UI isolate on native platforms while
/// remaining safe on web (fallback to main isolate).
Future<Uint8List?> bakeVignette(
  Uint8List imageBytes, {
  required double intensity,
  required double radius,
  required double feather,
  int? colorHex,
}) async {
  return ImageWorker.instance.vignetteBake(
    imageBytes,
    intensity: intensity,
    radius: radius,
    feather: feather,
    colorHex: colorHex,
  );
}

/// Runs [bakeVignette] (decode in compute, pixel loop in isolate on native).
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
