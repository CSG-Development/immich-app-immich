import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_session_lifecycle.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

final Logger _log = Logger('GpenFaceRestorationOnnx');

/// GPEN-BFR ONNX wrapper.
///
/// Typical GPEN-BFR-256 usage:
/// - input: 1x3x256x256 RGB float in [-1, 1]
/// - output: 1x3x256x256 RGB float in [-1, 1] (some exports use [0,1] / [0,255])
///
/// This wrapper applies the model to the full frame (not per-face crops) as a
/// lightweight optional restoration stage in the enhancement pipeline.
class GpenFaceRestorationOnnx {
  GpenFaceRestorationOnnx({
    required this.modelPathOrUrl,
    this.inputSize = 256,
    this.blendStrength = 0.72,
    this.maskBlurRadius = 5,
    this.imageInputName,
    this.outputName,
  });

  final String modelPathOrUrl;
  final int inputSize;
  final double blendStrength;
  final int maskBlurRadius;
  final String? imageInputName;
  final String? outputName;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;
  bool _didRetrySessionInit = false;

  Future<void> _ensureSession() async {
    if (_session != null) return;
    final options = OrtSessionOptions();
    try {
      OrtEnv.instance.init();
      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _didRetrySessionInit = false;
    } catch (e, st) {
      _log.severe('[GPEN] Failed to create ONNX session', e, st);
      _session = null;
      if (!_didRetrySessionInit && OnnxModelLoader.isRemoteUrl(modelPathOrUrl)) {
        _didRetrySessionInit = true;
        try {
          await OnnxModelLoader.clearCached(modelPathOrUrl);
          await _ensureSession();
          return;
        } catch (retryError, retryStack) {
          _log.severe('[GPEN] Retry after cache clear failed', retryError, retryStack);
        }
      }
    } finally {
      options.release();
    }
  }

  Future<Uint8List> restore(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;
    final rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
    final modelInput = img.copyResize(
      rgb,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final tensor = _encodeImageToNchwMinusOneToOne(modelInput);
    try {
      await _ensureSession();
      final session = _session;
      if (session == null) return imageBytes;

      final inputTensor = OrtValueTensor.createTensorWithDataList(tensor, <int>[1, 3, inputSize, inputSize]);
      final inputNames = session.inputNames;
      final outputNames = session.outputNames;
      final resolvedInput = imageInputName ?? (inputNames.isNotEmpty ? inputNames.first : null);
      final resolvedOutput = outputName ?? (outputNames.isNotEmpty ? outputNames.first : null);
      if (resolvedInput == null || resolvedOutput == null) {
        inputTensor.release();
        return imageBytes;
      }

      final runOptions = OrtRunOptions();
      List<OrtValue?>? outputs;
      try {
        final inputs = <String, OrtValue>{resolvedInput: inputTensor};
        final isolateSession = _isolateSession;
        outputs = isolateSession != null
            ? await isolateSession.run(runOptions, inputs, <String>[resolvedOutput])
            : await session.runAsync(runOptions, inputs, <String>[resolvedOutput]);
        final outputTensor = outputs?.first;
        if (outputTensor == null) return imageBytes;

        final flat = <dynamic>[];
        final shape = _inferShapeAndFlatten(outputTensor.value, flat);
        if (shape.length != 4) return imageBytes;
        final isNchw = shape[1] == 3;
        final outH = isNchw ? shape[2] : shape[1];
        final outW = isNchw ? shape[3] : shape[2];
        final restoredSmall = isNchw
            ? _floatNchwToImage(flat, outW, outH)
            : _floatNhwcToImage(flat, outW, outH);

        final restored = img.copyResize(
          restoredSmall,
          width: rgb.width,
          height: rgb.height,
          interpolation: img.Interpolation.linear,
        );
        final blended = _softBlendWithFeatherMask(
          original: rgb,
          restored: restored,
          strength: blendStrength,
          blurRadius: maskBlurRadius,
        );
        return Uint8List.fromList(_isJpeg(imageBytes) ? img.encodeJpg(blended) : img.encodePng(blended));
      } finally {
        outputs?.forEach((t) => t?.release());
        inputTensor.release();
        runOptions.release();
      }
    } catch (e, st) {
      _log.warning('[GPEN] Face restoration failed', e, st);
      return imageBytes;
    } finally {
      await OnnxSessionLifecycle.maybeUnloadAfterRun(logger: _log, tag: 'GPEN', dispose: dispose);
    }
  }

  Future<void> dispose() async {
    await _isolateSession?.release();
    _session?.release();
    _session = null;
    _isolateSession = null;
  }
}

Float32List _encodeImageToNchwMinusOneToOne(img.Image image) {
  final w = image.width;
  final h = image.height;
  final pixelCount = w * h;
  final data = Float32List(3 * pixelCount);
  var idx = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      final r01 = p.r / 255.0;
      final g01 = p.g / 255.0;
      final b01 = p.b / 255.0;
      data[idx] = (r01 - 0.5) / 0.5;
      data[pixelCount + idx] = (g01 - 0.5) / 0.5;
      data[2 * pixelCount + idx] = (b01 - 0.5) / 0.5;
      idx++;
    }
  }
  return data;
}

img.Image _floatNchwToImage(List<dynamic> raw, int w, int h) {
  final pixelCount = w * h;
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = y * w + x;
      final r = _outputToByte((raw[idx] as num).toDouble());
      final g = _outputToByte((raw[pixelCount + idx] as num).toDouble());
      final b = _outputToByte((raw[2 * pixelCount + idx] as num).toDouble());
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}

img.Image _floatNhwcToImage(List<dynamic> raw, int w, int h) {
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final base = (y * w + x) * 3;
      final r = _outputToByte((raw[base] as num).toDouble());
      final g = _outputToByte((raw[base + 1] as num).toDouble());
      final b = _outputToByte((raw[base + 2] as num).toDouble());
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}

int _outputToByte(double v) {
  if (!v.isFinite) return 0;
  if (v >= -1.2 && v <= 1.2) {
    return (((v + 1.0) * 127.5).round()).clamp(0, 255);
  }
  if (v >= -0.2 && v <= 1.2) {
    return (v * 255).round().clamp(0, 255);
  }
  return v.round().clamp(0, 255);
}

List<int> _inferShapeAndFlatten(dynamic value, List<dynamic> out) {
  List<int> shapeOf(dynamic v) {
    if (v is List && v.isNotEmpty) return <int>[v.length, ...shapeOf(v.first)];
    if (v is List && v.isEmpty) return <int>[0];
    return const <int>[];
  }

  void flatten(dynamic v) {
    if (v is List) {
      for (final e in v) {
        flatten(e);
      }
      return;
    }
    out.add(v);
  }

  final shape = shapeOf(value);
  flatten(value);
  return shape;
}

bool _isJpeg(Uint8List bytes) {
  return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
}

img.Image _softBlendWithFeatherMask({
  required img.Image original,
  required img.Image restored,
  required double strength,
  required int blurRadius,
}) {
  if (original.width != restored.width || original.height != restored.height) {
    return restored;
  }
  final safeStrength = strength.clamp(0.0, 1.0);
  if (safeStrength < 0.01) {
    return original.clone();
  }

  final mask = img.Image(width: original.width, height: original.height);
  for (var y = 0; y < original.height; y++) {
    for (var x = 0; x < original.width; x++) {
      final src = original.getPixel(x, y);
      final out = restored.getPixel(x, y);
      final dr = (out.r - src.r).abs() / 255.0;
      final dg = (out.g - src.g).abs() / 255.0;
      final db = (out.b - src.b).abs() / 255.0;
      final diff = (dr + dg + db) / 3.0;
      const low = 0.02;
      const high = 0.30;
      final w = ((diff - low) / (high - low)).clamp(0.0, 1.0);
      final wb = (w * 255.0).round().clamp(0, 255);
      mask.setPixel(x, y, img.ColorRgb8(wb, wb, wb));
    }
  }

  final feathered = blurRadius > 0 ? img.gaussianBlur(mask, radius: blurRadius.clamp(1, 16)) : mask;
  final blended = original.clone();
  for (var y = 0; y < blended.height; y++) {
    for (var x = 0; x < blended.width; x++) {
      final src = original.getPixel(x, y);
      final out = restored.getPixel(x, y);
      final w = (feathered.getPixel(x, y).r / 255.0) * safeStrength;
      final r = (src.r * (1.0 - w) + out.r * w).round().clamp(0, 255);
      final g = (src.g * (1.0 - w) + out.g * w).round().clamp(0, 255);
      final b = (src.b * (1.0 - w) + out.b * w).round().clamp(0, 255);
      blended.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return blended;
}
