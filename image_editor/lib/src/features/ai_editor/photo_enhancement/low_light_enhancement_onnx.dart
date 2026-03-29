import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_session_lifecycle.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

/// Small image-to-image ONNX wrapper used for optional relight balance stage.
class LowLightEnhancementOnnx {
  LowLightEnhancementOnnx({
    required this.modelPathOrUrl,
    this.imageInputName,
    this.outputName,
    this.inputSize = 256,
  });

  final String modelPathOrUrl;
  final String? imageInputName;
  final String? outputName;
  final int inputSize;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;
  bool _didRetrySessionInit = false;
  static final Logger _log = Logger('LowLightEnhancementOnnx');

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
      _log.severe('[LOW_LIGHT_ONNX] Failed to create ONNX session', e, st);
      _session = null;
      if (!_didRetrySessionInit && OnnxModelLoader.isRemoteUrl(modelPathOrUrl)) {
        _didRetrySessionInit = true;
        try {
          await OnnxModelLoader.clearCached(modelPathOrUrl);
          await _ensureSession();
          return;
        } catch (retryError, retryStack) {
          _log.severe('[LOW_LIGHT_ONNX] Retry after cache clear failed', retryError, retryStack);
        }
      }
    } finally {
      options.release();
    }
  }

  Future<Uint8List> enhance(Uint8List imageBytes) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return imageBytes;
      final rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
      final resized = img.copyResize(
        rgb,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.linear,
      );
      final inputData = _toNchw01(resized);

      await _ensureSession();
      final session = _session;
      if (session == null) return imageBytes;

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputData,
        <int>[1, 3, inputSize, inputSize],
      );
      final inName = imageInputName ?? (session.inputNames.isNotEmpty ? session.inputNames.first : null);
      final outName = outputName ?? (session.outputNames.isNotEmpty ? session.outputNames.first : null);
      if (inName == null || outName == null) {
        inputTensor.release();
        return imageBytes;
      }

      final runOptions = OrtRunOptions();
      final inputs = <String, OrtValue>{inName: inputTensor};
      List<OrtValue?>? outputs;
      try {
        final isolateSession = _isolateSession;
        outputs = isolateSession != null
            ? await isolateSession.run(runOptions, inputs, <String>[outName])
            : await session.runAsync(runOptions, inputs, <String>[outName]);

        final outputTensor = outputs?.first;
        if (outputTensor == null) return imageBytes;

        final flat = <dynamic>[];
        final shape = _inferShapeAndFlatten(outputTensor.value, flat);
        if (shape.length != 4) return imageBytes;

        final isNchw = shape[1] == 3;
        final outH = isNchw ? shape[2] : shape[1];
        final outW = isNchw ? shape[3] : shape[2];
        final out = isNchw ? _fromNchw01(flat, outW, outH) : _fromNhwc01(flat, outW, outH);
        final restored = img.copyResize(
          out,
          width: decoded.width,
          height: decoded.height,
          interpolation: img.Interpolation.linear,
        );
        return Uint8List.fromList(decoded.hasAlpha ? img.encodePng(restored) : img.encodeJpg(restored, quality: 92));
      } finally {
        outputs?.forEach((v) => v?.release());
        inputTensor.release();
        runOptions.release();
      }
    } catch (e, st) {
      _log.severe('[LOW_LIGHT_ONNX] Exception during enhance()', e, st);
      return imageBytes;
    } finally {
      await OnnxSessionLifecycle.maybeUnloadAfterRun(
        logger: _log,
        tag: 'LOW_LIGHT_ONNX',
        dispose: dispose,
      );
    }
  }

  Float32List _toNchw01(img.Image image) {
    final pixelCount = image.width * image.height;
    final out = Float32List(3 * pixelCount);
    var idx = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        out[idx] = p.r / 255.0;
        out[pixelCount + idx] = p.g / 255.0;
        out[2 * pixelCount + idx] = p.b / 255.0;
        idx++;
      }
    }
    return out;
  }

  img.Image _fromNchw01(List<dynamic> data, int width, int height) {
    final out = img.Image(width: width, height: height);
    final pixelCount = width * height;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        final r = ((data[idx] as num).toDouble().clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        final g = ((data[pixelCount + idx] as num).toDouble().clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        final b = ((data[2 * pixelCount + idx] as num).toDouble().clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    return out;
  }

  img.Image _fromNhwc01(List<dynamic> data, int width, int height) {
    final out = img.Image(width: width, height: height);
    var idx = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final r = ((data[idx++] as num).toDouble().clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        final g = ((data[idx++] as num).toDouble().clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        final b = ((data[idx++] as num).toDouble().clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    return out;
  }

  List<int> _inferShapeAndFlatten(dynamic value, List<dynamic> out) {
    if (value is List) {
      if (value.isEmpty) return <int>[0];
      final first = value.first;
      final child = _inferShapeAndFlatten(first, out);
      for (var i = 1; i < value.length; i++) {
        _inferShapeAndFlatten(value[i], out);
      }
      return <int>[value.length, ...child];
    }
    out.add(value);
    return const <int>[];
  }

  Future<void> dispose() async {
    await _isolateSession?.release();
    _session?.release();
    _session = null;
    _isolateSession = null;
  }
}
