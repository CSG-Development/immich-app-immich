import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

final Logger _log = Logger('ModelZooSuperResolutionOnnx');

/// Low-level wrapper for ONNX Model Zoo `super-resolution-10.onnx`.
///
/// This model expects a **single-channel** input of shape [1, 1, 224, 224]
/// and produces a **single-channel** output typically [1, 1, 672, 672].
///
/// We convert the input image to luminance, run SR, then return the upscaled
/// luminance replicated into RGB.
class ModelZooSuperResolutionOnnx {
  ModelZooSuperResolutionOnnx({
    required this.modelPathOrUrl,
    this.imageInputName,
    this.outputName,
    this.inputSize = 224,
    this.maxOutputSide = 4096,
  });

  final String modelPathOrUrl;
  final String? imageInputName;
  final String? outputName;
  final int inputSize;
  final int maxOutputSide;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;

  Future<void> _ensureSession() async {
    if (_session != null) return;
    _log.info('[MZ_SR_ONNX] Creating ONNX session from: $modelPathOrUrl');
    try {
      OrtEnv.instance.init();
      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _log.info('[MZ_SR_ONNX] ONNX isolate session created successfully.');
    } catch (e, st) {
      _log.severe('[MZ_SR_ONNX] Failed to create ONNX session', e, st);
      _session = null;
    }
  }

  /// Runs Model Zoo SR and returns enhanced bytes.
  ///
  /// On any error, returns the original bytes.
  Future<Uint8List> upscale(Uint8List imageBytes) async {
    final totalStart = DateTime.now();
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        return imageBytes;
      }

      final originalW = decoded.width;
      final originalH = decoded.height;
      final rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);

      // Work on a fixed input size, preserving aspect ratio via resize+pad.
      final resized = _resizeAndPadToSquare(rgb, inputSize);

      final input = _encodeLumaToNchw(resized, inputSize);

      await _ensureSession();
      final session = _session;
      if (session == null) return imageBytes;

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        input,
        <int>[1, 1, inputSize, inputSize],
      );

      final resolvedInput = imageInputName ??
          (session.inputNames.isNotEmpty ? session.inputNames.first : null);
      final resolvedOutput = outputName ??
          (session.outputNames.isNotEmpty ? session.outputNames.first : null);

      if (resolvedInput == null || resolvedOutput == null) {
        inputTensor.release();
        return imageBytes;
      }

      final runOptions = OrtRunOptions();
      final isolateSession = _isolateSession;
      final outputs = isolateSession != null
          ? await isolateSession.run(
              runOptions,
              <String, OrtValue>{resolvedInput: inputTensor},
              <String>[resolvedOutput],
            )
          : await session.runAsync(
              runOptions,
              <String, OrtValue>{resolvedInput: inputTensor},
              <String>[resolvedOutput],
            );

      inputTensor.release();
      runOptions.release();

      final outputTensor = outputs?.first;
      if (outputTensor == null) {
        outputs?.forEach((t) => t?.release());
        return imageBytes;
      }

      final raw = outputTensor.value;
      outputs?.forEach((t) => t?.release());

      final flat = <dynamic>[];
      final shape = _inferShapeAndFlatten(raw, flat);
      if (shape.length != 4) return imageBytes;

      // Expect [1, 1, H, W] or [1, H, W, 1].
      final isNchw = shape[1] == 1;
      final outH = isNchw ? shape[2] : shape[1];
      final outW = isNchw ? shape[3] : shape[2];
      if (outW <= 0 || outH <= 0) return imageBytes;

      final srLuma = isNchw
          ? _floatToGrayImageNchw(flat, outW, outH)
          : _floatToGrayImageNhwc(flat, outW, outH);

      // Resize SR result to match original * scale (approx 3x), but clamp.
      final approxScale = math.min(outW / inputSize, outH / inputSize).clamp(1.0, 8.0);
      final desiredW = (originalW * approxScale).round();
      final desiredH = (originalH * approxScale).round();

      final longest = math.max(desiredW, desiredH);
      final scaleDown = longest > maxOutputSide ? maxOutputSide / longest : 1.0;
      final targetW = (desiredW * scaleDown).round().clamp(1, maxOutputSide);
      final targetH = (desiredH * scaleDown).round().clamp(1, maxOutputSide);

      final resizedGray = img.copyResize(
        srLuma,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.linear,
      );

      final outRgb = _grayToRgb(resizedGray);

      final isJpeg = imageBytes.length >= 3 &&
          imageBytes[0] == 0xFF &&
          imageBytes[1] == 0xD8 &&
          imageBytes[2] == 0xFF;
      final encoded = Uint8List.fromList(
        isJpeg ? img.encodeJpg(outRgb) : img.encodePng(outRgb),
      );

      final elapsed = DateTime.now().difference(totalStart).inMilliseconds;
      _log.info('[MZ_SR_ONNX] upscale() total elapsed ${elapsed}ms');
      return encoded;
    } catch (e, st) {
      _log.severe('[MZ_SR_ONNX] Exception during upscale', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {
    await _isolateSession?.release();
    _session?.release();
    _session = null;
    _isolateSession = null;
  }
}

img.Image _resizeAndPadToSquare(img.Image src, int size) {
  final scale = math.min(size / src.width, size / src.height);
  final newW = math.max(1, (src.width * scale).round());
  final newH = math.max(1, (src.height * scale).round());
  final resized = img.copyResize(
    src,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );

  final out = img.Image(width: size, height: size);
  // Fill with black.
  img.fill(out, color: img.ColorRgb8(0, 0, 0));
  final dx = ((size - newW) / 2).round();
  final dy = ((size - newH) / 2).round();
  img.compositeImage(out, resized, dstX: dx, dstY: dy);
  return out;
}

Float32List _encodeLumaToNchw(img.Image rgb, int size) {
  const scale = 1.0 / 255.0;
  final data = Float32List(size * size);
  var idx = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = rgb.getPixel(x, y);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      final yLuma = (0.299 * r + 0.587 * g + 0.114 * b) * scale;
      data[idx++] = yLuma.clamp(0.0, 1.0);
    }
  }
  return data;
}

img.Image _floatToGrayImageNchw(List<dynamic> raw, int w, int h) {
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = y * w + x;
      final v = (raw[idx] as num).toDouble();
      final byte = _srToByte(v);
      out.setPixel(x, y, img.ColorRgb8(byte, byte, byte));
    }
  }
  return out;
}

img.Image _floatToGrayImageNhwc(List<dynamic> raw, int w, int h) {
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = (y * w + x);
      final v = (raw[idx] as num).toDouble();
      final byte = _srToByte(v);
      out.setPixel(x, y, img.ColorRgb8(byte, byte, byte));
    }
  }
  return out;
}

int _srToByte(double v) {
  if (!v.isFinite) return 0;
  if (v > 1.0 || v < 0.0) {
    return v.round().clamp(0, 255);
  }
  return (v * 255).round().clamp(0, 255);
}

img.Image _grayToRgb(img.Image gray) {
  final out = img.Image(width: gray.width, height: gray.height);
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      final v = gray.getPixel(x, y).r.toInt();
      out.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }
  return out;
}

List<int> _inferShapeAndFlatten(dynamic value, List<dynamic> out) {
  List<int> shape0(dynamic v) {
    if (v is List && v.isNotEmpty) {
      return <int>[v.length, ...shape0(v.first)];
    }
    if (v is List && v.isEmpty) {
      return <int>[0];
    }
    return const <int>[];
  }

  void flatten(dynamic v) {
    if (v is List) {
      for (final e in v) {
        flatten(e);
      }
    } else {
      out.add(v);
    }
  }

  final shape = shape0(value);
  flatten(value);
  return shape;
}

