import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Result of decoding an image in a background isolate.
///
/// All fields are sendable so this can be returned from [compute].
class DecodedImageResult {
  const DecodedImageResult({
    required this.width,
    required this.height,
    required this.numChannels,
    required this.data,
  });

  final int width;
  final int height;
  final int numChannels;
  final Uint8List data;
}

/// Decodes image bytes in a background isolate and returns dimensions only.
///
/// Use when you only need width/height (e.g. overlay layout) to avoid
/// transferring pixel data between isolates.
Future<({int width, int height})?> decodeImageDimensionsInCompute(
  Uint8List bytes,
) async {
  if (kIsWeb) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return (width: decoded.width, height: decoded.height);
  }
  final result = await compute(_decodeImageDimensionsIsolate, bytes);
  return result;
}

/// Decodes image bytes in a background isolate and returns full pixel data.
///
/// Use when you need the decoded [img.Image] for further processing.
/// Reconstruct with [imageFromDecodedResult].
Future<DecodedImageResult?> decodeImageInCompute(Uint8List bytes) async {
  if (kIsWeb) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return DecodedImageResult(
      width: decoded.width,
      height: decoded.height,
      numChannels: decoded.numChannels,
      data: Uint8List.fromList(decoded.getBytes()),
    );
  }
  return compute(_decodeImageFullIsolate, bytes);
}

/// Reconstructs [img.Image] from a [DecodedImageResult].
img.Image imageFromDecodedResult(DecodedImageResult r) {
  return img.Image.fromBytes(
    width: r.width,
    height: r.height,
    bytes: r.data.buffer,
    bytesOffset: r.data.offsetInBytes,
    numChannels: r.numChannels,
  );
}

/// Isolate entry: decode and return dimensions only.
({int width, int height})? _decodeImageDimensionsIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return (width: decoded.width, height: decoded.height);
}

/// Isolate entry: decode and return full pixel data.
DecodedImageResult? _decodeImageFullIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return DecodedImageResult(
    width: decoded.width,
    height: decoded.height,
    numChannels: decoded.numChannels,
    data: Uint8List.fromList(decoded.getBytes()),
  );
}
